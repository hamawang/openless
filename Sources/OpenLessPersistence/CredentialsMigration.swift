import Foundation

/// 纯函数迁移：v0 扁平字典 → v1 schema。
///
/// 设计原则：
/// - **纯解析 / 翻译**，不做任何磁盘 IO。便于单元测试。
/// - 输入是已经从磁盘读出的原始 bytes / 解析过的字典；输出是判定结果（v1 model + 是否需要备份）。
/// - 检测到 `version` 字段：v1 直接 decode；version > 1 抛 `futureVersion`。
/// - 没有 `version` 字段：当作 v0，按 v0→v1 字段映射规则翻译。
///
/// 字段映射（v0 扁平字典 → v1）：
/// - `volcengine.app_key`     → `providers.asr.volcengine.appKey`
/// - `volcengine.access_key`  → `providers.asr.volcengine.accessKey`
/// - `volcengine.resource_id` → `providers.asr.volcengine.resourceId`
/// - `ark.api_key`            → `providers.llm.ark.apiKey`
/// - `ark.endpoint`           → `providers.llm.ark.baseURL` (空或缺失时回落 default)
/// - `ark.model_id`           → `providers.llm.ark.model`
///
/// 兼容备注：历史上 v0 既出现过点号风格（`volcengine.app_key`），也可能在外部文档里见到下划线风格
/// （`volcengine_app_key`）。这里两种都接受，避免外部转储的文件迁移失败。
public enum CredentialsMigration {
    /// 解析 / 迁移结果。
    public struct Result: Equatable, Sendable {
        public let schema: CredentialsSchemaV1
        /// 是否检测到 v0 数据并完成翻译，调用方需要执行"备份原文件 + 写新 v1 文件"。
        public let needsMigrationFromV0: Bool

        public init(schema: CredentialsSchemaV1, needsMigrationFromV0: Bool) {
            self.schema = schema
            self.needsMigrationFromV0 = needsMigrationFromV0
        }
    }

    /// 主入口：对原始 bytes 做版本嗅探并产出 v1 schema。
    ///
    /// - Throws: `CredentialsError.unparseable(fileURL)` 当 JSON 不能解析；
    ///           `CredentialsError.futureVersion(n)` 当 version > 1。
    public static func parseAndMigrate(rawData: Data, fileURL: URL) throws -> Result {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: rawData, options: [])
        } catch {
            throw CredentialsError.unparseable(fileURL)
        }

        guard let dict = json as? [String: Any] else {
            throw CredentialsError.unparseable(fileURL)
        }

        // 显式版本：直接走对应版本路径。
        if let version = dict["version"] as? Int {
            if version == 1 {
                let schema = try decodeV1(rawData: rawData, fileURL: fileURL)
                return Result(schema: schema, needsMigrationFromV0: false)
            }
            if version > 1 {
                throw CredentialsError.futureVersion(version)
            }
            // version == 0 或负数：当作 v0 处理（极少见，做兜底）。
        }

        // 没有 version 字段（或 version <= 0）：v0 扁平字典 → v1。
        let schema = translateV0Dict(dict)
        return Result(schema: schema, needsMigrationFromV0: true)
    }

    // MARK: - v1 解码

    private static func decodeV1(rawData: Data, fileURL: URL) throws -> CredentialsSchemaV1 {
        do {
            return try JSONDecoder().decode(CredentialsSchemaV1.self, from: rawData)
        } catch {
            throw CredentialsError.unparseable(fileURL)
        }
    }

    // MARK: - v0 → v1 字段翻译

    /// v0 扁平字典翻译成 v1 schema。纯函数，调用方负责处理是否需要备份 / 写盘。
    public static func translateV0Dict(_ dict: [String: Any]) -> CredentialsSchemaV1 {
        let v0 = readV0Fields(dict)

        var providers = CredentialsProviders()

        // Volcengine：任一字段非空才落 provider 节。
        let volcAppKey = nilIfEmpty(v0.volcengineAppKey)
        let volcAccessKey = nilIfEmpty(v0.volcengineAccessKey)
        let volcResourceId = nilIfEmpty(v0.volcengineResourceId)
        if volcAppKey != nil || volcAccessKey != nil || volcResourceId != nil {
            providers.asr[defaultActiveASRProviderId] = CredentialsProviderASRVolcengine(
                appKey: volcAppKey,
                accessKey: volcAccessKey,
                resourceId: volcResourceId
            )
        }

        // Ark：任一字段非空才落 provider 节。endpoint 空或缺失 → 落 default baseURL。
        let arkApiKey = nilIfEmpty(v0.arkApiKey)
        let arkModel = nilIfEmpty(v0.arkModelId)
        let arkEndpointRaw = v0.arkEndpoint
        let arkEndpointTrimmed = arkEndpointRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let arkBaseURL: String? = {
            if let v = arkEndpointTrimmed, !v.isEmpty { return v }
            return defaultArkBaseURL
        }()

        if arkApiKey != nil || arkModel != nil || (arkEndpointTrimmed?.isEmpty == false) {
            providers.llm[defaultActiveLLMProviderId] = CredentialsProviderLLMArk(
                apiKey: arkApiKey,
                baseURL: arkBaseURL,
                model: arkModel
            )
        }

        return CredentialsSchemaV1(
            version: 1,
            providers: providers,
            active: .defaults
        )
    }

    // MARK: - v0 字段读取（容忍点号 / 下划线两种风格）

    /// 读取 v0 扁平字典里的 6 个已知字段。点号 (`volcengine.app_key`) 是实际写盘格式，
    /// 同时接受下划线 (`volcengine_app_key`) 以兼容外部转储的文件。
    private static func readV0Fields(_ dict: [String: Any]) -> V0Fields {
        V0Fields(
            volcengineAppKey: stringValue(dict, keys: ["volcengine.app_key", "volcengine_app_key"]),
            volcengineAccessKey: stringValue(dict, keys: ["volcengine.access_key", "volcengine_access_key"]),
            volcengineResourceId: stringValue(dict, keys: ["volcengine.resource_id", "volcengine_resource_id"]),
            arkApiKey: stringValue(dict, keys: ["ark.api_key", "ark_api_key"]),
            arkModelId: stringValue(dict, keys: ["ark.model_id", "ark_model_id"]),
            arkEndpoint: stringValue(dict, keys: ["ark.endpoint", "ark_endpoint"])
        )
    }

    private struct V0Fields {
        let volcengineAppKey: String?
        let volcengineAccessKey: String?
        let volcengineResourceId: String?
        let arkApiKey: String?
        let arkModelId: String?
        let arkEndpoint: String?
    }

    private static func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let v = dict[k] as? String { return v }
        }
        return nil
    }

    private static func nilIfEmpty(_ s: String?) -> String? {
        guard let s else { return nil }
        return s.isEmpty ? nil : s
    }
}
