import Foundation
import SwiftData

/// Applies "Edit period dates" - the person taps every day they bled, and this
/// works out which logged periods to keep, stretch, move, remove or add.
enum PeriodBulkEditService {
    struct ExistingPeriod: Equatable {
        let id: UUID
        let start: Date
        let end: Date
    }

    enum Change: Equatable {
        case delete(UUID)
        case update(UUID, start: Date, end: Date)
        case create(start: Date, end: Date)
    }

    /// The days to pre-select when editing: an ongoing period is drawn as
    /// five days, but only the ones up to today have actually happened (and
    /// future days can't be tapped, so pre-selecting them left them stuck).
    static func editableDays(of period: PeriodEvent, today: Date = .now, calendar: Calendar = .current) -> [Date] {
        let limit = calendar.startOfDay(for: today)
        return days(of: period, calendar: calendar).filter { $0 <= limit }
    }

    static func days(of period: PeriodEvent, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: period.startDate)
        let end = calendar.startOfDay(for: period.endDate ?? calendar.date(byAdding: .day, value: 4, to: start) ?? start)
        return stride(start: start, through: max(start, end), calendar: calendar)
    }

    /// Pure planning step. Consecutive selected days form a run, except that a
    /// run always breaks at an existing period's first day so two logged
    /// periods that happen to touch are never silently merged.
    static func plan(existing: [ExistingPeriod], selectedDays: Set<Date>, calendar: Calendar = .current) -> [Change] {
        let selected = Set(selectedDays.map { calendar.startOfDay(for: $0) })
        let existingStarts = Set(existing.map { calendar.startOfDay(for: $0.start) })
        var runs: [(start: Date, end: Date)] = []
        for day in selected.sorted() {
            if let last = runs.last,
               let next = calendar.date(byAdding: .day, value: 1, to: last.end),
               calendar.isDate(next, inSameDayAs: day),
               !existingStarts.contains(day) {
                runs[runs.count - 1].end = day
            } else {
                runs.append((day, day))
            }
        }

        var changes: [Change] = []
        var matched = Set<UUID>()
        var creates: [Change] = []
        let sortedExisting = existing.sorted { $0.start < $1.start }
        for run in runs {
            let overlapping = sortedExisting.filter { period in
                !matched.contains(period.id) && period.start <= run.end && period.end >= run.start
            }
            // Prefer the period that already starts on this run's first day.
            if let keep = overlapping.first(where: { calendar.isDate($0.start, inSameDayAs: run.start) }) ?? overlapping.first {
                matched.insert(keep.id)
                if !calendar.isDate(keep.start, inSameDayAs: run.start) || !calendar.isDate(keep.end, inSameDayAs: run.end) {
                    changes.append(.update(keep.id, start: run.start, end: run.end))
                }
            } else {
                creates.append(.create(start: run.start, end: run.end))
            }
        }
        let deletes = sortedExisting.filter { !matched.contains($0.id) }.map { Change.delete($0.id) }
        return deletes + changes + creates
    }

    @MainActor
    @discardableResult
    static func apply(selectedDays: Set<Date>, settings: UserSettings, context: ModelContext, today: Date = .now, calendar: Calendar = .current) -> Bool {
        let marker = "[LineCheck Screenshot Sample]"
        let limit = calendar.startOfDay(for: today)
        let periods = ((try? context.fetch(FetchDescriptor<PeriodEvent>())) ?? []).filter { !$0.notes.contains(marker) }
        // An ongoing period runs "to today" for comparison, matching what the
        // editor pre-selects, so saving it unchanged isn't read as an edit.
        let existing = periods.map { period in
            ExistingPeriod(id: period.id, start: calendar.startOfDay(for: period.startDate), end: editableDays(of: period, today: today, calendar: calendar).last ?? calendar.startOfDay(for: period.startDate))
        }
        let changes = plan(existing: existing, selectedDays: selectedDays.filter { calendar.startOfDay(for: $0) <= limit }, calendar: calendar)
        guard !changes.isEmpty else { return false }

        for change in changes {
            switch change {
            case .delete(let id):
                if let period = fetchPeriods(context).first(where: { $0.id == id }) {
                    delete(period, context: context, calendar: calendar)
                }
            case .update(let id, let start, let end):
                if let period = fetchPeriods(context).first(where: { $0.id == id }) {
                    // Still bleeding today: keep it open rather than ending it.
                    let stillOngoing = period.endDate == nil && calendar.isDate(end, inSameDayAs: limit)
                    move(period, to: start, end: stillOngoing ? nil : end, context: context, calendar: calendar)
                }
            case .create(let start, let end):
                let records = ((try? context.fetch(FetchDescriptor<CycleRecord>())) ?? []).filter { !$0.notes.contains(marker) }
                _ = CycleTrackingService.recordPeriodStart(start, settings: settings, records: records, periods: fetchPeriods(context), context: context)
                // Commit the insert so the fetch below can see the new period.
                try? context.save()
                if let created = fetchPeriods(context).first(where: { calendar.isDate($0.startDate, inSameDayAs: start) }) {
                    // A run reaching today is a period that's still going.
                    created.endDate = calendar.isDate(end, inSameDayAs: limit) ? nil : end
                }
            }
            // Each step reads the store fresh, so commit before the next one.
            try? context.save()
        }

        let remaining = fetchPeriods(context)
        let records = ((try? context.fetch(FetchDescriptor<CycleRecord>())) ?? []).filter { !$0.notes.contains(marker) }
        let scans = (try? context.fetch(FetchDescriptor<Scan>())) ?? []
        for scan in scans where scan.cycleRecordID == nil { CycleTrackingService.attach(scan, to: records) }
        CycleTrackingService.reconcileOvulationEstimates(records: records, scans: scans)
        CycleTrackingService.reconcileTemperatureOvulation(records: records, logs: (try? context.fetch(FetchDescriptor<DailyFertilityLog>())) ?? [])
        settings.lastPeriodStartDate = remaining.map(\.startDate).max()
        settings.averageCycleLength = CycleTrackingService.learnedAverageCycleLength(from: remaining, fallback: settings.averageCycleLength)
        try? context.save()
        AppAnalytics.log("linecheck_period_bulk_edited", ["changes": String(changes.count)])
        return true
    }

    // MARK: Helpers

    private static func fetchPeriods(_ context: ModelContext) -> [PeriodEvent] {
        ((try? context.fetch(FetchDescriptor<PeriodEvent>())) ?? []).filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
    }

    /// Mirrors Calendar's single-period delete: the cycle it started goes too,
    /// and the previous cycle is re-joined to whatever follows.
    @MainActor
    private static func delete(_ period: PeriodEvent, context: ModelContext, calendar: Calendar) {
        let records = ((try? context.fetch(FetchDescriptor<CycleRecord>())) ?? []).filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        if let target = records.first(where: { $0.id == period.cycleRecordID }) {
            let remaining = records.filter { $0.id != target.id }.sorted { $0.startDate < $1.startDate }
            let previous = remaining.last { $0.startDate < target.startDate }
            let next = remaining.first { $0.startDate > target.startDate }
            previous?.endDate = next?.startDate
            previous?.status = next == nil ? .active : .completed
            let scans = (try? context.fetch(FetchDescriptor<Scan>())) ?? []
            for scan in scans where scan.cycleRecordID == target.id { scan.cycleRecordID = nil }
            let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
            let notifications = NotificationService()
            for reminder in reminders where reminder.isAutoGenerated && reminder.cycleRecordID == target.id {
                notifications.cancel(id: reminder.id)
                context.delete(reminder)
            }
            context.delete(target)
        }
        context.delete(period)
    }

    /// Moves a period (and the cycle it starts) to new dates. Only the start
    /// matters to predictions; the end just changes which days render as
    /// period.
    @MainActor
    private static func move(_ period: PeriodEvent, to start: Date, end: Date?, context: ModelContext, calendar: Calendar) {
        let oldStart = calendar.startOfDay(for: period.startDate)
        period.startDate = start
        period.endDate = end
        guard !calendar.isDate(oldStart, inSameDayAs: start) else { return }
        let records = ((try? context.fetch(FetchDescriptor<CycleRecord>())) ?? []).filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        guard let cycle = records.first(where: { $0.id == period.cycleRecordID || calendar.isDate($0.startDate, inSameDayAs: oldStart) }) else { return }
        cycle.startDate = start
        if let previous = records.filter({ $0.id != cycle.id && $0.startDate < start }).max(by: { $0.startDate < $1.startDate }),
           previous.endDate.map({ calendar.isDate($0, inSameDayAs: oldStart) }) ?? false {
            previous.endDate = start
        }
        if cycle.ovulationSource == nil,
           let baseline = FertilityWindowCalculator.window(for: start, lastPeriodStart: start, averageCycleLength: cycle.averageCycleLengthAtStart, lutealPhaseLength: cycle.lutealPhaseLengthAtStart, calendar: calendar) {
            cycle.predictedOvulationDate = baseline.predictedOvulationDate
            if cycle.confirmedOvulationDate == nil { cycle.expectedPeriodDate = baseline.nextPeriodDate }
        }
        cycle.updatedAt = .now
    }

    private static func stride(start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = start
        while day <= end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
