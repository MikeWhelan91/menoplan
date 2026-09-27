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

}
