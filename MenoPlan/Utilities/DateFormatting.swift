import Foundation

enum DateFormatting {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    /// "24 Aug" - no year, for tight spaces like chart axis labels where `shortDate`
    /// ("24 Aug 2026") is too wide to fit more than a couple without overlapping.
    static let axisDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()
}
