import SwiftUI

// MARK: - Week strip

/// The current week across the top of Home, tinted by cycle phase. Tapping a
/// past day or today opens that day's log, so logging never needs a trip into
/// Calendar.
struct HomeWeekStrip: View {
    let window: FertilityWindow?
    let cycleRecords: [CycleRecord]
    let periodEvents: [PeriodEvent]
    let loggedDays: Set<Date>
    var onSelect: (Date) -> Void

    @State private var appeared = false

    private var days: [Date] {
        // Today always sits in the middle, with three days either side.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayCell(day)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.035), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > calendar.startOfDay(for: .now)
        let style = HomePhaseStyle.forDay(day, window: window, cycleRecords: cycleRecords, periodEvents: periodEvents)

        return Button {
            guard !isFuture else { return }
            onSelect(day)
        } label: {
            VStack(spacing: 5) {
                Text(isToday ? "TODAY" : day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.app(size: LineType.size(9), weight: .heavy))
                    .foregroundStyle(isToday ? Color.lineNavy : Color.lineNavy.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(day.formatted(.dateTime.day()))
                    .font(.app(size: LineType.size(17), weight: isToday ? .heavy : .semibold))
                    .foregroundStyle(style.text.opacity(isFuture && style.text == Color.lineNavy ? 0.55 : 1))
                    .frame(width: LineType.size(38), height: LineType.size(38))
                    .background {
                        if isToday {
                            // White first so a translucent phase fill still
                            // reads as raised; solid fills keep white text legible.
                            ZStack {
                                Circle().fill(Color.white)
                                if let fill = style.fill { Circle().fill(fill) }
                            }
                            .shadow(color: Color.linePurple.opacity(0.18), radius: 8, y: 3)
                        } else if let fill = style.fill {
                            Circle().fill(fill)
                        }
                    }
                    .overlay {
                        if let ring = style.ring {
                            Circle().stroke(ring, style: StrokeStyle(lineWidth: 1.6, dash: style.dashed ? [3, 3] : []))
                        }
                        if style.estimateRing {
                            Circle()
                                .inset(by: 3)
                                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2.5]))
                        }
                        if isToday {
                            Circle().stroke(Color.lineNavy, lineWidth: 2).padding(-2)
                        }
                    }

                Circle()
                    .fill(Color.linePurple.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .opacity(loggedDays.contains(calendar.startOfDay(for: day)) ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityHint(isFuture ? "" : "Opens the daily log")
    }
}

/// Colours for a phase on Home, matching the Calendar's language: logged
/// period is solid pink, fertile days soft purple, ovulation solid purple,
/// luteal days soft teal, and predictions carry dashes.
struct HomePhaseStyle {
    var text: Color = .lineNavy
    var fill: Color?
    var ring: Color?
    var dashed = false
    /// Dashed white ring inside a solid fill - an estimated ovulation day.
    var estimateRing = false
    /// The colour that identifies the phase on a plain background.
    var accent: Color = .lineNavy

    init(_ phase: CycleCalendarPhase) {
        switch phase {
        case .period:
            text = .white; fill = .linePink; accent = .linePink
        case .predictedPeriod:
            text = .linePink; ring = Color.linePink.opacity(0.7); dashed = true; accent = .linePink
        case .fertile:
            text = HomePhaseStyle.fertile; fill = HomePhaseStyle.fertile.opacity(0.1); accent = HomePhaseStyle.fertile
        case .ovulation:
            text = .white; fill = .linePurple; estimateRing = true; accent = .linePurple
        case .confirmedOvulation:
            text = .white; fill = .linePurple; accent = .linePurple
        case .luteal:
            text = .lineLuteal; fill = Color.lineTeal.opacity(0.11); accent = .lineLuteal
        case .opkWindow:
            ring = .lineFertileSoft; dashed = true
        case .regular:
            break
        }
    }

    static let fertile = Color.linePurple

    static func forDay(_ day: Date, window: FertilityWindow?, cycleRecords: [CycleRecord], periodEvents: [PeriodEvent]) -> HomePhaseStyle {
        let phase: CycleCalendarPhase = window.map { window in
            if CycleTrackingService.periodEvent(containing: day, in: periodEvents) == nil,
               let projected = CycleCalendarPhaseResolver.projectedWindow(for: day, from: window) {
                return CycleCalendarPhaseResolver.projectedPhase(for: day, window: projected)
            }
            return CycleCalendarPhaseResolver.phase(for: day, window: window, cycleRecords: cycleRecords, periodEvents: periodEvents)
        } ?? .regular
        return HomePhaseStyle(phase)
    }
}

// MARK: - Countdown hero

struct HomeCountdownHero<Chart: View>: View {
    let countdown: HomeCountdown
    /// Today's colour in the week strip, so the number reads as the same day.
    var numberColor: Color = .lineNavy
    var uncertaintyNote: String?
    var onWhy: () -> Void
    @ViewBuilder var chart: () -> Chart

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var tint: Color {
        switch countdown.stage {
        case .beforeOvulationTesting: .linePurple
        case .ovulationTesting, .fertile, .ovulationDay: HomePhaseStyle.fertile
        case .waitingToTest, .earlyTesting, .periodDue, .periodLate: .linePink
        }
    }

    /// The glow sits behind the number, so it takes the number's colour
    /// (today's phase: pink on a period day). A plain navy day falls back
    /// to the countdown's own tint.
    private var glowTint: Color { numberColor == .lineNavy ? tint : numberColor }

    var body: some View {
        // Top-aligned and offset so the glow centres on the number rather
        // than the whole hero, which would push it down onto the graph.
        ZStack(alignment: .top) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowTint.opacity(0.22), glowTint.opacity(0.06), .clear],
                        center: .center, startRadius: 10, endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .scaleEffect(breathe ? 1.06 : 0.94)
                .opacity(breathe ? 1 : 0.8)
                // Scoped to the glow alone. Started with withAnimation from
                // the whole card, the repeat-forever transaction also caught
                // the number's first layout, sliding it left and right forever.
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: breathe)
                .offset(y: LineType.size(62) - 140)
                .allowsHitTesting(false)

            VStack(spacing: 6) {
                Text(countdown.caption)
                    .font(.app(size: LineType.size(16), weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                Group {
                    if let value = countdown.value, let unit = countdown.unit {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(value)")
                                .font(.app(size: LineType.size(64), weight: .heavy))
                                .contentTransition(.numericText(value: Double(value)))
                            Text(unit)
                                .font(.app(size: LineType.size(30), weight: .heavy))
                        }
                    } else {
                        Text(countdown.headline)
                            .font(.app(size: LineType.size(58), weight: .heavy))
                            .contentTransition(.interpolate)
                    }
                }
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                Text(countdown.footnote)
                    .font(.app(size: LineType.size(14), weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)

                chart()
                    .padding(.horizontal, -12)
                    .padding(.top, 4)

                if let uncertaintyNote {
                    Label(uncertaintyNote, systemImage: "info.circle")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.1), in: Capsule())
                        .padding(.top, 2)
                }

                Button(action: onWhy) {
                    Text("How is this worked out?")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineBlue)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 250)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: countdown)
        .onAppear {
            guard !reduceMotion else { return }
            breathe = true
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Quick actions

struct HomeQuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    var filled = false
    let action: () -> Void
}

struct HomeQuickActionsRow: View {
    let actions: [HomeQuickAction]
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    VStack(spacing: 7) {
                        Image(systemName: item.symbol)
                            .font(.system(size: LineType.size(21), weight: .semibold))
                            .foregroundStyle(item.filled ? Color.white : item.tint)
                            .frame(width: LineType.size(56), height: LineType.size(56))
                            .background {
                                Circle()
                                    .fill(item.filled ? AnyShapeStyle(item.tint.gradient) : AnyShapeStyle(Color.white))
                                    .shadow(color: item.tint.opacity(0.18), radius: 8, y: 4)
                            }
                        Text(item.title)
                            .font(.app(size: LineType.size(13), weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.68).delay(0.12 + Double(index) * 0.05), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

/// A springy press used by the new tappable surfaces on Home.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Nudge cards

/// A soft card used for the one-off prompts on Home (personalise, doctor
/// suggestion, confirm pregnancy). Consistent chrome so each reads as a
/// gentle suggestion rather than an alert.
struct HomeNudgeCard<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var onDismiss: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: LineType.size(16), weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.app(size: LineType.size(16), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text(message)
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(Color.lineNavy.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(Color.lineNavy.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.97), tint.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint.opacity(0.18)))
    }
}

// MARK: - Pregnancy mode

/// The pregnancy counterpart of the day strip: weeks, with the current one
/// in the middle.
struct PregnancyWeekStrip: View {
    let currentWeek: Int
    @State private var appeared = false

    private var weeks: [Int] { (currentWeek - 3...currentWeek + 3).map { $0 } }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weeks.enumerated()), id: \.element) { index, week in
                let isCurrent = week == currentWeek
                let valid = (1...42).contains(week)
                VStack(spacing: 5) {
                    Text(isCurrent ? "THIS WEEK" : "WEEK")
                        .font(.app(size: LineType.size(9), weight: .heavy))
                        .foregroundStyle(isCurrent ? Color.lineNavy : Color.lineNavy.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(valid ? "\(week)" : "")
                        .font(.app(size: LineType.size(17), weight: isCurrent ? .heavy : .semibold))
                        .foregroundStyle(isCurrent ? Color.white : (week < currentWeek ? Color.linePink : Color.lineNavy.opacity(0.5)))
                        .frame(width: LineType.size(38), height: LineType.size(38))
                        .background {
                            if isCurrent {
                                Circle().fill(Color.linePink.gradient)
                            } else if week < currentWeek && valid {
                                Circle().fill(Color.linePink.opacity(0.12))
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .opacity(valid ? (appeared ? 1 : 0) : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.035), value: appeared)
            }
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week \(currentWeek) of pregnancy")
    }
}

struct PregnancyHomeHero: View {
    let progress: PregnancyProgress
    var onDetails: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0
    @State private var float = false
    private var floatAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true) }

    /// Drop week illustrations into the asset catalogue as PregnancyWeek4…
    /// PregnancyWeek40 and they're picked up here automatically.
    private var weekImage: UIImage? {
        UIImage(named: "PregnancyWeek\(min(max(progress.weeks, 4), 40))")
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.linePink.opacity(0.18), Color.linePinkSoft.opacity(0.3), .clear], center: .center, startRadius: 8, endRadius: 150))
                    .frame(width: 270, height: 270)
                    .scaleEffect(float ? 1.04 : 0.97)
                    .animation(floatAnimation, value: float)

                Circle()
                    .stroke(Color.linePink.opacity(0.12), lineWidth: 10)
                    .frame(width: 220, height: 220)
                Circle()
                    .trim(from: 0, to: drawn)
                    .stroke(Color.linePink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)

                if let weekImage {
                    Image(uiImage: weekImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .offset(y: float ? -3 : 3)
                        .animation(floatAnimation, value: float)
                } else {
                    VStack(spacing: 0) {
                        Text("\(progress.weeks)")
                            .font(.app(size: LineType.size(62), weight: .heavy))
                            .contentTransition(.numericText(value: Double(progress.weeks)))
                            .foregroundStyle(Color.lineNavy)
                        Text(progress.weeks == 1 ? "week" : "weeks")
                            .font(.app(size: LineType.size(16), weight: .bold))
                            .foregroundStyle(Color.lineNavy.opacity(0.62))
                            .offset(y: -6)
                    }
                    .offset(y: float ? -2 : 2)
                    .animation(floatAnimation, value: float)
                }
            }
            .frame(height: 270)

            VStack(spacing: 6) {
                Text(progress.ageLabel)
                    .font(.app(size: LineType.size(24), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                if let size = progress.sizeComparison {
                    Text("About the size of \(size)")
                        .font(.app(size: LineType.size(15), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.65))
                }
                Text("Due \(progress.dueDate.formatted(.dateTime.day().month(.wide).year()))")
                    .font(.app(size: LineType.size(14), weight: .bold))
                    .foregroundStyle(Color.linePink)
            }
            .multilineTextAlignment(.center)

            Button(action: onDetails) {
                Text("Your pregnancy")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.linePink)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Color.linePink.opacity(0.18), radius: 8, y: 3)
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 1.2).delay(0.15)) { drawn = max(0.02, progress.fractionComplete) }
            guard !reduceMotion else { return }
            // Animated per view (floatAnimation) rather than with
            // withAnimation here, which would also make the labels below
            // drift forever with the repeating transaction.
            float = true
        }
        .onChange(of: progress.fractionComplete) { _, new in
            withAnimation(.easeOut(duration: 0.6)) { drawn = max(0.02, new) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.ageLabel) pregnant. Estimated due date \(progress.dueDate.formatted(date: .long, time: .omitted)).")
    }
}

/// A single scrolling page rather than a stack of cards: the headline
/// numbers, a trimester bar, then the milestones as a plain timeline.
struct PregnancyDetailSheet: View {
    let progress: PregnancyProgress
    let completedMilestones: Set<String>
    var onPregnancyEnded: () -> Void
    var onNotPregnant: () -> Void
    var onSetDueDate: (Date) -> Void
    var onResetDueDate: () -> Void
    var onToggleMilestone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnded = false
    @State private var revealed = false
    @State private var barFill: Double = 0
    @State private var editingDueDate = false
    @State private var dueDateDraft = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.ageLabel)
                            .font(.app(size: LineType.size(34), weight: .heavy))
                            .foregroundStyle(Color.lineNavy)
                        HStack(spacing: 8) {
                            Text("Due \(progress.dueDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))")
                                .font(.app(size: LineType.size(17), weight: .bold))
                                .foregroundStyle(Color.linePink)
                            Button {
                                dueDateDraft = progress.dueDate
                                editingDueDate = true
                            } label: {
                                Text(progress.isManualDueDate ? "Edit" : "Adjust")
                                    .font(.app(size: LineType.size(13), weight: .bold))
                                    .foregroundStyle(Color.lineNavy.opacity(0.5))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.lineNavy.opacity(0.08)))
                            }
                        }
                        if progress.isManualDueDate {
                            Button("Reset to date worked out from cycle") { onResetDueDate() }
                                .font(.app(size: LineType.size(13), weight: .semibold))
                                .foregroundStyle(Color.lineNavy.opacity(0.4))
                        }
                    }

                    trimesterBar

                    HStack(spacing: 0) {
                        stat("\(progress.trimester)", progress.trimester == 1 ? "st trimester" : progress.trimester == 2 ? "nd trimester" : "rd trimester", prefixOnly: true)
                        divider
                        stat("\(progress.daysToGo)", "days to go")
                        divider
                        stat("\(Int((progress.fractionComplete * 100).rounded()))%", "of the way")
                    }

                    Text("Your due date is worked out from your cycle dates. Your midwife or doctor may adjust it after a dating scan.")
                        .font(.app(size: LineType.size(14), weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Milestones")
                            .font(.app(size: LineType.size(20), weight: .heavy))
                            .foregroundStyle(Color.lineNavy)
                            .padding(.bottom, 16)
                        let items = CycleJourneyCalculator.milestones(for: progress)
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            let done = completedMilestones.contains(item.title)
                            Button {
                                onToggleMilestone(item.title)
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    VStack(spacing: 0) {
                                        ZStack {
                                            Circle()
                                                .fill(done ? Color.linePink : Color.clear)
                                                .overlay(Circle().stroke(done ? Color.linePink : Color.lineNavy.opacity(0.3), lineWidth: 2))
                                            if done {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 20, height: 20)
                                        .padding(.top, 2)
                                        if index < items.count - 1 {
                                            Rectangle()
                                                .fill(done ? Color.linePink.opacity(0.4) : Color.lineNavy.opacity(0.1))
                                                .frame(width: 2)
                                                .frame(maxHeight: .infinity)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.app(size: LineType.size(16), weight: .bold))
                                            .foregroundStyle(Color.lineNavy.opacity(done ? 1 : 0.75))
                                            .strikethrough(done, pattern: .solid, color: Color.lineNavy.opacity(0.4))
                                        Text(item.detail)
                                            .font(.app(size: LineType.size(14), weight: .medium))
                                            .foregroundStyle(Color.lineNavy.opacity(0.55))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.bottom, 20)
                                }
                            }
                            .buttonStyle(.plain)
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 12)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.1 + Double(index) * 0.05), value: revealed)
                        }
                    }

                    VStack(spacing: 14) {
                        Button("I’m not pregnant — go back to cycle tracking") { dismiss(); onNotPregnant() }
                        Button("This pregnancy has ended") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { confirmEnded = true }
                        }
                    }
                    .font(.app(size: LineType.size(15), weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
                    .frame(maxWidth: .infinity)

                    Text("General information based on your dates, not medical advice.")
                        .font(.app(.caption2))
                        .foregroundStyle(Color.lineNavy.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background { LineCheckBrandBackdrop() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                revealed = true
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) { barFill = progress.fractionComplete }
            }
            .sheet(isPresented: $editingDueDate) {
                NavigationStack {
                    DatePicker("Due date", selection: $dueDateDraft, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 24)
                        .navigationTitle("Edit due date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingDueDate = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    onSetDueDate(dueDateDraft)
                                    editingDueDate = false
                                }
                            }
                        }
                        .presentationDetents([.medium])
                }
            }
        }
        .tint(Color.lineBlue)
        .overlay {
            if confirmEnded {
                ConfirmDialog(
                    title: "Mark this pregnancy as ended?",
                    message: "We’re so sorry if this is a difficult time. Your saved tests and history stay as they are, and pregnancy updates will stop.",
                    confirmTitle: "Yes, it has ended",
                    onConfirm: { dismiss(); onPregnancyEnded() },
                    onCancel: { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { confirmEnded = false } }
                )
                .transition(.opacity)
            }
        }
    }

    private var trimesterBar: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.lineNavy.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.linePurple, .linePink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, proxy.size.width * barFill))
                    ForEach([14.0 / 40, 28.0 / 40], id: \.self) { mark in
                        Rectangle().fill(Color.white).frame(width: 2).offset(x: proxy.size.width * mark)
                    }
                }
            }
            .frame(height: 10)
            HStack {
                Text("1st").frame(maxWidth: .infinity, alignment: .leading)
                Text("2nd").frame(maxWidth: .infinity)
                Text("3rd").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.app(size: LineType.size(12), weight: .bold))
            .foregroundStyle(Color.lineNavy.opacity(0.45))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.lineNavy.opacity(0.1)).frame(width: 1, height: 40)
    }

    private func stat(_ value: String, _ label: String, prefixOnly: Bool = false) -> some View {
        VStack(spacing: 2) {
            if prefixOnly {
                (Text(value) + Text(label.prefix(2)).font(.app(size: LineType.size(14), weight: .heavy)))
                    .font(.app(size: LineType.size(26), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                Text("trimester")
            } else {
                Text(value)
                    .font(.app(size: LineType.size(26), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                Text(label)
            }
        }
        .font(.app(size: LineType.size(13), weight: .semibold))
        .foregroundStyle(Color.lineNavy.opacity(0.5))
        .frame(maxWidth: .infinity)
    }
}

/// A centred modal that dims everything behind it - used for confirmations
/// that deserve more weight than an action sheet.
struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Text(title)
                    .font(.app(size: LineType.size(21), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.app(size: LineType.size(15), weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(.primaryLine)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.secondaryLine)
                }
                .padding(.top, 6)
            }
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
            .padding(.horizontal, 28)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { shown = true }
        }
    }
}

/// Full-screen moment shown once when someone switches into pregnancy mode.
struct PregnancyRevealView: View {
    let progress: PregnancyProgress
    let name: String
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var displayedDays = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.linePinkSoft, Color.white, Color.linePurpleSoft.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ConfettiBurst(isActive: stage >= 2)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    ForEach(0..<3) { ring in
                        Circle()
                            .stroke(Color.linePink.opacity(0.18 - Double(ring) * 0.05), lineWidth: 2)
                            .frame(width: 150 + CGFloat(ring) * 46, height: 150 + CGFloat(ring) * 46)
                            .scaleEffect(stage >= 1 ? 1 : 0.4)
                            .opacity(stage >= 1 ? 1 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(Double(ring) * 0.08), value: stage)
                    }
                    Image(systemName: "heart.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.linePink, .linePurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .scaleEffect(stage >= 1 ? 1 : 0.2)
                        .symbolEffect(.pulse, options: .repeating, isActive: stage >= 2 && !reduceMotion)
                        .animation(.spring(response: 0.55, dampingFraction: 0.55), value: stage)
                }
                .frame(height: 260)

                VStack(spacing: 10) {
                    Text(name.isEmpty ? "Congratulations" : "Congratulations, \(name)")
                        .font(.app(size: LineType.size(17), weight: .bold))
                        .foregroundStyle(Color.linePink)
                    (Text("Based on your cycle data, you’re ") + Text("\(displayedDays / 7) weeks \(displayedDays % 7) days").foregroundStyle(Color.linePink) + Text(" pregnant"))
                        .font(.app(size: LineType.size(28), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                    Text("We count from the first day of your last period, which is how pregnancies are usually dated.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .opacity(stage >= 1 ? 1 : 0)
                .offset(y: stage >= 1 ? 0 : 24)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: stage)

                Spacer()

                Button("Continue", action: onContinue)
                    .buttonStyle(.primaryLine)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .opacity(stage >= 2 ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: stage)
            }
        }
        .task {
            stage = 1
            let target = progress.gestationalDays
            if reduceMotion {
                displayedDays = target
            } else {
                let steps = 18
                for step in 1...steps {
                    try? await Task.sleep(for: .milliseconds(40))
                    withAnimation(.snappy) { displayedDays = target * step / steps }
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
            stage = 2
        }
    }
}

/// Lightweight confetti - a handful of shapes falling with slight drift. No
/// assets, and nothing runs until `isActive` flips.
struct ConfettiBurst: View {
    var isActive: Bool
    @State private var start: Date?

    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, drift: Double, size: Double
        let color: Color
    }

    private let pieces: [Piece] = (0..<46).map { index in
        var generator = SeededGenerator(seed: UInt64(index + 7))
        let colors: [Color] = [.linePink, .linePurple, .lineTeal, .orange, .yellow]
        return Piece(
            x: Double.random(in: 0...1, using: &generator),
            delay: Double.random(in: 0...0.8, using: &generator),
            speed: Double.random(in: 0.22...0.42, using: &generator),
            spin: Double.random(in: -360...360, using: &generator),
            drift: Double.random(in: -40...40, using: &generator),
            size: Double.random(in: 6...11, using: &generator),
            color: colors[index % colors.count]
        )
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Canvas { graphics, size in
                guard let start else { return }
                let elapsed = context.date.timeIntervalSince(start)
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -20 + t * piece.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + sin(t * 2.4) * piece.drift
                    var context = graphics
                    context.translateBy(x: x, y: y)
                    context.rotate(by: .degrees(piece.spin * t))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color.opacity(0.9)))
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active { start = .now }
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
