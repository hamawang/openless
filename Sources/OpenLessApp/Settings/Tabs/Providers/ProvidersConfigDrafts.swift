import OpenLessASR

struct LLMConfigDraft: Equatable {
    var apiKey: String = ""
    var baseURL: String = ""
    var model: String = ""
    var temperature: Double = 0.3
    /// 自定义 provider 的展示名。预设条目从 registry 兜底，不暴露在 UI 上。
    var displayName: String = ""
}

struct VolcengineDraft: Equatable {
    var appKey: String = ""
    var accessKey: String = ""
    var resourceId: String = VolcengineCredentials.defaultResourceId
}

struct AliyunParaformerDraft: Equatable {
    var apiKey: String = ""
}

struct CustomWhisperDraft: Equatable {
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
}
