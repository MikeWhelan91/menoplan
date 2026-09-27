import XCTest
import UIKit
@testable import MenoPlan

final class TestTemplateGeometryTests: XCTestCase {
    func testLineRegionStaysInsideAlignedTestAndExcludesOuterEnds() {
        let region = TestTemplateGeometry.lineRegion
        XCTAssertGreaterThan(region.minX, 0.20)
        XCTAssertLessThan(region.maxX, 0.80)
        XCTAssertGreaterThanOrEqual(region.minY, 0)
        XCTAssertLessThanOrEqual(region.maxY, 1)
    }

    func testLineAnalysisCropUsesSharedNormalizedRegion() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 250))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 250))
        }
        let cropped = try XCTUnwrap(TestTemplateGeometry.lineAnalysisImage(from: image))
        XCTAssertEqual(cropped.size.width, 400, accuracy: 1)
        XCTAssertEqual(cropped.size.height, 200, accuracy: 1)
    }

    func testOvulationKeepsTheAlignedOuterCropForNow() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 250)).image { _ in }
        let analysis = TestTemplateGeometry.analysisImage(from: image, testType: .ovulation)
        XCTAssertEqual(analysis.size.width, 1_000, accuracy: 1)
        XCTAssertEqual(analysis.size.height, 250, accuracy: 1)
    }
}
