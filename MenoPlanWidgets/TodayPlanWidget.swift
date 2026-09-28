import SwiftUI
import WidgetKit

// MARK: - Daily check-in widget

struct TodayPlanEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var checkIn: WidgetCheckIn { WidgetCheckIn.make(for: snapshot, on: date) }
}

struct TodayPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayPlanEntry {
        TodayPlanEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayPlanEntry) -> Void) {
        let stored = WidgetSnapshotStore.load()
        let snapshot = context.isPreview && !(stored?.isSetUp ?? false) ? .preview : (stored ?? .empty)
        completion(TodayPlanEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayPlanEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .empty
        let entries = WidgetTimeline.dates(from: .now).map { TodayPlanEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Kind string kept from LineCheck's "Today's Plan" so placed widgets survive.
struct TodayPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.todayPlanWidgetKind, provider: TodayPlanProvider()) { entry in
            TodayPlanWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
        }
        .configurationDisplayName("Daily Check-in")
        .description("One tap to log how today went, and your last seven days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayPlanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayPlanEntry

    var body: some View {
        let checkIn = entry.checkIn
        Group {
            if !entry.snapshot.isSetUp {
                WidgetIdleView(summary: WidgetCycleSummary.make(for: entry.snapshot, on: entry.date), compact: family == .systemSmall)
            } else if family == .systemSmall {
                VStack(spacing: 8) {
                    prompt(checkIn, size: 19)
                    WeekDots(week: checkIn.week)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    prompt(checkIn, size: 21)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 8) {
                        Text("Last 7 days")
                            .font(.widget(.caption2, weight: .heavy))
                            .foregroundStyle(Color.wNavy.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(0.6)
                        WeekDots(week: checkIn.week, showsLabels: true)
                    }
                    .padding(10)
                    .frame(width: 138)
                    .frame(maxHeight: .infinity)
                    .background(Color.wSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .widgetURL(WidgetDeepLink.checkIn.url)
    }

    private func prompt(_ checkIn: WidgetCheckIn, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: checkIn.loggedToday ? "checkmark.circle.fill" : "sun.haze.fill")
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundStyle(checkIn.loggedToday ? Color.wPurple : Color.orange)
                .widgetAccentable()
            Text(checkIn.headline)
                .font(.widget(size: size, weight: .heavy))
                .foregroundStyle(Color.wNavy)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(checkIn.detail)
                .font(.widget(.caption, weight: .semibold))
                .foregroundStyle(Color.wNavy.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .multilineTextAlignment(.center)
    }
}

/// Seven dots, filled for days with a check-in. No streak count on purpose.
private struct WeekDots: View {
    let week: [WidgetCheckIn.Day]
    var showsLabels = false

    var body: some View {
        HStack(spacing: showsLabels ? 5 : 6) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 3) {
                    if showsLabels {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.widget(size: 9, weight: .bold))
                            .foregroundStyle(Color.wNavy.opacity(0.45))
                    }
                    Circle()
                        .fill(day.logged ? Color.wPurple : Color.wNavy.opacity(0.12))
                        .frame(width: showsLabels ? 12 : 9, height: showsLabels ? 12 : 9)
                        .overlay {
                            if index == week.count - 1 {
                                Circle().stroke(Color.wNavy, lineWidth: 1.2).padding(-2)
                            }
                        }
                        .widgetAccentable()
                }
            }
        }
    }
}

#Preview(as: .systemMedium) {
    TodayPlanWidget()
} timeline: {
    TodayPlanEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemSmall) {
    TodayPlanWidget()
} timeline: {
    TodayPlanEntry(date: .now, snapshot: .preview)
}
