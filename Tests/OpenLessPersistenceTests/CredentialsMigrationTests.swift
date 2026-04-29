import XCTest
@testable import OpenLessPersistence

/// 凭据 v0 → v1 迁移与原子写入的集成测试。
///
/// 用例策略：
/// - 每个 case 独立 temp 目录，`addTeardownBlock` 清理。
/// - 直接构造期望的 v0 文件（点号风格 key，与历史磁盘一致）让 vault 加载。
/// - 通过 vault 的 public API（`get` / `set` / `snapshot`) 间接验证迁移结果与 v1 schema。
final class CredentialsMigrationTests: XCTestCase {

    // MARK: - 辅助

    /// 给当前用例分配独立的 temp 目录，并在 teardown 时清理。
    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openless-credtest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    /// 直接写一个 v0 扁平字典文件到指定目录。
    private func writeV0File(_ dict: [String: String], to dir: URL) throws {
        let url = dir.appendingPathComponent("credentials.json")
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: url)
    }

    /// 直接写一个 v1 schema 文件到指定目录。
    private func writeV1File(_ schema: CredentialsSchemaV1, to dir: URL) throws {
        let url = dir.appendingPathComponent("credentials.json")
        let data = try JSONEncoder().encode(schema)
        try data.write(to: url)
    }

    /// 列目录里所有以 `credentials.v0.bak.` 开头的备份文件。
    private func backupFiles(in dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("credentials.v0.bak.") }
    }

    /// 完整 v0 字典（6 个字段都填充）。
    private func fullV0Dict() -> [String: String] {
        [
            "volcengine.app_key": "vk-app",
            "volcengine.access_key": "vk-access",
            "volcengine.resource_id": "vk-resource",
            "ark.api_key": "ark-key",
            "ark.model_id": "ark-model",
            "ark.endpoint": "https://example.test/api/v3"
        ]
    }

    // MARK: - 用例

    func test_freshInstall_noFile_loadsEmptyV1() {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        let snap = vault.snapshot()

        // Assert
        XCTAssertNil(snap.volcengineAppKey)
        XCTAssertNil(snap.arkApiKey)

        // 文件没存在（等到第一次 set 才写）。
        let fileURL = dir.appendingPathComponent("credentials.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func test_v0_full_migratesToV1WithBackup() throws {
        // Arrange
        let dir = makeTempDirectory()
        try writeV0File(fullV0Dict(), to: dir)
        let originalData = try Data(contentsOf: dir.appendingPathComponent("credentials.json"))

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        let snap = vault.snapshot()

        // Assert: v1 字段读取一致
        XCTAssertEqual(snap.volcengineAppKey, "vk-app")
        XCTAssertEqual(snap.volcengineAccessKey, "vk-access")
        XCTAssertEqual(snap.volcengineResourceId, "vk-resource")
        XCTAssertEqual(snap.arkApiKey, "ark-key")
        XCTAssertEqual(snap.arkModelId, "ark-model")
        XCTAssertEqual(snap.arkEndpoint, "https://example.test/api/v3")

        // 当前文件应该是 v1 格式（有 version 字段）
        let mainURL = dir.appendingPathComponent("credentials.json")
        let curData = try Data(contentsOf: mainURL)
        let curJson = try JSONSerialization.jsonObject(with: curData) as? [String: Any]
        XCTAssertEqual(curJson?["version"] as? Int, 1)

        // 备份文件存在，且内容等于原 v0 bytes
        let backups = backupFiles(in: dir)
        XCTAssertEqual(backups.count, 1)
        let backupData = try Data(contentsOf: backups[0])
        XCTAssertEqual(backupData, originalData)
    }

    func test_v0_partialOnlyArk_migrates() throws {
        // Arrange
        let dir = makeTempDirectory()
        try writeV0File([
            "ark.api_key": "ark-key",
            "ark.model_id": "ark-model",
            "ark.endpoint": "https://example.test/api/v3"
        ], to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert: 没有 volcengine 节
        let s = vault.currentSchema()
        XCTAssertNil(s.providers.asr[defaultActiveASRProviderId])
        XCTAssertNotNil(s.providers.llm[defaultActiveLLMProviderId])
        XCTAssertEqual(s.providers.llm[defaultActiveLLMProviderId]?.apiKey, "ark-key")

        // 写盘的 v1 JSON 不应包含 asr.volcengine
        let main = try Data(contentsOf: dir.appendingPathComponent("credentials.json"))
        let json = try JSONSerialization.jsonObject(with: main) as? [String: Any]
        let providers = json?["providers"] as? [String: Any]
        let asr = providers?["asr"] as? [String: Any]
        XCTAssertTrue(asr?.isEmpty ?? true)
    }

    func test_v0_partialOnlyVolcengine_migrates() throws {
        // Arrange
        let dir = makeTempDirectory()
        try writeV0File([
            "volcengine.app_key": "vk-app",
            "volcengine.access_key": "vk-access",
            "volcengine.resource_id": "vk-resource"
        ], to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert
        let s = vault.currentSchema()
        XCTAssertNotNil(s.providers.asr[defaultActiveASRProviderId])
        XCTAssertNil(s.providers.llm[defaultActiveLLMProviderId])
        XCTAssertEqual(s.providers.asr[defaultActiveASRProviderId]?.appKey, "vk-app")

        let main = try Data(contentsOf: dir.appendingPathComponent("credentials.json"))
        let json = try JSONSerialization.jsonObject(with: main) as? [String: Any]
        let providers = json?["providers"] as? [String: Any]
        let llm = providers?["llm"] as? [String: Any]
        XCTAssertTrue(llm?.isEmpty ?? true)
    }

    func test_v0_emptyArkEndpoint_usesDefault() throws {
        // Arrange
        let dir = makeTempDirectory()
        try writeV0File([
            "ark.api_key": "ark-key",
            "ark.model_id": "ark-model",
            "ark.endpoint": ""  // 空字符串
        ], to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert: baseURL 落 default
        XCTAssertEqual(
            vault.snapshot().arkEndpoint,
            defaultArkBaseURL
        )
    }

    func test_v0_emptyArkEndpoint_missing_usesDefault() throws {
        // Arrange
        let dir = makeTempDirectory()
        try writeV0File([
            "ark.api_key": "ark-key",
            "ark.model_id": "ark-model"
            // ark.endpoint 完全不在 dict 里
        ], to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert
        XCTAssertEqual(vault.snapshot().arkEndpoint, defaultArkBaseURL)
    }

    func test_alreadyV1_loadsWithoutMigration() throws {
        // Arrange
        let dir = makeTempDirectory()
        let schema = CredentialsSchemaV1(
            version: 1,
            providers: CredentialsProviders(
                asr: [defaultActiveASRProviderId: CredentialsProviderASRVolcengine(appKey: "vk-app")],
                llm: [defaultActiveLLMProviderId: CredentialsProviderLLMArk(apiKey: "ark-key")]
            ),
            active: .defaults
        )
        try writeV1File(schema, to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert: 字段读取一致
        XCTAssertEqual(vault.snapshot().volcengineAppKey, "vk-app")
        XCTAssertEqual(vault.snapshot().arkApiKey, "ark-key")

        // 没有备份文件
        XCTAssertEqual(backupFiles(in: dir).count, 0)
    }

    func test_futureVersion_throws() throws {
        // Arrange
        let dir = makeTempDirectory()
        let url = dir.appendingPathComponent("credentials.json")
        let payload = ["version": 99] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: url)
        let originalBytes = try Data(contentsOf: url)

        // Act：直接调用 pure migration 函数检查错误类型。
        XCTAssertThrowsError(try CredentialsMigration.parseAndMigrate(rawData: originalBytes, fileURL: url)) { err in
            guard case CredentialsError.futureVersion(let v) = err else {
                XCTFail("应该抛 futureVersion，实际: \(err)")
                return
            }
            XCTAssertEqual(v, 99)
        }

        // Vault 路径下文件不应被修改（snapshot 触发 load）
        let vault = CredentialsVault(directoryURL: dir)
        _ = vault.snapshot()
        let after = try Data(contentsOf: url)
        XCTAssertEqual(after, originalBytes)
        // 也不应有备份
        XCTAssertEqual(backupFiles(in: dir).count, 0)
        // 错误应被记录到 loadError
        if case .futureVersion(let v) = vault.loadError() {
            XCTAssertEqual(v, 99)
        } else {
            XCTFail("应该把 futureVersion 错误存到 loadError")
        }
    }

    func test_damagedJson_throws_fileUntouched() throws {
        // Arrange
        let dir = makeTempDirectory()
        let url = dir.appendingPathComponent("credentials.json")
        let bad = "not-valid-json{".data(using: .utf8)!
        try bad.write(to: url)
        let originalBytes = try Data(contentsOf: url)

        // Act
        XCTAssertThrowsError(try CredentialsMigration.parseAndMigrate(rawData: originalBytes, fileURL: url)) { err in
            guard case CredentialsError.unparseable(let u) = err else {
                XCTFail("应该抛 unparseable，实际: \(err)")
                return
            }
            XCTAssertEqual(u, url)
        }

        // 通过 vault 加载也应保持文件不动
        let vault = CredentialsVault(directoryURL: dir)
        _ = vault.snapshot()
        let after = try Data(contentsOf: url)
        XCTAssertEqual(after, originalBytes)
        XCTAssertEqual(backupFiles(in: dir).count, 0)
        if case .unparseable(let u) = vault.loadError() {
            XCTAssertEqual(u, url)
        } else {
            XCTFail("应该把 unparseable 错误存到 loadError")
        }
    }

    func test_backupConflict_appendsSuffix() throws {
        // Arrange
        let dir = makeTempDirectory()
        try writeV0File(fullV0Dict(), to: dir)

        // 预先放一个会冲突的备份占位文件（覆盖当前可能生成的所有时间戳）。
        // 最稳妥的办法：在迁移之前就把"所有"可能的时间戳备份名都占住。
        // 实际行为：迁移会生成 timestamp 形如 `yyyyMMddTHHmmss`。
        // 我们通过先迁移、抓到生成的备份名，再恢复 v0 文件、占住该名字、重新加载来制造冲突。

        // 第一次迁移：先得到一个真实的备份文件名。
        do {
            let v = CredentialsVault(directoryURL: dir)
            _ = v.snapshot()
        }
        let firstBackups = backupFiles(in: dir)
        XCTAssertEqual(firstBackups.count, 1, "首次迁移应生成 1 个备份")
        let conflictName = firstBackups[0].lastPathComponent

        // 重写 v0 文件 + 让冲突名字占住（不动它），然后清掉之前生成的 v1 main 文件并触发新一轮迁移。
        // 改成：不删除 conflictName，而是再次写入 v0 主文件，重新 init vault。
        // 由于 currentSchema 已经被 vault A 持久化为 v1，需要重置 main 为 v0 才能重新触发迁移。
        try FileManager.default.removeItem(at: dir.appendingPathComponent("credentials.json"))
        try writeV0File(fullV0Dict(), to: dir)

        // Act：再次加载，时间戳同秒会撞 conflictName，应改用 `-1` 后缀。
        // 注意：测试可能跨秒，所以这里还是按"如果新备份文件名等于 conflictName，就要看 -1 文件"的逻辑判断。
        let vault2 = CredentialsVault(directoryURL: dir)
        XCTAssertNotNil(vault2.snapshot().volcengineAppKey)

        let allBackups = backupFiles(in: dir)
        // 至少 2 个备份文件存在（旧的 + 新的）
        XCTAssertGreaterThanOrEqual(allBackups.count, 2)

        // 如果第二次迁移的时间戳跟 conflictName 一样，应该出现 `-1` 后缀
        let suffixed = allBackups.first { $0.lastPathComponent.contains("-1.json") }
        let differentTimestamp = allBackups.first {
            $0.lastPathComponent != conflictName && !$0.lastPathComponent.contains("-1.json")
        }
        XCTAssertTrue(suffixed != nil || differentTimestamp != nil,
                      "应该要么生成 -1 后缀文件，要么时间戳不同")

        // conflict 文件本身不应该被覆盖
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(conflictName).path))
    }

    func test_idempotentSave() throws {
        // Arrange
        let dir = makeTempDirectory()
        let schema = CredentialsSchemaV1(
            version: 1,
            providers: CredentialsProviders(
                asr: [defaultActiveASRProviderId: CredentialsProviderASRVolcengine(
                    appKey: "vk-app", accessKey: "vk-access", resourceId: "vk-resource"
                )],
                llm: [defaultActiveLLMProviderId: CredentialsProviderLLMArk(
                    apiKey: "ark-key", baseURL: defaultArkBaseURL, model: "ark-model"
                )]
            ),
            active: .defaults
        )
        try writeV1File(schema, to: dir)

        // Act：load → save (随便 set 一次再设回原值) → load 再读
        let vault1 = CredentialsVault(directoryURL: dir)
        let s1 = vault1.currentSchema()
        try vault1.set("vk-app", for: CredentialAccount.volcengineAppKey)

        let vault2 = CredentialsVault(directoryURL: dir)
        let s2 = vault2.currentSchema()

        // Assert: schema 完全一致
        XCTAssertEqual(s1, s2)
    }

    func test_atomicWrite_noTempLeftBehind() throws {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        try vault.set("vk-app", for: CredentialAccount.volcengineAppKey)

        // Assert
        let tmp = dir.appendingPathComponent("credentials.json.tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    func test_filePermissions_0600() throws {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        try vault.set("vk-app", for: CredentialAccount.volcengineAppKey)

        // Assert
        let main = dir.appendingPathComponent("credentials.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: main.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    // MARK: - 兼容性补充：snake_case 风格 v0 也能识别（防御性）

    func test_v0_snakeCaseKeys_alsoMigrates() throws {
        // Arrange：用文档里描述的下划线风格 key 写入。
        let dir = makeTempDirectory()
        try writeV0File([
            "volcengine_app_key": "vk-app",
            "volcengine_access_key": "vk-access",
            "volcengine_resource_id": "vk-resource",
            "ark_api_key": "ark-key",
            "ark_model_id": "ark-model",
            "ark_endpoint": "https://example.test/api/v3"
        ], to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert
        XCTAssertEqual(vault.snapshot().volcengineAppKey, "vk-app")
        XCTAssertEqual(vault.snapshot().arkApiKey, "ark-key")
        XCTAssertEqual(vault.snapshot().arkEndpoint, "https://example.test/api/v3")
    }
}
