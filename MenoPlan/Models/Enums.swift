import Foundation
import SwiftUI

enum TestType: String, CaseIterable, Codable, Identifiable {
    case pregnancy, ovulation
    var id: String { rawValue }
    var title: String { self == .pregnancy ? "Pregnancy Test" : "Ovulation Test" }
    var shortTitle: String { self == .pregnancy ? "Pregnancy" : "Ovulation" }
    var tint: Color { self == .pregnancy ? .linePink : .linePurple }
}

enum TestFormat: String, CaseIterable, Codable, Identifiable {
    case unspecified, strip, cassette, midstream
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PregnancyResult: String, CaseIterable, Codable {
    case appearsPositive, appearsNegative, faintLineDetected, unclear, invalid
}

enum OvulationResult: String, CaseIterable, Codable {
    case low, rising, high, peak, unclear, invalid
}

enum ScanResultType: String, CaseIterable, Codable, Identifiable {
    case appearsPositive, appearsNegative, faintLineDetected, low, rising, high, peak, unclear, invalid, manualSaved
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearsPositive: "Appears Positive"
        case .appearsNegative: "Appears Negative"
        case .faintLineDetected: "Faint Line Detected"
        case .low: "Low"
        case .rising: "Rising"
        case .high: "High"
        case .peak: "Peak"
        case .unclear: "Not Clear"
        case .invalid: "Invalid Test"
        case .manualSaved: "Manual Check"
        }
    }
    var badgeTitle: String {
        switch self {
        case .appearsPositive: "Positive"
        case .appearsNegative: "Negative"
        case .faintLineDetected: "Faint"
        case .manualSaved: "Manual"
        default: title
        }
    }
    var tint: Color {
        switch self {
        case .appearsPositive, .faintLineDetected: .linePink
        case .low, .rising: .lineTeal
        case .high, .peak: .linePurple
        case .invalid, .unclear, .manualSaved, .appearsNegative: .lineNavy
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
    case pregnancyRetest, ovulationTest, fertileWindow, fertilePeak
    case periodExpected, periodCheckIn, periodLate, logTestResult, ovulationFollowUp
    case medication, bodyCheckIn, cycleSetup, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pregnancyRetest: "Pregnancy retest"
        case .ovulationTest: "Ovulation test"
        case .fertileWindow: "Fertile window"
        case .fertilePeak: "Fertile peak check-in"
        case .periodExpected: "Period expected"
        case .periodCheckIn: "Period check-in"
        case .periodLate: "Period late check-in"
        case .logTestResult: "Log a test result"
        case .ovulationFollowUp: "Ovulation test follow-up"
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

enum OvulationTrackingGoal: String, CaseIterable, Codable, Identifiable {
    case tryingToConceive, trackingCycle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tryingToConceive: "Trying for a pregnancy"
        case .trackingCycle: "Understanding my cycle"
        }
    }
}

enum PregnancyTrackingGoal: String, CaseIterable, Codable, Identifiable {
    case tryingToConceive, trackingProgression
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tryingToConceive: "Trying for a pregnancy"
        case .trackingProgression: "Comparing pregnancy tests"
        }
    }
}

enum TrackingFocus: String, CaseIterable, Codable, Identifiable {
    case both, pregnancy, ovulation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: "Both"
        case .pregnancy: "Pregnancy Tests"
        case .ovulation: "Ovulation Tests"
        }
    }
    var defaultTestType: TestType {
        switch self {
        case .both, .pregnancy: .pregnancy
        case .ovulation: .ovulation
        }
    }
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

enum PregnancyJourneyState: String, CaseIterable, Codable, Identifiable {
    case trying, possiblePositive, confirmedPregnant, periodArrived, ended
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trying: "Trying to conceive"
        case .possiblePositive: "Possible positive"
        case .confirmedPregnant: "Pregnancy confirmed"
        case .periodArrived: "Period arrived"
        case .ended: "Pregnancy ended"
        }
    }
}
