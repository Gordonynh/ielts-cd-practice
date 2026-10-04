import Foundation

/// 只读的内置题库：
/// - `Content/bank/`：题库，真题与模拟题的听力、阅读、写作（scripts/build-bank.mjs 生成，或从题库仓库下载）
/// - `Content/dictionary/`、`Content/vocabulary/`：ECDICT 离线词典与雅思核心词（scripts/build-dictionary.mjs 生成）
final class ContentStore {
    static let shared = ContentStore()

    let rootURL: URL
    let exams: [ExamSummary]
    let readingSets: [ReadingSet]
    let listeningTests: [ListeningTest]
    let writingTasks: [CambridgeWritingTask]
    let catalog: ContentCatalog
    /// 题库生成时间
    let generatedAt: Date?
    private let examsByID: [String: ExamSummary]
    private let setsByID: [String: ReadingSet]
    private let sectionsByID: [String: (test: ListeningTest, section: ListeningTest.Section)]
    private var documentCache: [String: ExamDocument] = [:]
    private let cacheLock = NSLock()

    private init() {
        rootURL = Bundle.main.url(forResource: "Content", withExtension: nil)
            ?? Bundle.main.bundleURL.appendingPathComponent("Content")
        let decoder = JSONDecoder()
        let bank = try? decoder.decode(BankIndex.self, from: Data(contentsOf: rootURL.appendingPathComponent("bank/index.json")))
        exams = bank?.reading ?? []
        readingSets = bank?.readingSets ?? []
        listeningTests = bank?.listening ?? []
        writingTasks = bank?.writing ?? []
        catalog = ContentCatalog(reading: bank?.reading ?? [], readingSets: readingSets,
                                 listening: listeningTests, writing: writingTasks)
        generatedAt = bank?.generatedAt.flatMap { try? Date($0, strategy: .iso8601) }
        examsByID = Dictionary(exams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        setsByID = Dictionary(readingSets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sections: [String: (ListeningTest, ListeningTest.Section)] = [:]
        for test in listeningTests {
            for section in test.sections { sections[section.id] = (test, section) }
        }
        sectionsByID = sections
    }

    // MARK: - Lookup

    func summary(for id: String) -> ExamSummary? {
        examsByID[id]
    }

    func readingSet(for id: String) -> ReadingSet? {
        setsByID[id]
    }

    func listeningSection(for id: String) -> (test: ListeningTest, section: ListeningTest.Section)? {
        sectionsByID[id]
    }

    func listeningTest(containing sectionID: String) -> ListeningTest? {
        sectionsByID[sectionID]?.test
    }

    func exams(in category: ExamCategory) -> [ExamSummary] {
        exams.filter { $0.category == category }
    }

    /// 练习记录、草稿中显示的标题
    func displayTitle(for id: String) -> String {
        if let summary = examsByID[id] { return summary.title }
        if let (test, section) = sectionsByID[id] { return "\(test.title) · Part \(section.part)" }
        if let item = writingItem(id) {
            return item.source == .cambridge ? "\(item.title) · Task \(item.part)" : item.title
        }
        return id
    }

    func isListening(_ id: String) -> Bool {
        sectionsByID[id] != nil
    }

    // MARK: - Files

    func examURL(_ id: String) -> URL {
        let skill = sectionsByID[id] != nil ? "listening" : "reading"
        return rootURL.appendingPathComponent("bank/\(skill)/exams/\(id).json")
    }

    func explanationURL(_ id: String) -> URL {
        let skill = sectionsByID[id] != nil ? "listening" : "reading"
        return rootURL.appendingPathComponent("bank/\(skill)/explanations/\(id).json")
    }

    func document(for id: String) throws -> ExamDocument {
        cacheLock.lock()
        if let cached = documentCache[id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        let document = try JSONDecoder().decode(ExamDocument.self, from: Data(contentsOf: examURL(id)))
        cacheLock.lock()
        documentCache[id] = document
        cacheLock.unlock()
        return document
    }

    func explanation(for id: String) -> ExamExplanation? {
        try? JSONDecoder().decode(ExamExplanation.self, from: Data(contentsOf: explanationURL(id)))
    }

    /// 传给机考引擎的原始 JSON 对象。
    func examJSONObject(_ id: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: examURL(id)))
    }

    func explanationJSONObject(_ id: String) -> Any? {
        guard let data = try? Data(contentsOf: explanationURL(id)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Random

    /// 随机抽题：优先选择尚未练习过的篇目。
    func randomExam(in category: ExamCategory, practiced: Set<String>, excluding: Set<String> = [],
                    source: ExamSource? = nil) -> ExamSummary? {
        let pool = readingPassages.filter {
            $0.category == category && !excluding.contains($0.id) && (source == nil || $0.examSource == source)
        }
        let fresh = pool.filter { !practiced.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement()
    }

    func randomListeningSection(part: Int? = nil, practiced: Set<String>, excluding: Set<String> = []) -> String? {
        let pool = listeningTests.flatMap(\.sections).filter {
            (part == nil || $0.part == part) && !excluding.contains($0.id)
        }
        let fresh = pool.filter { !practiced.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement()?.id
    }

    func imageURL(_ name: String) -> URL {
        rootURL.appendingPathComponent("bank/images/\(name)")
    }

    /// 离线词典的词条数（设置页显示）
    var dictionaryEntryCount: Int {
        guard let data = try? Data(contentsOf: rootURL.appendingPathComponent("dictionary/ecdict.tsv")) else { return 0 }
        return data.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
    }

    func loadCoreWords() -> [CoreWord] {
        let url = rootURL.appendingPathComponent("vocabulary/ielts-core.json")
        return (try? JSONDecoder().decode([CoreWord].self, from: Data(contentsOf: url))) ?? []
    }
}
