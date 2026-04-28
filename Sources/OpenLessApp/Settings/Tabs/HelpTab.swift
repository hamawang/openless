import SwiftUI
import OpenLessCore
import OpenLessPersistence

struct HelpTab: View {
    var body: some View {
        SettingsPage(
            title: "帮助中心",
            subtitle: "快速上手 OpenLess、查阅快捷键、检查授权状态、跳转到文档与反馈渠道。"
        ) {
            GlassSection(title: "快速上手", symbol: "play.circle") {
                helpStep(num: 1, title: "配置火山 ASR", body: "在「火山 ASR」页面填入 APP ID 和 Access Token；没有 ASR 凭据时只能走演示模式。")
                DividerLine()
                helpStep(num: 2, title: "（可选）配置润色", body: "「润色模式」页面填入 Ark API Key 后，识别结果会按所选模式润色；不填也能用，会直接插入原文。")
                DividerLine()
                helpStep(num: 3, title: "授权辅助功能 + 麦克风", body: "首次启动会请求权限。授权后必须完全退出 OpenLess 再重新打开，全局快捷键才会生效。")
                DividerLine()
                helpStep(num: 4, title: "开始说话", body: "默认按右 Option 开始/停止录音；说完后文字自动插入到当前光标位置。Esc 取消本次。")
            }

            GlassSection(title: "快捷键速查", symbol: "keyboard") {
                helpKey("开始 / 停止录音", value: UserPreferences.shared.hotkeyTrigger.displayName)
                DividerLine()
                helpKey("取消本次录音", value: "Esc")
                DividerLine()
                helpKey("胶囊确认插入", value: "点击右侧 ✓")
            }

            GlassSection(title: "常见问题", symbol: "questionmark.bubble") {
                helpFAQ(q: "全局快捷键没反应？", a: "确认「系统设置 → 隐私与安全 → 辅助功能」里 OpenLess 已勾选；首次授权之后必须完全退出再重启 App。")
                DividerLine()
                helpFAQ(q: "胶囊一直显示「演示」？", a: "缺少火山 ASR 凭据。到「火山 ASR」页面填入 APP ID + Access Token 即可。")
                DividerLine()
                helpFAQ(q: "插入失败 / 只复制到剪贴板？", a: "目标 App 不支持 AX 写入或粘贴模拟。OpenLess 会自动降级为复制到剪贴板，按 ⌘V 粘贴即可。")
            }

            GlassSection(title: "更多", symbol: "link") {
                helpLink(title: "GitHub 仓库", url: "https://github.com/baiqing/openless")
                DividerLine()
                helpLink(title: "提交问题或建议", url: "https://github.com/baiqing/openless/issues")
            }
        }
    }

    private func helpStep(num: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(num)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func helpKey(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.vertical, 9)
    }

    private func helpFAQ(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(q).font(.system(size: 14, weight: .semibold))
            Text(a).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }

    private func helpLink(title: String, url: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let parsed = URL(string: url) {
                Link(destination: parsed) {
                    Label(url, systemImage: "arrow.up.right.square")
                        .font(.callout)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 9)
    }
}
