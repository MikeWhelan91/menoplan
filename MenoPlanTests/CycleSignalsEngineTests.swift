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

    /// Low temperatures to cycle day 15 (offset 14), then a clear rise.
    private func biphasicLogs(riseOnOffset rise: Int = 15, through last: Int = 24, wrist: Bool = false) -> [DailyFertilityLog] {
        (4...last).map { offset in
            let value = offset < rise ? 36.3 + Double(offset % 3) * 0.03 : 36.75
            let log = DailyFertilityLog(date: day(offset, from: cycleStart))
            if wrist { log.wristTemperatureCelsius = value - 1.4 } else { log.basalBodyTemperatureCelsius = value }
            return log
        }
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
            profile: profile,
            tryingToConceive: true,
            pregnancyState: .trying
        )
    }

    // MARK: Thermal shift

    func testDetectsThreeOverSixShift() throws {
        let shift = try XCTUnwrap(ThermalShiftDetector.detect(in: biphasicLogs(), from: cycleStart, calendar: calendar))
        XCTAssertTrue(calendar.isDate(shift.shiftDay, inSameDayAs: day(15, from: cycleStart)))
        XCTAssertTrue(calendar.isDate(shift.estimatedOvulation, inSameDayAs: day(14, from: cycleStart)))
        XCTAssertFalse(shift.usesWristTemperature)
    }

    func testFlatTemperaturesHaveNoShift() {
        let flat = (4...24).map { offset -> DailyFertilityLog in
            let log = DailyFertilityLog(date: day(offset, from: cycleStart))
            log.basalBodyTemperatureCelsius = 36.4
            return log
        }
        XCTAssertNil(ThermalShiftDetector.detect(in: flat, from: cycleStart, calendar: calendar))
    }

    func testWristTemperatureIsUsedOnlyWithoutEnoughBBT() throws {
        let shift = try XCTUnwrap(ThermalShiftDetector.detect(in: biphasicLogs(wrist: true), from: cycleStart, calendar: calendar))
        XCTAssertTrue(shift.usesWristTemperature)
    }

    func testTemperatureShiftMovesOvulationAndNextPeriod() throws {
        let cycle = CycleRecord(startDate: cycleStart, averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        // Rise on offset 18: later than the calendar's day-14 estimate.
        let logs = biphasicLogs(riseOnOffset: 18, through: 24)
        let changed = CycleTrackingService.reconcileTemperatureOvulation(records: [cycle], logs: logs, calendar: calendar)
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(cycle.ovulationSource, .temperatureSupported)

        let window = try XCTUnwrap(CycleTrackingService.window(for: day(22, from: cycleStart), records: [cycle], settings: nil, calendar: calendar))
        XCTAssertTrue(calendar.isDate(window.predictedOvulationDate, inSameDayAs: day(17, from: cycleStart)))
        // Ovulation offset 17 + 14 luteal days + 1.
        XCTAssertTrue(calendar.isDate(window.nextPeriodDate, inSameDayAs: day(32, from: cycleStart)))
    }

    func testPeakTestOutranksTemperatureShift() {
        let peakOvulation = day(13, from: cycleStart)
        let cycle = CycleRecord(startDate: cycleStart, predictedOvulationDate: peakOvulation, ovulationSource: .testSupported)
        CycleTrackingService.reconcileTemperatureOvulation(records: [cycle], logs: biphasicLogs(riseOnOffset: 18), calendar: calendar)
        XCTAssertEqual(cycle.ovulationSource, .testSupported)
        XCTAssertTrue(calendar.isDate(cycle.predictedOvulationDate!, inSameDayAs: peakOvulation))
    }

    func testRemovedShiftFallsBackToCalendarEstimate() {
        let cycle = CycleRecord(startDate: cycleStart, averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        CycleTrackingService.reconcileTemperatureOvulation(records: [cycle], logs: biphasicLogs(riseOnOffset: 18), calendar: calendar)
        CycleTrackingService.reconcileTemperatureOvulation(records: [cycle], logs: [], calendar: calendar)
        XCTAssertNil(cycle.ovulationSource)
        XCTAssertTrue(calendar.isDate(cycle.predictedOvulationDate!, inSameDayAs: day(13, from: cycleStart)))
    }

    // MARK: Signals

    func testSustainedHighTemperatureFlagsPossiblePregnancy() {
        let today = day(33, from: cycleStart)
        let signals = CycleSignalsEngine.signals(input(today: today, logs: biphasicLogs(riseOnOffset: 15, through: 33)))
        XCTAssertTrue(signals.contains { $0.id == "sustainedHighTemperature" && $0.tone == .attention })
        XCTAssertTrue(signals.contains { $0.id == "periodLate" })
        XCTAssertEqual(signals.first?.tone, .attention)
    }

    func testLotsOfWaterAffectsTestReadings() {
        let today = day(10, from: cycleStart)
        let log = DailyFertilityLog(date: today)
        log.waterMl = 3000
        let result = CycleSignalsEngine.signals(for: .pregnancyResult, input(today: today, logs: [log]))
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

    func testLateFertileMucusSuggestsLaterOvulation() {
        let today = day(24, from: cycleStart)
        let log = DailyFertilityLog(date: today)
        log.cervicalMucusRaw = "Egg White"
        let signal = CycleSignalsEngine.signals(input(today: today, logs: [log])).first { $0.id == "fertileMucus" }
        XCTAssertEqual(signal?.title, "Fertile mucus later than expected")
    }

    func testQuietDataProducesNoSignals() {
        let today = day(5, from: cycleStart)
        XCTAssertTrue(CycleSignalsEngine.signals(input(today: today)).isEmpty)
    }

    @MainActor
    func testNoticedHistoryKeepsASignalOnTheDayItFirstAppeared() throws {
        let container = try ModelContainer(for: NoticedSignal.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let signal = CycleSignal(id: "shortSleep", tone: .info, symbol: "bed.double", title: "Short on sleep", detail: "d", surfaces: [.home])
        let resultOnly = CycleSignal(id: "pcosLH", tone: .info, symbol: "waveform", title: "PCOS", detail: "d", surfaces: [.ovulationResult])
        let first = day(10, from: cycleStart)

        CycleSignalHistory.record([signal, resultOnly], today: first, context: context, calendar: calendar)
        CycleSignalHistory.record([signal], today: day(11, from: cycleStart), context: context, calendar: calendar)
        CycleSignalHistory.record([signal], today: day(12, from: cycleStart), context: context, calendar: calendar)
        var rows = try context.fetch(FetchDescriptor<NoticedSignal>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(calendar.isDate(rows[0].firstSeen, inSameDayAs: first))
        XCTAssertTrue(calendar.isDate(rows[0].lastSeen, inSameDayAs: day(12, from: cycleStart)))

        // After a gap it's a new occurrence on its own day.
        CycleSignalHistory.record([signal], today: day(20, from: cycleStart), context: context, calendar: calendar)
        rows = try context.fetch(FetchDescriptor<NoticedSignal>())
        XCTAssertEqual(rows.count, 2)
    }

    // MARK: No contradictions

    func testDetectedShiftStopsLateMucusSayingNoRiseYet() {
        let today = day(22, from: cycleStart)
        var logs = biphasicLogs(riseOnOffset: 15, through: 22)
        logs.last?.cervicalMucusRaw = "Egg White"
        let cycle = CycleRecord(startDate: cycleStart, averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        let signals = CycleSignalsEngine.signals(input(today: today, cycle: cycle, logs: logs))
        XCTAssertTrue(signals.contains { $0.id == "temperatureShift" })
        XCTAssertNotEqual(signals.first { $0.id == "fertileMucus" }?.title, "Fertile mucus later than expected")
    }

    func testPeakTestSuppressesNoTemperatureRiseYet() {
        let today = day(20, from: cycleStart)
        let flat = (4...20).map { offset -> DailyFertilityLog in
            let log = DailyFertilityLog(date: day(offset, from: cycleStart))
            log.basalBodyTemperatureCelsius = 36.4
            return log
        }
        let withPeak = CycleRecord(startDate: cycleStart, predictedOvulationDate: day(14, from: cycleStart), ovulationSource: .testSupported)
        XCTAssertFalse(CycleSignalsEngine.signals(input(today: today, cycle: withPeak, logs: flat)).contains { $0.id == "noTemperatureShiftYet" })
        let withoutPeak = CycleRecord(startDate: cycleStart, averageCycleLengthAtStart: 28, lutealPhaseLengthAtStart: 14)
        XCTAssertTrue(CycleSignalsEngine.signals(input(today: today, cycle: withoutPeak, logs: flat)).contains { $0.id == "noTemperatureShiftYet" })
    }

    func testContraceptionCaveatsCycleTimingSignals() {
        let today = day(24, from: cycleStart)
        let mucus = DailyFertilityLog(date: today)
        mucus.cervicalMucusRaw = "Egg White"
        let pill = DailyFertilityLog(date: day(-10, from: cycleStart))
        pill.healthKitObservations = ["Apple Health contraceptive: Pill"]
        let signals = CycleSignalsEngine.signals(input(today: today, logs: [mucus, pill]))
        let fertile = signals.first { $0.id == "fertileMucus" }
        XCTAssertEqual(fertile?.tone, .info)
        XCTAssertTrue(fertile?.detail.hasSuffix("may not reflect your natural cycle.") == true)
        XCTAssertTrue(CycleSignalsEngine.suggestsLaterOvulation(signals))
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
