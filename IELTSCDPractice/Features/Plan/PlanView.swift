import SwiftData
import SwiftUI

/// 备考计划：考试倒计时、每天的任务与完成情况。
struct PlanView: View {
    var navigate: (HomeDestination) -> Void

    @Query(sort: \StudyPlan.createdAt, order: .reverse) private var plans: [StudyPlan]
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]
    @Query(sort: \MockTest.updatedAt, order: .reverse) private var mocks: [MockTest]
    @Environment(\.modelContext) private var modelContext
    @State private var selected: Int?
    @State private var showingSetup = false

    var body: some View {
        Group {
            if let plan = plans.first, plan.dayCount > 0 {
                content(plan)
            } else {
                ContentUnavailableView {
                    Label("还没有备考计划", systemImage: "calendar.badge.clock")
                } description: {
                    Text("设置考试日期和目标分数，自动安排每天的模考、分项练习与机经冲刺。")
                } actions: {
                    Button("制定备考计划") { showingSetup = true }
                        .buttonStyle(.borderedProminent)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("备考计划")
        .toolbar {
            if !plans.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSetup = true
                    } label: {
                        Label("调整计划", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            PlanSetupSheet(plan: plans.first)
        }
        .onAppear {
            if let plan = plans.first { StudyPlanGenerator.prepareToday(plan, in: modelContext) }
        }
    }

    private func content(_ plan: StudyPlan) -> some View {
        let schedule = StudyPlanGenerator.schedule(plan, records: records, mocks: mocks)
        let days = schedule.days
        let progress = PlanProgress(plan: plan, days: days, records: records, mocks: mocks)
        let examIndex = days.count
        let current = min(max(selected ?? plan.todayIndex, 0), examIndex)
        let selection = Binding(get: { current }, set: { selected = $0 })

        return GeometryReader { proxy in
            let wide = proxy.size.width >= 860
            ScrollView {
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 14) {
                                CountdownCard(plan: plan, progress: progress)
                                SkillStatusCard(insights: schedule.insights)
                                DayList(plan: plan, days: days, progress: progress, selection: selection)
                            }
                            .frame(width: 320)
                            dayDetail(current, plan: plan, days: days, progress: progress)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            CountdownCard(plan: plan, progress: progress)
                            SkillStatusCard(insights: schedule.insights)
                            DayStrip(plan: plan, days: days, progress: progress, selection: selection)
                            dayDetail(current, plan: plan, days: days, progress: progress)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func dayDetail(_ index: Int, plan: StudyPlan, days: [PlanDay], progress: PlanProgress) -> some View {
        if index < days.count {
            DayDetail(plan: plan, day: days[index], progress: progress, records: records, navigate: navigate)
        } else {
            ExamDayCard(plan: plan)
        }
    }
}

// MARK: - 倒计时

private struct CountdownCard: View {
    let plan: StudyPlan
    let progress: PlanProgress

    var body: some View {
        let left = plan.daysLeft
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if left > 0 {
                    Text("距离考试还有")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(left)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("天")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(left == 0 ? "今天考试，加油！" : "考试已结束")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(plan.examDate.chineseDay) · 学术类机考 · 目标 \(BandScore.format(plan.targetBand))（"
                     + PlanSkill.allCases.map { "\($0.shortTitle) \(BandScore.short(plan.skillTargets[$0]))" }.joined(separator: " · ") + "）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let listening = plan.targetListening, let reading = plan.targetReading {
                    Text("听力至少答对 \(listening)/40，阅读至少答对 \(reading)/40")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(progress.totalDone), total: Double(max(progress.totalTasks, 1)))
                    .tint(.white)
                Text("已开始的 \(progress.started.count) 天里完成 \(progress.totalDone)/\(progress.totalTasks) 项任务")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - 四科现状

extension PlanSkill {
    var symbol: String {
        switch self {
        case .listening: ExamSkill.listening.iconSymbol
        case .reading: ExamSkill.reading.iconSymbol
        case .writing: ExamSkill.writing.iconSymbol
        case .speaking: "mic.fill"
        }
    }

    var tint: Color {
        switch self {
        case .listening: ExamSkill.listening.tint
        case .reading: ExamSkill.reading.tint
        case .writing: ExamSkill.writing.tint
        case .speaking: Theme.speaking
        }
    }
}

/// 四科估分与目标的差距：每天的安排据此侧重。
private struct SkillStatusCard: View {
    let insights: PlanInsights

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("四科现状").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let focus = insights.focusSkills.first {
                        Text("当前重点：\(insights.focusSkills.prefix(2).map(\.title).joined(separator: "、"))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(focus.tint)
                    }
                }
                ForEach(insights.skills) { status in
                    HStack(spacing: 10) {
                        Image(systemName: status.skill.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.skill.tint)
                            .frame(width: 18)
                        Text(status.skill.title)
                            .font(.subheadline)
                            .frame(width: 34, alignment: .leading)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(status.band.map(BandScore.format) ?? "—")
                                .font(.subheadline.weight(.semibold))
                            Text("/\(BandScore.short(status.target))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(status.band.map(BandScore.format) ?? "待测")，目标 \(BandScore.short(status.target))")
                        Text(status.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        gapText(status)
                    }
                }
                if let overall = insights.overall {
                    Divider()
                    Label(overallText(overall), systemImage: "sum")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let weak = insights.weakReading.first ?? insights.weakListening.first {
                    Divider()
                    Label("最弱题型：\(weak.kind.title)（正确率 \(weak.accuracy.percentString)）", systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func overallText(_ overall: (sum: Double, band: Double, shortfall: Double)) -> String {
        let text = "按估分总分约 \(BandScore.format(overall.band))（四科合计 \(BandScore.short((overall.sum * 10).rounded() / 10))）"
        guard overall.shortfall > 0 else { return text + "，已达到目标总分" }
        let needed = 4 * (insights.target - 0.25)
        return text + "；目标 \(BandScore.format(insights.target)) 需要合计 \(BandScore.short(needed))，"
            + "还差 \(BandScore.short((overall.shortfall * 10).rounded() / 10)) 分"
    }

    @ViewBuilder
    private func gapText(_ status: SkillStatus) -> some View {
        if let gap = status.gap {
            Text(gap > 0 ? "差 \(BandScore.format(gap))" : "已达标")
                .font(.caption.weight(.semibold))
                .foregroundStyle(gap >= 0.5 ? Color.red : (gap > 0 ? Color.orange : Color.green))
                .fixedSize()
        } else {
            Text("待测").font(.caption).foregroundStyle(.tertiary).fixedSize()
        }
    }
}

// MARK: - 日期选择

extension PlanDayKind {
    var symbol: String {
        switch self {
        case .diagnostic: "stethoscope"
        case .mock: "timer"
        case .drill: "dumbbell.fill"
        case .sprint: "flame.fill"
        case .final: "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .diagnostic, .mock: .indigo
        case .drill: .blue
        case .sprint: .orange
        case .final: .teal
        }
    }
}

/// 窄屏：横向日期条。
private struct DayStrip: View {
    let plan: StudyPlan
    let days: [PlanDay]
    let progress: PlanProgress
    @Binding var selection: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        Button {
                            selection = day.index
                        } label: {
                            DayChip(date: day.date, symbol: day.isSkipped ? "minus" : day.kind.symbol, tint: day.isSkipped ? .gray : day.kind.tint,
                                    isToday: day.index == plan.todayIndex, isSelected: selection == day.index,
                                    fraction: day.isPreview || day.isSkipped ? nil : Double(progress.doneCount(day)) / Double(max(day.tasks.count, 1)),
                                    isPast: day.index < plan.todayIndex)
                        }
                        .buttonStyle(.plain)
                        .id(day.index)
                    }
                    Button {
                        selection = days.count
                    } label: {
                        DayChip(date: plan.examDate, symbol: "graduationcap.fill", tint: .red,
                                isToday: plan.daysLeft == 0, isSelected: selection == days.count,
                                fraction: nil, isPast: false, label: "考试")
                    }
                    .buttonStyle(.plain)
                    .id(days.count)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -Theme.pagePadding)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

private struct DayChip: View {
    let date: Date
    let symbol: String
    let tint: Color
    let isToday: Bool
    let isSelected: Bool
    let fraction: Double?
    let isPast: Bool
    var label: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(label ?? (isToday ? "今天" : date.weekdayName))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : (isToday ? tint : Color(.secondaryLabel)))
            Text(date.shortDay)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color(.label))
            ZStack {
                if let fraction {
                    if fraction >= 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(isSelected ? Color.white : Color.green)
                    } else {
                        ProgressRing(value: fraction, tint: isSelected ? .white : tint, size: 20, lineWidth: 3) {
                            EmptyView()
                        }
                        if isPast && fraction < 1 {
                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                        }
                    }
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(isSelected ? Color.white : tint)
                }
            }
            .font(.system(size: 18))
            .frame(height: 22)
        }
        .frame(width: 58)
        .padding(.vertical, 10)
        .background(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.chineseDay)\(isToday ? "，今天" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 宽屏：左栏日期列表。
private struct DayList: View {
    let plan: StudyPlan
    let days: [PlanDay]
    let progress: PlanProgress
    @Binding var selection: Int

    var body: some View {
        Card(padding: 6) {
            VStack(spacing: 2) {
                ForEach(days) { day in
                    row(index: day.index, date: day.date, title: day.title + (day.isPreview ? "（预览）" : ""),
                        symbol: day.kind.symbol, tint: day.isSkipped ? .gray : day.kind.tint,
                        done: day.isPreview || day.isSkipped ? nil : progress.doneCount(day),
                        total: day.isPreview || day.isSkipped ? nil : day.tasks.count)
                }
                row(index: days.count, date: plan.examDate, title: "考试", symbol: "graduationcap.fill", tint: .red,
                    done: nil, total: nil)
            }
        }
    }

    private func row(index: Int, date: Date, title: String, symbol: String, tint: Color, done: Int?, total: Int?) -> some View {
        let isSelected = selection == index
        let isToday = index == plan.todayIndex
        let overdue = index < plan.todayIndex && (done ?? 0) < (total ?? 0)
        return Button {
            selection = index
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color(.label))
                    Text(isToday ? "今天 · \(date.shortDay) \(date.weekdayName)" : "\(date.shortDay) \(date.weekdayName)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : (isToday ? tint : Color(.secondaryLabel)))
                }
                Spacer(minLength: 4)
                if let done, let total {
                    if done >= total {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(isSelected ? .white : .green)
                    } else {
                        Text("\(done)/\(total)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : (overdue ? Color.orange : Color(.secondaryLabel)))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 当天任务

private struct DayDetail: View {
    let plan: StudyPlan
    let day: PlanDay
    let progress: PlanProgress
    let records: [PracticeRecord]
    let navigate: (HomeDestination) -> Void

    var body: some View {
        let done = progress.doneCount(day)
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        TintedIcon(symbol: day.kind.symbol, tint: day.kind.tint, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("第 \(day.index + 1) 天 · \(day.date.chineseDay)" + (day.index == plan.todayIndex ? " · 今天" : ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(day.title)
                                .font(.title2.weight(.bold))
                        }
                        Spacer()
                        if !day.isPreview && !day.tasks.isEmpty {
                            ProgressRing(value: Double(done) / Double(max(day.tasks.count, 1)), tint: day.kind.tint,
                                         size: 52, lineWidth: 6) {
                                Text("\(done)/\(day.tasks.count)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                            }
                        }
                    }
                    Label(day.focus, systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .labelStyle(FocusLabelStyle())
                    if !day.tasks.isEmpty {
                        Text("预计用时 \(day.minutes.durationText)（每天 \(plan.dailyMinutes.durationText)）")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    if day.isPreview {
                        Label("预览：到这一天时会根据你最新的成绩重新安排，题目也可能更换。", systemImage: "wand.and.stars")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.indigo)
                    } else if day.index < plan.todayIndex && done < day.tasks.count {
                        Label("还有 \(day.tasks.count - done) 项没完成，最重要的练习会自动顺延到今天", systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
            if !day.tasks.isEmpty {
                Card(padding: 0) {
                    DividedRows(data: day.tasks, inset: 64) { task in
                        PlanTaskRow(plan: plan, task: task, progress: progress, records: records, navigate: navigate,
                                    preview: day.isPreview)
                    }
                }
            }
        }
    }
}

private struct FocusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(.yellow)
            configuration.title
        }
    }
}

extension PlanTaskKind {
    var symbol: String {
        switch self {
        case .mock: "timer"
        case .listening: ExamSkill.listening.iconSymbol
        case .reading: ExamSkill.reading.iconSymbol
        case .writing: ExamSkill.writing.iconSymbol
        case .speaking: "mic.fill"
        case .vocabulary: "character.book.closed.fill"
        case .review: "arrow.uturn.backward"
        case .weakSpot: "scope"
        case .jijing: "flame.fill"
        case .checklist: "checklist"
        }
    }

    var tint: Color {
        switch self {
        case .mock: .indigo
        case .listening: ExamSkill.listening.tint
        case .reading: ExamSkill.reading.tint
        case .writing: ExamSkill.writing.tint
        case .speaking: Theme.speaking
        case .vocabulary: .brown
        case .review: .gray
        case .weakSpot: .purple
        case .jijing: .red
        case .checklist: .green
        }
    }
}

/// 一项任务：练习类任务点「开始」直接进入机考界面，完成后自动打勾；其余任务手动打勾。
struct PlanTaskRow: View {
    let plan: StudyPlan
    let task: PlanTask
    let progress: PlanProgress
    let records: [PracticeRecord]
    let navigate: (HomeDestination) -> Void
    var preview = false

    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let status = progress.status(task)
        HStack(alignment: .top, spacing: 12) {
            TintedIcon(symbol: task.kind.symbol, tint: task.kind.tint, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(status.isDone ? Color(.secondaryLabel) : Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail(status))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = task.reason, !status.isDone {
                    Label(reason, systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.indigo)
                        .fixedSize(horizontal: false, vertical: true)
                }
                extra
            }
            Spacer(minLength: 8)
            if preview {
                if task.optional == true {
                    Text("可选").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                trailing(status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func detail(_ status: PlanTaskStatus) -> String {
        var text = task.detail
        if case .partial(let fraction) = status {
            text += " · 已完成 \(Int((fraction * Double(task.examIDs.count)).rounded()))/\(task.examIDs.count)"
        }
        if task.kind == .mock, let mock = progress.mock(for: task) {
            text = mock.isFinished
                ? MockResult(mock: mock, records: records).bandSummary
                : "进行到\(mock.stage.skill?.title ?? "")"
        }
        return text + " · 约 \(task.minutes.durationText)" + (task.optional == true ? " · 时间不够可跳过" : "")
    }

    // MARK: 附加内容

    @ViewBuilder
    private var extra: some View {
        switch task.kind {
        case .speaking where !task.topicIDs.isEmpty:
            FlowLayout(spacing: 6) {
                ForEach(task.topicIDs, id: \.self) { id in
                    NavigationLink(value: id == "examiner" ? Route.examiner : Route.speakingTopic(id)) {
                        Text(topicName(id))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.speaking)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Theme.speaking.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        case .weakSpot:
            if let weak = WeakSpot.find(records: records) {
                NavigationLink(value: weak.route) {
                    Label("\(weak.skill.title) · \(weak.kind.title)（正确率 \(weak.accuracy.percentString)）",
                          systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .tint(task.kind.tint)
            } else {
                Text("完成诊断模考后，这里会显示你最弱的题型。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .checklist:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(PlanChecklist.dayBefore, id: \.self) { item in
                    Label(item, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(BulletLabelStyle())
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: 右侧操作

    @ViewBuilder
    private func trailing(_ status: PlanTaskStatus) -> some View {
        if task.kind.isTracked {
            if status.isDone {
                if task.kind == .mock, let mock = progress.mock(for: task) {
                    NavigationLink(value: Route.mock(mock.id)) {
                        Text("成绩")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(task.kind.tint)
                }
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("已完成")
            } else {
                Button(status == .todo && !task.isResume ? "开始" : "继续") {
                    launcher.run(task, progress: progress, context: modelContext)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(task.kind.tint)
            }
        } else {
            HStack(spacing: 10) {
                link
                Button {
                    plan.toggle(task.id)
                    try? modelContext.save()
                } label: {
                    Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(status.isDone ? Color.green : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(status.isDone ? "标记为未完成" : "标记为已完成")
            }
        }
    }

    @ViewBuilder
    private var link: some View {
        switch task.kind {
        case .vocabulary:
            Button("去复习") { navigate(.vocabulary) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(task.kind.tint)
        case .jijing:
            Button("机经") { navigate(.predictions(.listening)) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(task.kind.tint)
        case .review:
            if let mock = progress.mock(for: task) {
                NavigationLink(value: Route.mock(mock.id)) { Text("成绩单") }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.indigo)
            } else if task.testID == nil {
                Button("练习记录") { navigate(.records) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.indigo)
            }
        default:
            EmptyView()
        }
    }

    private func topicName(_ id: String) -> String {
        if id == "examiner" { return "考官流程用语" }
        return ExtrasStore.shared.speaking?.topics.first { $0.id == id }?.name ?? id
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 4)).baselineOffset(3)
            configuration.title
        }
    }
}

// MARK: - 薄弱题型

/// 阅读、听力中正确率最低的题型（至少做过 3 题）。
struct WeakSpot {
    let skill: ExamSkill
    let kind: QuestionKind
    let accuracy: Double

    var route: Route {
        switch skill {
        case .listening: .sections(SectionFilter(title: "听力 · \(kind.title)", kind: kind, status: .unpracticed))
        default: .passages(PassageFilter(title: kind.title, kind: kind, status: .unpracticed))
        }
    }

    static func find(records: [PracticeRecord]) -> WeakSpot? {
        var candidates: [WeakSpot] = []
        for skill in [ExamSkill.reading, .listening] {
            let statistics = PracticeStatistics(records: records.filter { $0.skill == skill })
            if let item = statistics.kindAccuracy.first(where: { $0.total >= 3 && $0.kind != .other }) {
                candidates.append(WeakSpot(skill: skill, kind: item.kind, accuracy: item.accuracy))
            }
        }
        return candidates.min { $0.accuracy < $1.accuracy }
    }
}

// MARK: - 考试日

enum PlanChecklist {
    static let dayBefore = [
        "确认考试时间、考点地址和路线",
        "报名时用的证件（护照或身份证）原件放进包里",
        "口语考试时间以考点通知为准",
        "早点睡，不熬夜刷题",
    ]

    static let examDay = [
        "带好报名时使用的有效证件原件",
        "按考点通知提前到达，留出签到、拍照和存包的时间",
        "手机、手表等物品按要求存放，考场内只用考点提供的文具",
        "机考顺序：听力约 30 分钟 → 阅读 60 分钟 → 写作 60 分钟，中间不休息",
        "听力每部分开始前先读题；机考没有誊写时间，最后只有 2 分钟检查答案",
        "阅读每篇控制在 20 分钟左右，不会的先跳过；剩 10 分钟和 5 分钟时计时器会闪烁",
        "写作 Task 2 的分数权重是 Task 1 的两倍，按 20 / 40 分钟分配时间；字数显示在左下角",
        "机考的口语可能在笔试当天的前后，也可能在另一天，以考点通知为准",
    ]
}

private struct ExamDayCard: View {
    let plan: StudyPlan
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let checked = plan.checked
        VStack(alignment: .leading, spacing: 14) {
            Card {
                HStack(spacing: 12) {
                    TintedIcon(symbol: "graduationcap.fill", tint: .red, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.examDate.chineseDay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("考试日")
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    Text("目标 \(BandScore.format(plan.targetBand))")
                        .font(.headline)
                        .foregroundStyle(.red)
                }
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(PlanChecklist.examDay.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().padding(.leading, 52) }
                        let id = "exam-\(index)"
                        Button {
                            plan.toggle(id)
                            try? modelContext.save()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: checked.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(checked.contains(id) ? Color.green : Color(.tertiaryLabel))
                                Text(item)
                                    .foregroundStyle(Color(.label))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            Text("以上为通用提醒，具体安排以考点的考试确认信息为准。机考如果某一科没达到目标，可在考试后 60 天内申请 One Skill Retake 单科重考（各考点和院校的接受情况不同，需要先确认）。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - 开始任务

extension ExamLauncher {
    /// 开始计划中的练习任务：模考继续或新建，其余练习有草稿时继续作答。
    @MainActor
    func run(_ task: PlanTask, progress: PlanProgress, context: ModelContext) {
        switch task.kind {
        case .mock:
            if let mock = progress.mock(for: task), !mock.isFinished {
                self.mock(mock)
            } else if let id = task.testID, let test = ContentStore.shared.test(id) {
                startMock(test, context: context)
            }
        case .listening, .reading, .writing:
            guard let skill = task.kind.skill, !task.examIDs.isEmpty else { return }
            let ids = task.examIDs
            let key = ExamSession.draftKey(kind: ids.count > 1 ? .fullTest : .practice, examIDs: ids)
            var descriptor = FetchDescriptor<ExamDraft>(predicate: #Predicate { $0.key == key })
            descriptor.fetchLimit = 1
            if let draft = try? context.fetch(descriptor).first {
                resume(draft)
            } else {
                start(skill, ids)
            }
        default:
            break
        }
    }
}

// MARK: - 设置

struct PlanSetupSheet: View {
    let plan: StudyPlan?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var examDate: Date
    @State private var targetBand: Double
    @State private var dailyMinutes: Int
    @State private var history: [SkillScores]
    @State private var skillTargets: SkillScores
    @State private var confirmRegenerate = false
    @State private var confirmDelete = false

    private static let bands: [Double] = Array(stride(from: 5.5, through: 8.5, by: 0.5))

    init(plan: StudyPlan?) {
        self.plan = plan
        _examDate = State(initialValue: plan?.examDate ?? StudyPlanGenerator.defaultExamDate)
        _targetBand = State(initialValue: plan?.targetBand ?? StudyPlanGenerator.defaultTargetBand)
        _dailyMinutes = State(initialValue: plan?.dailyMinutes ?? StudyPlanGenerator.defaultDailyMinutes)
        _history = State(initialValue: plan?.history ?? [])
        _skillTargets = State(initialValue: plan?.skillTargets ?? .uniform(StudyPlanGenerator.defaultTargetBand))
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var daysUntilExam: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                       to: calendar.startOfDay(for: examDate)).day ?? 0
    }

    private var dateChanged: Bool {
        guard let plan else { return true }
        return !Calendar.current.isDate(plan.examDate, inSameDayAs: examDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("考试日期", selection: $examDate, in: tomorrow..., displayedComponents: .date)
                    Picker("总分目标", selection: $targetBand) {
                        ForEach(Self.bands, id: \.self) { Text(BandScore.format($0)).tag($0) }
                    }
                    .onChange(of: targetBand) { old, new in
                        // 分项目标还是统一值时跟着总目标一起改
                        if PlanSkill.allCases.allSatisfy({ skillTargets[$0] == old }) {
                            for skill in PlanSkill.allCases { skillTargets[skill] = new }
                        }
                    }
                    SkillScoresRow(label: "分项目标", score: $skillTargets, showsSum: true)
                    Stepper(value: $dailyMinutes, in: 60...360, step: 30) {
                        LabeledContent("每天可用时间", value: dailyMinutes.durationText)
                    }
                } footer: {
                    Text(targetsNote + "距离考试 \(daysUntilExam) 天。" + (history.isEmpty ? "第一天诊断模考，之后定期模考" : "定期模考")
                         + "，最后一次在考前两天。每天的任务在当天按你最新的成绩安排：哪一科离目标差得多就多练哪一科，选含薄弱题型的题目，没做完的练习自动顺延；超出每天可用时间时先去掉可选任务。")
                }

                Section {
                    ForEach($history) { $score in
                        SkillScoresRow(label: "第 \((history.firstIndex { $0.id == score.id } ?? 0) + 1) 次", score: $score)
                    }
                    .onDelete { history.remove(atOffsets: $0) }
                    Button {
                        history.append(history.last.map { SkillScores(listening: $0.listening, reading: $0.reading,
                                                                    writing: $0.writing, speaking: $0.speaking) }
                                       ?? SkillScores(listening: 6.5, reading: 6.5, writing: 6, speaking: 6))
                    } label: {
                        Label("添加一次成绩", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("以往的正式成绩")
                } footer: {
                    Text("填了以往的成绩就不需要诊断模考。四科估分先按历史平均计算，之后做了模考和练习，再与新成绩各占一半。")
                }

                Section("分项目标对应的原始分") {
                    LabeledContent("听力 \(BandScore.short(skillTargets.listening))（40 题）",
                                   value: BandScore.minimumListening(for: skillTargets.listening).map { "至少 \($0) 题" } ?? "—")
                    LabeledContent("学术类阅读 \(BandScore.short(skillTargets.reading))（40 题）",
                                   value: BandScore.minimumAcademicReading(for: skillTargets.reading).map { "至少 \($0) 题" } ?? "—")
                }

                if plan != nil {
                    Section {
                        Button("从今天重新安排") { confirmRegenerate = true }
                        Button("删除计划", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("改了目标分数或每天可用时间后，可以从今天重新安排。已做过的题目不会再排进计划。")
                    }
                }
            }
            .navigationTitle(plan == nil ? "制定备考计划" : "调整计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(plan == nil ? "生成计划" : "保存") { save() }
                }
            }
            .alert("从今天重新安排计划？", isPresented: $confirmRegenerate) {
                Button("取消", role: .cancel) {}
                Button("重新安排") {
                    if let plan {
                        apply(plan)
                        StudyPlanGenerator.reschedule(plan, in: modelContext)
                    }
                    dismiss()
                }
            } message: {
                Text("今天及以后的任务会按最新成绩重新安排，已经过去的日子和练习记录不受影响。")
            }
            .alert("删除备考计划？", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    try? modelContext.delete(model: StudyPlan.self)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    /// 分项目标换算出的总分与总目标是否一致
    private var targetsNote: String {
        guard let overall = skillTargets.overall else { return "" }
        let sum = BandScore.short(skillTargets.sum)
        if overall < targetBand {
            return "按分项目标四科合计 \(sum)，总分只有 \(BandScore.format(overall))，低于总分目标。"
        }
        return "按分项目标四科合计 \(sum)，总分 \(BandScore.format(overall))。"
    }

    private func apply(_ plan: StudyPlan) {
        plan.targetBand = targetBand
        plan.dailyMinutes = dailyMinutes
        plan.history = history
        plan.skillTargets = skillTargets
    }

    private func save() {
        if let plan, !dateChanged {
            apply(plan)
            // 刚填了历史成绩时，今天还没开始的诊断模考换成分项练习
            StudyPlanGenerator.prepareToday(plan, in: modelContext)
        } else {
            StudyPlanGenerator.create(examDate: examDate, targetBand: targetBand, dailyMinutes: dailyMinutes,
                                      history: history, targets: skillTargets, in: modelContext)
        }
        dismiss()
    }
}

/// 四科分数（一次以往成绩或分项目标），每科用一个菜单选择。
private struct SkillScoresRow: View {
    let label: String
    @Binding var score: SkillScores
    var showsSum = false

    private static let bands: [Double] = Array(stride(from: 4.0, through: 9.0, by: 0.5))

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(showsSum ? Color(.label) : Color(.secondaryLabel))
            Spacer(minLength: 4)
            ForEach(PlanSkill.allCases) { skill in
                Menu {
                    Picker(skill.title, selection: Binding(get: { score[skill] }, set: { score[skill] = $0 })) {
                        ForEach(Self.bands, id: \.self) { Text(BandScore.short($0)).tag($0) }
                    }
                } label: {
                    Text("\(skill.shortTitle) \(BandScore.short(score[skill]))")
                        .monospacedDigit()
                }
                .buttonStyle(.bordered)
                .tint(skill.tint)
                .accessibilityLabel("\(skill.title) \(BandScore.short(score[skill]))")
            }
            Text(showsSum ? "合计 \(BandScore.short(score.sum))" : "总分 \(score.overall.map(BandScore.format) ?? "—")")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
    }
}
