import Foundation

struct DictionaryEntry: Hashable {
    let word: String
    let phonetic: String
    let translation: String
    let definition: String
}

/// ECDICT 离线词典（MIT 许可），首次查询时在后台加载。
actor DictionaryService {
    static let shared = DictionaryService()

    private var entries: [String: DictionaryEntry]?

    func lookup(_ raw: String) -> DictionaryEntry? {
        let entries = load()
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard !word.isEmpty else { return nil }
        if let entry = entries[word] { return entry }
        // 简单的词形还原：复数、过去式、进行时
        for candidate in lemmaCandidates(for: word) {
            if let entry = entries[candidate] { return entry }
        }
        return nil
    }

    private func load() -> [String: DictionaryEntry] {
        if let entries { return entries }
        var result: [String: DictionaryEntry] = [:]
        let url = ContentStore.shared.rootURL.appendingPathComponent("dictionary/ecdict.tsv")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            result.reserveCapacity(21000)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map {
                    String($0).replacingOccurrences(of: "\\n", with: "\n")
                }
                guard fields.count >= 3 else { continue }
                let entry = DictionaryEntry(
                    word: fields[0],
                    phonetic: fields[1],
                    translation: fields[2],
                    definition: fields.count > 3 ? fields[3] : ""
                )
                result[fields[0].lowercased()] = entry
            }
        }
        entries = result
        return result
    }

    private func lemmaCandidates(for word: String) -> [String] {
        var candidates: [String] = []
        func add(_ value: String) { if value.count > 1 { candidates.append(value) } }
        if word.hasSuffix("ies") { add(String(word.dropLast(3)) + "y") }
        if word.hasSuffix("es") { add(String(word.dropLast(2))) }
        if word.hasSuffix("s") { add(String(word.dropLast())) }
        if word.hasSuffix("ied") { add(String(word.dropLast(3)) + "y") }
        if word.hasSuffix("ed") { add(String(word.dropLast(2))); add(String(word.dropLast())) }
        if word.hasSuffix("ing") { add(String(word.dropLast(3))); add(String(word.dropLast(3)) + "e") }
        if word.hasSuffix("ly") { add(String(word.dropLast(2))) }
        return candidates
    }
}
