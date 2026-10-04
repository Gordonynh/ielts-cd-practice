import SwiftData
import SwiftUI

/// 专项练习：阅读按 Passage / 题型，听力按 Part / 题型，写作按 Task 与题目类型。
struct FocusPracticeView: View {
    @Binding var skill: ExamSkill

    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Query private var favorites: [FavoriteExam]
    @Environment(ExamLauncher.self) private var launcher

    private let content = ContentStore.shared
    private let kindColumns = [GridItem(.adaptive(minimum: 160), spacing: Theme.gridSpacing)]

    var body: some View {
        DashboardPage {
            switch skill {
            case .reading: readingSections
            case .listening: listeningSections
            case .writing: writingSections
            }
        }
        .navigationTitle("专项练习")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("科目", selection: $skill) {
                    ForEach([ExamSkill.listening, .reading, .writing]) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }

    // MARK: - 阅读

    @ViewBuilder
    private var readingSections: some View {
        let tint = ExamSkill.reading.tint
        let passages = content.readingPassages
        let statistics = PracticeStatistics(records: records.filter { $0.skill == .reading })
        let accuracy = Dictionary(statistics.kindAccuracy.map { ($0.kind, $0.accuracy) }, uniquingKeysWith: { first, _ in first })
        let mistakes = passages.filter { statistics.examBest[$0.id]?.hasMistakes == true }.count
        let favoriteIDs = Set(favorites.map(\.examId))

        DashboardSection("按 Passage") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing), count: 3),
                      spacing: Theme.gridSpacing) {
                ForEach(ExamCategory.allCases) { category in
                    let pool = passages.filter { $0.category == category }
                    let practiced = pool.filter { statistics.practicedExamIDs.contains($0.id) }
                    PartCard(badge: category.shortTitle, title: category.title, subtitle: category.subtitle,
                             practiced: practiced.count, total: pool.count, unit: "篇", tint: tint,
                             route: .passages(PassageFilter(title: category.title, category: category))) {
                        let fresh = pool.filter { !statistics.practicedExamIDs.contains($0.id) }
                        if let exam = (fresh.isEmpty ? pool : fresh).randomElement() { launcher.reading([exam.id]) }
                    }
                }
            }
        }

        DashboardSection("按题型", subtitle: "百分比为你的正确率") {
            LazyVGrid(columns: kindColumns, spacing: Theme.gridSpacing) {
                ForEach(kinds(in: passages.flatMap(\.questionKinds))) { kind in
                    let count = passages.filter { $0.questionKinds.contains(kind) }.count
                    NavigationLink(value: Route.passages(PassageFilter(title: kind.title, kind: kind))) {
                        FocusCard(symbol: kind.symbol, title: kind.title, subtitle: "\(count) 篇",
                                  accuracy: accuracy[kind], tint: tint)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }

        DashboardSection("复习") {
            LazyVGrid(columns: Theme.tileColumns, spacing: Theme.gridSpacing) {
                NavigationLink(value: Route.passages(PassageFilter(title: "阅读错题", status: .mistakes))) {
                    FocusCard(symbol: "xmark.circle.fill", title: "错题", subtitle: "\(mistakes) 篇有错题", tint: .red)
                }
                .buttonStyle(CardButtonStyle())
                NavigationLink(value: Route.passages(PassageFilter(title: "收藏的篇目", status: .favorites))) {
                    FocusCard(symbol: "star.fill", title: "收藏",
                              subtitle: "\(passages.filter { favoriteIDs.contains($0.id) }.count) 篇", tint: .yellow)
                }
                .buttonStyle(CardButtonStyle())
                NavigationLink(value: Route.passages(PassageFilter(title: "全部阅读"))) {
                    FocusCard(symbol: "books.vertical.fill", title: "全部阅读", subtitle: "\(passages.count) 篇", tint: tint)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    // MARK: - 听力

    @ViewBuilder
    private var listeningSections: some View {
        let tint = ExamSkill.listening.tint
        let sections = content.listeningSections
        let statistics = PracticeStatistics(records: records.filter { $0.skill == .listening })
        let accuracy = Dictionary(statistics.kindAccuracy.map { ($0.kind, $0.accuracy) }, uniquingKeysWith: { first, _ in first })
        let mistakes = sections.filter { statistics.examBest[$0.section.id]?.hasMistakes == true }.count
        let subtitles = [1: "生活场景对话，以表格、笔记填空为主", 2: "生活场景独白，常见地图、单选、配对",
                         3: "学术讨论，以单选、配对为主", 4: "学术讲座，以笔记填空为主"]

        DashboardSection("按 Part") {
            LazyVGrid(columns: Theme.tileColumns, spacing: Theme.gridSpacing) {
                ForEach(1...4, id: \.self) { part in
                    let pool = sections.filter { $0.section.part == part }.map(\.section.id)
                    let practiced = pool.filter(statistics.practicedExamIDs.contains)
                    PartCard(badge: "Part \(part)", title: "Part \(part)", subtitle: subtitles[part] ?? "",
                             practiced: practiced.count, total: pool.count, unit: "个", tint: tint,
                             route: .sections(SectionFilter(title: "听力 Part \(part)", part: part))) {
                        let fresh = pool.filter { !statistics.practicedExamIDs.contains($0) }
                        if let id = (fresh.isEmpty ? pool : fresh).randomElement() { launcher.listening([id]) }
                    }
                }
            }
        }

        DashboardSection("按题型", subtitle: "百分比为你的正确率") {
            LazyVGrid(columns: kindColumns, spacing: Theme.gridSpacing) {
                ForEach(kinds(in: sections.flatMap(\.section.questionKinds))) { kind in
                    let count = sections.filter { $0.section.questionKinds.contains(kind) }.count
                    NavigationLink(value: Route.sections(SectionFilter(title: "听力 · \(kind.title)", kind: kind))) {
                        FocusCard(symbol: kind.symbol, title: kind.title, subtitle: "\(count) 个 Part",
                                  accuracy: accuracy[kind], tint: tint)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }

        DashboardSection("复习") {
            LazyVGrid(columns: Theme.tileColumns, spacing: Theme.gridSpacing) {
                NavigationLink(value: Route.sections(SectionFilter(title: "听力错题", status: .mistakes))) {
                    FocusCard(symbol: "xmark.circle.fill", title: "错题", subtitle: "\(mistakes) 个 Part 有错题", tint: .red)
                }
                .buttonStyle(CardButtonStyle())
                NavigationLink(value: Route.sections(SectionFilter(title: "全部听力"))) {
                    FocusCard(symbol: "headphones", title: "全部听力", subtitle: "\(sections.count) 个 Part", tint: tint)
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    // MARK: - 写作

    @ViewBuilder
    private var writingSections: some View {
        let tint = ExamSkill.writing.tint
        let items = content.writingItems
        let attempts = writingAttempts(records)
        let task1 = items.filter { $0.part == 1 }
        let task2 = items.filter { $0.part == 2 }
        let task1Categories = WritingTaskItem.task1Categories.filter { category in task1.contains { $0.category == category } }
        let task2Categories = orderedCategories(task2.filter { $0.source == .jijing })
        let symbols = ["线图": "chart.xyaxis.line", "柱状图": "chart.bar.fill", "饼图": "chart.pie.fill", "混合图": "chart.bar.xaxis",
                       "图表": "chart.line.uptrend.xyaxis", "表格": "tablecells", "地图": "map.fill", "流程图": "arrow.triangle.branch"]

        DashboardSection("Task 1", subtitle: "图表作文 · 20 分钟 · 150 词") {
            LazyVGrid(columns: kindColumns, spacing: Theme.gridSpacing) {
                NavigationLink(value: Route.writingTasks(WritingFilter(title: "Task 1", part: 1))) {
                    FocusCard(symbol: "square.grid.2x2.fill", title: "全部 Task 1", subtitle: written(task1, attempts), tint: tint)
                }
                .buttonStyle(CardButtonStyle())
                ForEach(task1Categories, id: \.self) { category in
                    let pool = task1.filter { $0.category == category }
                    NavigationLink(value: Route.writingTasks(WritingFilter(title: "Task 1 · \(category)", part: 1, category: category))) {
                        FocusCard(symbol: symbols[category] ?? "chart.bar", title: category, subtitle: written(pool, attempts), tint: tint)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }

        DashboardSection("Task 2", subtitle: "议论文 · 40 分钟 · 250 词") {
            LazyVGrid(columns: kindColumns, spacing: Theme.gridSpacing) {
                NavigationLink(value: Route.writingTasks(WritingFilter(title: "Task 2", part: 2))) {
                    FocusCard(symbol: "square.grid.2x2.fill", title: "全部 Task 2", subtitle: written(task2, attempts), tint: tint)
                }
                .buttonStyle(CardButtonStyle())
                ForEach(task2Categories, id: \.self) { category in
                    let pool = task2.filter { $0.category == category }
                    NavigationLink(value: Route.writingTasks(WritingFilter(title: "Task 2 · \(category)", part: 2, category: category))) {
                        FocusCard(symbol: "text.bubble.fill", title: category, subtitle: written(pool, attempts), tint: tint)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }
    }

    // MARK: - Helpers

    private func kinds(in all: [QuestionKind]) -> [QuestionKind] {
        let present = Set(all)
        return QuestionKind.allCases.filter { $0 != .other && present.contains($0) }
    }

    private func written(_ items: [WritingTaskItem], _ attempts: [String: Int]) -> String {
        "\(items.count) 道 · 已写 \(items.filter { (attempts[$0.id] ?? 0) > 0 }.count)"
    }

    private func orderedCategories(_ items: [WritingTaskItem]) -> [String] {
        var counts: [String: Int] = [:]
        for item in items where !item.category.isEmpty { counts[item.category, default: 0] += 1 }
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }
}

/// Passage / Part 卡片：进度、浏览（点按卡片）与随机练习（右上角按钮）。
private struct PartCard: View {
    let badge: String
    let title: String
    let subtitle: String
    let practiced: Int
    let total: Int
    let unit: String
    let tint: Color
    let route: Route
    let onRandom: () -> Void

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                PartBadge(text: badge, large: true, tint: tint)
                    .frame(height: 34, alignment: .leading)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                ProgressView(value: total > 0 ? Double(practiced) / Double(total) : 0)
                    .tint(tint)
                HStack {
                    Text("已练 \(practiced)/\(total) \(unit)")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Chevron()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .overlay(alignment: .topTrailing) {
            Button(action: onRandom) {
                Image(systemName: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("随机练习 \(title)")
        }
        .accessibilityElement(children: .contain)
    }
}

/// 题型 / 话题卡片。
private struct FocusCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    var accuracy: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(height: 26)
                Spacer()
                if let accuracy {
                    Text(accuracy.percentString)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AccuracyRing.color(for: accuracy))
                }
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
