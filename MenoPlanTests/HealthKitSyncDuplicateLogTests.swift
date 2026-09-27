import XCTest
import SwiftData
@testable import MenoPlan

/// Regression cover for a launch crash: two DailyFertilityLog rows on the same
/// day made HealthKitSyncService's day lookup trap in
/// Dictionary(uniqueKeysWithValues:), taking the app down during sync.
@MainActor
final class HealthKitSyncDuplicateLogTests: XCTestCase {
    func testFlowRunAllowsOneMissingDayButKeepsSeparateCycles() throws {
        let calendar = Calendar.current
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let days = [0, 1, 3, 4, 28, 29].map { calendar.date(byAdding: .day, value: $0, to: first)! }
        let runs = HealthKitSyncService.periodRuns(from: days, calendar: calendar)
        XCTAssertEqual(runs.count, 2)
        XCTAssertTrue(calendar.isDate(runs[0].start, inSameDayAs: first))
        XCTAssertTrue(calendar.isDate(runs[0].end, inSameDayAs: days[3]))
        XCTAssertTrue(calendar.isDate(runs[1].start, inSameDayAs: days[4]))
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DailyFertilityLog.self, configurations: configuration)
        return ModelContext(container)
    }

    func testDuplicateSameDayLogsDoNotTrap() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)

        context.insert(DailyFertilityLog(date: day))
        context.insert(DailyFertilityLog(date: day.addingTimeInterval(60 * 60 * 6)))

        let logs = try HealthKitSyncService.logsByDay(calendar: calendar, context: context)

        XCTAssertEqual(logs.count, 1)
        XCTAssertNotNil(logs[day])
    }

    func testManualTemperatureWinsOverImportedOne() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)

        let imported = DailyFertilityLog(date: day, basalBodyTemperatureCelsius: 36.7, basalBodyTemperatureSource: .healthKit)
        let manual = DailyFertilityLog(date: day, basalBodyTemperatureCelsius: 36.4, basalBodyTemperatureSource: .userConfirmed)

        // Order must not matter: the hand-entered reading is the one the sync
        // has to see, so it never overwrites the user's own edit.
        XCTAssertTrue(HealthKitSyncService.logsByDay([imported, manual], calendar: calendar)[day] === manual)
        XCTAssertTrue(HealthKitSyncService.logsByDay([manual, imported], calendar: calendar)[day] === manual)
    }

    func testRicherLogWinsWhenNeitherTemperatureIsManual() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)

        let sparse = DailyFertilityLog(date: day)
        let rich = DailyFertilityLog(date: day, symptoms: ["Cramps"], moods: ["Tired"], cervicalMucus: "Egg white")

        XCTAssertTrue(HealthKitSyncService.logsByDay([sparse, rich], calendar: calendar)[day] === rich)
        XCTAssertTrue(HealthKitSyncService.logsByDay([rich, sparse], calendar: calendar)[day] === rich)
    }
}
