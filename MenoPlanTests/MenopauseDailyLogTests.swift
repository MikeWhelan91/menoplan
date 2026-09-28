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
        func index(_ section: DailyLogSection, _ stage: MenopauseStage) -> Int {
            DailyLogSection.ordered(for: stage).firstIndex(of: section) ?? -1
        }
        for stage in MenopauseStage.allCases {
            XCTAssertEqual(DailyLogSection.ordered(for: stage).first, .day)
        }
        XCTAssertLessThan(index(.flow, .perimenopause), index(.symptoms, .perimenopause))
        XCTAssertGreaterThan(index(.flow, .postmenopause), index(.symptoms, .postmenopause))
        XCTAssertGreaterThan(index(.flow, .unsure), index(.symptoms, .unsure))
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

    private func log(_ offset: Int, sleep: SleepQuality? = nil, symptoms: [String] = [], impact: DayImpact? = nil) -> DailyFertilityLog {
        let log = DailyFertilityLog(date: day(offset), symptoms: symptoms)
        log.sleepQuality = sleep
        log.dayImpact = impact
        return log
    }

    func testTappingASymptomStepsThroughSeverity() {
        let log = DailyFertilityLog(date: day(0))
        FocusSymptoms.advance("Brain Fog", in: log)
        XCTAssertEqual(log.severity(of: "Brain Fog"), .mild)
        XCTAssertTrue(log.symptoms.contains("Brain Fog"))
        FocusSymptoms.advance("Brain Fog", in: log)
        FocusSymptoms.advance("Brain Fog", in: log)
        XCTAssertEqual(log.severity(of: "Brain Fog"), .severe)
        FocusSymptoms.advance("Brain Fog", in: log)
        XCTAssertNil(log.severity(of: "Brain Fog"))
        XCTAssertFalse(log.symptoms.contains("Brain Fog"))
        XCTAssertEqual(log.symptomSeverityRaw, "")
    }

    func testSleepAndCountersUseTheirOwnFields() {
        let log = DailyFertilityLog(date: day(0))
        FocusSymptoms.advance(FocusSymptoms.sleep, in: log)
        XCTAssertEqual(log.sleepQuality, .good)
        XCTAssertFalse(FocusSymptoms.isPresent(FocusSymptoms.sleep, in: log))
        FocusSymptoms.advance(FocusSymptoms.sleep, in: log)
        XCTAssertTrue(FocusSymptoms.isPresent(FocusSymptoms.sleep, in: log))

        FocusSymptoms.advance(FocusSymptoms.hotFlushes, in: log)
        FocusSymptoms.advance(FocusSymptoms.hotFlushes, in: log)
        XCTAssertEqual(log.hotFlushCount, 2)
        FocusSymptoms.setCount(0, for: FocusSymptoms.hotFlushes, in: log)
        XCTAssertNil(log.hotFlushCount)
    }

    func testFocusSymptomsDefaultUntilChosenAndCapAtFive() {
        let settings = UserSettings()
        XCTAssertFalse(settings.hasChosenFocusSymptoms)
        XCTAssertEqual(settings.focusSymptoms, FocusSymptoms.defaults)
        XCTAssertFalse(FocusSymptoms.defaults.first == FocusSymptoms.hotFlushes)
        settings.focusSymptoms = ["A", "B", "C", "D", "E", "F"]
        XCTAssertEqual(settings.focusSymptoms.count, 5)
        XCTAssertTrue(settings.hasChosenFocusSymptoms)
    }

    func testNoObservationUntilEnoughDaysAreLogged() {
        let logs = (0..<6).map { log(-$0, symptoms: ["Brain Fog"]) }
        XCTAssertNil(RecentChangeCalculator.observation(logs: logs, focus: ["Brain Fog"], on: day(0), calendar: calendar))
    }

    func testObservationComparesWithTheFortnightBefore() {
        // Days without brain fog are still logged ("not at all"), so they count.
        let recent = (0..<10).map { log(-$0, symptoms: $0 < 8 ? ["Brain Fog"] : [], impact: .notAtAll) }
        let earlier = (14..<24).map { log(-$0, symptoms: $0 < 16 ? ["Brain Fog"] : [], impact: .notAtAll) }
        let change = RecentChangeCalculator.observation(
            logs: recent + earlier, focus: ["Anxiety", "Brain Fog"],
            hrtChanged: day(-12), on: day(0), calendar: calendar
        )
        XCTAssertEqual(change?.title, "Brain fog on 8 of your last 10 logged days, up from 2 the fortnight before.")
        XCTAssertEqual(change?.detail, "You changed your HRT 12 days ago.")
    }

    func testObservationFallsBackToTheMostCommonSymptom() {
        let logs = (0..<8).map { log(-$0, sleep: $0 < 5 ? .poor : .good) }
        let change = RecentChangeCalculator.observation(logs: logs, focus: [FocusSymptoms.sleep], on: day(0), calendar: calendar)
        XCTAssertEqual(change?.title, "Broken or poor sleep on 5 of your last 8 logged days.")
        XCTAssertNil(change?.detail)
    }

}
