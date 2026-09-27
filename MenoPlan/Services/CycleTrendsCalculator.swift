import Foundation

/// The four stretches of a cycle the Trends charts group data by.
enum CyclePhaseKind: String, CaseIterable, Identifiable {
    case period, follicular, fertile, luteal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .period: "Period"
        case .follicular: "Follicular"
        case .fertile: "Fertile"
        case .luteal: "Luteal"
        }
    }
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
    let fertileStart: Int
    let fertileEnd: Int
    let ovulation: Int
    /// How ovulation was placed, when there's real evidence (confirmed date,
    /// Peak test or temperature rise); nil for a calendar estimate.
    let ovulationEvidence: TrackingDataSource?
    /// Days strictly between ovulation and the next period. Only for closed
    /// cycles with ovulation evidence - an estimate says nothing about it.
    let lutealLength: Int?
    /// Actual next period minus the forecast (positive = came later). Only
    /// for cycles LineCheck was tracking live, so backfilled history can't
    /// grade a "prediction" made after the fact.
    let predictionErrorDays: Int?
    let isCurrent: Bool

    var ovulationConfirmed: Bool { ovulationEvidence != nil }

    /// A closed cycle far shorter or longer than any real cycle - usually
    /// spotting logged as a period, or a missed period. It has no
    /// meaningful fertile days, ovulation or luteal phase.
    var isPlausible: Bool { length.map { FertilityWindowCalculator.plausibleCycleLengthRange.contains($0) } ?? true }

    func phase(atOffset offset: Int) -> CyclePhaseKind {
        if offset < periodDays { return .period }
        guard isPlausible else { return .follicular }
        if offset >= fertileStart && offset <= ovulation { return .fertile }
        if offset > ovulation { return .luteal }
        return .follicular
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
    /// For a luteal pattern: the median number of days before the period.
    let typicalDaysBeforePeriod: Int?
    var id: String { "\(kind.rawValue)-\(name)" }

    var summary: String {
        switch dominant {
        case .luteal:
            if let days = typicalDaysBeforePeriod {
                return days <= 1 ? "Usually the day before your period" : "Usually about \(days) days before your period"
            }
            return "Mostly after ovulation"
        case .period: return "Mostly during your period"
        case .fertile: return "Mostly around ovulation"
        case .follicular: return "Mostly in the days after your period"
        case nil: return "Spread across your cycle"
        }
    }
}

enum CycleTrendsCalculator {
    static let sampleMarker = "[LineCheck Screenshot Sample]"
    /// Luteal lengths outside this range are almost certainly a misplaced
    /// ovulation or period rather than a real luteal phase.
    static let plausibleLutealRange = 5...20
    /// Under this many days is worth mentioning to a doctor.
    static let shortLutealThreshold = 10

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

            let lastDay = span - 1
            let ovulation = min(max(0, days(start, window.predictedOvulationDate)), lastDay)
            let fertileStart = min(max(0, days(start, window.fertileStartDate)), ovulation)

            let hasEvidence = record.confirmedOvulationDate != nil
                || record.ovulationSource == .testSupported
                || record.ovulationSource == .temperatureSupported
            let evidence: TrackingDataSource? = hasEvidence ? (record.ovulationSource ?? .userConfirmed) : nil

            var luteal: Int?
            if hasEvidence, let length, FertilityWindowCalculator.plausibleCycleLengthRange.contains(length) {
                let value = length - ovulation - 1
                luteal = plausibleLutealRange.contains(value) ? value : nil
            }

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
                fertileStart: fertileStart,
                fertileEnd: ovulation,
                ovulation: ovulation,
                ovulationEvidence: evidence,
                lutealLength: luteal,
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

    // MARK: Luteal phase

    struct LutealSummary: Equatable {
        let lengths: [Int]
        let median: Int
        let shortCount: Int
    }

    static func lutealSummary(_ entries: [CycleHistoryEntry]) -> LutealSummary? {
        let lengths = entries.compactMap(\.lutealLength)
        guard !lengths.isEmpty else { return nil }
        let sorted = lengths.sorted()
        return LutealSummary(
            lengths: lengths,
            median: sorted[sorted.count / 2],
            shortCount: lengths.filter { $0 < shortLutealThreshold }.count
        )
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
                if phase == .luteal, let daysBefore { tally.daysBefore.append(daysBefore) }
                tallies[key] = (kind, tally)
            }
        }

        return tallies.compactMap { key, value -> SymptomTiming? in
            let tally = value.tally
            guard tally.total >= minimumLogs else { return nil }
            let top = tally.counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key.title > $1.key.title }
            let dominant = top.flatMap { Double($0.value) / Double(tally.total) >= 0.5 ? $0.key : nil }
            var typical: Int?
            if dominant == .luteal, tally.daysBefore.count >= 2 {
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
