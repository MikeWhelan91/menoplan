import Foundation
import SwiftData

/// Where a signal is worth surfacing. One engine feeds every surface so Home,
/// the result page, weekly updates and Luna can never disagree about what the
/// person's data shows.
enum CycleSignalSurface: Hashable {
    case luna
    case weekly
    case home
    case ovulationResult
}

struct CycleSignal: Identifiable, Equatable {
    enum Tone: Int, Comparable {
        case info, positive, attention
        static func < (lhs: Tone, rhs: Tone) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Stable identifier, also used as the fact key sent to Luna.
    let id: String
    let tone: Tone
    let symbol: String
    let title: String
    let detail: String
    let surfaces: Set<CycleSignalSurface>

    /// Compact line for Luna's context: key, tone and the same plain-English
    /// detail the app shows, so Luna explains it the way the UI does.
    var lunaFact: String { "\(id) [\(tone == .attention ? "attention" : tone == .positive ? "supportive" : "info")]: \(detail)" }
}

/// Everything the engine reads. Built once per screen from the same queries
/// the screen already has.
struct CycleSignalInputs {
    var today: Date = .now
    var window: FertilityWindow?
    var activeCycle: CycleRecord?
    var logs: [DailyFertilityLog]
    var metrics: [DailyHealthMetrics]
    var scans: [Scan]
    var profile: HealthProfile
}

/// Turns the person's own data - cycle, daily log, Apple Health, profile and
/// saved tests - into a short list of grounded observations. Every rule is
/// deliberately conservative and descriptive: it says what the data shows and
/// what that pattern is commonly linked with, never a diagnosis.
enum CycleSignalsEngine {
    static func signals(_ input: CycleSignalInputs, calendar: Calendar = .current) -> [CycleSignal] {
        var signals: [CycleSignal] = []
        let today = calendar.startOfDay(for: input.today)
        func days(from: Date, to: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0 }
        func short(_ date: Date) -> String { DateFormatting.shortDate.string(from: date) }
        let realLogs = input.logs.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        func logs(inLast count: Int) -> [DailyFertilityLog] {
            realLogs.filter { let age = days(from: $0.date, to: today); return age >= 0 && age < count }
        }

        // MARK: Cycle timing

        if let window = input.window, input.activeCycle != nil, window.cycleDay > 45 {
            let longGap = window.cycleDay >= 60
            signals.append(CycleSignal(
                id: "longCycle", tone: .info, symbol: "calendar.badge.clock",
                title: longGap ? "\(window.cycleDay) days since your last period" : "A longer cycle than usual",
                detail: longGap
                    ? "Gaps of 60 days or more between periods are common later in perimenopause. Keep logging, and talk to a doctor if bleeding comes back very heavy or you're unsure what's normal for you."
                    : "You're on cycle day \(window.cycleDay). Cycles often lengthen and vary in perimenopause, and stress, illness or weight change can do it too.",
                surfaces: [.luna, .weekly, .home]
            ))
        }

        // MARK: Things that change how a test reads

        if let water = logs(inLast: 1).first?.waterMl, water >= 2500 {
            signals.append(CycleSignal(
                id: "highFluidIntake", tone: .info, symbol: "drop.fill",
                title: "Lots of water today",
                detail: "You've logged about \(Int((water / 100).rounded()) * 100) ml of water today. Very diluted urine can make test lines look fainter than they are. A test after 2-4 hours without drinking much reads more reliably.",
                surfaces: [.luna, .ovulationResult]
            ))
        }

        let recentObservations = realLogs.filter { days(from: $0.date, to: today) <= 180 }.flatMap { log in log.healthKitObservations.map { (log.date, $0) } }
        if let contraceptive = recentObservations.filter({ $0.1.hasPrefix("Apple Health contraceptive") && days(from: $0.0, to: today) <= 90 }).max(by: { $0.0 < $1.0 }) {
            let method = contraceptive.1.replacingOccurrences(of: "Apple Health contraceptive: ", with: "").lowercased()
            signals.append(CycleSignal(
                id: "hormonalContraception", tone: .attention, symbol: "pills.circle",
                title: "Contraception recorded in Apple Health",
                detail: "Apple Health has contraception (\(method)) recorded from \(short(contraceptive.0)). Hormonal methods can change or stop bleeding, so cycle dates may not reflect your natural cycle.",
                surfaces: [.luna, .weekly, .home, .ovulationResult]
            ))
        } else if input.profile.birthControl?.isCurrentlyUsing == true {
            signals.append(CycleSignal(
                id: "hormonalContraception", tone: .attention, symbol: "pills.circle",
                title: "Using hormonal contraception",
                detail: "You said you use hormonal contraception. It can change or stop bleeding, and home FSH tests may not be reliable while you use it. Your symptoms still tell the story.",
                surfaces: [.luna, .weekly, .ovulationResult]
            ))
        }

        // MARK: Body and lifestyle (Apple Health + daily log)

        let metrics = input.metrics.sorted { $0.date < $1.date }
        func values(_ keyPath: KeyPath<DailyHealthMetrics, Double?>, from start: Int, to end: Int) -> [Double] {
            metrics.filter { let age = days(from: $0.date, to: today); return age >= start && age <= end }.compactMap { $0[keyPath: keyPath] }
        }
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return 0 }
            return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }

        let sleep = values(\.sleepHours, from: 0, to: 6).filter { $0 > 0.5 }
        if sleep.count >= 4, mean(sleep) < 6 {
            signals.append(CycleSignal(
                id: "shortSleep", tone: .info, symbol: "bed.double",
                title: "Short on sleep this week",
                detail: String(format: "You've averaged %.1f hours of sleep over the last week. Night sweats, hot flushes and a racing mind are common reasons in perimenopause, and it's worth mentioning to a doctor if it keeps happening.", mean(sleep)),
                surfaces: [.luna, .weekly, .home]
            ))
        }

        let recentHR = values(\.restingHeartRate, from: 0, to: 4)
        let baselineHR = values(\.restingHeartRate, from: 7, to: 40)
        if recentHR.count >= 3, baselineHR.count >= 10 {
            let rise = mean(recentHR) - median(baselineHR)
            if rise >= 3 {
                let detail = "Your resting heart rate is about \(Int(rise.rounded())) bpm above your usual level. Hot flushes and night sweats, poor sleep, illness, stress or alcohol can all raise it."
                signals.append(CycleSignal(id: "restingHeartRateUp", tone: .info, symbol: "heart", title: "Resting heart rate is up", detail: detail,
                                           surfaces: [.luna, .weekly]))
            }
        }

        let recentHRV = values(\.heartRateVariabilityMs, from: 0, to: 6)
        let baselineHRV = values(\.heartRateVariabilityMs, from: 7, to: 40)
        if recentHRV.count >= 3, baselineHRV.count >= 10, mean(recentHRV) < median(baselineHRV) * 0.8 {
            signals.append(CycleSignal(
                id: "hrvDown", tone: .info, symbol: "waveform.path.ecg",
                title: "Heart rate variability is lower",
                detail: "Your heart rate variability has been lower than usual this week, often a sign of stress, poor sleep, illness or hard training.",
                surfaces: [.luna, .weekly]
            ))
        }

        let exercise = values(\.exerciseMinutes, from: 0, to: 6)
        if exercise.count >= 5, mean(exercise) >= 90 {
            signals.append(CycleSignal(
                id: "highTrainingLoad", tone: .info, symbol: "figure.run",
                title: "A heavy training week",
                detail: "You've averaged \(Int(mean(exercise).rounded())) minutes of exercise a day this week. Recovery and sleep matter more as hormones change.",
                surfaces: [.luna, .weekly]
            ))
        }

        let weighIns = realLogs.compactMap { log in log.weightKg.map { (calendar.startOfDay(for: log.date), $0) } }.sorted { $0.0 < $1.0 }
        if let latest = weighIns.last,
           let earlier = weighIns.last(where: { (30...120).contains(days(from: $0.0, to: latest.0)) }) {
            let change = latest.1 - earlier.1
            let percent = abs(change) / earlier.1 * 100
            if percent >= 5 {
                signals.append(CycleSignal(
                    id: "weightChange", tone: .info, symbol: "scalemass",
                    title: change > 0 ? "Weight has gone up" : "Weight has come down",
                    detail: String(format: "Your weight has changed by about %.1f kg (%.0f%%) since %@. Weight changes are common through menopause, and it can be worth mentioning to a doctor if it happened quickly.", abs(change), percent, short(earlier.0)),
                    surfaces: [.luna, .weekly, .home]
                ))
            }
        }

        return caveatedForContraception(signals).sorted { $0.tone > $1.tone }
    }

    /// Short aggregates of recent body and activity data for Luna - enough to
    /// answer "has my sleep been bad?" or "is my weight affecting this?"
    /// without sending every raw day.
    static func bodySummary(logs: [DailyFertilityLog], metrics: [DailyHealthMetrics], today: Date = .now, calendar: Calendar = .current) -> [String] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let day = calendar.startOfDay(for: today)
        func age(_ date: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: day).day ?? 0 }
        func average(_ keyPath: KeyPath<DailyHealthMetrics, Double?>, _ range: ClosedRange<Int>) -> (value: Double, count: Int)? {
            let values = metrics.filter { range.contains(age($0.date)) }.compactMap { $0[keyPath: keyPath] }.filter { $0 > 0 }
            guard !values.isEmpty else { return nil }
            return (values.reduce(0, +) / Double(values.count), values.count)
        }
        var lines: [String] = []
        let weighIns = logs.compactMap { log in log.weightKg.map { (log.date, $0) } }.sorted { $0.0 < $1.0 }
        if let latest = weighIns.last {
            var line = String(format: "latestWeightKg=%.1f on %@", latest.1, formatter.string(from: latest.0))
            if let earlier = weighIns.last(where: { (30...120).contains(calendar.dateComponents([.day], from: $0.0, to: latest.0).day ?? 0) }) {
                line += String(format: "; changeKg=%+.1f since %@", latest.1 - earlier.1, formatter.string(from: earlier.0))
            }
            lines.append(line)
        }
        if let sleep = average(\.sleepHours, 0...6) { lines.append(String(format: "sleepHoursAvgLast7Nights=%.1f (nights=%d)", sleep.value, sleep.count)) }
        if let recent = average(\.restingHeartRate, 0...4) {
            var line = String(format: "restingHeartRateAvgLast5Days=%.0fbpm", recent.value)
            if let usual = average(\.restingHeartRate, 7...40) { line += String(format: "; usual=%.0fbpm", usual.value) }
            lines.append(line)
        }
        if let recent = average(\.heartRateVariabilityMs, 0...6) {
            var line = String(format: "hrvAvgLast7Days=%.0fms", recent.value)
            if let usual = average(\.heartRateVariabilityMs, 7...40) { line += String(format: "; usual=%.0fms", usual.value) }
            lines.append(line)
        }
        if let steps = average(\.steps, 0...6) { lines.append(String(format: "stepsAvgLast7Days=%.0f", steps.value)) }
        if let exercise = average(\.exerciseMinutes, 0...6) {
            let workouts = metrics.filter { (0...6).contains(age($0.date)) }.compactMap(\.workoutCount).reduce(0, +)
            lines.append(String(format: "exerciseMinutesAvgLast7Days=%.0f; workoutsLast7Days=%d", exercise.value, workouts))
        }
        if let water = logs.first(where: { age($0.date) == 0 })?.waterMl { lines.append("waterTodayMl=\(Int(water.rounded()))") }
        let wrist = logs.filter { age($0.date) <= 13 }.compactMap(\.wristTemperatureCelsius)
        if wrist.count >= 3 {
            lines.append(String(format: "appleWatchWristTemperatureLast14Days=%.2f-%.2f°C (overnight wrist temperature; compare only with itself)", wrist.min() ?? 0, wrist.max() ?? 0))
        }
        return lines
    }

    /// Cycle-timing observations get a caveat instead of a push when
    /// contraception is recorded - they may not reflect a natural cycle, and
    /// Home's countdown already leads with that.
    private static let cycleTimingSignalIDs: Set<String> = [
        "longCycle"
    ]

    private static func caveatedForContraception(_ signals: [CycleSignal]) -> [CycleSignal] {
        guard signals.contains(where: { $0.id == "hormonalContraception" }) else { return signals }
        return signals.map { signal in
            guard cycleTimingSignalIDs.contains(signal.id) else { return signal }
            return CycleSignal(
                id: signal.id,
                tone: .info,
                symbol: signal.symbol,
                title: signal.title,
                detail: signal.detail + " Contraception is recorded, so this may not reflect your natural cycle.",
                surfaces: signal.surfaces
            )
        }
    }

    static func signals(for surface: CycleSignalSurface, _ input: CycleSignalInputs, limit: Int = .max) -> [CycleSignal] {
        Array(signals(input).filter { $0.surfaces.contains(surface) }.prefix(limit))
    }
}

/// Keeps NoticedSignal history in step with what Home shows. Only Home's
/// signals are recorded, so a day's "What MenoPlan noticed" always matches
/// what the info button showed that day - result-page-only notes (such as
/// hydration) stay on the result page.
@MainActor
enum CycleSignalHistory {
    /// Signals that never appear on Home. Early builds recorded these too;
    /// they're removed from history so the calendar matches Home.
    static let resultOnlySignalIDs: Set<String> = [
        "highFluidIntake", "hrvDown", "highTrainingLoad"
    ]

    static func record(_ signals: [CycleSignal], today: Date = .now, context: ModelContext, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return }
        var existing = (try? context.fetch(FetchDescriptor<NoticedSignal>())) ?? []
        var changed = false
        for stale in existing where resultOnlySignalIDs.contains(stale.signalID) {
            context.delete(stale)
            changed = true
        }
        existing.removeAll { resultOnlySignalIDs.contains($0.signalID) }
        let signals = signals.filter { $0.surfaces.contains(.home) }
        for signal in signals {
            let latest = existing.filter { $0.signalID == signal.id }.max { $0.lastSeen < $1.lastSeen }
            if let latest, calendar.startOfDay(for: latest.lastSeen) >= yesterday {
                // Still the same run - it stays on the day it first appeared.
                if calendar.startOfDay(for: latest.lastSeen) < day {
                    latest.lastSeen = day
                    changed = true
                }
            } else {
                context.insert(NoticedSignal(signal: signal, on: day, calendar: calendar))
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
