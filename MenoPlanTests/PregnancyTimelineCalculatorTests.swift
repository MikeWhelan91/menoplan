import XCTest
@testable import MenoPlan

final class PregnancyTimelineCalculatorTests: XCTestCase {
    func testTimelineUsesExpectedPeriodAndKnownOvulation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28)))
        let ovulation = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 14)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24)))

        let timeline = try XCTUnwrap(PregnancyTimelineCalculator.timeline(
            for: today,
            expectedPeriodDate: expected,
            knownOvulationDate: ovulation,
            fertilityWindow: nil,
            calendar: calendar
        ))

        XCTAssertEqual(timeline.daysPastOvulation, 10)
        XCTAssertEqual(timeline.daysUntilExpectedPeriod, 4)
        XCTAssertTrue(calendar.isDate(timeline.testingWindowStartDate, inSameDayAs: today))
    }

    func testTimelineFallsBackToFertilityWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let window = try XCTUnwrap(FertilityWindowCalculator.window(
            for: today,
            lastPeriodStart: start,
            averageCycleLength: 28,
            lutealPhaseLength: 14,
            calendar: calendar
        ))

        let timeline = try XCTUnwrap(PregnancyTimelineCalculator.timeline(
            for: today,
            expectedPeriodDate: nil,
            knownOvulationDate: nil,
            fertilityWindow: window,
            calendar: calendar
        ))

        XCTAssertEqual(timeline.daysPastOvulation, 6)
        XCTAssertEqual(timeline.daysUntilExpectedPeriod, 9)
    }

    func testStaleExplicitDatesDoNotLeakIntoLaterCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oldExpected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))
        let oldOvulation = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16)))
        let currentStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31)))
        let window = try XCTUnwrap(FertilityWindowCalculator.window(for: today, lastPeriodStart: currentStart, averageCycleLength: 28, lutealPhaseLength: 14, calendar: calendar))

        let timeline = try XCTUnwrap(PregnancyTimelineCalculator.timeline(for: today, expectedPeriodDate: oldExpected, knownOvulationDate: oldOvulation, fertilityWindow: window, calendar: calendar))

        XCTAssertTrue(calendar.isDate(timeline.expectedPeriodDate, inSameDayAs: window.nextPeriodDate))
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(timeline.ovulationDate), inSameDayAs: window.predictedOvulationDate))
        XCTAssertLessThan(timeline.daysUntilExpectedPeriod, 30)
    }
}
