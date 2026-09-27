import SwiftUI

/// Shared chrome for Home's cards, matching the reminder and scans panels.
private struct HomeCardBackground: ViewModifier {
    var tint: Color = .linePurple
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.white.opacity(0.96), tint.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint.opacity(0.13)))
    }
}

private struct HomeCardHeader: View {
    let title: String
    let symbol: String
    var tint: Color = .linePurple
    var trailing: String?
    var onTrailing: (() -> Void)?

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .symbolRenderingMode(.hierarchical)
                .tint(tint)
            Spacer()
            if let trailing, let onTrailing {
                Button(trailing, action: onTrailing)
                    .font(.app(.caption, weight: .bold))
            }
        }
    }
}

// MARK: - Cycle changes

/// Recent cycle lengths as bars, the pattern in one sentence, and - after a
/// long gap - progress towards 12 months without a period.
struct CycleChangeCard: View {
    let summary: CycleChangeSummary
    var onOpenCalendar: () -> Void
    var onSwitchStage: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeCardHeader(title: "How your cycle is changing", symbol: "chart.bar.fill", tint: .linePink, trailing: "Calendar", onTrailing: onOpenCalendar)

            if !summary.recentCycleLengths.isEmpty {
                cycleBars
            }

            Text(summary.headline)
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            if let progress = summary.twelveMonthProgress, let days = summary.daysSinceLastPeriod {
                twelveMonths(progress: progress, days: days)
            }
        }
        .modifier(HomeCardBackground(tint: .linePink))
        .onAppear { appeared = true }
    }

    private var cycleBars: some View {
        let lengths = summary.recentCycleLengths
        let tallest = CGFloat(max(lengths.max() ?? 1, 35))
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(lengths.enumerated()), id: \.offset) { index, length in
                let changed = index > 0 && abs(length - lengths[index - 1]) >= CycleChangeSummary.noticeableChangeDays
                VStack(spacing: 5) {
                    Text("\(length)")
                        .font(.app(.caption, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(changed ? Color.linePink : Color.lineNavy.opacity(0.7))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(changed ? AnyShapeStyle(Color.linePink.gradient) : AnyShapeStyle(Color.linePink.opacity(0.28)))
                        .frame(height: appeared ? max(12, 86 * CGFloat(length) / tallest) : 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(index) * 0.05), value: appeared)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(length) day cycle\(changed ? ", 7 or more days different from the one before" : "")")
            }
        }
        .frame(height: 112, alignment: .bottom)
        .overlay(alignment: .bottomLeading) {
            Text("Days per cycle, oldest first")
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.42))
                .offset(y: 18)
        }
        .padding(.bottom, 16)
    }

    private func twelveMonths(progress: Double, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(days) days since your last period")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                Spacer()
                Text(summary.reachedTwelveMonths ? "12 months" : "of 365")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.linePurple.opacity(0.12))
                    Capsule().fill(Color.linePurple.gradient)
                        .frame(width: proxy.size.width * (appeared ? progress : 0))
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: appeared)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            Text(summary.reachedTwelveMonths
                 ? "Menopause is usually described as 12 months without a period. If that fits you, you can switch MenoPlan to focus on symptoms."
                 : "Menopause is usually described as 12 months without a period.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if summary.reachedTwelveMonths {
                Button("Switch to “No period for 12+ months”", action: onSwitchStage)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.linePurple)
            }
        }
        .padding(12)
        .background(Color.linePurple.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Symptom week

/// The last seven days of the daily log at a glance.
struct SymptomWeekCard: View {
    let week: SymptomWeekSummary
    /// Home's hero already shows flushes and sweats when periods aren't tracked.
    var showsFlushesAndSweats = true
    var tracksHRT: Bool
    var onLog: () -> Void
    var onOpenTrends: () -> Void

    private var metrics: [(title: String, value: String, symbol: String, tint: Color)] {
        var items: [(String, String, String, Color)] = []
        func noun(_ count: Int, _ one: String, _ many: String) -> String { count == 1 ? one : many }
        if showsFlushesAndSweats {
            items.append((noun(week.hotFlushes, "Hot flush", "Hot flushes"), "\(week.hotFlushes)", "flame.fill", .orange))
            items.append((noun(week.nightSweats, "Night sweat", "Night sweats"), "\(week.nightSweats)", "moon.stars.fill", .linePurple))
        }
        items.append((noun(week.badSleepNights, "Broken night", "Broken nights"), "\(week.badSleepNights)", "bed.double.fill", .lineBlue))
        if tracksHRT { items.append(("HRT days", "\(week.hrtDays) of 7", "cross.vial.fill", .linePurple)) }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeCardHeader(title: "Your last 7 days", symbol: "waveform.path.ecg", trailing: "Trends", onTrailing: onOpenTrends)

            if week.isEmpty {
                Text("Nothing logged this week yet. A quick daily note of flushes, sleep and mood builds the picture you can share with your GP.")
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.lineNavy.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(metrics, id: \.symbol) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.system(size: LineType.size(14), weight: .bold))
                                .foregroundStyle(item.tint)
                                .frame(width: 32, height: 32)
                                .background(item.tint.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.value)
                                    .font(.app(size: LineType.size(18), weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.lineNavy)
                                    .contentTransition(.numericText())
                                Text(item.title)
                                    .font(.app(.caption2, weight: .semibold))
                                    .foregroundStyle(Color.lineNavy.opacity(0.52))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
                if !week.topSymptoms.isEmpty {
                    Text("Most logged: \(week.topSymptoms.joined(separator: ", "))")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                }
            }

            // Once there's a week to show, the quick actions above do this job.
            if week.isEmpty {
                Button(action: onLog) {
                    Label("Log today", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryLine)
            }
        }
        .modifier(HomeCardBackground())
        .animation(.snappy, value: week)
    }
}

// MARK: - Flushes & sweats hero

/// Home's hero when periods aren't tracked: hot flushes and night sweats over
/// the last 7 days, side by side and equal. A change chip appears only when
/// there's a week before to compare with.
struct VasomotorWeekHero: View {
    let week: SymptomWeekSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 10) {
            Text("Last 7 days")
                .font(.app(size: LineType.size(16), weight: .bold))
                .foregroundStyle(Color.lineNavy.opacity(0.78))
            HStack(alignment: .top, spacing: 0) {
                column(count: week.hotFlushes, previous: week.previousHotFlushes, one: "Hot flush", many: "Hot flushes", tint: .orange)
                Rectangle()
                    .fill(Color.lineNavy.opacity(0.08))
                    .frame(width: 1, height: LineType.size(84))
                    .padding(.top, 8)
                column(count: week.nightSweats, previous: week.previousNightSweats, one: "Night sweat", many: "Night sweats", tint: .linePurple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            // A full circle squashed flat, so the gradient fades out before
            // any edge instead of being clipped into a visible oval.
            Circle()
                .fill(RadialGradient(colors: [Color.orange.opacity(0.16), Color.linePurple.opacity(0.06), .clear], center: .center, startRadius: 10, endRadius: 170))
                .frame(width: 340, height: 340)
                .scaleEffect(x: breathe ? 1.05 : 0.95, y: breathe ? 0.68 : 0.62)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: breathe)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: week)
        .onAppear { if !reduceMotion { breathe = true } }
    }

    private func column(count: Int, previous: Int?, one: String, many: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.app(size: LineType.size(60), weight: .heavy))
                .foregroundStyle(Color.lineNavy)
                .contentTransition(.numericText(value: Double(count)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(count == 1 ? one : many)
                .font(.app(size: LineType.size(16), weight: .heavy))
                .foregroundStyle(tint)
            if let previous, previous != count {
                let down = count < previous
                Label("\(abs(count - previous)) vs last week", systemImage: down ? "arrow.down" : "arrow.up")
                    .font(.app(.caption2, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.lineNavy.opacity(0.05), in: Capsule())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - FSH test

/// The home FSH test, deliberately a supporting tile rather than Home's hero:
/// FSH swings a lot in perimenopause, so one reading is one data point.
struct FSHTestTile: View {
    var lastTested: Date?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: LineType.size(20), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.linePurple.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("FSH Test Check")
                        .font(.app(size: LineType.size(17), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text(lastTested.map { "Last test \(DateFormatting.shortDate.string(from: $0)) · one data point, not a diagnosis" } ?? "Read a home FSH test · one data point, not a diagnosis")
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.linePurple.opacity(0.6))
            }
            .modifier(HomeCardBackground())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityHint("Opens the camera to read a test")
    }
}
