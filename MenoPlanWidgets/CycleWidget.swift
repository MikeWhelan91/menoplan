import SwiftUI
import WidgetKit

// MARK: - Free widget: cycle countdown + month calendar

struct CycleEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var summary: WidgetCycleSummary { WidgetCycleSummary.make(for: snapshot, on: date) }
}

struct CycleProvider: TimelineProvider {
    func placeholder(in context: Context) -> CycleEntry {
        CycleEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CycleEntry) -> Void) {
        let stored = WidgetSnapshotStore.load()
        // The gallery should show what the widget does, not a "Set up" card.
        let snapshot = context.isPreview && (stored?.cycleState ?? .notSetUp) == .notSetUp ? .preview : (stored ?? .empty)
        completion(CycleEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CycleEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .empty
        let entries = WidgetTimeline.dates(from: .now).map { CycleEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct CycleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.cycleWidgetKind, provider: CycleProvider()) { entry in
            CycleWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
        }
        .configurationDisplayName("Cycle Countdown")
        .description("Days until your next period, and your cycle at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CycleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CycleEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text(entry.summary.inline)
        case .systemMedium:
            HStack(spacing: 14) {
                countdown
                MonthGrid(snapshot: entry.snapshot, date: entry.date)
                    .frame(maxWidth: .infinity)
            }
            .widgetURL(link.url)
        default:
            countdown
                .widgetURL(link.url)
        }
    }

    private var link: WidgetDeepLink {
        entry.snapshot.cycleState == .notSetUp ? .setupCycle : .calendar
    }

    @ViewBuilder
    private var countdown: some View {
        if entry.snapshot.cycleState == .tracking {
            trackingCountdown
        } else {
            idleState
        }
    }

    private var idleState: some View {
        WidgetIdleView(state: entry.snapshot.cycleState, compact: family == .systemSmall)
    }

    private var trackingCountdown: some View {
        let summary = entry.summary
        return VStack(spacing: 0) {
            HStack(spacing: 5) {
                WidgetBrandMark(size: 16)
                if let day = summary.cycleDay {
                    Text("Cycle day \(day)")
                        .font(.widget(.caption2, weight: .bold))
                        .foregroundStyle(Color.wNavy.opacity(0.6))
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, summary.cycleDay == nil ? 4 : 9)
            .padding(.vertical, 4)
            .background(Color.wSurface, in: Capsule())
            Spacer(minLength: 4)
            Text(summary.label)
                .font(.widget(.caption, weight: .heavy))
                .foregroundStyle(Color.wNavy.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.6)
            Text(summary.headline)
                .font(.widget(size: 30, weight: .heavy))
                .foregroundStyle(summary.tone.color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 4)
            Text(summary.detail)
                .font(.widget(.caption, weight: .medium))
                .foregroundStyle(Color.wNavy.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var circular: some View {
        let summary = entry.summary
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(circularValue(summary))
                    .font(.widget(size: 20, weight: .bold))
                    .minimumScaleFactor(0.6)
                Text(circularCaption(summary))
                    .font(.widget(size: 9, weight: .semibold))
                    .textCase(.uppercase)
            }
            .widgetAccentable()
        }
    }

    private func circularValue(_ summary: WidgetCycleSummary) -> String {
        if let day = summary.cycleDay { return "\(day)" }
        return "–"
    }

    private func circularCaption(_ summary: WidgetCycleSummary) -> String {
        summary.cycleDay == nil ? "Cycle" : "Day"
    }

    private var rectangular: some View {
        let summary = entry.summary
        return VStack(alignment: .leading, spacing: 1) {
            Text(summary.label)
                .font(.widget(.caption, weight: .semibold))
                .widgetAccentable()
            Text(summary.headline)
                .font(.widget(.headline, weight: .bold))
            Text(summary.detail)
                .font(.widget(.caption2))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Month grid: pink numbers for period days, a dashed ring for an estimated
/// period and a filled navy dot for today.
struct MonthGrid: View {
    let snapshot: WidgetSnapshot
    let date: Date
    var compact = false
    private let calendar = Calendar.current

    var body: some View {
        let cells = cells
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        VStack(spacing: compact ? 2 : 3) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.widget(size: 10, weight: .bold))
                        .foregroundStyle(Color.wNavy.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        dayCell(index < row.count ? row[index] : nil)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let phase = snapshot.phase(on: day, calendar: calendar)
            let isToday = calendar.isDate(day, inSameDayAs: date)
            Text("\(calendar.component(.day, from: day))")
                .font(.widget(size: 11, weight: isToday || phase != nil ? .bold : .medium))
                .foregroundStyle(foreground(phase: phase, isToday: isToday))
                .frame(width: 17, height: 17)
                .background {
                    if isToday {
                        Circle().fill(Color.wNavy)
                    } else if phase == .predictedPeriod {
                        Circle().strokeBorder(Color.wPink.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
        } else {
            Color.clear.frame(width: 17, height: 17)
        }
    }

    private func foreground(phase: WidgetSnapshot.DayPhase?, isToday: Bool) -> Color {
        if isToday { return .wOnInk }
        return phase?.color ?? Color.wNavy.opacity(0.85)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var cells: [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: date)?.start,
              let days = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + days.map { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }
}

#Preview(as: .systemMedium) {
    CycleWidget()
} timeline: {
    CycleEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemSmall) {
    CycleWidget()
} timeline: {
    CycleEntry(date: .now, snapshot: .preview)
}
