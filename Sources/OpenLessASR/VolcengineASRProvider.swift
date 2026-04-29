import Foundation
import OpenLessCore

// VolcengineASRProvider 把现有的 `VolcengineStreamingASR` 包装成符合
// `ASRProvider` / `ASRStreamingSession` 协议的对象。
//
// 这一层是「纯外包装」——不修改 VolcengineStreamingASR 任何内部逻辑，
// 仅把它的 openSession / consume / sendLastFrame / awaitFinalResult / cancel
// 暴露给 coordinator 通过 protocol 调用。
//
// 现有 `VolcengineStreamingASR` 的几个特性决定了这里的妥协：
//   1. 它在 `init` 时一次性接收 `dictionaryEntries`（即热词），没有运行时换词的接口。
//      所以 hotwords 在 openStreamingSession 阶段被构造成 DictionaryEntry，再
//      传进 VolcengineStreamingASR.init —— 我们不动它。
//   2. 它的 `cancel()` 是同步方法；我们在 `ASRStreamingSession.cancel()` 里 await
//      没有意义但符合协议（async 包同步是无害的）。
//   3. 它没有暴露 partial 回调。火山协议本身有增量结果，但旧实现把它们累到
//      `rawText` 里直到拿到 final 才 fire continuation；本次 C-1 不动这个逻辑，
//      `partialResults` 返回空 stream。需要 partial UI 时再回头改 ASR 内部。

public final class VolcengineASRProvider: ASRProvider {
    public let info: ASRProviderInfo
    private let credentials: VolcengineCredentials
    private let logger: (@Sendable (String) -> Void)?

    public init(
        credentials: VolcengineCredentials,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.credentials = credentials
        self.logger = logger
        self.info = ASRProviderInfo(
            providerId: "volcengine",
            displayName: "火山引擎",
            mode: .streaming,
            supportsHotwords: true,
            supportsLanguageHint: false,
            supportsPartialResults: false
        )
    }

    public func openStreamingSession(
        language: String,
        hotwords: [String]
    ) async throws -> ASRStreamingSession {
        // 把 hotwords[String] 适配回 DictionaryEntry（VolcengineStreamingASR 的入参形态）。
        // language 暂不消费——VolcengineStreamingASR 当前没有暴露 language 入参。
        // C-3/C-4 接入多 ASR provider 时再回来扩展。
        let entries = hotwords
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { phrase in
                DictionaryEntry(phrase: phrase)
            }

        let asr = VolcengineStreamingASR(
            credentials: credentials,
            dictionaryEntries: entries,
            logger: logger
        )
        try await asr.openSession()
        return VolcengineStreamingSessionAdapter(asr: asr)
    }

    public func transcribeBatch(
        pcm: Data,
        sampleRate: Int,
        channels: Int,
        language: String,
        hotwords: [String]
    ) async throws -> RawTranscript {
        throw ASRError.unsupportedMode
    }
}

/// 适配 `VolcengineStreamingASR` 到 `ASRStreamingSession`。
///
/// 它本身是 `AudioConsumer`：`consume(pcmChunk:)` 直接转发给底层 ASR 实例。
/// `partialResults` 暂时是个空 stream（在 init 里立即 finish），UI 即便订阅也不会拿到东西。
final class VolcengineStreamingSessionAdapter: ASRStreamingSession, @unchecked Sendable {
    private let asr: VolcengineStreamingASR
    let partialResults: AsyncStream<String>
    private let partialContinuation: AsyncStream<String>.Continuation

    init(asr: VolcengineStreamingASR) {
        self.asr = asr
        var capturedContinuation: AsyncStream<String>.Continuation!
        self.partialResults = AsyncStream<String> { continuation in
            capturedContinuation = continuation
        }
        self.partialContinuation = capturedContinuation
        // 当前 VolcengineStreamingASR 不暴露 partial 回调，立即关掉 stream，避免订阅方挂等。
        // 等火山 partial 真接入时，把这一行删掉，改成 onPartial { text in cont.yield(text) }。
        capturedContinuation.finish()
    }

    // MARK: - AudioConsumer

    func consume(pcmChunk: Data) {
        asr.consume(pcmChunk: pcmChunk)
    }

    // MARK: - ASRStreamingSession

    func sendAudio(_ pcm: Data) async throws {
        asr.consume(pcmChunk: pcm)
    }

    func endStream() async throws {
        try await asr.sendLastFrame()
    }

    func awaitFinalResult() async throws -> RawTranscript {
        return try await asr.awaitFinalResult()
    }

    func cancel() async {
        asr.cancel()
    }
}
