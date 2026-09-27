import Foundation
import SwiftData

/// Where a signal is worth surfacing. One engine feeds every surface so Home,
/// the result page, weekly updates and Luna can never disagree about what the
/// person's data shows.
enum CycleSignalSurface: Hashable {
    case luna
    case weekly
    case home
    case pregnancyResult
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

/// A sustained post-ovulation temperature rise, found with the standard
/// "three over six" rule: three readings above the highest of the previous
/// six, the third at least 0.2°C above it.
struct ThermalShift: Equatable {
    /// First day of the higher-temperature run.
    let shiftDay: Date
    /// Ovulation is estimated as the day before the rise.
    let estimatedOvulation: Date
    /// Highest of the six pre-shift readings - the "coverline".
    let coverlineCelsius: Double
    let usesWristTemperature: Bool
}

enum ThermalShiftDetector {
    static let minimumRiseCelsius = 0.2
    /// Readings more than this many days apart don't count as a run.
    static let maximumGapDays = 3

    static func detect(
        in logs: [DailyFertilityLog],
        from cycleStart: Date,
        until cycleEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> ThermalShift? {
        let start = calendar.startOfDay(for: cycleStart)
        let end = cycleEnd.map { calendar.startOfDay(for: $0) } ?? .distantFuture
        let cycleLogs = logs
            .filter { let day = calendar.startOfDay(for: $0.date); return day >= start && day < end }
            .sorted { $0.date < $1.date }
        let basal = cycleLogs.compactMap { log in log.basalBodyTemperatureCelsius.map { (calendar.startOfDay(for: log.date), $0) } }
        if let shift = detect(series: basal, cycleStart: start, calendar: calendar) {
            return ThermalShift(shiftDay: shift.day, estimatedOvulation: shift.ovulation, coverlineCelsius: shift.coverline, usesWristTemperature: false)
        }
        // Wrist temperature only when there aren't enough thermometer
        // readings to judge - the two are never mixed in one series.
        guard basal.count < 9 else { return nil }
        let wrist = cycleLogs.compactMap { log in log.wristTemperatureCelsius.map { (calendar.startOfDay(for: log.date), $0) } }
        guard let shift = detect(series: wrist, cycleStart: start, calendar: calendar) else { return nil }
        return ThermalShift(shiftDay: shift.day, estimatedOvulation: shift.ovulation, coverlineCelsius: shift.coverline, usesWristTemperature: true)
    }

    static func detect(series: [(Date, Double)], cycleStart: Date, calendar: Calendar = .current) -> (day: Date, ovulation: Date, coverline: Double)? {
        guard series.count >= 9 else { return nil }
        for index in 6..<(series.count - 2) {
            let lows = series[(index - 6)..<index]
            let highs = series[index...(index + 2)]
            guard let firstLow = lows.first?.0, let lastHigh = highs.last?.0,
                  (calendar.dateComponents([.day], from: firstLow, to: lastHigh).day ?? 99) <= 9 + maximumGapDays * 2
            else { continue }
            let coverline = lows.map(\.1).max() ?? 0
            let values = highs.map(\.1)
            guard values.allSatisfy({ $0 > coverline }), (values.last ?? 0) >= coverline + minimumRiseCelsius else { continue }
            let shiftDay = series[index].0
            // Ovulation before cycle day 8 isn't plausible; that's noise
            // from the period days, not a luteal rise.
            let cycleDay = FertilityWindowCalculator.cycleDay(for: shiftDay, cycleStart: cycleStart, calendar: calendar)
            guard cycleDay >= 9 else { continue }
            let ovulation = calendar.date(byAdding: .day, value: -1, to: shiftDay) ?? shiftDay
            return (shiftDay, ovulation, coverline)
        }
        return nil
    }
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
    var tryingToConceive: Bool
    var pregnancyState: PregnancyJourneyState
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
        let isPregnant = input.pregnancyState == .confirmedPregnant

        // MARK: Cycle timing evidence

        if let cycle = input.activeCycle, let window = input.window, !isPregnant {
            let cycleLogs = realLogs
                .filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: cycle.startDate) }
                .sorted { $0.date < $1.date }
            let shift = ThermalShiftDetector.detect(in: realLogs, from: cycle.startDate, until: cycle.endDate, calendar: calendar)
            // One answer to "has ovulation shown up yet?" for every rule below,
            // including a rise detected before the cycle has been updated.
            let hasOvulationEvidence = shift != nil
                || cycle.confirmedOvulationDate != nil
                || cycle.ovulationSource?.isOvulationEvidence == true
            let source = shift?.usesWristTemperature == true ? "wrist temperature" : "temperatures"
            if let shift {
                let highFor = days(from: shift.shiftDay, to: today) + 1
                let recentTemps = cycleLogs.compactMap { shift.usesWristTemperature ? $0.wristTemperatureCelsius : $0.basalBodyTemperatureCelsius }.suffix(3)
                let stillHigh = recentTemps.count >= 3 && recentTemps.allSatisfy { $0 > shift.coverlineCelsius }
                if highFor >= 18, stillHigh, input.tryingToConceive {
                    signals.append(CycleSignal(
                        id: "sustainedHighTemperature", tone: .attention, symbol: "thermometer.high",
                        title: "Temperatures high for \(highFor) days",
                        detail: "Your \(source) have stayed above your pre-ovulation level for \(highFor) days. A rise lasting 18 days or more is one of the earlier signs of pregnancy, and a pregnancy test will give you a clear answer.",
                        surfaces: [.luna, .weekly, .home, .pregnancyResult]
                    ))
                } else {
                    signals.append(CycleSignal(
                        id: "temperatureShift", tone: .positive, symbol: "thermometer.sun",
                        title: "Temperature shift detected",
                        detail: "Your \(source) rose and stayed up from \(short(shift.shiftDay)), the pattern that follows ovulation, so ovulation most likely happened around \(short(shift.estimatedOvulation)).",
                        surfaces: [.luna, .weekly, .home, .ovulationResult, .pregnancyResult]
                    ))
                }
            } else {
                let temps = cycleLogs.compactMap(\.basalBodyTemperatureCelsius)
                // A Peak or confirmed date already places ovulation, and BBT
                // often lags a Peak, so "may be later" would contradict it.
                if temps.count >= 8, !hasOvulationEvidence, days(from: window.predictedOvulationDate, to: today) >= 4 {
                    signals.append(CycleSignal(
                        id: "noTemperatureShiftYet", tone: .info, symbol: "thermometer.medium",
                        title: "No temperature rise yet",
                        detail: "There's no sustained temperature rise yet, although ovulation was estimated for \(short(window.predictedOvulationDate)). Ovulation may be later than the calendar suggests this cycle, so keep ovulation testing.",
                        surfaces: [.luna, .weekly, .ovulationResult]
                    ))
                }
            }

            // Fertile-quality mucus, and whether it's arriving earlier than the calendar expects.
            if let mucusLog = logs(inLast: 3).first(where: { ["Egg White", "Egg white", "Watery"].contains($0.cervicalMucusRaw ?? "") }) {
                let kind = (mucusLog.cervicalMucusRaw ?? "").lowercased()
                let early = days(from: mucusLog.date, to: window.fertileStartDate) >= 2
                let afterEstimate = days(from: window.predictedOvulationDate, to: mucusLog.date) >= 2
                let detail: String
                if early {
                    detail = "You logged \(kind) mucus on \(short(mucusLog.date)), earlier than your estimated fertile window. Your body may be heading towards ovulation sooner than the calendar expects, so start ovulation tests now."
                } else if afterEstimate && !hasOvulationEvidence {
                    detail = "You logged \(kind) mucus on \(short(mucusLog.date)), after your estimated ovulation day, and there's no Peak test or temperature rise yet this cycle. Ovulation may be later than the calendar estimated, so keep ovulation testing."
                } else if afterEstimate {
                    detail = "You logged \(kind) mucus on \(short(mucusLog.date)). Your data suggests ovulation has already happened this cycle, and wetter days can also show up afterwards, so this doesn't change your estimate."
                } else {
                    detail = "You logged \(kind) mucus on \(short(mucusLog.date)), one of the clearest signs that ovulation is close."
                }
                signals.append(CycleSignal(
                    id: "fertileMucus", tone: afterEstimate ? .info : .positive, symbol: "drop.triangle",
                    title: afterEstimate && !hasOvulationEvidence ? "Fertile mucus later than expected" : "Fertile-quality mucus",
                    detail: detail,
                    surfaces: [.luna, .weekly, .home, .ovulationResult]
                ))
            }

            if cycleLogs.contains(where: { $0.healthKitObservations.contains("Apple Health OPK: LH surge") }) {
                signals.append(CycleSignal(
                    id: "healthLHSurge", tone: .positive, symbol: "heart.text.square",
                    title: "LH surge recorded in Apple Health",
                    detail: "A positive ovulation test was recorded in Apple Health this cycle. Ovulation usually follows within 1-2 days of a surge.",
                    surfaces: [.luna, .weekly, .ovulationResult]
                ))
            }

            let ovulation = calendar.startOfDay(for: window.predictedOvulationDate)
            if let painLog = cycleLogs.first(where: { $0.symptoms.contains("Pelvic Pain") && abs(days(from: ovulation, to: $0.date)) <= 2 }) {
                signals.append(CycleSignal(
                    id: "midCyclePain", tone: .info, symbol: "bolt.heart",
                    title: "Mid-cycle pelvic pain",
                    detail: "You logged pelvic pain on \(short(painLog.date)), close to your estimated ovulation. One-sided twinges around ovulation are common. Severe or lasting pain is worth checking with a doctor.",
                    surfaces: [.luna, .weekly]
                ))
            }

            if input.tryingToConceive,
               let spotLog = cycleLogs.first(where: { log in
                   let dpo = days(from: ovulation, to: log.date)
                   return (6...12).contains(dpo) && (log.flowIntensity == .spotting || log.symptoms.contains("Spotting"))
               }) {
                signals.append(CycleSignal(
                    id: "lutealSpotting", tone: .info, symbol: "circle.dotted",
                    title: "Spotting after ovulation",
                    detail: "You logged spotting on \(short(spotLog.date)), about \(days(from: ovulation, to: spotLog.date)) days after estimated ovulation. Some people spot around implantation, but it's also common in cycles without a pregnancy. A test from your expected period is the reliable check.",
                    surfaces: [.luna, .weekly, .pregnancyResult]
                ))
            }

            let late = days(from: window.nextPeriodDate, to: today)
            let hasPositivePregnancyTest = input.scans.contains { scan in
                scan.testType == .pregnancy && !scan.excludedFromCalculations
                    && [.appearsPositive, .faintLineDetected].contains(scan.resultType)
                    && calendar.startOfDay(for: scan.createdAt) >= calendar.startOfDay(for: cycle.startDate)
            }
            if late >= 2, !hasPositivePregnancyTest, input.tryingToConceive {
                signals.append(CycleSignal(
                    id: "periodLate", tone: .attention, symbol: "calendar.badge.exclamationmark",
                    title: "Period \(late) days late",
                    detail: "Your period was expected \(short(window.nextPeriodDate)) and hasn't been logged. A pregnancy test now gives a reliable answer. If it's negative and your period still doesn't come, retest in 2-3 days.",
                    surfaces: [.luna, .weekly, .pregnancyResult]
                ))
            }
            if window.cycleDay > 45, !hasPositivePregnancyTest {
                signals.append(CycleSignal(
                    id: "longCycle", tone: .attention, symbol: "calendar.badge.clock",
                    title: "A longer cycle than usual",
                    detail: "You're on cycle day \(window.cycleDay). Stress, illness, weight change, PCOS or coming off birth control can all lengthen a cycle. If long cycles keep happening, it's worth mentioning to a doctor.",
                    surfaces: [.luna, .weekly, .home]
                ))
            }
        }

        // MARK: Things that change how a test reads

        if let water = logs(inLast: 1).first?.waterMl, water >= 2500 {
            signals.append(CycleSignal(
                id: "highFluidIntake", tone: .info, symbol: "drop.fill",
                title: "Lots of water today",
                detail: "You've logged about \(Int((water / 100).rounded()) * 100) ml of water today. Very diluted urine can make test lines look fainter than they are. A test after 2-4 hours without drinking much reads more reliably.",
                surfaces: [.luna, .pregnancyResult, .ovulationResult]
            ))
        }

        let recentObservations = realLogs.filter { days(from: $0.date, to: today) <= 180 }.flatMap { log in log.healthKitObservations.map { (log.date, $0) } }
        if let contraceptive = recentObservations.filter({ $0.1.hasPrefix("Apple Health contraceptive") && days(from: $0.0, to: today) <= 90 }).max(by: { $0.0 < $1.0 }) {
            let method = contraceptive.1.replacingOccurrences(of: "Apple Health contraceptive: ", with: "").lowercased()
            signals.append(CycleSignal(
                id: "hormonalContraception", tone: .attention, symbol: "pills.circle",
                title: "Contraception recorded in Apple Health",
                detail: "Apple Health has contraception (\(method)) recorded from \(short(contraceptive.0)). Hormonal methods usually stop ovulation and keep LH low, so cycle predictions and ovulation tests may not reflect your natural cycle yet.",
                surfaces: [.luna, .weekly, .home, .ovulationResult]
            ))
        } else if input.profile.birthControl == .stillUsing {
            signals.append(CycleSignal(
                id: "hormonalContraception", tone: .attention, symbol: "pills.circle",
                title: "Using birth control",
                detail: "You said you're still using birth control. Hormonal methods usually stop ovulation and keep LH low, so cycle predictions and ovulation tests may not reflect your natural cycle.",
                surfaces: [.luna, .weekly, .ovulationResult]
            ))
        }

        if let lactation = recentObservations.filter({ $0.1 == "Apple Health: lactation recorded" }).max(by: { $0.0 < $1.0 }) {
            signals.append(CycleSignal(
                id: "breastfeeding", tone: .info, symbol: "figure.and.child.holdinghands",
                title: "Breastfeeding recorded",
                detail: "Apple Health has lactation recorded from \(short(lactation.0)). Breastfeeding can delay ovulation and make cycles irregular, and ovulation tests may read low or jump around until cycles settle.",
                surfaces: [.luna, .weekly, .home, .ovulationResult]
            ))
        }

        if input.profile.hasPCOS {
            signals.append(CycleSignal(
                id: "pcosLH", tone: .info, symbol: "waveform.path.ecg",
                title: "PCOS and ovulation tests",
                detail: "With PCOS, LH can stay raised for several days, so ovulation tests may read High more often. Your trend across several tests tells you more than any single one.",
                surfaces: [.luna, .ovulationResult]
            ))
        }

        if let fever = logs(inLast: 3).first(where: { ($0.basalBodyTemperatureCelsius ?? 0) >= 37.6 }) {
            signals.append(CycleSignal(
                id: "possibleFever", tone: .info, symbol: "thermometer.high",
                title: "An unusually high temperature",
                detail: "Your temperature on \(short(fever.date)) was high enough to be a fever. Illness can push BBT up for a few days, so those readings are less useful for spotting ovulation.",
                surfaces: [.luna, .weekly]
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
                detail: String(format: "You've averaged %.1f hours of sleep over the last week. Ongoing short sleep and stress can nudge ovulation later, and poor sleep makes BBT readings less reliable.", mean(sleep)),
                surfaces: [.luna, .weekly, .home]
            ))
        }

        let recentHR = values(\.restingHeartRate, from: 0, to: 4)
        let baselineHR = values(\.restingHeartRate, from: 7, to: 40)
        if recentHR.count >= 3, baselineHR.count >= 10 {
            let rise = mean(recentHR) - median(baselineHR)
            if rise >= 3 {
                let window = input.window
                let pastPeriod = window.map { days(from: $0.nextPeriodDate, to: today) >= 1 } ?? false
                let luteal = window.map { today > calendar.startOfDay(for: $0.predictedOvulationDate) && today < calendar.startOfDay(for: $0.nextPeriodDate) } ?? false
                let detail: String
                let tone: CycleSignal.Tone
                if pastPeriod && input.tryingToConceive && !isPregnant {
                    tone = .attention
                    detail = "Your resting heart rate is about \(Int(rise.rounded())) bpm above your usual level and your period is due. A resting heart rate that stays raised after a missed period can be an early pregnancy sign. It can also mean illness, so a test is the way to know."
                } else if luteal {
                    tone = .info
                    detail = "Your resting heart rate is about \(Int(rise.rounded())) bpm above your usual level. A small rise after ovulation is normal as progesterone increases."
                } else {
                    tone = .info
                    detail = "Your resting heart rate is about \(Int(rise.rounded())) bpm above your usual level. Illness, stress, alcohol or poor sleep can all raise it, and the same things can shift cycle timing."
                }
                signals.append(CycleSignal(id: "restingHeartRateUp", tone: tone, symbol: "heart", title: "Resting heart rate is up", detail: detail,
                                           surfaces: tone == .attention ? [.luna, .weekly, .home, .pregnancyResult] : [.luna, .weekly]))
            }
        }

        let recentHRV = values(\.heartRateVariabilityMs, from: 0, to: 6)
        let baselineHRV = values(\.heartRateVariabilityMs, from: 7, to: 40)
        if recentHRV.count >= 3, baselineHRV.count >= 10, mean(recentHRV) < median(baselineHRV) * 0.8 {
            signals.append(CycleSignal(
                id: "hrvDown", tone: .info, symbol: "waveform.path.ecg",
                title: "Heart rate variability is lower",
                detail: "Your heart rate variability has been lower than usual this week, often a sign of stress, illness or hard training. Stress can delay ovulation, so your fertile window may come later this cycle.",
                surfaces: [.luna, .weekly]
            ))
        }

        let exercise = values(\.exerciseMinutes, from: 0, to: 6)
        if exercise.count >= 5, mean(exercise) >= 90 {
            signals.append(CycleSignal(
                id: "highTrainingLoad", tone: .info, symbol: "figure.run",
                title: "A heavy training week",
                detail: "You've averaged \(Int(mean(exercise).rounded())) minutes of exercise a day this week. Very high training loads, especially with low energy intake, can delay ovulation or lengthen cycles.",
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
                    detail: String(format: "Your weight has changed by about %.1f kg (%.0f%%) since %@. Changes of 5%% or more can shift when you ovulate, so predictions may take a cycle or two to catch up.", abs(change), percent, short(earlier.0)),
                    surfaces: [.luna, .weekly, .home]
                ))
            }
        }

        if let category = input.profile.bmiCategory, category.mayAffectOvulation, let note = category.fertilityNote {
            signals.append(CycleSignal(id: "bmi", tone: .info, symbol: "figure.stand", title: category.title, detail: note, surfaces: [.luna, .ovulationResult]))
        }

        if !isPregnant, let pregnancy = recentObservations.filter({ $0.1 == "Apple Health: pregnancy recorded" }).max(by: { $0.0 < $1.0 }), days(from: pregnancy.0, to: today) <= 300 {
            signals.append(CycleSignal(
                id: "healthPregnancy", tone: .info, symbol: "heart.text.square",
                title: "Pregnancy recorded in Apple Health",
                detail: FeatureFlags.pregnancyModeEnabled
                    ? "Apple Health has a pregnancy recorded from \(short(pregnancy.0)). If that's current, you can switch MenoPlan to pregnancy mode. If it has ended, cycles can take a while to settle."
                    : "Apple Health has a pregnancy recorded from \(short(pregnancy.0)). If it has ended, cycles can take a while to settle, so predictions may shift for a few months.",
                surfaces: [.luna, .weekly, .home]
            ))
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
            lines.append(String(format: "appleWatchWristTemperatureLast14Days=%.2f-%.2f°C (wrist reads lower than BBT; compare only with itself)", wrist.min() ?? 0, wrist.max() ?? 0))
        }
        return lines
    }

    /// True when the data says ovulation hasn't shown up where the calendar
    /// drew it - Home's countdown and the Calendar header both use this.
    static func suggestsLaterOvulation(_ signals: [CycleSignal]) -> Bool {
        signals.contains { $0.id == "noTemperatureShiftYet" || ($0.id == "fertileMucus" && $0.title == "Fertile mucus later than expected") }
    }

    /// Cycle-timing observations get a caveat instead of a push when
    /// contraception is recorded - they may not reflect a natural cycle, and
    /// Home's countdown already leads with that.
    private static let cycleTimingSignalIDs: Set<String> = [
        "temperatureShift", "noTemperatureShiftYet", "fertileMucus", "healthLHSurge", "midCyclePain", "longCycle"
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
/// what the info button showed that day - result-page-only notes (PCOS,
/// hydration) stay on the result page.
@MainActor
enum CycleSignalHistory {
    /// Signals that never appear on Home. Early builds recorded these too;
    /// they're removed from history so the calendar matches Home.
    static let resultOnlySignalIDs: Set<String> = [
        "noTemperatureShiftYet", "healthLHSurge", "midCyclePain", "lutealSpotting", "periodLate",
        "highFluidIntake", "pcosLH", "possibleFever", "hrvDown", "highTrainingLoad", "bmi"
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
