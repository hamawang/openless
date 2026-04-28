import SwiftUI
import OpenLessCore
import OpenLessPersistence

/// 风格 Tab：参考 LazyTyper 风格页 — 顶部启用开关 + 4 个模式卡片网格。
/// 选中卡片得绿色顶 stroke + 标题前 ✓；样例文本固定，仅作示意。
struct StyleTab: View {
    @State private var enabled = UserPreferences.shared.polishEnabled
    @State private var mode: PolishMode = UserPreferences.shared.polishMode

    var body: some View {
        SettingsPage(
            title: "风格",
            subtitle: "为不同场景配置输出风格。每个风格包含 AI 润色与文本优化设置。"
        ) {
            HStack {
                Spacer()
                Toggle("启用", isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .onChange(of: enabled) { _, newValue in
                        UserPreferences.shared.polishEnabled = newValue
                    }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(PolishMode.allCases, id: \.self) { m in
                    StyleCard(
                        mode: m,
                        selected: mode == m,
                        enabled: enabled,
                        onSelect: {
                            mode = m
                            UserPreferences.shared.polishMode = m
                        }
                    )
                }
            }
            .opacity(enabled ? 1 : 0.55)
            .allowsHitTesting(enabled)
        }
        .onAppear {
            enabled = UserPreferences.shared.polishEnabled
            mode = UserPreferences.shared.polishMode
        }
    }
}

struct StyleCard: View {
    let mode: PolishMode
    let selected: Bool
    let enabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                // 顶条：选中时绿色，未选中时透明
                Rectangle()
                    .fill(selected ? Color.green : Color.clear)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(selected ? Color.green : Color.green.opacity(0.45))
                            .font(.system(size: 13))
                        Text(mode.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                    Text(modeSubtitle(mode))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sampleText(mode))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.8))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.green.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func modeSubtitle(_ m: PolishMode) -> String {
        switch m {
        case .raw: return "忠实转写"
        case .light: return "去口癖保语气"
        case .structured: return "结构化整理"
        case .formal: return "正式书面"
        }
    }

    private func sampleText(_ m: PolishMode) -> String {
        switch m {
        case .raw: return "嗯那个我刚刚看了下新出的电影预告片，挺有意思的你有空也看看。"
        case .light: return "我刚看了下新出的电影预告片，挺有意思的，你有空也看看。"
        case .structured: return "刚看了新电影预告片，挺有意思的。建议有空也看一下，反馈一下你的想法。"
        case .formal: return "我刚刚观看了新电影的预告片，内容颇具新意。如有时间，建议你也观看，并分享你的看法。"
        }
    }
}
