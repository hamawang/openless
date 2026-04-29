import Foundation

/// 开发期凭据存储：JSON 文件，路径 `~/.openless/credentials.json`，权限 0600。
///
/// 内部存储为 v1 schema（`CredentialsSchemaV1`）：版本化结构 + provider 分节。
/// 旧的 v0 扁平字典文件首次加载时会被自动迁移：
/// 1. 备份原文件到 `credentials.v0.bak.<timestamp>.json`
/// 2. 翻译 v0 字段 → v1 schema
/// 3. 原子写新 v1 文件（tmp + rename + 0600）
///
/// 公开 API（`get` / `set` / `remove` / `snapshot`）保留与 v0 一致的"扁平账号 key"语义，
/// 内部把 `volcengine.app_key` 这样的 key 路由到 `providers.asr.volcengine.appKey` 字段。
/// 这让 SettingsHubTab / Sidebar 等老调用点不用改字段访问就能继续工作。
///
/// 为什么不用 Keychain：
/// 这个 .app 是 ad-hoc 签名（`codesign --sign -`），Keychain ACL 跟二进制 hash 强绑定。
/// 每次 `swift build` 重建后 hash 都变 → "始终允许"立刻作废 → 6 个账号 6 个弹窗。
/// 而且弹窗在主线程同步阻塞，会卡住录音/识别 hot path。
/// 上线前若需要更强机密性，再切回 Keychain（届时会有稳定的开发者签名）或叠层 AES。
///
/// 当前威胁模型：单用户开发机，0600 权限，只防同账户下的非特权进程。
public final class CredentialsVault: @unchecked Sendable {
    /// 仍保留这个常量，build-app.sh 等地方按 bundle id 引用它。
    public static let serviceName = "com.openless.app"
    public static let shared = CredentialsVault()

    private let directoryURL: URL
    private let fileURL: URL
    private let lock = NSLock()
    private var schema: CredentialsSchemaV1 = .empty
    private var loaded = false
    /// 累积过的非致命加载错误（unparseable / futureVersion 等）。
    /// 调用方可读出来用于 UI 提示；这里**不抛出**，否则 vault 单例初始化路径会全线崩。
    private var lastLoadError: CredentialsError?

    public init(directoryURL: URL? = nil) {
        let dir = directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openless", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.directoryURL = dir
        self.fileURL = dir.appendingPathComponent("credentials.json")
    }

    // MARK: - 公开 API（保持 v0 兼容签名）

    /// 按账号 key 写入凭据。空字符串等价于删除。
    /// 写入后立即落盘（atomic rename + 0600）。
    public func set(_ value: String, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()

        let normalized = value
        if normalized.isEmpty {
            removeAccountLocked(account)
        } else {
            setAccountLocked(account, value: normalized)
        }
        try writeLocked()
    }

    /// 按账号 key 读取凭据。返回 nil 表示未设置 / 空。
    public func get(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return readAccountLocked(account)
    }

    /// 按账号 key 删除凭据；写入失败被吞（这是历史 v0 行为）。
    public func remove(_ account: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        removeAccountLocked(account)
        try? writeLocked()
    }

    /// 一次性把所有账号读出来；调用方在内存里持有，避免每次会话都打 IO。
    public func snapshot() -> CredentialsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        let volc = schema.providers.asr[defaultActiveASRProviderId]
        let ark = schema.providers.llm[defaultActiveLLMProviderId]
        return CredentialsSnapshot(
            volcengineAppKey: volc?.appKey,
            volcengineAccessKey: volc?.accessKey,
            volcengineResourceId: volc?.resourceId,
            arkApiKey: ark?.apiKey,
            arkModelId: ark?.model,
            arkEndpoint: ark?.baseURL
        )
    }

    /// 暴露当前内存中 v1 schema 的副本（值类型，安全）。
    public func currentSchema() -> CredentialsSchemaV1 {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return schema
    }

    /// 最近一次 `loadIfNeeded` 期间累积的非致命错误（如果有）。
    public func loadError() -> CredentialsError? {
        lock.lock()
        defer { lock.unlock() }
        return lastLoadError
    }

    // MARK: - 加载 / 迁移

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true

        // 文件不存在 → 空 v1 schema，不创建文件（首次 set 时再写）。
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            schema = .empty
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // 读取失败：保留 empty schema，不删原文件。
            lastLoadError = .ioError("读取 credentials.json 失败: \(error.localizedDescription)")
            schema = .empty
            return
        }

        let result: CredentialsMigration.Result
        do {
            result = try CredentialsMigration.parseAndMigrate(rawData: data, fileURL: fileURL)
        } catch let credErr as CredentialsError {
            // 解析失败 / 未来版本：原文件不动；schema 保持 empty。
            lastLoadError = credErr
            schema = .empty
            return
        } catch {
            lastLoadError = .ioError(String(describing: error))
            schema = .empty
            return
        }

        schema = result.schema

        // v0 → v1：先备份原文件，再写出新 v1 文件（atomic）。
        if result.needsMigrationFromV0 {
            do {
                try backupV0FileLocked()
                try writeLocked()
            } catch let credErr as CredentialsError {
                lastLoadError = credErr
            } catch {
                lastLoadError = .ioError(String(describing: error))
            }
        }
    }

    /// 把当前 fileURL 处的 v0 文件 move 到 `credentials.v0.bak.<timestamp>[-N].json`。
    /// 时间戳用紧凑 ISO8601（`yyyyMMddTHHmmss`）。冲突时追加 `-1`、`-2` 后缀。
    private func backupV0FileLocked() throws {
        let timestamp = compactISO8601Timestamp(date: Date())
        var target = directoryURL.appendingPathComponent("credentials.v0.bak.\(timestamp).json")
        var suffix = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = directoryURL.appendingPathComponent("credentials.v0.bak.\(timestamp)-\(suffix).json")
            suffix += 1
        }

        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
        } catch {
            throw CredentialsError.backupFailed(target)
        }
    }

    // MARK: - 写入

    /// 原子写：JSON → tmp → fsync → rename → 0600。
    private func writeLocked() throws {
        // 写之前过滤掉空 provider 节，保持 JSON 干净。
        let cleaned = cleanedSchema(schema)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(cleaned)
        } catch {
            throw CredentialsError.writeFailed(fileURL, "JSON 编码失败: \(error.localizedDescription)")
        }

        // 确保目录存在（直接调用 vault 而没经过 init 的边角情况）。
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let tmpURL = directoryURL.appendingPathComponent("credentials.json.tmp")
        // 防止上次写崩留下的残骸。
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }

        // 写 tmp + fsync。
        do {
            try data.write(to: tmpURL, options: [.atomic])
        } catch {
            throw CredentialsError.writeFailed(tmpURL, "写 tmp 文件失败: \(error.localizedDescription)")
        }
        // 显式 fsync 一下，防止 rename 后元数据丢失。
        if let fh = try? FileHandle(forWritingTo: tmpURL) {
            try? fh.synchronize()
            try? fh.close()
        }

        // 原子替换：rename(tmp, target)。如果 target 已存在，replaceItemAt 也能正确处理。
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: fileURL)
            }
        } catch {
            // 失败时清理 tmp，避免残骸误导下一次。
            try? FileManager.default.removeItem(at: tmpURL)
            throw CredentialsError.writeFailed(fileURL, "rename 失败: \(error.localizedDescription)")
        }

        // 设置权限 0600。
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw CredentialsError.writeFailed(fileURL, "设置权限失败: \(error.localizedDescription)")
        }

        // 兜底：万一 replaceItemAt 留下了 tmp（不同 macOS 行为不一致），统一清理。
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    /// 写盘前过滤：移除 isAllEmpty 的 provider 节。
    private func cleanedSchema(_ s: CredentialsSchemaV1) -> CredentialsSchemaV1 {
        var out = s
        out.providers.asr = out.providers.asr.filter { !$0.value.isAllEmpty }
        out.providers.llm = out.providers.llm.filter { !$0.value.isAllEmpty }
        return out
    }

    // MARK: - 账号 key → v1 字段路由

    private func readAccountLocked(_ account: String) -> String? {
        switch account {
        case CredentialAccount.volcengineAppKey:
            return schema.providers.asr[defaultActiveASRProviderId]?.appKey
        case CredentialAccount.volcengineAccessKey:
            return schema.providers.asr[defaultActiveASRProviderId]?.accessKey
        case CredentialAccount.volcengineResourceId:
            return schema.providers.asr[defaultActiveASRProviderId]?.resourceId
        case CredentialAccount.arkApiKey:
            return schema.providers.llm[defaultActiveLLMProviderId]?.apiKey
        case CredentialAccount.arkModelId:
            return schema.providers.llm[defaultActiveLLMProviderId]?.model
        case CredentialAccount.arkEndpoint:
            return schema.providers.llm[defaultActiveLLMProviderId]?.baseURL
        default:
            return nil
        }
    }

    private func setAccountLocked(_ account: String, value: String) {
        switch account {
        case CredentialAccount.volcengineAppKey:
            mutateVolc { $0.appKey = value }
        case CredentialAccount.volcengineAccessKey:
            mutateVolc { $0.accessKey = value }
        case CredentialAccount.volcengineResourceId:
            mutateVolc { $0.resourceId = value }
        case CredentialAccount.arkApiKey:
            mutateArk { $0.apiKey = value }
        case CredentialAccount.arkModelId:
            mutateArk { $0.model = value }
        case CredentialAccount.arkEndpoint:
            mutateArk { $0.baseURL = value }
        default:
            // 未知 account：保持向后兼容，静默忽略。
            break
        }
    }

    private func removeAccountLocked(_ account: String) {
        switch account {
        case CredentialAccount.volcengineAppKey:
            mutateVolc { $0.appKey = nil }
        case CredentialAccount.volcengineAccessKey:
            mutateVolc { $0.accessKey = nil }
        case CredentialAccount.volcengineResourceId:
            mutateVolc { $0.resourceId = nil }
        case CredentialAccount.arkApiKey:
            mutateArk { $0.apiKey = nil }
        case CredentialAccount.arkModelId:
            mutateArk { $0.model = nil }
        case CredentialAccount.arkEndpoint:
            mutateArk { $0.baseURL = nil }
        default:
            break
        }
    }

    private func mutateVolc(_ apply: (inout CredentialsProviderASRVolcengine) -> Void) {
        var existing = schema.providers.asr[defaultActiveASRProviderId] ?? CredentialsProviderASRVolcengine()
        apply(&existing)
        if existing.isAllEmpty {
            schema.providers.asr.removeValue(forKey: defaultActiveASRProviderId)
        } else {
            schema.providers.asr[defaultActiveASRProviderId] = existing
        }
    }

    private func mutateArk(_ apply: (inout CredentialsProviderLLMArk) -> Void) {
        var existing = schema.providers.llm[defaultActiveLLMProviderId] ?? CredentialsProviderLLMArk()
        apply(&existing)
        if existing.isAllEmpty {
            schema.providers.llm.removeValue(forKey: defaultActiveLLMProviderId)
        } else {
            schema.providers.llm[defaultActiveLLMProviderId] = existing
        }
    }
}

// MARK: - 时间戳工具

/// 紧凑 ISO8601 时间戳，例如 `20260429T103045`。固定 UTC，避免 DST。
@inlinable
func compactISO8601Timestamp(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss"
    return formatter.string(from: date)
}

// MARK: - Account constants

public enum CredentialAccount {
    public static let volcengineAppKey = "volcengine.app_key"
    public static let volcengineAccessKey = "volcengine.access_key"
    public static let volcengineResourceId = "volcengine.resource_id"
    public static let arkApiKey = "ark.api_key"
    public static let arkModelId = "ark.model_id"
    public static let arkEndpoint = "ark.endpoint"
}

// MARK: - Snapshot

/// 一次性把所有账号读出来；调用方在内存里持有，避免每次会话都打 IO。
public struct CredentialsSnapshot: Sendable, Equatable {
    public let volcengineAppKey: String?
    public let volcengineAccessKey: String?
    public let volcengineResourceId: String?
    public let arkApiKey: String?
    public let arkModelId: String?
    public let arkEndpoint: String?

    public init(
        volcengineAppKey: String?,
        volcengineAccessKey: String?,
        volcengineResourceId: String?,
        arkApiKey: String?,
        arkModelId: String?,
        arkEndpoint: String?
    ) {
        self.volcengineAppKey = volcengineAppKey
        self.volcengineAccessKey = volcengineAccessKey
        self.volcengineResourceId = volcengineResourceId
        self.arkApiKey = arkApiKey
        self.arkModelId = arkModelId
        self.arkEndpoint = arkEndpoint
    }
}
