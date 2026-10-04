import SwiftData
import SwiftUI

struct RecordDetailView: View {
    let record: PracticeRecord
    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private let content = ContentStore.shared

    var body: some View {
        let payload = record.payload
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            }

            Section {
                Button {
                    launcher.review(record)
                } label: {
                    Label(record.isWriting ? "在机考界面查看作文" : "查看作答与解析", systemImage: "doc.text.magnifyingglass")
                }
                if record.mockID == nil {
                    Button {
                        launcher.start(record.skill, record.examIDList)
                    } label: {
                        Label(record.isWriting ? "再写一次" : "再练一次", systemImage: "arrow.counterclockwise")
                    }
                }
                if let mockID = record.mockID {
                    NavigationLink(value: Route.mock(mockID)) {
                        Label("查看这次模考的成绩", systemImage: "rectangle.stack")
                    }
                }
                if let test = record.examIDList.first.flatMap(content.test(containing:)) {
                    NavigationLink(value: Route.test(test.id)) {
                        Label(test.title, systemImage: "books.vertical")
                    }
                }
            }

            if record.isWriting {
                ForEach(Array((payload?.parts ?? []).enumerated()), id: \.offset) { _, part in
                    essaySection(part)
                }
            } else {
                ForEach(Array((payload?.parts ?? []).enumerated()), id: \.offset) { index, part in
                    Section {
                        ForEach(part.order, id: \.self) { questionID in
                            if let result = part.questions[questionID] {
                                QuestionResultRow(result: result)
                            }
                        }
                    } header: {
                        HStack {
                            if (payload?.parts.count ?? 0) > 1 {
                                Text("Part \(index + 1)")
                            }
                            Text(part.title)
                            Spacer()
                            Text("\(part.score)/\(part.total)").monospacedDigit()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(record.isWriting ? "写作记录" : (record.kind == .fullTest ? "整套成绩" : "练习成绩"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("删除记录", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("删除这条练习记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                modelContext.delete(record)
                try? modelContext.save()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func essaySection(_ part: PartRecord) -> some View {
        let item = content.writingItem(part.examId)
        let minimum = item?.minWords ?? (part.writingPart == 1 ? 150 : 250)
        Section {
            if part.essay.isEmpty {
                Text("没有作答").foregroundStyle(.secondary)
            } else {
                Text(part.essay)
                    .font(.system(size: 17, design: .serif))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
            }
            if item != nil {
                NavigationLink(value: Route.writingTask(part.examId)) {
                    Label(item?.essay != nil ? "题目与参考范文" : "查看题目", systemImage: "doc.richtext")
                }
            }
        } header: {
            HStack {
                Text("Task \(part.writingPart ?? 1) · \(part.title)")
                Spacer()
                Text("\(part.wordCount ?? 0) 词")
                    .monospacedDigit()
                    .foregroundStyle((part.wordCount ?? 0) >= minimum ? Color.secondary : Color.orange)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            if record.isWriting {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, height: 96)
                    .background(Color(.tertiarySystemFill), in: Circle())
            } else {
                AccuracyRing(value: record.accuracy, size: 96, lineWidth: 9)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(record.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    RecordBadges(record: record)
                    Text(record.kindTitle)
                    if record.timeUp {
                        TagLabel(text: "到时自动提交", color: .red)
                    }
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    if record.isWriting {
                        metric("字数", "\(record.wordCount) 词")
                    } else {
                        metric("得分", "\(record.score)/\(record.total)")
                    }
                    if let band = record.band {
                        metric("估算分数", band)
                    }
                    metric("用时", record.duration.clockString)
                    metric("完成时间", record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .padding(.top, 4)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }
}

private struct QuestionResultRow: View {
    let result: QuestionResult

    var body: some View {
        HStack(spacing: 12) {
            Text(result.number)
                .font(.headline.monospacedDigit())
                .frame(width: 32, alignment: .leading)
            Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.correct ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.given.isEmpty ? "未作答" : result.given)
                    .foregroundStyle(result.given.isEmpty ? .secondary : (result.correct ? .primary : Color.red))
                    .strikethrough(!result.correct && !result.given.isEmpty)
                if !result.correct {
                    Text("正确答案：\(result.expected.joined(separator: " / "))")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            Text(result.kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
