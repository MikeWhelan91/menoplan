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
}
