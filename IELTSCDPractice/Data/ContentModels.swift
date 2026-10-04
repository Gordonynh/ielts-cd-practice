import SwiftUI

// MARK: - 题库分类

enum ExamCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p1: "Passage 1"
        case .p2: "Passage 2"
        case .p3: "Passage 3"
        }
    }

    var shortTitle: String { rawValue }

    var part: Int {
        switch self {
        case .p1: 1
        case .p2: 2
        case .p3: 3
        }
    }

    var subtitle: String {
        switch self {
        case .p1: "难度较低，题号 1–13"
        case .p2: "中等难度，题号 14–26"
        case .p3: "难度最高，题号 27–40"
        }
    }
}

enum ExamFrequency: String, Codable, CaseIterable, Identifiable, Hashable {
    case high, medium, low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "高频"
        case .medium: "中频"
        case .low: "低频"
        }
    }

    var color: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .low: .secondary
        }
    }
}

enum QuestionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case matching
    case matchingHeadings = "matching_headings"
    case matchingInformation = "matching_information"
    case matchingFeatures = "matching_features"
    case matchingSentenceEndings = "matching_sentence_endings"
    case trueFalseNotGiven = "true_false_not_given"
    case yesNoNotGiven = "yes_no_not_given"
    case singleChoice = "single_choice"
    case multiChoice = "multi_choice"
    case sentenceCompletion = "sentence_completion"
    case summaryCompletion = "summary_completion"
    case notesCompletion = "notes_completion"
    case tableCompletion = "table_completion"
    case flowChartCompletion = "flow_chart_completion"
    case diagramCompletion = "diagram_completion"
    case shortAnswer = "short_answer"
    case classification
    case other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = QuestionKind(rawValue: raw) ?? .other
    }

    var title: String {
        switch self {
        case .matching: "匹配题"
        case .matchingHeadings: "段落标题匹配"
        case .matchingInformation: "段落信息匹配"
        case .matchingFeatures: "特征匹配"
        case .matchingSentenceEndings: "句尾匹配"
        case .trueFalseNotGiven: "判断题 T/F/NG"
        case .yesNoNotGiven: "判断题 Y/N/NG"
        case .singleChoice: "单选题"
        case .multiChoice: "多选题"
        case .sentenceCompletion: "句子填空"
        case .summaryCompletion: "摘要填空"
        case .notesCompletion: "笔记填空"
        case .tableCompletion: "表格题"
        case .flowChartCompletion: "流程图填空"
        case .diagramCompletion: "图表填空"
        case .shortAnswer: "简答题"
        case .classification: "分类题"
        case .other: "其他题型"
        }
    }

    var symbol: String {
        switch self {
        case .matching, .classification, .matchingFeatures, .matchingSentenceEndings: "arrow.left.arrow.right"
        case .matchingHeadings: "text.line.first.and.arrowtriangle.forward"
        case .matchingInformation: "text.magnifyingglass"
        case .trueFalseNotGiven, .yesNoNotGiven: "checkmark.circle"
        case .singleChoice: "smallcircle.filled.circle"
        case .multiChoice: "checklist"
        case .sentenceCompletion, .summaryCompletion, .notesCompletion, .shortAnswer: "character.cursor.ibeam"
        case .tableCompletion: "tablecells"
        case .flowChartCompletion: "arrow.down.forward.and.arrow.up.backward"
        case .diagramCompletion: "photo"
        case .other: "questionmark.circle"
        }
    }
}

// MARK: - 题库来源

enum ExamSkill: String, Codable, CaseIterable, Identifiable {
    case listening, reading, writing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: "听力"
        case .reading: "阅读"
        case .writing: "写作"
        }
    }

    var englishTitle: String {
        switch self {
        case .listening: "Listening"
        case .reading: "Reading"
        case .writing: "Writing"
        }
    }

    var symbol: String {
        switch self {
        case .listening: "headphones"
        case .reading: "book"
        case .writing: "square.and.pencil"
        }
    }
}

enum ExamModule: String, Codable, CaseIterable, Identifiable {
    case academic, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .academic: "学术类"
        case .general: "培训类"
        }
    }
}

enum ExamSource: String, CaseIterable, Identifiable {
    case cambridge, mock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cambridge: "剑桥真题"
        case .mock: "模拟题"
        }
    }

    var shortTitle: String {
        switch self {
        case .cambridge: "剑桥"
        case .mock: "模拟"
        }
    }
}

// MARK: - 题目列表

struct ExamSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let titleZh: String
    let category: ExamCategory
    let frequency: ExamFrequency
    let difficulty: Double?
    let questionCount: Int
    let firstQuestionNumber: Int
    let questionKinds: [QuestionKind]
    let hasExplanation: Bool
    let wordCount: Int
    /// 题库来源：cambridge（剑桥真题）或其他模拟题
    var source: String?
    var module: String?
    var setId: String?
    var setTitle: String?
    var part: Int?

    /// 属于整套试卷（题库中的阅读都属于某一套）
    var isBank: Bool { source != nil }
    var isCambridge: Bool { source == "cambridge" }
    var examSource: ExamSource { isCambridge ? .cambridge : .mock }
    var examModule: ExamModule { ExamModule(rawValue: module ?? "") ?? .academic }

    /// 列表中显示的副标题：中文标题或所属试卷
    var subtitle: String {
        if let setTitle { return setTitle + (part.map { " · Passage \($0)" } ?? "") }
        return titleZh
    }

    var questionRange: String {
        "\(firstQuestionNumber)–\(firstQuestionNumber + questionCount - 1)"
    }

    /// 1–5 星；上游难度分为 1–5，缺失时按分类估计。
    var difficultyStars: Int {
        if let difficulty { return min(max(Int(difficulty.rounded()), 1), 5) }
        switch category {
        case .p1: return 2
        case .p2: return 3
        case .p3: return 4
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || titleZh.localizedCaseInsensitiveContains(query)
            || (setTitle?.localizedCaseInsensitiveContains(query) ?? false)
            || id.localizedCaseInsensitiveContains(query)
    }
}

// MARK: - 单篇题目

struct ExamDocument: Codable, Hashable {
    struct Group: Codable, Hashable {
        let id: String
        let kind: QuestionKind
        let questionIds: [String]
        let html: String
        let allowOptionReuse: Bool
        let multiSelect: Bool
    }

    let id: String
    let title: String
    let titleZh: String
    /// 阅读为 P1–P3，听力为 L1–L4
    let category: String
    let frequency: ExamFrequency
    var skill: String?
    var part: Int?
    let passageHtml: String
    let questionGroups: [Group]
    let questionOrder: [String]
    let questionNumbers: [String: String]
    let answerKey: [String: [String]]

    var readingCategory: ExamCategory? { ExamCategory(rawValue: category) }
    var isListening: Bool { skill == ExamSkill.listening.rawValue }

    func number(of questionID: String) -> String {
        questionNumbers[questionID] ?? questionID.replacingOccurrences(of: "q", with: "")
    }

    func group(of questionID: String) -> Group? {
        questionGroups.first { $0.questionIds.contains(questionID) }
    }
}

/// 一整套剑桥阅读（Passage 1–3）。
struct ReadingSet: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let module: String
    let book: Int?
    let test: String
    var series: String?
    let passages: [String]

    var examModule: ExamModule { ExamModule(rawValue: module) ?? .academic }
}

/// 一整套剑桥听力（Part 1–4）。
struct ListeningTest: Codable, Identifiable, Hashable {
    struct Section: Codable, Identifiable, Hashable {
        let id: String
        let part: Int
        let topic: String
        let questionCount: Int
        let firstQuestionNumber: Int
        let questionKinds: [QuestionKind]
        let audioUrl: String
        let audioFile: String
        let hasTranscript: Bool
        let hasExplanation: Bool

        var questionRange: String {
            "\(firstQuestionNumber)–\(firstQuestionNumber + questionCount - 1)"
        }

        var displayTopic: String { topic.isEmpty ? "Questions \(questionRange)" : topic }
    }

    let id: String
    let title: String
    let module: String
    let book: Int?
    let test: String
    var series: String?
    let sections: [Section]

    var examModule: ExamModule { ExamModule(rawValue: module) ?? .academic }
    var bookTitle: String { series ?? book.map { "剑桥雅思 \($0)" } ?? "其他" }
    var shortTitle: String { "Test \(test)" }
    var questionCount: Int { sections.reduce(0) { $0 + $1.questionCount } }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || sections.contains { $0.topic.localizedCaseInsensitiveContains(query) }
    }
}

/// 剑桥真题写作（Task 1 含图表，部分附参考范文）。
struct CambridgeWritingTask: Codable, Identifiable, Hashable {
    let id: String
    let setId: String
    let setTitle: String
    let series: String?
    let module: String
    let part: Int
    let type: String
    let minWords: Int
    let prompt: String
    let image: String?
    let essay: String?

    var typeTitle: String {
        switch type {
        case "chart": "图表"
        case "table": "表格"
        case "map": "地图"
        case "process": "流程图"
        case "letter": "书信"
        default: "议论文"
        }
    }
}

struct BankIndex: Codable {
    let reading: [ExamSummary]
    let readingSets: [ReadingSet]
    let listening: [ListeningTest]
    var writing: [CambridgeWritingTask]?
    var generatedAt: String?
}

struct ExamExplanation: Codable, Hashable {
    struct PassageNote: Codable, Hashable {
        let label: String
        let text: String
    }

    let id: String
    let passageNotes: [PassageNote]
    let questionNotes: [String: String]
}

struct CoreWord: Codable, Identifiable, Hashable {
    let word: String
    let meaning: String
    let example: String
    let frequency: Double

    var id: String { word }
}
