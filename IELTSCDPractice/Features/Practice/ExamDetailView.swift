import SwiftData
import SwiftUI

struct ExamDetailView: View {
    let exam: ExamSummary
    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @Query private var drafts: [ExamDraft]
    @Query private var favorites: [FavoriteExam]
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var allRecords: [PracticeRecord]
    @AppStorage(PreferenceKey.timerKind) private var timerKind = ExamTimerKind.countdown.rawValue
    @AppStorage(PreferenceKey.practiceMinutes) private var practiceMinutes = 20
    @State private var confirmDiscard = false

    init(exam: ExamSummary) {
        self.exam = exam
        let key = ExamSession.draftKey(kind: .practice, examIDs: [exam.id])
        _drafts = Query(filter: #Predicate<ExamDraft> { $0.key == key })
        let examID = exam.id
        _favorites = Query(filter: #Predicate<FavoriteExam> { $0.examId == examID })
    }

    private var records: [PracticeRecord] {
        allRecords.filter { $0.examIDList.contains(exam.id) }
    }

    private var questionKinds: [(QuestionKind, Int)] {
        guard let document = try? ContentStore.shared.document(for: exam.id) else { return [] }
        var counts: [QuestionKind: Int] = [:]
        var order: [QuestionKind] = []
        for group in document.questionGroups {
            if counts[group.kind] == nil { order.append(group.kind) }
            counts[group.kind, default: 0] += group.questionIds.count
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            }

            Section {
                if let draft = drafts.first {
                    Button {
                        launcher.resume(draft)
                    } label: {
                        actionRow(title: "继续作答", subtitle: "已答 \(draft.answered)/\(draft.totalQuestions) 题 · 已用时 \(draft.elapsed.clockString)",
                                  symbol: "play.circle.fill", tint: .orange)
                    }
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label("放弃本次作答并重新开始", systemImage: "arrow.counterclockwise")
                    }
                } else {
                    Button {
                        launcher.practice(exam.id)
                    } label: {
                        actionRow(title: "开始练习", subtitle: timerDescription, symbol: "play.circle.fill", tint: .accentColor)
                    }
                }
                Button {
                    launcher.study(exam.id)
                } label: {
                    actionRow(title: "背题模式", subtitle: exam.hasExplanation ? "直接显示答案、中文解析与段落翻译" : "直接显示答案",
                              symbol: "book.circle", tint: .accentColor)
                }
            } footer: {
                Text("计时方式可在“设置”中修改。练习过程中会自动保存，中途退出可继续作答。")
            }

            if let test = ContentStore.shared.test(containing: exam.id) {
                Section {
                    NavigationLink(value: Route.test(test.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(test.title)
                                Text("整套阅读、听力、写作与完整模考").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "books.vertical")
                        }
                    }
                } header: {
                    Text("所在试卷")
                }
            }

            if let jijing = ExtrasStore.shared.jijing(forContent: exam.id) {
                Section {
                    NavigationLink(value: jijing) {
                        HStack(spacing: 24) {
                            jijingMetric("重考次数", "\(jijing.retestCount) 次")
                            jijingMetric("最近考到", jijing.lastHitDate ?? "—")
                            if let rate = jijing.correctRate {
                                jijingMetric("题库平均正确率", "\(rate)%")
                            }
                            jijingMetric("练习人数", jijing.practiceCount.formatted())
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("机经考情")
                }
            }

            Section("题型") {
                ForEach(questionKinds, id: \.0) { kind, count in
                    LabeledContent {
                        Text("\(count) 题")
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }

            Section("练习历史") {
                if records.isEmpty {
                    Text("还没有练习过这篇文章")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        NavigationLink(value: record) {
                            RecordRow(record: record, showTitle: false)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(exam.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFavorite()
                } label: {
                    Label(favorites.isEmpty ? "收藏" : "取消收藏", systemImage: favorites.isEmpty ? "star" : "star.fill")
                }
            }
        }
        .confirmationDialog("放弃本次作答？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃并重新开始", role: .destructive) {
                if let draft = drafts.first {
                    modelContext.delete(draft)
                    try? modelContext.save()
                }
                launcher.practice(exam.id)
            }
        } message: {
            Text("已填写的答案与划线将被清除。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CategoryBadge(category: exam.category, large: true)
                if exam.isBank {
                    TagLabel(text: "\(exam.examSource.title) · \(exam.examModule.title)")
                } else {
                    TagLabel(text: "机经 · \(exam.frequency.title)", color: exam.frequency == .high ? .red : .secondary)
                }
                DifficultyStars(stars: exam.difficultyStars)
            }
            Text(exam.title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if !exam.subtitle.isEmpty {
                Text(exam.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                metric("题目", "\(exam.questionCount) 题", detail: "Q\(exam.questionRange)")
                metric("篇幅", "\(exam.wordCount) 词", detail: "约 \(max(exam.wordCount / 180, 1)) 分钟阅读")
                metric("最佳成绩", records.map(\.accuracy).max().map(\.percentString) ?? "—", detail: "\(records.count) 次练习")
            }
            .padding(.top, 4)
        }
    }

    private func metric(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func jijingMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func actionRow(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color(.label))
                Text(subtitle).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var timerDescription: String {
        switch ExamTimerKind(rawValue: timerKind) ?? .countdown {
        case .countdown: "\(practiceMinutes) 分钟倒计时 · 完成后自动判分"
        case .countup: "正计时 · 完成后自动判分"
        case .none: "不计时 · 完成后自动判分"
        }
    }

    private func toggleFavorite() {
        if let favorite = favorites.first {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteExam(examId: exam.id))
        }
        try? modelContext.save()
    }
}
