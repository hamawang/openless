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
