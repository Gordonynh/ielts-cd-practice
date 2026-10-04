import SwiftData
import SwiftUI

struct JijingRow: View {
    let item: JijingItem

    var body: some View {
        HStack(spacing: 14) {
            PartBadge(text: item.partLabel, tint: item.tint)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title).font(.headline).lineLimit(2).layoutPriority(1)
                    if item.match != nil {
                        TagLabel(text: "可练习", color: .green)
                    }
                    if item.isRecent {
                        TagLabel(text: "近 30 天", color: .red)
                    }
                }
                Text(([item.topic] + item.questionTypes + [item.difficultyText].compactMap { $0 })
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("重考 \(item.retestCount) 次")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(item.lastHit.map { "最近 \($0.agoDescription)" } ?? "暂无命中记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let rate = item.correctRate {
                AccuracyRing(value: Double(rate) / 100, size: 36, lineWidth: 4)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecentHitCard: View {
    let item: JijingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PartBadge(text: item.partLabel, tint: item.tint)
                Spacer()
                if let date = item.lastHitDate {
                    Text(String(date.suffix(5))).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
            HStack {
                Label("\(item.retestCount)", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if let rate = item.correctRate {
                    Text("正确率 \(rate)%")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 220)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 机经题目详情：考情数据、出现过的考试，以及 App 内对应题目的练习入口。
struct JijingDetailView: View {
    let item: JijingItem
    @Environment(ExamLauncher.self) private var launcher
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var records: [PracticeRecord]

    private let content = ContentStore.shared

    var body: some View {
        let recalls = ExtrasStore.shared.recalls(jijing: item.id, content: item.match)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TagLabel(text: item.skill == "writing" ? "写作" : (item.skill == "listening" ? "听力" : "阅读"))
                        TagLabel(text: item.partLabel, color: .secondary)
                        if !item.topic.isEmpty { TagLabel(text: item.topic, color: .secondary) }
                    }
                    Text(item.title)
                        .font(.largeTitle.weight(.bold))
                    if let question = item.question {
                        Text(question)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                        GridRow {
                            metric("重考次数", "\(item.retestCount) 次")
                            metric("最近考到", item.lastHitDate ?? "—")
                            metric("练习人数", item.practiceCount.formatted())
                            if let rate = item.correctRate {
                                metric("平均正确率", "\(rate)%")
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }

            if let match = item.match {
                Section {
                    practiceLink(for: match)
                } header: {
                    Text("练习")
                } footer: {
                    if let mine = myBest(for: match) {
                        Text("你的最佳正确率 \(mine.percentString)" + (item.correctRate.map { "，题库平均 \($0)%" } ?? ""))
                    }
                }
            } else if item.skill == "writing" {
                Section("练习") {
                    NavigationLink(value: Route.writingTask(item.id)) {
                        Label("查看题目并开始写作", systemImage: "square.and.pencil")
                    }
                }
            } else {
                Section {
                    Text("App 中暂无这道题的完整题目，可以查看下方出现过的考试回忆。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("出现过的考试（\(recalls.count)）") {
                if recalls.isEmpty {
                    Text("考试回忆中暂无记录").foregroundStyle(.secondary)
                }
                ForEach(recalls) { exam in
                    NavigationLink(value: exam) {
                        ExamRecallRow(exam: exam)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func practiceLink(for match: String) -> some View {
        if let summary = content.summary(for: match) {
            NavigationLink(value: Route.passage(summary.id)) {
                Label {
                    VStack(alignment: .leading) {
                        Text(summary.title)
                        Text(summary.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "book")
                }
            }
        } else if let (test, section) = content.listeningSection(for: match) {
            Button {
                launcher.listening([section.id])
            } label: {
                Label("练习 \(test.title) · Part \(section.part)", systemImage: "headphones")
            }
        }
    }

    private func myBest(for match: String) -> Double? {
        records.compactMap { record in
            record.payload?.parts.first { $0.examId == match }.map { Double($0.score) / Double(max($0.total, 1)) }
        }.max()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}
