import Foundation

// ASRProvider 是录音层与具体 ASR 供应商之间的抽象。
//
// 与 LLMProvider 的差异：ASR 有「流式」和「批量」两种交互形态。
//   - 流式（火山 / 阿里 paraformer / Apple Speech）：边录边推 PCM，partial → final
//   - 批量（OpenAI Whisper）：录完整体上传，等几秒拿 final
//
// 我们在 protocol 层一并暴露两种入口；具体 provider 用 `info.mode` 自报家门，
// 调到错误入口时抛 `.unsupportedMode`。这样 coordinator 调用的代码在两种模式下
// 的「形状」是一致的——选择由配置决定，业务流程不分叉。
//
// AudioConsumer 桥接策略：
//   `AudioConsumer.consume(pcmChunk:)` 是同步 + 不抛错的现存协议（OpenLessRecorder /
//   BufferingAudioConsumer 都依赖它）。`ASRStreamingSession` 同时继承 AudioConsumer，
//   provider 自己实现 `consume(pcmChunk:)`（通常委托给内部异步发送任务）。这是最小侵入
//   方案——不改 AudioConsumer，不改任何现有 conformer 的签名。

/// ASR 提供两种交互形态。
public enum ASRMode: String, Codable, Sendable {
    /// 边录边推 PCM，边拿 partial 边等 final。火山 / 阿里 / Apple Speech 都属此类。
    case streaming
    /// 录完整体上传，等几秒拿 final。OpenAI Whisper 属此类。
    case batch
}

/// Provider 元数据：用于 UI 选择列表 + coordinator 路由决策。
public struct ASRProviderInfo: Sendable, Hashable {
    /// 稳定 slug，例如 "volcengine" / "openai-whisper" / "aliyun-paraformer" / "apple-speech"。
    public let providerId: String
    /// 给 UI 显示的中文名，例如「火山引擎」。
    public let displayName: String
    public let mode: ASRMode
    /// 是否支持「真热词」（服务器端生效），不是 prompt 软提示。
    public let supportsHotwords: Bool
    public let supportsLanguageHint: Bool
    /// 流式 provider 是否会推送 partial（增量识别结果）。批量 provider 应为 false。
    public let supportsPartialResults: Bool

    public init(
        providerId: String,
        displayName: String,
        mode: ASRMode,
        supportsHotwords: Bool,
        supportsLanguageHint: Bool,
        supportsPartialResults: Bool
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.mode = mode
        self.supportsHotwords = supportsHotwords
        self.supportsLanguageHint = supportsLanguageHint
        self.supportsPartialResults = supportsPartialResults
    }
}

/// ASR provider 抽象。
///
/// 同一份 protocol 同时承载流式 / 批量两类入口；非自家形态直接抛 `.unsupportedMode`。
public protocol ASRProvider: Sendable {
    var info: ASRProviderInfo { get }

    /// 流式入口：开 session，coordinator 后续把 PCM 推进 session（session 是 AudioConsumer）。
    /// - Parameters:
    ///   - language: BCP-47 语言提示，例如 "zh-CN" / "en-US"。不支持的 provider 可忽略。
    ///   - hotwords: 用户词典中启用的词条；服务器端真热词。
    /// - Throws: 批量 provider 应抛 `ASRError.unsupportedMode`；连接失败抛对应错误。
    func openStreamingSession(language: String, hotwords: [String]) async throws -> ASRStreamingSession

    /// 批量入口：传完整 PCM，返回 final transcript。
    /// - Throws: 流式 provider 应抛 `ASRError.unsupportedMode`。
    func transcribeBatch(
        pcm: Data,
        sampleRate: Int,
        channels: Int,
        language: String,
        hotwords: [String]
    ) async throws -> RawTranscript
}

/// 流式 session 抽象。
///
/// 同时继承 `AudioConsumer`：可以直接 `BufferingAudioConsumer.attach(session)`，
/// recorder 推 PCM → session.consume(pcmChunk:) → provider 内部发送队列。
public protocol ASRStreamingSession: AudioConsumer, Sendable {
    /// 显式异步发送一段 PCM（16 kHz / 16-bit LE / mono）；framing / 编码 / gzip 由 provider 自负。
    /// 默认实现转发到 `AudioConsumer.consume(pcmChunk:)`，供 provider 选择性覆盖。
    func sendAudio(_ pcm: Data) async throws

    /// 用户停止说话，告诉 provider 收尾（不是 cancel）。
    func endStream() async throws

    /// 可选 partial：UI 想显示就订阅，不订阅也不影响 final。批量 / 不支持的 provider 应返回空 stream。
    var partialResults: AsyncStream<String> { get }

    /// 阻塞等 final transcript。`endStream()` 之后调用。
    func awaitFinalResult() async throws -> RawTranscript

    /// 用户按 Esc / 取消。drop 所有内部状态。
    func cancel() async
}

/// `sendAudio(_:)` 的默认实现：直接走 `consume(pcmChunk:)`。Provider 若有更精确的
/// 异步控制（背压 / 错误回流）可自己覆盖。
public extension ASRStreamingSession {
    func sendAudio(_ pcm: Data) async throws {
        consume(pcmChunk: pcm)
    }
}

/// ASR provider 抛出的错误。
///
/// 与 `LLMError` 风格保持一致：URLError 不直接暴露（不 Sendable / 不稳定 Equatable），
/// 网络错误统一用 NSError 包装。
public enum ASRError: Error, Sendable, Equatable {
    /// 凭据缺失（apiKey / appId 等）。
    case missingCredentials
    /// 流式 provider 调批量入口或反之。
    case unsupportedMode
    /// 鉴权失败。`statusCode` 可空——某些协议在 WebSocket 握手后才报错。
    case authFailed(statusCode: Int?)
    /// 配额或限流。
    case quotaExceeded
    /// 输入 PCM 不合法（采样率 / 声道数错等）。
    case invalidAudio(String)
    /// 服务端返回业务错误（带 code + message）。
    case providerError(code: String, message: String)
    /// 操作超时。
    case timeout
    /// 其他网络错误。
    case network(NSError)
    /// 用户主动取消。
    case cancelled
}
