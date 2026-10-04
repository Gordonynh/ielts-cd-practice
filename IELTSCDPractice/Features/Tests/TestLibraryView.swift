import SwiftData
import SwiftUI

/// 一套题某个科目的完成情况。
struct SkillProgress {
    var practiced = 0
    var total = 0
    /// 成绩最好的一次整套练习（含模考）
    var bestFull: PracticeRecord?

    var isStarted: Bool { practiced > 0 }
    var isComplete: Bool { bestFull != nil || (total > 0 && practiced >= total) }

    /// 完成比例（做过整套即为 1）
    var fraction: Double {
        if bestFull != nil { return 1 }
        return total > 0 ? Double(practiced) / Double(total) : 0
    }

    /// 「32/40 · 7.5」「已练 2/4」「未练」「已写 1/2」
    func summary(for skill: ExamSkill) -> String {
        if skill == .writing {
            return practiced > 0 ? "已写 \(practiced)/\(total)" : "未写"
        }
        if let best = bestFull {
            return "\(best.score)/\(best.total)" + (best.band.map { " · \($0)" } ?? "")
        }
        return practiced > 0 ? "已练 \(practiced)/\(total)" : "未练"
    }

    /// 圆环下方的简短文字：Band、「2/4」或科目名
    func shortSummary(for skill: ExamSkill) -> String {
        if let best = bestFull {
            return best.band ?? "\(best.score)/\(best.total)"
        }
        return practiced > 0 ? "\(practiced)/\(total)" : skill.title
    }
}

/// 练习记录按题目 ID 建立的索引（避免为每套题重复解析记录）。
struct RecordIndex {
    let entries: [(ids: Set<String>, record: PracticeRecord)]

    init(_ records: [PracticeRecord]) {
        entries = records.map { (Set($0.examIDList), $0) }
    }
}

struct TestProgress {
    private var skills: [ExamSkill: SkillProgress] = [:]

    init(test: PracticeTest, records: [PracticeRecord]) {
        self.init(test: test, index: RecordIndex(records))
    }

    init(test: PracticeTest, index: RecordIndex) {
        for skill in test.skills {
            let ids = test.ids(for: skill)
            let idSet = Set(ids)
            var practiced = Set<String>()
            var best: PracticeRecord?
            for entry in index.entries where !idSet.isDisjoint(with: entry.ids) {
                practiced.formUnion(idSet.intersection(entry.ids))
                if entry.record.kind == .fullTest, entry.ids == idSet, skill != .writing,
                   best == nil || entry.record.score > best!.score {
                    best = entry.record
                }
            }
            skills[skill] = SkillProgress(practiced: practiced.count, total: ids.count, bestFull: best)
        }
    }

    func callAsFunction(_ skill: ExamSkill) -> SkillProgress {
        skills[skill] ?? SkillProgress()
    }

    var isComplete: Bool { !skills.isEmpty && skills.values.allSatisfy(\.isComplete) }
    var isStarted: Bool { skills.values.contains(where: \.isStarted) }
}

/// 剑桥真题：按书分组的试卷卡片。
struct TestLibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, unfinished, finished
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部试卷"
            case .unfinished: "未完成"
            case .finished: "已完成"
            }
        }
    }

    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Query(sort: \MockTest.updatedAt, order: .reverse) private var mocks: [MockTest]
    @State private var searchText = ""
    @State private var filter: Filter = .all

    private let content = ContentStore.shared

    var body: some View {
        let index = RecordIndex(records)
        let activeMocks = Set(mocks.filter { !$0.isFinished }.map(\.testID))
        let sections = content.books.compactMap { book -> BookSection? in
            let all = book.tests.map { ($0, TestProgress(test: $0, index: index)) }
            let visible = all.filter { test, progress in
                guard test.matches(searchText) else { return false }
                switch filter {
                case .all: return true
                case .unfinished: return !progress.isComplete
                case .finished: return progress.isComplete
                }
            }
            return visible.isEmpty ? nil : BookSection(book: book, tests: visible,
                                                       completed: all.filter { $0.1.isComplete }.count)
        }

        DashboardPage {
            ForEach(sections) { section in
                DashboardSection(title: section.book.title,
                                 subtitle: section.book.isCambridge ? nil : "模拟题") {
                    Text("已完成 \(section.completed)/\(section.book.tests.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } content: {
                    LazyVGrid(columns: Theme.tileColumns, spacing: Theme.gridSpacing) {
                        ForEach(section.tests, id: \.0.id) { test, progress in
                            NavigationLink(value: Route.test(test.id)) {
                                TestCard(test: test, progress: progress, mockInProgress: activeMocks.contains(test.id))
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                }
            }
        }
        .overlay {
            if content.books.isEmpty {
                ContentUnavailableView("没有题库", systemImage: "books.vertical",
                                       description: Text("请先导入题库包（见 README）。"))
            } else if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("剑桥真题")
        .searchable(text: $searchText, prompt: "搜索试卷、文章或话题")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("显示", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("筛选", systemImage: filter == .all
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }
}

private struct BookSection: Identifiable {
    let book: TestBook
    let tests: [(PracticeTest, TestProgress)]
    let completed: Int
    var id: String { book.id }
}

/// 试卷卡片：标题、文章主题与三个科目的进度圆环。
private struct TestCard: View {
    let test: PracticeTest
    let progress: TestProgress
    let mockInProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(test.shortTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(.label))
                Spacer(minLength: 4)
                if mockInProgress {
                    TagLabel(text: "模考中", color: .orange)
                } else if progress.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("已完成")
                }
            }
            Text(test.reading.map(\.title).joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 0) {
                ForEach(test.skills) { skill in
                    SkillRingColumn(skill: skill, progress: progress(skill))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// 科目进度圆环 + 简短成绩。
struct SkillRingColumn: View {
    let skill: ExamSkill
    let progress: SkillProgress
    var size: CGFloat = 42

    var body: some View {
        VStack(spacing: 6) {
            ProgressRing(value: progress.fraction, tint: skill.tint, size: size, lineWidth: size * 0.11) {
                Image(systemName: skill.iconSymbol)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(progress.isStarted ? skill.tint : Color(.tertiaryLabel))
            }
            Text(progress.shortSummary(for: skill))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(progress.isStarted ? Color(.label) : Color(.tertiaryLabel))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skill.title)：\(progress.summary(for: skill))")
    }
}
