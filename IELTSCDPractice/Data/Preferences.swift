import Foundation

enum ExamTimerKind: String, Codable, CaseIterable, Identifiable {
    case countdown
    case countup
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: "倒计时"
        case .countup: "正计时"
        case .none: "不计时"
        }
    }
}

struct ExamTimerSetting: Hashable {
    var kind: ExamTimerKind
    var limit: TimeInterval
}

enum ExamContrast: String, CaseIterable, Identifiable {
    case standard, inverse, yellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "白底黑字"
        case .inverse: "黑底白字"
        case .yellow: "黑底黄字"
        }
    }
}

enum ExamTextSize: String, CaseIterable, Identifiable {
    case regular, large, xlarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "标准"
        case .large: "大"
        case .xlarge: "特大"
        }
    }
}

/// 所有设置项的 UserDefaults 键与默认值，界面中用 @AppStorage 读取。
enum PreferenceKey {
    static let timerKind = "exam.timerKind"
    static let practiceMinutes = "exam.practiceMinutes"
    static let fullTestMinutes = "exam.fullTestMinutes"
    static let contrast = "exam.contrast"
    static let textSize = "exam.textSize"
    static let splitRatio = "exam.splitRatio"
    static let hideTimer = "exam.hideTimer"
    static let candidateID = "exam.candidateID"
    static let dailyNewWords = "vocab.dailyNewWords"
}

enum Preferences {
    static var defaults: UserDefaults { .standard }

    static func register() {
        defaults.register(defaults: [
            PreferenceKey.timerKind: ExamTimerKind.countdown.rawValue,
            PreferenceKey.practiceMinutes: 20,
            PreferenceKey.fullTestMinutes: 60,
            PreferenceKey.contrast: ExamContrast.standard.rawValue,
            PreferenceKey.textSize: ExamTextSize.regular.rawValue,
            PreferenceKey.splitRatio: 0.5,
            PreferenceKey.hideTimer: false,
            PreferenceKey.dailyNewWords: 10,
        ])
        if defaults.string(forKey: PreferenceKey.candidateID) == nil {
            let digits = (0..<8).map { _ in String(Int.random(in: 0...9)) }.joined()
            defaults.set("\(digits.prefix(4)) \(digits.suffix(4))", forKey: PreferenceKey.candidateID)
        }
    }

    /// 阅读计时：单篇按设置（默认 20 分钟），整套按设置（默认 60 分钟）
    static func timer(for kind: PracticeKind) -> ExamTimerSetting {
        let timerKind = ExamTimerKind(rawValue: defaults.string(forKey: PreferenceKey.timerKind) ?? "") ?? .countdown
        let minutes = kind == .fullTest
            ? defaults.integer(forKey: PreferenceKey.fullTestMinutes)
            : defaults.integer(forKey: PreferenceKey.practiceMinutes)
        return ExamTimerSetting(kind: timerKind, limit: TimeInterval(max(minutes, 1) * 60))
    }

    /// 写作计时：Task 1 为 20 分钟、Task 2 为 40 分钟，两篇一起为 60 分钟
    static func writingTimer(parts: [Int]) -> ExamTimerSetting {
        let timerKind = ExamTimerKind(rawValue: defaults.string(forKey: PreferenceKey.timerKind) ?? "") ?? .countdown
        let minutes = parts.reduce(0) { $0 + ($1 == 1 ? 20 : 40) }
        return ExamTimerSetting(kind: timerKind, limit: TimeInterval(max(minutes, 20) * 60))
    }

    /// 模考按官方时长计时，不受设置影响
    static func officialTimer(for skill: ExamSkill) -> ExamTimerSetting {
        switch skill {
        case .listening: ExamTimerSetting(kind: .none, limit: 0)
        case .reading, .writing: ExamTimerSetting(kind: .countdown, limit: 3600)
        }
    }

    static var examPreferences: [String: Any] {
        [
            "contrast": defaults.string(forKey: PreferenceKey.contrast) ?? "standard",
            "textSize": defaults.string(forKey: PreferenceKey.textSize) ?? "regular",
            "split": defaults.double(forKey: PreferenceKey.splitRatio),
            "hideTimer": defaults.bool(forKey: PreferenceKey.hideTimer),
        ]
    }

    static func updateExamPreferences(from payload: [String: Any]) {
        if let contrast = payload["contrast"] as? String { defaults.set(contrast, forKey: PreferenceKey.contrast) }
        if let textSize = payload["textSize"] as? String { defaults.set(textSize, forKey: PreferenceKey.textSize) }
        if let split = payload["split"] as? Double { defaults.set(split, forKey: PreferenceKey.splitRatio) }
        if let hide = payload["hideTimer"] as? Bool { defaults.set(hide, forKey: PreferenceKey.hideTimer) }
    }

    static var candidateID: String {
        defaults.string(forKey: PreferenceKey.candidateID) ?? "0000 0000"
    }
}
