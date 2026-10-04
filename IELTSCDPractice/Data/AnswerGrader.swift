import Foundation

/// 判分规则：
/// - 忽略大小写、首尾标点、多余空格，弯引号/连字符等写法差异；
/// - 数字中的千分位逗号与空格忽略（60,000 = 60000 = 60 000）；
/// - 答案中的 “/” 表示可选写法（4/four），括号内为可省略部分（(vigorous) exercise）；
/// - 「选出 N 个字母」的多选题按集合判分，与选择顺序无关。
enum AnswerGrader {
    static func grade(_ document: ExamDocument, answers: [String: String], title: String) -> PartRecord {
        var questions: [String: QuestionResult] = [:]

        for group in document.questionGroups where group.multiSelect {
            gradeMultiSelect(group, document: document, answers: answers, into: &questions)
        }

        for questionID in document.questionOrder where questions[questionID] == nil {
            let kind = document.group(of: questionID)?.kind ?? .other
            let expected = document.answerKey[questionID] ?? []
            let given = answers[questionID] ?? ""
            questions[questionID] = QuestionResult(
                number: document.number(of: questionID),
                correct: isCorrect(given: given, expected: expected, kind: kind),
                expected: expected,
                given: given,
                kind: kind
            )
        }

        let score = questions.values.filter(\.correct).count
        return PartRecord(
            examId: document.id,
            title: title,
            category: document.readingCategory,
            listeningPart: document.isListening ? document.part : nil,
            answers: answers,
            questions: questions,
            order: document.questionOrder,
            score: score,
            total: document.questionOrder.count
        )
    }

    private static func gradeMultiSelect(_ group: ExamDocument.Group, document: ExamDocument,
                                         answers: [String: String], into questions: inout [String: QuestionResult]) {
        var expectedSet: [String] = []
        for questionID in group.questionIds {
            for value in document.answerKey[questionID] ?? [] where !expectedSet.contains(where: { normalize($0) == normalize(value) }) {
                expectedSet.append(value)
            }
        }
        var remaining = expectedSet.sorted()
        var used = Set<String>()
        var pending: [String] = []

        for questionID in group.questionIds {
            let given = answers[questionID] ?? ""
            let key = normalize(given)
            if !key.isEmpty, !used.contains(key), let match = remaining.firstIndex(where: { normalize($0) == key }) {
                used.insert(key)
                questions[questionID] = QuestionResult(
                    number: document.number(of: questionID), correct: true,
                    expected: [remaining.remove(at: match)], given: given, kind: group.kind
                )
            } else {
                pending.append(questionID)
            }
        }
        for questionID in pending {
            let expected = remaining.isEmpty ? [] : [remaining.removeFirst()]
            questions[questionID] = QuestionResult(
                number: document.number(of: questionID), correct: false,
                expected: expected, given: answers[questionID] ?? "", kind: group.kind
            )
        }
    }

    static func isCorrect(given: String, expected: [String], kind: QuestionKind) -> Bool {
        let answer = canonical(normalize(given), kind: kind)
        guard !answer.isEmpty else { return false }
        return expected.contains { key in
            variants(of: key).contains { canonical(normalize($0), kind: kind) == answer }
        }
    }

    /// 把一个答案展开为所有可接受的写法。
    static func variants(of key: String) -> [String] {
        var results: [String] = [key]

        if key.contains("/"), key.range(of: #"^\s*\d+\s*/\s*\d+\s*$"#, options: .regularExpression) == nil {
            results += key.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        var expanded: [String] = []
        for candidate in results where candidate.contains("(") {
            let without = candidate.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            let with = candidate.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
            expanded += [without, with]
        }
        return (results + expanded).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func normalize(_ value: String) -> String {
        var text = value.lowercased()
        let replacements: [(String, String)] = [
            ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{00A0}", " "),
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        // 数字中的千分位
        text = text.replacingOccurrences(of: #"(?<=\d)[,\s](?=\d{3}\b)"#, with: "", options: .regularExpression)
        // 连字符与空格视为相同
        text = text.replacingOccurrences(of: "-", with: " ")
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let edge = CharacterSet(charactersIn: ".,;:!?\"'()[] ").union(.whitespacesAndNewlines)
        return text.trimmingCharacters(in: edge)
    }

    private static func canonical(_ value: String, kind: QuestionKind) -> String {
        switch kind {
        case .trueFalseNotGiven, .yesNoNotGiven:
            switch value {
            case "t": return "true"
            case "f": return "false"
            case "y": return "yes"
            case "n": return "no"
            case "ng", "not given", "notgiven": return "not given"
            default: return value
            }
        default:
            return value
        }
    }
}

/// 原始分 → 雅思分数（按 40 题折算），分别对应学术类阅读、培训类阅读与听力的官方换算表。
enum BandScore {
    private static let generalTable: [(minimum: Int, band: String)] = [
        (40, "9.0"), (39, "8.5"), (37, "8.0"), (36, "7.5"), (34, "7.0"), (32, "6.5"), (30, "6.0"),
        (27, "5.5"), (23, "5.0"), (19, "4.5"), (15, "4.0"), (12, "3.5"), (9, "3.0"), (6, "2.5"), (1, "2.0"),
    ]

    private static let listeningTable: [(minimum: Int, band: String)] = [
        (39, "9.0"), (37, "8.5"), (35, "8.0"), (32, "7.5"), (30, "7.0"), (26, "6.5"), (23, "6.0"),
        (18, "5.5"), (16, "5.0"), (13, "4.5"), (10, "4.0"), (8, "3.5"), (6, "3.0"), (4, "2.5"), (1, "2.0"),
    ]

    private static let table: [(minimum: Int, band: String)] = [
        (39, "9.0"), (37, "8.5"), (35, "8.0"), (33, "7.5"), (30, "7.0"), (27, "6.5"),
        (23, "6.0"), (19, "5.5"), (15, "5.0"), (13, "4.5"), (10, "4.0"), (8, "3.5"),
        (6, "3.0"), (4, "2.5"), (2, "2.0"), (1, "1.0"),
    ]

    static func academicReading(score: Int, total: Int) -> String? {
        lookup(table, score: score, total: total)
    }

    static func generalReading(score: Int, total: Int) -> String? {
        lookup(generalTable, score: score, total: total)
    }

    static func listening(score: Int, total: Int) -> String? {
        lookup(listeningTable, score: score, total: total)
    }

    /// 总分：四科平均后按官方规则取整（尾数 .25 进到 .5，.75 进到整数）
    static func overall(_ bands: [Double]) -> Double? {
        guard !bands.isEmpty else { return nil }
        let average = bands.reduce(0, +) / Double(bands.count)
        let whole = average.rounded(.down)
        switch average - whole {
        case ..<0.25: return whole
        case ..<0.75: return whole + 0.5
        default: return whole + 1
        }
    }

    /// 达到某个分数所需的最低原始分（40 题）
    static func minimumListening(for band: Double) -> Int? {
        minimum(listeningTable, band: band)
    }

    static func minimumAcademicReading(for band: Double) -> Int? {
        minimum(table, band: band)
    }

    private static func minimum(_ table: [(minimum: Int, band: String)], band: Double) -> Int? {
        table.filter { (Double($0.band) ?? 0) >= band }.map(\.minimum).min()
    }

    static func format(_ band: Double) -> String {
        String(format: "%.1f", band)
    }

    /// 整数分不带小数（8、6.5、7.7）
    static func short(_ band: Double) -> String {
        band == band.rounded() ? String(format: "%.0f", band) : String(format: "%.1f", band)
    }

    private static func lookup(_ table: [(minimum: Int, band: String)], score: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        let scaled = Int((Double(score) * 40 / Double(total)).rounded())
        return table.first { scaled >= $0.minimum }?.band ?? "0"
    }
}
