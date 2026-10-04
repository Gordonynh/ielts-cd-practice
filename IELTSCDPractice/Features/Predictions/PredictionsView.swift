import SwiftData
import SwiftUI

/// 机经预测：听力、阅读、写作、口语的近期考题与重考数据。
struct PredictionsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case listening, reading, writing, speaking
        var id: String { rawValue }
        var title: String {
            switch self {
            case .listening: "听力"
            case .reading: "阅读"
            case .writing: "写作"
            case .speaking: "口语"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent, retest, hardest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent: "最近考到"
            case .retest: "重考次数"
            case .hardest: "正确率（低→高）"
            }
        }
    }

    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Binding var tab: Tab
    @State private var sort: Sort = .recent
    @State private var part: Int?
    @State private var category: ExamCategory?
    @State private var writingPart = 2
    @State private var speakingPart = 1
    @State private var searchText = ""

    private let extras = ExtrasStore.shared
    private let content = ContentStore.shared

    var body: some View {
        List {
            switch tab {
            case .listening: listening
            case .reading: reading
            case .writing: writing
            case .speaking: speaking
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !extras.isAvailable && tab != .reading {
                ContentUnavailableView("没有机经数据", systemImage: "flame",
                                       description: Text("请先导入题库包的扩展数据（scripts/build-extras.mjs）。"))
            }
        }
        .navigationTitle("机经预测")
        .searchable(text: $searchText, prompt: "搜索标题、话题或题目")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("科目", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if extras.isAvailable {
                    NavigationLink(value: Route.recalls) {
                        Label("考试回忆", systemImage: "calendar")
                    }
                }
                if tab != .speaking {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(Sort.allCases.filter { tab == .writing ? $0 != .hardest : true }) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onChange(of: tab) {
            part = nil
            if sort == .hardest && tab == .writing { sort = .recent }
        }
    }

    // MARK: - 听力

    @ViewBuilder
    private var listening: some View {
        recentHits(skill: "listening")
        Section {
            Picker("Part", selection: $part) {
                Text("全部").tag(Int?.none)
                ForEach(1...4, id: \.self) { Text("Part \($0)").tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        let items = sorted(extras.items(skill: .listening).filter { (part == nil || $0.part == part) && matches($0) })
        Section {
            ForEach(items) { item in
                NavigationLink(value: item) { JijingRow(item: item) }
            }
        } header: {
            Text("\(items.count) 道听力机经")
        } footer: {
            Text("点开可查看出现过的考试与题目回忆截图。")
        }
    }

    // MARK: - 阅读

    @ViewBuilder
    private var reading: some View {
        recentHits(skill: "reading")
        Section {
            Picker("Passage", selection: $category) {
                Text("全部").tag(ExamCategory?.none)
                ForEach(ExamCategory.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        let statistics = PracticeStatistics(records: records.filter { $0.skill == .reading })
        let passages = sortedPassages(content.readingPassages.filter { exam in
            extras.jijing(forContent: exam.id) != nil && (category == nil || exam.category == category) && exam.matches(searchText)
        })
        if !passages.isEmpty {
            Section {
                ForEach(passages) { exam in
                    NavigationLink(value: Route.passage(exam.id)) {
                        ReadingPassageRow(exam: exam, best: statistics.examBest[exam.id])
                    }
                }
            } header: {
                Text("题库中考到过的文章 · \(passages.count) 篇")
            } footer: {
                Text("与近期机经对应的题库文章；火焰图标为重考次数。")
            }
        }
        let others = sorted(extras.items(skill: .reading).filter { item in
            item.match == nil && (category == nil || item.part == category?.part) && matches(item)
        })
        if !others.isEmpty {
            Section {
                ForEach(others) { item in
                    NavigationLink(value: item) { JijingRow(item: item) }
                }
            } header: {
                Text("其他机经 · 暂无完整题目")
            }
        }
    }

    // MARK: - 写作

    @ViewBuilder
    private var writing: some View {
        Section {
            Picker("Task", selection: $writingPart) {
                Text("Task 1").tag(1)
                Text("Task 2").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        let attempts = writingAttempts(records)
        let items = sortedWriting(content.writingItems.filter {
            $0.source == .jijing && $0.part == writingPart && $0.matches(searchText)
        })
        Section {
            ForEach(items) { item in
                NavigationLink(value: Route.writingTask(item.id)) {
                    WritingTaskRow(item: item, attempts: attempts[item.id] ?? 0)
                }
            }
        } header: {
            Text("\(items.count) 道 Task \(writingPart) 机经")
        } footer: {
            if writingPart == 1 { Text("机经 Task 1 只有题目文字，没有原题图表。") }
        }
    }

    // MARK: - 口语

    @ViewBuilder
    private var speaking: some View {
        let bank = extras.speaking
        Section {
            Picker("Part", selection: $speakingPart) {
                Text("Part 1").tag(1)
                Text("Part 2 & 3").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        if speakingPart == 1, searchText.isEmpty, let examiner = bank?.examiner, !examiner.isEmpty {
            Section {
                NavigationLink(value: Route.examiner) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("考官开场与流程用语")
                            Text("\(examiner.count) 句，熟悉考场节奏").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.wave.2")
                    }
                }
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let topics = (bank?.topics ?? []).filter { topic in
            topic.part == speakingPart && (query.isEmpty || topic.name.localizedCaseInsensitiveContains(query)
                || topic.questions.contains { $0.text.localizedCaseInsensitiveContains(query) })
        }
        .sorted { $0.recentExamCount > $1.recentExamCount }
        Section {
            ForEach(topics) { topic in
                if topic.questions.isEmpty {
                    SpeakingTopicRow(topic: topic)
                } else {
                    NavigationLink(value: Route.speakingTopic(topic.id)) {
                        SpeakingTopicRow(topic: topic)
                    }
                }
            }
        } header: {
            Text("\(bank?.season ?? "本季") · \(topics.count) 个话题")
        } footer: {
            Text("按近期考试出现次数排序。")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func recentHits(skill: String) -> some View {
        let hits = extras.recentHits.filter { $0.skill == skill }
        if searchText.isEmpty, !hits.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(hits) { item in
                            NavigationLink(value: item) {
                                RecentHitCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("近期命中")
            }
        }
    }

    private func matches(_ item: JijingItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
            || item.topic.localizedCaseInsensitiveContains(query)
    }

    private func sorted(_ items: [JijingItem]) -> [JijingItem] {
        switch sort {
        case .recent: items.sorted { ($0.lastHitDate ?? "", $0.retestCount) > ($1.lastHitDate ?? "", $1.retestCount) }
        case .retest: items.sorted { ($0.retestCount, $0.lastHitDate ?? "") > ($1.retestCount, $1.lastHitDate ?? "") }
        case .hardest: items.sorted { ($0.correctRate ?? 101) < ($1.correctRate ?? 101) }
        }
    }

    private func sortedWriting(_ items: [WritingTaskItem]) -> [WritingTaskItem] {
        items.sorted { lhs, rhs in
            switch sort {
            case .retest: (lhs.jijing?.retestCount ?? 0) > (rhs.jijing?.retestCount ?? 0)
            default: (lhs.jijing?.lastHitDate ?? "", lhs.jijing?.retestCount ?? 0) > (rhs.jijing?.lastHitDate ?? "", rhs.jijing?.retestCount ?? 0)
            }
        }
    }

    /// 机经阅读：有考情数据的排在前面，其余按出现频率
    private func sortedPassages(_ passages: [ExamSummary]) -> [ExamSummary] {
        let rank: [ExamFrequency: Int] = [.high: 0, .medium: 1, .low: 2]
        return passages.sorted { lhs, rhs in
            let left = extras.jijing(forContent: lhs.id)
            let right = extras.jijing(forContent: rhs.id)
            switch (left, right) {
            case let (l?, r?):
                return sort == .retest ? l.retestCount > r.retestCount : (l.lastHitDate ?? "") > (r.lastHitDate ?? "")
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (rank[lhs.frequency] ?? 3, lhs.category.part) < (rank[rhs.frequency] ?? 3, rhs.category.part)
            }
        }
    }
}
