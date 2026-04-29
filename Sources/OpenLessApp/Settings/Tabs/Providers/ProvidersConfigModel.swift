import Foundation
import SwiftUI
import OpenLessCore
import OpenLessASR
import OpenLessPersistence

/// 配置 Tab 的核心：把所有 LLM / ASR 改动都积攒在内存里，commit() 时一次性写盘。
@MainActor
final class ProvidersConfigModel: ObservableObject {
    @Published private(set) var configuredLLMProviderIds: [String] = []
    @Published private(set) var activeLLMProviderId: String = defaultActiveLLMProviderId
    @Published private(set) var selectedLLMProviderId: String = defaultActiveLLMProviderId
    @Published var llmDraft = LLMConfigDraft()
    @Published var isShowingAddCustom = false

    @Published private(set) var activeASRProviderId: String = defaultActiveASRProviderId
    @Published private(set) var selectedASRProviderId: String = defaultActiveASRProviderId
    @Published var volcDraft = VolcengineDraft()
    @Published var aliyunParaformerDraft = AliyunParaformerDraft()
    @Published var customWhisperDraft = CustomWhisperDraft()

    /// 用户在草稿态下编辑过的所有 provider 配置（key 为 providerId）。
    /// 切到别的 provider 不会丢；commit 时一起写盘。
    private var pendingLLMConfigs: [String: LLMConfigDraft] = [:]
    /// 用户在草稿态下"添加"的自定义 provider id 列表。commit 时若仍未填关键字段会被回滚。
    private var pendingNewLLMProviders: Set<String> = []
    /// 用户在草稿态下「删除」的 provider id 列表。commit 时一并清掉。
    private var pendingDeletedLLMProviders: Set<String> = []

    /// 加载时记录的 ASR 三类字段值，作为「是否有未保存改动」的基线。
    /// LLM 改动直接与 vault 比较，因此不需要快照。
    private var initialSnapshot = Snapshot()

    private struct Snapshot: Equatable {
        var volc: VolcengineDraft = VolcengineDraft()
        var aliyunParaformer: AliyunParaformerDraft = AliyunParaformerDraft()
        var customWhisper: CustomWhisperDraft = CustomWhisperDraft()
    }

    var hasUnsavedChanges: Bool {
        if selectedLLMProviderId != activeLLMProviderId { return true }
        if selectedASRProviderId != activeASRProviderId { return true }
        if !isCurrentLLMDraftClean() { return true }

        if !pendingDeletedLLMProviders.isEmpty { return true }
        if !pendingNewLLMProviders.isEmpty { return true }
        for (id, draft) in pendingLLMConfigs where id != selectedLLMProviderId {
            if !isLLMDraftClean(providerId: id, draft: draft) { return true }
        }

        if volcDraft != initialSnapshot.volc { return true }
        if aliyunParaformerDraft != initialSnapshot.aliyunParaformer { return true }
        if customWhisperDraft != initialSnapshot.customWhisper { return true }

        return false
    }

    var aliyunDashScopeApiKeyAvailable: Bool {
        if let cfg = pendingLLMConfigs["aliyun-dashscope"] {
            return !cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let cfg = CredentialsVault.shared.llmProviderConfig(for: "aliyun-dashscope") {
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

        loadLLMDraftFromVault(for: selectedLLMProviderId)
        loadVolcDraftFromVault()
        loadAliyunParaformerDraft()
        loadCustomWhisperDraft()

        initialSnapshot = baselineSnapshot()
    }

    private func baselineSnapshot() -> Snapshot {
        Snapshot(
            volc: volcDraft,
            aliyunParaformer: aliyunParaformerDraft,
            customWhisper: customWhisperDraft
        )
    }

    // MARK: - LLM Selection

    func selectLLMProvider(_ providerId: String) {
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

    func beginAddCustomLLM() {
        isShowingAddCustom = true
    }

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
        guard LLMProviderRegistry.preset(for: id) == nil else { return }

        pendingDeletedLLMProviders.insert(id)
        pendingNewLLMProviders.remove(id)
        pendingLLMConfigs.removeValue(forKey: id)
        configuredLLMProviderIds.removeAll { $0 == id }
        selectedLLMProviderId = activeLLMProviderId
        loadLLMDraftFromVault(for: selectedLLMProviderId)
    }

    // MARK: - ASR Selection

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

    func commit() {
        stashCurrentLLMDraft()

        let vault = CredentialsVault.shared

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

        persistVolcDraft()
        persistAliyunParaformerDraft()
        persistCustomWhisperDraft()
        if vault.activeASRProviderId != selectedASRProviderId {
            vault.activeASRProviderId = selectedASRProviderId
        }

        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        load()
    }

    // MARK: - LLM Drafts

    private func isCurrentLLMDraftClean() -> Bool {
        isLLMDraftClean(providerId: selectedLLMProviderId, draft: llmDraft)
    }

    private func isLLMDraftClean(providerId: String, draft: LLMConfigDraft) -> Bool {
        draft == vaultLLMDraft(for: providerId)
    }

    private func vaultLLMDraft(for providerId: String) -> LLMConfigDraft {
        let vault = CredentialsVault.shared
        let cfg = vault.llmProviderConfig(for: providerId)
        let preset = LLMProviderRegistry.preset(for: providerId)
        var draft = LLMConfigDraft()
        draft.apiKey = cfg?.apiKey ?? ""
        draft.baseURL = cfg?.baseURL.absoluteString ?? preset?.defaultBaseURL.absoluteString ?? ""
        draft.model = cfg?.model ?? preset?.defaultModel ?? ""
        draft.temperature = cfg?.temperature ?? 0.3
        draft.displayName = cfg?.displayName ?? preset?.displayName ?? providerId
        return draft
    }

    private func stashCurrentLLMDraft() {
        pendingLLMConfigs[selectedLLMProviderId] = llmDraft
    }

    private func loadLLMDraftFromVault(for providerId: String) {
        if let pending = pendingLLMConfigs[providerId] {
            llmDraft = pending
            return
        }
        llmDraft = vaultLLMDraft(for: providerId)
    }

    private func persistLLMDraft(providerId: String, draft: LLMConfigDraft) {
        let vault = CredentialsVault.shared
        let preset = LLMProviderRegistry.preset(for: providerId)

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

        let config = OpenAICompatibleConfig(
            providerId: providerId,
            displayName: displayName,
            baseURL: baseURL,
            apiKey: draft.apiKey,
            model: draft.model,
            extraHeaders: [:],
            temperature: draft.temperature
        )
        vault.setLLMProviderConfig(config)
    }

    // MARK: - Volcengine Draft

    private func loadVolcDraftFromVault() {
        let vault = CredentialsVault.shared
        var draft = VolcengineDraft()
        draft.appKey = vault.get(CredentialAccount.volcengineAppKey) ?? ""
        draft.accessKey = vault.get(CredentialAccount.volcengineAccessKey) ?? ""
        let resource = vault.get(CredentialAccount.volcengineResourceId) ?? ""
        draft.resourceId = resource.isEmpty ? VolcengineCredentials.defaultResourceId : resource
        volcDraft = draft
    }

    private func persistVolcDraft() {
        let vault = CredentialsVault.shared
        try? vault.set(volcDraft.appKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAppKey)
        try? vault.set(volcDraft.accessKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAccessKey)
        try? vault.set(volcDraft.resourceId.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineResourceId)
    }

    // MARK: - Aliyun Paraformer Draft

    private func loadAliyunParaformerDraft() {
        var draft = AliyunParaformerDraft()
        let vault = CredentialsVault.shared
        if let asr = vault.asrProviderConfig(for: "aliyun-paraformer"),
           let key = asr.apiKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.apiKey = key
        } else if let llm = vault.llmProviderConfig(for: "aliyun-dashscope"),
                  !llm.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.apiKey = llm.apiKey
        }
        aliyunParaformerDraft = draft
    }

    private func persistAliyunParaformerDraft() {
        let vault = CredentialsVault.shared
        let trimmed = aliyunParaformerDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? vault.removeASRProvider("aliyun-paraformer")
        } else {
            var entry = vault.asrProviderConfig(for: "aliyun-paraformer") ?? CredentialsProviderASREntry()
            entry.apiKey = trimmed
            vault.setASRProviderConfig(entry, for: "aliyun-paraformer")
        }
    }

    // MARK: - Custom OpenAI Whisper Draft

    private func loadCustomWhisperDraft() {
        var draft = CustomWhisperDraft()
        let vault = CredentialsVault.shared
        if let asr = vault.asrProviderConfig(for: "custom-openai-whisper") {
            draft.baseURL = asr.baseURL ?? ""
            draft.apiKey = asr.apiKey ?? ""
            draft.model = (asr.model?.isEmpty == false ? asr.model! : "whisper-1")
        } else {
            draft.model = "whisper-1"
        }
        customWhisperDraft = draft
    }

    private func persistCustomWhisperDraft() {
        let vault = CredentialsVault.shared
        let baseURL = customWhisperDraft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = customWhisperDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = customWhisperDraft.model.trimmingCharacters(in: .whitespacesAndNewlines)

        if baseURL.isEmpty && apiKey.isEmpty && model.isEmpty {
            try? vault.removeASRProvider("custom-openai-whisper")
            return
        }

        var entry = vault.asrProviderConfig(for: "custom-openai-whisper") ?? CredentialsProviderASREntry()
        entry.baseURL = baseURL.isEmpty ? nil : baseURL
        entry.apiKey = apiKey.isEmpty ? nil : apiKey
        entry.model = model.isEmpty ? nil : model
        vault.setASRProviderConfig(entry, for: "custom-openai-whisper")
    }
}
