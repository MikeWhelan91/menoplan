import Charts
import SwiftUI

// Pro charts on Test Trends built from the cycle history: each view takes
// plain values so the same view renders on screen and in the PDF report.

private extension CyclePhaseKind {
    var color: Color {
        switch self {
        case .period: .linePink
        case .follicular: .lineNavy.opacity(0.12)
        case .fertile: .lineFertileSoft
        case .luteal: .lineLutealSoft
        }
    }
}

private func trendsDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated))
}

private struct TrendsCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.app(.caption, weight: .medium))
            .foregroundStyle(Color.lineNavy.opacity(0.68))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TrendsEmpty: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: LineType.size(24), weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.10), in: Circle())
            Text(title)
                .font(.app(.headline))
                .foregroundStyle(Color.lineNavy)
            Text(message)
                .font(.app(.subheadline))
                .foregroundStyle(Color.lineNavy.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - 1. Cycle history

struct CycleHistoryChart: View {
    let entries: [CycleHistoryEntry]
    var limit = 8

    private var rows: [CycleHistoryEntry] { Array(entries.suffix(limit).reversed()) }
    private var maxSpan: Int { max(28, rows.map(\.span).max() ?? 28) }

    var body: some View {
        if entries.isEmpty {
            TrendsEmpty(icon: "calendar", title: "No cycles yet", message: "Log a period in Calendar and each cycle will appear here.", tint: .linePink)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(rows) { entry in row(entry) }
                }
                legend
                if let caption { TrendsCaption(text: caption) }
            }
        }
    }

    private var caption: String? {
        // Implausible lengths (spotting logged as a period) would drag the
        // average; they still get a row, just not a say in the numbers.
        let closed = entries.filter(\.isPlausible).compactMap(\.length)
        let confirmed = entries.filter { $0.ovulationConfirmed && !$0.isCurrent && $0.isPlausible }.count
        guard !closed.isEmpty else { return "Your first full cycle will appear once your next period is logged." }
        let average = Int((Double(closed.reduce(0, +)) / Double(closed.count)).rounded())
        var text = "Your cycles average \(average) days across \(closed.count) logged \(closed.count == 1 ? "cycle" : "cycles")."
        if confirmed > 0 {
            text += " Ovulation was confirmed by a test or temperature rise in \(confirmed)."
        }
        if let odd = entries.first(where: { !$0.isPlausible }), let length = odd.length {
            text += " The \(length)-day cycle from \(trendsDate(odd.start)) isn't counted; it may be worth checking that period's dates."
        }
        return text
    }

    private func row(_ entry: CycleHistoryEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isCurrent ? "Now" : trendsDate(entry.start))
                    .font(.app(size: LineType.size(12), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                Text(entry.length.map { "\($0) days" } ?? "Day \(entry.elapsed)")
                    .font(.app(size: LineType.size(11), weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
            }
            .lineLimit(1)
            .frame(width: LineType.size(58), alignment: .leading)

            GeometryReader { proxy in
                let dayWidth = proxy.size.width / CGFloat(maxSpan)
                ZStack(alignment: .leading) {
                    ForEach(segments(entry), id: \.start) { segment in
                        Capsule()
                            .fill(segment.phase.color.opacity(segment.faded ? 0.35 : 1))
                            .frame(width: max(2, CGFloat(segment.length) * dayWidth - 1.5), height: 12)
                            .offset(x: CGFloat(segment.start) * dayWidth)
                    }
                    if entry.isPlausible {
                    Circle()
                        .fill(entry.ovulationConfirmed ? Color.linePurple : Color.white)
                        .overlay(Circle().strokeBorder(Color.linePurple, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .offset(x: (CGFloat(entry.ovulation) + 0.5) * dayWidth - 7)
                    }
                    if entry.isCurrent {
                        Rectangle()
                            .fill(Color.lineNavy)
                            .frame(width: 2, height: 20)
                            .offset(x: CGFloat(entry.elapsed) * dayWidth - 1)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(entry))
    }

    private struct Segment { let start: Int; let length: Int; let phase: CyclePhaseKind; let faded: Bool }

    private func segments(_ entry: CycleHistoryEntry) -> [Segment] {
        var result: [Segment] = []
        var runStart = 0
        func flush(_ end: Int) {
            guard end > runStart else { return }
            let phase = entry.phase(atOffset: runStart)
            let faded = entry.isCurrent && runStart >= entry.elapsed
            result.append(Segment(start: runStart, length: end - runStart, phase: phase, faded: faded))
            runStart = end
        }
        for offset in 1...entry.span {
            let changed = offset == entry.span
                || entry.phase(atOffset: offset) != entry.phase(atOffset: offset - 1)
                || (entry.isCurrent && offset == entry.elapsed)
            if changed { flush(offset) }
        }
        return result
    }

    private func accessibility(_ entry: CycleHistoryEntry) -> String {
        let ovulation = entry.ovulationConfirmed ? "confirmed ovulation on day \(entry.ovulation + 1)" : "estimated ovulation on day \(entry.ovulation + 1)"
        let length = entry.length.map { "\($0) day cycle" } ?? "current cycle, day \(entry.elapsed)"
        return "Cycle from \(trendsDate(entry.start)), \(length), \(entry.periodDays) day period, \(ovulation)"
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Capsule().fill(Color.linePink), "Period")
            legendItem(Capsule().fill(Color.lineFertileSoft), "Fertile")
            legendItem(Circle().fill(Color.linePurple), "Confirmed")
            legendItem(Circle().strokeBorder(Color.linePurple, lineWidth: 2), "Estimated")
            legendItem(Capsule().fill(Color.lineLutealSoft), "Luteal")
        }
        .font(.app(size: LineType.size(10), weight: .semibold))
        .foregroundStyle(Color.lineNavy.opacity(0.6))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    private func legendItem<S: View>(_ swatch: S, _ title: String) -> some View {
        HStack(spacing: 4) {
            swatch.frame(width: 10, height: 10)
            Text(title)
        }
    }
}

// MARK: - 2. Luteal phase

struct LutealPhaseChart: View {
    let entries: [CycleHistoryEntry]

    private var points: [(start: Date, length: Int)] {
        entries.compactMap { entry in entry.lutealLength.map { (entry.start, $0) } }.suffix(8).map { $0 }
    }

    var body: some View {
        if let summary = CycleTrendsCalculator.lutealSummary(entries) {
            VStack(spacing: 12) {
                Chart {
                    ForEach(points, id: \.start) { point in
                        BarMark(x: .value("Cycle", trendsDate(point.start)), y: .value("Days", point.length))
                            .foregroundStyle(point.length < CycleTrendsCalculator.shortLutealThreshold ? Color.linePink : Color.lineLuteal)
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                Text("\(point.length)")
                                    .font(.app(size: LineType.size(11), weight: .bold))
                                    .foregroundStyle(Color.lineNavy.opacity(0.7))
                            }
                    }
                    RuleMark(y: .value("Short", CycleTrendsCalculator.shortLutealThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.linePink.opacity(0.6))
                }
                .chartYScale(domain: 0...max(18, (points.map(\.length).max() ?? 14) + 3))
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(minHeight: 180)
                HStack(spacing: 14) {
                    lutealLegend(.lineLuteal, "10 days or more")
                    lutealLegend(.linePink, "Under 10 days")
                }
                .font(.app(size: LineType.size(11), weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.6))
                TrendsCaption(text: caption(summary))
            }
        } else {
            TrendsEmpty(
                icon: "moon.stars.fill",
                title: "Needs a confirmed ovulation",
                message: "Once a Peak test or a temperature rise confirms ovulation and your next period is logged, the days in between appear here.",
                tint: .lineLuteal
            )
        }
    }

    private func lutealLegend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(title)
        }
    }

    private func caption(_ summary: CycleTrendsCalculator.LutealSummary) -> String {
        let count = summary.lengths.count
        var text = "Your luteal phase has been about \(summary.median) days across \(count) confirmed \(count == 1 ? "cycle" : "cycles"). 10 to 16 days is typical; the dashed line marks 10."
        if summary.shortCount > 0 {
            text += " \(summary.shortCount == 1 ? "One was" : "\(summary.shortCount) were") under 10 days, which is worth mentioning to your doctor if you're trying to conceive."
        }
        return text
    }
}

// MARK: - 4. Prediction accuracy

struct PredictionAccuracyChart: View {
    let entries: [CycleHistoryEntry]

    private var points: [(start: Date, error: Int)] {
        entries.compactMap { entry in entry.predictionErrorDays.map { (entry.start, $0) } }.suffix(8).map { $0 }
    }

    var body: some View {
        if let summary = CycleTrendsCalculator.accuracySummary(entries) {
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(summary.withinOneDay) of \(summary.count)")
                        .font(.app(size: LineType.size(30), weight: .heavy))
                        .foregroundStyle(Color.linePurple)
                    Text(summary.count == 1 ? "prediction within a day" : "predictions within a day")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.65))
                }
                Chart {
                    RuleMark(y: .value("On time", 0))
                        .foregroundStyle(Color.lineNavy.opacity(0.25))
                    ForEach(points, id: \.start) { point in
                        BarMark(x: .value("Cycle", trendsDate(point.start)), y: .value("Days", point.error))
                            .foregroundStyle(color(for: point.error))
                            .cornerRadius(5)
                            .annotation(position: point.error >= 0 ? .top : .bottom) {
                                Text(label(point.error))
                                    .font(.app(size: LineType.size(10), weight: .bold))
                                    .foregroundStyle(Color.lineNavy.opacity(0.7))
                            }
                    }
                }
                .chartYScale(domain: domain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel { if let days = value.as(Int.self) { Text(label(days)) } }
                    }
                }
                .frame(minHeight: 150)
                TrendsCaption(text: caption(summary))
            }
        } else {
            TrendsEmpty(
                icon: "target",
                title: "Checking our predictions",
                message: "After your next period, you'll see how close MenoPlan's forecast was, cycle by cycle.",
                tint: .linePurple
            )
        }
    }

    private var domain: ClosedRange<Int> {
        // Headroom past the longest bar so its value label never meets the
        // axis labels.
        let longest = max(3, points.map { abs($0.error) }.max() ?? 3)
        let extreme = longest + max(2, Int((Double(longest) * 0.35).rounded(.up)))
        return -extreme...extreme
    }

    private func color(for error: Int) -> Color {
        switch abs(error) {
        case ...1: .linePurple
        case ...3: .lineFertileSoft
        default: .linePink
        }
    }

    private func label(_ days: Int) -> String { days == 0 ? "0" : (days > 0 ? "+\(days)" : "\(days)") }

    private func caption(_ summary: CycleTrendsCalculator.AccuracySummary) -> String {
        let average = summary.averageMissDays.formatted(.number.precision(.fractionLength(0...1)))
        return "On average your period came \(average) \(summary.averageMissDays == 1 ? "day" : "days") from the forecast. Bars above the line mean it came later than predicted, below means earlier. Predictions sharpen as you log more cycles and tests."
    }
}

// MARK: - 5. Symptom timing

struct SymptomTimingView: View {
    let timings: [SymptomTiming]
    var limit = 6

    var body: some View {
        if timings.isEmpty {
            TrendsEmpty(
                icon: "clock.arrow.circlepath",
                title: "Not enough logs yet",
                message: "Log a symptom or mood at least three times across your cycle to see when it tends to show up.",
                tint: .linePink
            )
        } else {
            VStack(spacing: 14) {
                ForEach(timings.prefix(limit)) { timing in row(timing) }
                phaseLegend
            }
        }
    }

    private func row(_ timing: SymptomTiming) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(timing.name)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                if timing.kind == .mood {
                    Text("Mood")
                        .font(.app(size: LineType.size(10), weight: .bold))
                        .foregroundStyle(Color.linePurple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.linePurple.opacity(0.1), in: Capsule())
                }
                Spacer()
                Text("\(timing.total) logs")
                    .font(.app(.caption, weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(CyclePhaseKind.allCases) { phase in
                        let count = timing.counts[phase] ?? 0
                        if count > 0 {
                            Rectangle()
                                .fill(phase.color)
                                .frame(width: max(3, proxy.size.width * CGFloat(count) / CGFloat(timing.total) - 2))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            Text(timing.summary)
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.65))
        }
        .accessibilityElement(children: .combine)
    }

    private var phaseLegend: some View {
        HStack(spacing: 12) {
            ForEach(CyclePhaseKind.allCases) { phase in
                HStack(spacing: 4) {
                    Capsule().fill(phase.color).frame(width: 10, height: 8)
                    Text(phase.title)
                }
            }
        }
        .font(.app(size: LineType.size(10), weight: .semibold))
        .foregroundStyle(Color.lineNavy.opacity(0.6))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 6. Body and lifestyle across the cycle

enum BodyTrendMetric: String, CaseIterable, Identifiable {
    case restingHeartRate, hrv, sleep, wristTemperature, weight
    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingHeartRate: "Resting HR"
        case .hrv: "HRV"
        case .sleep: "Sleep"
        case .wristTemperature: "Wrist Temp"
        case .weight: "Weight"
        }
    }

    var longTitle: String {
        switch self {
        case .restingHeartRate: "Resting Heart Rate"
        case .hrv: "Heart Rate Variability"
        case .sleep: "Sleep"
        case .wristTemperature: "Wrist Temperature"
        case .weight: "Weight"
        }
    }
}

struct BodyTrendData {
    let entries: [CycleHistoryEntry]
    let metrics: [DailyHealthMetrics]
    let logs: [DailyFertilityLog]
    let weightUnit: WeightUnit
    let temperatureUnit: TemperatureUnit

    func values(_ metric: BodyTrendMetric) -> [(date: Date, value: Double)] {
        func from(_ keyPath: KeyPath<DailyHealthMetrics, Double?>) -> [(date: Date, value: Double)] {
            metrics.compactMap { row in row[keyPath: keyPath].flatMap { $0 > 0 ? (row.date, $0) : nil } }
        }
        switch metric {
        case .restingHeartRate: return from(\.restingHeartRate)
        case .hrv: return from(\.heartRateVariabilityMs)
        case .sleep: return from(\.sleepHours)
        case .wristTemperature:
            return logs.compactMap { log in log.wristTemperatureCelsius.map { (log.date, display(temperature: $0)) } }
        case .weight:
            return logs.compactMap { log in log.weightKg.map { (log.date, display(weight: $0)) } }
        }
    }

    var available: [BodyTrendMetric] { BodyTrendMetric.allCases.filter { values($0).count >= 3 } }

    func display(temperature celsius: Double) -> Double { temperatureUnit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius }
    func display(weight kg: Double) -> Double {
        switch weightUnit {
        case .kilograms: kg
        case .pounds: kg * BodyMeasurementUnit.poundsPerKilogram
        case .stone: kg * BodyMeasurementUnit.poundsPerKilogram / 14
        }
    }

    func format(_ value: Double, _ metric: BodyTrendMetric) -> String {
        switch metric {
        case .restingHeartRate: "\(Int(value.rounded())) bpm"
        case .hrv: "\(Int(value.rounded())) ms"
        case .sleep: "\(value.formatted(.number.precision(.fractionLength(1)))) h"
        case .wristTemperature: "\(value.formatted(.number.precision(.fractionLength(2))))\(temperatureUnit.title)"
        case .weight:
            switch weightUnit {
            case .kilograms: "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
            case .pounds: "\(value.formatted(.number.precision(.fractionLength(1)))) lb"
            case .stone: weightUnit.formatted(value * 14 / BodyMeasurementUnit.poundsPerKilogram)
            }
        }
    }

    /// Plain-language comparison of the luteal and follicular averages.
    func phaseSentence(_ metric: BodyTrendMetric) -> String? {
        let averages = CycleTrendsCalculator.phaseAverages(values(metric), entries: entries)
        guard let luteal = averages.first(where: { $0.phase == .luteal }), luteal.count >= 3,
              let before = averages.first(where: { $0.phase == .follicular }) ?? averages.first(where: { $0.phase == .fertile }),
              before.count >= 3 else { return nil }
        let delta = luteal.value - before.value
        switch metric {
        case .restingHeartRate:
            guard abs(delta) >= 1 else { return "Your resting heart rate stays about the same through your cycle." }
            return "Your resting heart rate runs about \(Int(abs(delta).rounded())) bpm \(delta > 0 ? "higher" : "lower") after ovulation\(delta > 0 ? ", a common pattern as progesterone rises" : "")."
        case .hrv:
            guard abs(delta) >= 2 else { return "Your HRV stays about the same through your cycle." }
            return "Your HRV is about \(Int(abs(delta).rounded())) ms \(delta > 0 ? "higher" : "lower") after ovulation\(delta < 0 ? ", which many people see in the luteal phase" : "")."
        case .sleep:
            guard abs(delta) >= 0.25 else { return "Your sleep stays about the same through your cycle." }
            return "You sleep about \(Int((abs(delta) * 60).rounded())) minutes \(delta > 0 ? "more" : "less") after ovulation."
        case .wristTemperature:
            let shown = abs(delta).formatted(.number.precision(.fractionLength(1)))
            return delta > 0.1 ? "Your wrist temperature runs about \(shown)\(temperatureUnit.title) warmer after ovulation, consistent with ovulation happening." : "No clear rise in wrist temperature after ovulation yet."
        case .weight:
            return nil
        }
    }
}

struct BodyAcrossCycleView: View {
    let data: BodyTrendData
    @State private var selection: BodyTrendMetric?

    var body: some View {
        let available = data.available
        if available.isEmpty {
            TrendsEmpty(
                icon: "heart.text.square",
                title: "Connect Apple Health",
                message: "Resting heart rate, HRV, sleep, wrist temperature and weight show up here across your cycle phases.",
                tint: .linePink
            )
        } else {
            let metric = selection.flatMap { available.contains($0) ? $0 : nil } ?? available[0]
            VStack(spacing: 12) {
                if available.count > 1 {
                    // Chips wrap instead of squeezing five labels into a
                    // segmented control, so no name is ever cut short.
                    FlowLayout(spacing: 8) {
                        ForEach(available) { option in
                            let isSelected = option == metric
                            Button { selection = option } label: {
                                Text(option.title)
                                    .font(.app(size: LineType.size(13), weight: .bold))
                                    .foregroundStyle(isSelected ? Color.white : Color.lineNavy.opacity(0.65))
                                    .fixedSize()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isSelected ? Color.linePurple : Color.lineNavy.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                BodyMetricChart(data: data, metric: metric)
            }
        }
    }
}

/// One metric's chart: weight over time, anything else by cycle day over
/// the phase bands of the latest cycle with readings.
struct BodyMetricChart: View {
    let data: BodyTrendData
    let metric: BodyTrendMetric

    var body: some View {
        let values = data.values(metric)
        VStack(spacing: 12) {
            if metric == .weight {
                weightChart(values)
            } else if let entry = cycleWithReadings(values) {
                cycleChart(values, entry: entry)
                averagesRow(values)
            }
            if let sentence = data.phaseSentence(metric) { TrendsCaption(text: sentence) }
        }
    }

    /// The latest full cycle with a week of readings shows the whole
    /// pattern; the current cycle is the fallback.
    private func cycleWithReadings(_ values: [(date: Date, value: Double)]) -> CycleHistoryEntry? {
        data.entries.last { !$0.isCurrent && CycleTrendsCalculator.cycleDaySeries(values, entry: $0).count >= 7 }
            ?? data.entries.last { CycleTrendsCalculator.cycleDaySeries(values, entry: $0).count >= 3 }
    }

    private func cycleChart(_ values: [(date: Date, value: Double)], entry: CycleHistoryEntry) -> some View {
        let series = CycleTrendsCalculator.cycleDaySeries(values, entry: entry)
        let low = series.map(\.value).min() ?? 0
        let high = series.map(\.value).max() ?? 1
        let pad = max((high - low) * 0.25, metric == .wristTemperature ? 0.1 : 1)
        let bands = phaseBands(entry)
        return VStack(spacing: 4) {
            Chart {
                ForEach(bands, id: \.start) { band in
                    RectangleMark(xStart: .value("From", band.start + 1), xEnd: .value("To", band.end + 1))
                        .foregroundStyle(band.phase.color.opacity(0.22))
                }
                ForEach(series, id: \.offset) { point in
                    LineMark(x: .value("Cycle day", point.offset + 1), y: .value(metric.longTitle, point.value))
                        .foregroundStyle(Color.linePurple)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Cycle day", point.offset + 1), y: .value(metric.longTitle, point.value))
                        .foregroundStyle(Color.linePurple)
                        .symbolSize(24)
                }
            }
            .chartXScale(domain: 1...(entry.span + 1))
            .chartXAxis { AxisMarks(values: [1, 7, 14, 21, 28, 35].filter { $0 <= entry.span }) }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel { if let number = value.as(Double.self) { Text(axisLabel(number)) } }
                }
            }
            .chartXAxisLabel("Cycle day", alignment: .center)
            .frame(minHeight: 170)
            Text(entry.isCurrent ? "This cycle" : "Cycle from \(trendsDate(entry.start))")
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.5))
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .sleep: "\(value.formatted(.number.precision(.fractionLength(0...1))))h"
        case .wristTemperature: value.formatted(.number.precision(.fractionLength(1)))
        default: "\(Int(value.rounded()))"
        }
    }

    private struct Band { let start: Int; let end: Int; let phase: CyclePhaseKind }

    private func phaseBands(_ entry: CycleHistoryEntry) -> [Band] {
        var bands: [Band] = []
        var start = 0
        for offset in 1...entry.span where offset == entry.span || entry.phase(atOffset: offset) != entry.phase(atOffset: offset - 1) {
            bands.append(Band(start: start, end: offset, phase: entry.phase(atOffset: start)))
            start = offset
        }
        return bands
    }

    private func averagesRow(_ values: [(date: Date, value: Double)]) -> some View {
        let averages = CycleTrendsCalculator.phaseAverages(values, entries: data.entries)
        return HStack(spacing: 8) {
            ForEach(averages, id: \.phase) { average in
                VStack(spacing: 2) {
                    Text(average.phase.title)
                        .font(.app(size: LineType.size(10), weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(data.format(average.value, metric))
                        .font(.app(size: LineType.size(13), weight: .bold))
                        .foregroundStyle(Color.lineNavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(average.phase.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func weightChart(_ values: [(date: Date, value: Double)]) -> some View {
        let recent = values.sorted { $0.date < $1.date }.suffix(60)
        let low = recent.map(\.value).min() ?? 0
        let high = recent.map(\.value).max() ?? 1
        let pad = max((high - low) * 0.3, data.weightUnit == .stone ? 0.2 : 1)
        return VStack(spacing: 8) {
            Chart {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                        .foregroundStyle(Color.linePurple)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                        .foregroundStyle(Color.linePurple)
                        .symbolSize(22)
                }
            }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(data.weightUnit == .stone
                                ? data.format(number, .weight)
                                : "\(number.formatted(.number.precision(.fractionLength(0...1)))) \(data.weightUnit.shortTitle)")
                        }
                    }
                }
            }
            .frame(minHeight: 170)
            if let first = recent.first, let last = recent.last, recent.count >= 2 {
                let change = last.value - first.value
                let shown = data.weightUnit == .stone
                    ? "\((abs(change) * 14).formatted(.number.precision(.fractionLength(1)))) lb"
                    : "\(abs(change).formatted(.number.precision(.fractionLength(1)))) \(data.weightUnit.shortTitle)"
                TrendsCaption(text: abs(change) < 0.05
                    ? "Your weight has held steady since \(trendsDate(first.date)). Latest: \(data.format(last.value, .weight))."
                    : "Your weight is \(shown) \(change > 0 ? "up" : "down") since \(trendsDate(first.date)). Latest: \(data.format(last.value, .weight)).")
            }
        }
    }
}

// MARK: - 7. What LineCheck noticed

struct NoticedTimelineItem: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let tone: MenoPlan.CycleSignal.Tone
    let firstSeen: Date
    let lastSeen: Date
}

struct NoticedTimelineView: View {
    let entries: [CycleHistoryEntry]
    let items: [NoticedTimelineItem]
    var cycleLimit = 3

    private var groups: [(title: String, items: [NoticedTimelineItem])] {
        var grouped: [UUID: [NoticedTimelineItem]] = [:]
        var loose: [NoticedTimelineItem] = []
        for item in items {
            if let (entry, _) = CycleTrendsCalculator.locate(item.firstSeen, in: entries) {
                grouped[entry.id, default: []].append(item)
            } else {
                loose.append(item)
            }
        }
        var result: [(String, [NoticedTimelineItem])] = entries.reversed().compactMap { entry in
            guard let list = grouped[entry.id], !list.isEmpty else { return nil }
            return (entry.isCurrent ? "This cycle" : "Cycle from \(trendsDate(entry.start))", list.sorted { $0.firstSeen > $1.firstSeen })
        }
        if !loose.isEmpty { result.append(("Earlier", loose.sorted { $0.firstSeen > $1.firstSeen })) }
        return Array(result.prefix(cycleLimit))
    }

    var body: some View {
        if items.isEmpty {
            TrendsEmpty(
                icon: "eye",
                title: "Nothing noticed yet",
                message: "Anything MenoPlan spots in your cycle, daily log or Apple Health is saved here, cycle by cycle.",
                tint: .linePurple
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title.uppercased())
                            .font(.app(.caption2, weight: .heavy))
                            .foregroundStyle(Color.lineNavy.opacity(0.45))
                            .tracking(0.5)
                        ForEach(group.items) { item in row(item) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ item: NoticedTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(item.tone))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dates(item))
                    .font(.app(.caption, weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dates(_ item: NoticedTimelineItem) -> String {
        Calendar.current.isDate(item.firstSeen, inSameDayAs: item.lastSeen)
            ? trendsDate(item.firstSeen)
            : "\(trendsDate(item.firstSeen)) – \(trendsDate(item.lastSeen))"
    }

    private func color(_ tone: MenoPlan.CycleSignal.Tone) -> Color {
        switch tone {
        case .attention: .linePink
        case .positive: .linePurple
        case .info: .lineBlue
        }
    }
}

// MARK: - Cycle signals

struct CycleSignalsTrendBody: View {
    let signals: [MenoPlan.CycleSignal]
    let coverage: [String]
    var limit = 5

    @State private var expandedID: String?

    var body: some View {
        VStack(spacing: 10) {
            if signals.isEmpty {
                TrendsCaption(text: "Nothing to flag right now. As you log tests, temperatures and symptoms, or connect Apple Health, anything worth knowing shows up here.")
            } else {
                ForEach(signals.prefix(limit)) { signal in
                    CycleSignalRow(signal: signal, isExpanded: expandedID == signal.id) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                            expandedID = expandedID == signal.id ? nil : signal.id
                        }
                    }
                }
            }
            if !coverage.isEmpty {
                Text("Based on " + coverage.joined(separator: " · "))
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
