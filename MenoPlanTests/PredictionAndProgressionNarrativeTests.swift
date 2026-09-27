import XCTest
@testable import MenoPlan

final class PredictionExplanationBuilderTests: XCTestCase {
    func testBulletsExplainIrregularityWidening() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let window = try XCTUnwrap(FertilityWindowCalculator.window(for: today, lastPeriodStart: start, averageCycleLength: 28, lutealPhaseLength: 14, cycleLengthVariabilityDays: 12, calendar: calendar))
        let settings = UserSettings()
        settings.averageCycleLengthValue = 28
        settings.lutealPhaseLengthValue = 14

        let bullets = PredictionExplanationBuilder.bullets(window: window, cycle: nil, settings: settings)

        XCTAssertTrue(bullets.contains { $0.contains("28 days") })
        XCTAssertTrue(bullets.contains { $0.localizedCaseInsensitiveContains("varied") })
    }

    func testBulletsOmitIrregularityNoteWhenCycleIsSteady() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let window = try XCTUnwrap(FertilityWindowCalculator.window(for: today, lastPeriodStart: start, averageCycleLength: 28, lutealPhaseLength: 14, calendar: calendar))
        let settings = UserSettings()

        let bullets = PredictionExplanationBuilder.bullets(window: window, cycle: nil, settings: settings)

        XCTAssertFalse(bullets.contains { $0.localizedCaseInsensitiveContains("varied") })
    }
}

final class ProgressionNarrativeBuilderTests: XCTestCase {
}

final class HomeGreetingTests: XCTestCase {
    private func calendar(in zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    func testSeptember13At1940InDublinUsesEveningGreeting() throws {
        let calendar = try calendar(in: "Europe/Dublin")
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 19, minute: 40)))
        XCTAssertEqual(HomeGreeting.title(name: "Lauren", at: date, calendar: calendar), "Evening, Lauren")
        XCTAssertEqual(HomeGreeting.title(name: "", at: date, calendar: calendar), "Evening")
    }

    func testGreetingChangesAtNoonAndSixPM() throws {
        let calendar = try calendar(in: "Europe/Dublin")
        for (hour, minute, expected) in [(11, 59, "Morning"), (12, 0, "Afternoon"), (17, 59, "Afternoon"), (18, 0, "Evening")] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: hour, minute: minute)))
            XCTAssertEqual(HomeGreeting.title(name: "Lauren", at: date, calendar: calendar), "\(expected), Lauren")
        }
    }

    func testSameInstantUsesPhonesLocalTimeZone() throws {
        let dublin = try calendar(in: "Europe/Dublin")
        let losAngeles = try calendar(in: "America/Los_Angeles")
        let instant = try XCTUnwrap(dublin.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 19, minute: 40)))
        XCTAssertEqual(HomeGreeting.title(name: "Lauren", at: instant, calendar: dublin), "Evening, Lauren")
        XCTAssertEqual(HomeGreeting.title(name: "Lauren", at: instant, calendar: losAngeles), "Morning, Lauren")
    }
}
