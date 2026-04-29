import AppKit
import Foundation
import OpenLessCore
import OpenLessHotkey
import OpenLessUI
import OpenLessRecorder
import OpenLessASR
import OpenLessPolish
import OpenLessInsertion
import OpenLessPersistence

@MainActor
final class DictationCoordinator {
    private enum SessionPhase {
        case idle
        case starting
        case listening
        case processing
    }

    private let hotkey: HotkeyMonitor
    private let recorder = Recorder()
    private let inserter = TextInserter()
    private let history = HistoryStore()
    private let dictionary = DictionaryStore()
    private let capsule = CapsuleWindowController()
    private let settings = SettingsWindowController()

    weak var menuBar: MenuBarController?

    /// Toggle 状态：idle → 开始；listening → 结束；starting/processing 阶段忽略重复触发。
    private var sessionPhase: SessionPhase = .idle
    /// 当前 ASR session（通过 ASRProvider.openStreamingSession 拿到）。
    /// 抽象化后 coordinator 不再直接持有 VolcengineStreamingASR；具体 provider 由
    /// `makeASRProvider()` 选择，C-3 起会从 vault.activeASRProviderId 路由到不同实现。
    private var asrSession: ASRStreamingSession?
    private var audioConsumer: BufferingAudioConsumer?
    private var sessionStartedAt: Date = Date()
    /// hold 模式下，Esc 取消后下一次 .released 应被忽略（否则会再次触发结束流程）。
    private var suppressNextRelease = false

    /// 启动时一次性读 Keychain 缓存的凭据快照；会话热路径只读这里，
    /// 不再每次都打 SecItemCopyMatching 触发钥匙串弹窗。
    /// 设置页保存后通过 .openLessCredentialsChanged 通知刷新。
    private var credentials: CredentialsSnapshot = CredentialsSnapshot(
        volcengineAppKey: nil,
        volcengineAccessKey: nil,
        volcengineResourceId: nil,
        arkApiKey: nil,
        arkModelId: nil,
        arkEndpoint: nil
    )

    init() {
        self.hotkey = HotkeyMonitor()
    }

    func bootstrap() {
        Log.write("=== OpenLess 启动 ===")
        Log.write("日志: \(Log.fileURL.path)")

        if !AccessibilityPermission.isGranted() {
            Log.write("辅助功能权限未授予；请到「系统设置 → 隐私与安全 → 辅助功能」勾选 OpenLess")
            _ = AccessibilityPermission.request()
        }

        capsule.onCancel = { [weak self] in self?.handleCancel() }
        capsule.onConfirm = { [weak self] in self?.handleToggle() }

        // 启动时集中读一次：rebuild 后这里会触发若干钥匙串弹窗，但用户讲话期间不再弹。
        refreshCredentials()
        observeCredentialsChanged()

        startHotkey()
        observeHotkeyEvents()
        observeBindingChanged()
    }

    private func refreshCredentials() {
        credentials = CredentialsVault.shared.snapshot()
        Log.write("[creds] 凭据快照已刷新（volc=\(credentials.volcengineAppKey?.isEmpty == false), ark=\(credentials.arkApiKey?.isEmpty == false)）")
    }

    private func observeCredentialsChanged() {
        NotificationCenter.default.addObserver(
            forName: .openLessCredentialsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCredentials()
            }
        }
    }

    func openHome() {
        settings.show(tab: .home)
    }

    func openHistory() {
        settings.show(tab: .history)
    }

    func openDictionary() {
        settings.show(tab: .dictionary)
    }

    func openSettings() {
        settings.show(tab: .settings)
    }

    func toggleDictationFromMenu() {
        handleToggle()
    }

    private func startHotkey() {
        let binding = HotkeyBinding(trigger: UserPreferences.shared.hotkeyTrigger)
        do {
            try hotkey.start(binding: binding)
            Log.write("Hotkey 已启动，trigger=\(binding.trigger.displayName)")
        } catch {
            Log.write("Hotkey 启动失败: \(error)")
        }
    }

    private func observeBindingChanged() {
        NotificationCenter.default.addObserver(
            forName: .openLessHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let binding = HotkeyBinding(trigger: UserPreferences.shared.hotkeyTrigger)
                self.hotkey.updateBinding(binding)
                Log.write("Hotkey trigger → \(binding.trigger.displayName)")
            }
        }
    }

    private func observeHotkeyEvents() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.hotkey.events {
                switch event {
                case .pressed:
                    self.handlePressed()
                case .released:
                    self.handleReleased()
                case .cancelled:
                    self.handleCancel()
                }
            }
        }
    }

    // MARK: - Toggle / Hold 状态机

    private func handlePressed() {
        switch UserPreferences.shared.hotkeyMode {
        case .toggle:
            handleToggle()
        case .hold:
            handleHoldStart()
        }
    }

    private func handleReleased() {
        guard UserPreferences.shared.hotkeyMode == .hold else { return }
        if suppressNextRelease {
            suppressNextRelease = false
            return
        }
        switch sessionPhase {
        case .listening:
            sessionPhase = .processing
            Task { await endSession() }
        case .starting:
            // 用户没等到 ASR 连上就松手 — 当作取消，不发送任何已采集音频。
            Log.write("[session] hold: starting 阶段松手，取消")
            handleCancel()
        case .idle, .processing:
            return
        }
    }

    private func handleHoldStart() {
        switch sessionPhase {
        case .idle:
            sessionPhase = .starting
            Task { await beginSession() }
        case .starting, .listening, .processing:
            // hold 模式下重复 .pressed 通常来自系统自动重发；忽略即可。
            return
        }
    }

    private func handleToggle() {
        switch sessionPhase {
        case .idle:
            sessionPhase = .starting
            Task { await beginSession() }
        case .listening:
            sessionPhase = .processing
            Task { await endSession() }
        case .starting:
            Log.write("[session] 正在启动，忽略重复触发")
        case .processing:
            Log.write("[session] 正在思考中，忽略重复提交")
        }
    }

    private func handleCancel() {
        guard sessionPhase == .starting || sessionPhase == .listening else { return }
        Log.write("用户取消")
        sessionPhase = .idle
        if let session = asrSession {
            asrSession = nil
            // session.cancel() 是 async；让它在后台 detach 即可，不阻塞 UI/cancel 路径。
            Task { await session.cancel() }
        }
        recorder.stop()
        audioConsumer?.clear()
        audioConsumer = nil
        // hold 模式：如果用户还按着键，松手时会再来一次 .released —— 屏蔽掉，避免再次触发结束。
        if UserPreferences.shared.hotkeyMode == .hold {
            suppressNextRelease = true
        }
        capsule.update(state: .cancelled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.capsule.update(state: .hidden)
        }
    }

    private func beginSession() async {
        guard sessionPhase == .starting else { return }
        sessionStartedAt = Date()
        capsule.update(state: .listening, level: 0)
        Log.write("[session] 开始")

        let audioConsumer = BufferingAudioConsumer()
        self.audioConsumer = audioConsumer

        do {
            Log.write("[recorder] microphonePermission=\(MicrophonePermission.statusDescription)")
            if !MicrophonePermission.isGranted() {
                NSApp.activate(ignoringOtherApps: true)
            }
            try await recorder.start(
                consumer: audioConsumer,
                levelHandler: { [weak self] level in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.sessionPhase == .starting || self.sessionPhase == .listening else {
                            return
                        }
                        self.capsule.update(state: .listening, level: level)
                    }
                },
                logger: { msg in Log.write(msg) }
            )
            Log.write("[recorder] 麦克风已启动")
        } catch {
            Log.write("[recorder] 启动失败: \(error)")
            await failSession(reason: "录音启动失败")
            return
        }
        guard sessionPhase == .starting else { return }

        guard let provider = makeASRProvider() else {
            Log.write("缺少 ASR 凭据；麦克风已启动，结束后走 mock 模式")
            sessionPhase = .listening
            return
        }

        let dictionaryEntries = dictionary.enabledEntries()
        let hotwords = dictionaryEntries.map(\.trimmedPhrase).filter { !$0.isEmpty }

        do {
            let session = try await provider.openStreamingSession(
                language: "zh-CN",
                hotwords: hotwords
            )
            Log.write("[asr] streaming session opened (provider=\(provider.info.providerId))")
            guard sessionPhase == .starting else {
                await session.cancel()
                return
            }
            self.asrSession = session
            audioConsumer.attach(session)
            Log.write("[asr] 音频已接入 ASR")
            sessionPhase = .listening
        } catch {
            Log.write("[asr] 连接失败: \(error)")
            await failSession(reason: "ASR 连接失败")
            return
        }
    }

    private func endSession() async {
        guard sessionPhase == .processing else { return }
        defer {
            if sessionPhase == .processing {
                sessionPhase = .idle
            }
        }
        // 末尾 padding：用户按下结束的瞬间停止采样会丢掉
        // (1) AVAudioConverter resampler 内部 ~50ms 滤波器尾巴
        // (2) 人脑"预测松手"——最后一两个字的发音常常压在按键时刻之后
        // keep-record 250ms 让这些音频继续进入 recorder → ASR。
        capsule.update(state: .processing)
        try? await Task.sleep(nanoseconds: 250_000_000)
        recorder.stop()
        audioConsumer?.clear()
        audioConsumer = nil
        Log.write("[session] 录音停止（含 250ms 末尾 padding），等待 ASR 终态")

        guard let session = self.asrSession else {
            // mock pipeline：无凭据时给一段提示
            await runMockPipeline()
            return
        }

        do {
            try await session.endStream()
            let raw = try await session.awaitFinalResult()
            Log.write("[asr] final: \(raw.text)")
            self.asrSession = nil
            let trimmed = raw.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Log.write("[asr] 终态文本为空 — 跳过润色与插入")
                await failSession(reason: "没识别到内容")
                return
            }
            await polishAndInsert(
                raw: RawTranscript(text: trimmed, durationMs: raw.durationMs),
                dictionaryEntries: dictionary.enabledEntries()
            )
        } catch {
            Log.write("[asr] final 失败: \(error)")
            self.asrSession = nil
            await failSession(reason: "识别失败")
        }
    }

    /// 润色环节实际发生了什么。决定胶囊提示色调和历史记录的真实 mode。
    private enum PolishOutcome {
        case ok                       // 真润色完成
        case skippedNoCredentials     // 没填 Ark，直接跳过
        case failed(String)           // 调到了，但报错；error 文本仅作日志

        var logTag: String {
            switch self {
            case .ok: return "ok"
            case .skippedNoCredentials: return "skip-no-creds"
            case .failed(let msg): return "failed(\(msg.prefix(120)))"
            }
        }
    }

    private func polishAndInsert(
        raw: RawTranscript,
        originalRawText: String? = nil,
        dictionaryEntries: [DictionaryEntry] = []
    ) async {
        let mode = UserPreferences.shared.polishMode
        let savedRaw = originalRawText ?? raw.text

        // 风格关闭时直接插入原文，不调 Ark。
        guard UserPreferences.shared.polishEnabled else {
            Log.write("[polish] 风格已关闭；跳过润色，插入 raw")
            await insertText(
                text: raw.text,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count,
                polishOutcome: .skippedNoCredentials
            )
            return
        }

        // 走 active LLM provider 通用路径（OpenAICompatibleLLMProvider）。
        // 凭据缺失（apiKey 为空 / config 构造不出来）时静默降级为"插入 raw"，保持
        // "用户的原话不会丢"这条不变量。
        let vault = CredentialsVault.shared
        let activeId = vault.activeLLMProviderId
        guard let cfg = vault.llmProviderConfig(for: activeId),
              !cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.write("[polish] active provider=\(activeId) 缺少 apiKey；跳过润色，插入 raw")
            await insertText(
                text: raw.text,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count,
                polishOutcome: .skippedNoCredentials
            )
            return
        }

        // 词典条目里 enabled 的部分作为 hotwords 喂给 provider；hotwords 仅影响 prompt 后缀，
        // 不影响热路径成本。
        let hotwords = dictionaryEntries.map(\.phrase).filter { !$0.isEmpty }

        Log.write("[polish] provider=\(activeId) baseURL=\(cfg.baseURL.absoluteString) model=\(cfg.model)")
        let provider = OpenAICompatibleLLMProvider(
            config: cfg,
            logger: { msg in Log.write(msg) }
        )
        do {
            let final = try await provider.polish(rawText: raw.text, mode: mode, hotwords: hotwords)
            Log.write("[polish] mode=\(mode.rawValue) → \(final)")
            await insertText(
                text: final,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count,
                polishOutcome: .ok
            )
        } catch {
            Log.write("[polish] 失败: \(error)；插入 raw")
            await insertText(
                text: raw.text,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count,
                polishOutcome: .failed(String(describing: error))
            )
        }
    }

    private func insertText(
        text: String,
        raw: String,
        mode: PolishMode,
        durationMs: Int?,
        dictionaryEntryCount: Int,
        polishOutcome: PolishOutcome = .ok
    ) async {
        let result = await inserter.insert(text)
        let frontApp = NSWorkspace.shared.frontmostApplication
        // 命中次数：润色后的最终文本里出现的启用词条 +1，词汇表里展示用。
        let hits = dictionary.incrementHits(matching: text)
        if !hits.isEmpty {
            Log.write("[dictionary] 命中：\(hits.joined(separator: ", "))")
            NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        }
        // 润色没真跑时，历史里的 mode 应反映「实际只是 raw」，避免误导。
        let savedMode: PolishMode
        switch polishOutcome {
        case .ok: savedMode = mode
        case .skippedNoCredentials, .failed: savedMode = .raw
        }
        switch result {
        case .inserted:
            capsule.update(state: capsuleStateForInsert(polishOutcome))
            Log.write("[insert] OK (polish=\(polishOutcome.logTag))")
            saveSession(
                raw: raw,
                final: text,
                mode: savedMode,
                app: frontApp,
                status: .inserted,
                errorCode: nil,
                durationMs: durationMs,
                dictionaryEntryCount: dictionaryEntryCount
            )
        case .copiedFallback(let reason):
            capsule.update(state: capsuleStateForCopy(polishOutcome))
            Log.write("[insert] fallback: \(reason) (polish=\(polishOutcome.logTag))")
            saveSession(
                raw: raw,
                final: text,
                mode: savedMode,
                app: frontApp,
                status: .copiedFallback,
                errorCode: reason,
                durationMs: durationMs,
                dictionaryEntryCount: dictionaryEntryCount
            )
        }
        // 处理结果留在屏幕上 2.5 秒：
        // - 让用户有时间看到"已复制 ⌘V"提示并手动粘贴
        // - "已插入"也保留较长时间，避免视觉一闪而过
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.capsule.update(state: .hidden)
        }
    }

    private func capsuleStateForInsert(_ outcome: PolishOutcome) -> CapsuleState {
        switch outcome {
        case .ok: return .inserted
        case .skippedNoCredentials: return .warning("已插入原文 · 未润色")
        case .failed: return .warning("润色失败 · 已用原文")
        }
    }

    private func capsuleStateForCopy(_ outcome: PolishOutcome) -> CapsuleState {
        switch outcome {
        case .ok: return .copied
        case .skippedNoCredentials: return .warning("已复制原文 · 未润色 ⌘V")
        case .failed: return .warning("润色失败 · 已复制 ⌘V")
        }
    }

    private func runMockPipeline() async {
        let mockText = "（演示）请到设置 → 凭据填入火山引擎 ASR + Ark API Key 后才能真实识别"
        Log.write("[mock] \(mockText)")
        try? await Task.sleep(nanoseconds: 800_000_000)
        capsule.update(state: .copied)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mockText, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.capsule.update(state: .hidden)
        }
    }

    private func failSession(reason: String) async {
        recorder.stop()
        audioConsumer?.clear()
        audioConsumer = nil
        if let session = asrSession {
            asrSession = nil
            await session.cancel()
        }
        sessionPhase = .idle
        capsule.update(state: .error(reason))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.capsule.update(state: .hidden)
        }
    }

    private func saveSession(
        raw: String,
        final: String,
        mode: PolishMode,
        app: NSRunningApplication?,
        status: InsertStatus,
        errorCode: String?,
        durationMs: Int?,
        dictionaryEntryCount: Int
    ) {
        let session = DictationSession(
            rawTranscript: raw,
            finalText: final,
            mode: mode,
            appBundleId: app?.bundleIdentifier,
            appName: app?.localizedName,
            insertStatus: status,
            errorCode: errorCode,
            durationMs: durationMs,
            dictionaryEntryCount: dictionaryEntryCount
        )
        history.save(session)
        NotificationCenter.default.post(name: .openLessHistoryChanged, object: nil)
    }

    // MARK: - 凭据读取（全部走内存快照，不打 Keychain）

    private func loadVolcengineCredentials() -> VolcengineCredentials? {
        let app = credentials.volcengineAppKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let access = credentials.volcengineAccessKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !app.isEmpty, !access.isEmpty else { return nil }
        let resource = credentials.volcengineResourceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceID = (resource?.isEmpty == false) ? resource! : VolcengineCredentials.defaultResourceId
        return VolcengineCredentials(
            appID: app,
            accessToken: access,
            resourceID: resourceID
        )
    }

    // loadArkCredentials 已移除：润色路径改走 vault.llmProviderConfig(for:) +
    // OpenAICompatibleLLMProvider，不再单独构造 ArkCredentials。

    // MARK: - ASR provider 工厂

    /// 构造当前会话使用的 `ASRProvider`。
    ///
    /// C-1 阶段硬编码到 `VolcengineASRProvider`；C-3（Settings UI）会改成从
    /// `vault.activeASRProviderId` 路由。返回 nil 时 coordinator 走 mock 流程
    /// （沿用旧版「凭据缺失 → 提示性占位」的契约，不向用户报硬错误）。
    private func makeASRProvider() -> ASRProvider? {
        guard let creds = loadVolcengineCredentials() else { return nil }
        return VolcengineASRProvider(
            credentials: creds,
            logger: { msg in Log.write(msg) }
        )
    }
}
