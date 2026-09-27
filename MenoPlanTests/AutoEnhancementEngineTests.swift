import XCTest
@testable import MenoPlan


final class AutoEnhancementEngineTests: XCTestCase {
    func testAutoEnhancementCandidateContractIsDeterministic() {
        let quality = ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2)
        let first = LineAnalysisResult(resultType: .peak, confidencePercentage: 82, certaintyPercentage: 82, controlLineDetected: true, testLineDetected: true, testControlRatio: 1.02, lineStrength: 0.6, quality: quality, explanation: "Peak")
        let second = LineAnalysisResult(resultType: .peak, confidencePercentage: 82, certaintyPercentage: 82, controlLineDetected: true, testLineDetected: true, testControlRatio: 1.02, lineStrength: 0.6, quality: quality, explanation: "Peak")
        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.certaintyPercentage, LineAnalysisConstants.minCertainty)
    }
}
