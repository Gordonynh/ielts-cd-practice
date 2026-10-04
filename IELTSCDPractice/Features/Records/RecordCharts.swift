import Charts
import SwiftUI

struct AccuracyTrendChart: View {
    let records: [PracticeRecord]

    var body: some View {
        if records.count < 2 {
            Text("完成两次以上练习后显示趋势")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    LineMark(x: .value("次序", index + 1), y: .value("正确率", record.accuracy * 100))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                    AreaMark(x: .value("次序", index + 1), y: .value("正确率", record.accuracy * 100))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    PointMark(x: .value("次序", index + 1), y: .value("正确率", record.accuracy * 100))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(28)
                }
                RuleMark(y: .value("目标", 75))
                    .foregroundStyle(.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("75%").font(.caption2).foregroundStyle(.green)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .accessibilityLabel("最近 \(records.count) 次练习的正确率趋势")
        }
    }
}

struct DailyMinutesChart: View {
    let activity: [PracticeStatistics.DayActivity]

    var body: some View {
        Chart(activity) { day in
            BarMark(x: .value("日期", day.day, unit: .day), y: .value("分钟", day.minutes))
                .foregroundStyle(Color.orange.gradient)
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: activity.count > 14 ? 5 : (activity.count > 7 ? 2 : 1))) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) 分") }
            }
        }
    }
}

/// 各题型正确率（按正确率从低到高）。
struct KindAccuracyList: View {
    let items: [PracticeStatistics.KindAccuracy]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.kind.title, systemImage: item.kind.symbol)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.correct)/\(item.total) 题")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.accuracy.percentString)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(color(for: item.accuracy))
                            .frame(width: 48, alignment: .trailing)
                    }
                    ProgressView(value: item.accuracy)
                        .tint(color(for: item.accuracy))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func color(for accuracy: Double) -> Color {
        switch accuracy {
        case 0.85...: .green
        case 0.6..<0.85: .orange
        default: .red
        }
    }
}

/// 类似贡献图的练习热力图（按周排列）。
struct PracticeHeatmap: View {
    let activity: [PracticeStatistics.DayActivity]

    /// 让第一列从周一开始：前 weeks-1 周完整，最后一周截止到今天。
    static func dayCount(weeks: Int) -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 周日 = 1
        let daysSinceMonday = (weekday + 5) % 7
        return (weeks - 1) * 7 + daysSinceMonday + 1
    }

    var body: some View {
        let weeks = stride(from: 0, to: activity.count, by: 7).map { Array(activity[$0..<min($0 + 7, activity.count)]) }
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(index % 2 == 0 ? weekdaySymbol(for: activity[safe: index]?.day) : "")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 4) {
                    ForEach(week) { day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: day))
                            .frame(width: 16, height: 16)
                            .accessibilityLabel("\(day.day.formatted(date: .abbreviated, time: .omitted))，\(day.sessions) 次练习")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for day: PracticeStatistics.DayActivity) -> Color {
        switch day.sessions {
        case 0: Color(.tertiarySystemFill)
        case 1: Color.green.opacity(0.4)
        case 2: Color.green.opacity(0.65)
        default: Color.green
        }
    }

    private func weekdaySymbol(for date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
