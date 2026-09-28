import Foundation

/// Answers from the personalisation quiz. Each one changes something the app
/// actually does - how confident cycle estimates are presented, or whether a
/// gentle "talk to a doctor" note appears - rather than only steering content.

enum CycleRegularity: String, CaseIterable, Codable, Identifiable {
    case regular, irregular, unsure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "About the same as usual"
        case .irregular: "Changing: shorter, longer or skipped"
        case .unsure: "I’m not sure"
        }
    }

    var response: String? {
        switch self {
        case .regular: nil
        case .irregular: "Changing cycles are one of the most common signs of perimenopause. MenoPlan will show how much yours vary."
        case .unsure: "No problem. As you log a few periods, MenoPlan shows how your cycle is changing."
        }
    }
}

/// Health history a clinician would want to know at a menopause
/// appointment: things that change what bleeding means, which treatments
/// suit, or that cause similar symptoms. The type keeps LineCheck's name.
enum ReproductiveCondition: String, CaseIterable, Codable, Identifiable {
    case hysterectomy, ovariesRemoved, thyroid, breastCancer, bloodClots, migraineWithAura, endometriosis, fibroids, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hysterectomy: "Hysterectomy"
        case .ovariesRemoved: "Ovaries removed"
        case .thyroid: "A thyroid condition"
        case .breastCancer: "Breast cancer, now or in the past"
        case .bloodClots: "Blood clots or stroke"
        case .migraineWithAura: "Migraine with aura"
        case .endometriosis: "Endometriosis"
        case .fibroids: "Fibroids"
        case .other: "Something else"
        }
    }

    /// Short chip label for the quiz.
    var shortTitle: String {
        switch self {
        case .breastCancer: "Breast cancer"
        case .bloodClots: "Clots or stroke"
        case .thyroid: "Thyroid condition"
        default: title
        }
    }

    var response: String? {
        switch self {
        case .hysterectomy:
            "Without a womb, periods can’t show how things are changing, so MenoPlan focuses on your symptoms."
        case .ovariesRemoved:
            "Removing the ovaries usually brings menopause on straight away, so symptoms can be sudden. It’s worth mentioning at any appointment."
        case .breastCancer, .bloodClots, .migraineWithAura:
            "This can affect which treatments suit you, so it’s included in your appointment summary."
        case .thyroid:
            "Thyroid problems can cause similar symptoms, like tiredness and mood changes, so doctors often check them."
        default:
            nil
        }
    }
}

/// Hormonal contraception, which can change or stop bleeding and can make
/// home FSH tests unreliable. The type keeps LineCheck's name.
enum BirthControlRecency: String, CaseIterable, Codable, Identifiable {
    case none, hormonalCoil, pillPatchOrRing, implantOrInjection, stoppedRecently, preferNotToSay
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No"
        case .hormonalCoil: "A hormonal coil (like Mirena)"
        case .pillPatchOrRing: "The pill, patch or ring"
        case .implantOrInjection: "An implant or injection"
        case .stoppedRecently: "I stopped in the last 6 months"
        case .preferNotToSay: "Prefer not to say"
        }
    }

    var response: String? {
        switch self {
        case .hormonalCoil:
            "A hormonal coil can lighten or stop periods, so MenoPlan leans on your symptoms rather than cycle dates."
        case .pillPatchOrRing:
            "Combined methods can hide bleeding changes and some symptoms, and home FSH tests may not be reliable while you use them."
        case .implantOrInjection:
            "These can change or stop bleeding, so cycle dates may be less useful. Your symptoms still tell the story."
        case .stoppedRecently:
            "Cycles can take a few months to settle after stopping, so early patterns may shift."
        default:
            nil
        }
    }

    /// Using hormonal contraception now.
    var isCurrentlyUsing: Bool {
        [.hormonalCoil, .pillPatchOrRing, .implantOrInjection].contains(self)
    }

    var mayAffectRecentCycles: Bool {
        isCurrentlyUsing || self == .stoppedRecently
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

    /// No womb or ovaries, so bleeding can't guide anything.
    var hasSurgicalHistory: Bool { conditions.contains(.hysterectomy) || conditions.contains(.ovariesRemoved) }

    /// NICE NG23: under 45, symptoms are usually checked with a doctor (and
    /// a blood test may be used) rather than assumed to be perimenopause.
    func shouldSuggestDoctor(on date: Date = .now) -> Bool {
        guard let age = age(on: date) else { return false }
        return age < 45
    }

    /// True when dates alone are a weaker guide to this person's cycle.
    var predictionsLessCertain: Bool {
        regularity == .irregular || (birthControl?.mayAffectRecentCycles ?? false)
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
