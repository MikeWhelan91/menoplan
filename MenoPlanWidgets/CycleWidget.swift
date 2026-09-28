import SwiftUI
import WidgetKit

// MARK: - Cycle / log widget: facts only, never predicted dates

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
        let snapshot = context.isPreview && !(stored?.isSetUp ?? false) ? .preview : (stored ?? .empty)
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
        .configurationDisplayName("Your Month")
        .description("Days since your last period, or the days you've logged this month.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CycleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CycleEntry

    private var link: WidgetDeepLink {
        switch entry.summary.state {
        case .notSetUp: .checkIn
        case .needsPeriod: .setupCycle
        case .sinceLastPeriod: .calendar
        case .logging: .checkIn
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text(entry.summary.inline)
        case .systemMedium:
            HStack(spacing: 14) {
                headline
                MonthGrid(snapshot: entry.snapshot, date: entry.date)
                    .frame(maxWidth: .infinity)
            }
            .widgetURL(link.url)
        default:
            headline
                .widgetURL(link.url)
        }
    }

    @ViewBuilder
    private var headline: some View {
        let summary = entry.summary
        switch summary.state {
        case .notSetUp, .needsPeriod:
            WidgetIdleView(summary: summary, compact: family == .systemSmall)
        case .sinceLastPeriod, .logging:
            VStack(spacing: 0) {
                WidgetBrandMark(size: 16)
                    .padding(4)
                    .background(Color.wSurface, in: Capsule())
                Spacer(minLength: 4)
                Text(summary.label)
                    .font(.widget(.caption, weight: .heavy))
                    .foregroundStyle(Color.wNavy.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(summary.headline)
                    .font(.widget(size: 28, weight: .heavy))
                    .foregroundStyle(summary.state == .sinceLastPeriod ? Color.wPink : Color.wPurple)
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
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(entry.summary.circularValue)
                    .font(.widget(size: 20, weight: .bold))
                    .minimumScaleFactor(0.6)
                Text(entry.summary.circularCaption)
                    .font(.widget(size: 9, weight: .semibold))
                    .textCase(.uppercase)
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.summary.label)
                .font(.widget(.caption, weight: .semibold))
                .widgetAccentable()
            Text(entry.summary.headline)
                .font(.widget(.headline, weight: .bold))
            Text(entry.summary.detail)
                .font(.widget(.caption2))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Month grid: pink numbers for logged period days, a small dot under days
/// with a check-in, a filled navy circle for today. Nothing estimated.
struct MonthGrid: View {
    let snapshot: WidgetSnapshot
    let date: Date
    private let calendar = Calendar.current

    var body: some View {
        let cells = cells
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        VStack(spacing: 2) {
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
            let isToday = calendar.isDate(day, inSameDayAs: date)
            let isPeriod = snapshot.isPeriod(day, calendar: calendar)
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.widget(size: 11, weight: isToday || isPeriod ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.wOnInk : isPeriod ? Color.wPink : Color.wNavy.opacity(0.85))
                    .frame(width: 17, height: 15)
                    .background {
                        if isToday { Circle().fill(Color.wNavy).frame(width: 17, height: 17) }
                    }
                Circle()
                    .fill(Color.wPurple)
                    .frame(width: 3, height: 3)
                    .opacity(snapshot.isLogged(day, calendar: calendar) ? 1 : 0)
            }
        } else {
            Color.clear.frame(width: 17, height: 19)
        }
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
