import SwiftData
import SwiftUI

/// 首页卡片跳转的目的地。
enum HomeDestination {
    case plan
    case vocabulary
    case tests
    case records
    case predictions(PredictionsView.Tab)
    case focus(ExamSkill)
}

/// 首页：一屏内的仪表盘。
/// - 宽屏（横屏）：顶部为学习概况条；左栏为主卡片、开始练习、近期机经；右栏为继续作答与学习趋势。
/// - 窄屏（竖屏）：主卡片、学习概况条、继续作答（横向）、开始练习、近期机经、学习趋势（并排）。
struct HomeView: View {
    var navigate: (HomeDestination) -> Void

    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Query(sort: \ExamDraft.updatedAt, order: .reverse) private var drafts: [ExamDraft]
    @Query(sort: \MockTest.updatedAt, order: .reverse) private var mocks: [MockTest]
    @Query(sort: \StudyPlan.createdAt, order: .reverse) private var plans: [StudyPlan]
    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @State private var recordedSpeaking = 0

    private let content = ContentStore.shared
    private let sectionSpacing: CGFloat = 22

    var body: some View {
        let statistics = PracticeStatistics(records: records)
        let activeMocks = mocks.filter { !$0.isFinished }
        let items = continueItems(activeMocks: Array(activeMocks.dropFirst()))
        let metrics = metrics(statistics)

        GeometryReader { proxy in
            let wide = proxy.size.width >= 860
            ScrollView {
                Group {
                    if wide {
                        VStack(alignment: .leading, spacing: 18) {
                            MetricStrip(metrics: metrics)
                            HStack(alignment: .top, spacing: 18) {
                                VStack(alignment: .leading, spacing: 18) {
                                    hero(activeMock: activeMocks.first)
                                    quickPractice(statistics)
                                    recentHits(bleed: false)
                                }
                                VStack(alignment: .leading, spacing: 14) {
                                    if !items.isEmpty {
                                        HomeSection("继续作答") {
                                            Card(padding: 0) {
                                                DividedRows(data: Array(items.prefix(3)), inset: 62) { item in
                                                    ContinueRow(item: item)
                                                }
                                            }
                                        }
                                    }
                                    ActivityCard(activity: statistics.activity(lastDays: 14))
                                    WeakKindsCard(kinds: Array(statistics.kindAccuracy.prefix(3)))
                                }
                                .frame(width: 300)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            hero(activeMock: activeMocks.first)
                            MetricStrip(metrics: metrics)
                            if !items.isEmpty {
                                HomeSection("继续作答") {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(items) { item in
                                                ContinueCard(item: item)
                                                    .frame(width: 330)
                                            }
                                        }
                                        .padding(.horizontal, Theme.pagePadding)
                                    }
                                    .padding(.horizontal, -Theme.pagePadding)
                                }
                            }
                            quickPractice(statistics)
                            recentHits(bleed: true)
                            HomeSection("学习趋势") {
                                MoreButton(title: "练习记录") { navigate(.records) }
                            } content: {
                                HStack(alignment: .top, spacing: 12) {
                                    ActivityCard(activity: statistics.activity(lastDays: 14))
                                    WeakKindsCard(kinds: Array(statistics.kindAccuracy.prefix(3)))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("首页")
        .task {
            recordedSpeaking = SpeakingAudio.recordedCount()
            if let plan = plans.first { StudyPlanGenerator.prepareToday(plan, in: modelContext) }
        }
    }

    // MARK: - 主卡片

    @ViewBuilder
    private func hero(activeMock: MockTest?) -> some View {
        if let plan = plans.first, plan.daysLeft >= 0, plan.dayCount > 0 {
            let schedule = StudyPlanGenerator.schedule(plan, records: records, mocks: mocks)
            PlanHeroCard(plan: plan, today: schedule.today,
                         progress: PlanProgress(plan: plan, days: schedule.days, records: records, mocks: mocks)) {
                navigate(.plan)
            }
        } else if let mock = activeMock, let test = content.test(mock.testID) {
            HeroCard(test: test, mock: mock, progress: TestProgress(test: test, records: records)) {
                launcher.mock(mock)
            }
        } else if let test = nextTest() {
            HeroCard(test: test, mock: nil, progress: TestProgress(test: test, records: records)) {
                launcher.startMock(test, context: modelContext)
            }
        }
    }

    /// 从最新一册开始，找到第一套还没有完成的试卷
    private func nextTest() -> PracticeTest? {
        let index = RecordIndex(records)
        let books = content.books.filter(\.isCambridge)
        for book in books {
            for test in book.tests where !TestProgress(test: test, index: index).isComplete {
                return test
            }
        }
        return books.first?.tests.first
    }

    // MARK: - 继续作答

    private func continueItems(activeMocks: [MockTest]) -> [ContinueItem] {
        let mockItems = activeMocks.map { mock -> ContinueItem in
            let test = content.test(mock.testID)
            let stages = test?.skills ?? []
            let done = stages.filter { mock.recordID(for: $0) != nil }.count
            return ContinueItem(
                id: "mock-\(mock.id.uuidString)",
                title: "\(test?.title ?? mock.testID) · 完整模考",
                subtitle: "进行到\(mock.stage.skill?.title ?? "")",
                updated: mock.updatedAt, symbol: "timer", tint: .indigo,
                fraction: stages.isEmpty ? 0 : Double(done) / Double(stages.count),
                resume: { launcher.mock(mock) },
                discard: {
                    let mockID = mock.id
                    drafts.filter { $0.mockID == mockID }.forEach(modelContext.delete)
                    modelContext.delete(mock)
                    try? modelContext.save()
                }
            )
        }
        // 题库里已经没有的题目（例如换了题库）不再显示
        let content = ContentStore.shared
        let available = drafts.filter { draft in
            draft.mockID == nil && draft.examIDList.allSatisfy { id in
                content.summary(for: id) != nil || content.listeningSection(for: id) != nil || content.writingItem(id) != nil
            }
        }
        let draftItems = available.map { draft -> ContinueItem in
            let ids = draft.examIDList
            let skill = ids.first.map(content.skill(of:)) ?? draft.skill
            let title: String = {
                if ids.count > 1, let test = ids.first.flatMap(content.test(containing:)) {
                    return "\(test.title) · 整套\(skill.title)"
                }
                return ids.map(content.displayTitle(for:)).joined(separator: " · ")
            }()
            let progress = skill == .writing
                ? "已写 \(draft.answered)/\(draft.totalQuestions) 篇"
                : "已答 \(draft.answered)/\(draft.totalQuestions)"
            return ContinueItem(
                id: draft.key,
                title: title,
                subtitle: "\(progress) · 用时 \(draft.elapsed.clockString)",
                updated: draft.updatedAt, symbol: skill.iconSymbol, tint: skill.tint,
                fraction: draft.totalQuestions > 0 ? Double(draft.answered) / Double(draft.totalQuestions) : 0,
                resume: { launcher.resume(draft) },
                discard: {
                    modelContext.delete(draft)
                    try? modelContext.save()
                }
            )
        }
        return mockItems + draftItems
    }

    // MARK: - 学习概况

    private func metrics(_ statistics: PracticeStatistics) -> [Metric] {
        let scored = records.filter { $0.skill != .writing }
        let listening = records.first { $0.skill == .listening && $0.band != nil }
        let reading = records.first { $0.skill == .reading && $0.band != nil }
        return [
            Metric(title: "最近听力", value: listening?.band ?? "—",
                   symbol: ExamSkill.listening.iconSymbol, tint: ExamSkill.listening.tint),
            Metric(title: "最近阅读", value: reading?.band ?? "—",
                   symbol: ExamSkill.reading.iconSymbol, tint: ExamSkill.reading.tint),
            Metric(title: "平均正确率",
                   value: scored.isEmpty ? "—" : PracticeStatistics(records: scored).accuracy.percentString,
                   symbol: "target", tint: .green),
            Metric(title: "连续练习", value: "\(statistics.streak) 天", symbol: "flame.fill", tint: .red),
        ]
    }

    // MARK: - 开始练习

    private func quickPractice(_ statistics: PracticeStatistics) -> some View {
        let practiced = statistics.practicedExamIDs
        let sections = content.listeningSections.map(\.section.id)
        let passages = content.readingPassages.map(\.id)
        let writing = content.writingItems
        let speaking = ExtrasStore.shared.speaking
        let speakingQuestions = speaking?.topics.reduce(0) { $0 + $1.questions.count } ?? 0
        let practicedSections = sections.filter(practiced.contains).count
        let practicedPassages = passages.filter(practiced.contains).count
        let written = writing.filter { practiced.contains($0.id) }.count

        return HomeSection("开始练习", detail: "点卡片浏览，点右上角随机练习") {
            HStack(spacing: 12) {
                if !sections.isEmpty {
                    SkillTile(title: "听力", symbol: ExamSkill.listening.iconSymbol, tint: ExamSkill.listening.tint,
                              done: practicedSections, total: sections.count, verb: "已练",
                              actionSymbol: "shuffle", actionLabel: "随机练习一个听力 Part") {
                        if let id = content.randomListeningSection(practiced: practiced) { launcher.listening([id]) }
                    } onBrowse: {
                        navigate(.focus(.listening))
                    }
                }
                SkillTile(title: "阅读", symbol: ExamSkill.reading.iconSymbol, tint: ExamSkill.reading.tint,
                          done: practicedPassages, total: passages.count, verb: "已练",
                          actionSymbol: "shuffle", actionLabel: "随机练习一篇阅读") {
                    let pool = content.readingPassages.filter { !practiced.contains($0.id) }
                    if let exam = (pool.isEmpty ? content.readingPassages : pool).randomElement() {
                        launcher.reading([exam.id])
                    }
                } onBrowse: {
                    navigate(.focus(.reading))
                }
                if !writing.isEmpty {
                    SkillTile(title: "写作", symbol: ExamSkill.writing.iconSymbol, tint: ExamSkill.writing.tint,
                              done: written, total: writing.count, verb: "已写",
                              actionSymbol: "shuffle", actionLabel: "随机写一篇 Task 2") {
                        let pool = writing.filter { $0.part == 2 && !practiced.contains($0.id) }
                        if let item = (pool.isEmpty ? writing.filter { $0.part == 2 } : pool).randomElement() {
                            launcher.writing([item.id])
                        }
                    } onBrowse: {
                        navigate(.focus(.writing))
                    }
                }
                if speakingQuestions > 0 {
                    SkillTile(title: "口语", symbol: "mic.fill", tint: Theme.speaking,
                              done: recordedSpeaking, total: speakingQuestions, verb: "已录",
                              actionSymbol: "arrow.right", actionLabel: "按考频练习口语") {
                        navigate(.predictions(.speaking))
                    } onBrowse: {
                        navigate(.predictions(.speaking))
                    }
                }
            }
        }
    }

    // MARK: - 近期机经

    @ViewBuilder
    private func recentHits(bleed: Bool) -> some View {
        let hits = ExtrasStore.shared.recentHits.filter { $0.skill != "writing" }
        if !hits.isEmpty {
            HomeSection("近期机经") {
                MoreButton { navigate(.predictions(.listening)) }
            } content: {
                let strip = ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(hits) { item in
                            NavigationLink(value: item) {
                                RecentHitCard(item: item)
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, bleed ? Theme.pagePadding : 0)
                }
                if bleed {
                    // 窄屏：横向列表延伸到屏幕边缘
                    strip.padding(.horizontal, -Theme.pagePadding)
                } else {
                    strip.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

// MARK: - 分区标题

/// 首页分区：紧凑标题 + 内容。
private struct HomeSection<Trailing: View, Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing.font(.subheadline)
            }
            .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

extension HomeSection where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, detail: detail, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - 主卡片

/// 首页主卡片：下一套推荐真题，或进行中的模考。
private struct HeroCard: View {
    let test: PracticeTest
    let mock: MockTest?
    let progress: TestProgress
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mock == nil ? "下一套真题" : "模考进行中")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(test.title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            HStack(spacing: 8) {
                ForEach(test.skills) { skill in
                    stage(skill)
                }
            }
            HStack(spacing: 10) {
                if test.canMock {
                    Button(action: action) {
                        Label(mock == nil ? "开始完整模考" : "继续模考", systemImage: "play.fill")
                    }
                    .buttonStyle(HeroButtonStyle())
                }
                NavigationLink(value: Route.test(test.id)) {
                    Text("分项练习")
                }
                .buttonStyle(HeroButtonStyle(prominent: false))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 104))
                .foregroundStyle(.white.opacity(0.1))
                .rotationEffect(.degrees(-12))
                .offset(x: 16, y: -16)
                .accessibilityHidden(true)
        }
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func stage(_ skill: ExamSkill) -> some View {
        HStack(spacing: 6) {
            Image(systemName: skill.iconSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(skill.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(stageText(skill))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stageText(_ skill: ExamSkill) -> String {
        if let mock {
            if mock.recordID(for: skill) != nil { return "已完成" }
            return mock.stage.skill == skill ? "进行中" : "待完成"
        }
        let item = progress(skill)
        if item.isStarted { return item.shortSummary(for: skill) }
        switch skill {
        case .listening: return "30 分钟"
        case .reading, .writing: return "60 分钟"
        }
    }
}

// MARK: - 备考计划

/// 有备考计划时的首页主卡片：倒计时、今天的进度和下一项任务。
private struct PlanHeroCard: View {
    let plan: StudyPlan
    let today: PlanDay?
    let progress: PlanProgress
    let onOpen: () -> Void

    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let done = today.map(progress.doneCount) ?? 0
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(today.map { "今天 · 第 \($0.index + 1) 天 · \($0.title)" } ?? "考试日")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if plan.daysLeft > 0 {
                            Text("距离考试")
                                .font(.title3.weight(.semibold))
                            Text("\(plan.daysLeft)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("天")
                                .font(.title3.weight(.semibold))
                        } else {
                            Text("今天考试，加油！")
                                .font(.system(.title, design: .rounded).weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                if let today {
                    ProgressRing(value: Double(done) / Double(max(today.tasks.count, 1)), tint: .white,
                                 size: 56, lineWidth: 6) {
                        Text("\(done)/\(today.tasks.count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("今天已完成 \(done)/\(today.tasks.count) 项")
                }
            }
            if let today, let next = progress.nextTask(today) {
                HStack(spacing: 10) {
                    Image(systemName: next.kind.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("下一项")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(next.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if today != nil {
                Label("今天的任务都完成了", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 10) {
                if let today, let next = progress.nextTask(today), next.kind.isTracked {
                    Button {
                        launcher.run(next, progress: progress, context: modelContext)
                    } label: {
                        Label(progress.status(next) == .todo ? "开始" : "继续", systemImage: "play.fill")
                    }
                    .buttonStyle(HeroButtonStyle())
                }
                Button(action: onOpen) {
                    Text("查看今日计划")
                }
                .buttonStyle(HeroButtonStyle(prominent: !(today.flatMap(progress.nextTask)?.kind.isTracked ?? false)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - 学习概况

private struct Metric: Identifiable {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var id: String { title }
}

/// 窄屏：一行四个指标。
private struct MetricStrip: View {
    let metrics: [Metric]

    var body: some View {
        Card(padding: 0) {
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 {
                        Divider().padding(.vertical, 12)
                    }
                    MetricCell(metric: metric)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct MetricCell: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: metric.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(metric.value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 继续作答

private struct ContinueItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let updated: Date
    let symbol: String
    let tint: Color
    let fraction: Double
    let resume: () -> Void
    let discard: () -> Void
}

/// 窄屏横向滚动的卡片。
private struct ContinueCard: View {
    let item: ContinueItem

    var body: some View {
        Card(padding: 14) {
            ContinueContent(item: item, ringSize: 42)
        }
        .contextMenu {
            Button("放弃作答", systemImage: "trash", role: .destructive, action: item.discard)
        }
    }
}

/// 宽屏右栏列表中的一行。
private struct ContinueRow: View {
    let item: ContinueItem

    var body: some View {
        ContinueContent(item: item, ringSize: 36)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contextMenu {
                Button("放弃作答", systemImage: "trash", role: .destructive, action: item.discard)
            }
    }
}

private struct ContinueContent: View {
    let item: ContinueItem
    let ringSize: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ProgressRing(value: item.fraction, tint: item.tint, size: ringSize, lineWidth: 4.5) {
                Image(systemName: item.symbol)
                    .font(.system(size: ringSize * 0.36, weight: .semibold))
                    .foregroundStyle(item.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Button(action: item.resume) {
                Image(systemName: "play.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(item.tint.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("继续 \(item.title)")
        }
    }
}

// MARK: - 开始练习

/// 科目方块：点按浏览，右上角按钮随机练习。
private struct SkillTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let done: Int
    let total: Int
    let verb: String
    let actionSymbol: String
    let actionLabel: String
    let action: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        Button(action: onBrowse) {
            VStack(alignment: .leading, spacing: 10) {
                TintedIcon(symbol: symbol, tint: tint, size: 36)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                ProgressView(value: total > 0 ? min(Double(done) / Double(total), 1) : 0)
                    .tint(tint)
                Text("\(verb) \(done)/\(total)")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .overlay(alignment: .topTrailing) {
            Button(action: action) {
                Image(systemName: actionSymbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(actionLabel)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 学习趋势

/// 近 14 天练习时长（紧凑图表）。
private struct ActivityCard: View {
    let activity: [PracticeStatistics.DayActivity]

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("近 14 天").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(activity.reduce(0) { $0 + $1.minutes }.rounded())) 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                DailyMinutesChart(activity: activity)
                    .frame(height: 96)
            }
        }
    }
}

private struct WeakKindsCard: View {
    let kinds: [PracticeStatistics.KindAccuracy]

    var body: some View {
        Card(padding: 14) {
            if kinds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("薄弱题型").font(.subheadline.weight(.semibold))
                    Text("完成练习后，这里会列出正确率最低的题型。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("薄弱题型").font(.subheadline.weight(.semibold))
                    ForEach(kinds) { item in
                        let color = AccuracyRing.color(for: item.accuracy)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.kind.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.accuracy.percentString)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(color)
                            }
                            ProgressView(value: item.accuracy)
                                .tint(color)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            }
        }
    }
}
