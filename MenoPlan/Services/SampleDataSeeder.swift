#if DEBUG
import Foundation
import SwiftData

/// Debug-only sample data, from Settings' "Seed sample data" toggle or the
/// `menoplan://debug-seed` link (handy on a simulator).
enum SampleDataSeeder {
    /// A believable perimenopause history for screenshots and QA: cycles that
    /// lengthen and vary (including a 60+ day gap), vasomotor symptoms that
    /// build and then ease after HRT starts, rated symptoms, sleep that
    /// breaks on night-sweat nights, spaced FSH readings and an appointment
    /// next week. Seeded, so the same data appears every time; days that
    /// already have real entries are left alone.
    @MainActor
    static func seed(settings: UserSettings, context modelContext: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }
        func addingDays(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: n, to: date) ?? date }
        func currentCycles() -> [CycleRecord] { (try? modelContext.fetch(FetchDescriptor<CycleRecord>())) ?? [] }
        func currentPeriods() -> [PeriodEvent] { (try? modelContext.fetch(FetchDescriptor<PeriodEvent>())) ?? [] }
        func period(startingOn day: Date) -> PeriodEvent? { currentPeriods().first { calendar.isDate($0.startDate, inSameDayAs: day) } }

        var random = SeededGenerator(seed: 47)
        func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &random) < p }
        func noise(_ amount: Double) -> Double { Double.random(in: -amount...amount, using: &random) }
        func count(_ mean: Double) -> Int { max(0, Int((mean + noise(mean * 0.8 + 0.6)).rounded())) }

        settings.menopauseStage = .perimenopause
        if !settings.hasChosenFocusSymptoms { settings.focusSymptoms = ["Sleep", "Anxiety", "Brain Fog", "Hot Flushes", "Joint Pain"] }
        let hrtStart = daysAgo(42)
        if settings.hrtRegimen.isEmpty {
            settings.hrtRegimen = ["Oestrogen Gel", "Progesterone"]
            settings.hrtDoseText = "2 pumps of gel daily, 100mg progesterone at night"
            settings.hrtStartDate = hrtStart
            settings.hrtLastChangedDate = daysAgo(14)
        }
        if settings.nextAppointmentDate == nil { settings.nextAppointmentDate = addingDays(5, to: today) }

        // Oldest first: cycles lengthening and varying, then a long gap.
        let plan: [(length: Int, periodDays: Int)] = [(27, 5), (33, 6), (25, 4), (41, 7), (29, 5), (62, 4)]
        let earliestReal = currentPeriods().map { calendar.startOfDay(for: $0.startDate) }.filter { $0 <= today }.min()
        let anchor = earliestReal ?? daysAgo(9)
        var starts: [Date] = []
        var cursor = addingDays(-plan.map(\.length).reduce(0, +), to: anchor)
        for item in plan {
            starts.append(cursor)
            cursor = addingDays(item.length, to: cursor)
        }
        for start in starts + [anchor] where period(startingOn: start) == nil {
            _ = CycleTrackingService.recordPeriodStart(start, settings: settings, records: currentCycles(), periods: currentPeriods(), context: modelContext)
        }
        for (index, item) in plan.enumerated() {
            period(startingOn: starts[index])?.endDate = addingDays(item.periodDays - 1, to: starts[index])
        }
        if let current = period(startingOn: anchor), current.endDate == nil, anchor <= daysAgo(5) {
            current.endDate = addingDays(4, to: anchor)
        }

        // Spaced FSH readings that move between bands, as FSH does.
        let fshReadings: [(daysAgo: Int, ratio: Double, result: ScanResultType)] = [
            (150, 0.32, .low), (96, 0.58, .borderline), (61, 0.86, .elevated), (33, 0.52, .borderline), (12, 0.91, .elevated)
        ]
        let existingScanDays = Set(((try? modelContext.fetch(FetchDescriptor<Scan>())) ?? []).map { calendar.startOfDay(for: $0.createdAt) })
        for reading in fshReadings where !existingScanDays.contains(daysAgo(reading.daysAgo)) {
            modelContext.insert(Scan(
                createdAt: daysAgo(reading.daysAgo).addingTimeInterval(9 * 3600),
                testType: .ovulation, testFormat: .cassette, resultType: reading.result,
                certaintyPercentage: 86, testControlRatio: reading.ratio, analysisMode: .aiQuickCheck,
                imageFilename: "debug_seed_placeholder.jpg"
            ))
        }

        let existingLogs = Dictionary(((try? modelContext.fetch(FetchDescriptor<DailyFertilityLog>())) ?? []).map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
        let existingMetrics = Dictionary(((try? modelContext.fetch(FetchDescriptor<DailyHealthMetrics>())) ?? []).map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
        let flowByDay: [FlowIntensity] = [.heavy, .heavy, .medium, .medium, .light, .light, .spotting]
        let firstStart = starts.first ?? anchor
        let totalDays = (calendar.dateComponents([.day], from: firstStart, to: today).day ?? -1) + 1

        for dayNumber in 0..<totalDays {
            let date = addingDays(dayNumber, to: firstStart)
            // 0 at the start of the sample, 1 today: symptoms build over time.
            let progress = Double(dayNumber) / Double(max(totalDays - 1, 1))
            // HRT eases things over its first few weeks.
            let hrtDays = calendar.dateComponents([.day], from: hrtStart, to: date).day ?? -1
            let relief = hrtDays < 0 ? 1.0 : max(0.45, 1.0 - Double(hrtDays) / 60.0)
            let burden = (0.45 + 0.75 * progress) * relief
            let allStarts = starts + [anchor]
            let cycleStart = allStarts.last { $0 <= date } ?? anchor
            let dayInCycle = calendar.dateComponents([.day], from: cycleStart, to: date).day ?? 0
            let periodLength = starts.firstIndex(of: cycleStart).map { plan[$0].periodDays } ?? 5
            let isPeriod = dayInCycle < periodLength
            let nextStart = allStarts.first { $0 > date }
            let beforePeriod = nextStart.map { (calendar.dateComponents([.day], from: date, to: $0).day ?? 99) <= 5 } ?? false

            let metrics: DailyHealthMetrics
            if let existing = existingMetrics[date] {
                metrics = existing
            } else {
                metrics = DailyHealthMetrics(date: date)
                modelContext.insert(metrics)
            }

            // About four days in five logged; real entries are never touched.
            guard existingLogs[date] == nil, chance(0.8) || isPeriod else {
                if metrics.sleepHours == nil { metrics.sleepHours = 6.8 + noise(0.8) }
                continue
            }
            let log = DailyFertilityLog(date: date)
            modelContext.insert(log)

            let flushes = count(3.2 * burden)
            let sweats = count((beforePeriod ? 2.2 : 1.1) * burden)
            log.hotFlushCount = flushes == 0 ? nil : flushes
            log.nightSweatCount = sweats == 0 ? nil : sweats
            if flushes + sweats > 0 {
                log.vasomotorSeverity = burden > 1.0 ? (chance(0.4) ? .severe : .moderate) : (burden > 0.7 ? .moderate : .mild)
            }
            log.sleepQuality = sweats >= 2 ? .poor : (sweats == 1 || chance(0.25 * burden) ? .broken : .good)

            func rate(_ name: String, likelihood: Double) {
                guard chance(min(0.95, likelihood)) else { return }
                let level = burden + noise(0.35)
                log.setSeverity(level > 1.05 ? .severe : level > 0.7 ? .moderate : .mild, for: name)
            }
            rate("Brain Fog", likelihood: 0.55 * burden + (log.sleepQuality == .poor ? 0.25 : 0))
            rate("Anxiety", likelihood: 0.35 * burden + (beforePeriod ? 0.3 : 0))
            rate("Joint Pain", likelihood: 0.3 + 0.2 * progress)
            rate("Fatigue", likelihood: log.sleepQuality == .good ? 0.15 : 0.55)
            rate("Irritability", likelihood: beforePeriod ? 0.55 : 0.12)
            if isPeriod && dayInCycle < 2 { rate("Headache", likelihood: 0.6) }

            let severeCount = log.symptomSeverities.values.filter { $0 == .severe }.count
            let load = Double(log.symptoms.count) + Double(severeCount) + Double(sweats) + (log.sleepQuality == .poor ? 1 : 0)
            log.dayImpact = load >= 5 ? .lots : load >= 2 ? .some : .notAtAll
            if chance(0.35) {
                log.moods = [log.dayImpact == .lots ? (chance(0.5) ? "Tearful" : "Overwhelmed") : (chance(0.5) ? "Calm" : "Happy")]
            }
            if isPeriod { log.flowIntensity = flowByDay[min(dayInCycle, flowByDay.count - 1)] }
            if hrtDays >= 0, chance(0.9) { log.hrtTaken = settings.hrtRegimen }
            if dayNumber.isMultiple(of: 3) { log.supplements = ["Vitamin D", "Magnesium"] }
            if dayNumber.isMultiple(of: 7) { log.weightKg = 68.4 + progress * 1.6 + noise(0.3) }
            log.wristTemperatureCelsius = 35.4 + Double(sweats) * 0.08 + noise(0.08)

            if metrics.sleepHours == nil { metrics.sleepHours = 7.3 - Double(sweats) * 0.55 + noise(0.4) }
            if metrics.restingHeartRate == nil { metrics.restingHeartRate = 61 + Double(sweats) * 0.8 + noise(1.2) }
            if metrics.heartRateVariabilityMs == nil { metrics.heartRateVariabilityMs = 42 - Double(sweats) * 2 + noise(4) }
            if metrics.steps == nil { metrics.steps = 7800 + noise(2600) }
            if metrics.exerciseMinutes == nil { metrics.exerciseMinutes = 28 + noise(14) }
        }

        // A few things MenoPlan "noticed", spread across recent months.
        let noticed: [(id: String, symbol: String, title: String, detail: String, first: Date, days: Int)] = [
            ("longCycle", "calendar.badge.clock", "A longer cycle than usual",
             "Cycles often lengthen and vary in perimenopause.", addingDays(45, to: starts[plan.count - 1]), 10),
            ("shortSleep", "bed.double", "Short on sleep this week",
             "You've averaged under 7 hours of sleep. Night sweats and hot flushes often break up sleep.", daysAgo(55), 6)
        ]
        for item in noticed {
            let signal = MenoPlan.CycleSignal(id: item.id, tone: .info, symbol: item.symbol, title: item.title, detail: item.detail, surfaces: [.home, .luna])
            let row = NoticedSignal(signal: signal, on: item.first)
            row.lastSeen = min(today, addingDays(item.days - 1, to: item.first))
            row.seenAt = row.lastSeen
            modelContext.insert(row)
        }

        try? modelContext.save()
    }
}

/// Deterministic randomness for the sample data (SplitMix64), so screenshots
/// come out the same every time.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
