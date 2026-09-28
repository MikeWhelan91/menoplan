import XCTest
@testable import MenoPlan

final class AppointmentSummaryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!)!
    }

    private func log(_ offset: Int, _ edit: (DailyFertilityLog) -> Void) -> DailyFertilityLog {
        let log = DailyFertilityLog(date: day(offset))
        edit(log)
        return log
    }

    private func build(_ logs: [DailyFertilityLog], settings: UserSettings = UserSettings(), pinned: [String]? = nil) -> AppointmentSummary {
        AppointmentSummaryBuilder.build(days: 30, logs: logs, settings: settings, periodStarts: [], tests: [], pinned: pinned, on: day(0), calendar: calendar)
    }

    func testConcernsLeadWithCheckInSymptomsThenMostFrequent() {
        let settings = UserSettings()
        settings.focusSymptoms = ["Brain Fog", "Anxiety"]
        let logs = [
            log(0) { $0.setSeverity(.moderate, for: "Brain Fog"); $0.setSeverity(.mild, for: "Headache") },
            log(-1) { $0.setSeverity(.moderate, for: "Brain Fog"); $0.setSeverity(.mild, for: "Headache") },
            log(-2) { $0.setSeverity(.severe, for: "Brain Fog"); $0.setSeverity(.mild, for: "Headache") },
            log(-3) { $0.hotFlushCount = 4; $0.vasomotorSeverity = .moderate },
            log(-4) { $0.hotFlushCount = 2 }
        ]
        let summary = build(logs, settings: settings)
        XCTAssertEqual(summary.loggedDays, 5)
        // Anxiety was never logged, so it doesn't take a slot.
        XCTAssertEqual(summary.concerns.map(\.key), ["Brain Fog", "Headache", FocusSymptoms.hotFlushes])
        let fog = summary.concerns[0]
        XCTAssertEqual(fog.daysPresent, 3)
        XCTAssertEqual(fog.usualSeverity, "moderate")
        XCTAssertEqual(fog.worstSeverity, "severe")
        XCTAssertEqual(summary.concerns[2].total, 6)
    }

    func testPinnedConcernsWinAndTheRestAreListed() {
        let logs = [
            log(0) { $0.setSeverity(.mild, for: "Brain Fog"); $0.setSeverity(.mild, for: "Joint Pain") },
            log(-1) { $0.setSeverity(.mild, for: "Brain Fog") }
        ]
        let summary = build(logs, pinned: ["Joint Pain"])
        XCTAssertEqual(summary.concerns.map(\.key), ["Joint Pain"])
        XCTAssertEqual(summary.otherSymptoms.map(\.name), ["Brain Fog"])
        XCTAssertEqual(summary.otherSymptoms.first?.days, 2)
    }

    func testImpactSleepAndBleedingAreCounted() {
        let settings = UserSettings()
        settings.menopauseStage = .postmenopause
        let logs = [
            log(0) { $0.dayImpact = .lots; $0.sleepQuality = .poor },
            log(-1) { $0.dayImpact = .some; $0.sleepQuality = .good; $0.flowIntensity = .spotting },
            log(-40) { $0.dayImpact = .lots }
        ]
        let summary = build(logs, settings: settings)
        XCTAssertEqual(summary.loggedDays, 2, "Days outside the period are left out")
        XCTAssertEqual(summary.impactLots, 1)
        XCTAssertEqual(summary.impactSome, 1)
        XCTAssertEqual(summary.badSleepNights, 1)
        XCTAssertEqual(summary.sleepLoggedNights, 2)
        XCTAssertEqual(summary.bleedingDays, 1)
        XCTAssertEqual(summary.concerns.first?.name, "Broken or poor sleep")
    }

    func testHRTAdherenceComesFromTheLog() {
        let settings = UserSettings()
        settings.hrtRegimen = ["Oestrogen Gel"]
        settings.hrtDoseText = "2 pumps daily"
        let logs = [
            log(0) { $0.hrtTaken = ["Oestrogen Gel"] },
            log(-1) { $0.dayImpact = .notAtAll },
            log(-2) { $0.hrtTaken = ["Oestrogen Gel"] }
        ]
        let summary = build(logs, settings: settings)
        XCTAssertEqual(summary.hrtTakenDays, 2)
        XCTAssertEqual(summary.hrtDose, "2 pumps daily")
    }
}
