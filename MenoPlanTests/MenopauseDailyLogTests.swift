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
