import Foundation
import SwiftData

// MARK: - 练习记录

enum PracticeKind: String, Codable, CaseIterable {
    case practice
    case fullTest

    var title: String {
        switch self {
        case .practice: "单项练习"
        case .fullTest: "整套练习"
        }
    }

    var symbol: String {
        switch self {
        case .practice: "doc.text"
        case .fullTest: "rectangle.stack"
        }
    }
}

struct QuestionResult: Codable, Hashable {
    var number: String
    var correct: Bool
    var expected: [String]
    var given: String
    var kind: QuestionKind
}

struct PartRecord: Codable, Hashable {
    var examId: String
    var title: String
    /// 阅读 P1–P3；听力为 nil（见 listeningPart）
    var category: ExamCategory?
    var listeningPart: Int?
    var answers: [String: String]
    var questions: [String: QuestionResult]
    var order: [String]
    var score: Int
    var total: Int
    /// 写作：Task 1 / 2 与字数（写作不自动判分，score 与 total 为 0）
    var writingPart: Int?
    var wordCount: Int?

    var isWriting: Bool { writingPart != nil }
    var essay: String { answers["essay"] ?? "" }
}

struct HighlightRecord: Codable, Hashable {
    var part: Int
    var pane: String
    var start: Int
    var end: Int
    var note: String
}

struct RecordPayload: Codable {
    var parts: [PartRecord]
    var highlights: [HighlightRecord]
}

@Model
final class PracticeRecord {
    var id: UUID = UUID()
    var kindRaw: String = PracticeKind.practice.rawValue
    var startedAt: Date = Date()
    var finishedAt: Date = Date()
    var duration: Double = 0
    var score: Int = 0
    var total: Int = 0
    var timeUp: Bool = false
    /// 逗号分隔的题目 ID，便于按篇目查询
    var examIDs: String = ""
    var title: String = ""
    var categoriesRaw: String = ""
    var skillRaw: String = ExamSkill.reading.rawValue
    var moduleRaw: String = ExamModule.academic.rawValue
    /// 属于某次完整模考时为该模考的 ID
    var mockID: UUID?
    @Attribute(.externalStorage) var payloadData: Data = Data()

    init(kind: PracticeKind, skill: ExamSkill = .reading, module: ExamModule = .academic,
         startedAt: Date, finishedAt: Date, duration: Double, score: Int, total: Int,
         timeUp: Bool, payload: RecordPayload) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.duration = duration
        self.score = score
        self.total = total
        self.timeUp = timeUp
        self.examIDs = payload.parts.map(\.examId).joined(separator: ",")
        self.title = payload.parts.map(\.title).joined(separator: " · ")
        self.categoriesRaw = payload.parts.compactMap { part in
            part.category?.rawValue ?? part.listeningPart.map { "L\($0)" } ?? part.writingPart.map { "W\($0)" }
        }.joined(separator: ",")
        self.skillRaw = skill.rawValue
        self.moduleRaw = module.rawValue
        self.payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
    }

    var kind: PracticeKind { PracticeKind(rawValue: kindRaw) ?? .practice }

    var examIDList: [String] { examIDs.split(separator: ",").map(String.init) }

    var categories: [ExamCategory] {
        categoriesRaw.split(separator: ",").compactMap { ExamCategory(rawValue: String($0)) }
    }

    var skill: ExamSkill { ExamSkill(rawValue: skillRaw) ?? .reading }
    var module: ExamModule { ExamModule(rawValue: moduleRaw) ?? .academic }

    /// 听力记录涉及的 Part（1–4）
    var listeningParts: [Int] {
        categoriesRaw.split(separator: ",").compactMap { $0.hasPrefix("L") ? Int($0.dropFirst()) : nil }
    }

    /// 写作记录涉及的 Task（1–2）
    var writingParts: [Int] {
        categoriesRaw.split(separator: ",").compactMap { $0.hasPrefix("W") ? Int($0.dropFirst()) : nil }
    }

    var kindTitle: String {
        if mockID != nil { return "模考 · \(skill.title)" }
        switch (skill, kind) {
        case (.reading, .practice): return "阅读单篇"
        case (.reading, .fullTest): return "整套阅读"
        case (.listening, .practice): return "听力单个 Part"
        case (.listening, .fullTest): return "整套听力"
        case (.writing, .practice): return "写作单篇"
        case (.writing, .fullTest): return "整套写作"
        }
    }

    var isWriting: Bool { skill == .writing }

    /// 写作总字数
    var wordCount: Int { payload?.parts.reduce(0) { $0 + ($1.wordCount ?? 0) } ?? 0 }

    var accuracy: Double { total > 0 ? Double(score) / Double(total) : 0 }

    var payload: RecordPayload? {
        try? JSONDecoder().decode(RecordPayload.self, from: payloadData)
    }

    var band: String? {
        guard kind == .fullTest else { return nil }
        switch (skill, module) {
        case (.listening, _): return BandScore.listening(score: score, total: total)
        case (.reading, .general): return BandScore.generalReading(score: score, total: total)
        case (.reading, .academic): return BandScore.academicReading(score: score, total: total)
        case (.writing, _): return nil
        }
    }
}

// MARK: - 作答草稿

@Model
final class ExamDraft {
    @Attribute(.unique) var key: String = ""
    var kindRaw: String = PracticeKind.practice.rawValue
    var examIDs: String = ""
    var startedAt: Date = Date()
    var updatedAt: Date = Date()
    var timerKindRaw: String = ExamTimerKind.countdown.rawValue
    var timeLimit: Double = 1200
    var elapsed: Double = 0
    var answered: Int = 0
    var totalQuestions: Int = 0
    var skillRaw: String = ExamSkill.reading.rawValue
    var mockID: UUID?
    @Attribute(.externalStorage) var payloadData: Data = Data()

    init(key: String, kind: PracticeKind, skill: ExamSkill, examIDs: [String], timer: ExamTimerSetting,
         totalQuestions: Int, mockID: UUID?) {
        self.key = key
        self.kindRaw = kind.rawValue
        self.skillRaw = skill.rawValue
        self.mockID = mockID
        self.examIDs = examIDs.joined(separator: ",")
        self.timerKindRaw = timer.kind.rawValue
        self.timeLimit = timer.limit
        self.totalQuestions = totalQuestions
    }

    var kind: PracticeKind { PracticeKind(rawValue: kindRaw) ?? .practice }
    var skill: ExamSkill { ExamSkill(rawValue: skillRaw) ?? .reading }
    var examIDList: [String] { examIDs.split(separator: ",").map(String.init) }
    var timer: ExamTimerSetting {
        ExamTimerSetting(kind: ExamTimerKind(rawValue: timerKindRaw) ?? .countdown, limit: timeLimit)
    }
}

// MARK: - 生词本

@Model
final class VocabEntry {
    @Attribute(.unique) var word: String = ""
    var phonetic: String = ""
    var meaning: String = ""
    var context: String = ""
    var source: String = ""
    var addedAt: Date = Date()
    var due: Date = Date()
    var interval: Double = 0
    var ease: Double = 2.5
    var reps: Int = 0
    var lapses: Int = 0
    var lastReviewed: Date?

    init(word: String, phonetic: String = "", meaning: String, context: String = "", source: String) {
        self.word = word
        self.phonetic = phonetic
        self.meaning = meaning
        self.context = context
        self.source = source
        self.addedAt = Date()
        self.due = Date()
    }

    var isNew: Bool { reps == 0 && lastReviewed == nil }
    var isMastered: Bool { interval >= 21 }
}

// MARK: - 收藏

@Model
final class FavoriteExam {
    @Attribute(.unique) var examId: String = ""
    var addedAt: Date = Date()

    init(examId: String) {
        self.examId = examId
        self.addedAt = Date()
    }
}

// MARK: - 完整模考

enum MockStage: String, Codable, CaseIterable {
    case listening, reading, writing, finished

    var skill: ExamSkill? {
        switch self {
        case .listening: .listening
        case .reading: .reading
        case .writing: .writing
        case .finished: nil
        }
    }
}

/// 一次完整模考（听力 → 阅读 → 写作），可中途退出后继续。
@Model
final class MockTest {
    var id: UUID = UUID()
    var testID: String = ""
    var startedAt: Date = Date()
    var updatedAt: Date = Date()
    var finishedAt: Date?
    var stageRaw: String = MockStage.listening.rawValue
    var listeningRecordID: UUID?
    var readingRecordID: UUID?
    var writingRecordID: UUID?
    /// 写作、口语不自动评分，可自评后估算总分
    var writingBand: Double?
    var speakingBand: Double?

    init(testID: String, firstStage: MockStage) {
        self.id = UUID()
        self.testID = testID
        self.stageRaw = firstStage.rawValue
        self.startedAt = Date()
        self.updatedAt = Date()
    }

    var stage: MockStage {
        get { MockStage(rawValue: stageRaw) ?? .listening }
        set { stageRaw = newValue.rawValue }
    }

    var isFinished: Bool { stage == .finished }

    func recordID(for skill: ExamSkill) -> UUID? {
        switch skill {
        case .listening: listeningRecordID
        case .reading: readingRecordID
        case .writing: writingRecordID
        }
    }

    func setRecordID(_ id: UUID, for skill: ExamSkill) {
        switch skill {
        case .listening: listeningRecordID = id
        case .reading: readingRecordID = id
        case .writing: writingRecordID = id
        }
    }
}

// MARK: - 写作（旧版）

/// 旧版写作编辑器保存的作文，启动时会转换为写作练习记录。
@Model
final class WritingEssay {
    var id: UUID = UUID()
    var promptID: String = ""
    var task: Int = 2
    var prompt: String = ""
    var text: String = ""
    var wordCount: Int = 0
    var duration: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var finished: Bool = false

    init(promptID: String, task: Int, prompt: String) {
        self.id = UUID()
        self.promptID = promptID
        self.task = task
        self.prompt = prompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var minimumWords: Int { task == 1 ? 150 : 250 }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        PracticeRecord.self, ExamDraft.self, VocabEntry.self, FavoriteExam.self, WritingEssay.self, MockTest.self,
        StudyPlan.self,
    ]

    /// 把旧版写作编辑器的作文转换为写作练习记录。
    @MainActor
    static func migrateLegacyEssays(in context: ModelContext) {
        guard let essays = try? context.fetch(FetchDescriptor<WritingEssay>()), !essays.isEmpty else { return }
        let content = ContentStore.shared
        for essay in essays where !essay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let part = PartRecord(examId: essay.promptID, title: content.displayTitle(for: essay.promptID),
                                  category: nil, listeningPart: nil, answers: ["essay": essay.text], questions: [:],
                                  order: ["essay"], score: 0, total: 0, writingPart: essay.task, wordCount: essay.wordCount)
            let record = PracticeRecord(kind: .practice, skill: .writing, module: .academic,
                                        startedAt: essay.createdAt, finishedAt: essay.updatedAt, duration: essay.duration,
                                        score: 0, total: 0, timeUp: false,
                                        payload: RecordPayload(parts: [part], highlights: []))
            context.insert(record)
        }
        essays.forEach(context.delete)
        try? context.save()
    }
}
