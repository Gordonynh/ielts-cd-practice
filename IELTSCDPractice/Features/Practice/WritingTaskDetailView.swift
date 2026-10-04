import SwiftData
import SwiftUI

/// 写作题目：题目与图表、开始写作（机考界面）、参考范文、写作记录与机经考情。
struct WritingTaskDetailView: View {
    let item: WritingTaskItem

    @Environment(ExamLauncher.self) private var launcher
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PracticeRecord.finishedAt, order: .reverse) private var allRecords: [PracticeRecord]
    @Query private var drafts: [ExamDraft]
    @State private var showingEssay = false
    @State private var zoomImage: URL?

    private var records: [PracticeRecord] {
        allRecords.filter { $0.skill == .writing && $0.examIDList.contains(item.id) }
    }

    private var draft: ExamDraft? {
        let key = ExamSession.draftKey(kind: .practice, examIDs: [item.id])
        return drafts.first { $0.key == key }
    }

    private var test: PracticeTest? { ContentStore.shared.test(containing: item.id) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        TagLabel(text: "Task \(item.part)")
                        if !item.category.isEmpty { TagLabel(text: item.category) }
                        TagLabel(text: item.source.title)
                    }
                    Text(item.title)
                        .font(.title.weight(.bold))
                    Text("You should spend about \(item.minutes) minutes on this task. Write at least \(item.minWords) words.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.prompt)
                        .font(.body)
                        .textSelection(.enabled)
                    if let name = item.imageName {
                        let url = ContentStore.shared.imageURL(name)
                        if let image = UIImage(contentsOfFile: url.path) {
                            Button {
                                zoomImage = url
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 420)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("放大图表")
                        }
                    } else if item.part == 1 && item.source == .jijing {
                        Label("机经题只有题目文字，没有原题图表", systemImage: "chart.bar.xaxis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                if let draft {
                    Button {
                        launcher.resume(draft)
                    } label: {
                        ActionRow(title: "继续写作", subtitle: "已用时 \(draft.elapsed.clockString)",
                                  symbol: "square.and.pencil", tint: .orange)
                    }
                } else {
                    Button {
                        launcher.writing([item.id])
                    } label: {
                        ActionRow(title: "开始写作", subtitle: "机考界面 · \(item.minutes) 分钟", symbol: "square.and.pencil")
                    }
                }
                if item.essay != nil {
                    Button {
                        showingEssay = true
                    } label: {
                        ActionRow(title: "参考范文", subtitle: "可与自己的作文对照", symbol: "doc.richtext")
                    }
                }
                if let test, test.writing.count > 1 {
                    Button {
                        launcher.writing(test.writingIDs)
                    } label: {
                        ActionRow(title: "整套写作", subtitle: "\(test.title) · Task 1 + Task 2 · 60 分钟",
                                  symbol: "rectangle.stack")
                    }
                }
            } footer: {
                Text("写作界面与官方机考一致：左侧为题目，右侧作答并实时统计字数。写作不自动评分。")
            }

            if let jijing = item.jijing {
                Section("机经考情") {
                    LabeledContent("重考次数", value: "\(jijing.retestCount) 次")
                    LabeledContent("最近考到", value: jijing.lastHitDate ?? "—")
                    NavigationLink(value: jijing) {
                        Text("出现过的考试")
                    }
                }
            }

            if let test {
                Section {
                    NavigationLink(value: Route.test(test.id)) {
                        Label(test.title, systemImage: "books.vertical")
                    }
                } header: {
                    Text("所在试卷")
                }
            }

            Section("写作记录") {
                if records.isEmpty {
                    Text("还没有写过这道题").foregroundStyle(.secondary)
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
        .navigationTitle(item.source == .cambridge ? "\(item.title) · Task \(item.part)" : item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEssay) {
            ModelEssaySheet(item: item, mine: records.first?.payload?.parts.first { $0.examId == item.id }?.essay ?? "")
        }
        .sheet(item: $zoomImage) { url in
            ImageViewer(url: url)
        }
    }
}

/// 参考范文与自己最近一次的作文对照。
struct ModelEssaySheet: View {
    let item: WritingTaskItem
    let mine: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                column(title: "参考范文", text: item.essay ?? "")
                if !mine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                    column(title: "我的作文", text: mine)
                }
            }
            .navigationTitle(item.source == .cambridge ? "\(item.title) · Task \(item.part)" : item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func column(title: String, text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text("\(text.split { $0.isWhitespace || $0.isNewline }.count) 词")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.system(size: 17, design: .serif))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 图片全屏查看（可缩放）。
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                        }
                    }
                    .frame(width: proxy.size.width * scale)
                }
            }
            .gesture(MagnifyGesture()
                .onChanged { value in scale = min(max(base * value.magnification, 1), 4) }
                .onEnded { _ in base = scale })
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
