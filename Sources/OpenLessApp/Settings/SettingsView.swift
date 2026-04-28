import AppKit
import SwiftUI
import OpenLessCore
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder
import OpenLessASR
import OpenLessPolish

// 设置窗口的根入口：导航枚举 + 模型 + 主分发。
// 共享组件、侧边栏、各 Tab、遗留 Tab、通知名都在同目录其他文件里。

enum OpenLessMainTab: String, CaseIterable, Identifiable {
    case home
    case history
    case dictionary
    case polish
    case help
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .history: return "历史记录"
        case .dictionary: return "词汇表"
        case .polish: return "风格"
        case .help: return "帮助中心"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "chart.line.uptrend.xyaxis"
        case .history: return "clock"
        case .dictionary: return "text.book.closed"
        case .polish: return "paintpalette"
        case .help: return "questionmark.circle"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: OpenLessMainTab

    init(selection: OpenLessMainTab = .home) {
        self.selection = selection
    }
}

struct SettingsView: View {
    @ObservedObject private var navigation: SettingsNavigationModel

    init(navigation: SettingsNavigationModel) {
        self.navigation = navigation
    }

    var body: some View {
        HStack(spacing: 14) {
            FixedSidebar(selection: $navigation.selection)
            Group {
                switch navigation.selection {
                case .home: HomeTab()
                case .history: HistoryTab()
                case .dictionary: DictionaryTab()
                case .polish: StyleTab()
                case .help: HelpTab()
                case .settings: SettingsHubTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 右栏顶部留点空白，避免内容贴到 title bar 区域。
            .padding(.top, 12)
        }
        // 左/下/右用相等 12pt；上方为 0，让侧边栏顶边贴窗口顶，
        // 红绿灯（系统画在 title bar 层）就自然落在侧边栏的圆角矩形内部。
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .background(WindowCanvasBackground())
        .frame(minWidth: 1040, minHeight: 700)
    }
}
