import SwiftUI

/// Shared chrome for Home's cards, matching the reminder panel.
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
                    .foregroundStyle(Color.linePurple)
            }
        }
    }
}

// MARK: - Check-in

/// Home's hero: how much symptoms affected today, then the person's own
/// pinned symptoms, each one tap to rate. Nothing is required and there's
/// no streak - a single tap is a useful entry.
struct CheckInCard: View {
    let log: DailyFertilityLog?
    let focus: [String]
    var onImpact: (DayImpact?) -> Void
    var onAdvance: (String) -> Void
    var onSetSeverity: (String, SymptomSeverity?) -> Void
    var onCount: (String, Int) -> Void
    var onOpenLog: () -> Void
    var onEditFocus: () -> Void

    private var isLogged: Bool { log?.hasContent ?? false }
    private var hasRatedAnything: Bool {
        guard let log else { return false }
        return focus.contains { FocusSymptoms.state(of: $0, in: log) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How's today?")
                        .font(.app(size: LineType.size(24), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text(isLogged ? "Logged · tap anything to change it" : "A tap or two is enough")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(isLogged ? Color.linePurple : Color.lineNavy.opacity(0.5))
                        .contentTransition(.opacity)
                }
                Spacer()
                if isLogged {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: LineType.size(22)))
                        .foregroundStyle(Color.white, Color.linePurple)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How much did symptoms affect your day?")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.75))
                HStack(spacing: 8) {
                    ForEach(DayImpact.allCases) { impact in
                        impactButton(impact)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your symptoms")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.75))
                    Spacer()
                    Button("Change", action: onEditFocus)
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(Color.linePurple)
                }
                VStack(spacing: 8) {
                    ForEach(focus, id: \.self) { name in
                        symptomRow(name)
                    }
                }
                if !hasRatedAnything {
                    Text("Tap a symptom to rate it mild, moderate or severe. Leave the rest.")
                        .font(.app(.caption2))
                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                }
            }

            Button(action: onOpenLog) {
                HStack {
                    Label("Add a note, bleeding or more", systemImage: "square.and.pencil")
                    Spacer()
                    Image(systemName: "chevron.right").font(.app(.caption, weight: .bold))
                }
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Color.linePurple)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.linePurple.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.98), Color.linePurple.opacity(0.08), Color.linePink.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.linePurple.opacity(0.16)))
        .shadow(color: Color.linePurple.opacity(0.08), radius: 16, y: 8)
        .animation(.snappy, value: log?.updatedAt)
    }

    private func impactTint(_ impact: DayImpact) -> Color {
        switch impact {
        case .notAtAll: .orange
        case .some: .linePurple
        case .lots: .lineBlue
        }
    }

    private func impactButton(_ impact: DayImpact) -> some View {
        let selected = log?.dayImpact == impact
        return Button {
            onImpact(selected ? nil : impact)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: impact.symbol)
                    .font(.system(size: LineType.size(18), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? Color.white : impactTint(impact))
                Text(impact.title)
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(selected ? Color.white : Color.lineNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(selected ? AnyShapeStyle(Color.linePurple.gradient) : AnyShapeStyle(Color.white.opacity(0.9)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Color.clear : Color.lineNavy.opacity(0.06)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel("Symptoms affected my day: \(impact.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowLabel(_ name: String, active: Bool, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: FocusSymptoms.symbol(for: name))
                .font(.system(size: LineType.size(14), weight: .bold))
                .foregroundStyle(active ? Color.white : tint)
                .frame(width: 34, height: 34)
                .background(active ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.12)), in: Circle())
            Text(name)
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
        }
    }

    @ViewBuilder
    private func symptomRow(_ name: String) -> some View {
        let state = FocusSymptoms.state(of: name, in: log)
        let active = log.map { FocusSymptoms.isPresent(name, in: $0) } ?? false
        let kind = FocusSymptoms.kind(of: name)
        let tint: Color = kind == .counter ? .orange : .linePurple

        if kind == .counter {
            HStack(spacing: 10) {
                rowLabel(name, active: active, tint: tint)
                counterButton("minus", enabled: (Int(state ?? "") ?? 0) > 0, tint: tint) { onCount(name, -1) }
                    .accessibilityLabel("One fewer \(name.lowercased())")
                Text(state ?? "0")
                    .font(.app(.title3, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.lineNavy)
                    .frame(minWidth: 26)
                    .contentTransition(.numericText())
                counterButton("plus", enabled: true, tint: tint) { onCount(name, 1) }
                    .accessibilityLabel("One more \(name.lowercased())")
            }
            .rowChrome(active: active, tint: tint)
        } else {
            Button { onAdvance(name) } label: {
                HStack(spacing: 10) {
                    rowLabel(name, active: active, tint: tint)
                    if let state {
                        Text(state)
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(tint)
                            .contentTransition(.opacity)
                    }
                    levelDots(for: name)
                }
                .rowChrome(active: active, tint: tint)
            }
            .buttonStyle(PressScaleButtonStyle())
            .sensoryFeedback(.selection, trigger: state)
            .contextMenu {
                if kind == .severity {
                    ForEach(SymptomSeverity.allCases) { level in
                        Button(level.title) { onSetSeverity(name, level) }
                    }
                    Button("Clear", role: .destructive) { onSetSeverity(name, nil) }
                }
            }
            .accessibilityLabel(name)
            .accessibilityValue(state ?? "Not logged")
            .accessibilityHint("Tap to change the rating")
        }
    }

    private func level(for name: String) -> Int {
        guard let log else { return 0 }
        switch FocusSymptoms.kind(of: name) {
        case .sleep:
            switch log.sleepQuality {
            case .good: return 1
            case .broken: return 2
            case .poor: return 3
            case nil: return 0
            }
        case .severity: return log.symptoms.contains(name) ? (log.severity(of: name)?.level ?? 1) : 0
        case .counter: return 0
        }
    }

    private func levelDots(for name: String) -> some View {
        let filled = level(for: name)
        return HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step <= filled ? Color.linePurple : Color.lineNavy.opacity(0.1))
                    .frame(width: 6, height: 14)
            }
        }
        .accessibilityHidden(true)
    }

    private func counterButton(_ symbol: String, enabled: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

private extension View {
    func rowChrome(active: Bool, tint: Color) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(active ? tint.opacity(0.08) : Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? tint.opacity(0.35) : Color.lineNavy.opacity(0.05)))
    }
}

// MARK: - Recent change

struct RecentChangeCard: View {
    let change: RecentChange
    var onOpenTrends: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeCardHeader(title: "Recent changes", symbol: "chart.line.uptrend.xyaxis", trailing: "Trends", onTrailing: onOpenTrends)
            Text(change.title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lineNavy)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = change.detail {
                Text(detail)
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.lineNavy.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("An observation from your log, not a cause.")
                .font(.app(.caption2))
                .foregroundStyle(Color.lineNavy.opacity(0.45))
        }
        .modifier(HomeCardBackground())
    }
}

// MARK: - Appointment

struct AppointmentCard: View {
    let appointment: Date?
    let loggedDays: Int
    var onPrepare: () -> Void
    var onSetDate: () -> Void

    private var daysAway: Int? {
        guard let appointment else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: appointment)).day
    }

    private var subtitle: String {
        guard let appointment, let daysAway else {
            return "A one-page summary of what's affecting you most, to take to your GP or clinician."
        }
        let when = daysAway == 0 ? "today" : daysAway == 1 ? "tomorrow" : "in \(daysAway) days"
        return "Your appointment is \(when), \(appointment.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeCardHeader(title: "Prepare for your appointment", symbol: "stethoscope", tint: .linePink, trailing: appointment == nil ? "Add date" : "Change", onTrailing: onSetDate)
            Text(subtitle)
                .font(.app(.subheadline))
                .foregroundStyle(Color.lineNavy.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(Color.linePink)
                Text(loggedDays == 1 ? "1 day logged in the last 30" : "\(loggedDays) days logged in the last 30")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.65))
            }
            Button(action: onPrepare) {
                Label("Open your summary", systemImage: "doc.text.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryLine)
        }
        .modifier(HomeCardBackground(tint: .linePink))
    }
}

/// Picks (or clears) the next appointment date.
struct AppointmentDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    var onSave: (Date?) -> Void

    init(initial: Date?, onSave: @escaping (Date?) -> Void) {
        _date = State(initialValue: initial ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            DatePicker("Appointment", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Color.linePurple)
                .padding()
                .navigationTitle("Next appointment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Remove") { onSave(nil); dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(date); dismiss() }.fontWeight(.bold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - HRT

/// Only shown to people who've set their HRT up in Settings.
struct HRTTodayCard: View {
    let regimen: [String]
    let taken: [String]
    let doseText: String?
    let lastChanged: Date?
    let reminderTime: Date?
    var onToggle: (String) -> Void
    var onReminder: (Date?) -> Void
    var onEdit: () -> Void

    private var defaultReminderTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeCardHeader(title: "Today's HRT", symbol: "cross.vial.fill", trailing: "Edit", onTrailing: onEdit)
            FlowLayout(spacing: 8) {
                ForEach(regimen, id: \.self) { item in
                    itemButton(item, done: taken.contains(item))
                }
            }
            if let doseText, !doseText.isEmpty {
                Text(doseText)
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.6))
            }
            if let lastChanged {
                Text("Last changed \(lastChanged.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
            }
            Divider()
            Toggle(isOn: Binding(
                get: { reminderTime != nil },
                set: { on in onReminder(on ? (reminderTime ?? defaultReminderTime) : nil) }
            )) {
                Text("Daily reminder")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy)
            }
            .tint(Color.linePurple)
            if let reminderTime {
                DatePicker("Time", selection: Binding(get: { reminderTime }, set: { onReminder($0) }), displayedComponents: .hourAndMinute)
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.lineNavy.opacity(0.7))
                    .tint(Color.linePurple)
            }
        }
        .modifier(HomeCardBackground())
    }

    private func itemButton(_ item: String, done: Bool) -> some View {
        Button { onToggle(item) } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                Text(item)
                    .font(.app(.subheadline, weight: .semibold))
            }
            .foregroundStyle(done ? Color.linePurple : Color.lineNavy.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(done ? Color.linePurple.opacity(0.14) : Color.white.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(done ? Color.linePurple.opacity(0.6) : Color.lineNavy.opacity(0.06)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.success, trigger: done)
        .accessibilityLabel("\(item), \(done ? "taken" : "not taken")")
    }
}

// MARK: - Cycle

/// While periods continue: when the last one was, recent cycle lengths as
/// bars, and the pattern in one sentence. No predicted dates - late in
/// perimenopause they're mostly noise.
struct CycleChangeCard: View {
    let summary: CycleChangeSummary
    var onLogPeriod: () -> Void
    var onOpenCalendar: () -> Void
    var onSwitchStage: () -> Void

    @State private var appeared = false

    private var lastPeriodTitle: String {
        guard let days = summary.daysSinceLastPeriod else { return "No periods logged yet" }
        return days == 0 ? "Period started today" : "Last period \(days) \(days == 1 ? "day" : "days") ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeCardHeader(title: "Your cycle", symbol: "drop.circle.fill", tint: .linePink, trailing: "Calendar", onTrailing: onOpenCalendar)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastPeriodTitle)
                        .font(.app(size: LineType.size(18), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    if let start = summary.lastPeriodStart {
                        Text("Started \(start.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(Color.lineNavy.opacity(0.5))
                    }
                }
                Spacer()
                Button(action: onLogPeriod) {
                    Label("Log period", systemImage: "drop.fill")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.linePink.gradient, in: Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
            }

            if summary.recentCycleLengths.count >= 2 {
                cycleBars
            }

            Text(summary.headline)
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.75))
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(lengths.enumerated()), id: \.offset) { index, length in
                    cycleBar(length: length, changed: index > 0 && abs(length - lengths[index - 1]) >= CycleChangeSummary.noticeableChangeDays, tallest: tallest, index: index)
                }
            }
            .frame(height: 94, alignment: .bottom)
            Text("Days per cycle, oldest first")
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.42))
        }
    }

    private func cycleBar(length: Int, changed: Bool, tallest: CGFloat, index: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(length)")
                .font(.app(.caption, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(changed ? Color.linePink : Color.lineNavy.opacity(0.7))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(changed ? AnyShapeStyle(Color.linePink.gradient) : AnyShapeStyle(Color.linePink.opacity(0.28)))
                .frame(height: appeared ? max(12, 70 * CGFloat(length) / tallest) : 6)
                .animation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(index) * 0.05), value: appeared)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(length) day cycle\(changed ? ", 7 or more days different from the one before" : "")")
    }

    private func twelveMonths(progress: Double, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                 : "\(days) of 365 days. Menopause is usually described as 12 months without a period.")
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
