import AppKit
import SwiftUI
import OpenLessCore
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder

/// 系统级开关与状态汇总：录音快捷键 + 授权 + 隐私 + 关于。
/// LLM 与 ASR 的凭据 / provider 切换全部搬到「配置」Tab。
struct SettingsHubTab: View {
    @State private var trigger: HotkeyBinding.Trigger = UserPreferences.shared.hotkeyTrigger
    @State private var hotkeyMode: HotkeyMode = UserPreferences.shared.hotkeyMode
    @State private var hasAccessibility = false
    @State private var hasMicrophone = false

    @State private var hasLLMProvider = false
    @State private var llmProviderDisplayName = ""
    @State private var activeASRDisplayName = ""

    var body: some View {
        SettingsPage(
            title: "设置",
            subtitle: "录音快捷键、授权状态、隐私和版本信息。LLM 模型 / ASR 语音的 API Key 和切换在「配置」Tab。"
        ) {
            GlassSection(title: "录音", symbol: "keyboard") {
                SettingsRow(title: "录音快捷键") {
                    Picker("触发键", selection: $trigger) {
                        ForEach(HotkeyBinding.Trigger.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                    .onChange(of: trigger) { _, newValue in
                        UserPreferences.shared.hotkeyTrigger = newValue
                        NotificationCenter.default.post(name: .openLessHotkeyChanged, object: nil)
                    }
                }
                DividerLine()
                SettingsRow(title: "录音方式") {
                    Picker("录音方式", selection: $hotkeyMode) {
                        ForEach(HotkeyMode.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220, alignment: .leading)
                    .onChange(of: hotkeyMode) { _, newValue in
                        UserPreferences.shared.hotkeyMode = newValue
                        NotificationCenter.default.post(name: .openLessHotkeyChanged, object: nil)
                    }
                }
                DividerLine()
                Text(hotkeyMode.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            GlassSection(title: "Provider 概览", symbol: "wand.and.stars") {
                SettingsRow(title: "LLM 模型") {
                    HStack(spacing: 10) {
                        Label(
                            hasLLMProvider ? llmProviderDisplayName : "未配置",
                            systemImage: hasLLMProvider ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(hasLLMProvider ? .green : .orange)
                        Spacer()
                    }
                }
                DividerLine()
                SettingsRow(title: "ASR 语音") {
                    HStack(spacing: 10) {
                        Label(
                            activeASRDisplayName.isEmpty ? "未选择" : activeASRDisplayName,
                            systemImage: "waveform"
                        )
                        .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                DividerLine()
                Text("前往「配置」Tab 选择并填写 LLM / ASR 凭据。未配置 LLM 时识别后直接插入原文；ASR 缺凭据时回退到演示模式。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            GlassSection(title: "授权状态", symbol: "checkmark.seal") {
                StatusLine(title: "辅助功能", detail: hasAccessibility ? "已授权" : "未授权", ok: hasAccessibility)
                DividerLine()
                StatusLine(title: "麦克风", detail: hasMicrophone ? "已授权" : "未授权", ok: hasMicrophone)
            }

            GlassSection(title: "隐私", symbol: "lock.shield") {
                privacyRow("音频默认不保存到磁盘", symbol: "mic.slash")
                DividerLine()
                privacyRow("API Key 仅存本机 0600 权限文件", symbol: "key")
                DividerLine()
                privacyRow("历史只保存原始转写和最终文本", symbol: "doc.text")
                DividerLine()
                privacyRow("云端 ASR 会上传音频；开启润色时上传转写文本", symbol: "icloud")
            }

            GlassSection(title: "关于", symbol: "info.circle") {
                SettingsRow(title: "版本") {
                    Text(versionString)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                DividerLine()
                SettingsRow(title: "更新") {
                    Button("检查更新…") {
                        NSApp.sendAction(#selector(UpdaterController.checkForUpdates(_:)), to: nil, from: nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessCredentialsChanged)) { _ in
            refresh()
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }

    private func refresh() {
        trigger = UserPreferences.shared.hotkeyTrigger
        hotkeyMode = UserPreferences.shared.hotkeyMode
        hasAccessibility = AccessibilityPermission.isGranted()
        hasMicrophone = MicrophonePermission.isGranted()
        let v = CredentialsVault.shared

        // 当前 active LLM provider 是否填了 apiKey；详细配置在「配置」Tab。
        let activeLLMId = v.activeLLMProviderId
        if let cfg = v.llmProviderConfig(for: activeLLMId), !cfg.apiKey.isEmpty {
            hasLLMProvider = true
            llmProviderDisplayName = cfg.displayName
        } else {
            hasLLMProvider = false
            llmProviderDisplayName = LLMProviderRegistry.preset(for: activeLLMId)?.displayName ?? activeLLMId
        }

        let activeASRId = v.activeASRProviderId
        activeASRDisplayName = ASRProviderRegistry.preset(for: activeASRId)?.displayName ?? activeASRId
    }

    private func privacyRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 9)
    }
}
