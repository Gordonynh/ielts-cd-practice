import SwiftUI

// MARK: - 筛选条件

enum PracticeStatus: String, CaseIterable, Identifiable, Hashable {
    case all, unpracticed, practiced, mistakes, favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .unpracticed: "未练习"
        case .practiced: "已练习"
        case .mistakes: "有错题"
        case .favorites: "已收藏"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .unpracticed: "circle.dashed"
        case .practiced: "checkmark.circle"
        case .mistakes: "xmark.circle"
        case .favorites: "star"
        }
    }
}

/// 阅读篇目列表的筛选条件
struct PassageFilter: Hashable {
    var title: String
    var category: ExamCategory?
    var kind: QuestionKind?
    var source: ExamSource?
    var status: PracticeStatus = .all
}

/// 听力 Part 列表的筛选条件
struct SectionFilter: Hashable {
    var title: String
    var part: Int?
    var kind: QuestionKind?
    var status: PracticeStatus = .all
}

/// 写作题目列表的筛选条件
struct WritingFilter: Hashable {
    var title: String
    var part: Int
    var category: String?
    var source: WritingTaskItem.Source?
}

// MARK: - 阅读

struct ReadingPassageRow: View {
    let exam: ExamSummary
    let best: PracticeStatistics.ExamBest?
    var isFavorite = false
    var hasDraft = false
    /// 在套题页中不重复显示所属试卷与来源
    var showSet = true

    var body: some View {
        HStack(spacing: 14) {
            CategoryBadge(category: exam.category)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(exam.title)
                        .font(.headline)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("已收藏")
                    }
                }
                Text(([showSet ? exam.subtitle : (exam.titleZh.isEmpty ? nil : exam.titleZh),
                       exam.questionKinds.prefix(2).map(\.title).joined(separator: "、")] as [String?])
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if hasDraft {
                TagLabel(text: "未完成", color: .orange)
            }
            if let jijing = ExtrasStore.shared.jijing(forContent: exam.id), jijing.retestCount > 0 {
                HotLabel(item: jijing)
            }
            if exam.isBank {
                if showSet { TagLabel(text: exam.examSource.shortTitle) }
            } else {
                TagLabel(text: exam.frequency.title, color: exam.frequency == .high ? .red : .secondary)
            }
            AccuracyRing(value: best?.bestAccuracy, size: 34, lineWidth: 4)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 听力

struct ListeningSectionRow: View {
    let test: ListeningTest
    let section: ListeningTest.Section
    let best: PracticeStatistics.ExamBest?
    var showTest = true
    var hasDraft = false

    var body: some View {
        HStack(spacing: 14) {
            PartBadge(text: "Part \(section.part)", tint: ExamSkill.listening.tint)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.displayTopic)
                    .font(.headline)
                    .lineLimit(1)
                Text(([showTest ? test.title : nil, section.topic.isEmpty ? nil : "Q\(section.questionRange)",
                       section.questionKinds.prefix(2).map(\.title).joined(separator: "、")] as [String?])
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if hasDraft {
                TagLabel(text: "未完成", color: .orange)
            }
            if let jijing = ExtrasStore.shared.jijing(forContent: section.id), jijing.retestCount > 0 {
                HotLabel(item: jijing)
            }
            AccuracyRing(value: best?.bestAccuracy, size: 34, lineWidth: 4)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - 写作

struct WritingTaskRow: View {
    let item: WritingTaskItem
    var attempts = 0
    var showTitle = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let name = item.imageName, let image = UIImage(contentsOfFile: ContentStore.shared.imageURL(name).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if showTitle {
                        Text(item.title).font(.headline).lineLimit(1)
                    }
                    PartBadge(text: "Task \(item.part)", tint: ExamSkill.writing.tint)
                    if !item.category.isEmpty { TagLabel(text: item.category) }
                    if item.essay != nil { TagLabel(text: "有范文", color: .indigo) }
                    if attempts > 0 { TagLabel(text: "已写 \(attempts) 次", color: .green) }
                    Spacer(minLength: 0)
                    if let jijing = item.jijing, jijing.retestCount > 0 {
                        HotLabel(item: jijing)
                    }
                }
                Text(item.prompt.replacingOccurrences(of: "\n\n", with: " "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 通用

/// 机经热度：重考次数，近 30 天考到时为红色。
struct HotLabel: View {
    let item: JijingItem

    var body: some View {
        Label("\(item.retestCount)", systemImage: "flame.fill")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(item.isRecent ? Color.red : Color.orange)
            .accessibilityLabel("机经重考 \(item.retestCount) 次" + (item.isRecent ? "，近 30 天考到" : ""))
    }
}

/// 听力音频下载状态。
struct DownloadBadge: View {
    let test: ListeningTest
    let audio: AudioStore

    var body: some View {
        Group {
            if let progress = audio.progress[test.id] {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else if audio.isComplete(test) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("音频已下载")
            } else {
                Image(systemName: "icloud")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("在线播放")
            }
        }
        .frame(width: 22)
    }
}

/// 列表中的操作行：图标 + 标题 + 说明。
struct ActionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 14) {
            TintedIcon(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color(.label))
                Text(subtitle).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
