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

    func testCertaintyBoundsConstants() {
        XCTAssertEqual(LineAnalysisConstants.maxCertainty, 95)
        XCTAssertGreaterThanOrEqual(LineAnalysisConstants.minCertainty, 40)
    }

    func testUnclearResultUsesHumanFacingLabel() {
        XCTAssertEqual(ScanResultType.unclear.title, "Not Clear")
        XCTAssertEqual(ScanResultType.unclear.badgeTitle, "Not Clear")
    }

}
