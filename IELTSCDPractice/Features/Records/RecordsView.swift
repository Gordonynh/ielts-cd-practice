import Charts
import SwiftData
import SwiftUI

struct RecordsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week, month, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: "近 7 天"
            case .month: "近 30 天"
            case .all: "全部"
            }
        }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .all: nil
            }
        }
    }

    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var allRecords: [PracticeRecord]
    @Query(sort: \MockTest.updatedAt, order: .reverse) private var mocks: [MockTest]
    @Environment(\.modelContext) private var modelContext
    @State private var range: Range = .month
    @State private var skill: ExamSkill?
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var pendingDeletion: [PracticeRecord] = []

    private var records: [PracticeRecord] {
        let bySkill = skill.map { skill in allRecords.filter { $0.skill == skill } } ?? allRecords
        guard let days = range.days,
              let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))
        else { return bySkill }
        return bySkill.filter { $0.finishedAt >= start }
    }

    var body: some View {
        let records = records
        let statistics = PracticeStatistics(records: records)

        List(selection: $selection) {
            if allRecords.isEmpty {
                ContentUnavailableView("暂无练习记录", systemImage: "chart.xyaxis.line",
                                       description: Text("完成一篇练习后，成绩与统计会显示在这里。"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    summaryGrid(statistics)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                let finishedMocks = mocks.filter(\.isFinished)
                if skill == nil, !finishedMocks.isEmpty {
                    Section("完整模考") {
                        ForEach(finishedMocks) { mock in
                            NavigationLink(value: Route.mock(mock.id)) {
                                MockSummaryRow(mock: mock, records: allRecords,
                                               title: ContentStore.shared.test(mock.testID)?.title ?? mock.testID)
                            }
                        }
                    }
                }

                if skill != .writing {
                    Section("正确率趋势") {
                        AccuracyTrendChart(records: Array(records.filter { $0.total > 0 }.prefix(30).reversed()))
                            .frame(height: 220)
                            .padding(.vertical, 8)
                    }
                }

                Section("每日练习时长") {
                    DailyMinutesChart(activity: statistics.activity(lastDays: range.days ?? 30))
                        .frame(height: 180)
                        .padding(.vertical, 8)
                }

                Section {
                    PracticeHeatmap(activity: PracticeStatistics(records: allRecords).activity(lastDays: PracticeHeatmap.dayCount(weeks: 20)))
                        .padding(.vertical, 8)
                } header: {
                    Text("练习热力图")
                } footer: {
                    Text("最近 20 周，每格代表一天，颜色越深练习越多。")
                }

                if !statistics.kindAccuracy.isEmpty {
                    Section {
                        KindAccuracyList(items: statistics.kindAccuracy)
                            .padding(.vertical, 8)
                    } header: {
                        Text("题型正确率")
                    } footer: {
                        Text("按正确率从低到高排列，优先练习排在前面的题型。")
                    }
                }

                ForEach(groupedByDay(records), id: \.day) { group in
                    Section(group.day.formatted(.dateTime.year().month().day().weekday(.wide))) {
                        ForEach(group.records) { record in
                            NavigationLink(value: record) {
                                RecordRow(record: record, showTitle: true)
                            }
                            .tag(record.id)
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDeletion = [record]
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("练习记录")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("科目", selection: $skill) {
                    Text("全部").tag(ExamSkill?.none)
                    ForEach(ExamSkill.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("时间范围", selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(range.title, systemImage: "calendar")
                }
                if editMode.isEditing {
                    Button(role: .destructive) {
                        pendingDeletion = allRecords.filter { selection.contains($0.id) }
                    } label: {
                        Label("删除所选", systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)
                }
                ShareLink(item: MarkdownReport(records: records), preview: SharePreview("IELTS 练习报告")) {
                    Label("导出报告", systemImage: "square.and.arrow.up")
                }
                .disabled(records.isEmpty)
                Button(editMode.isEditing ? "完成" : "编辑") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll()
                    }
                }
                .disabled(allRecords.isEmpty)
            }
        }
        .confirmationDialog("删除 \(pendingDeletion.count) 条练习记录？", isPresented: Binding(
            get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                pendingDeletion.forEach(modelContext.delete)
                try? modelContext.save()
                pendingDeletion = []
                selection.removeAll()
            }
        } message: {
            Text("删除后无法恢复，建议先在“设置”中导出备份。")
        }
    }

    private func summaryGrid(_ statistics: PracticeStatistics) -> some View {
        LazyVGrid(columns: Theme.tileColumns, spacing: Theme.gridSpacing) {
            Group {
                StatTile(title: "练习次数", value: "\(statistics.records.count)", detail: "\(statistics.practicedExamIDs.count) 篇不同题目",
                         symbol: "doc.text.fill", tint: .blue)
                StatTile(title: "平均正确率", value: statistics.totalQuestions > 0 ? statistics.accuracy.percentString : "—",
                         detail: "\(statistics.totalCorrect)/\(statistics.totalQuestions) 题", symbol: "target", tint: .green)
                StatTile(title: "练习时长", value: statistics.totalSeconds.minutesString, detail: "所选时间范围",
                         symbol: "clock.fill", tint: .orange)
                StatTile(title: "连续练习", value: "\(PracticeStatistics(records: allRecords).streak) 天", detail: "今天也要坚持",
                         symbol: "flame.fill", tint: .red)
            }
        }
    }

    private func groupedByDay(_ records: [PracticeRecord]) -> [(day: Date, records: [PracticeRecord])] {
        let groups = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.finishedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}

struct RecordRow: View {
    let record: PracticeRecord
    var showTitle = true

    var body: some View {
        HStack(spacing: 14) {
            if record.isWriting {
                Image(systemName: ExamSkill.writing.iconSymbol)
                    .foregroundStyle(ExamSkill.writing.tint)
                    .frame(width: 40, height: 40)
                    .background(ExamSkill.writing.tint.opacity(0.14), in: Circle())
            } else {
                AccuracyRing(value: record.accuracy, size: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                if showTitle {
                    Text(record.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    RecordBadges(record: record)
                    Text(record.kindTitle)
                    Text("·")
                    Text(record.finishedAt.relativeDescription)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.isWriting ? "\(record.wordCount) 词" : "\(record.score)/\(record.total)")
                    .font(.headline.monospacedDigit())
                HStack(spacing: 4) {
                    if let band = record.band {
                        TagLabel(text: "Band \(band)", color: .accentColor)
                    }
                    Text(record.duration.clockString)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 记录的分类标记：阅读显示 P1–P3，听力显示 Part 1–4，写作显示 Task 1–2。
struct RecordBadges: View {
    let record: PracticeRecord

    var body: some View {
        switch record.skill {
        case .listening:
            let parts = record.listeningParts
            PartBadge(text: parts.count > 1 ? "听力 ×\(parts.count)" : "Part \(parts.first ?? 1)", tint: record.skill.tint)
        case .reading:
            if record.categories.count > 1 {
                PartBadge(text: "阅读 ×\(record.categories.count)", tint: record.skill.tint)
            } else {
                ForEach(record.categories, id: \.self) { CategoryBadge(category: $0) }
            }
        case .writing:
            PartBadge(text: record.writingParts.count > 1 ? "写作 ×\(record.writingParts.count)" : "Task \(record.writingParts.first ?? 1)", tint: record.skill.tint)
        }
    }
}

/// 导出练习报告（Markdown）。
struct MarkdownReport: Transferable {
    let text: String

    init(records: [PracticeRecord]) {
        text = BackupService.markdownReport(records: records)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { report in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("IELTS-练习报告.md")
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
