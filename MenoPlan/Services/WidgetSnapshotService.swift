import Foundation
import WidgetKit

/// Turns the app's SwiftData state into the small, precomputed snapshot the
/// Home Screen widgets read. Uses the same calculators as Home and Calendar so
/// the widget can never disagree with what the app shows.
enum WidgetSnapshotService {
    private static let sampleMarker = "[LineCheck Screenshot Sample]"

    static func snapshot(
        settings: UserSettings?,
        cycleRecords: [CycleRecord],
        periodEvents: [PeriodEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let records = cycleRecords.filter { !$0.notes.contains(sampleMarker) }
        let periods = periodEvents.filter { !$0.notes.contains(sampleMarker) }
        let window = CycleTrackingService.window(for: now, records: records, periods: periods, settings: settings, calendar: calendar)
        let cycleState: WidgetSnapshot.CycleState = window == nil ? .notSetUp : .tracking

        var phases: [String: WidgetSnapshot.DayPhase] = [:]
        if let window, cycleState == .tracking {
            // This month and next, so the medium calendar keeps working across
            // a month boundary even if the app isn't opened for a while.
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 2, to: monthStart) ?? monthStart
            var day = monthStart
            while day < end {
                let phase = CycleCalendarPhaseResolver.phase(
                    for: day, window: window, cycleRecords: records, periodEvents: periods, calendar: calendar
                )
                if let mapped = mapped(phase) {
                    phases[WidgetSnapshot.dayKey(day, calendar: calendar)] = mapped
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
            }
        }

        return WidgetSnapshot(
            cycleState: cycleState,
            cycle: cycleState == .tracking ? window.map {
                WidgetSnapshot.Cycle(cycleStart: $0.cycleStart, nextPeriod: $0.nextPeriodDate, isIrregular: $0.isIrregular)
            } : nil,
            dayPhases: phases
        )
    }

    /// Writes the snapshot and reloads widgets only when something changed.
    static func publish(_ snapshot: WidgetSnapshot) {
        guard WidgetSnapshotStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func mapped(_ phase: CycleCalendarPhase) -> WidgetSnapshot.DayPhase? {
        switch phase {
        case .regular: nil
        case .period: .period
        case .predictedPeriod: .predictedPeriod
        }
    }
}
