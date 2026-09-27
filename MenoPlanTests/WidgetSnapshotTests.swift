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

    private func snapshot() throws -> WidgetSnapshot {
        WidgetSnapshot(
            cycleState: .tracking,
            cycle: .init(
                cycleStart: try day(1), opkStart: try day(8), fertileStart: try day(10), fertileEnd: try day(15),
                ovulation: try day(15), nextPeriod: try day(29), isIrregular: false, ovulationConfirmed: false
            ),
            dayPhases: [:], ovulationTestDays: [], latestOvulationTest: nil
        )
    }

    func testCountdownFollowsTheCycle() throws {
        let snapshot = try snapshot()
        func summary(_ value: Int) throws -> WidgetCycleSummary {
            WidgetCycleSummary.make(for: snapshot, on: try day(value), calendar: calendar)
        }

        let early = try summary(3)
        XCTAssertEqual(early.label, "Fertile window")
        XCTAssertEqual(early.headline, "In 7 Days")
        XCTAssertEqual(early.cycleDay, 3)

        XCTAssertEqual(try summary(9).headline, "Tomorrow")
        XCTAssertEqual(try summary(9).detail, "Time to start ovulation tests")

        let fertile = try summary(12)
        XCTAssertEqual(fertile.label, "Ovulation")
        XCTAssertEqual(fertile.headline, "In 3 Days")
        XCTAssertEqual(fertile.tone, .fertile)

        XCTAssertEqual(try summary(15).headline, "Today")
        XCTAssertEqual(try summary(15).tone, .ovulation)

        let luteal = try summary(26)
        XCTAssertEqual(luteal.label, "Period")
        XCTAssertEqual(luteal.headline, "In 3 Days")
        XCTAssertEqual(luteal.daysPastOvulation, 11)
        XCTAssertEqual(luteal.detail, "11 DPO")
        XCTAssertEqual(try summary(20).detail, "5 DPO")

        XCTAssertEqual(try summary(29).headline, "Due Today")
        XCTAssertEqual(try summary(31).headline, "2 Days Late")
    }

}
