import SwiftData
import SwiftUI

/// 一套试题：完整模考、听力 / 阅读 / 写作分项练习、音频下载与练习记录。
struct TestDetailView: View {
    let test: PracticeTest

    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var allRecords: [PracticeRecord]
    @Query private var drafts: [ExamDraft]
    @Query(sort: \MockTest.startedAt, order: .reverse) private var allMocks: [MockTest]
    @State private var audio = AudioStore.shared
    @State private var confirmAbandon: MockTest?
    @State private var confirmDeleteAudio = false

    private var records: [PracticeRecord] {
        let ids = Set(test.listeningIDs + test.readingIDs + test.writingIDs)
        return allRecords.filter { !ids.isDisjoint(with: $0.examIDList) }
    }

    private var mocks: [MockTest] { allMocks.filter { $0.testID == test.id } }
    private var activeMock: MockTest? { mocks.first { !$0.isFinished } }

    private func draft(_ ids: [String]) -> ExamDraft? {
        let kind: PracticeKind = ids.count > 1 ? .fullTest : .practice
        let key = ExamSession.draftKey(kind: kind, examIDs: ids)
        return drafts.first { $0.key == key }
    }

    var body: some View {
        let records = records
        let statistics = PracticeStatistics(records: records)
        let progress = TestProgress(test: test, records: records)
        GeometryReader { proxy in
            // 横屏分两栏：左栏为概览、模考、写作，右栏为听力、阅读
            let wide = proxy.size.width >= 860
            ScrollView {
                VStack(alignment: .leading, spacing: wide ? 20 : Theme.sectionSpacing) {
                    if wide {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 18) {
                                summary(progress)
                                if test.canMock { mockSection }
                                if !test.writing.isEmpty { writingCard(records: records) }
                            }
                            VStack(alignment: .leading, spacing: 18) {
                                if let listening = test.listening {
                                    listeningCard(listening, statistics: statistics)
                                }
                                if !test.reading.isEmpty { readingCard(statistics: statistics) }
                            }
                        }
                    } else {
                        summary(progress)
                        if test.canMock { mockSection }
                        if let listening = test.listening {
                            listeningCard(listening, statistics: statistics)
                        }
                        if !test.reading.isEmpty { readingCard(statistics: statistics) }
                        if !test.writing.isEmpty { writingCard(records: records) }
                    }
                    history(records)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(test.title)
        .confirmationDialog("放弃这次模考？", isPresented: Binding(
            get: { confirmAbandon != nil }, set: { if !$0 { confirmAbandon = nil } }
        ), titleVisibility: .visible) {
            Button("放弃模考", role: .destructive) {
                if let mock = confirmAbandon { abandon(mock) }
            }
        } message: {
            Text("已完成部分的成绩会保留在练习记录中。")
        }
        .confirmationDialog("删除这套听力的音频？", isPresented: $confirmDeleteAudio, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let listening = test.listening { audio.delete(listening) }
            }
        } message: {
            Text("删除后仍可联网在线播放。")
        }
    }

    // MARK: - 练习记录

    private func history(_ records: [PracticeRecord]) -> some View {
        DashboardSection("练习记录") {
            if records.isEmpty {
                Card {
                    Text("还没有练习过这套题")
                        .foregroundStyle(.secondary)
                }
            } else {
                Card(padding: 0) {
                    DividedRows(data: Array(records.prefix(10))) { record in
                        NavigationLink(value: record) {
                            HStack(spacing: 10) {
                                RecordRow(record: record, showTitle: true)
                                Chevron()
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - 概览

    private func summary(_ progress: TestProgress) -> some View {
        HStack(spacing: Theme.gridSpacing) {
            ForEach(test.skills) { skill in
                Card(padding: 14) {
                    HStack(spacing: 12) {
                        ProgressRing(value: progress(skill).fraction, tint: skill.tint, size: 44, lineWidth: 5) {
                            Image(systemName: skill.iconSymbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(skill.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(progress(skill).summary(for: skill))
                                .font(.headline)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 完整模考

    private var mockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("完整模考")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(activeMock.map { "进行到\($0.stage.skill?.title ?? "") · 开始于 \($0.startedAt.relativeDescription)" }
                             ?? test.mockDescription)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "timer")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .accessibilityHidden(true)
                }
                HStack(spacing: 12) {
                    if let mock = activeMock {
                        Button {
                            launcher.mock(mock)
                        } label: {
                            Label("继续模考", systemImage: "play.fill")
                        }
                        .buttonStyle(HeroButtonStyle())
                        Button("放弃") { confirmAbandon = mock }
                            .buttonStyle(HeroButtonStyle(prominent: false))
                    } else {
                        Button {
                            launcher.startMock(test, context: modelContext)
                        } label: {
                            Label("开始完整模考", systemImage: "play.fill")
                        }
                        .buttonStyle(HeroButtonStyle())
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            let finished = mocks.filter(\.isFinished)
            if !finished.isEmpty {
                Card(padding: 0) {
                    DividedRows(data: finished) { mock in
                        NavigationLink(value: Route.mock(mock.id)) {
                            HStack(spacing: 10) {
                                MockSummaryRow(mock: mock, records: allRecords)
                                Chevron()
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            Text("按官方机考流程依次进行：每部分开始前有说明页，录音只播放一次，计时不能暂停。中途退出后可从当前部分继续。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - 分项练习

    private func listeningCard(_ listening: ListeningTest, statistics: PracticeStatistics) -> some View {
        skillCard(.listening, subtitle: "Part 1–4 · \(listening.questionCount) 题 · 可暂停与回放") {
            DividedRows(data: listening.sections) { section in
                Button {
                    start(.listening, [section.id])
                } label: {
                    HStack(spacing: 12) {
                        ListeningSectionRow(test: listening, section: section, best: statistics.examBest[section.id],
                                            showTest: false, hasDraft: draft([section.id]) != nil)
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ExamSkill.listening.tint)
                    }
                }
                .buttonStyle(RowButtonStyle())
                .contextMenu {
                    Button { start(.listening, [section.id]) } label: { Label("练习这一部分", systemImage: "play") }
                    Button { launcher.study([section.id]) } label: { Label("背题模式", systemImage: "book") }
                }
            }
            Divider().padding(.leading, 16)
            audioRow(listening)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private func readingCard(statistics: PracticeStatistics) -> some View {
        skillCard(.reading, subtitle: "Passage 1–3 · \(test.reading.reduce(0) { $0 + $1.questionCount }) 题 · 60 分钟") {
            DividedRows(data: test.reading) { passage in
                NavigationLink(value: Route.passage(passage.id)) {
                    HStack(spacing: 10) {
                        ReadingPassageRow(exam: passage, best: statistics.examBest[passage.id],
                                          hasDraft: draft([passage.id]) != nil, showSet: false)
                        Chevron()
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
        }
    }

    private func writingCard(records: [PracticeRecord]) -> some View {
        let attempts = writingAttempts(records)
        return skillCard(.writing, subtitle: "Task 1 + Task 2 · 60 分钟") {
            DividedRows(data: test.writing) { task in
                NavigationLink(value: Route.writingTask(task.id)) {
                    HStack(spacing: 10) {
                        WritingTaskRow(item: WritingTaskItem(cambridge: task), attempts: attempts[task.id] ?? 0, showTitle: false)
                        Chevron()
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
        }
    }

    /// 科目卡片：标题行（整套练习按钮）+ 各部分
    private func skillCard<Rows: View>(_ skill: ExamSkill, subtitle: String, @ViewBuilder rows: () -> Rows) -> some View {
        let ids = test.ids(for: skill)
        let existing = draft(ids)
        return Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TintedIcon(symbol: skill.iconSymbol, tint: skill.tint, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(skill.title) · \(skill.englishTitle)")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(existing.map { "未完成 · 已答 \($0.answered)/\($0.totalQuestions) · 用时 \($0.elapsed.clockString)" } ?? subtitle)
                            .font(.subheadline)
                            .foregroundStyle(existing == nil ? Color(.secondaryLabel) : Color.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    if skill != .writing || existing != nil {
                        Menu {
                            if skill != .writing {
                                Button { launcher.study(ids) } label: { Label("背题模式", systemImage: "book") }
                            }
                            if let existing {
                                Button(role: .destructive) {
                                    modelContext.delete(existing)
                                    try? modelContext.save()
                                } label: { Label("放弃未完成的作答", systemImage: "trash") }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(skill.tint)
                        }
                    }
                    Button(existing == nil ? "整套练习" : "继续") {
                        if let existing { launcher.resume(existing) } else { launcher.start(skill, ids) }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(skill.tint)
                }
                .padding(16)
                Divider()
                rows()
            }
        }
    }

    @ViewBuilder
    private func audioRow(_ listening: ListeningTest) -> some View {
        if let progress = audio.progress[listening.id] {
            HStack(spacing: 10) {
                Label("正在下载音频", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: progress).frame(width: 120)
                Text("\(Int(progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else if audio.isComplete(listening) {
            HStack {
                Label("音频已下载，可离线练习", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("删除", role: .destructive) { confirmDeleteAudio = true }
                    .buttonStyle(.borderless)
            }
            .font(.subheadline)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    audio.download(listening)
                } label: {
                    Label(audio.downloadedCount(listening) > 0
                          ? "继续下载音频（\(audio.downloadedCount(listening))/\(listening.sections.count)）"
                          : "下载音频以离线练习", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                if let failure = audio.failures[listening.id] {
                    Text("部分音频下载失败：\(failure)").font(.footnote).foregroundStyle(.red)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func start(_ skill: ExamSkill, _ ids: [String]) {
        if let existing = draft(ids) {
            launcher.resume(existing)
        } else {
            launcher.start(skill, ids)
        }
    }

    private func abandon(_ mock: MockTest) {
        let mockID = mock.id
        drafts.filter { $0.mockID == mockID }.forEach(modelContext.delete)
        modelContext.delete(mock)
        try? modelContext.save()
    }
}

extension ExamLauncher {
    /// 新建一次完整模考并进入第一部分
    func startMock(_ test: PracticeTest, context: ModelContext) {
        let first: MockStage = test.listening != nil ? .listening : .reading
        let mock = MockTest(testID: test.id, firstStage: first)
        context.insert(mock)
        try? context.save()
        self.mock(mock)
    }
}

/// 模考成绩摘要行。
struct MockSummaryRow: View {
    let mock: MockTest
    let records: [PracticeRecord]
    /// 在多套试卷的列表中显示试卷名
    var title: String?

    var body: some View {
        let result = MockResult(mock: mock, records: records)
        let date = mock.finishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "进行中"
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? date)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                Text(title == nil ? result.bandSummary : "\(date) · \(result.bandSummary)")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            if let overall = result.overallBand {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("总分").font(.caption).foregroundStyle(Color(.secondaryLabel))
                    Text(BandScore.format(overall)).font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Color(.label))
                }
            }
        }
        .padding(.vertical, 3)
    }
}
