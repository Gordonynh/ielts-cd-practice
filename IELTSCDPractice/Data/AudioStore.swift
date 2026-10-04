import Foundation
import Observation

/// 听力音频：默认在线播放；按套下载后离线播放。
@MainActor
@Observable
final class AudioStore {
    static let shared = AudioStore()

    /// 正在下载的套题 → 进度（0–1）
    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]
    /// 每次文件变化时递增，界面据此刷新下载状态
    private(set) var revision = 0

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ListeningAudio", isDirectory: true)
    }

    private init() {
        var url = Self.directory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - State

    nonisolated func localURL(for section: ListeningTest.Section) -> URL {
        Self.directory.appendingPathComponent(section.audioFile)
    }

    func isDownloaded(_ section: ListeningTest.Section) -> Bool {
        _ = revision
        return FileManager.default.fileExists(atPath: localURL(for: section).path)
    }

    func downloadedCount(_ test: ListeningTest) -> Int {
        test.sections.filter(isDownloaded).count
    }

    func isComplete(_ test: ListeningTest) -> Bool {
        downloadedCount(test) == test.sections.count
    }

    func isDownloading(_ test: ListeningTest) -> Bool {
        progress[test.id] != nil
    }

    /// 机考引擎使用的音频地址：已下载用本地文件，否则在线播放。
    func playbackURL(for section: ListeningTest.Section) -> String {
        if FileManager.default.fileExists(atPath: localURL(for: section).path) {
            return "cdpractice://exam/audio/\(section.audioFile)"
        }
        return section.audioUrl
    }

    var totalBytes: Int64 {
        _ = revision
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    var downloadedTestCount: Int {
        _ = revision
        return ContentStore.shared.listeningTests.filter(isComplete).count
    }

    // MARK: - Actions

    func download(_ test: ListeningTest) {
        guard progress[test.id] == nil else { return }
        failures[test.id] = nil
        let pending = test.sections.filter { !isDownloaded($0) }
        guard !pending.isEmpty else { return }
        progress[test.id] = 0

        Task {
            var completed = 0
            var failed: String?
            for section in pending {
                guard let url = URL(string: section.audioUrl) else { continue }
                do {
                    let (temporary, response) = try await URLSession.shared.download(from: url)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    let destination = localURL(for: section)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    revision += 1
                } catch {
                    failed = error.localizedDescription
                }
                completed += 1
                progress[test.id] = Double(completed) / Double(pending.count)
            }
            progress[test.id] = nil
            failures[test.id] = failed
            revision += 1
        }
    }

    func delete(_ test: ListeningTest) {
        for section in test.sections {
            try? FileManager.default.removeItem(at: localURL(for: section))
        }
        revision += 1
    }

    func deleteAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        revision += 1
    }
}
