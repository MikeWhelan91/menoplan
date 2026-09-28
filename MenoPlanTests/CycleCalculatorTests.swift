import XCTest
@testable import MenoPlan

final class CalendarProjectionTests: XCTestCase {
    // PeriodEvent normalises with Calendar.current, so this test does too.
    func testFutureCyclesAreProjectedAndPredictedPeriodSurvivesALoggedEnd() throws {
        let calendar = Calendar.current
        func day(_ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }
        let window = try XCTUnwrap(FertilityWindowCalculator.window(for: day(9, 20), lastPeriodStart: day(9, 2), averageCycleLength: 28, lutealPhaseLength: 14, calendar: calendar))
        // A logged period with an end date must not hide the next forecast.
        let logged = PeriodEvent(startDate: day(9, 2), endDate: day(9, 5))
        XCTAssertEqual(CycleCalendarPhaseResolver.phase(for: day(9, 30), window: window, cycleRecords: [], periodEvents: [logged], calendar: calendar), .predictedPeriod)
        // A period that came a day late retires the forecast day before it.
        let late = PeriodEvent(startDate: day(10, 1))
        XCTAssertNotEqual(CycleCalendarPhaseResolver.phase(for: day(9, 30), window: window, cycleRecords: [], periodEvents: [logged, late], calendar: calendar), .predictedPeriod)
        XCTAssertEqual(CycleCalendarPhaseResolver.phase(for: day(10, 1), window: window, cycleRecords: [], periodEvents: [logged, late], calendar: calendar), .period)

        let projected = try XCTUnwrap(CycleCalendarPhaseResolver.projectedWindow(for: day(10, 13), from: window, today: day(9, 20), calendar: calendar))
        XCTAssertTrue(calendar.isDate(projected.cycleStart, inSameDayAs: day(9, 30)))
        XCTAssertEqual(CycleCalendarPhaseResolver.projectedPhase(for: day(10, 2), window: projected, calendar: calendar), .predictedPeriod)
        XCTAssertEqual(CycleCalendarPhaseResolver.projectedPhase(for: day(10, 13), window: projected, calendar: calendar), .regular)

        // Once the period is late, nothing beyond it is guessed.
        XCTAssertNil(CycleCalendarPhaseResolver.projectedWindow(for: day(10, 13), from: window, today: day(10, 2), calendar: calendar))
    }
}

final class ProfileWideningTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    private func day(_ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }

    func testWideningPadsFertileWindowAndTestingStart() throws {
        let plain = try XCTUnwrap(FertilityWindowCalculator.window(for: day(9, 3), lastPeriodStart: day(9, 1), averageCycleLength: 28, lutealPhaseLength: 14, calendar: calendar))
        let pcos = try XCTUnwrap(FertilityWindowCalculator.window(for: day(9, 3), lastPeriodStart: day(9, 1), averageCycleLength: 28, lutealPhaseLength: 14, profileWidening: .pcos, calendar: calendar))
        // The late side widens by the full 4 days; the early side stops at the
        // day after the period (6 Sep with a 5-day period starting 1 Sep).
        XCTAssertTrue(calendar.isDate(pcos.fertileStartDate, inSameDayAs: day(9, 6)))
        XCTAssertEqual(calendar.dateComponents([.day], from: plain.fertileEndDate, to: pcos.fertileEndDate).day, 4)
        XCTAssertTrue(calendar.isDate(pcos.opkStartDate, inSameDayAs: day(9, 6)))

        // Case from a screenshot: period 26 Sep, 5 days; ovulation estimated
        // 6 Oct with ±4 widening. Fertile days and testing start 1 Oct, the
        // day after the period, never "tomorrow" on cycle day 1.
        let short = try XCTUnwrap(FertilityWindowCalculator.window(for: day(9, 26), lastPeriodStart: day(9, 26), averageCycleLength: 25, lutealPhaseLength: 14, profileWidening: .irregularPeriods, calendar: calendar))
        XCTAssertTrue(calendar.isDate(short.predictedOvulationDate, inSameDayAs: day(10, 5)) || calendar.isDate(short.predictedOvulationDate, inSameDayAs: day(10, 6)))
        XCTAssertTrue(calendar.isDate(short.fertileStartDate, inSameDayAs: day(10, 1)))
        XCTAssertTrue(calendar.isDate(short.opkStartDate, inSameDayAs: day(10, 1)))
        // A short period logged last month (learned length 2) must not let
        // widening reach into this month's still-open, five-day period.
        let learnedShort = try XCTUnwrap(FertilityWindowCalculator.window(for: day(9, 27), lastPeriodStart: day(9, 26), averageCycleLength: 25, lutealPhaseLength: 14, profileWidening: .irregularPeriods, periodLength: 2, currentPeriodDays: 5, calendar: calendar))
        XCTAssertTrue(calendar.isDate(learnedShort.fertileStartDate, inSameDayAs: day(10, 1)))
        XCTAssertTrue(calendar.isDate(learnedShort.opkStartDate, inSameDayAs: day(10, 1)))
        XCTAssertTrue(calendar.isDate(pcos.predictedOvulationDate, inSameDayAs: plain.predictedOvulationDate), "Widening never moves the ovulation estimate itself")
        XCTAssertFalse(pcos.isIrregular, "Self-reported widening must not claim the logged history is irregular")
    }

    func testReasonsAndWhenHistoryTakesOver() {
        let settings = UserSettings()
        XCTAssertNil(ProfileWidening.reason(for: settings, loggedPeriodCount: 0))
        settings.cycleRegularity = .irregular
        XCTAssertEqual(ProfileWidening.reason(for: settings, loggedPeriodCount: 2), .irregularPeriods)
        XCTAssertNil(ProfileWidening.reason(for: settings, loggedPeriodCount: 4), "Enough logged periods: measured variability decides")
        settings.cycleRegularity = .regular
        settings.birthControlRecency = .pill
        XCTAssertEqual(ProfileWidening.reason(for: settings, loggedPeriodCount: 1), .recentBirthControl)
        settings.birthControlRecency = .stillUsing
        XCTAssertNil(ProfileWidening.reason(for: settings, loggedPeriodCount: 1))
        settings.reproductiveConditions = [.pcos]
        XCTAssertEqual(ProfileWidening.reason(for: settings, loggedPeriodCount: 12), .pcos, "PCOS keeps widening however much history there is")
    }
}

final class HealthProfileTests: XCTestCase {
    func testDoctorSuggestionIsForUnder45s() {
        let year = Calendar.current.component(.year, from: .now)
        XCTAssertFalse(HealthProfile(conditions: []).shouldSuggestDoctor(), "No age, no suggestion")
        XCTAssertTrue(HealthProfile(birthYear: year - 42, conditions: []).shouldSuggestDoctor())
        XCTAssertFalse(HealthProfile(birthYear: year - 50, conditions: []).shouldSuggestDoctor())
    }

    func testPredictionsLessCertain() {
        XCTAssertFalse(HealthProfile(regularity: .regular, conditions: []).predictionsLessCertain)
        XCTAssertTrue(HealthProfile(regularity: .irregular, conditions: []).predictionsLessCertain)
        XCTAssertTrue(HealthProfile(conditions: [.pcos]).predictionsLessCertain)
        XCTAssertTrue(HealthProfile(conditions: [], birthControl: .stillUsing).predictionsLessCertain)
    }

    func testStageDecidesWhetherCycleTimingIsTracked() {
        XCTAssertTrue(MenopauseStage.perimenopause.tracksCycle)
        XCTAssertFalse(MenopauseStage.postmenopause.tracksCycle)
        XCTAssertFalse(MenopauseStage.unsure.tracksCycle)
        XCTAssertEqual(UserSettings().menopauseStage, .perimenopause)
    }
}

final class PeriodBulkEditPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func days(_ month: Int, _ range: ClosedRange<Int>) -> Set<Date> {
        Set(range.map { day(month, $0) })
    }

    func testUntouchedSelectionIsANoOp() {
        let a = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(8, 1), end: day(8, 5))
        let b = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(8, 29), end: day(9, 2))
        let selected = days(8, 1...5).union(days(8, 29...31)).union(days(9, 1...2))
        XCTAssertEqual(PeriodBulkEditService.plan(existing: [a, b], selectedDays: selected, calendar: calendar), [])
    }

    func testOngoingPeriodOnlyPreselectsDaysSoFar() {
        // Open period from 26 Sep drawn as 26-30; on the 27th only 26-27 are
        // editable, so the future days can't get stuck selected.
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let editable = PeriodBulkEditService.editableDays(of: PeriodEvent(startDate: start), today: today, calendar: calendar)
        XCTAssertEqual(editable, [start, today])
        let ended = PeriodEvent(startDate: start, endDate: calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(PeriodBulkEditService.editableDays(of: ended, today: calendar.date(byAdding: .day, value: 10, to: start)!, calendar: calendar).count, 2)
    }

    func testAdjacentPeriodsAreNotMerged() {
        let a = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(8, 1), end: day(8, 5))
        let b = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(8, 6), end: day(8, 8))
        XCTAssertEqual(PeriodBulkEditService.plan(existing: [a, b], selectedDays: days(8, 1...8), calendar: calendar), [])
    }

    func testExtendTrimMoveDeleteAndCreate() {
        let keep = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(7, 3), end: day(7, 7))
        let move = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(8, 1), end: day(8, 5))
        let remove = PeriodBulkEditService.ExistingPeriod(id: UUID(), start: day(8, 20), end: day(8, 22))
        let selected = days(7, 3...8)        // extended by one day
            .union(days(8, 2...5))           // first day unticked -> start moves
            .union(days(9, 10...13))         // brand new period
        let changes = PeriodBulkEditService.plan(existing: [keep, move, remove], selectedDays: selected, calendar: calendar)
        XCTAssertEqual(changes, [
            .delete(remove.id),
            .update(keep.id, start: day(7, 3), end: day(7, 8)),
            .update(move.id, start: day(8, 2), end: day(8, 5)),
            .create(start: day(9, 10), end: day(9, 13))
        ])
    }

}
