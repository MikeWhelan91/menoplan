import Foundation
import HealthKit
import SwiftData

private final class HealthKitObserverCompletionBox: @unchecked Sendable {
    private let completion: HKObserverQueryCompletionHandler

    init(_ completion: @escaping HKObserverQueryCompletionHandler) {
        self.completion = completion
    }

    func call() {
        completion()
    }
}

/// Wrapper around LineCheck's HealthKit access. One system-owned permission
/// screen presents every supported signal so people can decide which
/// individual categories to share. Every type here feeds something real:
/// predictions, the daily log, CycleSignalsEngine, or Luna's context - a
/// type nothing reads doesn't get asked for (App Review rejects that).
final class HealthKitService: @unchecked Sendable {
    static let shared = HealthKitService()

    /// Bump when `readTypes` / `shareTypes` grow, so people who connected
    /// before are offered the new categories once (see Settings).
    static let permissionsVersion = 3

    private let store = HKHealthStore()
    private let bbtType = HKQuantityType(.basalBodyTemperature)
    private let wristTemperatureType = HKQuantityType(.appleSleepingWristTemperature)
    private let flowType = HKCategoryType(.menstrualFlow)
    private let spottingType = HKCategoryType(.intermenstrualBleeding)
    private let breastPainType = HKCategoryType(.breastPain)
    private let pelvicPainType = HKCategoryType(.pelvicPain)
    private let vaginalDrynessType = HKCategoryType(.vaginalDryness)
    private let contraceptiveType = HKCategoryType(.contraceptive)
    private let lactationType = HKCategoryType(.lactation)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let weightType = HKQuantityType(.bodyMass)
    private let heightType = HKQuantityType(.height)
    private let waterType = HKQuantityType(.dietaryWater)
    private let stepsType = HKQuantityType(.stepCount)
    private let walkingRunningType = HKQuantityType(.distanceWalkingRunning)
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private let exerciseTimeType = HKQuantityType(.appleExerciseTime)
    private let restingHeartRateType = HKQuantityType(.restingHeartRate)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private var backgroundObserverQueries: [HKObserverQuery] = []

    private var backgroundDeliveryTypes: [HKSampleType] {
        [
            bbtType,
            wristTemperatureType,
            flowType,
            spottingType
        ]
    }

    /// What LineCheck writes back: the values a person can type into the
    /// daily log. Sleep is read-only on purpose - LineCheck only knows
    /// "hours", and inventing bedtimes would corrupt the person's sleep data.
    private var shareTypes: Set<HKSampleType> { [weightType, waterType] }

    private var readTypes: Set<HKObjectType> {
        [
            bbtType, wristTemperatureType, flowType,
            spottingType, breastPainType, pelvicPainType, vaginalDrynessType,
            contraceptiveType, lactationType, sleepType,
            weightType, heightType, waterType,
            stepsType, walkingRunningType, activeEnergyType, exerciseTimeType,
            restingHeartRateType, hrvType,
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth)
        ]
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// HealthKit only tells us whether *we've* granted/denied access to a type we've
    /// requested for write, not for read (Apple keeps read grants private from the
    /// requesting app for privacy reasons). For read-only types like ours, "not
    /// determined" is the only status we can reliably act on - anything else means
    /// the system prompt has already been resolved one way or another.
    var hasRequestedAccess: Bool {
        store.authorizationStatus(for: weightType) != .notDetermined
    }

    /// True when the permission sheet still has categories the person hasn't
    /// seen - e.g. they connected before LineCheck asked for sleep or weight.
    func hasUnrequestedTypes() async -> Bool {
        guard isAvailable else { return false }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }
    /// Registers long-running observers so a change saved in Apple Health can wake LineCheck
    /// in the background. HealthKit controls the actual delivery timing.
    func startBackgroundDelivery(onUpdate: @escaping @Sendable () async -> Void) async throws {
        guard isAvailable, backgroundObserverQueries.isEmpty else { return }

        var queries: [HKObserverQuery] = []
        for sampleType in backgroundDeliveryTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }
                let completionBox = HealthKitObserverCompletionBox(completion)
                Task { @MainActor in
                    await onUpdate()
                    completionBox.call()
                }
            }
            store.execute(query)
            queries.append(query)
        }

        do {
            for sampleType in backgroundDeliveryTypes {
                try await enableBackgroundDelivery(for: sampleType)
            }
            backgroundObserverQueries = queries
        } catch {
            queries.forEach(store.stop)
            throw error
        }
    }

    func stopBackgroundDelivery() async {
        backgroundObserverQueries.forEach(store.stop)
        backgroundObserverQueries = []
        for sampleType in backgroundDeliveryTypes {
            await disableBackgroundDelivery(for: sampleType)
        }
    }

    private func enableBackgroundDelivery(for sampleType: HKSampleType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.backgroundDeliveryUnavailable)
                }
            }
        }
    }

    private func disableBackgroundDelivery(for sampleType: HKSampleType) async {
        await withCheckedContinuation { continuation in
            store.disableBackgroundDelivery(for: sampleType) { _, _ in
                continuation.resume()
            }
        }
    }

    struct BBTSample {
        let date: Date
        let celsius: Double
        let isBasalBodyTemperature: Bool
    }

    struct FlowSample {
        let date: Date
        let intensity: FlowIntensity?
    }

    /// A Health entry is an observation recorded by another app or by the user,
    /// never a LineCheck image reading. Keep the label intact so its origin is clear.
    struct TestObservation {
        let date: Date
        let label: String
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func fetchBasalBodyTemperature(since startDate: Date) async throws -> [BBTSample] {
        guard isAvailable else { return [] }
        // LineCheck writes typed temperatures back to Health; reading those
        // again would just echo the person's own entry back as an "import".
        let predicate = Self.excludingLineCheck(HKQuery.predicateForSamples(withStart: startDate, end: .now))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bbtType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let basalSamples = try await descriptor.result(for: store)
        let wristDescriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: wristTemperatureType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let wristSamples = try await wristDescriptor.result(for: store)
        return basalSamples.map { BBTSample(date: $0.startDate, celsius: $0.quantity.doubleValue(for: .degreeCelsius()), isBasalBodyTemperature: true) }
            + wristSamples.map { BBTSample(date: $0.startDate, celsius: $0.quantity.doubleValue(for: .degreeCelsius()), isBasalBodyTemperature: false) }
    }

    func fetchMenstrualFlow(since startDate: Date) async throws -> [FlowSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: flowType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { FlowSample(date: $0.startDate, intensity: Self.flowIntensity(for: $0.value)) }
    }

    // MARK: Symptoms & other reproductive-health entries

    struct SymptomSample {
        let date: Date
        /// The LineCheck symptom name this maps to, e.g. "Tender Breasts".
        let symptom: String
    }

    /// Spotting, breast pain, pelvic pain and vaginal dryness, mapped onto the
    /// daily log's symptom names. A severity of "not present" is an explicit
    /// "I didn't have this" and is skipped rather than logged.
    func fetchSymptoms(since startDate: Date) async throws -> [SymptomSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let notPresent = HKCategoryValueSeverity.notPresent.rawValue
        var results: [SymptomSample] = []
        let mapped: [(HKCategoryType, String, Bool)] = [
            (spottingType, "Spotting", false),
            (breastPainType, "Tender Breasts", true),
            (pelvicPainType, "Pelvic Pain", true),
            (vaginalDrynessType, "Vaginal Dryness", true)
        ]
        for (type, symptom, hasSeverity) in mapped {
            let samples = try await categorySamples(type: type, predicate: predicate)
            results += samples.compactMap { sample in
                if hasSeverity && sample.value == notPresent { return nil }
                return SymptomSample(date: sample.startDate, symptom: symptom)
            }
        }
        return results
    }

    /// Contraception and lactation entries. These describe spans of
    /// time rather than a single day, so each is noted on the day it starts.
    func fetchContextObservations(since startDate: Date) async throws -> [TestObservation] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let contraceptives = try await categorySamples(type: contraceptiveType, predicate: predicate)
        let lactation = try await categorySamples(type: lactationType, predicate: predicate)
        return contraceptives.map { sample in
            let method: String
            switch HKCategoryValueContraceptive(rawValue: sample.value) {
            case .implant: method = "Implant"
            case .injection: method = "Injection"
            case .intrauterineDevice: method = "IUD"
            case .intravaginalRing: method = "Vaginal ring"
            case .oral: method = "Pill"
            case .patch: method = "Patch"
            default: method = "Recorded"
            }
            return TestObservation(date: sample.startDate, label: "Apple Health contraceptive: \(method)")
        }
        + lactation.map { TestObservation(date: $0.startDate, label: "Apple Health: lactation recorded") }
    }

    // MARK: Body measurements

    struct DatedValue {
        let date: Date
        let value: Double
    }

    /// Weight readings in kilograms, excluding ones LineCheck wrote itself.
    func fetchWeights(since startDate: Date) async throws -> [DatedValue] {
        try await quantitySamples(type: weightType, unit: .gramUnit(with: .kilo), since: startDate)
    }

    /// The most recent height on record, in centimetres, however old.
    func fetchLatestHeightCm() async throws -> Double? {
        guard isAvailable else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heightType)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: .meterUnit(with: .centi))
    }

    /// Water per day in millilitres, excluding what LineCheck wrote itself.
    func fetchDailyWater(since startDate: Date) async throws -> [Date: Double] {
        try await dailyStatistics(type: waterType, unit: .literUnit(with: .milli), options: .cumulativeSum, since: startDate, excludingLineCheck: true)
    }

    /// Birth year from Health's date of birth, used to fill the profile's age
    /// (which drives the doctor-suggestion thresholds) when it's missing.
    func fetchBirthYear() -> Int? {
        guard isAvailable else { return nil }
        return (try? store.dateOfBirthComponents())?.year
    }

    // MARK: Activity, vitals and sleep

    struct DailyMetrics {
        var steps: Double?
        var walkingRunningKm: Double?
        var activeEnergyKcal: Double?
        var exerciseMinutes: Double?
        var workoutCount: Int?
        var workoutMinutes: Double?
        var restingHeartRate: Double?
        var heartRateVariabilityMs: Double?
        var sleepHours: Double?
    }

    /// One summary per day since `startDate`. Uses Health's own statistics
    /// queries, which de-duplicate overlapping iPhone and Apple Watch data.
    func fetchDailyMetrics(since startDate: Date, calendar: Calendar = .current) async throws -> [Date: DailyMetrics] {
        guard isAvailable else { return [:] }
        let start = calendar.startOfDay(for: startDate)
        var byDay: [Date: DailyMetrics] = [:]
        func merge(_ values: [Date: Double], _ apply: (inout DailyMetrics, Double) -> Void) {
            for (day, value) in values {
                var metrics = byDay[day] ?? DailyMetrics()
                apply(&metrics, value)
                byDay[day] = metrics
            }
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        merge(try await dailyStatistics(type: stepsType, unit: .count(), options: .cumulativeSum, since: start)) { $0.steps = $1 }
        merge(try await dailyStatistics(type: walkingRunningType, unit: .meterUnit(with: .kilo), options: .cumulativeSum, since: start)) { $0.walkingRunningKm = $1 }
        merge(try await dailyStatistics(type: activeEnergyType, unit: .kilocalorie(), options: .cumulativeSum, since: start)) { $0.activeEnergyKcal = $1 }
        merge(try await dailyStatistics(type: exerciseTimeType, unit: .minute(), options: .cumulativeSum, since: start)) { $0.exerciseMinutes = $1 }
        merge(try await dailyStatistics(type: restingHeartRateType, unit: bpm, options: .discreteAverage, since: start)) { $0.restingHeartRate = $1 }
        merge(try await dailyStatistics(type: hrvType, unit: .secondUnit(with: .milli), options: .discreteAverage, since: start)) { $0.heartRateVariabilityMs = $1 }

        for (day, hours) in try await dailySleepHours(since: start, calendar: calendar) {
            var metrics = byDay[day] ?? DailyMetrics()
            metrics.sleepHours = hours
            byDay[day] = metrics
        }

        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            var metrics = byDay[day] ?? DailyMetrics()
            metrics.workoutCount = (metrics.workoutCount ?? 0) + 1
            metrics.workoutMinutes = (metrics.workoutMinutes ?? 0) + workout.duration / 60
            byDay[day] = metrics
        }
        return byDay
    }

    /// Time asleep per night, credited to the day the person woke up. Several
    /// sources (Watch, iPhone, a sleep app) often record the same night, so
    /// intervals are merged before summing instead of simply added up.
    private func dailySleepHours(since start: Date, calendar: Calendar) async throws -> [Date: Double] {
        // Start a day early so a night that began before `start` still counts.
        let lookback = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let samples = try await categorySamples(type: sleepType, predicate: HKQuery.predicateForSamples(withStart: lookback, end: .now))
        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        var intervalsByDay: [Date: [(Date, Date)]] = [:]
        for sample in samples where asleepValues.contains(sample.value) {
            let day = calendar.startOfDay(for: sample.endDate)
            guard day >= start else { continue }
            intervalsByDay[day, default: []].append((sample.startDate, sample.endDate))
        }
        return intervalsByDay.mapValues { intervals in
            var total: TimeInterval = 0
            var current: (Date, Date)?
            for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
                if let open = current, interval.0 <= open.1 {
                    current = (open.0, max(open.1, interval.1))
                } else {
                    if let open = current { total += open.1.timeIntervalSince(open.0) }
                    current = interval
                }
            }
            if let open = current { total += open.1.timeIntervalSince(open.0) }
            return total / 3600
        }
    }

    // MARK: Writing back

    func saveWeight(kilograms: Double?, on day: Date) async {
        await replaceDailyValue(type: weightType, quantity: kilograms.map { HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: $0) }, on: day)
    }

    func saveWater(millilitres: Double?, on day: Date) async {
        await replaceDailyValue(type: waterType, quantity: millilitres.map { HKQuantity(unit: .literUnit(with: .milli), doubleValue: $0) }, on: day)
    }

    private func replaceDailyValue(type: HKQuantityType, quantity: HKQuantity?, on day: Date, calendar: Calendar = .current) async {
        guard isAvailable, store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let ours = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        _ = try? await store.deleteObjects(of: type, predicate: ours)
        guard let quantity else { return }
        // Today's entry is stamped now; a back-filled day at midday, so it
        // can't slip into a neighbouring day in another time zone.
        let timestamp = calendar.isDateInToday(start) ? Date.now : (calendar.date(byAdding: .hour, value: 12, to: start) ?? start)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp)
        try? await store.save(sample)
    }

    // MARK: Query helpers

    private static func excludingLineCheck(_ predicate: NSPredicate) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        ])
    }

    private func quantitySamples(type: HKQuantityType, unit: HKUnit, since startDate: Date) async throws -> [DatedValue] {
        guard isAvailable else { return [] }
        let predicate = Self.excludingLineCheck(HKQuery.predicateForSamples(withStart: startDate, end: .now))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map { DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func dailyStatistics(
        type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        since startDate: Date,
        excludingLineCheck: Bool = false,
        calendar: Calendar = .current
    ) async throws -> [Date: Double] {
        guard isAvailable else { return [:] }
        let start = calendar.startOfDay(for: startDate)
        var predicate: NSPredicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        if excludingLineCheck { predicate = Self.excludingLineCheck(predicate) }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var values: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: .now) { statistics, _ in
            let quantity = options.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                values[calendar.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return values
    }

    private func categorySamples(type: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    /// HKCategoryTypeIdentifierMenstrualFlow itself wasn't renamed - only the value enum used
    /// to decode its samples was, from HKCategoryValueMenstrualFlow to
    /// HKCategoryValueVaginalBleeding (iOS 18+, same underlying raw values).
    private static func flowIntensity(for rawValue: Int) -> FlowIntensity? {
        guard let value = HKCategoryValueVaginalBleeding(rawValue: rawValue) else { return nil }
        switch value {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        default: return nil // .unspecified and .none (explicitly "no flow") aren't a loggable intensity
        }
    }
}

enum HealthKitError: Error {
    case unavailable
    case backgroundDeliveryUnavailable
}

/// Bridges HealthKit's background observer callbacks to the SwiftData-backed merge service.
/// The coordinator only activates after the person has explicitly enabled Health sync.
@MainActor
final class HealthKitBackgroundSyncCoordinator {
    static let shared = HealthKitBackgroundSyncCoordinator()

    private var modelContainer: ModelContainer?
    private var didFinishLaunching = false
    private var isSyncingBackgroundChange = false
    private var lastBackgroundSyncStart: Date?
    private let backgroundSyncCoalescingWindow: TimeInterval = 10 * 60

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        Task { await activateIfPossible() }
    }

    func appDidFinishLaunching() {
        didFinishLaunching = true
        Task { await activateIfPossible() }
    }

    func activateIfPossible() async {
        guard didFinishLaunching, let modelContainer else { return }
        let context = ModelContext(modelContainer)
        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first,
              settings.healthKitSyncEnabled else { return }

        do {
            try await HealthKitService.shared.startBackgroundDelivery { [weak self] in
                await self?.syncAfterHealthKitChange()
            }
        } catch {
            AppAnalytics.log("linecheck_healthkit_background_delivery_failed")
        }
    }

    func deactivate() async {
        await HealthKitService.shared.stopBackgroundDelivery()
    }

    private func syncAfterHealthKitChange() async {
        guard !isSyncingBackgroundChange else { return }
        if let lastBackgroundSyncStart,
           Date.now.timeIntervalSince(lastBackgroundSyncStart) < backgroundSyncCoalescingWindow {
            return
        }
        guard let modelContainer else { return }
        isSyncingBackgroundChange = true
        lastBackgroundSyncStart = .now
        defer { isSyncingBackgroundChange = false }
        let context = ModelContext(modelContainer)
        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first,
              settings.healthKitSyncEnabled else { return }
        _ = try? await HealthKitSyncService.sync(settings: settings, context: context)
    }
}
