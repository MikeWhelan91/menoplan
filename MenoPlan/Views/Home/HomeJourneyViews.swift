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
        case .waitingToTest, .periodDue, .periodLate: .linePink
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

