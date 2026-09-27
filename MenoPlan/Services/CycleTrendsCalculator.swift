import Foundation

/// The stretches of a cycle the Trends charts group data by. Hormones swing
/// most around a period in perimenopause, so the week before one is kept
/// apart from the rest of the cycle.
enum CyclePhaseKind: String, CaseIterable, Identifiable {
    case period, between, beforePeriod
    var id: String { rawValue }

    var title: String {
        switch self {
        case .period: "Period"
        case .between: "Between periods"
        case .beforePeriod: "Week before period"
        }
    }

    /// Days before the next period that count as "the week before".
    static let beforePeriodDays = 7
}

/// One cycle as the Trends page draws it. Offsets are zero-based days from
/// the cycle's first period day; dates come from the same window the
/// calendar uses, so the two never disagree.
struct CycleHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let start: Date
    /// Days until the next period started; nil while the cycle is running.
    let length: Int?
    /// Days drawn for the row: the full length, or for the current cycle the
    /// later of today and the expected next period.
    let span: Int
    /// Days so far, for the current cycle.
    let elapsed: Int
    let periodDays: Int
    /// Actual next period minus the forecast (positive = came later). Only
    /// for cycles LineCheck was tracking live, so backfilled history can't
    /// grade a "prediction" made after the fact.
    let predictionErrorDays: Int?
    let isCurrent: Bool

    /// A closed cycle far shorter or longer than any real cycle - usually
    /// spotting logged as a period, or a missed period.
    var isPlausible: Bool { length.map { FertilityWindowCalculator.plausibleCycleLengthRange.contains($0) } ?? true }

    func phase(atOffset offset: Int) -> CyclePhaseKind {
        if offset < periodDays { return .period }
        guard isPlausible else { return .between }
        return offset >= span - CyclePhaseKind.beforePeriodDays ? .beforePeriod : .between
    }
}

/// When in the cycle a symptom or mood tends to be logged.
struct SymptomTiming: Identifiable, Equatable {
    enum Kind: String { case symptom, mood }

    let name: String
    let kind: Kind
    let counts: [CyclePhaseKind: Int]
    let total: Int
    /// The phase holding at least half the logs, if any.
    let dominant: CyclePhaseKind?
    /// For a week-before-period pattern: the median number of days before it.
    let typicalDaysBeforePeriod: Int?
    var id: String { "\(kind.rawValue)-\(name)" }

    var summary: String {
        switch dominant {
        case .beforePeriod:
            if let days = typicalDaysBeforePeriod {
                return days <= 1 ? "Usually the day before your period" : "Usually about \(days) days before your period"
            }
            return "Mostly in the week before your period"
        case .period: return "Mostly during your period"
        case .between: return "Mostly between periods"
        case nil: return "Spread across your cycle"
        }
    }
}

enum CycleTrendsCalculator {
    static let sampleMarker = "[LineCheck Screenshot Sample]"

    static func history(
        records: [CycleRecord],
        periods: [PeriodEvent],
        settings: UserSettings?,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [CycleHistoryEntry] {
        let realRecords = records.filter { !$0.notes.contains(sampleMarker) }.sorted { $0.startDate < $1.startDate }
        let realPeriods = periods.filter { !$0.notes.contains(sampleMarker) }
        let day = calendar.startOfDay(for: today)
        func days(_ from: Date, _ to: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
        }

        return realRecords.compactMap { record -> CycleHistoryEntry? in
            let start = calendar.startOfDay(for: record.startDate)
            guard start <= day,
                  let window = CycleTrackingService.window(for: start, records: realRecords, periods: realPeriods, settings: settings, calendar: calendar)
            else { return nil }

            let length = record.endDate.map { days(start, $0) }.flatMap { $0 > 0 ? $0 : nil }
            let isCurrent = length == nil
            let elapsed = days(start, day) + 1
            let expected = max(1, days(start, window.nextPeriodDate))
            let span = length ?? max(elapsed, expected)

            let drawnPeriod: Int = {
                guard let event = CycleTrackingService.periodEvent(containing: start, in: realPeriods, calendar: calendar) else {
                    return window.periodLength
                }
                let first = calendar.startOfDay(for: event.startDate)
                let last = event.endDate.map { calendar.startOfDay(for: $0) } ?? (calendar.date(byAdding: .day, value: 4, to: first) ?? first)
                return days(first, last) + 1
            }()
            let periodDays = min(max(1, drawnPeriod), span)

            var predictionError: Int?
            // A cycle of implausible length is a logging gap or a stray entry,
            // not a forecast that missed.
            if let end = record.endDate, let forecast = record.expectedPeriodDate, record.createdAt < end,
               let length, FertilityWindowCalculator.plausibleCycleLengthRange.contains(length) {
                let error = days(forecast, end)
                predictionError = abs(error) <= 30 ? error : nil
            }

            return CycleHistoryEntry(
                id: record.id,
                start: start,
                length: length,
                span: span,
                elapsed: min(elapsed, span),
                periodDays: periodDays,
                predictionErrorDays: predictionError,
                isCurrent: isCurrent
            )
        }
    }

    /// The cycle a date falls in, with its zero-based offset.
    static func locate(_ date: Date, in entries: [CycleHistoryEntry], calendar: Calendar = .current) -> (entry: CycleHistoryEntry, offset: Int)? {
        let day = calendar.startOfDay(for: date)
        for entry in entries.reversed() where entry.start <= day {
            let offset = calendar.dateComponents([.day], from: entry.start, to: day).day ?? 0
            let limit = entry.isCurrent ? entry.elapsed : entry.span
            return offset < limit ? (entry, offset) : nil
        }
        return nil
    }

    // MARK: Prediction accuracy

    struct AccuracySummary: Equatable {
        let count: Int
        let withinOneDay: Int
        let withinThreeDays: Int
        let averageMissDays: Double
    }

    static func accuracySummary(_ entries: [CycleHistoryEntry], recent: Int = 6) -> AccuracySummary? {
        let errors = entries.compactMap(\.predictionErrorDays).suffix(recent)
        guard !errors.isEmpty else { return nil }
        let misses = errors.map { abs($0) }
        return AccuracySummary(
            count: errors.count,
            withinOneDay: misses.filter { $0 <= 1 }.count,
            withinThreeDays: misses.filter { $0 <= 3 }.count,
            averageMissDays: Double(misses.reduce(0, +)) / Double(misses.count)
        )
    }

    // MARK: Period length

    /// Average length of periods with a logged end date.
    static func averagePeriodLength(_ periods: [PeriodEvent], recent: Int = 6, calendar: Calendar = .current) -> Int? {
        let lengths = periods
            .filter { !$0.notes.contains(sampleMarker) }
            .sorted { $0.startDate < $1.startDate }
            .compactMap { period -> Int? in
                guard let end = period.endDate else { return nil }
                let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: period.startDate), to: calendar.startOfDay(for: end)).day ?? -1) + 1
                return FertilityWindowCalculator.plausiblePeriodLengthRange.contains(days) ? days : nil
            }
            .suffix(recent)
        guard !lengths.isEmpty else { return nil }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    // MARK: Symptom timing

    static func symptomTiming(
        logs: [DailyFertilityLog],
        entries: [CycleHistoryEntry],
        minimumLogs: Int = 3,
        calendar: Calendar = .current
    ) -> [SymptomTiming] {
        struct Tally { var counts: [CyclePhaseKind: Int] = [:]; var total = 0; var daysBefore: [Int] = [] }
        var tallies: [String: (kind: SymptomTiming.Kind, tally: Tally)] = [:]

        for log in logs where !log.notes.contains(sampleMarker) {
            guard let (entry, offset) = locate(log.date, in: entries, calendar: calendar) else { continue }
            let phase = entry.phase(atOffset: offset)
            let daysBefore = entry.length.map { $0 - offset }
            let items = log.symptoms.map { ($0, SymptomTiming.Kind.symptom) } + log.moods.map { ($0, SymptomTiming.Kind.mood) }
            for (name, kind) in items {
                let key = "\(kind.rawValue)|\(name)"
                var tally = tallies[key]?.tally ?? Tally()
                tally.counts[phase, default: 0] += 1
                tally.total += 1
                if phase == .beforePeriod, let daysBefore { tally.daysBefore.append(daysBefore) }
                tallies[key] = (kind, tally)
            }
        }

        return tallies.compactMap { key, value -> SymptomTiming? in
            let tally = value.tally
            guard tally.total >= minimumLogs else { return nil }
            let top = tally.counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key.title > $1.key.title }
            let dominant = top.flatMap { Double($0.value) / Double(tally.total) >= 0.5 ? $0.key : nil }
            var typical: Int?
            if dominant == .beforePeriod, tally.daysBefore.count >= 2 {
                let sorted = tally.daysBefore.sorted()
                typical = sorted[sorted.count / 2]
            }
            return SymptomTiming(
                name: String(key.split(separator: "|", maxSplits: 1).last ?? ""),
                kind: value.kind,
                counts: tally.counts,
                total: tally.total,
                dominant: dominant,
                typicalDaysBeforePeriod: typical
            )
        }
        .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
    }

    // MARK: Body metrics by phase

    struct PhaseAverage: Equatable {
        let phase: CyclePhaseKind
        let value: Double
        let count: Int
    }

    static func phaseAverages(
        _ values: [(date: Date, value: Double)],
        entries: [CycleHistoryEntry],
        calendar: Calendar = .current
    ) -> [PhaseAverage] {
        var buckets: [CyclePhaseKind: [Double]] = [:]
        for item in values {
            guard let (entry, offset) = locate(item.date, in: entries, calendar: calendar) else { continue }
            buckets[entry.phase(atOffset: offset), default: []].append(item.value)
        }
        return CyclePhaseKind.allCases.compactMap { phase in
            guard let list = buckets[phase], !list.isEmpty else { return nil }
            return PhaseAverage(phase: phase, value: list.reduce(0, +) / Double(list.count), count: list.count)
        }
    }

    /// One cycle's readings by cycle day, for a line over phase bands.
    static func cycleDaySeries(
        _ values: [(date: Date, value: Double)],
        entry: CycleHistoryEntry,
        calendar: Calendar = .current
    ) -> [(offset: Int, value: Double)] {
        values.compactMap { item in
            let offset = calendar.dateComponents([.day], from: entry.start, to: calendar.startOfDay(for: item.date)).day ?? -1
            let limit = entry.isCurrent ? entry.elapsed : entry.span
            return (0..<limit).contains(offset) ? (offset, item.value) : nil
        }
        .sorted { $0.offset < $1.offset }
    }
}
