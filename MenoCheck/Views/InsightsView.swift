import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject private var store: MenoStore
    /// Sleep shares the hot-flash axis at half scale, so the domain must clear both.
    private static let sleepScale = 2.0

    private var chartMax: Double {
        let sleepPeak = (trendDays.map(\.sleepHours).max() ?? 0) / Self.sleepScale
        return max(4, Double(trendDays.hotFlashPeak) + 1, sleepPeak.rounded(.up))
    }

    private var trendDays: [SymptomDay] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            let record = store.record(for: date)
            return SymptomDay(id: offset, label: date.formatted(.dateTime.weekday(.abbreviated)), hotFlashes: record.hotFlashes, sleepHours: record.sleepHours)
        }
    }

    var body: some View {
        MenoScreen(title: "Patterns",
                   subtitle: "Drawn from what you have logged. These are associations, not causes.") {
            VStack(alignment: .leading, spacing: MenoSpace.xl) {
                correlationCard
                seriesCard
                MenoDisclaimer(text: "Patterns need several weeks of data before they mean much. Keep logging, and take these with you to your next appointment.")
            }
        }
    }

    private var correlationCard: some View {
        MenoSection(title: "Hot flashes and sleep", trailing: "Last 7 days") {
            Chart {
                ForEach(trendDays) { day in
                    BarMark(x: .value("Day", day.label),
                            y: .value("Hot flashes", day.hotFlashes),
                            width: .fixed(16))
                        .foregroundStyle(MenoColor.primary)
                        .cornerRadius(4)
                }
                ForEach(trendDays) { day in
                    LineMark(x: .value("Day", day.label),
                             y: .value("Sleep", day.sleepHours / Self.sleepScale))
                        .foregroundStyle(MenoColor.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                        .symbol { Circle().fill(MenoColor.secondary).frame(width: 7, height: 7) }
                }
            }
            .chartXScale(domain: trendDays.map(\.label))
            .chartYScale(domain: 0...chartMax)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(MenoColor.rule)
                    AxisValueLabel().font(MenoFont.caption).foregroundStyle(MenoColor.primary)
                }
                // Sleep gets its own labelled axis. Without one, the line sits against the
                // hot-flash numbers and reads as a count rather than as hours.
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { mark in
                    AxisValueLabel {
                        if let value = mark.as(Double.self) {
                            Text("\(Int(value * Self.sleepScale))h")
                        }
                    }
                    .font(MenoFont.caption)
                    .foregroundStyle(MenoColor.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
                }
            }
            .frame(height: 150)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityElement()
            .accessibilityLabel("Hot flashes and sleep over the last seven days")
            .accessibilityValue(trendDays
                .map { "\($0.label): \($0.hotFlashes) hot flashes, \(String(format: "%.1f", $0.sleepHours)) hours sleep" }
                .joined(separator: ". "))

            HStack(spacing: MenoSpace.l) {
                ChartKey(color: MenoColor.primary, label: "Hot flashes")
                ChartKey(color: MenoColor.secondary, label: "Sleep (hours)")
            }

            MenoRule()

            Text("This chart is built from the daily records you save. Patterns can be useful to discuss with a clinician, but one week cannot establish a cause.")
                .font(MenoFont.secondary)
                .foregroundStyle(MenoColor.inkSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seriesCard: some View {
        let readings = store.fshReadings.reversed()
        return MenoSection(title: "Your test series", trailing: "\(readings.count) of 5 saved") {
            SeriesProgress(completed: min(readings.count, 5), total: 5)
            if readings.isEmpty {
                Text("No saved FSH checks yet. Your series will appear here after you save a reading.").font(MenoFont.secondary).foregroundStyle(MenoColor.inkSecondary)
            } else {
                TracePlot(values: readings.map(\.testLineStrength))
                .frame(height: 56)
            }
            Text(readings.count < 5 ? "Spacing checks out gives a fairer picture than testing on consecutive days." : "This series is complete. Keep results alongside your symptoms and period history for any appointment.")
                .font(MenoFont.secondary)
                .foregroundStyle(MenoColor.inkSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChartKey: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: MenoSpace.s - 2) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(MenoFont.caption)
                .foregroundStyle(MenoColor.inkSecondary)
        }
        .accessibilityHidden(true)
    }
}
