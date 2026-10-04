import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, plan, tests, predictions, focus, records, vocabulary, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .plan: "备考计划"
        case .tests: "剑桥真题"
        case .predictions: "机经预测"
        case .focus: "专项练习"
        case .records: "练习记录"
        case .vocabulary: "生词本"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .plan: "calendar.badge.clock"
        case .tests: "books.vertical"
        case .predictions: "flame"
        case .focus: "scope"
        case .records: "chart.xyaxis.line"
        case .vocabulary: "character.book.closed"
        case .settings: "gearshape"
        }
    }
}

/// 详情页路由（统一在根导航栈注册，避免各页面重复声明）。
enum Route: Hashable {
    case test(String)
    case passage(String)
    case writingTask(String)
    case passages(PassageFilter)
    case sections(SectionFilter)
    case writingTasks(WritingFilter)
    case mock(UUID)
    case speakingTopic(String)
    case examiner
    case recalls
}

struct RootView: View {
    @State private var selection: AppSection? = .home
    @State private var path = NavigationPath()
    @State private var launcher = ExamLauncher()
    @State private var predictionsTab: PredictionsView.Tab = .listening
    @State private var focusSkill: ExamSkill = .reading
    @Environment(\.modelContext) private var modelContext
    @Query private var words: [VocabEntry]
    @Query(sort: \StudyPlan.createdAt, order: .reverse) private var plans: [StudyPlan]

    private var dueWords: Int {
        let now = Date()
        return words.filter { $0.due <= now }.count
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(AppSection.home.title, systemImage: AppSection.home.symbol)
                    .tag(AppSection.home)
                Label(AppSection.plan.title, systemImage: AppSection.plan.symbol)
                    .badge(planBadge)
                    .tag(AppSection.plan)
                Section("题库") {
                    ForEach([AppSection.tests, .predictions, .focus]) { section in
                        Label(section.title, systemImage: section.symbol).tag(section)
                    }
                }
                Section("我的") {
                    Label(AppSection.records.title, systemImage: AppSection.records.symbol)
                        .tag(AppSection.records)
                    Label(AppSection.vocabulary.title, systemImage: AppSection.vocabulary.symbol)
                        .badge(dueWords)
                        .tag(AppSection.vocabulary)
                    Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                        .tag(AppSection.settings)
                }
            }
            .navigationTitle("IELTS CD Practice")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch selection ?? .home {
                    case .home: HomeView(navigate: navigate)
                    case .plan: PlanView(navigate: navigate)
                    case .tests: TestLibraryView()
                    case .predictions: PredictionsView(tab: $predictionsTab)
                    case .focus: FocusPracticeView(skill: $focusSkill)
                    case .records: RecordsView()
                    case .vocabulary: VocabularyView()
                    case .settings: SettingsView()
                    }
                }
                .navigationDestination(for: Route.self, destination: destination)
                .navigationDestination(for: PracticeRecord.self) { RecordDetailView(record: $0) }
                .navigationDestination(for: JijingItem.self) { JijingDetailView(item: $0) }
                .navigationDestination(for: ExamRecall.self) { ExamRecallDetailView(exam: $0) }
            }
            .id(selection)
        }
        .environment(launcher)
        .fullScreenCover(item: $launcher.session) { session in
            ExamScreen(session: session) { mockID in
                launcher.finishedMockID = mockID
            }
        }
        .sheet(item: Binding(get: { launcher.finishedMockID.map(MockSheetItem.init) },
                             set: { launcher.finishedMockID = $0?.id })) { item in
            NavigationStack {
                MockResultView(mockID: item.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { launcher.finishedMockID = nil }
                        }
                    }
            }
            .environment(launcher)
            .pageSheetSizing()
        }
        .onAppear {
            AppSchema.migrateLegacyEssays(in: modelContext)
            if let plan = plans.first { StudyPlanGenerator.prepareToday(plan, in: modelContext) }
        }
    }

    /// 侧边栏「备考计划」旁显示剩余天数
    private var planBadge: Text? {
        guard let plan = plans.first, plan.daysLeft >= 0 else { return nil }
        return Text(plan.daysLeft == 0 ? "今天" : "\(plan.daysLeft) 天")
    }

    private func navigate(_ destination: HomeDestination) {
        switch destination {
        case .plan:
            selection = .plan
        case .vocabulary:
            selection = .vocabulary
        case .tests:
            selection = .tests
        case .records:
            selection = .records
        case .predictions(let tab):
            predictionsTab = tab
            selection = .predictions
        case .focus(let skill):
            focusSkill = skill
            selection = .focus
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .test(let id):
            if let test = ContentStore.shared.test(id) { TestDetailView(test: test) } else { missing }
        case .passage(let id):
            if let exam = ContentStore.shared.summary(for: id) { ExamDetailView(exam: exam) } else { missing }
        case .writingTask(let id):
            if let item = ContentStore.shared.writingItem(id) { WritingTaskDetailView(item: item) } else { missing }
        case .passages(let filter):
            PassageListView(filter: filter)
        case .sections(let filter):
            SectionListView(filter: filter)
        case .writingTasks(let filter):
            WritingTaskListView(filter: filter)
        case .mock(let id):
            MockResultView(mockID: id)
        case .speakingTopic(let id):
            if let topic = ExtrasStore.shared.speaking?.topics.first(where: { $0.id == id }) {
                SpeakingTopicView(topic: topic)
            } else { missing }
        case .examiner:
            ExaminerScriptView(lines: ExtrasStore.shared.speaking?.examiner ?? [])
        case .recalls:
            ExamRecallView()
        }
    }

    private var missing: some View {
        ContentUnavailableView("找不到题目", systemImage: "questionmark.folder")
    }
}

private struct MockSheetItem: Identifiable {
    let id: UUID
}

private extension View {
    /// iPad 上以接近整页的尺寸显示成绩单
    @ViewBuilder
    func pageSheetSizing() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
