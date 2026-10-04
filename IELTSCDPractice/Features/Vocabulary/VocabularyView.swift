import AVFoundation
import SwiftData
import SwiftUI

struct VocabularyView: View {
    @Query(sort: \VocabEntry.addedAt, order: .reverse) private var entries: [VocabEntry]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PreferenceKey.dailyNewWords) private var dailyNewWords = 10
    @State private var searchText = ""
    @State private var reviewing = false

    private var dueEntries: [VocabEntry] {
        let now = Date()
        return entries.filter { $0.due <= now }.sorted { $0.due < $1.due }
    }

    private var filtered: [VocabEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.word.localizedCaseInsensitiveContains(searchText) || $0.meaning.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                Section {
                    reviewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                NavigationLink {
                    CoreWordListView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("雅思核心词表")
                            Text("\(ContentStore.shared.loadCoreWords().count) 个雅思词汇（ECDICT），按词频排序")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "text.book.closed.fill").foregroundStyle(.tint)
                    }
                }
            }

            Section {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "生词本是空的" : "没有匹配的单词", systemImage: "character.book.closed")
                    } description: {
                        Text(searchText.isEmpty ? "在练习中选中单词并点“加入生词本”，或从核心词表添加。" : "换个关键词试试。")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { entry in
                        NavigationLink {
                            WordDetailView(entry: entry)
                        } label: {
                            WordRow(entry: entry)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(modelContext.delete)
                        try? modelContext.save()
                    }
                }
            } header: {
                Text("我的生词（\(entries.count)）")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("生词本")
        .searchable(text: $searchText, prompt: "搜索单词或释义")
        .toolbar {
            EditButton().disabled(entries.isEmpty)
        }
        .fullScreenCover(isPresented: $reviewing) {
            ReviewSessionView(queue: dueEntries)
        }
    }

    private var reviewCard: some View {
        let due = dueEntries
        let newCount = due.filter(\.isNew).count
        let mastered = entries.filter(\.isMastered).count
        return Card {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日复习")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 22) {
                        counter("待复习", due.count - newCount, .orange)
                        counter("新词", newCount, .blue)
                        counter("已掌握", mastered, .green)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        reviewing = true
                    } label: {
                        Label("开始复习", systemImage: "rectangle.on.rectangle.angled")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(due.isEmpty)
                    Button {
                        addNewWords()
                    } label: {
                        Label("添加 \(dailyNewWords) 个新词", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func counter(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addNewWords() {
        let existing = Set(entries.map(\.word))
        let words = ContentStore.shared.loadCoreWords()
            .filter { !existing.contains($0.word.lowercased()) }
            .prefix(dailyNewWords)
        for word in words {
            modelContext.insert(VocabEntry(word: word.word.lowercased(), meaning: word.meaning,
                                           context: word.example, source: "ielts-core"))
        }
        try? modelContext.save()
    }
}

struct WordRow: View {
    let entry: VocabEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.word).font(.headline)
                    if !entry.phonetic.isEmpty {
                        Text("/\(entry.phonetic)/").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text(entry.meaning.replacingOccurrences(of: "\n", with: "；"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if entry.isMastered {
                TagLabel(text: "已掌握", color: .green)
            } else if entry.isNew {
                TagLabel(text: "新词", color: .blue)
            } else {
                Text(entry.due <= Date() ? "待复习" : "下次 " + entry.due.formatted(.dateTime.month().day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WordDetailView: View {
    @Bindable var entry: VocabEntry
    @State private var dictionary: DictionaryEntry?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.word).font(.largeTitle.weight(.bold))
                        if !(dictionary?.phonetic ?? entry.phonetic).isEmpty {
                            Text("/\(dictionary?.phonetic ?? entry.phonetic)/").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    SpeakButton(text: entry.word)
                }
                .padding(.vertical, 6)
            }
            Section("释义") {
                TextField("中文释义", text: $entry.meaning, axis: .vertical)
                if let definition = dictionary?.definition, !definition.isEmpty {
                    Text(definition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !entry.context.isEmpty {
                Section("原文语境") {
                    Text(highlighted(entry.context, word: entry.word))
                }
            }
            Section("记忆进度") {
                LabeledContent("复习次数", value: "\(entry.reps)")
                LabeledContent("遗忘次数", value: "\(entry.lapses)")
                LabeledContent("下次复习", value: entry.due.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("加入时间", value: entry.addedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationTitle(entry.word)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            dictionary = await DictionaryService.shared.lookup(entry.word)
            if entry.phonetic.isEmpty, let phonetic = dictionary?.phonetic { entry.phonetic = phonetic }
        }
    }
}

func highlighted(_ sentence: String, word: String) -> AttributedString {
    var attributed = AttributedString(sentence)
    if let range = attributed.range(of: word, options: .caseInsensitive) {
        attributed[range].font = .body.weight(.semibold)
        attributed[range].foregroundColor = .accentColor
    }
    return attributed
}

/// 系统语音朗读（英式发音）。
struct SpeakButton: View {
    let text: String

    var body: some View {
        Button {
            Speaker.shared.speak(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title2)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("朗读")
    }
}

final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
