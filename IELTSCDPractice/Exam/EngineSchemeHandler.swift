import Foundation
import UniformTypeIdentifiers
import WebKit

/// 为机考引擎提供 `cdpractice://exam/...` 本地资源：
/// `content/...` → App 内置题库，`audio/...` → 已下载的听力音频，其余 → ExamEngine/。
/// 支持 Range 请求，听力音频可以拖动进度。
final class EngineSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cdpractice"
    static let entryURL = URL(string: "cdpractice://exam/exam.html")!

    private let engineRoot: URL
    private let contentRoot: URL
    private let audioRoot: URL
    /// WebKit 调用 stop 之后不能再操作对应的 task。仅在主线程访问。
    private var activeTasks = Set<ObjectIdentifier>()

    init(engineRoot: URL, contentRoot: URL, audioRoot: URL) {
        self.engineRoot = engineRoot.standardizedFileURL
        self.contentRoot = contentRoot.standardizedFileURL
        self.audioRoot = audioRoot.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskID)
        let request = urlSchemeTask.request
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let url = request.url else { return }
            let (response, data) = self.respond(to: request, url: url)
            DispatchQueue.main.async {
                guard self.activeTasks.remove(taskID) != nil else { return }
                urlSchemeTask.didReceive(response)
                if let data { urlSchemeTask.didReceive(data) }
                urlSchemeTask.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - Files

    private func fileURL(for url: URL) -> URL? {
        var path = url.path
        while path.hasPrefix("/") { path.removeFirst() }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        switch components.first {
        case "content": return components.dropFirst().reduce(contentRoot) { $0.appendingPathComponent($1) }
        case "audio": return components.dropFirst().reduce(audioRoot) { $0.appendingPathComponent($1) }
        default: return components.reduce(engineRoot) { $0.appendingPathComponent($1) }
        }
    }

    private func respond(to request: URLRequest, url: URL) -> (URLResponse, Data?) {
        guard let fileURL = fileURL(for: url),
              let handle = try? FileHandle(forReadingFrom: fileURL),
              let size = try? handle.seekToEnd() else {
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!, nil)
        }
        defer { try? handle.close() }

        var headers = [
            "Content-Type": Self.mimeType(for: fileURL.pathExtension),
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
        ]
        var start: UInt64 = 0
        var end: UInt64 = size > 0 ? size - 1 : 0
        var status = 200
        if let range = request.value(forHTTPHeaderField: "Range"), size > 0,
           let parsed = Self.parseRange(range, size: size) {
            start = parsed.lowerBound
            end = parsed.upperBound
            status = 206
            headers["Content-Range"] = "bytes \(start)-\(end)/\(size)"
        }
        let length = size == 0 ? 0 : end - start + 1
        headers["Content-Length"] = "\(length)"
        try? handle.seek(toOffset: start)
        let data = length > 0 ? (try? handle.read(upToCount: Int(length))) ?? Data() : Data()
        return (HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, data)
    }

    static func parseRange(_ header: String, size: UInt64) -> ClosedRange<UInt64>? {
        let value = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard value.hasPrefix("bytes=") else { return nil }
        let spec = value.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]), suffix > 0 else { return nil }
            return (size - min(suffix, size))...(size - 1)
        }
        guard let start = UInt64(parts[0]), start < size else { return nil }
        let end = parts[1].isEmpty ? size - 1 : min(UInt64(parts[1]) ?? size - 1, size - 1)
        return start <= end ? start...end : nil
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        default: return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
