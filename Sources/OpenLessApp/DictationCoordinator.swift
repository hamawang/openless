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
    private var asr: VolcengineStreamingASR?
    private var audioConsumer: BufferingAudioConsumer?
    private var sessionStartedAt: Date = Date()

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
                case .toggled:
                    self.handleToggle()
                case .cancelled:
                    self.handleCancel()
                }
            }
        }
    }

    // MARK: - Toggle 状态机

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
        asr?.cancel()
        asr = nil
        recorder.stop()
        audioConsumer?.clear()
        audioConsumer = nil
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

        guard let credentials = loadVolcengineCredentials() else {
            Log.write("缺少火山引擎凭据；麦克风已启动，结束后走 mock 模式")
            sessionPhase = .listening
            return
        }

        let dictionaryEntries = dictionary.enabledEntries()
        let asr = VolcengineStreamingASR(
            credentials: credentials,
            dictionaryEntries: dictionaryEntries,
            logger: { msg in Log.write(msg) }
        )
        self.asr = asr

        do {
            try await asr.openSession()
            Log.write("[asr] WebSocket 已连接")
            guard sessionPhase == .starting else {
                asr.cancel()
                return
            }
            audioConsumer.attach(asr)
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

        guard let asr = self.asr else {
            // mock pipeline：无凭据时给一段提示
            await runMockPipeline()
            return
        }

        do {
            try await asr.sendLastFrame()
            let raw = try await asr.awaitFinalResult()
            Log.write("[asr] final: \(raw.text)")
            self.asr = nil
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
            self.asr = nil
            await failSession(reason: "识别失败")
        }
    }

    private func polishAndInsert(
        raw: RawTranscript,
        originalRawText: String? = nil,
        dictionaryEntries: [DictionaryEntry] = []
    ) async {
        let mode = UserPreferences.shared.polishMode
        let savedRaw = originalRawText ?? raw.text

        guard let arkCreds = loadArkCredentials() else {
            Log.write("缺少 Ark 凭据；直接用 raw 插入")
            await insertText(
                text: raw.text,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count
            )
            return
        }

        Log.write("[polish] 调用 endpoint=\(arkCreds.endpoint.absoluteString) model=\(arkCreds.modelId)")
        let polish = DoubaoPolishClient(
            credentials: arkCreds,
            logger: { msg in Log.write(msg) }
        )
        do {
            let final = try await polish.polish(rawTranscript: raw, mode: mode, dictionaryEntries: dictionaryEntries)
            Log.write("[polish] mode=\(mode.rawValue) → \(final.text)")
            await insertText(
                text: final.text,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count
            )
        } catch {
            Log.write("[polish] 失败: \(error)；fallback 用 raw")
            // 让用户知道润色失败（最常见原因：Ark 模型 ID 写错）。
            // 1.5s 提示后用 raw 兜底插入，避免用户以为是"整理完成"。
            capsule.update(state: .error("整理失败 用原文"))
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await insertText(
                text: raw.text,
                raw: savedRaw,
                mode: mode,
                durationMs: raw.durationMs,
                dictionaryEntryCount: dictionaryEntries.count
            )
        }
    }

    private func insertText(
        text: String,
        raw: String,
        mode: PolishMode,
        durationMs: Int?,
        dictionaryEntryCount: Int
    ) async {
        let result = await inserter.insert(text)
        let frontApp = NSWorkspace.shared.frontmostApplication
        let learned = dictionary.learnTerms(from: text)
        if !learned.isEmpty {
            Log.write("[dictionary] 自动学习：\(learned.map { $0.phrase }.joined(separator: ", "))")
        }
        switch result {
        case .inserted:
            capsule.update(state: .inserted)
            Log.write("[insert] OK")
            saveSession(
                raw: raw,
                final: text,
                mode: mode,
                app: frontApp,
                status: .inserted,
                errorCode: nil,
                durationMs: durationMs,
                dictionaryEntryCount: dictionaryEntryCount
            )
        case .copiedFallback(let reason):
            capsule.update(state: .copied)
            Log.write("[insert] fallback: \(reason)")
            saveSession(
                raw: raw,
                final: text,
                mode: mode,
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
        asr?.cancel()
        asr = nil
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

    private func loadArkCredentials() -> ArkCredentials? {
        guard let key = credentials.arkApiKey, !key.isEmpty else { return nil }
        let model = credentials.arkModelId ?? ArkCredentials.defaultModelId
        let endpointStr = credentials.arkEndpoint ?? ArkCredentials.defaultEndpoint.absoluteString
        let endpoint = URL(string: endpointStr) ?? ArkCredentials.defaultEndpoint
        return ArkCredentials(apiKey: key, modelId: model, endpoint: endpoint)
    }
}
