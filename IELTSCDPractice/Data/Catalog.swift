import Foundation

// MARK: - 套题

/// 一整套试题（剑桥真题或模拟题）：听力 Part 1–4、阅读 Passage 1–3、写作 Task 1–2。
struct PracticeTest: Identifiable, Hashable {
    let id: String
    let bookID: String
    let bookTitle: String
    let title: String
    let test: String
    let listening: ListeningTest?
    let reading: [ExamSummary]
    let writing: [CambridgeWritingTask]

    var shortTitle: String { "Test \(test)" }
    var listeningIDs: [String] { listening?.sections.map(\.id) ?? [] }
    var readingIDs: [String] { reading.map(\.id) }
    var writingIDs: [String] { writing.map(\.id) }

    var skills: [ExamSkill] {
        var skills: [ExamSkill] = []
        if listening != nil { skills.append(.listening) }
        if !reading.isEmpty { skills.append(.reading) }
        if !writing.isEmpty { skills.append(.writing) }
        return skills
    }

    func ids(for skill: ExamSkill) -> [String] {
        switch skill {
        case .listening: listeningIDs
        case .reading: readingIDs
        case .writing: writingIDs
        }
    }

    /// 完整模考：按官方顺序依次进行听力、阅读、写作
    var canMock: Bool { listening != nil && reading.count == 3 }

    var mockDescription: String {
        skills.map { skill in
            switch skill {
            case .listening: "听力约 30 分钟"
            case .reading: "阅读 60 分钟"
            case .writing: "写作 60 分钟"
            }
        }.joined(separator: " → ")
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || reading.contains { $0.title.localizedCaseInsensitiveContains(query) }
            || (listening?.sections.contains { $0.topic.localizedCaseInsensitiveContains(query) } ?? false)
            || writing.contains { $0.prompt.localizedCaseInsensitiveContains(query) }
    }
}

/// 一本书（剑桥雅思 5–21）或一个模拟题系列。
struct TestBook: Identifiable, Hashable {
    let id: String
    let title: String
    let number: Int?
    let tests: [PracticeTest]

    var isCambridge: Bool { number != nil }
}

// MARK: - 写作题目

/// 写作题目：剑桥真题（Task 1 含图表，部分附范文）或机经题。
struct WritingTaskItem: Identifiable, Hashable {
    enum Source: String, Hashable {
        case cambridge, jijing

        var title: String {
            switch self {
            case .cambridge: "剑桥真题"
            case .jijing: "机经"
            }
        }
    }

    let id: String
    let source: Source
    let part: Int
    let title: String
    /// Task 1：图表类型；Task 2：话题（机经）或「议论文」
    let category: String
    let prompt: String
    let imageName: String?
    let minWords: Int
    let essay: String?
    let jijing: JijingItem?

    init(cambridge task: CambridgeWritingTask) {
        id = task.id
        source = .cambridge
        part = task.part
        title = task.setTitle
        category = Self.category(forCambridgeType: task.type)
        prompt = task.prompt
        imageName = task.image
        minWords = task.minWords
        essay = task.essay
        jijing = nil
    }

    init(jijing item: JijingItem) {
        id = item.id
        source = .jijing
        part = item.part ?? 2
        title = item.title
        category = part == 1 ? Self.category(forJijingTopic: item.topic) : item.topic
        prompt = item.question ?? item.title
        imageName = nil
        minWords = part == 1 ? 150 : 250
        essay = nil
        jijing = item
    }

    var minutes: Int { part == 1 ? 20 : 40 }

    /// Task 1 的分类（图表、表格、地图、流程图）
    static let task1Categories = ["线图", "柱状图", "饼图", "混合图", "图表", "表格", "地图", "流程图"]

    private static func category(forCambridgeType type: String) -> String {
        switch type {
        case "chart": "图表"
        case "table": "表格"
        case "map": "地图"
        case "process": "流程图"
        default: "议论文"
        }
    }

    private static func category(forJijingTopic topic: String) -> String {
        switch topic {
        case "折线": "线图"
        case "柱状": "柱状图"
        case "饼图": "饼图"
        case "混合图": "混合图"
        default: topic
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query) || prompt.localizedCaseInsensitiveContains(query)
            || category.localizedCaseInsensitiveContains(query)
    }
}

// MARK: - 题库目录

extension ContentStore {
    /// 按书分组的全部套题（剑桥 21 → 5，之后是模拟题系列）
    var books: [TestBook] { catalog.books }

    func test(_ id: String) -> PracticeTest? {
        catalog.testsByID[id]
    }

    /// 某篇阅读、某个听力 Part 或某道写作题所属的套题
    func test(containing examID: String) -> PracticeTest? {
        catalog.testByExamID[examID]
    }

    /// 阅读篇目：题库包 + 机经题库
    var readingPassages: [ExamSummary] { exams }

    var listeningSections: [(test: ListeningTest, section: ListeningTest.Section)] {
        listeningTests.flatMap { test in test.sections.map { (test, $0) } }
    }

    /// 写作题目：剑桥真题 + 机经
    var writingItems: [WritingTaskItem] {
        writingTasks.map(WritingTaskItem.init(cambridge:)) + ExtrasStore.shared.writingPrompts.map(WritingTaskItem.init(jijing:))
    }

    func writingItem(_ id: String) -> WritingTaskItem? {
        if let task = catalog.writingByID[id] { return WritingTaskItem(cambridge: task) }
        if let item = ExtrasStore.shared.item(id), item.skill == "writing" { return WritingTaskItem(jijing: item) }
        return nil
    }

    func skill(of examID: String) -> ExamSkill {
        if listeningSection(for: examID) != nil { return .listening }
        if summary(for: examID) != nil { return .reading }
        return .writing
    }
}

/// ContentStore 初始化时构建的索引。
struct ContentCatalog {
    let books: [TestBook]
    let testsByID: [String: PracticeTest]
    let testByExamID: [String: PracticeTest]
    let writingByID: [String: CambridgeWritingTask]

    init(reading: [ExamSummary], readingSets: [ReadingSet], listening: [ListeningTest], writing: [CambridgeWritingTask]) {
        let passages = Dictionary(reading.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let listeningByID = Dictionary(listening.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let writingBySet = Dictionary(grouping: writing, by: \.setId)
        var setIDs = readingSets.map(\.id)
        for test in listening where !setIDs.contains(test.id) { setIDs.append(test.id) }
        let setsByID = Dictionary(readingSets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var tests: [PracticeTest] = []
        for id in setIDs {
            let set = setsByID[id]
            let listeningTest = listeningByID[id]
            let book = set?.book ?? listeningTest?.book
            let series = set?.series ?? listeningTest?.series ?? listeningTest?.bookTitle ?? "其他"
            tests.append(PracticeTest(
                id: id,
                bookID: book.map { "c\($0)" } ?? series,
                bookTitle: series,
                title: set?.title ?? listeningTest?.title ?? id,
                test: set?.test ?? listeningTest?.test ?? "",
                listening: listeningTest,
                reading: (set?.passages ?? []).compactMap { passages[$0] },
                writing: (writingBySet[id] ?? []).sorted { $0.part < $1.part }
            ))
        }

        var bookOrder: [String] = []
        var grouped: [String: [PracticeTest]] = [:]
        for test in tests {
            if grouped[test.bookID] == nil { bookOrder.append(test.bookID) }
            grouped[test.bookID, default: []].append(test)
        }
        books = bookOrder.map { id in
            let tests = (grouped[id] ?? []).sorted { $0.test.localizedStandardCompare($1.test) == .orderedAscending }
            // 剑桥真题的书号：bookID 形如 c18
            let number = id.hasPrefix("c") ? Int(id.dropFirst()) : nil
            return TestBook(id: id, title: tests.first?.bookTitle ?? id, number: number, tests: tests)
        }
        .sorted { lhs, rhs in
            switch (lhs.number, rhs.number) {
            case let (l?, r?): l > r
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.title < rhs.title
            }
        }
        testsByID = Dictionary(tests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byExam: [String: PracticeTest] = [:]
        for test in tests {
            for id in test.listeningIDs + test.readingIDs + test.writingIDs { byExam[id] = test }
        }
        testByExamID = byExam
        writingByID = Dictionary(writing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
