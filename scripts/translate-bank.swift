// =============================================================================
// 用 Apple 翻译（Translation 框架，本机离线模型）为题库包中没有中文翻译的内容补充译文。
//
// 用法（macOS 26 及以上，需在「系统设置 → 通用 → 语言与地区 → 翻译语言」中下载英语与简体中文）:
//   xcrun swiftc scripts/translate-bank.swift -o /tmp/translate-bank && /tmp/translate-bank [题库包目录]
//
// 输出: <题库包目录>/translations.json（缓存，可重复运行，只翻译新增内容）
//   reading:   { "<套题id>-p<Part>": ["段落译文", …] }       —— 没有 translation 的文章
//   listening: { "<套题id>-l<Part>": { "<行号>": "译文" } } —— 原文中缺少中文的句子
// =============================================================================
import Foundation
import Translation

setvbuf(stdout, nil, _IONBF, 0)

struct Cache: Codable {
    var reading: [String: [String]] = [:]
    var listening: [String: [String: String]] = [:]
}

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "bank-source")
let cacheURL = root.appendingPathComponent("translations.json")
var cache = (try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL))) ?? Cache()

let source = Locale.Language(identifier: "en")
let target = Locale.Language(identifier: "zh-Hans")
let status = await LanguageAvailability().status(from: source, to: target)
guard status == .installed else {
    print("ERROR: 英语 → 简体中文翻译模型未安装（状态：\(status)）。请在系统设置中下载翻译语言。")
    exit(1)
}
let session = TranslationSession(installedSource: source, target: target)

/// 去掉 **加粗**、*斜体* 标记，翻译纯文本
func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func translate(_ texts: [String]) async throws -> [String] {
    // 逐段翻译：批量接口在命令行环境下可能长时间无响应
    var results: [String] = []
    for text in texts {
        let value = plain(text)
        if value.isEmpty {
            results.append("")
        } else {
            results.append(try await session.translate(value).targetText)
            print(".", terminator: "")
        }
    }
    return results
}

func save() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try? encoder.encode(cache).write(to: cacheURL, options: .atomic)
}

// MARK: - 阅读：没有 translation 的文章

let fm = FileManager.default
let setFiles = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("sets").path)) ?? [])
    // 只翻译学术类，跳过培训类（-gt）
    .filter { $0.hasSuffix(".json") && !$0.contains("-gt") }
    .sorted()
var readingDone = 0
var paragraphCount = 0
for file in setFiles {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("sets/\(file)")),
          let set = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = set["id"] as? String,
          let passages = set["passages"] as? [[String: Any]] else { continue }
    for passage in passages {
        let part = passage["part"] as? Int ?? 0
        let key = "\(id)-p\(part)"
        let existing = passage["translation"] as? [[String: Any]] ?? []
        guard existing.isEmpty, cache.reading[key] == nil else { continue }
        let paragraphs = ((passage["text"] as? [String: Any])?["paragraphs"] as? [[String: Any]] ?? [])
            .map { $0["text"] as? String ?? "" }
        guard !paragraphs.isEmpty else { continue }
        do {
            cache.reading[key] = try await translate(paragraphs)
            readingDone += 1
            paragraphCount += paragraphs.count
            print(" 阅读 \(key)：\(paragraphs.count) 段")
            save()
        } catch {
            print("阅读 \(key) 翻译失败：\(error)")
        }
    }
}
save()

// MARK: - 听力：原文中缺少中文的句子

let listeningFiles = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("listening").path)) ?? [])
    .filter { $0.hasSuffix(".json") && !$0.contains("-gt") }.sorted()
var lineCount = 0
for file in listeningFiles {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("listening/\(file)")),
          let test = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawID = test["id"] as? String,
          let sections = test["sections"] as? [[String: Any]] else { continue }
    let id = rawID.replacingOccurrences(of: "-listening", with: "")
    for section in sections {
        let part = section["part"] as? Int ?? 0
        let key = "\(id)-l\(part)"
        guard cache.listening[key] == nil else { continue }
        let lines = section["transcript"] as? [[String: Any]] ?? []
        let missing = lines.enumerated().filter { _, line in
            ((line["zh"] as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                && !((line["en"] as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !missing.isEmpty else { continue }
        do {
            let translated = try await translate(missing.map { $0.element["en"] as? String ?? "" })
            cache.listening[key] = Dictionary(uniqueKeysWithValues: zip(missing.map { String($0.offset) }, translated))
            lineCount += missing.count
            print(" 听力 \(key)：\(missing.count) 句")
        } catch {
            print("听力 \(key) 翻译失败：\(error)")
        }
    }
}
save()
print("完成：新翻译阅读 \(readingDone) 篇（\(paragraphCount) 段），听力 \(lineCount) 句。缓存共 \(cache.reading.count) 篇阅读、\(cache.listening.count) 个听力 Part。")
