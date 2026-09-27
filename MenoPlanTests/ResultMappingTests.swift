import XCTest
@testable import MenoPlan


final class ResultMappingTests: XCTestCase {
    func testOvulationThresholdMapping() {
        let engine = LineAnalysisEngine()
        XCTAssertEqual(engine.ovulationResult(ratio: 0.12), .low)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.52), .rising)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.82), .high)
        XCTAssertEqual(engine.ovulationResult(ratio: 1.02), .peak)
        XCTAssertEqual(engine.ovulationResult(ratio: 0, testDetected: false), .low)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.96, testDetected: true), .peak)
    }

    func testPregnancyThresholdMapping() {
        let engine = LineAnalysisEngine()
        XCTAssertEqual(engine.pregnancyResult(test: 0.03, ratio: 0.08, testDetected: false), .appearsNegative)
        XCTAssertEqual(engine.pregnancyResult(test: 0.12, ratio: 0.24, testDetected: true), .faintLineDetected)
        XCTAssertEqual(engine.pregnancyResult(test: 0.28, ratio: 0.50, testDetected: true), .appearsPositive)
    }

    func testCertaintyBoundsConstants() {
        XCTAssertEqual(LineAnalysisConstants.maxCertainty, 95)
        XCTAssertGreaterThanOrEqual(LineAnalysisConstants.minCertainty, 40)
    }

    func testUnclearResultUsesHumanFacingLabel() {
        XCTAssertEqual(ScanResultType.unclear.title, "Not Clear")
        XCTAssertEqual(ScanResultType.unclear.badgeTitle, "Not Clear")
    }

    func testPregnancyComparisonPrioritisesResultCategoryOverContradictoryStrength() {
        let earlier = pregnancyScan(format: .unspecified, result: .faintLineDetected, strength: 0.30)
        let later = pregnancyScan(format: .unspecified, result: .appearsPositive, strength: 0.08)

        let assessment = CompareViewModel().pregnancyAssessment(from: earlier, to: later)

        XCTAssertEqual(assessment.direction, .stronger)
        XCTAssertEqual(assessment.title, "Later result is more pronounced")
        XCTAssertTrue(assessment.detail.contains("Faint"))
        XCTAssertTrue(assessment.detail.contains("Positive"))
    }

    func testPregnancyComparisonIgnoresLegacyStoredFormat() {
        let earlier = pregnancyScan(format: .cassette, result: .faintLineDetected, strength: 0.30)
        let later = pregnancyScan(format: .midstream, result: .faintLineDetected, strength: 0.08)

        let assessment = CompareViewModel().pregnancyAssessment(from: earlier, to: later)

        XCTAssertEqual(assessment.direction, .lighter)
        XCTAssertEqual(assessment.title, "Line appears lighter")
    }

    private func pregnancyScan(format: TestFormat, result: ScanResultType, strength: Double) -> Scan {
        Scan(
            testType: .pregnancy,
            testFormat: format,
            resultType: result,
            lineStrength: strength,
            analysisMode: .manualEnhance,
            imageFilename: UUID().uuidString
        )
    }
}
