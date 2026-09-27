import Foundation

/// Answers from the personalisation quiz. Each one changes something the app
/// actually does - how confident predictions are presented, how ovulation
/// results are worded, or whether a gentle "talk to a doctor" note appears -
/// rather than only steering content.

enum TTCDuration: String, CaseIterable, Codable, Identifiable {
    case justStarted, underThreeMonths, threeToSixMonths, sixToTwelveMonths, overAYear
    var id: String { rawValue }

    var title: String {
        switch self {
        case .justStarted: "I’ve just started trying"
        case .underThreeMonths: "0 to 3 months"
        case .threeToSixMonths: "3 to 6 months"
        case .sixToTwelveMonths: "6 months to a year"
        case .overAYear: "Over a year"
        }
    }

    var response: String? {
        switch self {
        case .justStarted: "Welcome. Most people don’t conceive in the first cycle or two, so it’s worth getting to know your pattern first."
        case .underThreeMonths: nil
        case .threeToSixMonths: "Timing makes the biggest difference. We’ll help you pinpoint your most fertile days each cycle."
        case .sixToTwelveMonths: "This can be a tiring stretch. If you’re 35 or over, it’s a good time to check in with a doctor."
        case .overAYear: "We know this can be emotionally tiring, and you’re not alone. After a year of trying, doctors recommend a fertility check-up, and MenoPlan can export your history for that appointment."
        }
    }

    /// Ordinal used for the doctor-suggestion threshold.
    var months: Int {
        switch self {
        case .justStarted: 0
        case .underThreeMonths: 1
        case .threeToSixMonths: 3
        case .sixToTwelveMonths: 6
        case .overAYear: 12
        }
    }
}

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
        case .irregular: "An irregular cycle makes ovulation harder to predict from dates alone. We’ll suggest starting ovulation tests earlier and lean on your test results more than the calendar."
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
        case .pcos: "With PCOS, LH can stay raised for several days, so ovulation tests may read High more often. MenoPlan will flag this on your results."
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
            "Cycles can take a few months to settle after hormonal birth control, so early predictions may shift. Your test results will help."
        case .stillUsing:
            "Hormonal birth control usually prevents ovulation, so cycle predictions may not apply until you stop."
        default:
            nil
        }
    }

    var mayAffectRecentCycles: Bool {
        [.stillUsing, .pill, .iud, .implantOrShot].contains(self)
    }
}

enum PreconceptionSupplement: String, CaseIterable, Codable, Identifiable {
    case folicAcid, prenatal, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .folicAcid: "Yes, folic acid"
        case .prenatal: "Yes, a prenatal multivitamin"
        case .none: "Not yet"
        }
    }

    var response: String? {
        switch self {
        case .folicAcid, .prenatal:
            "Great. Health guidance recommends at least 400mcg of folic acid daily before conception and through the first 12 weeks."
        case .none:
            "Health guidance recommends 400mcg of folic acid daily before conception and through the first 12 weeks. We can remind you each morning."
        }
    }
}

/// A read-only view over the personalisation fields on `UserSettings`, so
/// callers ask questions ("should we suggest a doctor?") rather than
/// re-deriving thresholds in every view.
struct HealthProfile: Equatable {
    var ttcDuration: TTCDuration?
    var birthYear: Int?
    var regularity: CycleRegularity?
    var conditions: Set<ReproductiveCondition>
    var birthControl: BirthControlRecency?
    var supplement: PreconceptionSupplement?
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

    /// Mirrors common guidance: evaluation after 12 months of trying, after
    /// 6 months at 35+, and sooner again at 40+.
    func shouldSuggestDoctor(on date: Date = .now) -> Bool {
        guard let ttcDuration else { return false }
        let age = age(on: date) ?? 0
        if ttcDuration.months >= 12 { return true }
        if age >= 35 && ttcDuration.months >= 6 { return true }
        if age >= 40 && ttcDuration.months >= 3 { return true }
        return false
    }

    /// True when dates alone are a weaker guide to ovulation for this person.
    var predictionsLessCertain: Bool {
        regularity == .irregular || hasPCOS || (birthControl?.mayAffectRecentCycles ?? false) || (bmiCategory?.mayAffectOvulation ?? false)
    }

    var isEmpty: Bool {
        ttcDuration == nil && birthYear == nil && regularity == nil && conditions.isEmpty && birthControl == nil && supplement == nil && heightCm == nil && weightKg == nil
    }
}

/// WHO adult BMI bands. Only used for a gentle, optional note - both a low and
/// a high BMI are linked with less regular ovulation, which is the one thing
/// this app can usefully say about it.
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

    /// True where BMI is linked with ovulation becoming less predictable.
    var mayAffectOvulation: Bool { self == .underweight || self == .obese }

    var fertilityNote: String? {
        switch self {
        case .underweight:
            "A BMI under 18.5 can make ovulation less regular. Your test results will tell you more than dates alone."
        case .obese:
            "A BMI of 30 or more can make ovulation less regular. Your test results will tell you more than dates alone."
        default:
            nil
        }
    }
}

