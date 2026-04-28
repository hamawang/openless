import AppKit
import SwiftUI
import OpenLessCore
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder
import OpenLessASR
import OpenLessPolish

/// 所有可调项汇总：录音 + 凭据（Volc ASR + Ark 润色）+ 授权 + 隐私 + 关于。
struct SettingsHubTab: View {
    @State private var trigger: HotkeyBinding.Trigger = UserPreferences.shared.hotkeyTrigger
    @State private var hotkeyMode: HotkeyMode = UserPreferences.shared.hotkeyMode
    @State private var hasAccessibility = false
    @State private var hasMicrophone = false

    @State private var volcAppKey = ""
    @State private var volcAccessKey = ""
    @State private var volcResourceId = VolcengineCredentials.defaultResourceId
    @State private var arkApiKey = ""
    @State private var arkModelId = ArkCredentials.defaultModelId
    @State private var arkEndpoint = ArkCredentials.defaultEndpoint.absoluteString
    @State private var saved = false

    var body: some View {
        SettingsPage(
            title: "设置",
            subtitle: "录音快捷键、凭据、授权状态、隐私和版本信息全部在这里。"
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

            GlassSection(title: "火山引擎大模型流式 ASR", symbol: "waveform") {
                SettingsRow(title: "APP ID") {
                    PasteableCredentialField(placeholder: "X-Api-App-Key", secure: false, text: $volcAppKey)
                }
                DividerLine()
                SettingsRow(title: "Access Token") {
                    PasteableCredentialField(placeholder: "X-Api-Access-Key", secure: true, text: $volcAccessKey)
                }
                DividerLine()
                SettingsRow(title: "Resource ID") {
                    PasteableCredentialField(placeholder: "X-Api-Resource-Id", secure: false, text: $volcResourceId)
                }
            }

            GlassSection(title: "Ark / DeepSeek V3.2 润色", symbol: "wand.and.stars") {
                SettingsRow(title: "API Key") {
                    PasteableCredentialField(placeholder: "Bearer Token", secure: true, text: $arkApiKey)
                }
                DividerLine()
                SettingsRow(title: "Model ID") {
                    PasteableCredentialField(placeholder: "Model ID", secure: false, text: $arkModelId)
                }
                DividerLine()
                SettingsRow(title: "Endpoint") {
                    PasteableCredentialField(placeholder: "Endpoint", secure: false, text: $arkEndpoint)
                }
            }

            PrimaryActionRow {
                Button("保存凭据") { saveCredentials() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
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
                privacyRow("云端 ASR 会上传音频；开启 Ark 润色时上传转写文本", symbol: "icloud")
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
        volcAppKey = v.get(CredentialAccount.volcengineAppKey) ?? ""
        volcAccessKey = v.get(CredentialAccount.volcengineAccessKey) ?? ""
        volcResourceId = v.get(CredentialAccount.volcengineResourceId) ?? VolcengineCredentials.defaultResourceId
        arkApiKey = v.get(CredentialAccount.arkApiKey) ?? ""
        arkModelId = v.get(CredentialAccount.arkModelId) ?? ArkCredentials.defaultModelId
        arkEndpoint = v.get(CredentialAccount.arkEndpoint) ?? ArkCredentials.defaultEndpoint.absoluteString
    }

    private func saveCredentials() {
        let v = CredentialsVault.shared
        try? v.set(volcAppKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAppKey)
        try? v.set(volcAccessKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAccessKey)
        try? v.set(volcResourceId.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineResourceId)
        try? v.set(arkApiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.arkApiKey)
        try? v.set(arkModelId.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.arkModelId)
        try? v.set(arkEndpoint.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.arkEndpoint)
        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
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
