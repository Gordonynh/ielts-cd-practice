import Foundation
import SwiftUI

// MARK: - 机经考情

struct JijingItem: Codable, Identifiable, Hashable {
    let id: String
    let code: String
    let skill: String
    let part: Int?
    let title: String
    let topic: String
    let difficulty: Int?
    let practiceCount: Int
    let correctRate: Int?
    let retestCount: Int
    let lastHitDate: String?
    let questionTypes: [String]
    let question: String?
    /// App 内对应的篇目（阅读 examId / 听力 sectionId）
    let match: String?

    var lastHit: Date? { lastHitDate.flatMap(ExtrasStore.parseDate) }

    var isRecent: Bool {
        guard let lastHit else { return false }
        return lastHit > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    }

    var partLabel: String {
        guard let part else { return "" }
        switch skill {
        case "listening": return "Part \(part)"
        case "reading": return "P\(part)"
        default: return "Task \(part)"
        }
    }

    /// 科目主题色
    var tint: Color {
        switch skill {
        case "listening": ExamSkill.listening.tint
        case "reading": ExamSkill.reading.tint
        default: ExamSkill.writing.tint
        }
    }

    /// 0–3 → 简单 / 中等 / 较难 / 难
    var difficultyText: String? {
        guard let difficulty else { return nil }
        return ["简单", "中等", "较难", "难"][min(max(difficulty, 0), 3)]
    }
}

// MARK: - 考试回忆

struct ExamRecall: Codable, Identifiable, Hashable {
    struct Item: Codable, Hashable {
        let part: Int?
        let code: String?
        let theme: String?
        let questionTypes: String?
        let keywords: String?
        let rating: Int?
        let note: String?
        let image: String?
        let jijing: String?
        let match: String?
    }

    struct Task: Codable, Hashable {
        let task: Int?
        let question: String?
        let note: String?
        let image: String?
        let jijing: String?
    }

    let id: String
    let date: String
    let place: String
    let module: String
    let listening: [Item]
    let reading: [Item]
    let writing: [Task]

    var day: Date? { ExtrasStore.parseDate(date) }
}

// MARK: - 口语

struct SpeakingBank: Codable {
    struct Audio: Codable, Hashable {
        let accent: String
        let url: String
    }

    struct Question: Codable, Identifiable, Hashable {
        let id: String
        /// 1 / 2（题卡）/ 3
        var part: Int?
        let text: String
        let sample: String
        let audio: [Audio]

        var isCueCard: Bool { part == 2 }
    }

    struct Topic: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        /// 1 = Part 1，2 = Part 2 & 3
        let part: Int
        let category: String
        let recentExamCount: Int
        let practiceText: String
        let questions: [Question]
    }

    struct ExaminerLine: Codable, Hashable {
        let text: String
        let audio: String
    }

    let season: String
    let topics: [Topic]
    let examiner: [ExaminerLine]
}

struct ExtrasData: Codable {
    let jijing: [JijingItem]
    let recentHits: [String]
    let exams: [ExamRecall]
    let speaking: SpeakingBank
}

// MARK: - Store

/// 题库包扩展数据（scripts/build-extras.mjs 生成的 Content/bank/extras.json）。
final class ExtrasStore {
    static let shared = ExtrasStore()

    let data: ExtrasData?
    private let byID: [String: JijingItem]
    private let byMatch: [String: JijingItem]
    private let recallsByJijing: [String: [ExamRecall]]
    private let recallsByMatch: [String: [ExamRecall]]

    var isAvailable: Bool { data != nil }
    var jijing: [JijingItem] { data?.jijing ?? [] }
    var exams: [ExamRecall] { data?.exams ?? [] }
    var speaking: SpeakingBank? { data?.speaking }

    var recentHits: [JijingItem] {
        (data?.recentHits ?? []).compactMap { byID[$0] }
    }

    private init() {
        let url = ContentStore.shared.rootURL.appendingPathComponent("bank/extras.json")
        data = try? JSONDecoder().decode(ExtrasData.self, from: Data(contentsOf: url))
        let items = data?.jijing ?? []
        byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byMatch = Dictionary(items.compactMap { item in item.match.map { ($0, item) } },
                             uniquingKeysWith: { first, second in first.retestCount >= second.retestCount ? first : second })
        var jijingIndex: [String: [ExamRecall]] = [:]
        var matchIndex: [String: [ExamRecall]] = [:]
        for exam in data?.exams ?? [] {
            for item in exam.listening + exam.reading {
                if let id = item.jijing { jijingIndex[id, default: []].append(exam) }
                if let id = item.match { matchIndex[id, default: []].append(exam) }
            }
            for task in exam.writing {
                if let id = task.jijing { jijingIndex[id, default: []].append(exam) }
            }
        }
        recallsByJijing = jijingIndex.mapValues(Self.unique)
        recallsByMatch = matchIndex.mapValues(Self.unique)
    }

    func item(_ id: String) -> JijingItem? { byID[id] }

    /// App 内某篇阅读 / 听力 Part 对应的机经数据
    func jijing(forContent id: String) -> JijingItem? { byMatch[id] }

    func items(skill: ExamSkill) -> [JijingItem] {
        jijing.filter { $0.skill == skill.rawValue }
    }

    var writingPrompts: [JijingItem] {
        jijing.filter { $0.skill == "writing" && ($0.question?.isEmpty == false) }
    }

    /// 出现过某道机经或某篇 App 内题目的考试回忆
    func recalls(jijing id: String?, content: String?) -> [ExamRecall] {
        var result: [ExamRecall] = []
        if let id { result += recallsByJijing[id] ?? [] }
        if let content { result += recallsByMatch[content] ?? [] }
        return Self.unique(result)
    }

    private static func unique(_ exams: [ExamRecall]) -> [ExamRecall] {
        var seen = Set<String>()
        return exams.filter { seen.insert($0.id).inserted }.sorted { $0.date > $1.date }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseDate(_ text: String) -> Date? {
        formatter.date(from: String(text.prefix(10)))
    }
}

extension Date {
    /// 「3 天前」「2 个月前」
    var agoDescription: String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: self),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return "今天"
        case 1: return "昨天"
        case 2..<31: return "\(days) 天前"
        case 31..<365: return "\(days / 30) 个月前"
        default: return "\(days / 365) 年前"
        }
    }
}
