import XCTest
@testable import MenoPlan

final class MenopauseDailyLogTests: XCTestCase {
    func testFlushCountsMakeADayLogged() {
        let log = DailyFertilityLog(date: .now)
        XCTAssertFalse(log.hasContent)
        log.hotFlushCount = 2
        XCTAssertTrue(log.hasContent)
    }

    func testSleepAndHRTMakeADayLogged() {
        let sleep = DailyFertilityLog(date: .now)
        sleep.sleepQuality = .broken
        XCTAssertTrue(sleep.hasContent)

        let hrt = DailyFertilityLog(date: .now)
        hrt.hrtTaken = ["Oestrogen Gel", "Progesterone"]
        XCTAssertTrue(hrt.hasContent)
        XCTAssertEqual(hrt.hrtTaken, ["Oestrogen Gel", "Progesterone"])
    }

    func testVasomotorSummaryReadsNaturally() {
        let log = DailyFertilityLog(date: .now)
        XCTAssertNil(log.vasomotorSummary)

        log.hotFlushCount = 1
        XCTAssertEqual(log.vasomotorSummary, "1 hot flush")

        log.hotFlushCount = 3
        log.nightSweatCount = 2
        log.vasomotorSeverity = .moderate
        XCTAssertEqual(log.vasomotorSummary, "3 hot flushes · 2 night sweats · Moderate")
    }

    func testZeroCountsAreNotASummary() {
        let log = DailyFertilityLog(date: .now)
        log.hotFlushCount = 0
        log.vasomotorSeverity = .mild
        XCTAssertNil(log.vasomotorSummary)
    }

    func testHRTRegimenRoundTrips() {
        let settings = UserSettings()
        XCTAssertEqual(settings.hrtRegimen, [])
        XCTAssertNil(settings.hrtRegimenRaw)

        settings.hrtRegimen = ["Oestrogen Patch", "Progesterone"]
        XCTAssertEqual(settings.hrtRegimen, ["Oestrogen Patch", "Progesterone"])

        settings.hrtRegimen = []
        XCTAssertNil(settings.hrtRegimenRaw)
    }

    func testBleedingLeadsTheLogOnlyWhilePeriodsAreTracked() {
        XCTAssertEqual(DailyLogSection.ordered(for: .perimenopause).first, .flow)
        XCTAssertEqual(DailyLogSection.ordered(for: .postmenopause).first, .flushes)
        XCTAssertEqual(DailyLogSection.ordered(for: .unsure).first, .flushes)
        for stage in MenopauseStage.allCases {
            XCTAssertEqual(Set(DailyLogSection.ordered(for: stage)), Set(DailyLogSection.allCases))
        }
    }
}

final class MenopauseSummaryCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!)!
    }

    func testSteadyCycles() {
        let summary = CycleChangeCalculator.summary(periodStarts: [day(-84), day(-56), day(-28), day(0)], on: day(3), calendar: calendar)
        XCTAssertEqual(summary.recentCycleLengths, [28, 28, 28])
        XCTAssertFalse(summary.hasNoticeableChange)
        XCTAssertFalse(summary.hasLongGap)
        XCTAssertEqual(summary.daysSinceLastPeriod, 3)
        XCTAssertNil(summary.twelveMonthProgress)
        XCTAssertTrue(summary.headline.contains("steady"))
    }

    func testSevenDayChangeBetweenConsecutiveCycles() {
        let summary = CycleChangeCalculator.summary(periodStarts: [day(-63), day(-35), day(0)], on: day(1), calendar: calendar)
        XCTAssertEqual(summary.recentCycleLengths, [28, 35])
        XCTAssertTrue(summary.hasNoticeableChange)
    }

    func testDuplicateStartsAreOneBleed() {
        let summary = CycleChangeCalculator.summary(periodStarts: [day(-28), day(-26), day(0)], on: day(0), calendar: calendar)
        XCTAssertEqual(summary.recentCycleLengths, [28])
    }

    func testLongWaitCountsTowardsTwelveMonths() {
        let summary = CycleChangeCalculator.summary(periodStarts: [day(-150)], on: day(0), calendar: calendar)
        XCTAssertTrue(summary.hasLongGap)
        XCTAssertEqual(summary.twelveMonthProgress ?? 0, 150.0 / 365.0, accuracy: 0.001)
        XCTAssertFalse(summary.reachedTwelveMonths)

        let year = CycleChangeCalculator.summary(periodStarts: [day(-400)], on: day(0), calendar: calendar)
        XCTAssertTrue(year.reachedTwelveMonths)
        XCTAssertEqual(year.twelveMonthProgress, 1)
    }

    private func log(_ offset: Int, flushes: Int? = nil, sleep: SleepQuality? = nil, symptoms: [String] = []) -> DailyFertilityLog {
        let log = DailyFertilityLog(date: day(offset), symptoms: symptoms)
        log.hotFlushCount = flushes
        log.sleepQuality = sleep
        return log
    }

    func testSymptomWeekComparesWithTheWeekBefore() {
        let logs = [
            log(0, flushes: 2, sleep: .poor, symptoms: ["Brain Fog"]),
            log(-3, flushes: 1, symptoms: ["Brain Fog", "Joint Pain"]),
            log(-8, flushes: 6)
        ]
        logs[0].nightSweatCount = 1
        let week = SymptomWeekCalculator.summary(logs: logs, on: day(0), calendar: calendar)
        XCTAssertEqual(week.hotFlushes, 3)
        XCTAssertEqual(week.previousHotFlushes, 6)
        XCTAssertEqual(week.nightSweats, 1)
        XCTAssertEqual(week.previousNightSweats, 0)
        XCTAssertEqual(week.badSleepNights, 1)
        XCTAssertEqual(week.loggedDays, 2)
        XCTAssertEqual(week.topSymptoms, ["Brain Fog", "Joint Pain"])
    }

    func testEmptyWeekAsksForALog() {
        let week = SymptomWeekCalculator.summary(logs: [], on: day(0), calendar: calendar)
        XCTAssertTrue(week.isEmpty)
        XCTAssertNil(week.previousHotFlushes)
        XCTAssertNil(week.previousNightSweats)
    }
}
