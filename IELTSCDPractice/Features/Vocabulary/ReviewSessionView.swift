import SwiftData
import SwiftUI

/// 闪卡复习：先回忆，再翻面评分。
struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var queue: [VocabEntry]
    @State private var revealed = false
    @State private var reviewedCount = 0
    @State private var dictionary: DictionaryEntry?
    private let initialCount: Int

    init(queue: [VocabEntry]) {
        _queue = State(initialValue: queue)
        initialCount = queue.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                ProgressView(value: Double(reviewedCount), total: Double(max(initialCount, 1)))
                    .padding(.horizontal, 40)

                if let entry = queue.first {
                    card(for: entry)
                        .id(entry.word)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                    controls(for: entry)
                } else {
                    ContentUnavailableView {
                        Label("今日复习完成", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("本次复习了 \(reviewedCount) 个单词。")
                    } actions: {
                        Button("完成") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("复习 \(min(reviewedCount + 1, initialCount))/\(initialCount)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("结束") { dismiss() }
                }
            }
            .task(id: queue.first?.word) {
                guard let word = queue.first?.word else { return }
                dictionary = await DictionaryService.shared.lookup(word)
            }
        }
    }

    private func card(for entry: VocabEntry) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.word)
                    .font(.system(size: 46, weight: .bold, design: .serif))
                SpeakButton(text: entry.word)
            }
            let phonetic = entry.phonetic.isEmpty ? (dictionary?.phonetic ?? "") : entry.phonetic
            if !phonetic.isEmpty {
                Text("/\(phonetic)/").font(.title3).foregroundStyle(.secondary)
            }
            if !entry.context.isEmpty {
                Text(highlighted(entry.context, word: entry.word))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            if revealed {
                Divider().padding(.horizontal, 60)
                Text(entry.meaning.isEmpty ? (dictionary?.translation ?? "暂无释义") : entry.meaning)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(28)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 32)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        }
    }

    @ViewBuilder
    private func controls(for entry: VocabEntry) -> some View {
        if revealed {
            HStack(spacing: 12) {
                ForEach(ReviewGrade.allCases) { grade in
                    Button {
                        rate(entry, grade)
                    } label: {
                        VStack(spacing: 4) {
                            Text(grade.title).font(.headline)
                            Text(VocabScheduler.label(for: VocabScheduler.preview(entry, grade: grade)))
                                .font(.caption)
                                .opacity(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint(for: grade))
                }
            }
            .padding(.horizontal, 32)
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { revealed = true }
            } label: {
                Text("显示释义").frame(maxWidth: 320, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    private func rate(_ entry: VocabEntry, _ grade: ReviewGrade) {
        VocabScheduler.apply(grade, to: entry)
        try? modelContext.save()
        withAnimation(.snappy) {
            queue.removeFirst()
            if grade == .again {
                queue.insert(entry, at: min(3, queue.count))
            } else {
                reviewedCount += 1
            }
            revealed = false
        }
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

struct CoreWordListView: View {
    @Query private var entries: [VocabEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var words: [CoreWord] = []

    var body: some View {
        let existing = Set(entries.map(\.word))
        let filtered = searchText.isEmpty ? words : words.filter {
            $0.word.localizedCaseInsensitiveContains(searchText) || $0.meaning.contains(searchText)
        }
        List(filtered) { word in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(word.word).font(.headline)
                    Text(word.meaning).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if existing.contains(word.word.lowercased()) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("已在生词本")
                } else {
                    Button {
                        modelContext.insert(VocabEntry(word: word.word.lowercased(), meaning: word.meaning,
                                                       context: word.example, source: "ielts-core"))
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("加入生词本")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("雅思核心词表")
        .searchable(text: $searchText, prompt: "搜索单词或释义")
        .task {
            if words.isEmpty { words = ContentStore.shared.loadCoreWords() }
        }
    }
}
