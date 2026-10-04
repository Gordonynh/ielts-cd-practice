import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 备份文件格式（JSON）：练习记录、生词本、收藏。
struct BackupArchive: Codable {
    struct Record: Codable {
        var id: UUID
        var kind: String
        var startedAt: Date
        var finishedAt: Date
        var duration: Double
        var score: Int
        var total: Int
        var timeUp: Bool
        var skill: String?
        var module: String?
        var payload: RecordPayload
    }

    struct Word: Codable {
        var word: String
        var phonetic: String
        var meaning: String
        var context: String
        var source: String
        var addedAt: Date
        var due: Date
        var interval: Double
        var ease: Double
        var reps: Int
        var lapses: Int
        var lastReviewed: Date?
    }

    static let currentFormat = "ielts-cd-practice-backup"

    var format = BackupArchive.currentFormat
    var version = 1
    var exportedAt = Date()
    var records: [Record]
    var words: [Word]
    var favorites: [String]
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var archive: BackupArchive

    init(archive: BackupArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        archive = try BackupService.decoder.decode(BackupArchive.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BackupService.encoder.encode(archive))
    }
}

enum BackupService {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @MainActor
    static func makeArchive(context: ModelContext) throws -> BackupArchive {
        let records = try context.fetch(FetchDescriptor<PracticeRecord>(sortBy: [SortDescriptor(\.finishedAt)]))
        let words = try context.fetch(FetchDescriptor<VocabEntry>(sortBy: [SortDescriptor(\.addedAt)]))
        let favorites = try context.fetch(FetchDescriptor<FavoriteExam>())
        return BackupArchive(
            records: records.compactMap { record in
                guard let payload = record.payload else { return nil }
                return BackupArchive.Record(
                    id: record.id, kind: record.kindRaw, startedAt: record.startedAt, finishedAt: record.finishedAt,
                    duration: record.duration, score: record.score, total: record.total, timeUp: record.timeUp,
                    skill: record.skillRaw, module: record.moduleRaw, payload: payload
                )
            },
            words: words.map {
                BackupArchive.Word(
                    word: $0.word, phonetic: $0.phonetic, meaning: $0.meaning, context: $0.context, source: $0.source,
                    addedAt: $0.addedAt, due: $0.due, interval: $0.interval, ease: $0.ease, reps: $0.reps,
                    lapses: $0.lapses, lastReviewed: $0.lastReviewed
                )
            },
            favorites: favorites.map(\.examId)
        )
    }

    struct RestoreSummary {
        var records = 0
        var words = 0
        var favorites = 0
    }

    /// 合并恢复：已存在的记录（相同 ID）与单词不会重复导入。
    @MainActor
    static func restore(_ archive: BackupArchive, into context: ModelContext) throws -> RestoreSummary {
        // 早期版本的备份格式名不同，但都以 backup 结尾、结构相同
        guard archive.format.hasSuffix("backup") else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "不是本 App 的备份文件"])
        }
        var summary = RestoreSummary()
        let existingRecords = Set(try context.fetch(FetchDescriptor<PracticeRecord>()).map(\.id))
        for item in archive.records where !existingRecords.contains(item.id) {
            let record = PracticeRecord(
                kind: PracticeKind(rawValue: item.kind) ?? .practice,
                skill: ExamSkill(rawValue: item.skill ?? "") ?? .reading,
                module: ExamModule(rawValue: item.module ?? "") ?? .academic,
                startedAt: item.startedAt,
                finishedAt: item.finishedAt, duration: item.duration, score: item.score, total: item.total,
                timeUp: item.timeUp, payload: item.payload
            )
            record.id = item.id
            context.insert(record)
            summary.records += 1
        }
        let existingWords = Set(try context.fetch(FetchDescriptor<VocabEntry>()).map(\.word))
        for item in archive.words where !existingWords.contains(item.word) {
            let entry = VocabEntry(word: item.word, phonetic: item.phonetic, meaning: item.meaning,
                                   context: item.context, source: item.source)
            entry.addedAt = item.addedAt
            entry.due = item.due
            entry.interval = item.interval
            entry.ease = item.ease
            entry.reps = item.reps
            entry.lapses = item.lapses
            entry.lastReviewed = item.lastReviewed
            context.insert(entry)
            summary.words += 1
        }
        let existingFavorites = Set(try context.fetch(FetchDescriptor<FavoriteExam>()).map(\.examId))
        for examId in archive.favorites where !existingFavorites.contains(examId) {
            context.insert(FavoriteExam(examId: examId))
            summary.favorites += 1
        }
        try context.save()
        return summary
    }

    static func markdownReport(records: [PracticeRecord]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = ["# IELTS 练习报告", "", "导出时间：\(formatter.string(from: Date()))", ""]
        let stats = PracticeStatistics(records: records)
        lines += [
            "- 练习次数：\(records.count)",
            "- 总正确率：\(stats.accuracy.percentString)（\(stats.totalCorrect)/\(stats.totalQuestions)）",
            "- 累计时长：\(stats.totalSeconds.minutesString)", "",
            "| 时间 | 类型 | 题目 | 得分 | 正确率 | 用时 |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for record in records.sorted(by: { $0.finishedAt > $1.finishedAt }) {
            let title = record.title.replacingOccurrences(of: "|", with: "/")
            var score = "\(record.score)/\(record.total)"
            if let band = record.band { score += "（Band \(band)）" }
            lines.append("| \(formatter.string(from: record.finishedAt)) | \(record.kindTitle) | \(title) | \(score) | \(record.accuracy.percentString) | \(record.duration.clockString) |")
        }
        return lines.joined(separator: "\n")
    }
}
