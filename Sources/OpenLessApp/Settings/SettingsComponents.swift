import AppKit
import SwiftUI
import OpenLessCore
import OpenLessPersistence

// 共享 UI：所有 Tab 都用到的容器、行、字段、修饰符。
// 拆出来是为了让 SettingsView.swift / 各 Tab 文件保持单一职责。

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)

                content
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .background(Color.clear)
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 138, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}

struct DividerLine: View {
    var body: some View {
        Divider()
            .padding(.leading, 154)
    }
}

struct StatusLine: View {
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        SettingsRow(title: title) {
            Label(detail, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

struct PasteableCredentialField: View {
    let placeholder: String
    let secure: Bool
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if secure && !revealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 390)

            if secure {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(revealed ? "隐藏密钥" : "显示密钥")
            }

            Button {
                if let value = NSPasteboard.general.string(forType: .string) {
                    text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("从剪贴板粘贴")
        }
    }
}

struct PrimaryActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
        .padding(.top, 4)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .glassPanel(cornerRadius: 22)
    }
}

func isFilled(_ value: String?) -> Bool {
    guard let value else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

func polishModeHint(_ mode: PolishMode) -> String {
    switch mode {
    case .raw: return "尽量忠实转写，只做基础标点和必要分句。"
    case .light: return "去掉明显口癖和重复，尽量保留原句式和语气。"
    case .structured: return "整理句子、段落和列表，适合 prompt 与笔记。"
    case .formal: return "适合邮件、工作沟通和正式文档。"
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                // 边线半透明压到 0.04 + lineWidth 0.5：避免侧边栏外圈出现明显灰带。
                .overlay(shape.strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
                // 阴影 radius 从 16 → 6：侧边栏顶 padding=0 时不会再被裁出黑色矩形带。
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
    }
}

extension Notification.Name {
    static let openLessHistoryChanged = Notification.Name("openless.history_changed")
    static let openLessHotkeyChanged = Notification.Name("openless.hotkey_changed")
    static let openLessCredentialsChanged = Notification.Name("openless.credentials_changed")
    static let openLessDictionaryChanged = Notification.Name("openless.dictionary_changed")
}
