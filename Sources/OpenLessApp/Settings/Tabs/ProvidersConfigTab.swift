import AppKit
import Foundation
import SwiftUI
import OpenLessCore
import OpenLessASR
import OpenLessPersistence

/// 「配置」Tab：把 LLM 模型与 ASR 语音两类 provider 合并到一页编辑。
///
/// 与拆分前的 LLMProvidersTab / ASRProvidersTab 的关键差异：
/// - 切 chip 不立即写盘，所有改动都先放进内存草稿；底部一个统一「保存」按钮提交。
/// - 当前 active provider 的字段编辑同样进入草稿；用户切回去就回滚。
/// - 火山引擎 3 字段（APP ID / Access Token / Resource ID）从 SettingsHubTab 搬到这里。
///
/// 为什么不用嵌套 TabView：单 ScrollView 把两段（LLM + ASR）摆在同一页，
/// 用户一次能看见全部状态，无需在子 tab 之间反复跳。
@MainActor
struct ProvidersConfigTab: View {
    @StateObject private var model = ProvidersConfigModel()
    @State private var savedFlash = false

    var body: some View {
        SettingsPage(
            title: "配置",
            subtitle: "选择并填写 LLM 模型和语音识别（ASR）凭据。改完后点击底部「保存」生效。"
        ) {
            llmSection
            asrSection
            saveActionRow
        }
        .onAppear { model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessCredentialsChanged)) { _ in
            model.load()
        }
    }

    // MARK: - LLM Section

    private var llmSection: some View {
        GlassSection(title: "LLM 模型", symbol: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 12) {
                LLMProviderChipRow(
                    presets: LLMProviderRegistry.presets,
                    selectedProviderId: model.selectedLLMProviderId,
                    activeProviderId: model.activeLLMProviderId,
                    onSelect: { id in model.selectLLMProvider(id) },
                    onAddCustom: { model.beginAddCustomLLM() }
                )

                Text(llmHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            DividerLine()

            llmForm
        }
    }

    private var llmHint: String {
        if let preset = LLMProviderRegistry.preset(for: model.selectedLLMProviderId) {
            return "\(preset.displayName) · \(preset.defaultBaseURL.absoluteString)"
        }
        return "自定义 OpenAI 兼容 provider · \(model.llmDraft.baseURL.isEmpty ? "请填写 Base URL" : model.llmDraft.baseURL)"
    }

    @ViewBuilder
    private var llmForm: some View {
        let preset = LLMProviderRegistry.preset(for: model.selectedLLMProviderId)
        let isCustom = preset == nil

        SettingsRow(title: "API Key") {
            PasteableCredentialField(
                placeholder: "Bearer Token",
                secure: true,
                text: Binding(
                    get: { model.llmDraft.apiKey },
                    set: { model.updateLLMApiKey($0) }
                )
            )
        }
        DividerLine()

        SettingsRow(title: "Base URL") {
            PasteableCredentialField(
                placeholder: preset?.defaultBaseURL.absoluteString ?? "https://api.example.com/v1",
                secure: false,
                text: Binding(
                    get: { model.llmDraft.baseURL },
                    set: { model.updateLLMBaseURL($0) }
                )
            )
        }
        DividerLine()

        SettingsRow(title: "Model") {
            PasteableCredentialField(
                placeholder: preset?.defaultModel.isEmpty == false ? preset!.defaultModel : "endpoint id / model name",
                secure: false,
                text: Binding(
                    get: { model.llmDraft.model },
                    set: { model.updateLLMModel($0) }
                )
            )
        }
        DividerLine()

        SettingsRow(title: "Temperature") {
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { model.llmDraft.temperature },
                        set: { model.updateLLMTemperature($0) }
                    ),
                    in: 0.0...1.0,
                    step: 0.05
                )
                .frame(width: 220)
                Text(String(format: "%.2f", model.llmDraft.temperature))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }
        }

        if isCustom, !model.selectedLLMProviderId.isEmpty {
            DividerLine()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    model.deleteSelectedLLM()
                } label: {
                    Label("删除此 provider", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedLLMProviderId == model.activeLLMProviderId)
                .help(model.selectedLLMProviderId == model.activeLLMProviderId ? "当前 active provider 不能删除——先切到别的 provider" : "从本机移除该 provider 的所有字段")
            }
        }
    }

    // MARK: - ASR Section

    private var asrSection: some View {
        GlassSection(title: "ASR 语音", symbol: "waveform") {
            VStack(alignment: .leading, spacing: 12) {
                ASRProviderChipRow(
                    presets: ASRProviderRegistry.presets,
                    selectedProviderId: model.selectedASRProviderId,
                    activeProviderId: model.activeASRProviderId,
                    onSelect: { id in model.selectASRProvider(id) }
                )

                Text(asrHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            DividerLine()

            asrForm
        }
    }

    private var asrHint: String {
        ASRProviderRegistry.preset(for: model.selectedASRProviderId)?.helpText
            ?? "未知 ASR provider；请选择左侧任一选项。"
    }

    @ViewBuilder
    private var asrForm: some View {
        switch model.selectedASRProviderId {
        case "volcengine":
            volcengineForm
        case "apple-speech":
            appleSpeechInfo
        case "aliyun-paraformer":
            aliyunParaformerForm
        case "custom-openai-whisper":
            customWhisperForm
        default:
            Text("未知 ASR provider：\(model.selectedASRProviderId)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var volcengineForm: some View {
        Group {
            SettingsRow(title: "APP ID") {
                PasteableCredentialField(
                    placeholder: "X-Api-App-Key",
                    secure: false,
                    text: Binding(
                        get: { model.volcDraft.appKey },
                        set: { model.updateVolcAppKey($0) }
                    )
                )
            }
            DividerLine()
            SettingsRow(title: "Access Token") {
                PasteableCredentialField(
                    placeholder: "X-Api-Access-Key",
                    secure: true,
                    text: Binding(
                        get: { model.volcDraft.accessKey },
                        set: { model.updateVolcAccessKey($0) }
                    )
                )
            }
            DividerLine()
            SettingsRow(title: "Resource ID") {
                PasteableCredentialField(
                    placeholder: "X-Api-Resource-Id",
                    secure: false,
                    text: Binding(
                        get: { model.volcDraft.resourceId },
                        set: { model.updateVolcResourceId($0) }
                    )
                )
            }
        }
    }

    private var appleSpeechInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            asrInfoLine("无需配置 API key —— Apple Speech 完全由 macOS 系统提供。", symbol: "checkmark.seal")
            asrInfoLine("中文 (zh-CN) 在 Apple Silicon 上支持完全离线识别；其他语言或 Intel 机器会回退到 Apple 云端。", symbol: "globe")
            asrInfoLine("第一次切换并开始录音时，系统会弹窗请求「语音识别」权限——选择允许即可。", symbol: "hand.raised.fill")
        }
        .padding(.vertical, 4)
    }

    private var aliyunParaformerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(title: "API Key") {
                PasteableCredentialField(
                    placeholder: model.aliyunDashScopeApiKeyAvailable ? "已与 LLM「阿里通义」共享" : "百炼控制台 sk-...",
                    secure: true,
                    text: Binding(
                        get: { model.aliyunParaformerDraft.apiKey },
                        set: { model.updateAliyunParaformerApiKey($0) }
                    )
                )
            }

            if model.aliyunDashScopeApiKeyAvailable {
                asrInfoLine("已自动从 LLM「阿里通义 (DashScope)」复用同一个 API Key；如需单独覆盖可直接编辑上方字段。", symbol: "link")
            } else {
                asrInfoLine("可在 LLM 区域选择并填入「阿里通义 (DashScope)」的 API Key，下次会自动复用，不必两边各填一遍。", symbol: "info.circle")
            }
        }
        .padding(.vertical, 4)
    }

    private var customWhisperForm: some View {
        Group {
            SettingsRow(title: "Base URL") {
                PasteableCredentialField(
                    placeholder: "https://api.openai.com/v1",
                    secure: false,
                    text: Binding(
                        get: { model.customWhisperDraft.baseURL },
                        set: { model.updateCustomWhisperBaseURL($0) }
                    )
                )
            }
            DividerLine()
            SettingsRow(title: "API Key") {
                PasteableCredentialField(
                    placeholder: "sk-...",
                    secure: true,
                    text: Binding(
                        get: { model.customWhisperDraft.apiKey },
                        set: { model.updateCustomWhisperApiKey($0) }
                    )
                )
            }
            DividerLine()
            SettingsRow(title: "Model") {
                PasteableCredentialField(
                    placeholder: "whisper-1",
                    secure: false,
                    text: Binding(
                        get: { model.customWhisperDraft.model },
                        set: { model.updateCustomWhisperModel($0) }
                    )
                )
            }
        }
    }

    private func asrInfoLine(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Save

    private var saveActionRow: some View {
        PrimaryActionRow {
            Button {
                model.commit()
                flashSaved()
            } label: {
                Label(savedFlash ? "已保存" : "保存", systemImage: savedFlash ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.hasUnsavedChanges)
        }
        .sheet(isPresented: $model.isShowingAddCustom) {
            AddLLMProviderSheet(
                isPresented: $model.isShowingAddCustom,
                existingIds: Set(model.configuredLLMProviderIds),
                onAdd: { providerId, displayName in
                    model.addLLMProvider(providerId: providerId, displayName: displayName)
                }
            )
        }
    }

    private func flashSaved() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { savedFlash = false }
    }
}

// MARK: - Chip rows

@MainActor
private struct LLMProviderChipRow: View {
    let presets: [LLMProviderRegistry.Preset]
    let selectedProviderId: String
    let activeProviderId: String
    let onSelect: (String) -> Void
    let onAddCustom: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.providerId) { preset in
                    ProviderChipButton(
                        title: preset.displayName,
                        symbol: chipSymbol(for: preset.providerId),
                        isSelected: selectedProviderId == preset.providerId,
                        isActive: activeProviderId == preset.providerId,
                        onSelect: { onSelect(preset.providerId) }
                    )
                }
                // 自定义条目：当 selectedProviderId 不是预设时（用户加进来的 slug），独立画一颗 chip。
                if !selectedProviderId.isEmpty,
                   LLMProviderRegistry.preset(for: selectedProviderId) == nil {
                    ProviderChipButton(
                        title: "自定义 (\(selectedProviderId))",
                        symbol: "slider.horizontal.3",
                        isSelected: true,
                        isActive: activeProviderId == selectedProviderId,
                        onSelect: { onSelect(selectedProviderId) }
                    )
                }
                Button(action: onAddCustom) {
                    Label("自定义", systemImage: "plus.circle")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("添加自定义 OpenAI 兼容 LLM provider")
            }
            .padding(.vertical, 2)
        }
    }

    private func chipSymbol(for providerId: String) -> String {
        switch providerId {
        case "ark": return "sparkles"
        case "openai": return "circle.hexagongrid.fill"
        case "aliyun-dashscope": return "cloud.fill"
        case "deepseek": return "fish"
        case "moonshot": return "moon.stars"
        default: return "wand.and.stars"
        }
    }
}

@MainActor
private struct ASRProviderChipRow: View {
    let presets: [ASRProviderRegistry.Preset]
    let selectedProviderId: String
    let activeProviderId: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.providerId) { preset in
                    ProviderChipButton(
                        title: preset.displayName,
                        symbol: chipSymbol(for: preset.providerId),
                        isSelected: selectedProviderId == preset.providerId,
                        isActive: activeProviderId == preset.providerId,
                        onSelect: { onSelect(preset.providerId) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chipSymbol(for providerId: String) -> String {
        switch providerId {
        case "volcengine": return "cloud.fill"
        case "apple-speech": return "applelogo"
        case "aliyun-paraformer": return "waveform.badge.mic"
        case "custom-openai-whisper": return "slider.horizontal.3"
        default: return "waveform"
        }
    }
}

@MainActor
private struct ProviderChipButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if isActive {
                    Text("当前")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.green.opacity(0.18))
                        )
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drafts

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

// MARK: - Model

/// 配置 Tab 的核心：把所有 LLM / ASR 改动都积攒在内存里，commit() 时一次性写盘。
@MainActor
final class ProvidersConfigModel: ObservableObject {
    // LLM
    @Published private(set) var configuredLLMProviderIds: [String] = []
    @Published private(set) var activeLLMProviderId: String = defaultActiveLLMProviderId
    @Published private(set) var selectedLLMProviderId: String = defaultActiveLLMProviderId
    @Published var llmDraft = LLMConfigDraft()
    /// 用户在草稿态下编辑过的所有 provider 配置（key 为 providerId）。
    /// 切到别的 provider 不会丢；commit 时一起写盘。
    private var pendingLLMConfigs: [String: LLMConfigDraft] = [:]
    /// 用户在草稿态下"添加"的自定义 provider id 列表。commit 时若仍未填关键字段会被回滚。
    private var pendingNewLLMProviders: Set<String> = []
    /// 用户在草稿态下「删除」的 provider id 列表。commit 时一并清掉。
    private var pendingDeletedLLMProviders: Set<String> = []

    @Published var isShowingAddCustom = false

    // ASR
    @Published private(set) var activeASRProviderId: String = defaultActiveASRProviderId
    @Published private(set) var selectedASRProviderId: String = defaultActiveASRProviderId
    @Published var volcDraft = VolcengineDraft()
    @Published var aliyunParaformerDraft = AliyunParaformerDraft()
    @Published var customWhisperDraft = CustomWhisperDraft()

    /// 加载时记录的 ASR 三类字段值，作为「是否有未保存改动」的基线。
    /// LLM 改动直接与 vault 比较，因此不需要快照。
    private var initialSnapshot = Snapshot()

    private struct Snapshot: Equatable {
        var volc: VolcengineDraft = VolcengineDraft()
        var aliyunParaformer: AliyunParaformerDraft = AliyunParaformerDraft()
        var customWhisper: CustomWhisperDraft = CustomWhisperDraft()
    }

    /// 用户已经填好且尚未点保存的改动数。
    var hasUnsavedChanges: Bool {
        // 1. active provider 切换
        if selectedLLMProviderId != activeLLMProviderId { return true }
        if selectedASRProviderId != activeASRProviderId { return true }

        // 2. 当前编辑的 LLM 草稿与 vault 不一致
        if !isCurrentLLMDraftClean() { return true }

        // 3. pending 集合不空（之前切走过的草稿、新增、删除）
        if !pendingDeletedLLMProviders.isEmpty { return true }
        if !pendingNewLLMProviders.isEmpty { return true }
        for (id, draft) in pendingLLMConfigs where id != selectedLLMProviderId {
            if !isLLMDraftClean(providerId: id, draft: draft) { return true }
        }

        // 4. ASR 字段改动
        if volcDraft != initialSnapshot.volc { return true }
        if aliyunParaformerDraft != initialSnapshot.aliyunParaformer { return true }
        if customWhisperDraft != initialSnapshot.customWhisper { return true }

        return false
    }

    /// 当前 selected provider 的草稿是否与 vault 一致（无未保存改动）。
    private func isCurrentLLMDraftClean() -> Bool {
        isLLMDraftClean(providerId: selectedLLMProviderId, draft: llmDraft)
    }

    private func isLLMDraftClean(providerId: String, draft: LLMConfigDraft) -> Bool {
        let vaultDraft = vaultLLMDraft(for: providerId)
        return draft == vaultDraft
    }

    /// 直接读 vault 构造 baseline 草稿；不修改任何状态。
    private func vaultLLMDraft(for providerId: String) -> LLMConfigDraft {
        let vault = CredentialsVault.shared
        let cfg = vault.llmProviderConfig(for: providerId)
        let preset = LLMProviderRegistry.preset(for: providerId)
        var d = LLMConfigDraft()
        d.apiKey = cfg?.apiKey ?? ""
        d.baseURL = cfg?.baseURL.absoluteString ?? preset?.defaultBaseURL.absoluteString ?? ""
        d.model = cfg?.model ?? preset?.defaultModel ?? ""
        d.temperature = cfg?.temperature ?? 0.3
        d.displayName = cfg?.displayName ?? preset?.displayName ?? providerId
        return d
    }

    var aliyunDashScopeApiKeyAvailable: Bool {
        if let cfg = pendingLLMConfigs["aliyun-dashscope"] {
            return !cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let vault = CredentialsVault.shared
        if let cfg = vault.llmProviderConfig(for: "aliyun-dashscope") {
            return !cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    // MARK: - Load

    func load() {
        let vault = CredentialsVault.shared
        configuredLLMProviderIds = vault.configuredLLMProviderIds
        activeLLMProviderId = vault.activeLLMProviderId
        activeASRProviderId = vault.activeASRProviderId

        if !configuredLLMProviderIds.contains(selectedLLMProviderId) {
            selectedLLMProviderId = activeLLMProviderId
        }
        if !ASRProviderRegistry.presets.contains(where: { $0.providerId == selectedASRProviderId }) {
            selectedASRProviderId = activeASRProviderId
        }

        pendingLLMConfigs = [:]
        pendingNewLLMProviders = []
        pendingDeletedLLMProviders = []

        // 把当前 selected 的草稿从 vault 拉出来。
        loadLLMDraftFromVault(for: selectedLLMProviderId)

        // ASR 三类草稿全部从 vault / UserDefaults 读出来。
        loadVolcDraftFromVault()
        loadAliyunParaformerDraft()
        loadCustomWhisperDraft()

        initialSnapshot = baselineSnapshot()
    }

    /// 加载时记录的 ASR 字段基线。LLM 改动直接和 vault 比较。
    private func baselineSnapshot() -> Snapshot {
        var s = Snapshot()
        s.volc = volcDraft
        s.aliyunParaformer = aliyunParaformerDraft
        s.customWhisper = customWhisperDraft
        return s
    }

    // MARK: - LLM selection / form

    func selectLLMProvider(_ providerId: String) {
        // 切走前先把当前草稿快照存起来（commit 时会用到）。
        stashCurrentLLMDraft()
        selectedLLMProviderId = providerId
        loadLLMDraftFromVault(for: providerId)
    }

    func updateLLMApiKey(_ value: String) {
        llmDraft.apiKey = value
    }

    func updateLLMBaseURL(_ value: String) {
        llmDraft.baseURL = value
    }

    func updateLLMModel(_ value: String) {
        llmDraft.model = value
    }

    func updateLLMTemperature(_ value: Double) {
        llmDraft.temperature = value
    }

    func updateLLMDisplayName(_ value: String) {
        llmDraft.displayName = value
    }

    func beginAddCustomLLM() {
        isShowingAddCustom = true
    }

    /// AddLLMProviderSheet 回调：内存里登记一个新 provider，切到它，等待用户填字段。
    func addLLMProvider(providerId: String, displayName: String) {
        let trimmedId = providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        stashCurrentLLMDraft()

        var draft = LLMConfigDraft()
        let preset = LLMProviderRegistry.preset(for: trimmedId)
        draft.displayName = displayName.isEmpty ? (preset?.displayName ?? trimmedId) : displayName
        draft.baseURL = preset?.defaultBaseURL.absoluteString ?? ""
        draft.model = preset?.defaultModel ?? ""
        pendingLLMConfigs[trimmedId] = draft
        pendingNewLLMProviders.insert(trimmedId)
        pendingDeletedLLMProviders.remove(trimmedId)

        if !configuredLLMProviderIds.contains(trimmedId) {
            configuredLLMProviderIds.append(trimmedId)
            configuredLLMProviderIds.sort()
        }
        selectedLLMProviderId = trimmedId
        llmDraft = draft
    }

    func deleteSelectedLLM() {
        let id = selectedLLMProviderId
        guard id != activeLLMProviderId else { return }
        guard LLMProviderRegistry.preset(for: id) == nil else { return } // 预设不允许删
        pendingDeletedLLMProviders.insert(id)
        pendingNewLLMProviders.remove(id)
        pendingLLMConfigs.removeValue(forKey: id)
        configuredLLMProviderIds.removeAll { $0 == id }
        selectedLLMProviderId = activeLLMProviderId
        loadLLMDraftFromVault(for: selectedLLMProviderId)
    }

    // MARK: - ASR selection / form

    func selectASRProvider(_ providerId: String) {
        selectedASRProviderId = providerId
    }

    func updateVolcAppKey(_ value: String) {
        volcDraft.appKey = value
    }

    func updateVolcAccessKey(_ value: String) {
        volcDraft.accessKey = value
    }

    func updateVolcResourceId(_ value: String) {
        volcDraft.resourceId = value
    }

    func updateAliyunParaformerApiKey(_ value: String) {
        aliyunParaformerDraft.apiKey = value
    }

    func updateCustomWhisperBaseURL(_ value: String) {
        customWhisperDraft.baseURL = value
    }

    func updateCustomWhisperApiKey(_ value: String) {
        customWhisperDraft.apiKey = value
    }

    func updateCustomWhisperModel(_ value: String) {
        customWhisperDraft.model = value
    }

    // MARK: - Commit

    /// 一次性把所有改动写盘。
    func commit() {
        stashCurrentLLMDraft()

        let vault = CredentialsVault.shared

        // LLM：先删要删的；再写所有 pending；最后切 active。
        for id in pendingDeletedLLMProviders {
            try? vault.removeLLMProvider(id)
        }
        for (providerId, draft) in pendingLLMConfigs {
            persistLLMDraft(providerId: providerId, draft: draft)
        }
        if vault.activeLLMProviderId != selectedLLMProviderId,
           !pendingDeletedLLMProviders.contains(selectedLLMProviderId) {
            vault.activeLLMProviderId = selectedLLMProviderId
        }

        // ASR：火山字段写 vault；阿里 / Whisper 写 UserDefaults（vault schema 暂不支持）。
        persistVolcDraft()
        persistAliyunParaformerDraft()
        persistCustomWhisperDraft()
        if vault.activeASRProviderId != selectedASRProviderId {
            vault.activeASRProviderId = selectedASRProviderId
        }

        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        load()
    }

    // MARK: - LLM draft 装载 / 存档

    private func stashCurrentLLMDraft() {
        pendingLLMConfigs[selectedLLMProviderId] = llmDraft
    }

    private func loadLLMDraftFromVault(for providerId: String) {
        if let pending = pendingLLMConfigs[providerId] {
            llmDraft = pending
            return
        }
        let vault = CredentialsVault.shared
        let cfg = vault.llmProviderConfig(for: providerId)
        let preset = LLMProviderRegistry.preset(for: providerId)
        var draft = LLMConfigDraft()
        draft.apiKey = cfg?.apiKey ?? ""
        draft.baseURL = cfg?.baseURL.absoluteString ?? preset?.defaultBaseURL.absoluteString ?? ""
        draft.model = cfg?.model ?? preset?.defaultModel ?? ""
        draft.temperature = cfg?.temperature ?? 0.3
        draft.displayName = cfg?.displayName ?? preset?.displayName ?? providerId
        llmDraft = draft
    }

    private func persistLLMDraft(providerId: String, draft: LLMConfigDraft) {
        let vault = CredentialsVault.shared
        let preset = LLMProviderRegistry.preset(for: providerId)

        // 自定义 provider 没填 baseURL 时跳过——避免落出空配置。
        let trimmedBaseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL: URL
        if let parsed = URL(string: trimmedBaseURL), !trimmedBaseURL.isEmpty, parsed.scheme != nil {
            baseURL = parsed
        } else if let preset {
            baseURL = preset.defaultBaseURL
        } else {
            return
        }

        let displayName = draft.displayName.isEmpty
            ? (preset?.displayName ?? providerId)
            : draft.displayName

        let cfg = OpenAICompatibleConfig(
            providerId: providerId,
            displayName: displayName,
            baseURL: baseURL,
            apiKey: draft.apiKey,
            model: draft.model,
            extraHeaders: [:],
            temperature: draft.temperature
        )
        vault.setLLMProviderConfig(cfg)
    }

    // MARK: - Volcengine draft

    private func loadVolcDraftFromVault() {
        let vault = CredentialsVault.shared
        var d = VolcengineDraft()
        d.appKey = vault.get(CredentialAccount.volcengineAppKey) ?? ""
        d.accessKey = vault.get(CredentialAccount.volcengineAccessKey) ?? ""
        let resource = vault.get(CredentialAccount.volcengineResourceId) ?? ""
        d.resourceId = resource.isEmpty ? VolcengineCredentials.defaultResourceId : resource
        volcDraft = d
    }

    private func persistVolcDraft() {
        let vault = CredentialsVault.shared
        try? vault.set(volcDraft.appKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAppKey)
        try? vault.set(volcDraft.accessKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAccessKey)
        try? vault.set(volcDraft.resourceId.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineResourceId)
    }

    // MARK: - Aliyun Paraformer draft（暂存 UserDefaults）

    private func loadAliyunParaformerDraft() {
        var d = AliyunParaformerDraft()
        // 优先用 LLM 阿里通义已填的 apiKey；否则用本地 fallback。
        let vault = CredentialsVault.shared
        if let llm = vault.llmProviderConfig(for: "aliyun-dashscope"),
           !llm.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            d.apiKey = llm.apiKey
        } else {
            d.apiKey = UserDefaults.standard.string(forKey: ProvidersConfigModel.aliyunParaformerApiKeyDefaultsKey) ?? ""
        }
        aliyunParaformerDraft = d
    }

    private func persistAliyunParaformerDraft() {
        let trimmed = aliyunParaformerDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: ProvidersConfigModel.aliyunParaformerApiKeyDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: ProvidersConfigModel.aliyunParaformerApiKeyDefaultsKey)
        }
    }

    // MARK: - Custom OpenAI Whisper draft（暂存 UserDefaults）

    private func loadCustomWhisperDraft() {
        var d = CustomWhisperDraft()
        let defaults = UserDefaults.standard
        d.baseURL = defaults.string(forKey: ProvidersConfigModel.customWhisperBaseURLKey) ?? ""
        d.apiKey = defaults.string(forKey: ProvidersConfigModel.customWhisperApiKeyKey) ?? ""
        d.model = defaults.string(forKey: ProvidersConfigModel.customWhisperModelKey) ?? "whisper-1"
        customWhisperDraft = d
    }

    private func persistCustomWhisperDraft() {
        let defaults = UserDefaults.standard
        let baseURL = customWhisperDraft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = customWhisperDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = customWhisperDraft.model.trimmingCharacters(in: .whitespacesAndNewlines)

        if baseURL.isEmpty {
            defaults.removeObject(forKey: ProvidersConfigModel.customWhisperBaseURLKey)
        } else {
            defaults.set(baseURL, forKey: ProvidersConfigModel.customWhisperBaseURLKey)
        }
        if apiKey.isEmpty {
            defaults.removeObject(forKey: ProvidersConfigModel.customWhisperApiKeyKey)
        } else {
            defaults.set(apiKey, forKey: ProvidersConfigModel.customWhisperApiKeyKey)
        }
        if model.isEmpty {
            defaults.removeObject(forKey: ProvidersConfigModel.customWhisperModelKey)
        } else {
            defaults.set(model, forKey: ProvidersConfigModel.customWhisperModelKey)
        }
    }

    // MARK: - 常量

    static let aliyunParaformerApiKeyDefaultsKey = "openless.asr.aliyun_paraformer.api_key"
    static let customWhisperBaseURLKey = "openless.asr.custom_whisper.base_url"
    static let customWhisperApiKeyKey = "openless.asr.custom_whisper.api_key"
    static let customWhisperModelKey = "openless.asr.custom_whisper.model"
}

// MARK: - Add Custom LLM Provider Sheet

/// 添加 LLM provider 的 sheet：列出所有预设 + "自定义"；选 "自定义" 时多一步收集 slug + displayName。
///
/// 与拆分前 LLMProvidersTab 中的同名 sheet 完全一致，搬到 ProvidersConfigTab 同文件保持邻近。
@MainActor
struct AddLLMProviderSheet: View {
    @Binding var isPresented: Bool
    let existingIds: Set<String>
    let onAdd: (_ providerId: String, _ displayName: String) -> Void

    @State private var customId: String = ""
    @State private var customDisplayName: String = ""
    @State private var step: Step = .pick

    enum Step {
        case pick
        case customDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(step == .pick ? "添加 LLM Provider" : "自定义 OpenAI 兼容 Provider")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                switch step {
                case .pick:
                    pickList
                case .customDetails:
                    customDetailsForm
                }
            }
            .frame(minHeight: 360, maxHeight: 480)
        }
        .frame(width: 520)
    }

    private var pickList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LLMProviderRegistry.presets, id: \.providerId) { preset in
                presetRow(preset)
                Divider().padding(.leading, 16)
            }
            customRow
        }
        .padding(.vertical, 4)
    }

    private func presetRow(_ preset: LLMProviderRegistry.Preset) -> some View {
        let alreadyAdded = existingIds.contains(preset.providerId)
        return Button {
            guard !alreadyAdded else { return }
            onAdd(preset.providerId, preset.displayName)
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(alreadyAdded ? .green : .secondary)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(preset.defaultBaseURL.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(preset.helpText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .help(alreadyAdded ? "已添加" : "添加 \(preset.displayName)")
    }

    private var customRow: some View {
        Button {
            step = .customDetails
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LLMProviderRegistry.customDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("任何遵循 OpenAI Chat Completions 协议的供应商都能填进来——比如自建网关、私有化部署、或表里没列的云厂商。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customDetailsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Provider ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("custom-gateway", text: $customId)
                    .textFieldStyle(.roundedBorder)
                Text("唯一 slug，建议小写字母 / 数字 / 短横线；不能与已存在的 id 重复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("展示名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("公司内部网关", text: $customDisplayName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("返回") {
                    step = .pick
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("添加") {
                    let id = customId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAdd(id, name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isCustomReady)
            }
            .padding(.top, 6)
        }
        .padding(20)
    }

    private var isCustomReady: Bool {
        let id = customId.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !name.isEmpty else { return false }
        if LLMProviderRegistry.preset(for: id) != nil { return false }
        if existingIds.contains(id) { return false }
        return true
    }
}
