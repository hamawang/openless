import SwiftUI
import OpenLessCore
import OpenLessPersistence

struct HistoryTab: View {
    @State private var sessions: [DictationSession] = []
    private let store = HistoryStore()

    var body: some View {
        SettingsPage(
            title: "历史",
            subtitle: "最近的识别结果只保存在本机。"
        ) {
            PrimaryActionRow {
                Button("刷新") { reload() }
                Button("清空") { store.clear(); reload() }
            }

            if sessions.isEmpty {
                ContentUnavailableView("还没有历史记录", systemImage: "clock", description: Text("完成一次语音输入后会显示在这里。"))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                GlassSection(title: "最近记录", symbol: "clock") {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { DividerLine() }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.createdAt, style: .time)
                                Text(session.mode.displayName)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(session.insertStatus.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(session.finalText)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        sessions = store.recent(limit: 100)
    }
}
