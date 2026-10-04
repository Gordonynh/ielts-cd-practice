import Foundation

/// 简化版 SM-2 间隔重复。
enum ReviewGrade: Int, CaseIterable, Identifiable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: "重来"
        case .hard: "困难"
        case .good: "良好"
        case .easy: "简单"
        }
    }
}

enum VocabScheduler {
    struct Outcome {
        let interval: Double   // 天
        let ease: Double
        let due: Date
    }

    static func preview(_ entry: VocabEntry, grade: ReviewGrade, now: Date = Date()) -> Outcome {
        var ease = entry.ease
        var interval: Double
        switch grade {
        case .again:
            ease = max(1.3, ease - 0.2)
            interval = 0
        case .hard:
            ease = max(1.3, ease - 0.15)
            interval = entry.interval == 0 ? 1 : max(1, entry.interval * 1.2)
        case .good:
            interval = entry.interval == 0 ? 1 : (entry.interval < 3 ? 3 : entry.interval * ease)
        case .easy:
            ease += 0.15
            interval = entry.interval == 0 ? 4 : entry.interval * ease * 1.3
        }
        interval = min(interval, 365)
        let due = grade == .again
            ? now.addingTimeInterval(60)
            : Calendar.current.date(byAdding: .day, value: Int(interval.rounded()), to: Calendar.current.startOfDay(for: now))!
        return Outcome(interval: interval, ease: ease, due: due)
    }

    static func apply(_ grade: ReviewGrade, to entry: VocabEntry, now: Date = Date()) {
        let outcome = preview(entry, grade: grade, now: now)
        entry.interval = outcome.interval
        entry.ease = outcome.ease
        entry.due = outcome.due
        entry.lastReviewed = now
        if grade == .again {
            entry.lapses += 1
        } else {
            entry.reps += 1
        }
    }

    static func label(for outcome: Outcome) -> String {
        if outcome.interval < 1 { return "1 分钟" }
        let days = Int(outcome.interval.rounded())
        if days < 30 { return "\(days) 天" }
        return "\(days / 30) 个月"
    }
}
