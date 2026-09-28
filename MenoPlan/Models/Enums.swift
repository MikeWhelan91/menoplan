import Foundation
import SwiftUI

enum TestType: String, CaseIterable, Codable, Identifiable {
    case ovulation
    var id: String { rawValue }
    // The case keeps LineCheck's name; the test it reads is a home FSH test.
    var title: String { "FSH Test" }
    var shortTitle: String { "FSH" }
    var tint: Color { .linePurple }
}

enum TestFormat: String, CaseIterable, Codable, Identifiable {
    case unspecified, strip, cassette, midstream
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum OvulationResult: String, CaseIterable, Codable {
    case low, rising, high, peak, unclear, invalid
}

enum ScanResultType: String, CaseIterable, Codable, Identifiable {
    /// Matches the FSH API's bands (api/analyse-fsh.js): test line much
    /// lighter than control, lighter, or close to / as dark as control.
    case low, borderline, elevated, unclear, invalid, manualSaved
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "Low"
        case .borderline: "Borderline"
        case .elevated: "Elevated"
        case .unclear: "Not Clear"
        case .invalid: "Invalid Test"
        case .manualSaved: "Manual Check"
        }
    }
    var badgeTitle: String {
        switch self {
        case .manualSaved: "Manual"
        default: title
        }
    }
    var tint: Color {
        switch self {
        case .low, .borderline: .lineTeal
        case .elevated: .linePurple
        case .invalid, .unclear, .manualSaved: .lineNavy
        }
    }
}

/// Where a scan's currently-saved result actually came from. `aiOriginal` is
/// the default for every AI-read scan; `aiRecheck` and `userOverride` are set
/// once the user disputes that original call via the results-page "Look
/// Again" (AI re-check) or "This isn't right" (direct self-report) controls.
/// `localScan` is the free on-device heuristic scan - a real (if simpler)
/// analysis, not a self-report, so it's kept distinct from `userOverride`.
enum ScanResultSource: String, Codable {
    case aiOriginal, aiRecheck, userOverride, localScan
}

enum ReminderType: String, CaseIterable, Codable, Identifiable {
    case ovulationTest
    case periodExpected, periodCheckIn, periodLate, logTestResult
    case medication, bodyCheckIn, cycleSetup, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ovulationTest: "Test reminder"
        case .periodExpected: "Period expected"
        case .periodCheckIn: "Period check-in"
        case .periodLate: "Period late check-in"
        case .logTestResult: "Log a test result"
        case .medication: "Medication or supplement"
        case .bodyCheckIn: "Body-sign check-in"
        case .cycleSetup: "Finish cycle setup"
        case .custom: "Custom reminder"
        }
    }
}

enum ImageQualityStatus: String, CaseIterable, Codable {
    case good, tooDark, overexposed, blurry, hardToDetect, poor
    var title: String {
        switch self {
        case .good: "Good"
        case .tooDark: "This image may be too dark."
        case .overexposed: "This image may be overexposed."
        case .blurry: "This image may be blurry."
        case .hardToDetect: "The test window may be hard to detect."
        case .poor: "This image may be hard to analyse."
        }
    }
}

enum AnalysisMode: String, CaseIterable, Codable, Identifiable {
    case manualEnhance, aiQuickCheck
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aiQuickCheck: "Luna Check"
        case .manualEnhance: "Manual Check"
        }
    }
}

enum ResultHeaderAction {
    case saveImage
    case exportPDF
}

enum PurchaseState: String, Codable {
    case unavailable, loading, free, pro, failed
}

enum DarkModePreference: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Where someone is in the menopause transition, as they describe it. It
/// shapes what Home leads with - it is never a diagnosis.
enum MenopauseStage: String, CaseIterable, Codable, Identifiable {
    /// Still having periods, but they're changing.
    case perimenopause
    /// No period for 12 months or more.
    case postmenopause
    /// Bleeding can't be used as a guide (hysterectomy, hormonal coil,
    /// continuous HRT) or they're not sure.
    case unsure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .perimenopause: "I still have periods, but they're changing"
        case .postmenopause: "No period for 12 months or more"
        case .unsure: "I can't tell or I'm not sure"
        }
    }
    /// Fits a Settings tile.
    var shortTitle: String {
        switch self {
        case .perimenopause: "Still having periods"
        case .postmenopause: "No period for 12+ months"
        case .unsure: "Can't tell"
        }
    }
    var detail: String {
        switch self {
        case .perimenopause: "We'll track how your cycle is changing alongside your symptoms."
        case .postmenopause: "We'll focus on your symptoms and any treatment you use."
        case .unsure: "For example after a hysterectomy, with a hormonal coil or on continuous HRT. We'll focus on your symptoms."
        }
    }
    var symbol: String {
        switch self {
        case .perimenopause: "calendar"
        case .postmenopause: "leaf"
        case .unsure: "questionmark.circle"
        }
    }
    /// Whether bleeding is a useful guide for this person, so cycle timing
    /// is worth showing.
    var tracksCycle: Bool { self == .perimenopause }
}

/// How much the day's hot flushes and night sweats got in the way. Named
/// steps rather than a number: "2" means nothing to a clinician reading the
/// summary weeks later.
enum SymptomSeverity: String, CaseIterable, Codable, Identifiable {
    case mild, moderate, severe
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SleepQuality: String, CaseIterable, Codable, Identifiable {
    case good, broken, poor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .good: "Slept Well"
        case .broken: "Broken Sleep"
        case .poor: "Poor Sleep"
        }
    }
}

/// Common kinds of HRT, for picking a regimen and ticking off the day's doses.
/// Names only - MenoPlan never records or suggests doses.
enum HRTOptions {
    static let common = [
        "Oestrogen Gel", "Oestrogen Patch", "Oestrogen Spray", "Oestrogen Tablet",
        "Progesterone", "Combined Tablet", "Vaginal Oestrogen", "Testosterone"
    ]
}

enum TrackingFocus: String, CaseIterable, Codable, Identifiable {
    case ovulation
    var id: String { rawValue }
    var title: String { "FSH Tests" }
    var defaultTestType: TestType { .ovulation }
}

enum CycleRecordStatus: String, CaseIterable, Codable {
    case active, completed, predicted, archived
}

enum TrackingDataSource: String, CaseIterable, Codable {
    case userConfirmed, testSupported, estimated, migrated, healthKit
    /// Ovulation placed by a sustained BBT / wrist-temperature rise
    /// (ThermalShiftDetector). Evidence, but weaker than a saved Peak test.
    case temperatureSupported

    /// Observed evidence of when ovulation happened (a confirmed date, a
    /// Peak test or a temperature shift) rather than a calendar estimate.
    var isOvulationEvidence: Bool { [.userConfirmed, .testSupported, .temperatureSupported, .migrated].contains(self) }

    var title: String {
        switch self {
        case .temperatureSupported: "Temperature shift"
        case .userConfirmed: "Confirmed"
        case .testSupported: "Test supported"
        case .estimated: "Estimated"
        case .migrated: "Imported"
        case .healthKit: "Apple Health"
        }
    }
}

enum FlowIntensity: String, CaseIterable, Codable, Identifiable {
    case spotting, light, medium, heavy
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var title: String { self == .celsius ? "°C" : "°F" }
    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

/// How height, weight and water are shown. Everything is stored metric.
enum BodyMeasurementUnit: String, CaseIterable, Codable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "kg · cm" : "lb · ft" }
    var weightSymbol: String { self == .metric ? "kg" : "lb" }
    var waterSymbol: String { self == .metric ? "ml" : "fl oz" }
    var distanceSymbol: String { self == .metric ? "km" : "mi" }

    static var localeDefault: BodyMeasurementUnit {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    static let poundsPerKilogram = 2.2046226218
    static let millilitresPerFluidOunce = 29.5735295625
    static let centimetresPerInch = 2.54
    static let kilometresPerMile = 1.609344

    func displayWeight(_ kg: Double) -> Double { self == .metric ? kg : kg * Self.poundsPerKilogram }
    func kilograms(fromDisplay value: Double) -> Double { self == .metric ? value : value / Self.poundsPerKilogram }
    func displayWater(_ ml: Double) -> Double { self == .metric ? ml : ml / Self.millilitresPerFluidOunce }
    func millilitres(fromDisplay value: Double) -> Double { self == .metric ? value : value * Self.millilitresPerFluidOunce }
    func displayDistance(_ km: Double) -> Double { self == .metric ? km : km / Self.kilometresPerMile }

    func formattedWeight(_ kg: Double) -> String { String(format: "%.1f %@", displayWeight(kg), weightSymbol) }
    func formattedWater(_ ml: Double) -> String {
        self == .metric ? "\(Int(ml.rounded())) ml" : String(format: "%.0f fl oz", displayWater(ml))
    }
    func formattedHeight(_ cm: Double) -> String {
        guard self == .imperial else { return "\(Int(cm.rounded())) cm" }
        let totalInches = Int((cm / Self.centimetresPerInch).rounded())
        return "\(totalInches / 12)′ \(totalInches % 12)″"
    }
}

/// Weight's own unit. Stone is common in the UK and Ireland, so it's a
/// first-class option rather than folded into pounds.
enum WeightUnit: String, CaseIterable, Codable, Identifiable {
    case kilograms, pounds, stone
    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lb"
        case .stone: "st"
        }
    }

    static var localeDefault: WeightUnit {
        switch Locale.current.measurementSystem {
        case .us: .pounds
        case .uk: .stone
        default: Locale.current.region?.identifier == "IE" ? .stone : .kilograms
        }
    }

    /// Water follows the weight choice: ml for kg and stone, fl oz for pounds.
    var system: BodyMeasurementUnit { self == .pounds ? .imperial : .metric }
    /// Distance: stone users (UK, Ireland) think in miles, like pounds users.
    var distanceSystem: BodyMeasurementUnit { self == .kilograms ? .metric : .imperial }

    func formatted(_ kg: Double) -> String {
        switch self {
        case .kilograms: return String(format: "%.1f kg", kg)
        case .pounds: return String(format: "%.1f lb", kg * BodyMeasurementUnit.poundsPerKilogram)
        case .stone:
            let (stone, pounds) = Self.stoneAndPounds(kg)
            return String(format: "%d st %.0f lb", stone, pounds)
        }
    }

    /// Whole stone plus remaining pounds (one decimal).
    static func stoneAndPounds(_ kg: Double) -> (Int, Double) {
        let totalPounds = (kg * BodyMeasurementUnit.poundsPerKilogram * 10).rounded() / 10
        let stone = Int(totalPounds / 14)
        return (stone, ((totalPounds - Double(stone * 14)) * 10).rounded() / 10)
    }

    static func kilograms(stone: Double, pounds: Double) -> Double {
        (stone * 14 + pounds) / BodyMeasurementUnit.poundsPerKilogram
    }
}

