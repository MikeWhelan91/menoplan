import Foundation

enum PregnancyComparisonDirection: Equatable {
    case stronger
    case lighter
    case similar
    case notComparable
}

struct PregnancyComparisonAssessment {
    let direction: PregnancyComparisonDirection
    let title: String
    let detail: String
    let metricNote: String
}

@Observable
final class CompareViewModel {
    func pregnancyChange(from first: Scan, to second: Scan) -> String {
        pregnancyAssessment(from: first, to: second).title
    }

    func pregnancyAssessment(from first: Scan, to second: Scan) -> PregnancyComparisonAssessment {
        if let firstRank = pregnancyResultRank(first.resultType),
           let secondRank = pregnancyResultRank(second.resultType),
           firstRank != secondRank {
            let isStronger = secondRank > firstRank
            return PregnancyComparisonAssessment(
                direction: isStronger ? .stronger : .lighter,
                title: isStronger ? "Later result is more pronounced" : "Later result is less pronounced",
                detail: "The saved result changed from \(first.resultType.badgeTitle) to \(second.resultType.badgeTitle).",
                metricNote: "The result category takes priority when a photo measurement points in the opposite direction."
            )
        }

        let delta = second.lineStrength - first.lineStrength
        if delta > 0.06 {
            return PregnancyComparisonAssessment(
                direction: .stronger,
                title: "Line appears stronger",
                detail: "The later pregnancy test has a higher saved line-strength value.",
                metricNote: "For a useful comparison, similar lighting, timing, and test type matter."
            )
        }
        if delta < -0.06 {
            return PregnancyComparisonAssessment(
                direction: .lighter,
                title: "Line appears lighter",
                detail: "The later pregnancy test has a lower saved line-strength value.",
                metricNote: "Differences can come from lighting, urine concentration, test brand, or photo quality."
            )
        }
        return PregnancyComparisonAssessment(
            direction: .similar,
            title: "Line appears similar",
            detail: "The saved line-strength values are close between these two pregnancy tests.",
            metricNote: "Retesting in a few days under similar conditions can make the line easier to compare. Follow the timing in your test instructions."
        )
    }

    private func pregnancyResultRank(_ result: ScanResultType) -> Int? {
        switch result {
        case .appearsNegative: 0
        case .faintLineDetected: 1
        case .appearsPositive: 2
        case .invalid, .unclear, .manualSaved, .low, .rising, .high, .peak: nil
        }
    }
}
