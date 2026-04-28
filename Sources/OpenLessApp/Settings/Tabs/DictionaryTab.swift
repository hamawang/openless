import SwiftUI
import OpenLessCore
import OpenLessPersistence

struct DictionaryTab: View {
    @State private var entries: [DictionaryEntry] = []
    @State private var editingEntry: DictionaryEntry?
    @State private var isShowingEditor = false
    @State private var input: String = ""
    @State private var hoveredID: UUID?
    @State private var showsClearConfirm = false
    private let store = DictionaryStore()

    var body: some View {
        SettingsPage(
            title: "词汇表",
            subtitle: "在识别前告诉模型可能出现的词——包括模型不认识的生词、新词或专业词汇。同时进入 ASR 热词与后期模型上下文。"
        ) {
            GlassSection(title: "易错词", symbol: "text.book.closed") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Spacer()
                        Button(action: resetHits) {
                            Label("重置统计", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                        .disabled(!hasHits)

                        Button(action: { showsClearConfirm = true }) {
                            Text("清除全部")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(entries.isEmpty)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        TextField("输入词语，每行一个…", text: $input, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)

                        Button(action: addFromInput) {
                            Label("添加", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(width: 92)
                    }

                    if entries.isEmpty {
                        Text("还没有词条。说一句包含 Claude、OpenLess 等词的话，或在上方批量输入即可。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else {
                        ChipFlow(spacing: 8, lineSpacing: 8) {
                            ForEach(entries) { entry in
                                DictionaryChip(
                                    entry: entry,
                                    hovered: hoveredID == entry.id,
                                    onHoverChanged: { isInside in
                                        if isInside {
                                            hoveredID = entry.id
                                        } else if hoveredID == entry.id {
                                            hoveredID = nil
                                        }
                                    },
                                    onTap: { beginEdit(entry) },
                                    onDelete: { delete(entry) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessDictionaryChanged)) { _ in reload() }
        .sheet(isPresented: $isShowingEditor) {
            DictionaryEditorSheet(entry: editingEntry) { entry in
                store.upsert(entry)
                NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
                reload()
            } onDelete: { id in
                store.delete(id: id)
                NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
                reload()
            }
        }
        .confirmationDialog("确定清除全部词汇？", isPresented: $showsClearConfirm, titleVisibility: .visible) {
            Button("清除全部", role: .destructive) {
                store.clearAll()
                NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可恢复。")
        }
    }

    private var hasHits: Bool {
        entries.contains { $0.hitCount > 0 }
    }

    private func reload() {
        // 命中次数高的排前面，没用过的按更新时间倒序。
        entries = store.all().sorted { lhs, rhs in
            if lhs.hitCount != rhs.hitCount { return lhs.hitCount > rhs.hitCount }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func beginEdit(_ entry: DictionaryEntry) {
        editingEntry = entry
        isShowingEditor = true
    }

    private func delete(_ entry: DictionaryEntry) {
        if hoveredID == entry.id { hoveredID = nil }
        store.delete(id: entry.id)
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        reload()
    }

    private func addFromInput() {
        let lines = input.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        var seen = Set(entries.map { $0.trimmedPhrase.lowercased() })
        for phrase in lines {
            let key = phrase.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            store.upsert(DictionaryEntry(phrase: phrase, source: .manual))
        }
        input = ""
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        reload()
    }

    private func resetHits() {
        store.resetHits()
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        reload()
    }
}

struct DictionaryChip: View {
    let entry: DictionaryEntry
    let hovered: Bool
    let onHoverChanged: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 6) {
                Text(entry.phrase)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Text("\(entry.hitCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
            )
            .opacity(entry.enabled ? 1 : 0.55)
            .contentShape(Capsule())
            .onTapGesture(perform: onTap)

            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Color.secondary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("删除")
                .offset(x: 5, y: -5)
                .transition(.opacity)
            }
        }
        .onHover(perform: onHoverChanged)
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

/// 自适应折行布局：把一组 chip 平铺并按行宽自动 wrap。
struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + lineSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct DictionaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void
    let onDelete: (UUID) -> Void
    @State private var phrase: String
    @State private var category: DictionaryEntryCategory
    @State private var notes: String
    @State private var enabled: Bool

    init(
        entry: DictionaryEntry?,
        onSave: @escaping (DictionaryEntry) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onDelete = onDelete
        _phrase = State(initialValue: entry?.phrase ?? "")
        _category = State(initialValue: entry?.category ?? .aiTool)
        _notes = State(initialValue: entry?.notes ?? "")
        _enabled = State(initialValue: entry?.enabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry == nil ? "新建词条" : "编辑词条")
                    .font(.system(size: 24, weight: .semibold))
                Text("把 Claude、OpenLess、内部项目名等模型可能写错的词放进来。它会进入 ASR 热词与后期模型上下文，整句语义匹配时自动修正。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                SettingsRow(title: "标准词") {
                    TextField("Claude", text: $phrase)
                        .textFieldStyle(.roundedBorder)
                }
                DividerLine()
                SettingsRow(title: "分类") {
                    Picker("分类", selection: $category) {
                        ForEach(DictionaryEntryCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                }
                DividerLine()
                SettingsRow(title: "启用") {
                    Toggle("用于 ASR 热词和后期语义判断", isOn: $enabled)
                        .toggleStyle(.checkbox)
                }
                DividerLine()
                SettingsRow(title: "备注") {
                    TextField("例如：AI 产品名，模型可按语义判断是否需要修正", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .glassPanel(cornerRadius: 20)

            HStack {
                if let entry {
                    Button("删除") {
                        onDelete(entry.id)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(DictionaryEntry(
                        id: entry?.id ?? UUID(),
                        phrase: trimmed,
                        category: category,
                        notes: notes,
                        enabled: enabled,
                        source: entry?.source ?? .manual,
                        createdAt: entry?.createdAt ?? Date()
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 560)
    }
}
