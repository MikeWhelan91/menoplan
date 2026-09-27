import Foundation

@Observable
final class HomeViewModel {
    var selectedTestType: TestType = .ovulation
}

/// The caller supplies one clock reading for both the hour and daily variant.
/// Autoupdating local time also follows changes to the phone's time zone.
enum HomeGreeting {
    static func title(name: String, at date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: date)
        let variants: [String]
        switch hour {
        case ..<12: variants = ["Good morning", "Morning", "Hope you're doing well this morning"]
        case 12..<18: variants = ["Good afternoon", "Afternoon", "Hope your day is going well"]
        default: variants = ["Good evening", "Evening", "Hope you had a good day"]
        }
        // Keep the phrasing stable within a time-of-day period.
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let greeting = variants[dayOfYear % variants.count]
        return name.isEmpty ? greeting : "\(greeting), \(name)"
    }
}
