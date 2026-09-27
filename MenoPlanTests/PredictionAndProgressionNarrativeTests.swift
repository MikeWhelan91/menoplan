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
    func testWeakComparisonNoteFlagsDifferentBrands() {
        let earlier = Scan(createdAt: .now.addingTimeInterval(-86_400), testType: .pregnancy, testFormat: .unspecified, resultType: .faintLineDetected, analysisMode: .aiQuickCheck, imageFilename: "a.jpg", brandName: "BrandA")
        let later = Scan(createdAt: .now, testType: .pregnancy, testFormat: .unspecified, resultType: .appearsPositive, analysisMode: .aiQuickCheck, imageFilename: "b.jpg", brandName: "BrandB")

        let note = ProgressionNarrativeBuilder.weakComparisonNote(scans: [earlier, later])

        XCTAssertNotNil(note)
        XCTAssertTrue(note!.localizedCaseInsensitiveContains("brand"))
    }

    func testWeakComparisonNoteIsNilForAConsistentPair() {
        let earlier = Scan(createdAt: .now.addingTimeInterval(-86_400), testType: .pregnancy, testFormat: .unspecified, resultType: .faintLineDetected, analysisMode: .aiQuickCheck, imageFilename: "a.jpg", brandName: "BrandA")
        let later = Scan(createdAt: .now, testType: .pregnancy, testFormat: .unspecified, resultType: .appearsPositive, analysisMode: .aiQuickCheck, imageFilename: "b.jpg", brandName: "BrandA")

        XCTAssertNil(ProgressionNarrativeBuilder.weakComparisonNote(scans: [earlier, later]))
    }

    func testPregnancyNarrativeDescribesAStrongerLine() {
        let earlier = Scan(createdAt: .now.addingTimeInterval(-86_400), testType: .pregnancy, testFormat: .unspecified, resultType: .faintLineDetected, confidencePercentage: 0, certaintyPercentage: 0, controlLineDetected: true, testLineDetected: true, testControlRatio: 0, lineStrength: 0.2, analysisMode: .aiQuickCheck, imageFilename: "a.jpg")
        let later = Scan(createdAt: .now, testType: .pregnancy, testFormat: .unspecified, resultType: .faintLineDetected, confidencePercentage: 0, certaintyPercentage: 0, controlLineDetected: true, testLineDetected: true, testControlRatio: 0, lineStrength: 0.4, analysisMode: .aiQuickCheck, imageFilename: "b.jpg")

        let narrative = try? XCTUnwrap(ProgressionNarrativeBuilder.pregnancyNarrative(scans: [earlier, later]))

        XCTAssertEqual(narrative, "Line appears stronger. The later pregnancy test has a higher saved line-strength value.")
    }
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
