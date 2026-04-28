import AppKit
import SwiftUI
import OpenLessCore
import OpenLessPersistence

// 侧边栏：固定列表 + 今日概览 + 连接状态 + 键盘快捷键脚注。
// 容器圆角 22pt 与系统窗口外角 ~10pt 形成"放大同心"。

struct FixedSidebar: View {
    @Binding var selection: OpenLessMainTab
    @State private var stats = SidebarStatsSnapshot.load()
    private let sidebarShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("OpenLess")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("自然说话，完美书写")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            // 顶部内卡片预留 36pt：让 OpenLess 标题落在红绿灯下方。
            .padding(.top, 36)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 8) {
                        ForEach(OpenLessMainTab.allCases) { tab in
                            Button {
                                selection = tab
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: tab.symbol)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(selection == tab ? Color.blue : .secondary)
                                        .frame(width: 22)
                                    Text(tab.title)
                                        .font(.system(size: 14, weight: selection == tab ? .semibold : .regular))
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(selection == tab ? .primary : .secondary)
                                .background(
                                    selection == tab ? Color.blue.opacity(0.10) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .help(tab.title)
                        }
                    }

                    SidebarUsageCard(stats: stats)
                    SidebarConnectionCard(stats: stats)

                    VStack(alignment: .leading, spacing: 7) {
                        Label("右 Option 开始录音", systemImage: "keyboard")
                        Label("Esc 取消", systemImage: "escape")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 264)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(sidebarShape)
        .glassPanel(cornerRadius: 22)
        .contentShape(sidebarShape)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessHistoryChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessDictionaryChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessCredentialsChanged)) { _ in refresh() }
    }

    private func refresh() {
        stats = SidebarStatsSnapshot.load()
    }
}

struct WindowCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.035),
                    Color.clear,
                    Color.accentColor.opacity(0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct SidebarUsageCard: View {
    let stats: SidebarStatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("今日概览", systemImage: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stats.sessionCountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            MiniUsageChart(values: stats.chartValues)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SidebarMetricBox(title: "时长", value: stats.durationText, symbol: "waveform")
                SidebarMetricBox(title: "总字数", value: "\(stats.totalCharacters)", symbol: "number")
                SidebarMetricBox(title: "每分钟", value: "\(stats.charactersPerMinute)", symbol: "speedometer")
                SidebarMetricBox(title: "词条", value: "\(stats.dictionaryCount)", symbol: "text.book.closed")
            }
        }
        .padding(13)
        .glassPanel(cornerRadius: 20)
    }
}

struct SidebarConnectionCard: View {
    let stats: SidebarStatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SidebarConnectionRow(title: "ASR", detail: stats.hasVolcCredentials ? "已配置" : "待配置", ok: stats.hasVolcCredentials)
            SidebarConnectionRow(title: "润色", detail: stats.hasArkCredentials ? "已配置" : "原文兜底", ok: stats.hasArkCredentials)
        }
        .padding(13)
        .glassPanel(cornerRadius: 20)
    }
}

struct SidebarMetricBox: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .glassPanel(cornerRadius: 15)
    }
}

struct SidebarConnectionRow: View {
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(ok ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 13)
    }
}

struct MiniUsageChart: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(height: max(8, 44 * value))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(height: 66)
        .glassPanel(cornerRadius: 15)
    }
}

struct SidebarStatsSnapshot {
    let totalSeconds: Double
    let totalCharacters: Int
    let charactersPerMinute: Int
    let dictionaryCount: Int
    let hasVolcCredentials: Bool
    let hasArkCredentials: Bool
    let chartValues: [Double]
    let sessionCount: Int

    var durationText: String {
        if totalSeconds < 60 {
            return "\(Int(totalSeconds.rounded())) 秒"
        }
        return String(format: "%.1f 分", totalSeconds / 60)
    }

    var sessionCountText: String {
        "\(sessionCount) 次"
    }

    static func load() -> SidebarStatsSnapshot {
        let sessions = HistoryStore().recent(limit: 100)
        let totalCharacters = sessions.reduce(0) { $0 + $1.finalText.count }
        let actualMs = sessions.compactMap(\.durationMs).reduce(0, +)
        let totalSeconds = actualMs > 0 ? Double(actualMs) / 1000 : Double(totalCharacters) / 240 * 60
        let charactersPerMinute = totalSeconds > 0 ? Int((Double(totalCharacters) / totalSeconds * 60).rounded()) : 0
        let recentCounts = Array(sessions.prefix(7).reversed()).map { Double(max($0.finalText.count, 1)) }
        let maxCount = recentCounts.max() ?? 1
        let chartValues = recentCounts.isEmpty ? Array(repeating: 0.18, count: 7) : recentCounts.map { $0 / maxCount }
        let vault = CredentialsVault.shared

        return SidebarStatsSnapshot(
            totalSeconds: totalSeconds,
            totalCharacters: totalCharacters,
            charactersPerMinute: charactersPerMinute,
            dictionaryCount: DictionaryStore().enabledEntries().count,
            hasVolcCredentials: isFilled(vault.get(CredentialAccount.volcengineAppKey)) && isFilled(vault.get(CredentialAccount.volcengineAccessKey)),
            hasArkCredentials: isFilled(vault.get(CredentialAccount.arkApiKey)),
            chartValues: chartValues,
            sessionCount: sessions.count
        )
    }
}
