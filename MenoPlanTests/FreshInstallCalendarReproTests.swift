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

}
