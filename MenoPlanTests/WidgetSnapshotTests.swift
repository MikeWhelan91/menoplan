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
            dayPhases: [:], pregnancyTestDays: [], ovulationTestDays: [], latestPregnancyTest: nil, latestOvulationTest: nil
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
        XCTAssertEqual(luteal.detail, "11 DPO · you can test now")
        XCTAssertEqual(try summary(20).detail, "5 DPO")

        XCTAssertEqual(try summary(29).headline, "Due Today")
        XCTAssertEqual(try summary(31).headline, "2 Days Late")
    }

    func testPausedStatesDoNotCountDown() throws {
        var snapshot = try snapshot()
        snapshot.cycleState = .pregnant
        let summary = WidgetCycleSummary.make(for: snapshot, on: try day(20), calendar: calendar)
        XCTAssertEqual(summary.headline, "Confirmed")
        XCTAssertNil(summary.cycleDay)
        XCTAssertEqual(WidgetCycleSummary.make(for: .empty, on: try day(20), calendar: calendar).headline, "Set Up")
    }

    func testBuilderRecordsReadableTestDays() throws {
        let scans = [
            Scan(createdAt: try day(10), testType: .ovulation, testFormat: .strip, resultType: .low, analysisMode: .aiQuickCheck, imageFilename: ""),
            Scan(createdAt: try day(11), testType: .ovulation, testFormat: .strip, resultType: .invalid, analysisMode: .aiQuickCheck, imageFilename: ""),
            Scan(createdAt: try day(13), testType: .ovulation, testFormat: .strip, resultType: .high, analysisMode: .manualEnhance, imageFilename: ""),
        ]
        let settings = UserSettings()
        settings.lastPeriodStartDate = try day(1)

        let result = WidgetSnapshotService.snapshot(
            settings: settings, cycleRecords: [], periodEvents: [], scans: scans, now: try day(14), calendar: calendar
        )

        XCTAssertEqual(result.ovulationTestDays, [WidgetSnapshot.dayKey(try day(10), calendar: calendar), WidgetSnapshot.dayKey(try day(13), calendar: calendar)])
        XCTAssertTrue(result.pregnancyTestDays.isEmpty)
        XCTAssertEqual(result.latestOvulationTest?.resultRaw, "high")
        XCTAssertNil(result.latestPregnancyTest)
        XCTAssertEqual(result.cycleState, .tracking)
        XCTAssertFalse(result.dayPhases.isEmpty)
    }

    func testTodayPlanAnswersWhetherToTestToday() throws {
        var snapshot = try snapshot()
        func plan(_ value: Int) throws -> WidgetTodayPlan {
            WidgetTodayPlan.make(for: snapshot, on: try day(value), calendar: calendar)
        }

        // Before the OPK window: nothing to do, and no button pushing a test.
        let early = try plan(4)
        XCTAssertEqual(early.phase, .beforeTesting)
        XCTAssertEqual(early.headline, "No Test Needed Today")
        XCTAssertNil(early.action)
        XCTAssertEqual(early.stops.map(\.title), ["Ovulation Tests Start", "Fertile Days Begin", "Likely Ovulation"])
        XCTAssertEqual(try plan(7).headline, "Start Ovulation Tests Tomorrow")

        // OPK window: prompt a test, and count the days already tested.
        snapshot.ovulationTestDays = [WidgetSnapshot.dayKey(try day(8), calendar: calendar)]
        let testing = try plan(10)
        XCTAssertEqual(testing.headline, "Take Today's Ovulation Test")
        XCTAssertEqual(testing.detail, "Ovulation estimated in 5 days · Tested 1 of the last 2 days")
        XCTAssertEqual(testing.action, .ovulationTest)

        snapshot.latestOvulationTest = .init(date: try day(13), resultRaw: "peak")
        let surge = try plan(13)
        XCTAssertEqual(surge.headline, "Ovulation Is Close")
        XCTAssertTrue(surge.isDone)
        XCTAssertNil(surge.action)

        // After ovulation: too early -> test from tomorrow -> can test.
        let tww = try plan(20)
        XCTAssertEqual(tww.headline, "Too Early to Test")
        XCTAssertTrue(tww.detail.hasPrefix("About 5 DPO"))
        XCTAssertNil(tww.action)
        XCTAssertEqual(try plan(24).headline, "Test from Tomorrow")
        XCTAssertEqual(try plan(25).headline, "You Can Test Today")
        XCTAssertEqual(try plan(25).action, .pregnancyTest)
        XCTAssertEqual(tww.stops.map(\.title), ["Earliest Pregnancy Test", "Period Due"])

        // A test-confirmed ovulation drops the "About" hedge.
        snapshot.cycle?.ovulationConfirmed = true
        XCTAssertTrue(try plan(20).detail.hasPrefix("5 DPO"))

        snapshot.latestPregnancyTest = .init(date: try day(26), resultRaw: "faintLineDetected")
        let faint = try plan(26)
        XCTAssertEqual(faint.headline, "Faint Line Today")
        XCTAssertTrue(faint.isDone)

        let late = try plan(31)
        XCTAssertEqual(late.phase, .periodDue)
        XCTAssertEqual(late.label, "Period 2 days late")
        XCTAssertEqual(late.headline, "Take a Pregnancy Test")

        // A widened (irregular) fertile range keeps ovulation testing going
        // after the estimate until it ends, matching Home.
        var widened = try self.snapshot()
        widened.cycle?.fertileEnd = try day(18)
        let wide = WidgetTodayPlan.make(for: widened, on: try day(17), calendar: calendar)
        XCTAssertEqual(wide.phase, .ovulationTesting)
        XCTAssertEqual(wide.label, "Possible fertile days")
        XCTAssertEqual(WidgetTodayPlan.make(for: widened, on: try day(19), calendar: calendar).phase, .twoWeekWait)

        snapshot.cycleState = .notSetUp
        XCTAssertEqual(try plan(10).phase, .idle)
    }
}
