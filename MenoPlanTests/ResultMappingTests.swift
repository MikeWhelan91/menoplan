import XCTest
@testable import MenoPlan


final class ResultMappingTests: XCTestCase {
    func testOvulationThresholdMapping() {
        let engine = LineAnalysisEngine()
        XCTAssertEqual(engine.ovulationResult(ratio: 0.12), .low)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.52), .borderline)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.82), .elevated)
        XCTAssertEqual(engine.ovulationResult(ratio: 1.02), .elevated)
        XCTAssertEqual(engine.ovulationResult(ratio: 0, testDetected: false), .low)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.96, testDetected: true), .elevated)
        // Same boundaries as api/analyse-fsh.js (<0.40 low, <0.75 borderline).
        XCTAssertEqual(engine.ovulationResult(ratio: 0.40), .borderline)
        XCTAssertEqual(engine.ovulationResult(ratio: 0.75), .elevated)
    }

    /// The exact shape api/analyse-fsh.js returns must decode, including its
    /// FSH bands - LineCheck's LH tiers used to make every read fail.
    func testFSHServerResponseDecodes() throws {
        for band in ["low", "borderline", "elevated", "unclear", "invalid"] {
            let json = """
            {"resultType":"\(band)","confidencePercentage":80,"certaintyPercentage":80,"controlLineDetected":true,
             "testLineDetected":true,"testControlRatio":0.62,"lineStrength":0.5,"observedLinePattern":"x",
             "nextBestAction":"y","imageQualityStatus":"good","explanation":"A visible but lighter test line.",
             "trendSummary":"One reading cannot establish a trend.","guidance":"One data point.","qualityNotes":[],
             "model":"m","promptVersion":"menoplan-fsh-v1"}
            """
            let response = try JSONDecoder().decode(AIAnalysisResponse.self, from: Data(json.utf8))
            XCTAssertEqual(response.resultType.rawValue, band)
        }
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
