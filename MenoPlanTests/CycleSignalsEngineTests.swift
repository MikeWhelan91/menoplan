import SwiftData
import XCTest
@testable import MenoPlan

final class CycleSignalsEngineTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ offset: Int, from start: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    private var cycleStart: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    }

    private func input(
        today: Date,
        cycle: CycleRecord? = nil,
        logs: [DailyFertilityLog] = [],
        metrics: [DailyHealthMetrics] = [],
        profile: HealthProfile = HealthProfile(conditions: [])
    ) -> CycleSignalInputs {
        let cycle = cycle ?? CycleRecord(startDate: cycleStart, averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        return CycleSignalInputs(
            today: today,
            window: CycleTrackingService.window(for: today, records: [cycle], settings: nil, calendar: calendar),
            activeCycle: cycle,
            logs: logs,
            metrics: metrics,
            scans: [],
            profile: profile
        )
    }

    // MARK: Signals

    func testLotsOfWaterAffectsTestReadings() {
        let today = day(10, from: cycleStart)
        let log = DailyFertilityLog(date: today)
        log.waterMl = 3000
        let result = CycleSignalsEngine.signals(for: .ovulationResult, input(today: today, logs: [log]))
        XCTAssertTrue(result.contains { $0.id == "highFluidIntake" })
    }

    func testContraceptionInHealthFlagsOvulationResults() {
        let today = day(10, from: cycleStart)
        let log = DailyFertilityLog(date: day(-20, from: cycleStart))
        log.healthKitObservations = ["Apple Health contraceptive: Pill"]
        let result = CycleSignalsEngine.signals(for: .ovulationResult, input(today: today, logs: [log]))
        XCTAssertTrue(result.contains { $0.id == "hormonalContraception" })
    }

    func testShortSleepAndRaisedRestingHeartRate() {
        let today = day(20, from: cycleStart)
        let metrics = (0...40).map { age -> DailyHealthMetrics in
            let row = DailyHealthMetrics(date: day(-age, from: today))
            row.sleepHours = age < 7 ? 5.2 : 7.5
            row.restingHeartRate = age < 5 ? 66 : 60
            return row
        }
        let signals = CycleSignalsEngine.signals(input(today: today, metrics: metrics))
        XCTAssertTrue(signals.contains { $0.id == "shortSleep" })
        XCTAssertTrue(signals.contains { $0.id == "restingHeartRateUp" })
    }

    func testLargeWeightChangeIsFlagged() {
        let today = day(10, from: cycleStart)
        let before = DailyFertilityLog(date: day(-60, from: today))
        before.weightKg = 70
        let now = DailyFertilityLog(date: today)
        now.weightKg = 65
        let signals = CycleSignalsEngine.signals(input(today: today, logs: [before, now]))
        XCTAssertTrue(signals.contains { $0.id == "weightChange" })
        XCTAssertTrue(CycleSignalsEngine.bodySummary(logs: [before, now], metrics: [], today: today).contains { $0.contains("changeKg=-5.0") })
    }

    func testQuietDataProducesNoSignals() {
        let today = day(5, from: cycleStart)
        XCTAssertTrue(CycleSignalsEngine.signals(input(today: today)).isEmpty)
    }

    func testLongGapBetweenPeriodsIsDescribedCalmly() {
        let long = CycleSignalsEngine.signals(input(today: day(50, from: cycleStart)))
        let longCycle = long.first { $0.id == "longCycle" }
        XCTAssertEqual(longCycle?.tone, .info)
        XCTAssertEqual(longCycle?.title, "A longer cycle than usual")

        let gap = CycleSignalsEngine.signals(input(today: day(70, from: cycleStart)))
        XCTAssertEqual(gap.first { $0.id == "longCycle" }?.title, "71 days since your last period")
    }

    // MARK: Weight units

    func testStoneConversionsRoundTrip() {
        let (stone, pounds) = WeightUnit.stoneAndPounds(62.5)   // 137.8 lb
        XCTAssertEqual(stone, 9)
        XCTAssertEqual(pounds, 11.8, accuracy: 0.05)
        XCTAssertEqual(WeightUnit.kilograms(stone: 9, pounds: 11.8), 62.5, accuracy: 0.05)
        XCTAssertEqual(WeightUnit.stone.formatted(62.5), "9 st 12 lb")
        XCTAssertEqual(WeightUnit.pounds.system, .imperial)
        XCTAssertEqual(WeightUnit.stone.system, .metric)
        XCTAssertEqual(WeightUnit.stone.distanceSystem, .imperial)
        XCTAssertEqual(WeightUnit.kilograms.distanceSystem, .metric)
    }

    func testChangingWeightUnitLeavesHeightUnitAlone() {
        let settings = UserSettings()
        settings.bodyMeasurementUnit = .imperial   // lb and ft/in
        settings.weightUnit = .stone
        XCTAssertEqual(settings.heightUnit, .imperial)
        XCTAssertEqual(settings.weightUnit, .stone)
    }

    // MARK: Health reminder pacing

    @MainActor
    func testHealthReminderPacing() throws {
        guard HealthKitService.shared.isAvailable else { throw XCTSkip("Health not available") }
        let settings = UserSettings()
        settings.hasCompletedOnboarding = true
        let start = cycleStart
        XCTAssertFalse(HealthKitConnection.shouldShowReminder(settings, now: start))            // first sight: starts the clock
        XCTAssertFalse(HealthKitConnection.shouldShowReminder(settings, now: day(1, from: start)))
        XCTAssertTrue(HealthKitConnection.shouldShowReminder(settings, now: day(2, from: start)))
        HealthKitConnection.recordReminderShown(settings, now: day(2, from: start))
        XCTAssertFalse(HealthKitConnection.shouldShowReminder(settings, now: day(10, from: start)))
        XCTAssertTrue(HealthKitConnection.shouldShowReminder(settings, now: day(16, from: start)))
        HealthKitConnection.recordReminderShown(settings, now: day(16, from: start))
        HealthKitConnection.recordReminderShown(settings, now: day(30, from: start))
        XCTAssertFalse(HealthKitConnection.shouldShowReminder(settings, now: day(60, from: start)))   // three times at most
        let optedOut = UserSettings()
        optedOut.hasCompletedOnboarding = true
        optedOut.healthPromptOptOutValue = true
        XCTAssertFalse(HealthKitConnection.shouldShowReminder(optedOut, now: day(60, from: start)))
    }
}
