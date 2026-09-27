import Foundation

/// Answers from the personalisation quiz. Each one changes something the app
/// actually does - how confident cycle estimates are presented, or whether a
/// gentle "talk to a doctor" note appears - rather than only steering content.

enum CycleRegularity: String, CaseIterable, Codable, Identifiable {
    case regular, irregular, unsure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "Yes"
        case .irregular: "No"
        case .unsure: "I don’t know"
        }
    }

    var response: String? {
        switch self {
        case .regular: nil
        case .irregular: "Changing cycles are one of the most common early signs of perimenopause. MenoPlan will track how much yours vary."
        case .unsure: "No problem. As you log a few periods, MenoPlan learns how much your cycle varies."
        }
    }
}

enum ReproductiveCondition: String, CaseIterable, Codable, Identifiable {
    case pcos, endometriosis, fibroids, thyroid, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pcos: "Polycystic ovary syndrome (PCOS)"
        case .endometriosis: "Endometriosis"
        case .fibroids: "Fibroids"
        case .thyroid: "A thyroid condition"
        case .other: "Something else"
        }
    }

    var response: String? {
        switch self {
        default: nil
        }
    }
}

enum BirthControlRecency: String, CaseIterable, Codable, Identifiable {
    case none, stillUsing, pill, iud, implantOrShot, nonHormonal, preferNotToSay
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No"
        case .stillUsing: "I’m still using birth control"
        case .pill: "Yes, I was on the pill"
        case .iud: "Yes, I had an IUD"
        case .implantOrShot: "Yes, an implant or injection"
        case .nonHormonal: "Yes, condoms or another non-hormonal method"
        case .preferNotToSay: "Prefer not to answer"
        }
    }

    var response: String? {
        switch self {
        case .pill, .iud, .implantOrShot:
            "Cycles can take a few months to settle after hormonal contraception, so early estimates may shift."
        case .stillUsing:
            "Hormonal contraception, including a hormonal coil, can change or stop bleeding, so cycle dates may be less useful. Symptoms still tell the story."
        default:
            nil
        }
    }

    var mayAffectRecentCycles: Bool {
        [.stillUsing, .pill, .iud, .implantOrShot].contains(self)
    }
}

/// A read-only view over the personalisation fields on `UserSettings`, so
/// callers ask questions ("should we suggest a doctor?") rather than
/// re-deriving thresholds in every view.
struct HealthProfile: Equatable {
    var birthYear: Int?
    var regularity: CycleRegularity?
    var conditions: Set<ReproductiveCondition>
    var birthControl: BirthControlRecency?
    var otherCondition: String? = nil
    var heightCm: Double? = nil
    var weightKg: Double? = nil

    /// Body mass index from the latest height and weight, nil until both exist
    /// and look like real adult measurements.
    var bmi: Double? {
        guard let heightCm, let weightKg, (120...230).contains(heightCm), (30...300).contains(weightKg) else { return nil }
        let metres = heightCm / 100
        return weightKg / (metres * metres)
    }

    var bmiCategory: BMICategory? { bmi.map(BMICategory.init(bmi:)) }

    func age(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        birthYear.map { calendar.component(.year, from: date) - $0 }
    }

    var hasPCOS: Bool { conditions.contains(.pcos) }

    /// NICE NG23: under 45, symptoms are usually checked with a doctor (and
    /// a blood test may be used) rather than assumed to be perimenopause.
    func shouldSuggestDoctor(on date: Date = .now) -> Bool {
        guard let age = age(on: date) else { return false }
        return age < 45
    }

    /// True when dates alone are a weaker guide to this person's cycle.
    var predictionsLessCertain: Bool {
        regularity == .irregular || hasPCOS || (birthControl?.mayAffectRecentCycles ?? false)
    }

    var isEmpty: Bool {
        birthYear == nil && regularity == nil && conditions.isEmpty && birthControl == nil && heightCm == nil && weightKg == nil
    }
}

/// WHO adult BMI bands, shown alongside logged weight.
enum BMICategory: String, Equatable {
    case underweight, healthy, overweight, obese

    init(bmi: Double) {
        switch bmi {
        case ..<18.5: self = .underweight
        case ..<25: self = .healthy
        case ..<30: self = .overweight
        default: self = .obese
        }
    }

    var title: String {
        switch self {
        case .underweight: "Below the healthy range"
        case .healthy: "Healthy range"
        case .overweight: "Above the healthy range"
        case .obese: "Well above the healthy range"
        }
    }
}
