import Foundation

/// 凭据 v1 schema：版本化结构，按 provider 类别（asr / llm）→ providerId → 字段。
///
/// 设计要点：
/// - `providers.asr` / `providers.llm` 用字典（键为 providerId），未来加 provider 不需要再涨版本号。
/// - 每个 provider 子对象内部用 camelCase；所有字段都是 `String?`，缺省即"未设置"。
/// - provider 子对象在没有任何字段时**省略不写**（不输出空对象），保持 JSON 干净。
/// - `active` 必须存在并指向当前选中的 provider。M1 默认 `volcengine` / `ark`。
public struct CredentialsSchemaV1: Codable, Sendable, Equatable {
    public var version: Int
    public var providers: CredentialsProviders
    public var active: CredentialsActiveSelection

    public init(
        version: Int = 1,
        providers: CredentialsProviders = CredentialsProviders(),
        active: CredentialsActiveSelection = .defaults
    ) {
        self.version = version
        self.providers = providers
        self.active = active
    }

    /// 空 schema：无任何 provider 数据，active 用默认值。
    public static var empty: CredentialsSchemaV1 {
        CredentialsSchemaV1()
    }
}

// MARK: - Providers

/// `providers` 节点。M1 类型化为已知的两类（asr / llm），未来扩展时把字典加到这里。
public struct CredentialsProviders: Codable, Sendable, Equatable {
    /// ASR 类别：providerId → provider 配置。M1 仅有 `volcengine`。
    public var asr: [String: CredentialsProviderASRVolcengine]
    /// LLM 类别：providerId → provider 配置。M1 仅有 `ark`。
    public var llm: [String: CredentialsProviderLLMArk]

    public init(
        asr: [String: CredentialsProviderASRVolcengine] = [:],
        llm: [String: CredentialsProviderLLMArk] = [:]
    ) {
        self.asr = asr
        self.llm = llm
    }
}

/// Volcengine streaming ASR 凭据。
///
/// 自定义编码：nil 字段直接省略（不写 `"appKey": null`），保持 JSON 干净。
public struct CredentialsProviderASRVolcengine: Codable, Sendable, Equatable {
    public var appKey: String?
    public var accessKey: String?
    public var resourceId: String?

    public init(appKey: String? = nil, accessKey: String? = nil, resourceId: String? = nil) {
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = resourceId
    }

    /// 是否所有字段都是空 / nil。空 provider 在写盘时不应出现。
    public var isAllEmpty: Bool {
        isNilOrEmpty(appKey) && isNilOrEmpty(accessKey) && isNilOrEmpty(resourceId)
    }

    private enum CodingKeys: String, CodingKey {
        case appKey, accessKey, resourceId
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(appKey, forKey: .appKey)
        try c.encodeIfPresent(accessKey, forKey: .accessKey)
        try c.encodeIfPresent(resourceId, forKey: .resourceId)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appKey = try c.decodeIfPresent(String.self, forKey: .appKey)
        accessKey = try c.decodeIfPresent(String.self, forKey: .accessKey)
        resourceId = try c.decodeIfPresent(String.self, forKey: .resourceId)
    }
}

/// Ark (Doubao) chat-completions 凭据。
///
/// 自定义编码：nil 字段直接省略。
public struct CredentialsProviderLLMArk: Codable, Sendable, Equatable {
    public var apiKey: String?
    public var baseURL: String?
    public var model: String?

    public init(apiKey: String? = nil, baseURL: String? = nil, model: String? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    /// 是否所有字段都是空 / nil。
    public var isAllEmpty: Bool {
        isNilOrEmpty(apiKey) && isNilOrEmpty(baseURL) && isNilOrEmpty(model)
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey, baseURL, model
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(apiKey, forKey: .apiKey)
        try c.encodeIfPresent(baseURL, forKey: .baseURL)
        try c.encodeIfPresent(model, forKey: .model)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }
}

// MARK: - Active selection

/// 当前激活的 provider。M1 默认 `volcengine` / `ark`。
public struct CredentialsActiveSelection: Codable, Sendable, Equatable {
    public var asr: String
    public var llm: String

    public init(asr: String, llm: String) {
        self.asr = asr
        self.llm = llm
    }

    public static var defaults: CredentialsActiveSelection {
        CredentialsActiveSelection(asr: defaultActiveASRProviderId, llm: defaultActiveLLMProviderId)
    }
}

// MARK: - 常量

public let defaultActiveASRProviderId = "volcengine"
public let defaultActiveLLMProviderId = "ark"
public let defaultArkBaseURL = "https://ark.cn-beijing.volces.com/api/v3"

// MARK: - 工具

@inlinable
func isNilOrEmpty(_ s: String?) -> Bool {
    guard let s else { return true }
    return s.isEmpty
}
