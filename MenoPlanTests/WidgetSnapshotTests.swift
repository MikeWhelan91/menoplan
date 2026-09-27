import XCTest
@testable import MenoPlan

final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func day(_ value: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: value)))
    }

    private func snapshot(irregular: Bool = false) throws -> WidgetSnapshot {
        WidgetSnapshot(
            cycleState: .tracking,
            cycle: .init(cycleStart: try day(1), nextPeriod: try day(29), isIrregular: irregular),
            dayPhases: [:]
        )
    }

    private func summary(_ value: Int, irregular: Bool = false) throws -> WidgetCycleSummary {
        WidgetCycleSummary.make(for: try snapshot(irregular: irregular), on: try day(value), calendar: calendar)
    }

    func testCountdownFollowsTheCycle() throws {
        let early = try summary(5)
        XCTAssertEqual(early.label, "Next period")
        XCTAssertEqual(early.headline, "In 24 Days")
        XCTAssertEqual(early.detail, "Cycle day 5")
        XCTAssertEqual(early.cycleDay, 5)

        XCTAssertEqual(try summary(28).headline, "Tomorrow")
        XCTAssertEqual(try summary(29).headline, "Due Today")
        XCTAssertEqual(try summary(31).headline, "2 Days Late")
        XCTAssertEqual(try summary(31).detail, "Cycles often vary more in perimenopause")
    }

    func testIrregularCycleSaysItIsAnEstimate() throws {
        XCTAssertTrue(try summary(5, irregular: true).detail.contains("estimate"))
    }

    func testNotSetUpAsksForALastPeriod() throws {
        let summary = WidgetCycleSummary.make(for: .empty, on: try day(5), calendar: calendar)
        XCTAssertEqual(summary.headline, "Set Up")
        XCTAssertEqual(summary.tone, .neutral)
    }

    func testTodayPlanOffersToLogALatePeriod() throws {
        let upcoming = WidgetTodayPlan.make(for: try snapshot(), on: try day(10), calendar: calendar)
        XCTAssertEqual(upcoming.phase, .upcoming)
        XCTAssertNil(upcoming.action)
        XCTAssertEqual(upcoming.stops.count, 1)

        let late = WidgetTodayPlan.make(for: try snapshot(), on: try day(33), calendar: calendar)
        XCTAssertEqual(late.phase, .periodDue)
        XCTAssertEqual(late.headline, "Period Is Late")
        XCTAssertEqual(late.action, .logPeriod)
    }
}
