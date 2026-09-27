import XCTest
import SwiftData
@testable import MenoPlan

@MainActor
final class FreshInstallCalendarReproTests: XCTestCase {
    func testFreshInstallLoggingPeriodStartedTodayColorsTodayAsPeriod() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserSettings.self, CycleRecord.self, PeriodEvent.self, configurations: configuration)
        let context = ModelContext(container)
        let settings = UserSettings()
        context.insert(settings)

        let today = Calendar.current.startOfDay(for: .now)

        let cycle = CycleTrackingService.recordPeriodStart(
            today,
            settings: settings,
            records: [],
            periods: [],
            context: context
        )

        let periodsDescriptor = FetchDescriptor<PeriodEvent>()
        let periods = try context.fetch(periodsDescriptor)
        print("REPRO: periods count = \(periods.count)")
        for p in periods {
            print("REPRO: period startDate=\(p.startDate) endDate=\(String(describing: p.endDate)) cycleRecordID=\(String(describing: p.cycleRecordID))")
        }
        print("REPRO: cycle.startDate=\(cycle.startDate) id=\(cycle.id)")

        let window = try XCTUnwrap(CycleTrackingService.window(records: [cycle], periods: periods, settings: settings))
        print("REPRO: window.cycleStart=\(window.cycleStart) predictedOvulationDate=\(window.predictedOvulationDate)")

        let phase = CycleCalendarPhaseResolver.phase(for: today, window: window, cycleRecords: [cycle], periodEvents: periods)
        print("REPRO: phase for today = \(phase)")

        XCTAssertEqual(phase, .period)
    }
}

extension FreshInstallCalendarReproTests {
    func testSeptember2026WeekdayColumnsMatchForEveryWeekStart() throws {
        for zone in ["Europe/Dublin", "America/Los_Angeles", "Pacific/Auckland"] {
            for firstWeekday in 1...7 {
                var calendar = Calendar(identifier: .gregorian)
                calendar.locale = Locale(identifier: "en_IE")
                calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
                calendar.firstWeekday = firstWeekday
                let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))
                let symbols = CalendarMonthLayout.weekdaySymbols(calendar: calendar)
                let cells = CalendarMonthLayout.cells(for: month, calendar: calendar)
                XCTAssertEqual(cells.compactMap { $0 }.count, 30)
                for (index, date) in cells.enumerated() {
                    guard let date else { continue }
                    let weekday = calendar.component(.weekday, from: date)
                    XCTAssertEqual(symbols[index % 7], calendar.shortStandaloneWeekdaySymbols[weekday - 1])
                    if calendar.component(.day, from: date) == 13 {
                        XCTAssertEqual(weekday, 1, "September 13, 2026 is Sunday")
                    }
                }
            }
        }
    }

    func testBackfilledHistoryReplacesStaleEarlyOvulationEstimate() throws {
        let calendar = Calendar.current
        func date(_ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        }
        let container = try ModelContainer(for: UserSettings.self, CycleRecord.self, PeriodEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = UserSettings()
        context.insert(settings)
        let start = try date(8, 27)
        let cycle = CycleTrackingService.recordPeriodStart(start, settings: settings, records: [], periods: [], context: context)
        cycle.predictedOvulationDate = try date(9, 3) // stale but previously accepted as plausible
        for historical in [try date(7, 26), try date(6, 24)] {
            _ = CycleTrackingService.recordPeriodStart(historical, settings: settings,
                records: try context.fetch(FetchDescriptor<CycleRecord>()),
                periods: try context.fetch(FetchDescriptor<PeriodEvent>()), context: context)
        }
        let records = try context.fetch(FetchDescriptor<CycleRecord>())
        let periods = try context.fetch(FetchDescriptor<PeriodEvent>())
        let window = try XCTUnwrap(CycleTrackingService.window(for: try date(9, 13), records: records, periods: periods, settings: settings))
        XCTAssertEqual(cycle.averageCycleLengthAtStart, 32)
        XCTAssertEqual(window.predictedOvulationDate, try date(9, 13))
        XCTAssertEqual(window.nextPeriodDate, try date(9, 28))
        XCTAssertLessThan(window.opkStartDate, window.fertileStartDate)
        XCTAssertLessThan(window.fertileStartDate, window.predictedOvulationDate)
        let withoutPeriods = try XCTUnwrap(CycleTrackingService.window(for: try date(9, 13), records: records, settings: settings))
        XCTAssertEqual(withoutPeriods.predictedOvulationDate, window.predictedOvulationDate)
    }

    func testPlausibleButUnobservedCachedOvulationIsRecalculated() throws {
        let calendar = Calendar.current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let stale = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
        let cycle = CycleRecord(startDate: start, predictedOvulationDate: stale, averageCycleLengthAtStart: 32, lutealPhaseLengthAtStart: 14)
        let window = try XCTUnwrap(CycleTrackingService.window(for: start, records: [cycle], settings: nil))
        XCTAssertEqual(window.predictedOvulationDate, calendar.date(byAdding: .day, value: 17, to: start))
        XCTAssertNotEqual(window.predictedOvulationDate, stale)
    }

    func testReminderResyncRemovesObsoleteTestingAndAlignsPeriodDueDate() async throws {
        let calendar = Calendar.current
        func date(_ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day)))
        }
        let container = try ModelContainer(for: UserSettings.self, CycleRecord.self, Reminder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = UserSettings()
        settings.autoRemindersEnabled = true
        let cycle = CycleRecord(startDate: try date(1))
        context.insert(settings)
        context.insert(cycle)
        let staleTest = Reminder(title: "Start ovulation testing", reminderType: .ovulationTest, scheduledDate: try date(13), cycleRecordID: cycle.id, isAutoGenerated: true)
        let staleFertile = Reminder(title: "Your fertile window begins", reminderType: .fertileWindow, scheduledDate: try date(15), cycleRecordID: cycle.id, isAutoGenerated: true)
        let stalePeriod = Reminder(title: "Old period title", reminderType: .pregnancyRetest, scheduledDate: try date(22), cycleRecordID: cycle.id, isAutoGenerated: true)
        let oldCycle = Reminder(title: "Old cycle", reminderType: .ovulationTest, scheduledDate: try date(16), cycleRecordID: UUID(), isAutoGenerated: true)
        let manual = Reminder(title: "My reminder", reminderType: .custom, scheduledDate: try date(15))
        let existing = [staleTest, staleFertile, stalePeriod, oldCycle, manual]
        existing.forEach(context.insert)
        let window = FertilityWindow(cycleStart: cycle.startDate, cycleDay: 13, predictedOvulationDate: try date(9), fertileStartDate: try date(4), fertileEndDate: try date(9), opkStartDate: try date(2), nextPeriodDate: try date(24))
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: existing, context: context, now: try date(13))
        let saved = try context.fetch(FetchDescriptor<Reminder>())
        // A due-day check-in includes testing advice, so the separate retest
        // alert must not also be scheduled for the same morning.
        XCTAssertEqual(saved.count, 4)
        XCTAssertTrue(saved.contains { $0.id == manual.id })
        XCTAssertFalse(saved.contains { $0.reminderType == .pregnancyRetest })
        let periodExpected = try XCTUnwrap(saved.first { $0.reminderType == .periodExpected })
        XCTAssertTrue(calendar.isDate(periodExpected.scheduledDate, inSameDayAs: try date(23)))
        XCTAssertEqual(periodExpected.title, "Period may start soon")
        let periodCheckIn = try XCTUnwrap(saved.first { $0.reminderType == .periodCheckIn })
        XCTAssertTrue(calendar.isDate(periodCheckIn.scheduledDate, inSameDayAs: try date(24)))
        XCTAssertEqual(periodCheckIn.title, PeriodCheckInCopy.titleWithTest)
        let periodLate = try XCTUnwrap(saved.first { $0.reminderType == .periodLate })
        XCTAssertTrue(calendar.isDate(periodLate.scheduledDate, inSameDayAs: try date(31)))
        // A second sync must not duplicate or move the corrected reminder.
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: saved, context: context, now: try date(13))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Reminder>()).count, 4)

        // Users who turn off the due-day check-in still receive their chosen
        // pregnancy-test reminder; turning it back on replaces that alert.
        settings.autoPeriodCheckInRemindersEnabled = false
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: saved, context: context, now: try date(13))
        let retestOnly = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertFalse(retestOnly.contains { $0.reminderType == .periodCheckIn })
        XCTAssertTrue(retestOnly.contains { $0.reminderType == .pregnancyRetest })
        settings.autoPeriodCheckInRemindersEnabled = true
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: retestOnly, context: context, now: try date(13))
        let combinedAgain = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertTrue(combinedAgain.contains { $0.reminderType == .periodCheckIn })
        XCTAssertFalse(combinedAgain.contains { $0.reminderType == .pregnancyRetest })

        settings.autoPregnancyRetestRemindersEnabled = false
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: combinedAgain, context: context, now: try date(13))
        let checkInWithoutTesting = try XCTUnwrap(context.fetch(FetchDescriptor<Reminder>()).first { $0.reminderType == .periodCheckIn })
        XCTAssertEqual(checkInWithoutTesting.title, PeriodCheckInCopy.title)
    }
}

extension FreshInstallCalendarReproTests {
    func testSavedHighOPKGetsOneNextDayFollowUpAndNewLowCancelsIt() async throws {
        let calendar = Calendar.current
        func date(_ day: Int, hour: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)))
        }
        let container = try ModelContainer(for: UserSettings.self, CycleRecord.self, Reminder.self, Scan.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = UserSettings()
        settings.autoRemindersEnabled = true
        settings.autoOvulationTestRemindersEnabled = true
        let cycle = CycleRecord(startDate: try date(1))
        context.insert(settings)
        context.insert(cycle)
        let high = Scan(createdAt: try date(11, hour: 10), testType: .ovulation, testFormat: .strip, resultType: .high, controlLineDetected: true, analysisMode: .manualEnhance, imageFilename: "high")
        high.cycleRecordID = cycle.id
        context.insert(high)
        let window = FertilityWindow(cycleStart: cycle.startDate, cycleDay: 11, predictedOvulationDate: try date(16), fertileStartDate: try date(11), fertileEndDate: try date(17), opkStartDate: try date(10), nextPeriodDate: try date(30))

        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: [], context: context, now: try date(11, hour: 11))
        var reminders = try context.fetch(FetchDescriptor<Reminder>())
        let followUp = try XCTUnwrap(reminders.first { $0.reminderType == .ovulationFollowUp })
        XCTAssertEqual(followUp.title, OvulationReminderCopy.highResultTitle)
        XCTAssertEqual(followUp.scheduledDate, try date(12, hour: 10))
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: reminders, context: context, now: try date(11, hour: 11))
        reminders = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertEqual(reminders.filter { $0.reminderType == .ovulationFollowUp }.count, 1)

        let low = Scan(createdAt: try date(11, hour: 12), testType: .ovulation, testFormat: .strip, resultType: .low, controlLineDetected: true, analysisMode: .manualEnhance, imageFilename: "low")
        low.cycleRecordID = cycle.id
        context.insert(low)
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: reminders, context: context, now: try date(11, hour: 13))
        XCTAssertFalse(try context.fetch(FetchDescriptor<Reminder>()).contains { $0.reminderType == .ovulationFollowUp })

        low.resultTypeRaw = ScanResultType.high.rawValue
        low.excludedFromCalculations = true
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: reminders, context: context, now: try date(11, hour: 13))
        XCTAssertFalse(try context.fetch(FetchDescriptor<Reminder>()).contains { $0.reminderType == .ovulationFollowUp })
    }

    func testIrregularOvulationFollowUpUsesItsOwnTypeAndStopsAfterPeak() async throws {
        let calendar = Calendar.current
        func date(_ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day)))
        }
        let container = try ModelContainer(for: UserSettings.self, CycleRecord.self, Reminder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = UserSettings()
        settings.autoRemindersEnabled = true
        let cycle = CycleRecord(startDate: try date(1))
        context.insert(settings)
        context.insert(cycle)
        let oldAutoCheckIn = Reminder(title: "Old generic testing nudge", reminderType: .bodyCheckIn, scheduledDate: try date(13), cycleRecordID: cycle.id, isAutoGenerated: true)
        let personalCheckIn = Reminder(title: "My body-sign note", reminderType: .bodyCheckIn, scheduledDate: try date(13))
        context.insert(oldAutoCheckIn)
        context.insert(personalCheckIn)
        let window = FertilityWindow(
            cycleStart: try date(1), cycleDay: 1,
            predictedOvulationDate: try date(15),
            fertileStartDate: try date(10), fertileEndDate: try date(19),
            opkStartDate: try date(8), nextPeriodDate: try date(30),
            cycleLengthVariabilityDays: 10
        )

        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: [oldAutoCheckIn, personalCheckIn], context: context, now: try date(1))
        let scheduled = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertFalse(scheduled.contains { $0.id == oldAutoCheckIn.id })
        XCTAssertTrue(scheduled.contains { $0.id == personalCheckIn.id })
        XCTAssertTrue(scheduled.contains { $0.reminderType == .ovulationTest && $0.title == OvulationReminderCopy.startTitle })
        XCTAssertTrue(scheduled.contains { $0.reminderType == .fertileWindow && $0.title == OvulationReminderCopy.fertileTitle })
        let followUp = try XCTUnwrap(scheduled.first { $0.reminderType == .ovulationFollowUp })
        XCTAssertTrue(followUp.isAutoGenerated)
        XCTAssertEqual(followUp.title, OvulationReminderCopy.followUpTitle)
        XCTAssertTrue(calendar.isDate(followUp.scheduledDate, inSameDayAs: try date(13)))
        let lateCheckIn = try XCTUnwrap(scheduled.first { $0.reminderType == .periodLate })
        let expectedLateDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: window.nextPeriodDate))
        XCTAssertTrue(calendar.isDate(lateCheckIn.scheduledDate, inSameDayAs: expectedLateDate))

        // An optional predicted-ovulation nudge on the same day replaces the
        // mid-window follow-up rather than sending two alerts at 09:00.
        settings.autoFertilePeakRemindersEnabled = true
        var overlappingWindow = window
        overlappingWindow.predictedOvulationDate = try date(13)
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: overlappingWindow, settings: settings, existingReminders: scheduled, context: context, now: try date(1))
        let withPeakNudge = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertTrue(withPeakNudge.contains { $0.reminderType == .fertilePeak })
        XCTAssertFalse(withPeakNudge.contains { $0.reminderType == .ovulationFollowUp })

        cycle.ovulationSource = .testSupported
        await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: overlappingWindow, settings: settings, existingReminders: withPeakNudge, context: context, now: try date(1))
        let afterPeak = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertTrue(afterPeak.contains { $0.id == personalCheckIn.id })
        XCTAssertFalse(afterPeak.contains { [.ovulationTest, .fertileWindow, .fertilePeak, .ovulationFollowUp].contains($0.reminderType) })
    }

    func testAppWideRefreshRepairsSavedDatesWithoutOpeningCalendar() async throws {
        let calendar = Calendar.current
        func date(_ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        }
        let container = try ModelContainer(for: UserSettings.self, CycleRecord.self, PeriodEvent.self, Reminder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = UserSettings()
        settings.autoRemindersEnabled = true
        let previous = CycleRecord(startDate: try date(7, 26), endDate: try date(8, 27), status: .completed)
        let cycle = CycleRecord(startDate: try date(8, 27), predictedOvulationDate: try date(9, 3), averageCycleLengthAtStart: 28)
        let periods = [PeriodEvent(startDate: previous.startDate), PeriodEvent(startDate: cycle.startDate)]
        context.insert(settings)
        context.insert(previous)
        context.insert(cycle)
        periods.forEach(context.insert)
        let fertile = Reminder(title: "Your fertile window begins", reminderType: .fertileWindow, scheduledDate: try date(9, 15), cycleRecordID: cycle.id, isAutoGenerated: true)
        let period = Reminder(title: "Period due - test if it hasn't arrived", reminderType: .pregnancyRetest, scheduledDate: try date(9, 22), cycleRecordID: cycle.id, isAutoGenerated: true)
        let manual = Reminder(title: "My reminder", reminderType: .custom, scheduledDate: try date(9, 15))
        let duplicatePeriod = Reminder(title: "Old duplicate", reminderType: .pregnancyRetest, scheduledDate: try date(9, 22), cycleRecordID: cycle.id, isAutoGenerated: true)
        [fertile, period, manual, duplicatePeriod].forEach(context.insert)
        try context.save()

        let now = try date(9, 1)
        let calendarWindow = try XCTUnwrap(CycleTrackingService.window(for: now, records: [previous, cycle], periods: periods, settings: settings))
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context, now: now)
        XCTAssertTrue(calendar.isDate(fertile.scheduledDate, inSameDayAs: calendarWindow.fertileStartDate))
        let refreshedReminders = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertFalse(refreshedReminders.contains { $0.reminderType == .pregnancyRetest })
        let correctedCheckIn = try XCTUnwrap(refreshedReminders.first { $0.reminderType == .periodCheckIn })
        XCTAssertTrue(calendar.isDate(correctedCheckIn.scheduledDate, inSameDayAs: calendarWindow.nextPeriodDate))
        XCTAssertFalse(calendar.isDate(fertile.scheduledDate, inSameDayAs: try date(9, 15)))
        XCTAssertFalse(calendar.isDate(correctedCheckIn.scheduledDate, inSameDayAs: try date(9, 22)))

        // Foregrounding on September 13 drops the already-passed fertile
        // reminder instead of leaving a misleading future date in the list.
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context, now: try date(9, 13))
        let saved = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertFalse(saved.contains { $0.reminderType == .fertileWindow })
        XCTAssertTrue(saved.contains { $0.id == manual.id })
        XCTAssertTrue(saved.contains { $0.id == correctedCheckIn.id })

        settings.autoRemindersEnabled = false
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context, now: try date(9, 13))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Reminder>()).map(\.id), [manual.id])
    }
}
