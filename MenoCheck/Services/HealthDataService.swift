import Foundation
import HealthKit

@MainActor
final class MenoHealthStore: ObservableObject {
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isLoading = false
    @Published private(set) var connectionStatus = "Not connected"
    @Published private(set) var lastNightSleepHours: Double?
    @Published private(set) var todaySteps: Int?

    private let healthStore = HKHealthStore()

    func requestAccess() async {
        guard isAvailable,
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            connectionStatus = "Apple Health is unavailable on this device"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [sleep, steps])
            connectionStatus = "Permission requested"
            await refresh()
        } catch {
            connectionStatus = "Couldn’t connect Apple Health"
        }
    }

    func refresh() async {
        guard isAvailable,
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        isLoading = true
        defer { isLoading = false }
        async let sleepHours = readSleepHours(type: sleep)
        async let stepCount = readSteps(type: steps)
        let (sleepResult, stepResult) = await (sleepHours, stepCount)
        lastNightSleepHours = sleepResult
        todaySteps = stepResult
        if sleepResult != nil || stepResult != nil { connectionStatus = "Connected" }
    }

    private func readSleepHours(type: HKCategoryType) async -> Double? {
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = Set([
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ])
                let hours = (samples as? [HKCategorySample] ?? [])
                    .filter { values.contains($0.value) }
                    .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 3600 }
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            healthStore.execute(query)
        }
    }

    private func readSteps(type: HKQuantityType) async -> Int? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let quantity = result?.sumQuantity() else { return continuation.resume(returning: nil) }
                continuation.resume(returning: Int(quantity.doubleValue(for: .count())))
            }
            healthStore.execute(query)
        }
    }
}
