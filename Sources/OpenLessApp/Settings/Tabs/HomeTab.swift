import SwiftUI
import OpenLessCore
import OpenLessPersistence

struct HomeTab: View {
    @State private var sessions: [DictationSession] = []
    @State private var dictionaryEntries: [DictionaryEntry] = []
    private let history = HistoryStore()
    private let dictionary = DictionaryStore()

    var body: some View {
        SettingsPage(
            title: "首页",
            subtitle: "用个人输入记录展示口述时长、总字数、平均每分钟字数和节省时间。"
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                MetricTile(title: "口述时长", value: formattedDuration(totalSpeakingSeconds), symbol: "waveform")
                MetricTile(title: "总字数", value: "\(totalCharacters) 字", symbol: "number")
                MetricTile(title: "平均每分钟", value: "\(Int(spokenCharsPerMinute.rounded())) 字", symbol: "speedometer")
                MetricTile(title: "估算节省", value: formattedDuration(savedTypingSeconds), symbol: "keyboard.badge.clock")
                MetricTile(title: "速度提升", value: String(format: "%.1fx", speedLift), symbol: "bolt.fill")
                MetricTile(title: "启用词条", value: "\(enabledDictionaryCount) 个", symbol: "text.book.closed")
            }

            GlassSection(title: "最近效果", symbol: "sparkles") {
                if sessions.isEmpty {
                    Text("完成几次语音输入后，这里会展示口述速度、节省打字时间和词汇表建议记录。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(sessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { DividerLine() }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.createdAt, style: .time)
                                Text(session.mode.displayName)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let durationMs = session.durationMs {
                                    Text(formattedDuration(Double(durationMs) / 1000))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(session.finalText)
                                .lineLimit(2)
                            if (session.dictionaryEntryCount ?? 0) > 0 {
                                Text("后期模型已参考 \(session.dictionaryEntryCount ?? 0) 个词汇表词条进行语义判断")
                                    .font(.footnote)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
            }

            GlassSection(title: "词汇表展示", symbol: "text.book.closed") {
                if dictionaryEntries.isEmpty {
                    Text("添加 Claude、OpenLess、内部项目名等正确词后，OpenLess 会把它们注入 ASR 热词和后期模型上下文，由模型根据整句语义自动判断是否需要修正。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(dictionaryEntries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { DividerLine() }
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.phrase)
                                    .font(.headline)
                                Text(entry.source.displayName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }

            GlassSection(title: "今日概览", symbol: "chart.bar.xaxis") {
                MiniUsageChart(values: chartValues)
                    .padding(.vertical, 6)
            }

            GlassSection(title: "风格", symbol: "paintpalette") {
                HStack(spacing: 12) {
                    Image(systemName: UserPreferences.shared.polishEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(UserPreferences.shared.polishEnabled ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(UserPreferences.shared.polishEnabled ? UserPreferences.shared.polishMode.displayName : "已关闭")
                            .font(.system(size: 14, weight: .semibold))
                        Text(UserPreferences.shared.polishEnabled
                             ? polishModeHint(UserPreferences.shared.polishMode)
                             : "识别后会直接插入原文，不调用 Ark 润色。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear { reload() }
    }

    private var totalCharacters: Int {
        sessions.reduce(0) { $0 + $1.finalText.count }
    }

    private var totalSpeakingSeconds: Double {
        let actual = sessions.compactMap(\.durationMs).reduce(0, +)
        if actual > 0 { return Double(actual) / 1000 }
        return Double(totalCharacters) / 240 * 60
    }

    private var savedTypingSeconds: Double {
        max(0, estimatedTypingSeconds - totalSpeakingSeconds)
    }

    private var estimatedTypingSeconds: Double {
        Double(totalCharacters) / 90 * 60
    }

    private var spokenCharsPerMinute: Double {
        guard totalSpeakingSeconds > 0 else { return 0 }
        return Double(totalCharacters) / totalSpeakingSeconds * 60
    }

    private var speedLift: Double {
        guard totalSpeakingSeconds > 0 else { return 0 }
        return estimatedTypingSeconds / totalSpeakingSeconds
    }

    private var chartValues: [Double] {
        let recent = Array(sessions.prefix(7).reversed()).map { Double(max($0.finalText.count, 1)) }
        let maxCount = recent.max() ?? 1
        return recent.isEmpty ? Array(repeating: 0.18, count: 7) : recent.map { $0 / maxCount }
    }

    private var enabledDictionaryCount: Int {
        dictionaryEntries.filter(\.enabled).count
    }

    private func reload() {
        sessions = history.recent(limit: 100)
        dictionaryEntries = dictionary.all()
    }

    private func formattedDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds.rounded())) 秒"
        }
        return String(format: "%.1f 分钟", seconds / 60)
    }
}
