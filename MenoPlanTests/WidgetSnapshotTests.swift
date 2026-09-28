import XCTest
@testable import MenoPlan

final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func day(_ value: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: value)))
    }

    private func snapshot(tracksCycle: Bool = true, lastPeriod: Int? = 1, logged: [Int] = []) throws -> WidgetSnapshot {
        WidgetSnapshot(
            isSetUp: true,
            tracksCycle: tracksCycle,
            lastPeriodStart: try lastPeriod.map { try day($0) },
            periodDays: [],
            loggedDays: Set(try logged.map { WidgetSnapshot.dayKey(try day($0), calendar: calendar) }),
            focus: ["Sleep", "Anxiety", "Brain Fog", "Joint Pain"]
        )
    }

    func testCountsFromTheLastPeriodWithoutPredicting() throws {
        let summary = WidgetCycleSummary.make(for: try snapshot(), on: try day(21), calendar: calendar)
        XCTAssertEqual(summary.state, .sinceLastPeriod)
        XCTAssertEqual(summary.headline, "20 Days Ago")
        XCTAssertEqual(summary.inline, "Last period 20 days ago")
        XCTAssertEqual(summary.circularValue, "20")

        // Long gaps just keep counting - never "late".
        let later = WidgetCycleSummary.make(for: try snapshot(), on: try day(30), calendar: calendar)
        XCTAssertFalse(later.headline.localizedCaseInsensitiveContains("late"))
        XCTAssertEqual(WidgetCycleSummary.make(for: try snapshot(), on: try day(1), calendar: calendar).headline, "Today")
    }

    func testWithoutPeriodsItShowsTheMonthsLog() throws {
        let summary = WidgetCycleSummary.make(for: try snapshot(tracksCycle: false, lastPeriod: nil, logged: [2, 5, 20, 21]), on: try day(20), calendar: calendar)
        XCTAssertEqual(summary.state, .logging)
        XCTAssertEqual(summary.headline, "3 Days Logged", "A future-dated key never counts")
        XCTAssertEqual(summary.detail, "Checked in today")
    }

    func testSetupStates() throws {
        XCTAssertEqual(WidgetCycleSummary.make(for: .empty, on: try day(5), calendar: calendar).state, .notSetUp)
        XCTAssertEqual(WidgetCycleSummary.make(for: try snapshot(lastPeriod: nil), on: try day(5), calendar: calendar).state, .needsPeriod)
    }

    func testCheckInShowsTodayAndTheLastSevenDays() throws {
        let notYet = WidgetCheckIn.make(for: try snapshot(logged: [18, 19]), on: try day(20), calendar: calendar)
        XCTAssertFalse(notYet.loggedToday)
        XCTAssertEqual(notYet.headline, "How's Today?")
        XCTAssertEqual(notYet.detail, "Sleep · Anxiety · Brain Fog")
        XCTAssertEqual(notYet.week.count, 7)
        XCTAssertEqual(notYet.week.map(\.logged), [false, false, false, false, true, true, false])

        let done = WidgetCheckIn.make(for: try snapshot(logged: [20]), on: try day(20), calendar: calendar)
        XCTAssertTrue(done.loggedToday)
        XCTAssertEqual(done.headline, "Logged Today")
    }

    func testDayKeysRoundTrip() throws {
        let key = WidgetSnapshot.dayKey(try day(7), calendar: calendar)
        XCTAssertEqual(key, "2026-09-07")
        XCTAssertEqual(WidgetCheckIn.date(fromKey: key, calendar: calendar), try day(7))
    }
}
