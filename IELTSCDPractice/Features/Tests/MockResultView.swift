import SwiftData
import SwiftUI

/// 一次模考的成绩：听力、阅读按官方评分表换算，写作、口语可自评后估算总分。
struct MockResult {
    let listening: PracticeRecord?
    let reading: PracticeRecord?
    let writing: PracticeRecord?
    let writingBand: Double?
    let speakingBand: Double?

    init(mock: MockTest, records: [PracticeRecord]) {
        func record(_ id: UUID?) -> PracticeRecord? {
            id.flatMap { id in records.first { $0.id == id } }
        }
        listening = record(mock.listeningRecordID)
        reading = record(mock.readingRecordID)
        writing = record(mock.writingRecordID)
        writingBand = mock.writingBand
        speakingBand = mock.speakingBand
    }

    var listeningBand: Double? { listening?.band.flatMap(Double.init) }
    var readingBand: Double? { reading?.band.flatMap(Double.init) }

    /// 四科都有分数时才计算总分
    var overallBand: Double? {
        guard let listeningBand, let readingBand, let writingBand, let speakingBand else { return nil }
        return BandScore.overall([listeningBand, readingBand, writingBand, speakingBand])
    }

    var bandSummary: String {
        [("听力", listeningBand), ("阅读", readingBand), ("写作", writingBand), ("口语", speakingBand)]
            .compactMap { name, band in band.map { "\(name) \(BandScore.format($0))" } }
            .joined(separator: " · ")
            .ifEmpty("尚无成绩")
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}

struct MockResultView: View {
    let mockID: UUID

    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @Query private var mocks: [MockTest]
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]

    init(mockID: UUID) {
        self.mockID = mockID
        _mocks = Query(filter: #Predicate<MockTest> { $0.id == mockID })
    }

    private static let bandOptions: [Double] = Array(stride(from: 9.0, through: 3.0, by: -0.5))

    var body: some View {
        if let mock = mocks.first, let test = ContentStore.shared.test(mock.testID) {
            let result = MockResult(mock: mock, records: records)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(test.title)
                            .font(.largeTitle.weight(.bold))
                        Text(mock.isFinished
                             ? "完成于 \(mock.finishedAt?.formatted(date: .long, time: .shortened) ?? "")"
                             : "进行到：\(mock.stage.skill?.title ?? "")")
                            .foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 4) {
                            GridRow {
                                bandColumn("听力", result.listeningBand, detail: result.listening.map { "\($0.score)/\($0.total)" })
                                bandColumn("阅读", result.readingBand, detail: result.reading.map { "\($0.score)/\($0.total)" })
                                bandColumn("写作", result.writingBand, detail: result.writingBand == nil ? "未评分" : "自评")
                                bandColumn("口语", result.speakingBand, detail: result.speakingBand == nil ? "未评分" : "自评")
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(width: 1, height: 52)
                                bandColumn("总分", result.overallBand, detail: result.overallBand == nil ? "四科评分后计算" : "估算")
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                if !mock.isFinished {
                    Section {
                        Button {
                            launcher.mock(mock)
                        } label: {
                            ActionRow(title: "继续模考", subtitle: "从\(mock.stage.skill?.title ?? "")开始", symbol: "play.circle.fill")
                        }
                    }
                }

                Section {
                    Picker("写作", selection: Binding(get: { mock.writingBand }, set: { mock.writingBand = $0; save(mock) })) {
                        Text("未评分").tag(Double?.none)
                        ForEach(Self.bandOptions, id: \.self) { Text(BandScore.format($0)).tag(Optional($0)) }
                    }
                    Picker("口语", selection: Binding(get: { mock.speakingBand }, set: { mock.speakingBand = $0; save(mock) })) {
                        Text("未评分").tag(Double?.none)
                        ForEach(Self.bandOptions, id: \.self) { Text(BandScore.format($0)).tag(Optional($0)) }
                    }
                } header: {
                    Text("自评")
                } footer: {
                    Text("写作与口语不能自动评分。可以对照参考范文和评分标准自评，四科都有分数后估算总分。")
                }

                Section("各部分") {
                    ForEach([result.listening, result.reading, result.writing].compactMap { $0 }) { record in
                        NavigationLink(value: record) {
                            RecordRow(record: record, showTitle: true)
                        }
                    }
                    if result.listening == nil && result.reading == nil && result.writing == nil {
                        Text("还没有完成任何部分").foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink(value: Route.test(test.id)) {
                        Label("查看这套试题", systemImage: "books.vertical")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("模考成绩")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("找不到这次模考", systemImage: "questionmark.folder")
        }
    }

    private func bandColumn(_ title: String, _ band: Double?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(band.map(BandScore.format) ?? "—")
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(band == nil ? Color(.tertiaryLabel) : Color(.label))
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save(_ mock: MockTest) {
        mock.updatedAt = Date()
        try? modelContext.save()
    }
}
