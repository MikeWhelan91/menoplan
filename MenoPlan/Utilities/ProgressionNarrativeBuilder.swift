import Foundation

/// Generates the auto-comparison sentence shown under the test trend
/// chart, turning a whole saved
/// sequence into a "your line is trending X" statement instead of leaving
/// the user to read a raw chart themselves. Reuses the exact wording
/// already used elsewhere in the app (OnDeviceOvulationReconciler's trend
/// summary) so the language a user
/// sees here always matches what they'd see from a single AI check or a
/// manual compare.
enum ProgressionNarrativeBuilder {
    /// `scans` must already be filtered to one test type, exclude scans the
    /// user marked excludedFromCalculations, and be sorted oldest-first.
    static func ovulationNarrative(scans: [Scan]) -> String? {
        guard let latest = scans.last, scans.count >= 2 else { return nil }
        let priorRatiosMostRecentFirst = scans.dropLast().reversed().map(\.testControlRatio)
        return OnDeviceOvulationReconciler.trendSummary(currentRatio: latest.testControlRatio, recentRatios: Array(priorRatiosMostRecentFirst))
    }

    /// A different brand, an unusually long gap, or a poor-quality photo
    /// makes "stronger/lighter" language between the two latest tests less
    /// trustworthy - surfaced so the narrative doesn't overclaim.
    static func weakComparisonNote(scans: [Scan]) -> String? {
        guard scans.count >= 2 else { return nil }
        let previous = scans[scans.count - 2]
        let latest = scans[scans.count - 1]
        var reasons: [String] = []

        if let latestBrand = latest.brandName?.trimmingCharacters(in: .whitespacesAndNewlines), !latestBrand.isEmpty,
           let previousBrand = previous.brandName?.trimmingCharacters(in: .whitespacesAndNewlines), !previousBrand.isEmpty,
           latestBrand.caseInsensitiveCompare(previousBrand) != .orderedSame {
            reasons.append("different test brands")
        }
        let days = Calendar.current.dateComponents([.day], from: previous.createdAt, to: latest.createdAt).day ?? 0
        if days >= 10 {
            reasons.append("a \(days)-day gap between tests")
        }
        if latest.imageQualityStatus != .good || previous.imageQualityStatus != .good {
            reasons.append("an image-quality warning on one of the photos")
        }

        guard !reasons.isEmpty else { return nil }
        return "This comparison may be less reliable because of \(reasons.joined(separator: " and "))."
    }
}
