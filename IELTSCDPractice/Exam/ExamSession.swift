import Foundation
import Observation

enum ExamMode: String {
    /// 计时作答
    case test
    /// 查看已提交的作答与解析
    case review
    /// 背题：直接显示答案与解析
    case study
}

struct ExamSession: Identifiable, Hashable {
    let id = UUID()
    var kind: PracticeKind
    var skill: ExamSkill
    var mode: ExamMode
    var examIDs: [String]
    var timer: ExamTimerSetting
    var recordID: UUID?
    /// 完整模考中的一个部分：按官方规则进行（说明页、录音只播放一次、计时不可暂停）
    var mockID: UUID?

    var isMock: Bool { mockID != nil }

    static func draftKey(kind: PracticeKind, examIDs: [String], mockID: UUID? = nil) -> String {
        (mockID.map { "mock-\($0.uuidString)|" } ?? "") + "\(kind.rawValue):\(examIDs.joined(separator: ","))"
    }

    var draftKey: String { Self.draftKey(kind: kind, examIDs: examIDs, mockID: mockID) }

    /// 按题目类型创建练习：1 篇（单项）或整套
    static func practice(_ skill: ExamSkill, _ examIDs: [String]) -> ExamSession {
        let kind: PracticeKind = examIDs.count > 1 ? .fullTest : .practice
        let timer: ExamTimerSetting
        switch skill {
        case .reading:
            timer = Preferences.timer(for: kind)
        case .listening:
            // 听力以录音为准，不另外计时
            timer = ExamTimerSetting(kind: .none, limit: 0)
        case .writing:
            timer = Preferences.writingTimer(parts: examIDs.compactMap { ContentStore.shared.writingItem($0)?.part })
        }
        return ExamSession(kind: kind, skill: skill, mode: .test, examIDs: examIDs, timer: timer)
    }
}

/// 负责弹出全屏机考界面。
@Observable
final class ExamLauncher {
    var session: ExamSession?
    /// 模考全部完成后显示成绩
    var finishedMockID: UUID?

    private var content: ContentStore { .shared }

    func start(_ skill: ExamSkill, _ examIDs: [String]) {
        guard !examIDs.isEmpty else { return }
        session = .practice(skill, examIDs)
    }

    func reading(_ examIDs: [String]) { start(.reading, examIDs) }
    func listening(_ examIDs: [String]) { start(.listening, examIDs) }
    func writing(_ examIDs: [String]) { start(.writing, examIDs) }

    /// 单篇阅读（兼容旧调用）
    func practice(_ examID: String) { reading([examID]) }

    /// 开始或继续一次完整模考的当前部分
    func mock(_ mock: MockTest) {
        guard let test = content.test(mock.testID), let skill = mock.stage.skill else { return }
        session = ExamSession(kind: .fullTest, skill: skill, mode: .test, examIDs: test.ids(for: skill),
                              timer: Preferences.officialTimer(for: skill), mockID: mock.id)
    }

    func resume(_ draft: ExamDraft) {
        let ids = draft.examIDList
        // 旧版草稿没有记录科目，按题目推断
        let skill = ids.first.map(content.skill(of:)) ?? draft.skill
        session = ExamSession(kind: draft.kind, skill: skill, mode: .test, examIDs: ids, timer: draft.timer,
                              mockID: draft.mockID)
    }

    /// 背题模式（写作没有背题模式，可在题目页查看范文）
    func study(_ examIDs: [String]) {
        guard let first = examIDs.first else { return }
        let skill = content.skill(of: first)
        guard skill != .writing else { return }
        session = ExamSession(kind: examIDs.count > 1 ? .fullTest : .practice, skill: skill, mode: .study,
                              examIDs: examIDs, timer: ExamTimerSetting(kind: .none, limit: 0))
    }

    func study(_ examID: String) {
        study([examID])
    }

    func review(_ record: PracticeRecord) {
        session = ExamSession(kind: record.kind, skill: record.skill, mode: .review, examIDs: record.examIDList,
                              timer: ExamTimerSetting(kind: .none, limit: 0), recordID: record.id)
    }
}
