import SwiftUI
import WidgetKit

// MARK: - What to do today, by cycle phase

struct TodayPlanEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var plan: WidgetTodayPlan { WidgetTodayPlan.make(for: snapshot, on: date) }
}

struct TodayPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayPlanEntry {
        TodayPlanEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayPlanEntry) -> Void) {
        // The gallery shows a sample cycle rather than an empty "Set up" card.
        let stored = WidgetSnapshotStore.load()
        let snapshot = context.isPreview && (stored?.cycleState ?? .notSetUp) == .notSetUp ? .preview : (stored ?? .empty)
        completion(TodayPlanEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayPlanEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .empty
        let entries = WidgetTimeline.dates(from: .now).map { TodayPlanEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.todayPlanWidgetKind, provider: TodayPlanProvider()) { entry in
            TodayPlanWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
        }
        .configurationDisplayName("Today's Plan")
        .description("A daily answer to \u{201C}should I test today?\u{201D} with the dates coming up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension WidgetTodayPlan {
    var tint: Color {
        switch phase {
        case .beforeTesting: .wTeal
        case .ovulationTesting: .wPurple
        case .twoWeekWait, .periodDue: .wPink
        case .idle: .wNavy
        }
    }

    var actionLink: WidgetDeepLink {
        .scanOvulation
    }

    var actionTitle: String {
        "Check Ovulation Test"
    }
}

struct TodayPlanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayPlanEntry

    var body: some View {
        let plan = entry.plan
        if plan.phase == .idle {
            WidgetIdleView(state: entry.snapshot.cycleState, compact: family == .systemSmall)
                .widgetURL((entry.snapshot.cycleState == .notSetUp ? WidgetDeepLink.setupCycle : .calendar).url)
        } else if family == .systemSmall {
            TodayPlanSmall(plan: plan)
                .widgetURL((plan.action == nil ? WidgetDeepLink.calendar : plan.actionLink).url)
        } else {
            TodayPlanMedium(plan: plan)
                .widgetURL(WidgetDeepLink.calendar.url)
        }
    }
}

private struct PlanHeadline: View {
    let plan: WidgetTodayPlan
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if plan.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.8, weight: .bold))
                    .foregroundStyle(plan.tint)
            }
            Text(plan.headline)
                .font(.widget(size: size, weight: .heavy))
                .foregroundStyle(Color.wNavy)
                .minimumScaleFactor(0.75)
        }
        .widgetAccentable()
    }
}

private struct PlanLabel: View {
    let plan: WidgetTodayPlan

    var body: some View {
        Text(plan.label)
            .font(.widget(.caption2, weight: .heavy))
            .foregroundStyle(plan.tint)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

private struct TodayPlanSmall: View {
    let plan: WidgetTodayPlan

    var body: some View {
        VStack(spacing: 6) {
            PlanLabel(plan: plan)
            PlanHeadline(plan: plan, size: 19)
                .lineLimit(3)
            Text(plan.compactDetail)
                .font(.widget(.caption, weight: .semibold))
                .foregroundStyle(Color.wNavy.opacity(0.62))
                .lineLimit(2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Left: today's answer and what to do. Right: the next dates that matter.
private struct TodayPlanMedium: View {
    let plan: WidgetTodayPlan

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .center, spacing: 4) {
                PlanLabel(plan: plan)
                PlanHeadline(plan: plan, size: 19)
                    .lineLimit(2)
                Text(plan.detail)
                    .font(.widget(.caption, weight: .semibold))
                    .foregroundStyle(Color.wNavy.opacity(0.65))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if plan.action != nil {
                    Link(destination: plan.actionLink.url) {
                        Label(plan.actionTitle, systemImage: "camera.viewfinder")
                            .font(.widget(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(plan.tint, in: Capsule())
                            .widgetAccentable()
                    }
                    .padding(.top, 6)
                } else if let tip = plan.tip {
                    Text(tip)
                        .font(.widget(.caption2, weight: .semibold))
                        .foregroundStyle(Color.wNavy.opacity(0.6))
                        .lineLimit(2)
                        .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if !plan.stops.isEmpty {
                ComingUpList(plan: plan)
                    .frame(width: 128)
            }
        }
    }
}

/// "Coming Up": one date per row, so close dates never collide.
private struct ComingUpList: View {
    let plan: WidgetTodayPlan

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            Text("Coming Up")
                .font(.widget(.caption2, weight: .heavy))
                .foregroundStyle(Color.wNavy.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.6)
            ForEach(Array(plan.stops.enumerated()), id: \.offset) { _, stop in
                VStack(alignment: .center, spacing: 0) {
                    Text(stop.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.widget(size: 12, weight: .heavy))
                        .foregroundStyle(plan.tint)
                        .widgetAccentable()
                    Text(stop.title)
                        .font(.widget(size: 11, weight: .semibold))
                        .foregroundStyle(Color.wNavy.opacity(0.75))
                        .minimumScaleFactor(0.8)
                }
                .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.wSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
