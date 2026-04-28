import SwiftUI
import OpenLessCore
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder

// 遗留 Tab：当前 SettingsView 的 switch 没用到，保留以备后续单独入口使用。
// 如果半年后仍然没人引用就可以一刀清。

// MARK: - Overview

struct OverviewTab: View {
    @State private var hasVolcCreds = false
    @State private var hasArkCreds = false
    @State private var hasAccessibility = false
    @State private var hasMicrophone = false
    @State private var dictionaryCount = 0

    var body: some View {
        SettingsPage(
            title: "OpenLess",
            subtitle: "本地优先、低打扰、可控润色的 macOS 语音输入层。"
        ) {
            GlassSection(title: "状态", symbol: "checkmark.seal") {
                StatusLine(title: "火山引擎 ASR", detail: hasVolcCreds ? "已配置" : "缺少 App ID 或 Access Token", ok: hasVolcCreds)
                DividerLine()
                StatusLine(title: "Ark 润色", detail: hasArkCreds ? "已配置" : "未配置，识别后会直接插入原文", ok: hasArkCreds)
                DividerLine()
                StatusLine(title: "辅助功能", detail: hasAccessibility ? "已授权" : "未授权", ok: hasAccessibility)
                DividerLine()
                StatusLine(title: "麦克风", detail: hasMicrophone ? "已授权" : "未授权", ok: hasMicrophone)
            }

            GlassSection(title: "当前设置", symbol: "slider.horizontal.3") {
                SettingsRow(title: "录音快捷键") {
                    Text(UserPreferences.shared.hotkeyTrigger.displayName)
                }
                DividerLine()
                SettingsRow(title: "默认输出模式") {
                    Text(UserPreferences.shared.polishMode.displayName)
                }
                DividerLine()
                SettingsRow(title: "启用词汇表") {
                    Text("\(dictionaryCount) 个词条")
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let v = CredentialsVault.shared
        hasVolcCreds = isFilled(v.get(CredentialAccount.volcengineAppKey))
            && isFilled(v.get(CredentialAccount.volcengineAccessKey))
        hasArkCreds = isFilled(v.get(CredentialAccount.arkApiKey))
        hasAccessibility = AccessibilityPermission.isGranted()
        hasMicrophone = MicrophonePermission.isGranted()
        dictionaryCount = DictionaryStore().enabledEntries().count
    }
}

// MARK: - Hotkey

struct HotkeyTab: View {
    @State private var trigger: HotkeyBinding.Trigger = UserPreferences.shared.hotkeyTrigger

    var body: some View {
        SettingsPage(
            title: "快捷键",
            subtitle: "按一次开始录音，再按一次结束；录音中按 Esc 取消。"
        ) {
            GlassSection(title: "录音", symbol: "keyboard") {
                SettingsRow(title: "触发键") {
                    Picker("触发键", selection: $trigger) {
                        ForEach(HotkeyBinding.Trigger.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
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

                Text("现在按下触发键时会立即弹出录音状态，不再等到松开后才显示。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)

                if trigger == .fn {
                    Label("Fn / Globe 可能被系统听写或表情面板占用；如果冲突，建议改用右 Option。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                }
            }
        }
    }
}

// MARK: - Modes

struct ModesTab: View {
    @State private var current: PolishMode = UserPreferences.shared.polishMode

    var body: some View {
        SettingsPage(
            title: "输出模式",
            subtitle: "选择识别后默认使用的文本整理方式。"
        ) {
            GlassSection(title: "默认模式", symbol: "text.badge.checkmark") {
                Picker("模式", selection: $current) {
                    ForEach(PolishMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: current) { _, newValue in
                    UserPreferences.shared.polishMode = newValue
                }

                DividerLine()

                Text(polishModeHint(current))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }
}

// MARK: - Privacy

struct PrivacyTab: View {
    var body: some View {
        SettingsPage(
            title: "隐私",
            subtitle: "OpenLess 默认只保存必要的文本历史、词汇表和本机受保护凭据文件。"
        ) {
            GlassSection(title: "本机", symbol: "lock.shield") {
                privacyRow("音频默认不保存到磁盘", symbol: "mic.slash")
                DividerLine()
                privacyRow("API Key 仅存本机 0600 权限文件", symbol: "key")
                DividerLine()
                privacyRow("历史只保存原始转写和最终文本", symbol: "doc.text")
            }

            GlassSection(title: "云端", symbol: "icloud") {
                privacyRow("使用云端 ASR 时，音频会发送给火山引擎", symbol: "waveform")
                DividerLine()
                privacyRow("开启 Ark 润色时，转写文本会发送给 Ark", symbol: "wand.and.stars")
            }
        }
    }

    private func privacyRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
            Spacer()
        }
        .padding(.vertical, 9)
    }
}
