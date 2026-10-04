import SwiftData
import SwiftUI

// MARK: - 阅读篇目

/// 阅读篇目列表（按 Passage、题型、来源、练习状态筛选）。
struct PassageListView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case standard, hot, accuracy, recent, title
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: "默认顺序"
            case .hot: "机经热度"
            case .accuracy: "正确率（低→高）"
            case .recent: "最近练习"
            case .title: "标题"
            }
        }
    }

    @State var filter: PassageFilter
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Query private var favorites: [FavoriteExam]
    @Query private var drafts: [ExamDraft]
    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var sort: Sort = .standard

    private let content = ContentStore.shared

    var body: some View {
        let statistics = PracticeStatistics(records: records)
        let favoriteIDs = Set(favorites.map(\.examId))
        let draftIDs = Set(drafts.filter { $0.kind == .practice && $0.mockID == nil }.flatMap(\.examIDList))
        let exams = filtered(statistics: statistics, favorites: favoriteIDs)
        List {
            Section {
                ForEach(exams) { exam in
                    NavigationLink(value: Route.passage(exam.id)) {
                        ReadingPassageRow(exam: exam, best: statistics.examBest[exam.id],
                                          isFavorite: favoriteIDs.contains(exam.id), hasDraft: draftIDs.contains(exam.id))
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            toggleFavorite(exam.id, isFavorite: favoriteIDs.contains(exam.id))
                        } label: {
                            Label(favoriteIDs.contains(exam.id) ? "取消收藏" : "收藏",
                                  systemImage: favoriteIDs.contains(exam.id) ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button { launcher.reading([exam.id]) } label: { Label("开始练习", systemImage: "play") }
                        Button { launcher.study(exam.id) } label: { Label("背题模式", systemImage: "book") }
                    }
                }
            } header: {
                if !exams.isEmpty { Text("\(exams.count) 篇") }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if exams.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle(filter.title)
        .searchable(text: $searchText, prompt: "搜索标题或中文名")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    let practiced = statistics.practicedExamIDs
                    let pool = exams.filter { !practiced.contains($0.id) }
                    if let exam = (pool.isEmpty ? exams : pool).randomElement() { launcher.reading([exam.id]) }
                } label: {
                    Label("随机一篇", systemImage: "shuffle")
                }
                .disabled(exams.isEmpty)
                Menu {
                    Picker("来源", selection: $filter.source) {
                        Text("全部来源").tag(ExamSource?.none)
                        ForEach(ExamSource.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("Passage", selection: $filter.category) {
                        Text("全部 Passage").tag(ExamCategory?.none)
                        ForEach(ExamCategory.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("练习状态", selection: $filter.status) {
                        ForEach(PracticeStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label("筛选", systemImage: filter.source == nil && filter.status == .all
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("排序", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func filtered(statistics: PracticeStatistics, favorites: Set<String>) -> [ExamSummary] {
        var exams = content.readingPassages.filter { exam in
            (filter.category == nil || exam.category == filter.category)
                && (filter.source == nil || exam.examSource == filter.source)
                && (filter.kind == nil || exam.questionKinds.contains(filter.kind!))
                && exam.matches(searchText)
        }
        switch filter.status {
        case .all: break
        case .unpracticed: exams = exams.filter { statistics.examBest[$0.id] == nil }
        case .practiced: exams = exams.filter { statistics.examBest[$0.id] != nil }
        case .mistakes: exams = exams.filter { statistics.examBest[$0.id]?.hasMistakes == true }
        case .favorites: exams = exams.filter { favorites.contains($0.id) }
        }
        let extras = ExtrasStore.shared
        switch sort {
        case .standard: break
        case .hot:
            exams.sort { (extras.jijing(forContent: $0.id)?.retestCount ?? -1) > (extras.jijing(forContent: $1.id)?.retestCount ?? -1) }
        case .accuracy:
            exams.sort { (statistics.examBest[$0.id]?.bestAccuracy ?? 2) < (statistics.examBest[$1.id]?.bestAccuracy ?? 2) }
        case .recent:
            exams.sort {
                (statistics.examBest[$0.id]?.lastPracticed ?? .distantPast) > (statistics.examBest[$1.id]?.lastPracticed ?? .distantPast)
            }
        case .title:
            exams.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return exams
    }

    private func toggleFavorite(_ examID: String, isFavorite: Bool) {
        if isFavorite {
            try? modelContext.delete(model: FavoriteExam.self, where: #Predicate { $0.examId == examID })
        } else {
            modelContext.insert(FavoriteExam(examId: examID))
        }
        try? modelContext.save()
    }
}

// MARK: - 听力 Part

/// 听力 Part 列表（按 Part、题型、练习状态筛选），点按即开始练习。
struct SectionListView: View {
    @State var filter: SectionFilter
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Query private var drafts: [ExamDraft]
    @Environment(ExamLauncher.self) private var launcher
    @State private var searchText = ""

    private let content = ContentStore.shared

    var body: some View {
        let statistics = PracticeStatistics(records: records)
        let draftIDs = Set(drafts.filter { $0.kind == .practice && $0.mockID == nil }.flatMap(\.examIDList))
        let items = filtered(statistics: statistics)
        List {
            Section {
                ForEach(items, id: \.section.id) { test, section in
                    Button {
                        if let draft = drafts.first(where: { $0.key == ExamSession.draftKey(kind: .practice, examIDs: [section.id]) }) {
                            launcher.resume(draft)
                        } else {
                            launcher.listening([section.id])
                        }
                    } label: {
                        ListeningSectionRow(test: test, section: section, best: statistics.examBest[section.id],
                                            hasDraft: draftIDs.contains(section.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { launcher.listening([section.id]) } label: { Label("开始练习", systemImage: "play") }
                        Button { launcher.study([section.id]) } label: { Label("背题模式", systemImage: "book") }
                    }
                }
            } header: {
                if !items.isEmpty { Text("\(items.count) 个 Part") }
            } footer: {
                if !items.isEmpty { Text("点按即开始练习，长按可进入背题模式。") }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if items.isEmpty { ContentUnavailableView.search(text: searchText) }
        }
        .navigationTitle(filter.title)
        .searchable(text: $searchText, prompt: "搜索试卷或话题")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    let practiced = statistics.practicedExamIDs
                    let pool = items.filter { !practiced.contains($0.section.id) }
                    if let item = (pool.isEmpty ? items : pool).randomElement() { launcher.listening([item.section.id]) }
                } label: {
                    Label("随机一个 Part", systemImage: "shuffle")
                }
                .disabled(items.isEmpty)
                Menu {
                    Picker("Part", selection: $filter.part) {
                        Text("全部 Part").tag(Int?.none)
                        ForEach(1...4, id: \.self) { Text("Part \($0)").tag(Optional($0)) }
                    }
                    Picker("练习状态", selection: $filter.status) {
                        ForEach(PracticeStatus.allCases.filter { $0 != .favorites }) {
                            Label($0.title, systemImage: $0.symbol).tag($0)
                        }
                    }
                } label: {
                    Label("筛选", systemImage: filter.status == .all
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    private func filtered(statistics: PracticeStatistics) -> [(test: ListeningTest, section: ListeningTest.Section)] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return content.listeningSections.filter { test, section in
            guard filter.part == nil || section.part == filter.part else { return false }
            guard filter.kind == nil || section.questionKinds.contains(filter.kind!) else { return false }
            guard query.isEmpty || test.title.localizedCaseInsensitiveContains(query)
                    || section.topic.localizedCaseInsensitiveContains(query) else { return false }
            switch filter.status {
            case .all, .favorites: return true
            case .unpracticed: return statistics.examBest[section.id] == nil
            case .practiced: return statistics.examBest[section.id] != nil
            case .mistakes: return statistics.examBest[section.id]?.hasMistakes == true
            }
        }
    }
}

// MARK: - 写作题目

struct WritingTaskListView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case standard, recent, retest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: "默认顺序"
            case .recent: "最近考到"
            case .retest: "重考次数"
            }
        }
    }

    @State var filter: WritingFilter
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @State private var searchText = ""
    @State private var onlyWithEssay = false
    @State private var sort: Sort = .standard

    var body: some View {
        let attempts = writingAttempts(records)
        let items = filtered()
        List {
            Section {
                ForEach(items) { item in
                    NavigationLink(value: Route.writingTask(item.id)) {
                        WritingTaskRow(item: item, attempts: attempts[item.id] ?? 0)
                    }
                }
            } header: {
                if !items.isEmpty { Text("\(items.count) 道题目") }
            } footer: {
                if filter.part == 1, items.contains(where: { $0.source == .jijing }) {
                    Text("机经 Task 1 只有题目文字，没有原题图表；剑桥真题的 Task 1 附有图表。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if items.isEmpty { ContentUnavailableView.search(text: searchText) }
        }
        .navigationTitle(filter.title)
        .searchable(text: $searchText, prompt: "搜索题目")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("来源", selection: $filter.source) {
                        Text("全部来源").tag(WritingTaskItem.Source?.none)
                        Text("剑桥真题").tag(Optional(WritingTaskItem.Source.cambridge))
                        Text("机经").tag(Optional(WritingTaskItem.Source.jijing))
                    }
                    Toggle("只看附范文的题目", isOn: $onlyWithEssay)
                } label: {
                    Label("筛选", systemImage: filter.source == nil && !onlyWithEssay
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("排序", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func filtered() -> [WritingTaskItem] {
        var items = ContentStore.shared.writingItems.filter { item in
            item.part == filter.part
                && (filter.category == nil || item.category == filter.category)
                && (filter.source == nil || item.source == filter.source)
                && (!onlyWithEssay || item.essay != nil)
                && item.matches(searchText)
        }
        switch sort {
        case .standard: break
        case .recent:
            items.sort { ($0.jijing?.lastHitDate ?? "", $0.jijing?.retestCount ?? 0) > ($1.jijing?.lastHitDate ?? "", $1.jijing?.retestCount ?? 0) }
        case .retest:
            items.sort { ($0.jijing?.retestCount ?? 0) > ($1.jijing?.retestCount ?? 0) }
        }
        return items
    }
}

/// 每道写作题的完成次数
func writingAttempts(_ records: [PracticeRecord]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for record in records where record.skill == .writing {
        for id in record.examIDList { counts[id, default: 0] += 1 }
    }
    return counts
}
