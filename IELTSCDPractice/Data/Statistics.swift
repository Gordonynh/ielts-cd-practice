import Foundation

/// 从练习记录派生的统计数据。
struct PracticeStatistics {
    struct DayActivity: Identifiable {
        let day: Date
        let minutes: Double
        let sessions: Int
        var id: Date { day }
    }

    struct KindAccuracy: Identifiable {
        let kind: QuestionKind
        let correct: Int
        let total: Int
        var id: QuestionKind { kind }
        var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    }

    struct CategoryProgress: Identifiable {
        let category: ExamCategory
        let practiced: Int
        let total: Int
        let accuracy: Double?
        var id: ExamCategory { category }
        var fraction: Double { total > 0 ? Double(practiced) / Double(total) : 0 }
    }

    struct ExamBest {
        let bestAccuracy: Double
        let attempts: Int
        let lastPracticed: Date
        let hasMistakes: Bool
    }

    let records: [PracticeRecord]
    let practicedExamIDs: Set<String>
    let examBest: [String: ExamBest]
    let totalCorrect: Int
    let totalQuestions: Int
    let totalSeconds: Double

    init(records: [PracticeRecord]) {
        self.records = records
        var practiced = Set<String>()
        var best: [String: ExamBest] = [:]
        var correct = 0
        var questions = 0
        var seconds = 0.0
        for record in records {
            correct += record.score
            questions += record.total
            seconds += record.duration
            for part in record.payload?.parts ?? [] {
                practiced.insert(part.examId)
                // 写作不判分，只计入「已练习」
                guard part.total > 0 else { continue }
                let accuracy = Double(part.score) / Double(part.total)
                let previous = best[part.examId]
                best[part.examId] = ExamBest(
                    bestAccuracy: max(previous?.bestAccuracy ?? 0, accuracy),
                    attempts: (previous?.attempts ?? 0) + 1,
                    lastPracticed: max(previous?.lastPracticed ?? .distantPast, record.finishedAt),
                    hasMistakes: (previous?.hasMistakes ?? false) || part.score < part.total
                )
            }
        }
        practicedExamIDs = practiced
        examBest = best
        totalCorrect = correct
        totalQuestions = questions
        totalSeconds = seconds
    }

    var accuracy: Double { totalQuestions > 0 ? Double(totalCorrect) / Double(totalQuestions) : 0 }

    var totalMinutes: Int { Int((totalSeconds / 60).rounded()) }

    /// 连续练习天数（今天或昨天有练习时才计入）。
    var streak: Int {
        let calendar = Calendar.current
        let days = Set(records.map { calendar.startOfDay(for: $0.finishedAt) })
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    func activity(lastDays: Int) -> [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var minutes: [Date: Double] = [:]
        var sessions: [Date: Int] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.finishedAt)
            minutes[day, default: 0] += record.duration / 60
            sessions[day, default: 0] += 1
        }
        return (0..<lastDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayActivity(day: day, minutes: minutes[day] ?? 0, sessions: sessions[day] ?? 0)
        }
    }

    var kindAccuracy: [KindAccuracy] {
        var correct: [QuestionKind: Int] = [:]
        var total: [QuestionKind: Int] = [:]
        for record in records {
            for part in record.payload?.parts ?? [] {
                for result in part.questions.values {
                    total[result.kind, default: 0] += 1
                    if result.correct { correct[result.kind, default: 0] += 1 }
                }
            }
        }
        return total.keys.map { KindAccuracy(kind: $0, correct: correct[$0] ?? 0, total: total[$0] ?? 0) }
            .sorted { $0.accuracy < $1.accuracy }
    }

    func categoryProgress(content: ContentStore) -> [CategoryProgress] {
        ExamCategory.allCases.map { category in
            let ids = Set(content.readingPassages.filter { $0.category == category }.map(\.id))
            var correct = 0
            var total = 0
            for record in records {
                for part in record.payload?.parts ?? [] where part.category == category {
                    correct += part.score
                    total += part.total
                }
            }
            return CategoryProgress(
                category: category,
                practiced: ids.intersection(practicedExamIDs).count,
                total: ids.count,
                accuracy: total > 0 ? Double(correct) / Double(total) : nil
            )
        }
    }
}

extension TimeInterval {
    /// 12:34 或 1:02:03
    var clockString: String {
        let total = Int(self.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    var minutesString: String {
        let minutes = Int((self / 60).rounded())
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }
}

extension Double {
    var percentString: String { "\(Int((self * 100).rounded()))%" }
}
