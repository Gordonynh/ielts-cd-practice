import SwiftUI

/// 考试回忆：按考试日期列出每场考试出现的听力、阅读、写作题目。
struct ExamRecallView: View {
    @State private var searchText = ""

    private let extras = ExtrasStore.shared

    private var exams: [ExamRecall] {
        guard !searchText.isEmpty else { return extras.exams }
        return extras.exams.filter { exam in
            exam.place.localizedCaseInsensitiveContains(searchText)
                || exam.date.contains(searchText)
                || (exam.listening + exam.reading).contains { ($0.theme ?? "").localizedCaseInsensitiveContains(searchText) }
                || exam.writing.contains { ($0.question ?? "").localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var grouped: [(month: String, exams: [ExamRecall])] {
        var order: [String] = []
        var groups: [String: [ExamRecall]] = [:]
        for exam in exams {
            let month = String(exam.date.prefix(7))
            if groups[month] == nil { order.append(month) }
            groups[month, default: []].append(exam)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if exams.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            }
            ForEach(grouped, id: \.month) { group in
                Section(monthTitle(group.month)) {
                    ForEach(group.exams) { exam in
                        NavigationLink(value: exam) {
                            ExamRecallRow(exam: exam)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("考试回忆")
        .searchable(text: $searchText, prompt: "搜索考点、主题或写作题目")
    }

    private func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let value = Int(parts[1]) else { return month }
        return "\(year) 年 \(value) 月"
    }
}

struct ExamRecallRow: View {
    let exam: ExamRecall

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(exam.day.map { String(Calendar.current.component(.day, from: $0)) } ?? "")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(exam.day.map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(exam.place.isEmpty ? "未注明考点" : exam.place)
                    .font(.headline)
                    .lineLimit(1)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                if !exam.listening.isEmpty { countTag("听", exam.listening.count) }
                if !exam.reading.isEmpty { countTag("读", exam.reading.count) }
                if !exam.writing.isEmpty { countTag("写", exam.writing.count) }
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let themes = exam.reading.compactMap(\.theme) + exam.listening.compactMap(\.theme)
        if !themes.isEmpty { return themes.prefix(3).joined(separator: " · ") }
        return exam.writing.compactMap(\.question).first ?? "旧题回忆"
    }

    private func countTag(_ label: String, _ count: Int) -> some View {
        Text("\(label) \(count)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

struct ExamRecallDetailView: View {
    let exam: ExamRecall
    @Environment(ExamLauncher.self) private var launcher
    @State private var zoomImage: URL?

    private let content = ContentStore.shared
    private let extras = ExtrasStore.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exam.day.map { $0.formatted(.dateTime.year().month().day().weekday(.wide)) } ?? exam.date)
                        .font(.title.weight(.bold))
                    Text(exam.place.isEmpty ? "未注明考点" : exam.place)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if !exam.listening.isEmpty {
                Section("听力") {
                    ForEach(Array(exam.listening.enumerated()), id: \.offset) { _, item in
                        itemRow(item, skill: .listening)
                    }
                }
            }
            if !exam.reading.isEmpty {
                Section("阅读") {
                    ForEach(Array(exam.reading.enumerated()), id: \.offset) { _, item in
                        itemRow(item, skill: .reading)
                    }
                }
            }
            if !exam.writing.isEmpty {
                Section("写作") {
                    ForEach(Array(exam.writing.enumerated()), id: \.offset) { _, task in
                        taskRow(task)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(exam.date)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $zoomImage) { url in
            ZoomableImageView(url: url)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ExamRecall.Item, skill: ExamSkill) -> some View {
        let jijing = item.jijing.flatMap(extras.item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let part = item.part {
                    PartBadge(text: skill == .listening ? "Part \(part)" : "Passage \(part)", tint: skill.tint)
                }
                Text(item.theme ?? (item.code.map { "题号 \($0)" } ?? "旧题"))
                    .font(.headline)
                if let rating = item.rating {
                    DifficultyStars(stars: rating)
                }
                Spacer()
                if let jijing {
                    Text("重考 \(jijing.retestCount) 次").font(.caption).foregroundStyle(.secondary)
                }
            }
            let details = [item.questionTypes.map { "题型：\($0)" }, item.keywords.map { "关键词：\($0)" }, item.note]
                .compactMap { $0 }.filter { !$0.isEmpty && $0 != "旧题如图" }
            if !details.isEmpty {
                Text(details.joined(separator: "\n"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let image = item.image, let url = URL(string: image) {
                RemoteImage(url: url)
                    .onTapGesture { zoomImage = url }
            }
            HStack(spacing: 12) {
                if let match = item.match {
                    matchButton(match)
                }
                if let jijing {
                    NavigationLink("机经数据", value: jijing)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func taskRow(_ task: ExamRecall.Task) -> some View {
        let jijing = task.jijing.flatMap(extras.item)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PartBadge(text: "Task \(task.task ?? 2)", tint: ExamSkill.writing.tint)
                if let jijing {
                    Text(jijing.title).font(.headline)
                    Spacer()
                    Text("重考 \(jijing.retestCount) 次").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let question = task.question {
                Text(question)
            } else if let note = task.note {
                Text(note).foregroundStyle(.secondary)
            }
            if let image = task.image, let url = URL(string: image) {
                RemoteImage(url: url)
                    .onTapGesture { zoomImage = url }
            }
            if let prompt = jijing ?? writingPrompt(for: task) {
                NavigationLink(value: Route.writingTask(prompt.id)) {
                    Label("写这道题", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func writingPrompt(for task: ExamRecall.Task) -> JijingItem? {
        guard let question = task.question else { return nil }
        return extras.writingPrompts.first { $0.question == question }
    }

    @ViewBuilder
    private func matchButton(_ match: String) -> some View {
        if let summary = content.summary(for: match) {
            NavigationLink(value: Route.passage(summary.id)) {
                Label("练习这篇", systemImage: "book")
            }
            .buttonStyle(.borderedProminent)
        } else if let (_, section) = content.listeningSection(for: match) {
            Button {
                launcher.listening([section.id])
            } label: {
                Label("练习这个 Part", systemImage: "headphones")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// 在线图片（考试回忆截图）。
struct RemoteImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(6)
                            .background(.thinMaterial, in: Circle())
                            .padding(8)
                    }
            case .failure:
                Label("图片加载失败（需要联网）", systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ZoomableImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 900 * scale)
            }
            .gesture(MagnifyGesture().onChanged { value in
                scale = min(max(value.magnification, 0.6), 4)
            })
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
