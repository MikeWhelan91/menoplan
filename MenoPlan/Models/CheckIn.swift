import Foundation

/// How much symptoms got in the way of the day - the one tap that matters
/// most at an appointment ("how is this affecting your life?").
enum DayImpact: String, CaseIterable, Codable, Identifiable {
    case notAtAll, some, lots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notAtAll: "Not at all"
        case .some: "A bit"
        case .lots: "A lot"
        }
    }
    var symbol: String {
        switch self {
        case .notAtAll: "sun.max.fill"
        case .some: "cloud.sun.fill"
        case .lots: "cloud.rain.fill"
        }
    }
}

/// The symptoms someone pins to Home's check-in. Most are rated mild /
/// moderate / severe; hot flushes and night sweats are counted; sleep uses
/// the log's sleep quality.
enum FocusSymptoms {
    enum Kind: Equatable { case severity, counter, sleep }

    static let hotFlushes = "Hot Flushes"
    static let nightSweats = "Night Sweats"
    static let sleep = "Sleep"
    static let maximum = 5

    /// Offered in onboarding and Settings, ordered by how often people in
    /// menopause communities say each one affects them most.
    static let suggested = [
        "Irritability", "Anxiety", sleep, "Brain Fog", hotFlushes, nightSweats, "Joint Pain",
        "Fatigue", "Low Mood", "Headache", "Palpitations", "Vaginal Dryness", "Bladder Leaks", "Low Libido"
    ]
    /// Used until the person chooses their own.
    static let defaults = [sleep, "Anxiety", "Brain Fog", "Joint Pain", hotFlushes]

    static func kind(of name: String) -> Kind {
        switch name {
        case hotFlushes, nightSweats: .counter
        case sleep: .sleep
        default: .severity
        }
    }

    static func symbol(for name: String) -> String {
        switch name {
        case hotFlushes: "flame.fill"
        case nightSweats: "moon.stars.fill"
        case sleep: "bed.double.fill"
        case "Irritability": "bolt.fill"
        case "Anxiety": "exclamationmark.bubble.fill"
        case "Low Mood": "cloud.fill"
        case "Brain Fog": "cloud.fog.fill"
        case "Joint Pain": "figure.walk"
        case "Fatigue": "battery.25percent"
        case "Headache": "brain.head.profile"
        case "Palpitations": "heart.text.square.fill"
        case "Vaginal Dryness": "sun.dust.fill"
        case "Bladder Leaks": "drop.triangle.fill"
        case "Low Libido": "heart.slash.fill"
        default: "circle.fill"
        }
    }

    /// Whether a day's log counts as having this symptom.
    static func isPresent(_ name: String, in log: DailyFertilityLog) -> Bool {
        switch kind(of: name) {
        case .counter: (count(name, in: log) ?? 0) > 0
        case .sleep: log.sleepQuality == .broken || log.sleepQuality == .poor
        case .severity: log.symptoms.contains(name)
        }
    }

    static func count(_ name: String, in log: DailyFertilityLog) -> Int? {
        name == hotFlushes ? log.hotFlushCount : name == nightSweats ? log.nightSweatCount : nil
    }

    static func setCount(_ value: Int?, for name: String, in log: DailyFertilityLog) {
        let clamped = value.map { min(max($0, 0), 50) }.flatMap { $0 == 0 ? nil : $0 }
        if name == hotFlushes { log.hotFlushCount = clamped } else if name == nightSweats { log.nightSweatCount = clamped }
        log.updatedAt = .now
    }

    /// One tap on a check-in chip: severity symptoms step none → mild →
    /// moderate → severe → none; sleep steps through slept well → broken →
    /// poor → not logged.
    static func advance(_ name: String, in log: DailyFertilityLog) {
        switch kind(of: name) {
        case .counter:
            setCount((count(name, in: log) ?? 0) + 1, for: name, in: log)
        case .sleep:
            let order: [SleepQuality?] = [nil, .good, .broken, .poor]
            let index = order.firstIndex(of: log.sleepQuality) ?? 0
            log.sleepQuality = order[(index + 1) % order.count]
        case .severity:
            let order: [SymptomSeverity?] = [nil, .mild, .moderate, .severe]
            let current = log.symptoms.contains(name) ? (log.severity(of: name) ?? .mild) : nil
            let index = order.firstIndex(of: current) ?? 0
            log.setSeverity(order[(index + 1) % order.count], for: name)
        }
    }

    /// Short state for a chip, e.g. "Moderate", "Broken", "3".
    static func state(of name: String, in log: DailyFertilityLog?) -> String? {
        guard let log else { return nil }
        switch kind(of: name) {
        case .counter: return count(name, in: log).map(String.init)
        case .sleep: return log.sleepQuality.map { $0 == .good ? "Good" : $0 == .broken ? "Broken" : "Poor" }
        case .severity: return log.symptoms.contains(name) ? (log.severity(of: name) ?? .mild).title : nil
        }
    }
}

extension SymptomSeverity {
    var level: Int {
        switch self {
        case .mild: 1
        case .moderate: 2
        case .severe: 3
        }
    }
}
