import SwiftData
import SwiftUI
import WebKit

/// 机考界面的原生控制器：组装题目、保存草稿、判分并写入练习记录。
@MainActor
final class ExamController: NSObject, WKScriptMessageHandler {
    struct Selection {
        var hasSelection = false
        var inHighlight = false
        var text = ""
        var sentence = ""

        /// 1–3 个英文单词时可加入生词本
        var isWordLike: Bool {
            let words = text.split(separator: " ")
            return !words.isEmpty && words.count <= 3 && text.range(of: #"^[A-Za-z][A-Za-z' -]*$"#, options: .regularExpression) != nil
        }
    }

    private(set) var session: ExamSession
    weak var webView: WKWebView?
    var modelContext: ModelContext?
    var onClose: () -> Void = {}
    /// 模考全部完成，关闭机考界面后显示成绩
    var onFinishMock: (UUID) -> Void = { _ in }
    private(set) var selection = Selection()
    /// 网页焦点是否在输入框中（输入时方向键交给系统移动光标）
    private(set) var isEditing = false

    private let content = ContentStore.shared
    private var documents: [ExamDocument] = []
    private var sessionStartedAt = Date()

    init(session: ExamSession) {
        self.session = session
    }

    // MARK: - Messages from the engine

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let payload = body["payload"] as? [String: Any]

        switch type {
        case "ready":
            start()
        case "started":
            if let webView, webView.alpha < 1 {
                UIView.animate(withDuration: 0.25) { webView.alpha = 1 }
            }
            // 让外接键盘的按键直接送到机考界面，不需要先点一下屏幕
            webView?.becomeFirstResponder()
        case "editing":
            isEditing = payload?["editing"] as? Bool ?? false
        case "vocab":
            addVocabulary(Selection(
                hasSelection: true,
                inHighlight: false,
                text: payload?["text"] as? String ?? "",
                sentence: payload?["sentence"] as? String ?? ""
            ))
        case "draft":
            if let payload { saveDraft(payload) }
        case "submit":
            if let payload { submit(payload) }
        case "selection":
            selection = Selection(
                hasSelection: payload?["hasSelection"] as? Bool ?? false,
                inHighlight: payload?["inHighlight"] as? Bool ?? false,
                text: payload?["text"] as? String ?? "",
                sentence: payload?["sentence"] as? String ?? ""
            )
        case "preferences":
            if let payload { Preferences.updateExamPreferences(from: payload) }
        case "exit":
            if payload?["finished"] as? Bool == true, let mockID = session.mockID {
                onFinishMock(mockID)
            }
            onClose()
        case "retry":
            restart(with: session.examIDs)
        case "next":
            startNextPassage()
        default:
            break
        }
    }

    // MARK: - Start

    private func start() {
        do {
            documents = session.skill == .writing ? [] : try session.examIDs.map { try content.document(for: $0) }
            let config = try makeConfig()
            sessionStartedAt = Date()
            call("ExamEngine.start(config)", arguments: ["config": config])
        } catch {
            call("document.body.innerText = message", arguments: ["message": "题目加载失败：\(error.localizedDescription)"])
        }
    }

    private func makeConfig() throws -> [String: Any] {
        var parts: [[String: Any]] = []
        for examID in session.examIDs {
            if session.skill == .writing {
                parts.append(["exam": try writingExamObject(examID)])
                continue
            }
            var part: [String: Any] = [
                "exam": try content.examJSONObject(examID),
                "explanation": content.explanationJSONObject(examID) ?? NSNull(),
            ]
            if let section = content.listeningSection(for: examID)?.section {
                part["audio"] = AudioStore.shared.playbackURL(for: section)
            }
            parts.append(part)
        }
        var timer = session.timer
        var config: [String: Any] = [
            "mode": session.mode.rawValue,
            "parts": parts,
            "candidateId": Preferences.candidateID,
            "preferences": Preferences.examPreferences,
            "strict": session.isMock,
            "actions": [
                "retry": !session.isMock,
                "next": session.kind == .practice && session.mode != .review && session.skill != .writing,
            ],
        ]
        if session.mode == .test, session.kind == .fullTest || session.isMock {
            config["intro"] = introObject(timer: timer)
        }

        switch session.mode {
        case .test:
            if let draft = fetchDraft(), let object = try? JSONSerialization.jsonObject(with: draft.payloadData) {
                config["draft"] = object
                timer = draft.timer
                sessionStartedAt = draft.startedAt
            }
        case .review:
            if let record = fetchRecord(), let payload = record.payload {
                config["review"] = [
                    "parts": payload.parts.map { ["answers": $0.answers] },
                    "results": resultsObject(parts: payload.parts, elapsed: record.duration, band: record.band),
                    "highlights": payload.highlights.map(highlightObject),
                ]
            }
        case .study:
            break
        }
        config["timer"] = ["kind": timer.kind.rawValue, "limit": timer.limit]
        return config
    }

    private func writingExamObject(_ id: String) throws -> [String: Any] {
        guard let item = content.writingItem(id) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "找不到写作题目 \(id)"])
        }
        var object: [String: Any] = [
            "id": id, "skill": "writing", "part": item.part, "title": item.title,
            "prompt": item.prompt, "minWords": item.minWords,
        ]
        if let image = item.imageName {
            object["image"] = "content/bank/images/" + (image.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? image)
        }
        if let essay = item.essay { object["essay"] = essay }
        return object
    }

    /// 每个部分开始前的说明页，内容参照官方机考
    private func introObject(timer: ExamTimerSetting) -> [String: Any] {
        let moduleName = "Academic"
        let time: String = {
            if session.skill == .listening { return "Approximately 30 minutes" }
            switch timer.kind {
            case .none, .countup: return "Untimed practice"
            case .countdown:
                let minutes = Int(timer.limit / 60)
                return minutes == 60 ? "1 hour" : "\(minutes) minutes"
            }
        }()
        let changeAnswers = "You can change your answers at any time during the test."
        let clock = "The test clock will show you when there are 10 minutes and 5 minutes remaining."
        switch session.skill {
        case .listening:
            return [
                "title": "IELTS Listening",
                "time": time,
                "instructions": ["Answer all the questions.", changeAnswers],
                "information": [
                    "There are \(documents.reduce(0) { $0 + $1.questionOrder.count }) questions in this test.",
                    "Each question carries one mark.",
                    "There are \(session.examIDs.count) parts to the test.",
                    session.isMock
                        ? "You will hear each part once only. The recording cannot be paused."
                        : "In this practice test you can pause and replay the recording.",
                    "For each part of the test there will be time for you to look through the questions and time for you to check your answers.",
                ],
            ]
        case .reading:
            return [
                "title": "IELTS \(moduleName) Reading",
                "time": time,
                "instructions": ["Answer all the questions.", changeAnswers],
                "information": [
                    "There are \(documents.reduce(0) { $0 + $1.questionOrder.count }) questions in this test.",
                    "Each question carries one mark.",
                    "There are \(session.examIDs.count) parts to the test.",
                    clock,
                ],
            ]
        case .writing:
            return [
                "title": "IELTS \(moduleName) Writing",
                "time": time,
                "instructions": [session.examIDs.count > 1 ? "Answer both parts." : "Answer the question.", changeAnswers],
                "information": [
                    "There are \(session.examIDs.count) parts in this test.",
                    "Part 2 contributes twice as much as Part 1 to the writing score.",
                    clock,
                ],
            ]
        }
    }

    private func restart(with examIDs: [String]) {
        deleteDraft(key: ExamSession.draftKey(kind: session.kind, examIDs: examIDs))
        session = .practice(session.skill, examIDs)
        selection = Selection()
        start()
    }

    private func startNextPassage() {
        guard let current = session.examIDs.first else { return }
        let practiced = Set(fetchRecords().flatMap(\.examIDList))
        if let (_, section) = content.listeningSection(for: current) {
            if let next = content.randomListeningSection(part: section.part, practiced: practiced, excluding: [current]) {
                restart(with: [next])
            }
            return
        }
        guard let summary = content.summary(for: current) else { return }
        guard let next = content.randomExam(in: summary.category, practiced: practiced, excluding: [current]) else { return }
        restart(with: [next.id])
    }

    // MARK: - Drafts

    private func fetchDraft() -> ExamDraft? {
        guard let modelContext else { return nil }
        let key = session.draftKey
        var descriptor = FetchDescriptor<ExamDraft>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func deleteDraft(key: String) {
        guard let modelContext else { return }
        try? modelContext.delete(model: ExamDraft.self, where: #Predicate { $0.key == key })
        try? modelContext.save()
    }

    private func saveDraft(_ payload: [String: Any]) {
        guard session.mode == .test, let modelContext,
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let total = session.skill == .writing ? session.examIDs.count : documents.reduce(0) { $0 + $1.questionOrder.count }
        let draft = fetchDraft() ?? {
            let draft = ExamDraft(key: session.draftKey, kind: session.kind, skill: session.skill, examIDs: session.examIDs,
                                  timer: session.timer, totalQuestions: total, mockID: session.mockID)
            draft.startedAt = sessionStartedAt
            modelContext.insert(draft)
            return draft
        }()
        draft.payloadData = data
        draft.updatedAt = Date()
        draft.elapsed = payload["elapsed"] as? Double ?? draft.elapsed
        draft.answered = (payload["parts"] as? [[String: Any]] ?? [])
            .reduce(0) { $0 + (($1["answers"] as? [String: Any])?.count ?? 0) }
        try? modelContext.save()
    }

    // MARK: - Submit

    private func submit(_ payload: [String: Any]) {
        guard let modelContext else { return }
        let submittedParts = payload["parts"] as? [[String: Any]] ?? []
        func answers(at index: Int) -> [String: String] {
            let raw = index < submittedParts.count ? submittedParts[index]["answers"] as? [String: Any] ?? [:] : [:]
            return raw.compactMapValues { value -> String? in
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return nil
            }
        }
        var parts: [PartRecord] = []
        if session.skill == .writing {
            for (index, examID) in session.examIDs.enumerated() {
                let text = answers(at: index)["essay"] ?? ""
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                parts.append(PartRecord(examId: examID, title: content.displayTitle(for: examID), category: nil,
                                        listeningPart: nil, answers: text.isEmpty ? [:] : ["essay": text], questions: [:],
                                        order: ["essay"], score: 0, total: 0,
                                        writingPart: content.writingItem(examID)?.part ?? index + 1, wordCount: words))
            }
        } else {
            for (index, document) in documents.enumerated() {
                parts.append(AnswerGrader.grade(document, answers: answers(at: index), title: content.displayTitle(for: document.id)))
            }
        }
        let highlights = (payload["highlights"] as? [[String: Any]] ?? []).compactMap(highlightRecord)
        let elapsed = payload["elapsed"] as? Double ?? Date().timeIntervalSince(sessionStartedAt)
        let score = parts.reduce(0) { $0 + $1.score }
        let total = parts.reduce(0) { $0 + $1.total }

        let test = session.examIDs.first.flatMap(content.test(containing:))
        let module: ExamModule = .academic
        let record = PracticeRecord(
            kind: session.kind,
            skill: session.skill,
            module: module,
            startedAt: sessionStartedAt,
            finishedAt: Date(),
            duration: elapsed,
            score: score,
            total: total,
            timeUp: payload["timeUp"] as? Bool ?? false,
            payload: RecordPayload(parts: parts, highlights: highlights)
        )
        // 整套题目以试卷名作为标题
        if parts.count > 1, let test, Set(test.ids(for: session.skill)) == Set(session.examIDs) {
            record.title = "\(test.title) · \(session.skill.title)"
        }
        record.mockID = session.mockID
        modelContext.insert(record)
        try? modelContext.save()
        deleteDraft(key: session.draftKey)

        if let mockID = session.mockID {
            advanceMock(mockID, record: record)
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        call("ExamEngine.showResults(results)",
             arguments: ["results": resultsObject(parts: parts, elapsed: elapsed, band: record.band)])
    }

    /// 模考：保存本部分成绩后进入下一部分；全部完成后显示结束页
    private func advanceMock(_ mockID: UUID, record: PracticeRecord) {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<MockTest>(predicate: #Predicate { $0.id == mockID })
        descriptor.fetchLimit = 1
        guard let mock = try? modelContext.fetch(descriptor).first, let test = content.test(mock.testID) else {
            onClose()
            return
        }
        mock.setRecordID(record.id, for: session.skill)
        let order: [MockStage] = [.listening, .reading, .writing].filter { stage in
            stage.skill.map { !test.ids(for: $0).isEmpty } ?? false
        }
        let next = order.drop { $0.skill != session.skill }.dropFirst().first ?? .finished
        mock.stage = next
        mock.updatedAt = Date()
        if next == .finished { mock.finishedAt = Date() }
        try? modelContext.save()

        if let skill = next.skill {
            session = ExamSession(kind: .fullTest, skill: skill, mode: .test, examIDs: test.ids(for: skill),
                                  timer: Preferences.officialTimer(for: skill), mockID: mockID)
            selection = Selection()
            start()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            call("ExamEngine.finish(info)", arguments: ["info": [
                "title": "The test is now finished",
                "message": "You have completed all parts of the test. Your answers have been saved.",
                "button": "View results",
            ]])
        }
    }

    private func resultsObject(parts: [PartRecord], elapsed: Double, band: String?) -> [String: Any] {
        [
            "parts": parts.map { part in
                [
                    "score": part.score,
                    "total": part.total,
                    "questions": part.questions.mapValues { result in
                        ["correct": result.correct, "expected": result.expected, "given": result.given] as [String: Any]
                    },
                ] as [String: Any]
            },
            "score": parts.reduce(0) { $0 + $1.score },
            "total": parts.reduce(0) { $0 + $1.total },
            "elapsed": elapsed,
            "band": band ?? NSNull(),
        ]
    }

    private func highlightRecord(_ object: [String: Any]) -> HighlightRecord? {
        guard let part = object["part"] as? Int, let start = object["start"] as? Int, let end = object["end"] as? Int else {
            return nil
        }
        return HighlightRecord(part: part, pane: object["pane"] as? String ?? "passage", start: start, end: end,
                               note: object["note"] as? String ?? "")
    }

    private func highlightObject(_ record: HighlightRecord) -> [String: Any] {
        ["part": record.part, "pane": record.pane, "start": record.start, "end": record.end, "note": record.note]
    }

    private func fetchRecord() -> PracticeRecord? {
        guard let modelContext, let recordID = session.recordID else { return nil }
        var descriptor = FetchDescriptor<PracticeRecord>(predicate: #Predicate { $0.id == recordID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchRecords() -> [PracticeRecord] {
        (try? modelContext?.fetch(FetchDescriptor<PracticeRecord>())) ?? []
    }

    // MARK: - Edit menu actions

    func applyHighlight(_ kind: String) {
        call("ExamEngine.highlightSelection(kind)", arguments: ["kind": kind])
    }

    func addSelectionToVocabulary() {
        guard let webView else { return }
        webView.callAsyncJavaScript("return ExamEngine.selectionInfo()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result, let info = value as? [String: Any] else { return }
            self.addVocabulary(Selection(
                hasSelection: info["hasSelection"] as? Bool ?? false,
                inHighlight: info["inHighlight"] as? Bool ?? false,
                text: info["text"] as? String ?? "",
                sentence: info["sentence"] as? String ?? ""
            ))
        }
    }

    private func addVocabulary(_ selection: Selection) {
        guard let modelContext else { return }
        let source = "exam:" + (session.examIDs.first ?? "")
        guard selection.isWordLike else {
            call("ExamEngine.toast(message)", arguments: ["message": "请选择一个单词或短语（最多 3 个词）"])
            return
        }
        let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            let entry = await DictionaryService.shared.lookup(text)
            let word = (entry?.word ?? text).lowercased()
            let exists = (try? modelContext.fetchCount(FetchDescriptor<VocabEntry>(predicate: #Predicate { $0.word == word }))) ?? 0
            if exists == 0 {
                modelContext.insert(VocabEntry(word: word, phonetic: entry?.phonetic ?? "",
                                               meaning: entry?.translation ?? "", context: selection.sentence,
                                               source: source))
                try? modelContext.save()
            }
            let message = exists > 0 ? "「\(word)」已在生词本中" : "已加入生词本：\(word)"
            self.call("ExamEngine.toast(message)", arguments: ["message": message])
        }
    }

    /// 外接键盘按键（Tab、方向键、Esc）转发给机考引擎
    func forwardKey(_ key: String, shift: Bool) {
        call("ExamEngine.key(key, shift)", arguments: ["key": key, "shift": shift])
    }

    // MARK: - JavaScript

    private func call(_ script: String, arguments: [String: Any]) {
        webView?.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
            if case .failure(let error) = result {
                print("[Exam] JavaScript error:", error)
            }
        }
    }
}

/// 机考 WebView：在系统文本选择菜单中加入 Highlight / Notes / 加入生词本，并处理外接键盘。
final class ExamWebView: WKWebView {
    weak var controller: ExamController?

    override var canBecomeFirstResponder: Bool { true }

    /// Tab / Shift+Tab 始终由机考引擎处理（切换题目）；方向键只在不输入文字时转发，输入时保留系统的光标移动
    override var keyCommands: [UIKeyCommand]? {
        var commands = [
            command(UIKeyCommand.inputEscape),
            command("\t"),
            command("\t", modifiers: .shift),
        ]
        if controller?.isEditing != true {
            commands += [UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow,
                         UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow,
                         UIKeyCommand.inputPageUp, UIKeyCommand.inputPageDown].map { command($0) }
        }
        return (super.keyCommands ?? []) + commands
    }

    private func command(_ input: String, modifiers: UIKeyModifierFlags = []) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: #selector(handleKeyCommand(_:)))
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        let key: String
        switch command.input {
        case "\t": key = "Tab"
        case UIKeyCommand.inputEscape: key = "Escape"
        case UIKeyCommand.inputUpArrow: key = "ArrowUp"
        case UIKeyCommand.inputDownArrow: key = "ArrowDown"
        case UIKeyCommand.inputLeftArrow: key = "ArrowLeft"
        case UIKeyCommand.inputRightArrow: key = "ArrowRight"
        case UIKeyCommand.inputPageUp: key = "PageUp"
        case UIKeyCommand.inputPageDown: key = "PageDown"
        default: return
        }
        controller?.forwardKey(key, shift: command.modifierFlags.contains(.shift))
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        // 文本选择菜单只会在有选区时出现；选区状态消息可能稍晚到达，因此不以它为前提
        guard let controller, builder.system == .context else { return }

        // 与官方机考右键菜单一致：Highlight / Notes / Clear
        var actions: [UIMenuElement] = [
            UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak controller] _ in
                controller?.applyHighlight("highlight")
            },
            UIAction(title: "Notes", image: UIImage(systemName: "note.text.badge.plus")) { [weak controller] _ in
                controller?.applyHighlight("note")
            },
        ]
        if controller.selection.inHighlight {
            actions.append(UIAction(title: "Clear", image: UIImage(systemName: "eraser")) { [weak controller] _ in
                controller?.applyHighlight("clear")
            })
        }
        actions.append(UIAction(title: "加入生词本", image: UIImage(systemName: "character.book.closed")) { [weak controller] _ in
            controller?.addSelectionToVocabulary()
        })
        let menu = UIMenu(title: "", options: .displayInline, children: actions)
        if builder.menu(for: .standardEdit) != nil {
            builder.insertSibling(menu, beforeMenu: .standardEdit)
        } else {
            builder.insertChild(menu, atStartOfMenu: .root)
        }
    }
}

/// WKUserContentController 会强引用消息处理者，用弱引用转发避免循环引用。
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
