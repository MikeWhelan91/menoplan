import XCTest
@testable import MenoPlan

final class CycleTrendsCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private func day(_ month: Int, _ value: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: value)))
    }

    /// Three cycles: 1 Jul (28 days, Peak-confirmed ovulation 14 Jul),
    /// 29 Jul (30 days, estimate only), 28 Aug (current).
    private func fixture() throws -> (records: [CycleRecord], periods: [PeriodEvent]) {
        let first = CycleRecord(startDate: try day(7, 1), endDate: try day(7, 29), status: .completed,
                                predictedOvulationDate: try day(7, 14), ovulationSource: .testSupported,
                                expectedPeriodDate: try day(7, 28), averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        first.createdAt = try day(7, 1)
        let second = CycleRecord(startDate: try day(7, 29), endDate: try day(8, 28), status: .completed,
                                 expectedPeriodDate: try day(8, 26), averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        // Backfilled after it ended: its forecast must not be graded.
        second.createdAt = try day(9, 1)
        let current = CycleRecord(startDate: try day(8, 28), averageCycleLengthAtStart: 29, lutealPhaseLengthAtStart: 14)
        let periods = [
            PeriodEvent(startDate: try day(7, 1), endDate: try day(7, 5)),
            PeriodEvent(startDate: try day(7, 29), endDate: try day(8, 1)),
            PeriodEvent(startDate: try day(8, 28), endDate: try day(9, 1)),
        ]
        return ([first, second, current], periods)
    }

    func testHistoryDrawsEachCycleWithEvidenceAndLuteal() throws {
        let (records, periods) = try fixture()
        let entries = CycleTrendsCalculator.history(records: records, periods: periods, settings: nil, today: try day(9, 5), calendar: calendar)
        XCTAssertEqual(entries.count, 3)

        let first = entries[0]
        XCTAssertEqual(first.length, 28)
        XCTAssertEqual(first.periodDays, 5)
        XCTAssertEqual(first.ovulation, 13)
        XCTAssertTrue(first.ovulationConfirmed)
        XCTAssertEqual(first.lutealLength, 14, "28-day cycle, ovulation day 14 -> 14 days before the next period")
        XCTAssertEqual(first.predictionErrorDays, 1, "Forecast 28 Jul, period came 29 Jul")

        let second = entries[1]
        XCTAssertEqual(second.length, 30)
        XCTAssertEqual(second.periodDays, 4)
        XCTAssertFalse(second.ovulationConfirmed)
        XCTAssertNil(second.lutealLength, "An estimated ovulation says nothing about the luteal phase")
        XCTAssertNil(second.predictionErrorDays, "Backfilled cycles weren't predicted live")

        let current = entries[2]
        XCTAssertTrue(current.isCurrent)
        XCTAssertNil(current.length)
        XCTAssertEqual(current.elapsed, 9)
        XCTAssertGreaterThanOrEqual(current.span, current.elapsed)
    }

    func testSummaries() throws {
        let (records, periods) = try fixture()
        let entries = CycleTrendsCalculator.history(records: records, periods: periods, settings: nil, today: try day(9, 5), calendar: calendar)
        XCTAssertEqual(CycleTrendsCalculator.lutealSummary(entries)?.median, 14)
        XCTAssertEqual(CycleTrendsCalculator.lutealSummary(entries)?.shortCount, 0)
        let accuracy = try XCTUnwrap(CycleTrendsCalculator.accuracySummary(entries))
        XCTAssertEqual(accuracy.count, 1)
        XCTAssertEqual(accuracy.withinOneDay, 1)
        XCTAssertEqual(CycleTrendsCalculator.averagePeriodLength(periods, calendar: calendar), 5)
    }

    func testImplausibleCycleIsNotGradedOrGivenPhases() throws {
        // A stray period five days in splits the cycle; that's not a forecast
        // that was 24 days early, and there's no ovulation to draw.
        let split = CycleRecord(startDate: try day(8, 27), endDate: try day(9, 1), status: .completed, expectedPeriodDate: try day(9, 25))
        split.createdAt = try day(8, 27)
        let entries = CycleTrendsCalculator.history(records: [split], periods: [PeriodEvent(startDate: try day(8, 27), endDate: try day(8, 30))], settings: nil, today: try day(9, 5), calendar: calendar)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertNil(entry.predictionErrorDays)
        XCTAssertFalse(entry.isPlausible)
        XCTAssertNil(entry.lutealLength)
        XCTAssertEqual(entry.phase(atOffset: 4), .follicular)
    }

    func testShortLutealPhaseIsCounted() throws {
        let cycle = CycleRecord(startDate: try day(7, 1), endDate: try day(7, 26), status: .completed,
                                confirmedOvulationDate: try day(7, 17), ovulationSource: .userConfirmed)
        let entries = CycleTrendsCalculator.history(records: [cycle], periods: [PeriodEvent(startDate: try day(7, 1), endDate: try day(7, 4))], settings: nil, today: try day(8, 1), calendar: calendar)
        XCTAssertEqual(entries.first?.lutealLength, 8)
        XCTAssertEqual(CycleTrendsCalculator.lutealSummary(entries)?.shortCount, 1)
    }

    func testSymptomTimingFindsThePremenstrualPattern() throws {
        let (records, periods) = try fixture()
        let entries = CycleTrendsCalculator.history(records: records, periods: periods, settings: nil, today: try day(9, 5), calendar: calendar)
        let logs = [
            DailyFertilityLog(date: try day(7, 26), symptoms: ["Cramps"]),
            DailyFertilityLog(date: try day(7, 27), symptoms: ["Cramps"]),
            DailyFertilityLog(date: try day(8, 26), symptoms: ["Cramps"]),
            DailyFertilityLog(date: try day(7, 2), symptoms: ["Headache"]),
            DailyFertilityLog(date: try day(7, 14), symptoms: ["Headache"]),
            DailyFertilityLog(date: try day(8, 20), symptoms: ["Headache"]),
            DailyFertilityLog(date: try day(8, 30), symptoms: ["Once"]),
        ]
        let timing = CycleTrendsCalculator.symptomTiming(logs: logs, entries: entries, calendar: calendar)
        XCTAssertEqual(timing.map(\.name).sorted(), ["Cramps", "Headache"], "Needs at least three logs")
        let cramps = try XCTUnwrap(timing.first { $0.name == "Cramps" })
        XCTAssertEqual(cramps.dominant, .luteal)
        XCTAssertEqual(cramps.typicalDaysBeforePeriod, 2)
        XCTAssertEqual(cramps.summary, "Usually about 2 days before your period")
        let headache = try XCTUnwrap(timing.first { $0.name == "Headache" })
        XCTAssertNil(headache.dominant)
        XCTAssertEqual(headache.summary, "Spread across your cycle")
    }

    func testPhaseAveragesGroupReadings() throws {
        let (records, periods) = try fixture()
        let entries = CycleTrendsCalculator.history(records: records, periods: periods, settings: nil, today: try day(9, 5), calendar: calendar)
        let readings: [(date: Date, value: Double)] = [
            (try day(7, 3), 58), (try day(7, 8), 58), (try day(7, 20), 62), (try day(7, 24), 64),
        ]
        let averages = CycleTrendsCalculator.phaseAverages(readings, entries: entries, calendar: calendar)
        XCTAssertEqual(averages.first { $0.phase == .luteal }?.value, 63)
        XCTAssertEqual(averages.first { $0.phase == .period }?.count, 1)
        let series = CycleTrendsCalculator.cycleDaySeries(readings, entry: entries[0], calendar: calendar)
        XCTAssertEqual(series.map(\.offset), [2, 7, 19, 23])
    }
}
