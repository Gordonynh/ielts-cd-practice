import SwiftUI

// MARK: - 设计规范

/// 非机考界面的统一视觉规范：卡片式仪表盘，按科目区分颜色。
enum Theme {
    static let cardRadius: CGFloat = 20
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 30
    static let gridSpacing: CGFloat = 14
    static let speaking = Color.pink

    /// 完整模考与首页主卡片的渐变
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.33, green: 0.27, blue: 0.92), Color(red: 0.12, green: 0.52, blue: 0.97)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 两列（竖屏）或四列（横屏）的卡片网格
    static let tileColumns = [GridItem(.adaptive(minimum: 200), spacing: gridSpacing)]
}

extension ExamSkill {
    /// 科目主题色：听力青色、阅读蓝色、写作橙色
    var tint: Color {
        switch self {
        case .listening: .teal
        case .reading: .blue
        case .writing: .orange
        }
    }

    /// 彩色图标块中使用的符号
    var iconSymbol: String {
        switch self {
        case .listening: "headphones"
        case .reading: "book.fill"
        case .writing: "pencil.line"
        }
    }
}

// MARK: - 页面骨架

/// 仪表盘页面：可滚动的分区卡片，背景为系统分组背景色。
struct DashboardPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                content
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// 分区标题，右侧可放「查看全部」等操作。
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing
                .font(.subheadline)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// 一个分区：标题 + 内容。
struct DashboardSection<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle) { trailing }
            content
        }
    }
}

extension DashboardSection where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// 「查看全部 ›」样式的文字按钮。
struct MoreButton: View {
    var title = "查看全部"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 卡片

/// 卡片容器。
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// 卡片内带分隔线的多行内容。
struct DividedRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    var inset: CGFloat = 16
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    Divider().padding(.leading, inset)
                }
                row(element)
            }
        }
    }
}

/// 卡片中的可点按行：按下时高亮。
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Color(.systemFill) : Color.clear)
            .contentShape(Rectangle())
    }
}

/// 整张卡片可点按：按下时轻微缩小。
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 渐变主卡片上的按钮：白底（主要）或半透明（次要）。
struct HeroButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? Color(red: 0.25, green: 0.3, blue: 0.9) : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(prominent ? Color.white : Color.white.opacity(0.2), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 行尾的导航箭头。
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - 图标与标记

/// 彩色圆角图标块（白色符号）。
struct TintedIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 进度圆环，中间可放图标或数字。
struct ProgressRing<Label: View>: View {
    let value: Double
    var tint: Color = .accentColor
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: lineWidth)
            if value > 0 {
                Circle()
                    .trim(from: 0, to: min(max(value, 0.02), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            label
        }
        .frame(width: size, height: size)
    }
}

/// 「P1」「Part 2」「Task 1」等部分标记，可按科目着色。
struct PartBadge: View {
    let text: String
    var large = false
    var tint: Color?

    var body: some View {
        Text(text)
            .font(large ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(tint ?? Color(.secondaryLabel))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, large ? 9 : 6)
            .padding(.vertical, large ? 4 : 2)
            .background(tint.map { $0.opacity(0.14) } ?? Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 阅读 Passage 1–3 标记。
struct CategoryBadge: View {
    let category: ExamCategory
    var large = false

    var body: some View {
        PartBadge(text: category.shortTitle, large: large, tint: ExamSkill.reading.tint)
            .accessibilityLabel(category.title)
    }
}

struct TagLabel: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// 数字统计卡片。
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TintedIcon(symbol: symbol, tint: tint, size: 28)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 正确率圆环。
struct AccuracyRing: View {
    let value: Double?
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4.5

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            if let value {
                Circle()
                    .trim(from: 0, to: max(value, 0.001))
                    .stroke(Self.color(for: value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Image(systemName: "minus")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(value.map { "正确率 \($0.percentString)" } ?? "未练习")
    }

    static func color(for value: Double) -> Color {
        switch value {
        case 0.85...: .green
        case 0.6..<0.85: .orange
        default: .red
        }
    }
}

struct DifficultyStars: View {
    let stars: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= stars ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(index <= stars ? Color.orange : Color(.quaternaryLabel))
            }
        }
        .accessibilityLabel("难度 \(stars) 星")
    }
}

extension Date {
    var relativeDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "今天 " + formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return "昨天 " + formatted(date: .omitted, time: .shortened) }
        return formatted(.dateTime.month().day().hour().minute())
    }
}

// MARK: - 布局

/// 自动换行的横向排列（用于标签、话题等）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 日期

extension Date {
    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 「周六」
    var weekdayName: String {
        Self.weekdayNames[(Calendar.current.component(.weekday, from: self) - 1) % 7]
    }

    /// 「10月3日 周六」
    var chineseDay: String {
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: self))月\(calendar.component(.day, from: self))日 \(weekdayName)"
    }

    /// 「10/3」
    var shortDay: String {
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: self))/\(calendar.component(.day, from: self))"
    }
}

extension Int {
    /// 「3 小时 20 分」「45 分钟」
    var durationText: String {
        if self < 60 { return "\(self) 分钟" }
        return self % 60 == 0 ? "\(self / 60) 小时" : "\(self / 60) 小时 \(self % 60) 分"
    }
}
