import Foundation
import SwiftData

// MARK: - 计划内容

enum PlanDayKind: String, Codable {
    /// 第一天：诊断模考
    case diagnostic
    /// 完整模考
    case mock
    /// 分项强化（前半段）
    case drill
    /// 机经冲刺（后半段）
    case sprint
    /// 考前一天
    case final
}

enum PlanTaskKind: String, Codable {
    case mock, listening, reading, writing, speaking, vocabulary, review, weakSpot, jijing, checklist

    /// 由练习记录自动判断是否完成；其余任务手动打勾
    var isTracked: Bool {
        switch self {
        case .mock, .listening, .reading, .writing: true
        default: false
        }
    }

    var skill: ExamSkill? {
        switch self {
        case .listening: .listening
        case .reading: .reading
        case .writing: .writing
        default: nil
        }
    }
}

struct PlanTask: Codable, Identifiable, Hashable {
    let id: String
    let kind: PlanTaskKind
    let title: String
    let detail: String
    let minutes: Int
    /// 听力 Part / 阅读篇目 / 写作题目
    var examIDs: [String] = []
    /// 完整模考或复盘对应的试卷
    var testID: String?
    /// 口语话题（"examiner" 表示考官流程用语）
    var topicIDs: [String] = []
    /// 为什么安排这一项（根据当前成绩生成）
    var reason: String?
    /// 时间不够时可以先跳过
    var optional: Bool?

    /// 接着做之前没做完的练习（包括顺延过来的）
    var isResume: Bool { id.contains("resume-") }
}

struct PlanDay: Codable, Identifiable, Hashable {
    let index: Int
    let date: Date
    let kind: PlanDayKind
    let title: String
    let focus: String
    let tasks: [PlanTask]
    /// 尚未到来的日子：只是预览，当天会按最新成绩重新安排
    var preview: Bool?
    /// 已经过去、但那天没有打开计划，因此没有生成任务
    var skipped: Bool?

    var id: Int { index }
    var minutes: Int { tasks.reduce(0) { $0 + $1.minutes } }
    var isPreview: Bool { preview == true }
    var isSkipped: Bool { skipped == true }
}

/// 四科分数：一次以往的正式成绩，或四科各自的目标。
struct SkillScores: Codable, Identifiable, Hashable {
    var id = UUID()
    var listening: Double
    var reading: Double
    var writing: Double
    var speaking: Double

    static func uniform(_ band: Double) -> SkillScores {
        SkillScores(listening: band, reading: band, writing: band, speaking: band)
    }

    var sum: Double { listening + reading + writing + speaking }

    subscript(skill: PlanSkill) -> Double {
        get {
            switch skill {
            case .listening: listening
            case .reading: reading
            case .writing: writing
            case .speaking: speaking
            }
        }
        set {
            switch skill {
            case .listening: listening = newValue
            case .reading: reading = newValue
            case .writing: writing = newValue
            case .speaking: speaking = newValue
            }
        }
    }

    var overall: Double? { BandScore.overall([listening, reading, writing, speaking]) }
}

/// 备考计划：考试日期、目标分数与已经开始的每一天。
/// 每天的任务在当天第一次打开时按最新成绩生成并固定下来，之后的日子只是预览。
@Model
final class StudyPlan {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var startDate: Date = Date()
    var examDate: Date = Date()
    var targetBand: Double = 7.0
    /// 每天可用于备考的时间（分钟）
    var dailyMinutes: Int = 180
    /// 手动打勾的任务 ID（逗号分隔）
    var checkedRaw: String = ""
    /// 旧版一次性生成的全部日程，仅用于迁移
    @Attribute(.externalStorage) var daysData: Data = Data()
    /// 已经开始的日子（固定下来的任务）。数据量很小，不使用外部存储（新增外部存储属性会导致旧数据库无法自动迁移）
    var frozenData: Data = Data()
    /// 以往的正式考试成绩（有了就不需要诊断模考）
    var historyData: Data = Data()
    /// 四科各自的目标（总分 7.5 不需要每科都 7.5，例如听阅 8、写口 6.5）
    var skillTargetData: Data = Data()

    init(startDate: Date, examDate: Date, targetBand: Double, dailyMinutes: Int) {
        self.id = UUID()
        self.createdAt = Date()
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.examDate = Calendar.current.startOfDay(for: examDate)
        self.targetBand = targetBand
        self.dailyMinutes = dailyMinutes
    }

    var frozenDays: [Int: PlanDay] {
        let days = (try? JSONDecoder().decode([PlanDay].self, from: frozenData)) ?? []
        return Dictionary(days.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func freeze(_ days: [PlanDay]) {
        var all = frozenDays
        for day in days { all[day.index] = day }
        frozenData = (try? JSONEncoder().encode(all.values.sorted { $0.index < $1.index })) ?? Data()
    }

    /// 清除从某天开始的固定任务与打勾（重新安排时使用）
    func unfreeze(from index: Int) {
        let removed = frozenDays.values.filter { $0.index >= index }
        let removedIDs = Set(removed.flatMap { $0.tasks.map(\.id) })
        let kept = frozenDays.values.filter { $0.index < index }.sorted { $0.index < $1.index }
        frozenData = (try? JSONEncoder().encode(kept)) ?? Data()
        checkedRaw = checked.subtracting(removedIDs).sorted().joined(separator: ",")
    }

    var history: [SkillScores] {
        get { (try? JSONDecoder().decode([SkillScores].self, from: historyData)) ?? [] }
        set { historyData = newValue.isEmpty ? Data() : ((try? JSONEncoder().encode(newValue)) ?? Data()) }
    }

    /// 已有可参考的成绩，不需要第一天诊断
    var hasBaseline: Bool { !history.isEmpty }

    /// 四科目标；没有单独设置时每科都按总目标
    var skillTargets: SkillScores {
        get { (try? JSONDecoder().decode(SkillScores.self, from: skillTargetData)) ?? .uniform(targetBand) }
        set { skillTargetData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var legacyDays: [PlanDay] {
        (try? JSONDecoder().decode([PlanDay].self, from: daysData)) ?? []
    }

    var checked: Set<String> {
        Set(checkedRaw.split(separator: ",").map(String.init))
    }

    func toggle(_ taskID: String) {
        var set = checked
        if set.contains(taskID) { set.remove(taskID) } else { set.insert(taskID) }
        checkedRaw = set.sorted().joined(separator: ",")
    }

    /// 计划天数（开始日到考试前一天）
    var dayCount: Int {
        Self.days(from: startDate, to: examDate)
    }

    /// 距离考试的天数（今天考试为 0）
    var daysLeft: Int {
        Self.days(from: Date(), to: examDate)
    }

    /// 今天是计划的第几天（从 0 开始；考试当天等于天数）
    var todayIndex: Int {
        Self.days(from: startDate, to: Date())
    }

    /// 两个日期相差的自然日数。两端都先取当天零点，换了时区（例如出国考试）也按日历日计算
    static func days(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    var targetListening: Int? { BandScore.minimumListening(for: skillTargets.listening) }
    var targetReading: Int? { BandScore.minimumAcademicReading(for: skillTargets.reading) }
}

// MARK: - 现状分析

enum PlanSkill: String, CaseIterable, Identifiable {
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

    var shortTitle: String {
        switch self {
        case .listening: "听"
        case .reading: "阅"
        case .writing: "写"
        case .speaking: "口"
        }
    }
}

/// 某一科目前的水平估计。
struct SkillStatus: Identifiable {
    let skill: PlanSkill
    /// 估计分数；还没有数据时为 nil
    let band: Double?
    /// 分数来源（「整套听力 10/3」「近期练习估算」「模考自评」）
    let source: String
    let target: Double

    var id: PlanSkill { skill }
    var gap: Double? { band.map { max(target - $0, 0) } }
    /// 安排练习时的优先级：差距越大越优先；没有数据时按中等差距处理
    var priority: Double { gap ?? 0.5 }
}

/// 根据练习记录与模考，分析四科现状、薄弱题型与最近的错题。
struct PlanInsights {
    let skills: [SkillStatus]
    let weakReading: [PracticeStatistics.KindAccuracy]
    let weakListening: [PracticeStatistics.KindAccuracy]
    /// 听力正确率最低的 Part
    let weakListeningPart: (part: Int, accuracy: Double)?
    /// 昨天以来的错题数
    let recentWrong: (listening: Int, reading: Int)
    /// 总分目标
    let target: Double

    init(records: [PracticeRecord], mocks: [MockTest], history: [SkillScores] = [], targets: SkillScores? = nil,
         target: Double, now: Date = Date()) {
        self.target = target
        let targets = targets ?? .uniform(target)
        let calendar = Calendar.current
        let twoWeeks = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        // 作答不到一半的记录（中途交卷、空白提交）不用于估分
        let records = records.filter { record in
            guard record.total > 0, let parts = record.payload?.parts else { return record.skill == .writing }
            let answered = parts.reduce(0) { $0 + $1.questions.values.filter { !$0.given.isEmpty }.count }
            return answered * 2 >= record.total
        }
        let recent = records.filter { $0.finishedAt >= twoWeeks }

        // 以往正式成绩的平均分；和新成绩同时存在时各占一半，避免一次发挥失常带偏整个计划
        func combine(_ skill: PlanSkill, recent: (band: Double, source: String)?, empty: String) -> SkillStatus {
            let past = history.map { $0[skill] }
            let pastMean = past.isEmpty ? nil : past.reduce(0, +) / Double(past.count)
            switch (recent, pastMean) {
            case let (recent?, mean?):
                return SkillStatus(skill: skill, band: (recent.band + mean) / 2,
                                   source: "\(recent.source) + 历史平均 \(BandScore.short(mean))", target: targets[skill])
            case let (recent?, nil):
                return SkillStatus(skill: skill, band: recent.band, source: recent.source, target: targets[skill])
            case let (nil, mean?):
                let source = past.count == 1 ? "历史成绩" : "历史 \(past.count) 次：" + past.map(BandScore.short).joined(separator: " / ")
                return SkillStatus(skill: skill, band: mean, source: source, target: targets[skill])
            case (nil, nil):
                return SkillStatus(skill: skill, band: nil, source: empty, target: targets[skill])
            }
        }

        func objective(_ skill: ExamSkill, title: String, band: (Int, Int) -> String?) -> SkillStatus {
            let planSkill: PlanSkill = skill == .listening ? .listening : .reading
            var latest: (Double, String)?
            // 最近一次整套（40 题）成绩最可靠；否则用近两周的分项练习按 40 题折算
            let practice = recent.filter { $0.skill == skill }
            let score = practice.reduce(0) { $0 + $1.score }
            let total = practice.reduce(0) { $0 + $1.total }
            if let full = records.first(where: { $0.skill == skill && $0.kind == .fullTest && $0.total >= 30 }),
               let value = full.band.flatMap(Double.init) {
                latest = (value, "整套\(title) \(full.finishedAt.shortDay) · \(full.score)/\(full.total)")
            } else if total >= 10, let value = band(score, total).flatMap(Double.init) {
                latest = (value, "近期 \(total) 题练习")
            }
            return combine(planSkill, recent: latest, empty: "还没有成绩")
        }

        let finishedMocks = mocks.filter(\.isFinished).sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        func selfRated(_ skill: PlanSkill, _ value: (MockTest) -> Double?) -> SkillStatus {
            let rated = finishedMocks.first(where: { value($0) != nil }).flatMap(value).map { ($0, "模考自评") }
            return combine(skill, recent: rated, empty: "模考后可在成绩单自评")
        }

        skills = [
            objective(.listening, title: "听力") { BandScore.listening(score: $0, total: $1) },
            objective(.reading, title: "阅读") { BandScore.academicReading(score: $0, total: $1) },
            selfRated(.writing) { $0.writingBand },
            selfRated(.speaking) { $0.speakingBand },
        ]

        func weak(_ skill: ExamSkill) -> [PracticeStatistics.KindAccuracy] {
            PracticeStatistics(records: recent.filter { $0.skill == skill }).kindAccuracy
                .filter { $0.total >= 3 && $0.kind != .other && $0.accuracy < 0.85 }
        }
        weakReading = weak(.reading)
        weakListening = weak(.listening)

        var partScore: [Int: (Int, Int)] = [:]
        for record in recent where record.skill == .listening {
            for part in record.payload?.parts ?? [] {
                guard let number = part.listeningPart else { continue }
                let current = partScore[number] ?? (0, 0)
                partScore[number] = (current.0 + part.score, current.1 + part.total)
            }
        }
        weakListeningPart = partScore.filter { $0.value.1 >= 10 }
            .map { (part: $0.key, accuracy: Double($0.value.0) / Double($0.value.1)) }
            .min { $0.accuracy < $1.accuracy }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let latest = records.filter { $0.finishedAt >= yesterday }
        recentWrong = (
            latest.filter { $0.skill == .listening }.reduce(0) { $0 + ($1.total - $1.score) },
            latest.filter { $0.skill == .reading }.reduce(0) { $0 + ($1.total - $1.score) }
        )
    }

    func status(_ skill: PlanSkill) -> SkillStatus {
        skills.first { $0.skill == skill }!
    }

    /// 听力、阅读、写作中最需要加练的一项（只在有成绩可比较时给出）
    var focusSkill: PlanSkill? {
        let known = skills.filter { $0.skill != .speaking && $0.band != nil }
        guard !known.isEmpty else { return nil }
        let candidates = skills.filter { $0.skill != .speaking && $0.priority >= 0.25 }
        return candidates.max { ($0.priority, $0.band == nil ? 0 : 1) < ($1.priority, $1.band == nil ? 0 : 1) }?.skill
    }

    /// 四科中离目标最远的科目（包括口语），从大到小；差距相近的一起列出
    var focusSkills: [PlanSkill] {
        let largest = skills.compactMap(\.gap).max() ?? 0
        return skills.filter { ($0.gap ?? 0) >= max(0.25, largest - 0.2) }
            .enumerated().sorted { ($0.element.gap ?? 0, -$0.offset) > ($1.element.gap ?? 0, -$1.offset) }
            .map(\.element.skill)
    }

    var hasScores: Bool { skills.contains { $0.band != nil } }

    /// 四科都有估分时的总分估算：四科合计、总分，以及达到目标总分还差的合计分
    var overall: (sum: Double, band: Double, shortfall: Double)? {
        let bands = skills.compactMap(\.band)
        guard bands.count == 4, let band = BandScore.overall(bands) else { return nil }
        let sum = bands.reduce(0, +)
        // 平均分达到「目标 − 0.25」即按官方规则进到目标分
        return (sum, band, max(4 * (target - 0.25) - sum, 0))
    }

    func describe(_ skill: PlanSkill) -> String {
        let status = status(skill)
        guard let band = status.band, let gap = status.gap else { return "还没有\(skill.title)成绩，先用整套摸底" }
        let target = BandScore.short(status.target)
        return gap > 0
            ? "\(skill.title)约 \(BandScore.format(band))，距目标 \(target) 还差 \(BandScore.format(gap))"
            : "\(skill.title)约 \(BandScore.format(band))，已达到目标 \(target)"
    }
}

// MARK: - 完成情况

enum PlanTaskStatus: Equatable {
    case todo
    case inProgress
    case partial(Double)
    case done

    var isDone: Bool { self == .done }
}

/// 根据计划开始后的练习记录、模考与手动打勾，计算每项任务的完成情况。
struct PlanProgress {
    let plan: StudyPlan
    let days: [PlanDay]
    let practiced: Set<String>
    let mocks: [MockTest]
    let checked: Set<String>

    init(plan: StudyPlan, days: [PlanDay], records: [PracticeRecord], mocks: [MockTest]) {
        self.plan = plan
        self.days = days
        let since = plan.startDate
        practiced = Set(records.filter { $0.finishedAt >= since }.flatMap(\.examIDList))
        self.mocks = mocks.filter { $0.startedAt >= since }
        checked = plan.checked
    }

    func mock(for task: PlanTask) -> MockTest? {
        guard let testID = task.testID else { return nil }
        let matches = mocks.filter { $0.testID == testID }
        return matches.first(where: \.isFinished) ?? matches.first
    }

    func status(_ task: PlanTask) -> PlanTaskStatus {
        switch task.kind {
        case .mock:
            guard let mock = mock(for: task) else { return .todo }
            return mock.isFinished ? .done : .inProgress
        case .listening, .reading, .writing:
            let done = task.examIDs.filter(practiced.contains).count
            if done == task.examIDs.count, done > 0 { return .done }
            return done > 0 ? .partial(Double(done) / Double(task.examIDs.count)) : .todo
        default:
            return checked.contains(task.id) ? .done : .todo
        }
    }

    func doneCount(_ day: PlanDay) -> Int {
        day.tasks.filter { status($0).isDone }.count
    }

    /// 已经开始的日子里的任务（预览中的日子不计入）
    var started: [PlanDay] { days.filter { !$0.isPreview } }
    var totalTasks: Int { started.reduce(0) { $0 + $1.tasks.count } }
    var totalDone: Int { started.reduce(0) { $0 + doneCount($1) } }

    /// 当天第一项未完成的任务
    func nextTask(_ day: PlanDay) -> PlanTask? {
        day.tasks.first { !status($0).isDone }
    }
}

// MARK: - 排期

/// 完整的日程：已经开始的日子（固定）+ 今天之后的预览。
struct PlanSchedule {
    let days: [PlanDay]
    let insights: PlanInsights
    var todayIndex = 0

    var today: PlanDay? {
        days.first { !$0.isPreview && $0.index == todayIndex }
    }
}

enum StudyPlanGenerator {
    /// 新建计划时默认的考试日期：30 天后
    static var defaultExamDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    static let defaultTargetBand = 7.0
    static let defaultDailyMinutes = 180

    /// 新建计划（替换已有计划），并安排今天的任务
    @MainActor
    @discardableResult
    static func create(examDate: Date, targetBand: Double, dailyMinutes: Int, history: [SkillScores],
                       targets: SkillScores, in context: ModelContext) -> StudyPlan {
        try? context.delete(model: StudyPlan.self)
        let plan = StudyPlan(startDate: Date(), examDate: examDate, targetBand: targetBand, dailyMinutes: dailyMinutes)
        plan.history = history
        plan.skillTargets = targets
        context.insert(plan)
        prepareToday(plan, in: context)
        return plan
    }

    /// 从今天起重新安排：保留已经过去的日子，今天及以后按最新成绩重排
    @MainActor
    static func reschedule(_ plan: StudyPlan, in context: ModelContext) {
        plan.unfreeze(from: max(plan.todayIndex, 0))
        prepareToday(plan, in: context)
    }

    /// 今天第一次打开时，按最新成绩生成今天的任务并固定下来
    @MainActor
    static func prepareToday(_ plan: StudyPlan, in context: ModelContext) {
        let today = plan.todayIndex
        guard today >= 0, today < plan.dayCount else { return }
        // 迁移旧版计划：保留已经开始的日子（包括今天，可能已经在做）
        if plan.frozenDays.isEmpty, !plan.legacyDays.isEmpty {
            plan.freeze(plan.legacyDays.filter { $0.index <= today })
            plan.daysData = Data()
        }
        let mocks = (try? context.fetch(FetchDescriptor<MockTest>())) ?? []
        let drafts = (try? context.fetch(FetchDescriptor<ExamDraft>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        // 填了历史成绩后不再需要诊断：今天的诊断模考还没答题时，改成分项练习。
        // 只点开、还没答题的模考保留在「继续作答」里，之后的模考日会接着用它
        if plan.hasBaseline, let day = plan.frozenDays[today], day.kind == .diagnostic {
            let testIDs = Set(day.tasks.compactMap(\.testID))
            let begun = mocks.contains { mock in
                testIDs.contains(mock.testID) && mock.startedAt >= plan.startDate
                    && (mock.stage != .listening || drafts.contains { $0.mockID == mock.id && $0.answered > 0 })
            }
            if !begun { plan.unfreeze(from: today) }
        }
        guard plan.frozenDays[today] == nil else {
            try? context.save()
            return
        }
        let records = (try? context.fetch(FetchDescriptor<PracticeRecord>(sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]))) ?? []
        let result = schedule(plan, records: records, mocks: mocks, drafts: drafts)
        if let day = result.days.first(where: { $0.index == today }) {
            var fixed = day
            fixed.preview = nil
            plan.freeze([fixed])
        }
        try? context.save()
    }

    /// 计算完整日程：已开始的日子取固定内容，今天（未固定时）与之后的日子按当前成绩生成
    static func schedule(_ plan: StudyPlan, records: [PracticeRecord], mocks: [MockTest],
                         drafts: [ExamDraft] = []) -> PlanSchedule {
        let calendar = Calendar.current
        let count = plan.dayCount
        let insights = PlanInsights(records: records, mocks: mocks, history: plan.history, targets: plan.skillTargets,
                                    target: plan.targetBand)
        guard count > 0 else { return PlanSchedule(days: [], insights: insights, todayIndex: plan.todayIndex) }

        let kinds = dayKinds(count: count, baseline: plan.hasBaseline)
        let frozen = plan.frozenDays
        let today = plan.todayIndex
        let progress = PlanProgress(plan: plan, days: Array(frozen.values), records: records, mocks: mocks)
        // 做到一半的练习：已经排进计划（包括前几天）的不再重复
        let planned = Set(frozen.values.flatMap(\.tasks).flatMap(\.examIDs))
        let resumed = frozen[today] == nil && today >= 0 && today < count
            ? unfinished(drafts).filter { $0.examIDs.allSatisfy { !planned.contains($0) } } : []
        var pools = ContentPools(records: records, reserved: frozen.values.flatMap(\.tasks) + resumed)
        var days: [PlanDay] = []
        var mockNumber = 0

        for index in 0..<count {
            let kind = kinds[index]
            if kind == .mock || kind == .diagnostic { mockNumber += 1 }
            let date = calendar.date(byAdding: .day, value: index, to: plan.startDate) ?? plan.startDate
            if let day = frozen[index] {
                days.append(day)
                continue
            }
            if index < today {
                days.append(PlanDay(index: index, date: date, kind: kind, title: "未安排",
                                    focus: "这一天没有打开备考计划，没有生成任务。", tasks: [], skipped: true))
                continue
            }
            // 今天：把前几天没完成的练习顺延过来
            let carried = index == today ? carryOver(frozen: frozen, before: today, progress: progress) : []
            var builder = DayBuilder(index: index, kind: kind, plan: plan, insights: insights,
                                     isToday: index == today, mockNumber: mockNumber, daysToExam: count - index)
            var day = builder.build(date: date, carried: carried, resumed: index == today ? resumed : [], pools: &pools)
            if index > today { day.preview = true }
            days.append(day)
        }
        return PlanSchedule(days: days, insights: insights, todayIndex: today)
    }

    /// 最近一周做到一半的练习（不含模考）：今天接着做完，比换新题更省时间
    private static func unfinished(_ drafts: [ExamDraft]) -> [PlanTask] {
        let content = ContentStore.shared
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var result: [PlanTask] = []
        for draft in drafts where draft.mockID == nil && draft.answered > 0 && draft.updatedAt >= weekAgo && result.count < 2 {
            let ids = draft.examIDList
            // 只接手计划能直接继续的草稿（与「开始」按钮使用相同的草稿键）
            guard !ids.isEmpty, draft.key == ExamSession.draftKey(kind: ids.count > 1 ? .fullTest : .practice, examIDs: ids),
                  !result.contains(where: { $0.kind.skill == draft.skill }) else { continue }
            let kind: PlanTaskKind
            let title: String
            let minutes: Int
            switch draft.skill {
            case .listening:
                kind = .listening
                let test = content.listeningTest(containing: ids[0])
                title = ids.count > 1 ? "听力整套：\(test?.title ?? "")" : "听力 " + content.displayTitle(for: ids[0])
                minutes = 10 * ids.count
            case .reading:
                kind = .reading
                title = ids.count > 1 ? "阅读整套：\(content.test(containing: ids[0])?.title ?? "")"
                    : "阅读 \(content.summary(for: ids[0])?.category.shortTitle ?? "")：\(content.displayTitle(for: ids[0]))"
                minutes = 20 * ids.count
            case .writing:
                kind = .writing
                title = "写作：" + content.displayTitle(for: ids[0])
                minutes = content.writingItem(ids[0])?.part == 1 ? 20 : 40
            }
            let answered = draft.totalQuestions > 0 ? "已答 \(draft.answered)/\(draft.totalQuestions)" : "做了一部分"
            result.append(PlanTask(id: "resume-\(draft.key)", kind: kind, title: title, detail: "接着上次的进度继续作答",
                                   minutes: minutes, examIDs: ids, reason: "\(draft.updatedAt.shortDay) \(answered)，接着做完"))
        }
        return result
    }

    /// 前几天没完成的练习（最多 2 项，越近越优先）。没做的模考只在近两天没有别的模考时顺延。
    private static func carryOver(frozen: [Int: PlanDay], before today: Int, progress: PlanProgress) -> [PlanTask] {
        let plan = progress.plan
        let kinds = dayKinds(count: plan.dayCount, baseline: plan.hasBaseline)
        let mockSoon = (today..<min(today + 2, kinds.count)).contains { kinds[$0] == .mock }
        var result: [PlanTask] = []
        for index in stride(from: today - 1, through: 0, by: -1) {
            guard let day = frozen[index] else { continue }
            for task in day.tasks where task.kind.isTracked && !progress.status(task).isDone {
                if task.kind == .mock && (mockSoon || progress.mock(for: task) != nil && progress.status(task) == .inProgress) {
                    // 进行中的模考在首页「继续」里，不重复安排
                    continue
                }
                // 有历史成绩后，没做的诊断模考不再补做
                if task.kind == .mock && day.kind == .diagnostic && plan.hasBaseline { continue }
                if task.optional == true { continue }
                result.append(task)
                if result.count == 2 { return result }
            }
        }
        return result
    }

    /// 每天的类型。最后一次模考放在考前两天，考前一天只做轻量调整（参考常见的考前减量建议）。
    /// 14 天时：第 1、5、9、13 天模考，第 14 天考前调整，前半段分项强化、后半段机经冲刺。
    /// 有历史成绩（baseline）时去掉第一天的诊断模考，其余模考位置不变。
    static func dayKinds(count: Int, baseline: Bool = false) -> [PlanDayKind] {
        guard count > 1 else { return [.final] }
        var kinds = Array(repeating: PlanDayKind.drill, count: count)
        kinds[count - 1] = .final
        let lastMock = count - 2
        let mockCount = count >= 4 ? max(2, min(4, Int((Double(count) / 3.5).rounded()))) : 1
        var positions: [Int] = [0]
        if mockCount > 1 {
            positions = (0..<mockCount).map { Int((Double($0) * Double(lastMock) / Double(mockCount - 1)).rounded()) }
        }
        if baseline {
            positions.removeAll { $0 == 0 }
            if positions.isEmpty { positions = [lastMock] }
        }
        for position in Set(positions) where position < count - 1 {
            kinds[position] = position == 0 && !baseline ? .diagnostic : .mock
        }
        for index in 0..<(count - 1) where kinds[index] == .drill && index >= count / 2 {
            kinds[index] = .sprint
        }
        return kinds
    }
}

// MARK: - 每天的任务

private struct DayBuilder {
    let index: Int
    let kind: PlanDayKind
    let plan: StudyPlan
    let insights: PlanInsights
    let isToday: Bool
    let mockNumber: Int
    let daysToExam: Int
    var tasks: [PlanTask] = []

    init(index: Int, kind: PlanDayKind, plan: StudyPlan, insights: PlanInsights, isToday: Bool, mockNumber: Int, daysToExam: Int) {
        self.index = index
        self.kind = kind
        self.plan = plan
        self.insights = insights
        self.isToday = isToday
        self.mockNumber = mockNumber
        self.daysToExam = daysToExam
    }

    mutating func add(_ kind: PlanTaskKind, _ title: String, _ detail: String, minutes: Int, examIDs: [String] = [],
                      testID: String? = nil, topics: [String] = [], reason: String? = nil, optional: Bool = false) {
        tasks.append(PlanTask(id: "d\(index)-\(tasks.count)-\(kind.rawValue)", kind: kind, title: title, detail: detail,
                              minutes: minutes, examIDs: examIDs, testID: testID, topicIDs: topics, reason: reason,
                              optional: optional ? true : nil))
    }

    mutating func build(date: Date, carried: [PlanTask], resumed: [PlanTask], pools: inout ContentPools) -> PlanDay {
        for task in carried {
            tasks.append(PlanTask(id: "d\(index)-carry-\(task.id)", kind: task.kind, title: "补做：" + task.title,
                                  detail: task.detail, minutes: task.minutes, examIDs: task.examIDs, testID: task.testID,
                                  topicIDs: task.topicIDs, reason: "前几天没做完，顺延到今天"))
        }
        let carriedMock = carried.contains { $0.kind == .mock }

        let title: String
        let focus: String
        switch kind {
        case .diagnostic, .mock:
            (title, focus) = mockDay(pools: &pools, skipMock: carriedMock)
        case .drill, .sprint:
            // 做到一半的练习只在练习日接着做（模考日时间不够）
            tasks.append(contentsOf: resumed)
            (title, focus) = practiceDay(pools: &pools, skipCore: carriedMock, resumed: resumed)
        case .final:
            (title, focus) = finalDay(pools: &pools)
        }
        trim()
        return PlanDay(index: index, date: date, kind: kind, title: title, focus: focus, tasks: tasks)
    }

    /// 超出每天可用时间时，去掉可选任务
    private mutating func trim() {
        while tasks.reduce(0, { $0 + $1.minutes }) > plan.dailyMinutes,
              let last = tasks.lastIndex(where: { $0.optional == true }) {
            tasks.remove(at: last)
        }
    }

    // MARK: 模考日

    private mutating func mockDay(pools: inout ContentPools, skipMock: Bool) -> (String, String) {
        if !skipMock, let test = pools.nextMockTest() {
            add(.mock, "完整模考：\(test.title)", "听力 → 阅读 → 写作，按官方流程一口气做完", minutes: 165, testID: test.id,
                reason: kind == .diagnostic ? "先摸清四科水平，后面的安排会根据这次成绩调整" : "检验最近几天的练习效果，并更新四科估分")
            add(.review, "复盘模考", "逐题看解析，把错题按原因归类：拼写 / 同义替换没认出 / 定位错 / 时间不够",
                minutes: 40, testID: test.id, reason: "差一两道题就可能差半分，复盘比多做一套更有效")
        }
        let speakingGap = insights.status(.speaking).priority
        let topics = speakingGap >= 0.25 ? pools.part2Topics(2) : pools.part2Topics(1)
        add(.speaking, "口语：Part 2&3 ×\(topics.count)" + (kind == .diagnostic ? " + 考官流程" : ""),
            "点话题听考官提问，录下自己的回答", minutes: 20 + 10 * (topics.count - 1),
            topics: (kind == .diagnostic ? ["examiner"] : []) + topics)
        if kind == .diagnostic {
            return ("诊断模考", "按真实考试流程完成一整套，不要暂停。做完后在成绩单里给写作、口语自评，之后每天的安排会根据四科差距自动调整。")
        }
        return ("第 \(mockNumber) 次模考", "尽量安排在和正式考试相同的时间段（上午），一口气做完。成绩出来后，后面几天会重新侧重最弱的一项。")
    }

    // MARK: 练习日

    private mutating func practiceDay(pools: inout ContentPools, skipCore: Bool, resumed: [PlanTask]) -> (String, String) {
        let sprint = kind == .sprint
        let focusSkill = insights.focusSkill
        let listening = insights.status(.listening)
        let reading = insights.status(.reading)
        let writing = insights.status(.writing)

        // 错题复盘：有昨天的错题时优先
        let wrong = insights.recentWrong
        if isToday && wrong.listening + wrong.reading > 0 {
            add(.review, "错题复盘：昨天错了 \(wrong.listening + wrong.reading) 道",
                "听力 \(wrong.listening) 道、阅读 \(wrong.reading) 道，逐题看解析并标出错因", minutes: 20,
                reason: "错题按原因归类后再练，提分最快")
        } else if !isToday && index > 0 {
            add(.review, "复盘前一天的错题", "逐题看解析，标出错因", minutes: 15)
        }

        if !skipCore {
            // 听力（今天接着做的听力已经算在内）
            if resumed.contains(where: { $0.kind == .listening }) {
                // 不再另排听力
            } else if listening.priority >= 0.5, let test = pools.nextListeningTest() {
                add(.listening, "听力整套：\(test.title)", "Part 1–4 · 做完对照原文精听错题，核对拼写、单复数和字数限制", minutes: 40,
                    examIDs: test.listening?.sections.map(\.id) ?? [], reason: insights.describe(.listening))
            } else {
                // 已接近目标：只练正确率最低的 Part；还没有分 Part 的数据时练最难的 Part 3、4
                let part = insights.weakListeningPart?.part
                let ids = part.map { pools.listeningSections(part: $0, kind: nil, count: 2) }
                    ?? pools.listeningSections(part: 3, kind: nil, count: 1) + pools.listeningSections(part: 4, kind: nil, count: 1)
                let parts = ids.compactMap { ContentStore.shared.listeningSection(for: $0)?.section.part }
                if !ids.isEmpty {
                    add(.listening, part.map { "听力 Part \($0) ×\(ids.count)" } ?? "听力 " + parts.map { "Part \($0)" }.joined(separator: " + "),
                        "做完对照原文精听错题，核对拼写、单复数和字数限制", minutes: 10 * ids.count, examIDs: ids,
                        reason: part.map { "听力已接近目标，只练正确率最低的 Part \($0)" }
                            ?? insights.describe(.listening) + "，每天精练两个难度较高的 Part")
                }
            }
            if focusSkill == .listening, let weak = insights.weakListening.first {
                let ids = pools.listeningSections(part: nil, kind: weak.kind, count: 2)
                if !ids.isEmpty {
                    add(.listening, "听力专项：\(weak.kind.title) ×\(ids.count)", "只听含这种题型的 Part",
                        minutes: 10 * ids.count, examIDs: ids,
                        reason: "听力是目前最弱的一项，「\(weak.kind.title)」正确率 \(weak.accuracy.percentString)", optional: true)
                }
            }

            // 写作是弱项时，最后一周按考场顺序连写 Task 1 + Task 2（IDP 写作备考建议），阅读少排一篇腾出时间
            let writingFocus = writing.priority >= 0.25
            let writeBoth = sprint && writingFocus

            // 阅读：薄弱题型优先，后半段用近期考到过的文章
            let readingCount = (reading.priority >= 0.5 ? 3 : (reading.priority > 0 ? 2 : 1)) - (writeBoth ? 1 : 0)
                - resumed.filter { $0.kind == .reading }.reduce(0) { $0 + $1.examIDs.count }
            let weakKind = insights.weakReading.first
            let passages = pools.passages(kind: weakKind?.kind, hot: sprint, count: readingCount)
            for (offset, passage) in passages.enumerated() {
                let retest = ExtrasStore.shared.jijing(forContent: passage.id)?.retestCount
                let source = (passage.setTitle ?? "题库") + (retest.map { " · 机经重考 \($0) 次" } ?? "")
                let reason: String? = offset > 0 ? nil : (weakKind.map { "阅读「\($0.kind.title)」正确率 \($0.accuracy.percentString)，选了含这种题型的文章" }
                    ?? insights.describe(.reading))
                add(.reading, "阅读 \(passage.category.shortTitle)：\(passage.title)", "\(source) · 计时 20 分钟 · 填空超出字数限制不得分",
                    minutes: 20, examIDs: [passage.id], reason: reason, optional: offset >= 2)
            }

            // 写作：Task 2 与 Task 1 交替；写作是弱项时每天都写 Task 2。
            // 要求来自 2023 版写作评分标准：7 分需要「清晰并展开的立场」与「清楚的总览」，6 分常见问题是论点展开不足、衔接生硬
            if writeBoth, let task1 = pools.nextTask1(), let task2 = pools.nextTask2() {
                add(.writing, "写作 Task 1：\(task1.title)",
                    "\(task1.category) · 和下面的 Task 2 连着写，共 60 分钟 · 开头 2–3 句写总览，不写结论和个人观点 · 约 180 词",
                    minutes: 20, examIDs: [task1.id], reason: "最后一周按考场节奏连写两篇")
                add(.writing, "写作 Task 2：\(task2.title)",
                    "机经" + (task2.jijing.map { " · 重考 \($0.retestCount) 次" } ?? "") + " · 约 280 词 · 留 5 分钟按评分标准自查",
                    minutes: 40, examIDs: [task2.id], reason: insights.describe(.writing))
            } else {
                if writingFocus || index % 2 == 1, let task = pools.nextTask2() {
                    add(.writing, "写作 Task 2：\(task.title)",
                        "机经" + (task.jijing.map { " · 重考 \($0.retestCount) 次" } ?? "") + " · 约 280 词"
                            + (writingFocus ? " · 先花 5 分钟列提纲，写完自查：立场是否贯穿全文、每段一个中心观点并展开、衔接不生硬" : ""),
                        minutes: 40, examIDs: [task.id],
                        reason: writingFocus ? insights.describe(.writing) + "；评分标准里 6 分常因论点展开不足被压分" : "Task 2 的分数权重是 Task 1 的两倍")
                }
                if !writingFocus || index % 2 == 0, let task = pools.nextTask1() {
                    add(.writing, "写作 Task 1：\(task.title)", "\(task.category) · 开头 2–3 句写总览，不写结论和个人观点 · 约 180 词",
                        minutes: 20, examIDs: [task.id], optional: writingFocus)
                }
            }
        }

        // 口语：弱项时加量
        let speakingFocus = insights.status(.speaking).priority >= 0.25
        let part1 = pools.part1Topics(speakingFocus ? 3 : 2)
        let part2 = pools.part2Topics(speakingFocus ? 2 : 1)
        add(.speaking, "口语：Part 1 ×\(part1.count) · Part 2&3 ×\(part2.count)",
            speakingFocus
                ? "Part 2 先用 1 分钟记要点、讲满 2 分钟；Part 3 按「观点 → 理由 → 例子 → 另一面」展开；录音回听，留意长停顿和反复自我纠正，不背模板"
                : "点话题听考官提问，录下自己的回答",
            minutes: speakingFocus ? 40 : 25, topics: part1 + part2,
            reason: speakingFocus ? insights.describe(.speaking) : nil)
        if sprint {
            add(.jijing, "浏览近期机经", "看近 30 天考到、重考次数高的话题和题型", minutes: 15, optional: true)
        }
        if daysToExam == 2 {
            add(.review, "错题总复盘", "回看练习记录里正确率最低的几次，把反复错的题型再过一遍", minutes: 30)
        }
        add(.vocabulary, "生词本复习", "复习今天到期的单词", minutes: 15, optional: true)

        let focusText: String
        let focusSkills = insights.focusSkills.prefix(2)
        if !focusSkills.isEmpty {
            focusText = "今天重点：\(focusSkills.map(\.title).joined(separator: "、"))。"
                + focusSkills.map(insights.describe).joined(separator: "；") + "。"
        } else if !insights.hasScores {
            focusText = "还没有成绩，先完成诊断模考；之后哪一科离目标差得多，就会多安排哪一科。"
        } else {
            focusText = "四科都接近目标，保持每天练习。"
        }
        return (sprint ? "机经冲刺" : "分项强化",
                focusText + (sprint ? " 阅读优先选近期考到过的文章，口语准备可复用的素材。" : " 听力做完立刻对照原文精听错题，阅读每篇严格 20 分钟。"))
    }

    // MARK: 考前一天

    private mutating func finalDay(pools: inout ContentPools) -> (String, String) {
        if let section = pools.listeningSections(part: 1, kind: nil, count: 1).first {
            add(.listening, "听力热身：Part 1", "保持手感，不做整套；顺便熟悉 Review、Highlight 等机考操作", minutes: 10, examIDs: [section])
        }
        add(.speaking, "口语：考官流程 + 高频题卡回顾", "最高频的 3 个 Part 2 题卡再讲一遍", minutes: 30,
            topics: ["examiner"] + pools.topPart2(3))
        add(.jijing, "回顾近期机经", "听力、阅读近 30 天高频话题过一遍即可", minutes: 20)
        add(.vocabulary, "生词本轻量复习", "只复习，不背新词", minutes: 15, optional: true)
        add(.checklist, "考前准备", "证件、考试时间和考点路线确认好，早点休息", minutes: 10)
        return ("考前调整", "不再做新的整套题，保持手感就好（IDP 建议考前一天只做轻量复习）。确认考试信息，早点睡。")
    }
}

// MARK: - 题目分配

/// 按顺序分配题目，避免重复，并跳过已经练过或已排进计划的内容。
struct ContentPools {
    private var used: Set<String>
    private var usedTests: Set<String>
    private var tests: [PracticeTest]
    private var task2: [WritingTaskItem]
    private var task1: [WritingTaskItem]
    private var part1: [SpeakingBank.Topic]
    private var part2: [SpeakingBank.Topic]
    private let allPart2: [SpeakingBank.Topic]

    init(records: [PracticeRecord], reserved: [PlanTask]) {
        let content = ContentStore.shared
        used = Set(records.flatMap(\.examIDList)).union(reserved.flatMap(\.examIDs))
        let index = RecordIndex(records)
        usedTests = Set(reserved.compactMap(\.testID))
        // 剑桥真题从新到旧；已经做过的试卷不再整套使用
        tests = content.books.filter(\.isCambridge).flatMap(\.tests)
        for test in tests where TestProgress(test: test, index: index).isStarted {
            usedTests.insert(test.id)
        }
        task2 = content.writingItems
            .filter { $0.source == .jijing && $0.part == 2 }
            .sorted { ($0.jijing?.lastHitDate ?? "", $0.jijing?.retestCount ?? 0) > ($1.jijing?.lastHitDate ?? "", $1.jijing?.retestCount ?? 0) }
        // 剑桥 Task 1 从旧到新，新题留给模考
        task1 = content.writingItems.filter { $0.source == .cambridge && $0.part == 1 }.reversed()
        let topics = (ExtrasStore.shared.speaking?.topics ?? []).filter { !$0.questions.isEmpty }
            .sorted { $0.recentExamCount > $1.recentExamCount }
        part1 = topics.filter { $0.part == 1 }
        part2 = topics.filter { $0.part == 2 }
        allPart2 = part2
        // 口语话题按已排进计划的跳过
        let reservedTopics = Set(reserved.flatMap(\.topicIDs))
        part1.removeAll { reservedTopics.contains($0.id) }
        part2.removeAll { reservedTopics.contains($0.id) }
    }

    private mutating func take(_ ids: [String]) -> [String] {
        used.formUnion(ids)
        return ids
    }

    /// 完整模考：一套还没碰过、听力阅读写作齐全的试卷
    mutating func nextMockTest() -> PracticeTest? {
        guard let test = tests.first(where: { test in
            test.canMock && !usedTests.contains(test.id) && !test.writing.isEmpty
                && (test.listeningIDs + test.readingIDs).allSatisfy { !used.contains($0) }
        }) else { return nil }
        usedTests.insert(test.id)
        _ = take(test.listeningIDs + test.readingIDs + test.writingIDs)
        return test
    }

    /// 整套听力：从模考不用的试卷里取（从旧到新，把新题留给模考）
    mutating func nextListeningTest() -> PracticeTest? {
        guard let test = tests.reversed().first(where: { test in
            !usedTests.contains(test.id) && test.listening != nil && test.listeningIDs.allSatisfy { !used.contains($0) }
        }) else { return nil }
        usedTests.insert(test.id)
        _ = take(test.listeningIDs)
        return test
    }

    mutating func listeningSections(part: Int?, kind: QuestionKind?, count: Int) -> [String] {
        let pool = tests.reversed().flatMap { test in test.listening?.sections ?? [] }.filter { section in
            !used.contains(section.id) && (part == nil || section.part == part)
                && (kind == nil || section.questionKinds.contains(kind!))
        }
        return take(Array(pool.prefix(count).map(\.id)))
    }

    /// 阅读：优先含薄弱题型的文章；冲刺阶段用近期考到过的文章，否则用剑桥真题的 P2、P3
    mutating func passages(kind: QuestionKind?, hot: Bool, count: Int) -> [ExamSummary] {
        let extras = ExtrasStore.shared
        let all = ContentStore.shared.readingPassages.filter { !used.contains($0.id) }
        // 剑桥真题从旧到新用于练习（新题留给模考），红皮密卷等模拟题排在后面
        let cambridge = tests.reversed().flatMap(\.reading).filter { !used.contains($0.id) && $0.category != .p1 }
        let cambridgeIDs = Set(cambridge.map(\.id))
        let bank = cambridge + all.filter { $0.isBank && $0.category != .p1 && !cambridgeIDs.contains($0.id) }
        // 冲刺阶段：近期考到过的文章（按机经重考次数）
        let jijing = all.filter { extras.jijing(forContent: $0.id) != nil }
            .sorted { (extras.jijing(forContent: $0.id)?.retestCount ?? 0) > (extras.jijing(forContent: $1.id)?.retestCount ?? 0) }
        let primary = hot ? jijing : Array(bank)
        let secondary = hot ? Array(bank) : jijing
        var result: [ExamSummary] = []
        func pick(_ list: [ExamSummary], matching: Bool) {
            for passage in list where result.count < count && !result.contains(passage) {
                if matching, let kind, !passage.questionKinds.contains(kind) { continue }
                // 同一天的文章分属不同 Passage
                if result.contains(where: { $0.category == passage.category }) && result.count < 2 { continue }
                result.append(passage)
            }
        }
        if kind != nil {
            pick(primary, matching: true)
            pick(secondary, matching: true)
        }
        pick(primary, matching: false)
        pick(secondary, matching: false)
        _ = take(result.map(\.id))
        return result
    }

    mutating func nextTask2() -> WritingTaskItem? {
        guard let index = task2.firstIndex(where: { !used.contains($0.id) }) else { return nil }
        let item = task2.remove(at: index)
        _ = take([item.id])
        return item
    }

    mutating func nextTask1() -> WritingTaskItem? {
        guard let index = task1.firstIndex(where: { !used.contains($0.id) && !usedTests.contains(ContentStore.shared.test(containing: $0.id)?.id ?? "") }) else { return nil }
        let item = task1.remove(at: index)
        _ = take([item.id])
        return item
    }

    mutating func part1Topics(_ count: Int) -> [String] {
        let taken = part1.prefix(count).map(\.id)
        part1.removeFirst(min(count, part1.count))
        return taken
    }

    mutating func part2Topics(_ count: Int) -> [String] {
        let taken = part2.prefix(count).map(\.id)
        part2.removeFirst(min(count, part2.count))
        return taken
    }

    func topPart2(_ count: Int) -> [String] {
        allPart2.prefix(count).map(\.id)
    }
}
