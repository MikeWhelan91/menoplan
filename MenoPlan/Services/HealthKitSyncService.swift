import Foundation
import SwiftData

/// Pulls the user-selected fertility signals from HealthKit and merges them into
/// LineCheck's own records, so anyone with a Bluetooth basal thermometer (Tempdrop,
/// iSnuggle, Femometer...) or who already tracks periods in Apple Health gets their trend
/// charts and cycle history filled in without retyping anything.
///
/// Two safety rules keep this from ever fighting the user's own data:
/// - A manual DailyFertilityLog BBT edit always wins - see basalBodyTemperatureSource.
/// - A period start HealthKit "discovers" is only recorded if LineCheck doesn't already
///   know about a period starting that day, from any source.
@MainActor
enum HealthKitSyncService {
    /// How far back a first sync reaches.
    private static let firstSyncLookback: TimeInterval = 60 * 60 * 24 * 365 * 2
    /// Later syncs re-read a week before the last sync. Entries are dated by
    /// when they happened, not when they reached Health, so a Watch that syncs
    /// late or a back-dated entry would otherwise fall behind the cursor and
    /// never import. Every merge below is idempotent, so the overlap is safe.
    private static let resyncOverlap: TimeInterval = 60 * 60 * 24 * 7
    /// Daily activity history is only kept for this long on a first sync -
    /// enough for cycle-by-cycle comparisons without importing years of steps.
    private static let dailyMetricsLookback: TimeInterval = 60 * 60 * 24 * 180

    struct Summary {
        let importedCount: Int
        let foundCount: Int
    }

    @discardableResult
    static func sync(settings: UserSettings, context: ModelContext) async throws -> Summary {
        let calendar = Calendar.current
        let since = settings.lastHealthKitSyncDate.map { $0.addingTimeInterval(-resyncOverlap) }
            ?? Date(timeIntervalSinceNow: -firstSyncLookback)
        // Symptoms, contraception, weight, water, sleep and activity were added
        // after some people connected. Their cursor only reaches back a week,
        // so read those categories' full history once.
        let needsBackfill = (settings.healthKitBackfillVersionValue ?? 0) < HealthKitService.permissionsVersion
        let newCategoriesSince = needsBackfill ? Date(timeIntervalSinceNow: -firstSyncLookback) : since
        let metricsSince = max(needsBackfill ? Date(timeIntervalSinceNow: -dailyMetricsLookback) : since, Date(timeIntervalSinceNow: -dailyMetricsLookback))
        let health = HealthKitService.shared

        let bbtSamples = try await health.fetchBasalBodyTemperature(since: since)
        let flowSamples = try await health.fetchMenstrualFlow(since: since)
        // The system permission screen lets the person approve each category. We
        // always try to read all supported types; denied types simply return no data.
        let mucusSamples = try await health.fetchCervicalMucus(since: since)
        let sexualActivitySamples = try await health.fetchSexualActivity(since: since)
        let testObservations = try await health.fetchTestObservations(since: since)
        // Categories added after someone first connected throw "not
        // determined" until they've seen the new permission sheet - that must
        // not stop the original, already-granted signals from syncing.
        let symptomSamples = (try? await health.fetchSymptoms(since: newCategoriesSince)) ?? []
        let contextObservations = (try? await health.fetchContextObservations(since: newCategoriesSince)) ?? []
        let weightSamples = (try? await health.fetchWeights(since: newCategoriesSince)) ?? []
        let waterByDay = (try? await health.fetchDailyWater(since: newCategoriesSince)) ?? [:]
        let latestHeight = try? await health.fetchLatestHeightCm()
        let dailyMetrics = (try? await health.fetchDailyMetrics(since: metricsSince, calendar: calendar)) ?? [:]
        let healthBirthYear = health.fetchBirthYear()

        let bbtCount = try mergeBBT(bbtSamples, calendar: calendar, context: context)
        let periodCount = try mergePeriods(flowSamples, settings: settings, calendar: calendar, context: context)
        let flowLogCount = try mergeFlowLogs(flowSamples, calendar: calendar, context: context)
        let mucusCount = try mergeCervicalMucus(mucusSamples, calendar: calendar, context: context)
        let sexualActivityCount = try mergeSexualActivity(sexualActivitySamples, calendar: calendar, context: context)
        let testObservationCount = try mergeTestObservations(testObservations + contextObservations, calendar: calendar, context: context)
        let symptomCount = try mergeSymptoms(symptomSamples, calendar: calendar, context: context)
        let weightCount = try mergeWeights(weightSamples, settings: settings, calendar: calendar, context: context)
        let waterCount = try mergeWater(waterByDay, calendar: calendar, context: context)
        let metricsCount = try mergeDailyMetrics(dailyMetrics, calendar: calendar, context: context)
        // Profile facts only fill gaps - what the person typed in LineCheck stays.
        if settings.heightCmValue == nil, let latestHeight { settings.heightCmValue = latestHeight }
        if settings.birthYearValue == nil, let healthBirthYear { settings.birthYearValue = healthBirthYear }

        // New temperatures can reveal (or remove) a post-ovulation rise.
        if bbtCount > 0 {
            CycleTrackingService.reconcileTemperatureOvulation(
                records: try context.fetch(FetchDescriptor<CycleRecord>()),
                logs: try context.fetch(FetchDescriptor<DailyFertilityLog>()),
                calendar: calendar
            )
        }

        settings.lastHealthKitSyncDate = .now
        // Only mark the backfill done once the new categories are readable,
        // i.e. the person has seen the updated permission sheet.
        if needsBackfill, await !health.hasUnrequestedTypes() {
            settings.healthKitBackfillVersionValue = HealthKitService.permissionsVersion
        }
        try? context.save()
        AppAnalytics.log("linecheck_healthkit_sync_completed", ["bbt_days": bbtCount, "periods_imported": periodCount, "flow_log_days": flowLogCount, "mucus_days": mucusCount, "sexual_activity_days": sexualActivityCount, "test_observations": testObservationCount, "symptom_days": symptomCount, "weight_days": weightCount, "water_days": waterCount, "metric_days": metricsCount])
        let importedCount = bbtCount + periodCount + flowLogCount + mucusCount + sexualActivityCount + testObservationCount + symptomCount + weightCount + waterCount
        let foundCount = bbtSamples.count + flowSamples.count + mucusSamples.count + sexualActivitySamples.count + testObservations.count
            + contextObservations.count + symptomSamples.count + weightSamples.count + waterByDay.count + dailyMetrics.count
        return Summary(importedCount: importedCount + metricsCount, foundCount: foundCount)
    }

    /// Existing logs keyed by day.
    ///
    /// Two DailyFertilityLog rows can legitimately share a day - a re-seeded
    /// debug set, an older import, the same day written on two devices - and
    /// keying with `uniqueKeysWithValues` traps on the second one, crashing the
    /// app during sync. Collapse duplicates deterministically instead, keeping
    /// the row the user is most likely to recognise as theirs.
    static func logsByDay(calendar: Calendar, context: ModelContext) throws -> [Date: DailyFertilityLog] {
        let logs = try context.fetch(FetchDescriptor<DailyFertilityLog>())
        return logsByDay(logs, calendar: calendar)
    }

    static func logsByDay(_ logs: [DailyFertilityLog], calendar: Calendar) -> [Date: DailyFertilityLog] {
        Dictionary(
            logs.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: preferredLog
        )
    }

    /// Which of two same-day rows the sync should treat as the real one: a
    /// hand-entered temperature outranks an imported one (the sync must never
    /// overwrite a manual edit), then whichever row carries more tracking, then
    /// the most recently touched.
    static func preferredLog(_ lhs: DailyFertilityLog, _ rhs: DailyFertilityLog) -> DailyFertilityLog {
        func isManualBBT(_ log: DailyFertilityLog) -> Bool {
            log.basalBodyTemperatureCelsius != nil && log.basalBodyTemperatureSource != .healthKit
        }
        if isManualBBT(lhs) != isManualBBT(rhs) { return isManualBBT(lhs) ? lhs : rhs }

        func filledFields(_ log: DailyFertilityLog) -> Int {
            var count = 0
            if !log.symptomsRaw.isEmpty { count += 1 }
            if !log.moodsRaw.isEmpty { count += 1 }
            if !log.supplementsRaw.isEmpty { count += 1 }
            if log.cervicalMucusRaw != nil { count += 1 }
            if log.cervicalPositionRaw != nil { count += 1 }
            if log.inseminationRaw != nil { count += 1 }
            if log.sexRaw != nil { count += 1 }
            if log.flowIntensityRaw != nil { count += 1 }
            if log.basalBodyTemperatureCelsius != nil { count += 1 }
            if log.wristTemperatureCelsius != nil { count += 1 }
            if log.weightKg != nil { count += 1 }
            if log.waterMl != nil { count += 1 }
            if !log.healthKitObservationsRaw.isEmpty { count += 1 }
            if !log.notes.isEmpty { count += 1 }
            return count
        }
        let lhsFields = filledFields(lhs), rhsFields = filledFields(rhs)
        if lhsFields != rhsFields { return lhsFields > rhsFields ? lhs : rhs }
        return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    /// Below this an imported "BBT" is almost certainly an Apple Watch wrist
    /// reading: waking oral/vaginal BBT sits around 36.1-37.2°C.
    static let wristTemperatureCeiling = 35.8

    private static func mergeBBT(_ samples: [HealthKitService.BBTSample], calendar: Calendar, context: ModelContext) throws -> Int {
        var logs = try logsByDay(calendar: calendar, context: context)

        // Earlier versions filled BBT with wrist temperature when there was no
        // thermometer reading. Move those back so the BBT series is one
        // measurement method again (a mixed series fakes a thermal shift).
        for log in logs.values where log.basalBodyTemperatureSource == .healthKit {
            if let celsius = log.basalBodyTemperatureCelsius, celsius < wristTemperatureCeiling {
                if log.wristTemperatureCelsius == nil { log.wristTemperatureCelsius = celsius }
                log.basalBodyTemperatureCelsius = nil
            }
        }
        guard !samples.isEmpty else { return 0 }

        var basalByDay: [Date: Double] = [:]
        var wristByDay: [Date: Double] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if sample.isBasalBodyTemperature {
                if basalByDay[day] == nil { basalByDay[day] = sample.celsius }
            } else if wristByDay[day] == nil {
                wristByDay[day] = sample.celsius
            }
        }

        var count = 0
        for (day, celsius) in basalByDay {
            let log = logs[day] ?? DailyFertilityLog(date: day)
            guard log.basalBodyTemperatureCelsius == nil || log.basalBodyTemperatureSource == .healthKit else { continue }
            log.basalBodyTemperatureCelsius = celsius
            log.basalBodyTemperatureSource = .healthKit
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        for (day, celsius) in wristByDay {
            let log = logs[day] ?? DailyFertilityLog(date: day)
            guard log.wristTemperatureCelsius != celsius else { continue }
            log.wristTemperatureCelsius = celsius
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    private static func mergeSymptoms(_ samples: [HealthKitService.SymptomSample], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let log = logs[day] ?? DailyFertilityLog(date: day)
            guard !log.symptoms.contains(sample.symptom) else { continue }
            log.symptoms = (log.symptoms + [sample.symptom]).sorted()
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    /// Same ownership rule as BBT: fills empty days and refreshes earlier
    /// Health imports, never replaces a weight the person typed.
    private static func mergeWeights(_ samples: [HealthKitService.DatedValue], settings: UserSettings, calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var latestByDay: [Date: Double] = [:]
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            latestByDay[calendar.startOfDay(for: sample.date)] = sample.value
        }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for (day, kilograms) in latestByDay {
            let log = logs[day] ?? DailyFertilityLog(date: day)
            guard log.weightKg == nil || log.weightSource == .healthKit else { continue }
            log.weightKg = kilograms
            log.weightSource = .healthKit
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        BodyMeasurementStore.refreshProfileWeight(settings: settings, logs: Array(logs.values))
        return count
    }

    private static func mergeWater(_ waterByDay: [Date: Double], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !waterByDay.isEmpty else { return 0 }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for (day, millilitres) in waterByDay where millilitres > 0 {
            let log = logs[day] ?? DailyFertilityLog(date: day)
            guard log.waterMl == nil || log.waterSource == .healthKit else { continue }
            guard log.waterMl != millilitres else { continue }
            log.waterMl = millilitres
            log.waterSource = .healthKit
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    /// Activity and vitals are Health's data, not the person's journal, so a
    /// newer reading simply replaces the day's row.
    private static func mergeDailyMetrics(_ metricsByDay: [Date: HealthKitService.DailyMetrics], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !metricsByDay.isEmpty else { return 0 }
        var rows = Dictionary(
            try context.fetch(FetchDescriptor<DailyHealthMetrics>()).map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { lhs, rhs in lhs.updatedAt >= rhs.updatedAt ? lhs : rhs }
        )
        for (day, metrics) in metricsByDay {
            let row = rows[day] ?? DailyHealthMetrics(date: day)
            row.steps = metrics.steps
            row.walkingRunningKm = metrics.walkingRunningKm
            row.activeEnergyKcal = metrics.activeEnergyKcal
            row.exerciseMinutes = metrics.exerciseMinutes
            row.workoutCount = metrics.workoutCount
            row.workoutMinutes = metrics.workoutMinutes
            row.restingHeartRate = metrics.restingHeartRate
            row.heartRateVariabilityMs = metrics.heartRateVariabilityMs
            row.sleepHours = metrics.sleepHours
            row.updatedAt = .now
            if rows[day] == nil { context.insert(row); rows[day] = row }
        }
        return metricsByDay.count
    }

    private static func mergeCervicalMucus(_ samples: [HealthKitService.CervicalMucusSample], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            guard logs[day]?.cervicalMucusRaw == nil else { continue }
            let log = logs[day] ?? DailyFertilityLog(date: day)
            log.cervicalMucusRaw = sample.quality
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    private static func mergeSexualActivity(_ samples: [HealthKitService.SexualActivitySample], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let log = logs[day] ?? DailyFertilityLog(date: day)
            let healthValue = sample.protectionUsed.map { $0 ? "Protected" : "Unprotected" } ?? "Logged in Apple Health"
            // A user-selected value always wins. The earlier generic Health label is
            // safe to upgrade when a later fetch includes protection metadata.
            guard log.sexRaw == nil || (log.sexRaw == "Logged in Apple Health" && healthValue != "Logged in Apple Health") else { continue }
            log.sexRaw = healthValue
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    private static func mergeFlowLogs(_ samples: [HealthKitService.FlowSample], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for sample in samples {
            guard let intensity = sample.intensity else { continue }
            let day = calendar.startOfDay(for: sample.date)
            guard logs[day]?.flowIntensity == nil else { continue }
            let log = logs[day] ?? DailyFertilityLog(date: day)
            log.flowIntensity = intensity
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    private static func mergeTestObservations(_ samples: [HealthKitService.TestObservation], calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }
        var logs = try logsByDay(calendar: calendar, context: context)
        var count = 0
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let log = logs[day] ?? DailyFertilityLog(date: day)
            var observations = log.healthKitObservations
            guard !observations.contains(sample.label) else { continue }
            observations.append(sample.label)
            log.healthKitObservations = observations.sorted()
            if logs[day] == nil { context.insert(log); logs[day] = log }
            count += 1
        }
        return count
    }

    private static func mergePeriods(_ samples: [HealthKitService.FlowSample], settings: UserSettings, calendar: Calendar, context: ModelContext) throws -> Int {
        guard !samples.isEmpty else { return 0 }

        let flowDays = Set(samples.compactMap { $0.intensity != nil ? calendar.startOfDay(for: $0.date) : nil }).sorted()
        guard !flowDays.isEmpty else { return 0 }

        let runs = periodRuns(from: flowDays, calendar: calendar)

        var records = try context.fetch(FetchDescriptor<CycleRecord>())
        var periods = try context.fetch(FetchDescriptor<PeriodEvent>())
        var count = 0
        for run in runs {
            let start = run.start
            if let existing = CycleTrackingService.periodStartConflict(on: start, periods: periods, minimumSeparationDays: 15, calendar: calendar) {
                // Only extend a Health-imported event. Never rewrite a manual period.
                if existing.source == .healthKit, run.end > (existing.endDate ?? existing.startDate) {
                    existing.endDate = run.end
                }
                continue
            }
            let cycle = CycleTrackingService.recordPeriodStart(
                start,
                settings: settings,
                records: records,
                periods: periods,
                context: context,
                source: .healthKit,
                calendar: calendar
            )
            if !records.contains(where: { $0.id == cycle.id }) { records.append(cycle) }
            if let inserted = try context.fetch(FetchDescriptor<PeriodEvent>()).first(where: { $0.cycleRecordID == cycle.id }) {
                inserted.endDate = run.end
                periods.append(inserted)
            }
            count += 1
        }
        return count
    }

    /// A missed/unsynced day of flow should not create a second cycle.
    static func periodRuns(from flowDays: [Date], calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        var runs: [(start: Date, end: Date)] = []
        var previousDay: Date?
        for day in Set(flowDays.map { calendar.startOfDay(for: $0) }).sorted() {
            let isContinuation = previousDay.map { (calendar.dateComponents([.day], from: $0, to: day).day ?? 99) <= 2 } ?? false
            if isContinuation, !runs.isEmpty {
                runs[runs.count - 1].end = day
            } else {
                runs.append((start: day, end: day))
            }
            previousDay = day
        }
        return runs
    }
}

/// Weight, height and water entered in LineCheck. One place so onboarding,
/// the quiz and the daily log all keep the profile value and Apple Health in
/// step with the day-by-day log.
@MainActor
enum BodyMeasurementStore {
    static func recordHeight(_ centimetres: Double, settings: UserSettings) {
        settings.heightCmValue = centimetres
    }

    /// Saves a typed weight for `date` (replacing any Health import for that
    /// day) and keeps the profile weight on the most recent weigh-in.
    static func recordWeight(_ kilograms: Double?, on date: Date, settings: UserSettings, context: ModelContext, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let logs = (try? context.fetch(FetchDescriptor<DailyFertilityLog>())) ?? []
        let log = HealthKitSyncService.logsByDay(logs, calendar: calendar)[day] ?? {
            let created = DailyFertilityLog(date: day)
            context.insert(created)
            return created
        }()
        log.weightKg = kilograms
        log.weightSource = .userConfirmed
        refreshProfileWeight(settings: settings, logs: logs + [log])
        if kilograms == nil, settings.weightKgValue != nil, !logs.contains(where: { $0.weightKg != nil }) {
            settings.weightKgValue = nil
        }
        writeToHealth(settings: settings) { await $0.saveWeight(kilograms: kilograms, on: day) }
    }

    /// Profile weight follows the latest dated weigh-in, so an old imported
    /// reading can't replace a newer one typed at onboarding and vice versa.
    static func refreshProfileWeight(settings: UserSettings, logs: [DailyFertilityLog]) {
        if let latest = logs.filter({ $0.weightKg != nil }).max(by: { $0.date < $1.date })?.weightKg {
            settings.weightKgValue = latest
        }
    }

    /// Pushes a value the person typed to Apple Health when they've connected
    /// it. Fire-and-forget: a failed write never blocks saving in LineCheck.
    static func writeToHealth(settings: UserSettings, _ write: @escaping @Sendable (HealthKitService) async -> Void) {
        guard settings.healthKitSyncEnabled else { return }
        Task { await write(HealthKitService.shared) }
    }
}

/// The one "connect Apple Health" flow, used by Settings, onboarding and the
/// in-context prompts. Free for everyone: syncing costs nothing to run and the
/// data makes every prediction and insight better.
@MainActor
enum HealthKitConnection {
    /// Whether it's worth offering the connection at all.
    static func canOffer(_ settings: UserSettings?) -> Bool {
        guard let settings else { return false }
        return HealthKitService.shared.isAvailable && !settings.healthKitSyncEnabled
    }

    /// Shows the system permission sheet, turns sync on and (unless told
    /// not to) runs the first import. Returns a short message for a toast.
    @discardableResult
    static func connect(settings: UserSettings, context: ModelContext, source: String, syncNow: Bool = true) async -> String {
        guard HealthKitService.shared.isAvailable else { return "Health data isn't available on this device" }
        do {
            try await HealthKitService.shared.requestAuthorization()
        } catch {
            return "Couldn't connect to Apple Health"
        }
        settings.healthKitSyncEnabled = true
        settings.healthKitPermissionsVersionValue = HealthKitService.permissionsVersion
        try? context.save()
        AppAnalytics.log("linecheck_healthkit_sync_enabled", ["source": source])
        await HealthKitBackgroundSyncCoordinator.shared.activateIfPossible()
        guard syncNow else { return "Apple Health connected" }
        do {
            let summary = try await HealthKitSyncService.sync(settings: settings, context: context)
            if summary.foundCount == 0 { return "Apple Health connected. Nothing shared yet, so check the Health app's permissions" }
            if summary.importedCount > 0 { return "Apple Health connected. \(summary.importedCount) entries imported" }
            return "Apple Health connected"
        } catch {
            return "Apple Health connected, but the first sync couldn't finish"
        }
    }
}

extension HealthKitConnection {
    static let reminderMaximum = 3
    static let firstReminderAfterDays = 2
    static let reminderIntervalDays = 14

    /// Whether Home should show its occasional reminder now: two days after
    /// the person first reaches Home, then every two weeks, three times at
    /// most, never after "Don't ask again" or once connected.
    static func shouldShowReminder(_ settings: UserSettings?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let settings, settings.hasCompletedOnboarding, canOffer(settings),
              settings.healthPromptOptOutValue != true,
              (settings.healthPromptCountValue ?? 0) < reminderMaximum else { return false }
        func days(since date: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0 }
        if let last = settings.healthPromptLastShownValue { return days(since: last) >= reminderIntervalDays }
        guard let first = settings.healthPromptFirstSeenValue else {
            settings.healthPromptFirstSeenValue = now
            return false
        }
        return days(since: first) >= firstReminderAfterDays
    }

    static func recordReminderShown(_ settings: UserSettings, now: Date = .now) {
        settings.healthPromptLastShownValue = now
        settings.healthPromptCountValue = (settings.healthPromptCountValue ?? 0) + 1
    }
}
