import Foundation
import WidgetKit

/// Turns the app's SwiftData state into the small snapshot the Home Screen
/// widgets read: logged days, period days and the last period start. Facts
/// only - the widgets never show predicted dates.
enum WidgetSnapshotService {
    private static let sampleMarker = "[LineCheck Screenshot Sample]"
    /// How far back logged and period days are kept (the month grid shows
    /// the current month; a week strip the last seven days).
    static let lookbackDays = 62

    static func snapshot(
        settings: UserSettings?,
        cycleRecords: [CycleRecord],
        periodEvents: [PeriodEvent],
        logs: [DailyFertilityLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        guard let settings, settings.hasCompletedOnboarding else { return .empty }
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let periods = periodEvents.filter { !$0.notes.contains(sampleMarker) }
        let records = cycleRecords.filter { !$0.notes.contains(sampleMarker) }
        let realLogs = logs.filter { !$0.notes.contains(sampleMarker) }

        var periodDays = Set<String>()
        for period in periods {
            let start = calendar.startOfDay(for: period.startDate)
            // Open-ended periods display as five days, as in the Calendar.
            let end = min(period.endDate.map { calendar.startOfDay(for: $0) } ?? calendar.date(byAdding: .day, value: 4, to: start) ?? start, today)
            var day = max(start, cutoff)
            while day <= end {
                periodDays.insert(WidgetSnapshot.dayKey(day, calendar: calendar))
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1)
            }
        }
        for log in realLogs where log.flowIntensity != nil && log.date >= cutoff {
            periodDays.insert(WidgetSnapshot.dayKey(log.date, calendar: calendar))
        }

        let loggedDays = Set(realLogs.filter { $0.hasContent && $0.date >= cutoff }.map { WidgetSnapshot.dayKey($0.date, calendar: calendar) })
        let lastStart = CycleChangeCalculator.summary(
            periodStarts: periods.map(\.startDate) + records.map(\.startDate), on: now, calendar: calendar
        ).lastPeriodStart

        return WidgetSnapshot(
            isSetUp: true,
            tracksCycle: settings.menopauseStage.tracksCycle,
            lastPeriodStart: settings.menopauseStage.tracksCycle ? lastStart : nil,
            periodDays: settings.menopauseStage.tracksCycle ? periodDays : [],
            loggedDays: loggedDays,
            focus: settings.focusSymptoms
        )
    }

    /// Writes the snapshot and reloads widgets only when something changed.
    static func publish(_ snapshot: WidgetSnapshot) {
        guard WidgetSnapshotStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
