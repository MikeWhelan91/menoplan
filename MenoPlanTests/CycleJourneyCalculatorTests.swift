import XCTest
@testable import MenoPlan

final class CycleJourneyCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int, year: Int = 2026) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    /// 28-day cycle starting Sep 1: ovulation on cycle day 14 (Sep 14), period due Sep 29.
    private func window(on date: Date) throws -> FertilityWindow {
        try XCTUnwrap(FertilityWindowCalculator.window(
            for: date, lastPeriodStart: try day(9, 1), averageCycleLength: 28, lutealPhaseLength: 14, calendar: calendar
        ))
    }

    private func countdown(_ month: Int, _ dayOfMonth: Int) throws -> HomeCountdown {
        let today = try day(month, dayOfMonth)
        return CycleJourneyCalculator.countdown(on: today, window: try window(on: today), calendar: calendar)
    }

    func testWidenedWindowKeepsTestingUntilPossibleFertileDaysEnd() throws {
        // Lee's case: period 12 Sep, 28 days, ovulation 25 Sep, periods vary (±4).
        let start = try day(9, 12)
        func widened(_ today: Date) throws -> HomeCountdown {
            let window = try XCTUnwrap(FertilityWindowCalculator.window(
                for: today, lastPeriodStart: start, averageCycleLength: 28, lutealPhaseLength: 14,
                profileWidening: .irregularPeriods, calendar: calendar
            ))
            XCTAssertTrue(calendar.isDate(window.fertileEndDate, inSameDayAs: try day(9, 29)))
            return CycleJourneyCalculator.countdown(on: today, window: window, calendar: calendar)
        }
        let dayAfterOvulation = try widened(try day(9, 26))
        XCTAssertEqual(dayAfterOvulation.stage, .fertile)
        XCTAssertEqual(dayAfterOvulation.caption, "Possible fertile days end in")
        XCTAssertEqual(dayAfterOvulation.value, 3)
        XCTAssertEqual(dayAfterOvulation.suggestedTest, .ovulation)
        XCTAssertEqual(try widened(try day(9, 29)).caption, "Last possible fertile day")
        // The day after the range ends, it moves on to pregnancy testing.
        XCTAssertEqual(try widened(try day(9, 30)).stage, .waitingToTest)
    }

    func testCountdownWalksThroughEveryStage() throws {
        let w = try window(on: try day(9, 2))
        XCTAssertTrue(calendar.isDate(w.predictedOvulationDate, inSameDayAs: try day(9, 14)))
        XCTAssertTrue(calendar.isDate(w.nextPeriodDate, inSameDayAs: try day(9, 29)))

        XCTAssertEqual(try countdown(9, 2).stage, .beforeOvulationTesting)
        XCTAssertEqual(try countdown(9, 2).suggestedTest, .ovulation)
        XCTAssertEqual(try countdown(9, 14).stage, .ovulationDay)
        XCTAssertEqual(try countdown(9, 14).headline, "Today")

        let waiting = try countdown(9, 18)
        XCTAssertEqual(waiting.stage, .waitingToTest)
        XCTAssertEqual(waiting.value, 7, "Early test is 4 days before the Sep 29 period, i.e. Sep 25")
        XCTAssertEqual(waiting.suggestedTest, .pregnancy)
        XCTAssertTrue(waiting.footnote.contains("11 days"))

        XCTAssertEqual(try countdown(9, 26).stage, .earlyTesting)
        XCTAssertEqual(try countdown(9, 29).stage, .periodDue)
    }

    func testFertileStageCountsDownToOvulation() throws {
        let w = try window(on: try day(9, 12))
        XCTAssertTrue(w.containsFertileDay(try day(9, 12), calendar: calendar))
        let fertile = try countdown(9, 12)
        XCTAssertEqual(fertile.stage, .fertile)
        XCTAssertEqual(fertile.value, 2)
        XCTAssertEqual(fertile.unit, "Days")
    }

    func testConceptionTimelineDates() throws {
        let today = try day(9, 20)
        let timeline = CycleJourneyCalculator.conceptionTimeline(window: try window(on: today), cycle: nil, calendar: calendar)
        XCTAssertTrue(calendar.isDate(timeline.implantationStart, inSameDayAs: try day(9, 20)))
        XCTAssertTrue(calendar.isDate(timeline.implantationEnd, inSameDayAs: try day(9, 24)))
        XCTAssertTrue(calendar.isDate(timeline.earliestTestDate, inSameDayAs: try day(9, 25)))
        XCTAssertTrue(calendar.isDate(timeline.reliableTestDate, inSameDayAs: try day(9, 29)))
        // Naegele: 280 days after the Sep 1 LMP for a 28-day cycle.
        XCTAssertTrue(calendar.isDate(timeline.dueDate, inSameDayAs: try day(6, 8, year: 2027)))
        XCTAssertEqual(timeline.cycleLength, 28)
        XCTAssertFalse(timeline.ovulationIsConfirmed)
    }

    // CycleRecord normalises with Calendar.current, so these use it too.
    func testPregnancyProgressFromLMPAndRecordedOvulation() throws {
        let calendar = Calendar.current
        func day(_ month: Int, _ day: Int, year: Int = 2026) throws -> Date { try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day))) }
        let cycle = CycleRecord(startDate: try day(9, 1), averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        let progress = CycleJourneyCalculator.pregnancyProgress(on: try day(10, 17), cycle: cycle, calendar: calendar)
        XCTAssertEqual(progress.gestationalDays, 46)
        XCTAssertEqual(progress.weeks, 6)
        XCTAssertEqual(progress.days, 4)
        XCTAssertEqual(progress.trimester, 1)
        XCTAssertEqual(progress.ageLabel, "6 weeks, 4 days")

        // A later recorded ovulation moves dating (and the due date) later.
        cycle.confirmedOvulationDate = try day(9, 19)
        cycle.ovulationSource = .userConfirmed
        let adjusted = CycleJourneyCalculator.pregnancyProgress(on: try day(10, 17), cycle: cycle, calendar: calendar)
        XCTAssertEqual(adjusted.gestationalDays, 42)
        XCTAssertTrue(calendar.isDate(adjusted.dueDate, inSameDayAs: try day(6, 12, year: 2027)))
    }

    func testLongCycleShiftsDueDate() throws {
        let calendar = Calendar.current
        func day(_ month: Int, _ day: Int, year: Int = 2026) throws -> Date { try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day))) }
        let cycle = CycleRecord(startDate: try day(9, 1), averageCycleLengthAtStart: 35, lutealPhaseLengthAtStart: 14)
        let progress = CycleJourneyCalculator.pregnancyProgress(on: try day(9, 1), cycle: cycle, calendar: calendar)
        // A 35-day cycle pushes the due date a week later than a 28-day one.
        XCTAssertTrue(calendar.isDate(progress.dueDate, inSameDayAs: try day(6, 15, year: 2027)))
    }
}

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
        XCTAssertTrue(calendar.isDate(projected.predictedOvulationDate, inSameDayAs: day(10, 13)))
        XCTAssertEqual(CycleCalendarPhaseResolver.projectedPhase(for: day(10, 2), window: projected, calendar: calendar), .predictedPeriod)
        XCTAssertEqual(CycleCalendarPhaseResolver.projectedPhase(for: day(10, 13), window: projected, calendar: calendar), .ovulation)

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
    func testDoctorSuggestionThresholds() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        var profile = HealthProfile(ttcDuration: .sixToTwelveMonths, birthYear: 1996, regularity: nil, conditions: [], birthControl: nil, supplement: nil)
        XCTAssertFalse(profile.shouldSuggestDoctor(on: now), "30 and under a year")
        profile.birthYear = 1990
        XCTAssertTrue(profile.shouldSuggestDoctor(on: now), "36 and six months or more")
        profile.birthYear = 1985
        profile.ttcDuration = .threeToSixMonths
        XCTAssertTrue(profile.shouldSuggestDoctor(on: now), "41 and three months or more")
        profile.birthYear = nil
        profile.ttcDuration = .overAYear
        XCTAssertTrue(profile.shouldSuggestDoctor(on: now))
        profile.ttcDuration = nil
        XCTAssertFalse(profile.shouldSuggestDoctor(on: now))
    }

    func testPredictionsLessCertain() {
        var profile = HealthProfile(ttcDuration: nil, birthYear: nil, regularity: .regular, conditions: [], birthControl: BirthControlRecency.none, supplement: nil)
        XCTAssertFalse(profile.predictionsLessCertain)
        profile.conditions = [.pcos]
        XCTAssertTrue(profile.predictionsLessCertain)
        profile.conditions = []
        profile.birthControl = .pill
        XCTAssertTrue(profile.predictionsLessCertain)
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

    // MARK: Countdown reacting to signals

    /// 28-day cycle from 1 Sep 2026 (ovulation 14 Sep, period due 29 Sep).
    private func reactionCountdown(_ month: Int, _ dayOfMonth: Int) throws -> HomeCountdown {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth)))
        let window = try XCTUnwrap(FertilityWindowCalculator.window(for: today, lastPeriodStart: start, averageCycleLength: 28, lutealPhaseLength: 14, calendar: calendar))
        return CycleJourneyCalculator.countdown(on: today, window: window, calendar: calendar)
    }

    private func signal(_ id: String, tone: CycleSignal.Tone = .info, title: String = "t") -> CycleSignal {
        CycleSignal(id: id, tone: tone, symbol: "circle", title: title, detail: "d", surfaces: [.home])
    }

    func testCountdownWithoutSignalsIsUnchanged() throws {
        let base = try reactionCountdown(9, 20)
        XCTAssertEqual(CycleJourneyCalculator.reacting(base, to: []), base)
    }

    func testSustainedHighTemperatureStrengthensLateTestAdvice() throws {
        let late = try reactionCountdown(10, 2)
        let reacted = CycleJourneyCalculator.reacting(late, to: [signal("sustainedHighTemperature", tone: .attention, title: "Temperatures high for 19 days")])
        XCTAssertEqual(reacted.headline, late.headline)
        XCTAssertEqual(reacted.footnote, "Temperatures high for 19 days. A pregnancy test now gives a clear answer")
    }

    func testEarlyFertileMucusStartsTestingToday() throws {
        let early = try reactionCountdown(9, 3)
        XCTAssertEqual(early.stage, .beforeOvulationTesting)
        let reacted = CycleJourneyCalculator.reacting(early, to: [signal("fertileMucus", tone: .positive)])
        XCTAssertEqual(reacted.headline, "Test Today")
        XCTAssertNil(reacted.value)
        XCTAssertEqual(reacted.suggestedTest, TestType.ovulation)
    }

    func testLateMucusKeepsOvulationTestingGoing() throws {
        let waiting = try reactionCountdown(9, 18)
        XCTAssertEqual(waiting.stage, .waitingToTest)
        let reacted = CycleJourneyCalculator.reacting(waiting, to: [signal("fertileMucus", title: "Fertile mucus later than expected")])
        XCTAssertEqual(reacted.suggestedTest, TestType.ovulation)
        XCTAssertEqual(reacted.headline, "Still Early")
        XCTAssertNil(reacted.value)
        XCTAssertEqual(CycleJourneyCalculator.reacting(waiting, to: [signal("noTemperatureShiftYet")]).headline, "Still Early")
    }

    func testLateMucusWarnsAnEarlyTestMayBeTooSoon() throws {
        let early = try reactionCountdown(9, 26)
        XCTAssertEqual(early.stage, .earlyTesting)
        let reacted = CycleJourneyCalculator.reacting(early, to: [signal("fertileMucus", title: "Fertile mucus later than expected")])
        XCTAssertTrue(reacted.footnote.contains("an early pregnancy test may be too soon"))
    }

    func testContraceptionOverridesEverythingElse() throws {
        let reacted = CycleJourneyCalculator.reacting(try reactionCountdown(10, 2), to: [
            signal("sustainedHighTemperature", tone: .attention), signal("hormonalContraception", tone: .attention)
        ])
        XCTAssertTrue(reacted.footnote.hasPrefix("Contraception is recorded"))
    }
}
