import Foundation
import SwiftData

struct FertilityWindow {
    var cycleStart: Date
    var cycleDay: Int
    var predictedOvulationDate: Date
    var fertileStartDate: Date
    var fertileEndDate: Date
    var opkStartDate: Date
    var nextPeriodDate: Date
    /// Spread (max - min) across the last up to 6 valid logged cycle lengths,
    /// nil when there isn't enough history to say anything meaningful.
    var cycleLengthVariabilityDays: Int? = nil
    /// Why the window was widened from the person's own answers (PCOS,
    /// irregular periods, recent hormonal birth control), if it was. Kept
    /// apart from `isIrregular`, which describes logged history only.
    var profileWidening: ProfileWidening? = nil
    /// How many days a *forecast* period is drawn for - learned from logged
    /// periods with a known end, else the length given at onboarding.
    var periodLength: Int = FertilityWindowCalculator.defaultPeriodLength

    /// True once cycles have varied enough recently that a single predicted
    /// date is unreliable. This is a description of the logged history, not a
    /// medical diagnosis - the UI should widen guidance, not alarm the user.
    var isIrregular: Bool {
        (cycleLengthVariabilityDays ?? 0) >= FertilityWindowCalculator.irregularCycleThresholdDays
    }

    /// True when the range has been padded for uncertainty (varying cycles,
    /// PCOS, recent birth control, BMI). Nobody is fertile for 10+ days - the
    /// real window is about 6 days - so a padded range must not be called a
    /// "fertile window"; it's where those 6 days are likely to fall.
    var isWidened: Bool { profileWidening != nil || isIrregular }

    var fertileRangeTitle: String { isWidened ? "Possible fertile days" : "Fertile window" }

    /// One line explaining a widened range, for wherever it's shown.
    var widenedRangeNote: String? {
        guard isWidened else { return nil }
        return "Your most fertile 6 days fall somewhere in this range. It's wider \(profileWidening.map { _ in "while MenoPlan learns your cycle" } ?? "because your recent cycles have varied"). A Peak test or temperature rise will narrow it."
    }

    func isPastExpectedPeriod(on date: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: nextPeriodDate)
    }

    func containsFertileDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: fertileStartDate) && day <= calendar.startOfDay(for: fertileEndDate)
    }

    func isPredictedOvulationDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: predictedOvulationDate)
    }
}

/// The semantic phase assigned to one calendar day. Keeping this decision out
/// of SwiftUI makes the calendar's precedence rules testable and reusable.
enum CycleCalendarPhase: Equatable {
    case regular
    case period
    case predictedPeriod
    case opkWindow
    case fertile
    case ovulation
    case confirmedOvulation
    case luteal
}

enum CycleCalendarPhaseResolver {
    static func phase(
        for date: Date,
        window: FertilityWindow,
        cycleRecords: [CycleRecord],
        periodEvents: [PeriodEvent],
        calendar: Calendar = .current
    ) -> CycleCalendarPhase {
        let day = calendar.startOfDay(for: date)

        // User-entered history is more reliable than any estimate.
        if CycleTrackingService.periodEvent(containing: day, in: periodEvents, calendar: calendar) != nil {
            return .period
        }

        if cycleRecords.contains(where: { $0.confirmedOvulationDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false }) {
            return .confirmedOvulation
        }
        if calendar.isDate(day, inSameDayAs: window.predictedOvulationDate) {
            return .ovulation
        }
        if window.containsFertileDay(day, calendar: calendar) {
            return .fertile
        }

        // An expected period is only a forecast. Do not let it conceal an
        // active fertile or ovulation estimate when the saved data overlaps.
        if day >= calendar.startOfDay(for: window.nextPeriodDate),
           day < (calendar.date(byAdding: .day, value: window.periodLength, to: calendar.startOfDay(for: window.nextPeriodDate)) ?? .distantPast),
           !hasConfirmedPeriodEnded(before: day, for: window, periodEvents: periodEvents, calendar: calendar) {
            return .predictedPeriod
        }
        if day > calendar.startOfDay(for: window.predictedOvulationDate)
            && day < calendar.startOfDay(for: window.nextPeriodDate) {
            return .luteal
        }
        if day >= calendar.startOfDay(for: window.opkStartDate)
            && day < calendar.startOfDay(for: window.fertileStartDate) {
            return .opkWindow
        }
        return .regular
    }

    private static func hasConfirmedPeriodEnded(
        before day: Date,
        for window: FertilityWindow,
        periodEvents: [PeriodEvent],
        calendar: Calendar
    ) -> Bool {
        // Only a period logged around the *expected* date retires the
        // forecast. The current cycle's own period ending says nothing about
        // the next one.
        let expected = calendar.startOfDay(for: window.nextPeriodDate)
        let earliest = calendar.date(byAdding: .day, value: -7, to: expected) ?? expected
        return periodEvents.contains { event in
            let start = calendar.startOfDay(for: event.startDate)
            guard start > calendar.startOfDay(for: window.cycleStart), start >= earliest else { return false }
            // It came late: the days it was forecast for, before it started,
            // weren't period and shouldn't stay drawn as one.
            if day < start { return true }
            guard let endDate = event.endDate else { return false }
            return day > calendar.startOfDay(for: endDate)
        }
    }

    /// Rolls the open cycle forward so later months show estimated periods,
    /// fertile windows and ovulation. Only used while the next period is
    /// still ahead: once it's late, nothing after it is guessed at.
    static func projectedWindow(
        for date: Date,
        from window: FertilityWindow,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> FertilityWindow? {
        let day = calendar.startOfDay(for: date)
        let next = calendar.startOfDay(for: window.nextPeriodDate)
        guard day >= next, next > calendar.startOfDay(for: today) else { return nil }
        let start = calendar.startOfDay(for: window.cycleStart)
        let length = calendar.dateComponents([.day], from: start, to: next).day ?? 28
        let ovulationOffset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: window.predictedOvulationDate)).day ?? 14
        return FertilityWindowCalculator.window(
            for: day,
            lastPeriodStart: next,
            averageCycleLength: length,
            lutealPhaseLength: length - ovulationOffset - 1,
            cycleLengthVariabilityDays: window.cycleLengthVariabilityDays,
            profileWidening: window.profileWidening,
            periodLength: window.periodLength,
            projectsFutureCycles: true,
            calendar: calendar
        )
    }

    /// Phase for a day in a projected (future) cycle: its first `periodLength`
    /// days are the estimated period, everything else follows the usual rules.
    static func projectedPhase(for date: Date, window: FertilityWindow, calendar: Calendar = .current) -> CycleCalendarPhase {
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: window.cycleStart)
        if day >= start, day < (calendar.date(byAdding: .day, value: window.periodLength, to: start) ?? start) {
            return .predictedPeriod
        }
        return phase(for: day, window: window, cycleRecords: [], periodEvents: [], calendar: calendar)
    }
}

/// Widening driven by the personalisation answers rather than logged
/// history. Each reason pads the fertile/testing window by a few days.
enum ProfileWidening: String, Equatable {
    case pcos, irregularPeriods, recentBirthControl, bodyWeight

    var paddingDays: Int {
        switch self {
        case .pcos, .irregularPeriods: 4
        case .recentBirthControl, .bodyWeight: 3
        }
    }

    /// Short label for Home.
    var shortNote: String {
        switch self {
        case .pcos: "Wider window to allow for PCOS"
        case .irregularPeriods: "Wider window as your periods vary"
        case .recentBirthControl: "Wider window while your cycle settles"
        case .bodyWeight: "Wider window until your cycle history builds"
        }
    }

    /// Plain-English reason for "How is this worked out?" and Luna.
    var explanation: String {
        switch self {
        case .pcos:
            "You told MenoPlan you have PCOS, so the fertile window and ovulation-test start are widened by \(paddingDays) days either side. Ovulation can be less predictable with PCOS."
        case .irregularPeriods:
            "You told MenoPlan your periods aren’t regular, so the fertile window is widened by \(paddingDays) days until you’ve logged enough periods for your own history to take over."
        case .recentBirthControl:
            "You recently used hormonal birth control, which can take a few cycles to settle, so the fertile window is widened by \(paddingDays) days until you’ve logged a few more periods."
        case .bodyWeight:
            "Your height and weight put your BMI outside the range where ovulation is most regular, so the fertile window is widened by \(paddingDays) days until you’ve logged enough periods for your own history to take over."
        }
    }

    /// Logged periods after which a self-reported irregular pattern or
    /// recent birth control stops widening: the person's own history
    /// (including its measured variability) is the better guide by then.
    static let historyTakesOverAfterPeriods = 4

    static func reason(for settings: UserSettings?, loggedPeriodCount: Int) -> ProfileWidening? {
        guard let profile = settings?.healthProfile else { return nil }
        if profile.hasPCOS { return .pcos }
        guard loggedPeriodCount < historyTakesOverAfterPeriods else { return nil }
        if profile.regularity == .irregular { return .irregularPeriods }
        if profile.birthControl?.mayAffectRecentCycles == true && profile.birthControl != .stillUsing { return .recentBirthControl }
        if profile.bmiCategory?.mayAffectOvulation == true { return .bodyWeight }
        return nil
    }
}

enum FertilityWindowCalculator {
    /// The widest span we'll treat as a single ovulatory cycle rather than
    /// discarding the data point. 45 days excluded real (if long) cycles for
    /// people with PCOS or other causes of oligomenorrhea - their logged
    /// history was silently thrown out and predictions fell back to a
    /// default 28-day assumption that didn't match their body at all. 90
    /// days covers the clinically recognized range for a long-but-still-
    /// cycling pattern; beyond that is amenorrhea, which this calculator
    /// isn't trying to predict through.
    static let plausibleCycleLengthRange = 21...90

    /// Spread (max - min) of recent cycle lengths at or above which we treat
    /// the cycle as irregular enough to widen the predicted testing window.
    static let irregularCycleThresholdDays = 8

    /// Maximum days the fertile/testing window is pulled earlier when cycles
    /// have been irregular. Widened from an earlier, more token 5-day cap so
    /// highly variable cycles get a genuinely useful window rather than a
    /// single unreliable date.
    static let irregularityPaddingCapDays = 10

    /// Period length used until the person tells us theirs or logs enough
    /// periods with an end date for LineCheck to learn it.
    static let defaultPeriodLength = 5
    static let plausiblePeriodLengthRange = 2...10

    /// The one place the ovulation -> next period relationship lives.
    ///
    /// Luteal phase length counts the days *after* ovulation up to the day
    /// before bleeding starts, so a 28-day cycle with a 14-day luteal phase
    /// ovulates on cycle day 14 and the next period is cycle day 29 - i.e.
    /// ovulation + luteal + 1. `window(...)` has always used this convention;
    /// LH-peak, confirmed-ovulation and learned-luteal paths previously
    /// used ovulation + luteal, which put the period a day early and, through
    /// the learned luteal length, pulled later ovulation estimates a day early.
    static func nextPeriod(afterOvulation ovulation: Date, lutealPhaseLength: Int, calendar: Calendar = .current) -> Date {
        let luteal = min(18, max(10, lutealPhaseLength))
        let day = calendar.startOfDay(for: ovulation)
        return calendar.date(byAdding: .day, value: luteal + 1, to: day) ?? day
    }

    static func isWithinProjectionHorizon(
        _ date: Date,
        from anchor: Date,
        months: Int = 6,
        calendar: Calendar = .current
    ) -> Bool {
        guard let limit = calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: anchor)) else {
            return false
        }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: limit)
    }

    static func window(
        for date: Date = .now,
        lastPeriodStart: Date?,
        averageCycleLength: Int,
        lutealPhaseLength: Int,
        cycleLengthVariabilityDays: Int? = nil,
        profileWidening: ProfileWidening? = nil,
        periodLength: Int = defaultPeriodLength,
        currentPeriodDays: Int? = nil,
        projectsFutureCycles: Bool = false,
        calendar: Calendar = .current
    ) -> FertilityWindow? {
        guard let lastPeriodStart else { return nil }
        let cycleLength = min(plausibleCycleLengthRange.upperBound, max(plausibleCycleLengthRange.lowerBound, averageCycleLength))
        let lutealLength = min(18, max(10, lutealPhaseLength))
        let day = calendar.startOfDay(for: date)
        var cycleStart = calendar.startOfDay(for: lastPeriodStart)

        // An actual start stays authoritative. Repeated-cycle projection is
        // available only when a caller explicitly requests a hypothetical view.
        guard day >= cycleStart else { return nil }

        if projectsFutureCycles {
            while let next = calendar.date(byAdding: .day, value: cycleLength, to: cycleStart), next <= day {
                cycleStart = next
            }
        }

        let cycleDay = (calendar.dateComponents([.day], from: cycleStart, to: day).day ?? 0) + 1
        // Cycle day 1 is the period start, while date offsets are zero-based.
        let predictedOvulationOffset = max(5, cycleLength - lutealLength - 1)
        let predictedOvulationDate = calendar.date(byAdding: .day, value: predictedOvulationOffset, to: cycleStart) ?? cycleStart
        let opkStartOffset = max(5, predictedOvulationOffset - 7)
        let nextPeriodDate = calendar.date(byAdding: .day, value: cycleLength, to: cycleStart) ?? cycleStart

        // When recent cycles have varied a lot, a single predicted ovulation
        // date is unreliable, so start the fertile/testing window earlier
        // rather than claim false precision. Capped so one very irregular
        // cycle doesn't push testing implausibly early.
        let historyPadding = (cycleLengthVariabilityDays ?? 0) >= irregularCycleThresholdDays
            ? min(irregularityPaddingCapDays, (cycleLengthVariabilityDays ?? 0) / 2)
            : 0
        let irregularityPadding = max(historyPadding, profileWidening?.paddingDays ?? 0)
        // Widening allows for ovulation coming earlier than estimated, but it
        // must not reach back into the period itself: the calendar draws those
        // days as period, so "fertile from tomorrow" on cycle day 1 would
        // contradict it. The un-widened window can still overlap the period
        // in a genuinely short cycle. The bleed the calendar actually draws
        // for this cycle (`currentPeriodDays`) wins over the learned typical length.
        let clampedPeriodLength = min(plausiblePeriodLengthRange.upperBound, max(plausiblePeriodLengthRange.lowerBound, currentPeriodDays ?? periodLength))
        let unpaddedFertileOffset = max(0, predictedOvulationOffset - 5)
        let fertileStartOffset = max(predictedOvulationOffset - 5 - irregularityPadding, min(unpaddedFertileOffset, clampedPeriodLength), 0)
        let fertileStartDate = calendar.date(byAdding: .day, value: fertileStartOffset, to: cycleStart) ?? cycleStart
        let widenedEnd = calendar.date(byAdding: .day, value: irregularityPadding, to: predictedOvulationDate) ?? predictedOvulationDate
        let fertileEndDate = min(widenedEnd, calendar.date(byAdding: .day, value: -1, to: nextPeriodDate) ?? widenedEnd)
        let opkOffset = max(opkStartOffset - irregularityPadding, min(opkStartOffset, clampedPeriodLength), 0)
        let opkStartDate = calendar.date(byAdding: .day, value: opkOffset, to: cycleStart) ?? cycleStart

        return FertilityWindow(
            cycleStart: cycleStart,
            cycleDay: cycleDay,
            predictedOvulationDate: predictedOvulationDate,
            fertileStartDate: fertileStartDate,
            fertileEndDate: fertileEndDate,
            opkStartDate: opkStartDate,
            nextPeriodDate: nextPeriodDate,
            cycleLengthVariabilityDays: cycleLengthVariabilityDays,
            profileWidening: profileWidening,
            periodLength: min(plausiblePeriodLengthRange.upperBound, max(plausiblePeriodLengthRange.lowerBound, periodLength))
        )
    }

    static func cycleDay(for date: Date, cycleStart: Date, calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: cycleStart), to: calendar.startOfDay(for: date)).day ?? 0) + 1
    }
}

enum CycleTrackingService {
    static func periodEvent(
        containing date: Date,
        in periods: [PeriodEvent],
        calendar: Calendar = .current
    ) -> PeriodEvent? {
        let day = calendar.startOfDay(for: date)
        return periods.last { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(
                for: event.endDate
                    ?? calendar.date(byAdding: .day, value: 4, to: start)
                    ?? start
            )
            return day >= start && day <= end
        }
    }

    static func activeCycle(on date: Date = .now, records: [CycleRecord], calendar: Calendar = .current) -> CycleRecord? {
        let day = calendar.startOfDay(for: date)
        return records
            .filter {
                !$0.notes.contains("[LineCheck Screenshot Sample]") &&
                calendar.startOfDay(for: $0.startDate) <= day &&
                ($0.endDate.map { day < calendar.startOfDay(for: $0) } ?? true)
            }
            .max { $0.startDate < $1.startDate }
    }

    static func cycle(containing date: Date, records: [CycleRecord], calendar: Calendar = .current) -> CycleRecord? {
        activeCycle(on: date, records: records, calendar: calendar)
    }

    static func window(for date: Date = .now, records: [CycleRecord], periods: [PeriodEvent] = [], settings: UserSettings?, calendar: Calendar = .current) -> FertilityWindow? {
        // Some callers (including reminder settings) only have cycle rows.
        // Their recorded starts carry the same history as period events.
        let history = periods.isEmpty
            ? records.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }.map { PeriodEvent(startDate: $0.startDate) }
            : periods.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        let variability = cycleLengthVariability(from: history, calendar: calendar)
        let widening = ProfileWidening.reason(for: settings, loggedPeriodCount: history.count)
        let periodLength = learnedPeriodLength(from: history, fallback: settings?.periodLength ?? FertilityWindowCalculator.defaultPeriodLength, calendar: calendar)
        /// Days the calendar draws as period for the bleed that starts a cycle
        /// (an open-ended one shows as five days).
        func drawnPeriodDays(from start: Date?) -> Int? {
            guard let start, let event = periodEvent(containing: start, in: history, calendar: calendar) else { return nil }
            let first = calendar.startOfDay(for: event.startDate)
            let last = calendar.startOfDay(for: event.endDate ?? calendar.date(byAdding: .day, value: 4, to: first) ?? first)
            return (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        }
        guard let cycle = activeCycle(on: date, records: records, calendar: calendar) else {
            return FertilityWindowCalculator.window(
                for: date,
                lastPeriodStart: settings?.lastPeriodStartDate,
                averageCycleLength: settings?.averageCycleLength ?? 28,
                lutealPhaseLength: settings?.lutealPhaseLength ?? 14,
                cycleLengthVariabilityDays: variability,
                profileWidening: widening,
                periodLength: periodLength,
                currentPeriodDays: drawnPeriodDays(from: settings?.lastPeriodStartDate),
                projectsFutureCycles: false,
                calendar: calendar
            )
        }
        // Backfilled/edited history must inform the open cycle too. Closed
        // cycles retain their original assumptions for historical views.
        // A length the person set by hand for this cycle beats both - they
        // may know something (a change of medication, travel) history can't.
        let cycleLength = cycle.userSetCycleLength ?? (cycle.endDate == nil
            ? learnedAverageCycleLength(from: history, fallback: cycle.averageCycleLengthAtStart, calendar: calendar)
            : cycle.averageCycleLengthAtStart)
        var window = FertilityWindowCalculator.window(
            for: date,
            lastPeriodStart: cycle.startDate,
            averageCycleLength: cycleLength,
            lutealPhaseLength: cycle.lutealPhaseLengthAtStart,
            cycleLengthVariabilityDays: variability,
            profileWidening: widening,
            periodLength: periodLength,
            currentPeriodDays: drawnPeriodDays(from: cycle.startDate),
            projectsFutureCycles: false,
            calendar: calendar
        )
        let isSavedCycle = window.map { calendar.isDate($0.cycleStart, inSameDayAs: cycle.startDate) } ?? false
        if isSavedCycle, let confirmed = cycle.confirmedOvulationDate, var resolved = window {
            resolved.predictedOvulationDate = calendar.startOfDay(for: confirmed)
            // Real evidence beats a widened guess.
            resolved.profileWidening = nil
            resolved.fertileStartDate = calendar.date(byAdding: .day, value: -5, to: confirmed) ?? confirmed
            resolved.fertileEndDate = confirmed
            resolved.opkStartDate = calendar.date(byAdding: .day, value: -7, to: confirmed) ?? confirmed
            resolved.nextPeriodDate = cycle.expectedPeriodDate
                ?? FertilityWindowCalculator.nextPeriod(afterOvulation: confirmed, lutealPhaseLength: cycle.lutealPhaseLengthAtStart, calendar: calendar)
            window = resolved
        } else if isSavedCycle, var resolved = window {
            // Calendar-only dates are cached calculations, not observations.
            // Recompute them from current history; only a saved test can
            // override the baseline (and it must belong to this cycle).
            if cycle.ovulationSource == .testSupported || cycle.ovulationSource == .temperatureSupported,
               let storedOvulation = cycle.predictedOvulationDate.map({ calendar.startOfDay(for: $0) }),
               isPlausiblePredictedOvulation(storedOvulation, cycle: cycle, calendar: calendar) {
                resolved.predictedOvulationDate = storedOvulation
                resolved.profileWidening = nil
                resolved.fertileStartDate = calendar.date(byAdding: .day, value: -5, to: storedOvulation) ?? storedOvulation
                resolved.fertileEndDate = storedOvulation
                resolved.opkStartDate = calendar.date(byAdding: .day, value: -7, to: storedOvulation) ?? storedOvulation
                resolved.nextPeriodDate = cycle.expectedPeriodDate ?? resolved.nextPeriodDate
            }
            window = resolved
        }
        return window
    }

    private static func isPlausiblePredictedOvulation(
        _ date: Date,
        cycle: CycleRecord,
        calendar: Calendar
    ) -> Bool {
        let earliest = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: cycle.startDate))
            ?? cycle.startDate
        let latest = cycle.endDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
        return date >= earliest && date < latest
    }

    /// Manual entries only conflict with an existing bleed. Importers may
    /// request a wider separation to avoid treating sparse flow as cycles.
    static func periodStartConflict(
        on date: Date,
        periods: [PeriodEvent],
        minimumSeparationDays: Int = 0,
        calendar: Calendar = .current
    ) -> PeriodEvent? {
        let day = calendar.startOfDay(for: date)
        return periods.first { event in
            let start = calendar.startOfDay(for: event.startDate)
            let distance = abs(calendar.dateComponents([.day], from: start, to: day).day ?? 0)
            return distance < minimumSeparationDays || periodEvent(containing: day, in: [event], calendar: calendar) != nil
        }
    }

    static func learnedAverageCycleLength(from periods: [PeriodEvent], fallback: Int, calendar: Calendar = .current) -> Int {
        let starts = periods.map { calendar.startOfDay(for: $0.startDate) }.sorted()
        let lengths = zip(starts, starts.dropFirst()).suffix(6).compactMap { first, second -> Int? in
            let days = calendar.dateComponents([.day], from: first, to: second).day ?? 0
            return FertilityWindowCalculator.plausibleCycleLengthRange.contains(days) ? days : nil
        }
        guard !lengths.isEmpty else { return fallback }
        // Median rather than mean: a single atypically long/short (but still
        // plausible) cycle shouldn't drag the prediction for the next 6 cycles.
        return median(of: lengths)
    }

    /// Spread (max - min) across the last up to 6 valid logged cycle lengths.
    /// Nil below 3 data points, where a spread isn't meaningful yet.
    static func cycleLengthVariability(from periods: [PeriodEvent], calendar: Calendar = .current) -> Int? {
        let starts = periods.map { calendar.startOfDay(for: $0.startDate) }.sorted()
        let lengths = zip(starts, starts.dropFirst()).suffix(6).compactMap { first, second -> Int? in
            let days = calendar.dateComponents([.day], from: first, to: second).day ?? 0
            return FertilityWindowCalculator.plausibleCycleLengthRange.contains(days) ? days : nil
        }
        guard lengths.count >= 3 else { return nil }
        guard let low = lengths.min(), let high = lengths.max() else { return nil }
        return high - low
    }

    /// Median length of the last up to 6 periods that have a logged end
    /// date. An open-ended period is only ever *displayed* as five days, so it
    /// is not evidence of anything and is skipped.
    static func learnedPeriodLength(from periods: [PeriodEvent], fallback: Int, calendar: Calendar = .current) -> Int {
        let lengths = periods
            .sorted { $0.startDate < $1.startDate }
            .compactMap { period -> Int? in
                guard let end = period.endDate else { return nil }
                let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: period.startDate), to: calendar.startOfDay(for: end)).day ?? -1) + 1
                return FertilityWindowCalculator.plausiblePeriodLengthRange.contains(days) ? days : nil
            }
            .suffix(6)
        let range = FertilityWindowCalculator.plausiblePeriodLengthRange
        guard !lengths.isEmpty else { return min(range.upperBound, max(range.lowerBound, fallback)) }
        return median(of: Array(lengths))
    }

    /// Records a known ovulation date on a cycle and moves that cycle's
    /// expected period with it, so confirming ovulation later than the
    /// estimate also pushes the next-period forecast later.
    static func confirmOvulation(_ date: Date, on cycle: CycleRecord, source: TrackingDataSource = .userConfirmed, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        cycle.confirmedOvulationDate = day
        cycle.ovulationSource = source
        cycle.expectedPeriodDate = FertilityWindowCalculator.nextPeriod(afterOvulation: day, lutealPhaseLength: cycle.lutealPhaseLengthAtStart, calendar: calendar)
        cycle.updatedAt = .now
    }

    /// A single value in an even-count window rounds to the nearer integer
    /// rather than always down, so a run like [27, 32] predicts 30, not 29.
    private static func median(of values: [Int]) -> Int {
        let sorted = values.sorted()
        let count = sorted.count
        guard count > 0 else { return 0 }
        if count % 2 == 1 { return sorted[count / 2] }
        return Int((Double(sorted[count / 2 - 1] + sorted[count / 2]) / 2.0).rounded())
    }

    /// Learns the interval from observed ovulation to the following period.
    /// Pure calendar predictions are excluded so the estimate does not train on itself.
    static func learnedLutealPhaseLength(from records: [CycleRecord], fallback: Int, calendar: Calendar = .current) -> Int {
        let lengths = records.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }.compactMap { cycle -> Int? in
            guard cycle.ovulationSource != nil,
                  let ovulation = cycle.effectiveOvulationDate,
                  let nextPeriod = cycle.endDate else { return nil }
            // Days strictly between ovulation and the next bleed - the same
            // convention FertilityWindowCalculator.nextPeriod(afterOvulation:) uses.
            let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: ovulation), to: calendar.startOfDay(for: nextPeriod)).day ?? 0) - 1
            return (8...18).contains(days) ? days : nil
        }
        guard !lengths.isEmpty else { return min(18, max(10, fallback)) }
        return min(18, max(10, median(of: Array(lengths.suffix(6)))))
    }

    @MainActor
    static func recordPeriodStart(
        _ date: Date,
        settings: UserSettings,
        records: [CycleRecord],
        periods: [PeriodEvent],
        context: ModelContext,
        source: TrackingDataSource = .userConfirmed,
        calendar: Calendar = .current
    ) -> CycleRecord {
        let start = calendar.startOfDay(for: date)
        let realRecords = records.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        if let existing = realRecords.first(where: { calendar.isDate($0.startDate, inSameDayAs: start) }) {
            if !periods.contains(where: { calendar.isDate($0.startDate, inSameDayAs: start) }) {
                context.insert(PeriodEvent(startDate: start, source: source, cycleRecordID: existing.id))
            }
            let latestStart = realRecords.map(\.startDate).max() ?? start
            settings.lastPeriodStartDate = calendar.startOfDay(for: max(start, latestStart))
            try? context.save()
            return existing
        }
        let previous = realRecords.filter { $0.startDate < start }.max(by: { $0.startDate < $1.startDate })
        let next = realRecords.filter { $0.startDate > start }.min(by: { $0.startDate < $1.startDate })
        if let previous {
            previous.endDate = start
            previous.status = .completed
        }
        let realPeriods = periods.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        let learned = learnedAverageCycleLength(from: realPeriods + [PeriodEvent(startDate: start)], fallback: settings.averageCycleLength, calendar: calendar)
        let learnedLuteal = learnedLutealPhaseLength(from: realRecords, fallback: settings.lutealPhaseLength, calendar: calendar)
        settings.averageCycleLength = learned
        settings.lutealPhaseLength = learnedLuteal
        let base = FertilityWindowCalculator.window(for: start, lastPeriodStart: start, averageCycleLength: learned, lutealPhaseLength: learnedLuteal, calendar: calendar)
        let cycle = CycleRecord(
            startDate: start,
            endDate: next?.startDate,
            status: next == nil ? .active : .completed,
            startSource: source,
            predictedOvulationDate: base?.predictedOvulationDate,
            expectedPeriodDate: base?.nextPeriodDate,
            averageCycleLengthAtStart: learned,
            lutealPhaseLengthAtStart: learnedLuteal
        )
        context.insert(cycle)
        if let existingPeriod = realPeriods.first(where: { calendar.isDate($0.startDate, inSameDayAs: start) }) {
            existingPeriod.cycleRecordID = cycle.id
        } else {
            context.insert(PeriodEvent(startDate: start, source: source, cycleRecordID: cycle.id))
        }
        if let latest = (realRecords + [cycle]).max(by: { $0.startDate < $1.startDate }), latest.endDate == nil {
            latest.averageCycleLengthAtStart = learned
            latest.lutealPhaseLengthAtStart = learnedLuteal
            if latest.confirmedOvulationDate == nil && latest.ovulationSource == nil {
                let refreshed = FertilityWindowCalculator.window(for: latest.startDate, lastPeriodStart: latest.startDate, averageCycleLength: learned, lutealPhaseLength: learnedLuteal, calendar: calendar)
                latest.predictedOvulationDate = refreshed?.predictedOvulationDate
                latest.expectedPeriodDate = refreshed?.nextPeriodDate
            }
        }
        AppAnalytics.log(source == .healthKit ? "linecheck_period_imported_healthkit" : "linecheck_period_logged")
        if next == nil {
            settings.lastPeriodStartDate = start
            settings.expectedPeriodDate = nil
            settings.knownOvulationDate = nil
        }
        try? context.save()
        return cycle
    }

    static func attach(_ scan: Scan, to records: [CycleRecord], calendar: Calendar = .current) {
        guard scan.cycleRecordID == nil, let cycle = cycle(containing: scan.createdAt, records: records, calendar: calendar) else { return }
        scan.cycleRecordID = cycle.id
    }

    static func applyPeakResult(from scan: Scan, records: [CycleRecord], calendar: Calendar = .current) -> CycleRecord? {
        guard scan.testType == .ovulation, scan.resultType == .peak, !scan.excludedFromCalculations,
              let cycle = cycle(containing: scan.createdAt, records: records, calendar: calendar)
        else { return nil }
        // An LH peak generally precedes ovulation; it supports an estimate but
        // does not medically confirm that ovulation occurred. Keep an explicit
        // user-confirmed date authoritative when one exists.
        let estimatedOvulation = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: scan.createdAt)) ?? scan.createdAt
        if cycle.confirmedOvulationDate == nil {
            cycle.predictedOvulationDate = estimatedOvulation
            cycle.ovulationSource = .testSupported
        }
        let authoritativeOvulation = cycle.confirmedOvulationDate ?? estimatedOvulation
        cycle.expectedPeriodDate = FertilityWindowCalculator.nextPeriod(afterOvulation: authoritativeOvulation, lutealPhaseLength: cycle.lutealPhaseLengthAtStart, calendar: calendar)
        cycle.updatedAt = .now
        scan.cycleRecordID = cycle.id
        return cycle
    }

    /// Rebuilds test-supported timing after a saved result is edited or removed.
    /// User-confirmed ovulation dates always remain authoritative.
    static func reconcileOvulationEstimates(records: [CycleRecord], scans: [Scan], calendar: Calendar = .current) {
        for cycle in records where cycle.confirmedOvulationDate == nil {
            let cycleEnd = cycle.endDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            let peaks = scans.filter { scan in
                guard scan.testType == .ovulation, scan.resultType == .peak, !scan.excludedFromCalculations else { return false }
                let day = calendar.startOfDay(for: scan.createdAt)
                return day >= calendar.startOfDay(for: cycle.startDate) && day < cycleEnd
            }
            .sorted { $0.createdAt < $1.createdAt }

            if let peak = peaks.last {
                let ovulation = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: peak.createdAt)) ?? peak.createdAt
                cycle.predictedOvulationDate = ovulation
                cycle.ovulationSource = .testSupported
                cycle.expectedPeriodDate = FertilityWindowCalculator.nextPeriod(afterOvulation: ovulation, lutealPhaseLength: cycle.lutealPhaseLengthAtStart, calendar: calendar)
            } else if cycle.ovulationSource == .testSupported {
                let baseline = FertilityWindowCalculator.window(
                    for: cycle.startDate,
                    lastPeriodStart: cycle.startDate,
                    averageCycleLength: cycle.averageCycleLengthAtStart,
                    lutealPhaseLength: cycle.lutealPhaseLengthAtStart,
                    calendar: calendar
                )
                cycle.predictedOvulationDate = baseline?.predictedOvulationDate
                cycle.expectedPeriodDate = baseline?.nextPeriodDate
                cycle.ovulationSource = nil
            }
        }
    }

    /// Places ovulation from a sustained temperature rise when nothing
    /// stronger exists. A Peak test or confirmed date always wins; a cycle
    /// whose shift disappears (a reading edited or removed) goes back to the
    /// calendar estimate. Returns the cycles that changed.
    @discardableResult
    static func reconcileTemperatureOvulation(records: [CycleRecord], logs: [DailyFertilityLog], calendar: Calendar = .current) -> [CycleRecord] {
        var changed: [CycleRecord] = []
        for cycle in records where !cycle.notes.contains("[LineCheck Screenshot Sample]") && cycle.confirmedOvulationDate == nil {
            guard cycle.ovulationSource == nil || cycle.ovulationSource == .temperatureSupported else { continue }
            if let shift = ThermalShiftDetector.detect(in: logs, from: cycle.startDate, until: cycle.endDate, calendar: calendar) {
                let ovulation = calendar.startOfDay(for: shift.estimatedOvulation)
                guard cycle.ovulationSource != .temperatureSupported || cycle.predictedOvulationDate.map({ !calendar.isDate($0, inSameDayAs: ovulation) }) ?? true else { continue }
                cycle.predictedOvulationDate = ovulation
                cycle.ovulationSource = .temperatureSupported
                cycle.expectedPeriodDate = FertilityWindowCalculator.nextPeriod(afterOvulation: ovulation, lutealPhaseLength: cycle.lutealPhaseLengthAtStart, calendar: calendar)
                changed.append(cycle)
            } else if cycle.ovulationSource == .temperatureSupported {
                let baseline = FertilityWindowCalculator.window(
                    for: cycle.startDate,
                    lastPeriodStart: cycle.startDate,
                    averageCycleLength: cycle.userSetCycleLength ?? cycle.averageCycleLengthAtStart,
                    lutealPhaseLength: cycle.lutealPhaseLengthAtStart,
                    calendar: calendar
                )
                cycle.predictedOvulationDate = baseline?.predictedOvulationDate
                cycle.expectedPeriodDate = baseline?.nextPeriodDate
                cycle.ovulationSource = nil
                changed.append(cycle)
            }
        }
        return changed
    }

}
