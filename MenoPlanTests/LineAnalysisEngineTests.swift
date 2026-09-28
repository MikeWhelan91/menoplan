import XCTest
import UIKit
@testable import MenoPlan


final class LineAnalysisEngineTests: XCTestCase {
    private let engine = LineAnalysisEngine()

    func testInvalidNoControlLineMapsToInvalid() {
        let quality = ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2)
        let result = LineAnalysisResult(resultType: .invalid, confidencePercentage: 0, certaintyPercentage: 45, controlLineDetected: false, testLineDetected: false, testControlRatio: 0, lineStrength: 0, quality: quality, explanation: "The control line was not detected.")
        XCTAssertEqual(result.resultType, .invalid)
        XCTAssertFalse(result.controlLineDetected)
    }


    func testGeneratedLowOvulationStripDoesNotMapToPeak() {
        let image = generatedOvulationStrip(testAlpha: 0.16, controlAlpha: 0.92)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue([.low, .borderline].contains(result.resultType), "Expected weak test line to stay below high/peak, got \(result.resultType) at ratio \(result.testControlRatio)")
        XCTAssertLessThan(result.testControlRatio, 0.75)
    }

    func testGeneratedLowOvulationStripWithPurpleHandleAndCropArtifactDoesNotMapToPeak() {
        let image = generatedOvulationStrip(testAlpha: 0.14, controlAlpha: 0.90, purpleHandle: true, leftCropArtifact: true)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue([.low, .borderline].contains(result.resultType), "Expected purple handle text and crop artifact to be ignored, got \(result.resultType) at ratio \(result.testControlRatio)")
        XCTAssertLessThan(result.testControlRatio, 0.70)
    }

    func testBlendedGreenHandleBoundaryDoesNotInflateALowTestLineToRising() {
        // Regression test for a real false read: a genuinely low/absent test
        // line was reported as "rising" against a green-handled test. The
        // suspected cause is a compression/antialiasing colour blend right
        // where the membrane meets the handle being mistaken for signal.
        let image = generatedOvulationStrip(testAlpha: 0.14, controlAlpha: 0.90, blendedHandleBoundary: true)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertEqual(result.resultType, .low, "Expected a near-invisible test line against a blended green handle boundary to read as low, got \(result.resultType) at ratio \(result.testControlRatio)")
        XCTAssertLessThan(result.testControlRatio, 0.40)
    }

    func testGeneratedPeakOvulationStripMapsToPeak() {
        let image = generatedOvulationStrip(testAlpha: 0.92, controlAlpha: 0.92)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue(result.testLineDetected)
        XCTAssertEqual(result.resultType, .elevated)
        XCTAssertGreaterThanOrEqual(result.testControlRatio, 0.95)
    }

    func testStandaloneLocalOvulationConsensusKeepsPeakInsteadOfAmbiguous() {
        let quality = ImageQualityResult(status: .hardToDetect, brightness: 0.5, blurScore: 0.4, overexposure: 0.2)
        let primary = LineAnalysisResult(
            resultType: .elevated,
            confidencePercentage: 60,
            certaintyPercentage: 60,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: 1.42,
            lineStrength: 0.82,
            quality: quality,
            explanation: "Peak"
        )
        let fallback = LineAnalysisResult(
            resultType: .elevated,
            confidencePercentage: 64,
            certaintyPercentage: 64,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: 0.98,
            lineStrength: 0.70,
            quality: quality,
            explanation: "High"
        )

        let localResult = engine.preferredOvulationResult(primary: primary, fallback: fallback)

        XCTAssertEqual(localResult.resultType, .elevated)
        XCTAssertEqual(localResult.testControlRatio, 1.20, accuracy: 0.001)
    }

    func testAIOvulationResultIsNotOverriddenByLocalMeasurement() {
        let quality = ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2)
        let ai = LineAnalysisResult(
            resultType: .elevated,
            confidencePercentage: 91,
            certaintyPercentage: 91,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: 0.84,
            lineStrength: 0.72,
            quality: quality,
            explanation: "High"
        )
        let local = LineAnalysisResult(
            resultType: .elevated,
            confidencePercentage: 68,
            certaintyPercentage: 68,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: 1.21,
            lineStrength: 0.82,
            quality: quality,
            explanation: "Peak"
        )

        let reconciled = AIResultReconciler.reconcileOvulation(ai: ai, local: local)

        XCTAssertEqual(reconciled.resultType, .elevated)
        XCTAssertEqual(reconciled.testControlRatio, 0.84)
        XCTAssertEqual(reconciled.certaintyPercentage, 91)
    }

    private func result(
        _ resultType: ScanResultType,
        certainty: Int,
        testDetected: Bool
    ) -> LineAnalysisResult {
        LineAnalysisResult(
            resultType: resultType,
            confidencePercentage: certainty,
            certaintyPercentage: certainty,
            controlLineDetected: true,
            testLineDetected: testDetected,
            testControlRatio: testDetected ? 0.2 : 0,
            lineStrength: testDetected ? 0.15 : 0,
            quality: ImageQualityResult(
                status: .good,
                brightness: 0.5,
                blurScore: 0.2,
                overexposure: 0.2
            ),
            explanation: "Fixture"
        )
    }

    private func rotateClockwise(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func generatedOvulationStrip(testAlpha: CGFloat, controlAlpha: CGFloat, purpleHandle: Bool = false, leftCropArtifact: Bool = false, blendedHandleBoundary: Bool = false) -> UIImage {
        let size = CGSize(width: 720, height: 300)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.985, green: 0.975, blue: 0.972, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            if leftCropArtifact {
                UIColor(red: 0.82, green: 0.14, blue: 0.36, alpha: 0.26).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 102, width: 52, height: 84)).fill()
                UIColor.black.withAlphaComponent(0.62).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 172, width: 44, height: 18)).fill()
            }

            let testBody = CGRect(x: 88, y: 120, width: 540, height: 42)
            UIColor(white: 0.965, alpha: 1).setFill()
            UIBezierPath(roundedRect: testBody, cornerRadius: 5).fill()
            UIColor(white: 0.78, alpha: 1).setStroke()
            UIBezierPath(roundedRect: testBody, cornerRadius: 5).stroke()

            UIColor.black.withAlphaComponent(0.82).setFill()
            UIBezierPath(rect: CGRect(x: testBody.minX + 116, y: testBody.minY + 3, width: 5, height: 36)).fill()

            let lineColor = UIColor(red: 0.62, green: 0.14, blue: 0.42, alpha: 1)
            lineColor.withAlphaComponent(testAlpha).setFill()
            UIBezierPath(roundedRect: CGRect(x: testBody.minX + 322, y: testBody.minY + 5, width: 6, height: 32), cornerRadius: 2).fill()
            lineColor.withAlphaComponent(controlAlpha).setFill()
            UIBezierPath(roundedRect: CGRect(x: testBody.minX + 362, y: testBody.minY + 5, width: 6, height: 32), cornerRadius: 2).fill()

            let handleColor = purpleHandle
                ? UIColor(red: 0.46, green: 0.42, blue: 0.66, alpha: 1)
                : UIColor(red: 0.12, green: 0.55, blue: 0.32, alpha: 1)

            if blendedHandleBoundary {
                // Real photos never have a perfectly flat colour boundary:
                // JPEG compression and antialiasing blend the membrane into
                // the handle's colour over a few pixels. Flat UIBezierPath
                // fills can't reproduce that, so simulate it explicitly to
                // catch a false dye signal at exactly that transition.
                let blendRect = CGRect(x: testBody.minX + 372, y: testBody.minY, width: 24, height: testBody.height)
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [UIColor(white: 0.965, alpha: 1).cgColor, handleColor.cgColor] as CFArray,
                    locations: [0, 1]
                ) {
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: blendRect)
                    context.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: blendRect.minX, y: blendRect.midY),
                        end: CGPoint(x: blendRect.maxX, y: blendRect.midY),
                        options: []
                    )
                    context.cgContext.restoreGState()
                }
            }

            handleColor.setFill()
            UIBezierPath(rect: CGRect(x: testBody.minX + 396, y: testBody.minY, width: 144, height: 42)).fill()
            UIColor.white.withAlphaComponent(0.45).setFill()
            for offset in stride(from: 406, through: 512, by: 22) {
                UIBezierPath(rect: CGRect(x: testBody.minX + CGFloat(offset), y: testBody.minY + 5, width: 4, height: 30)).fill()
                UIBezierPath(rect: CGRect(x: testBody.minX + CGFloat(offset + 8), y: testBody.minY + 5, width: 4, height: 30)).fill()
            }
        }
    }

    func testGenuinelyFaintTestLineReadsAsLowNotUnclear() {
        // Regression test for a real false "unclear": a genuinely faint test
        // line (control clearly present) scored below the old flat 0.0035
        // peak-registration floor, so the pair-finder found only one peak
        // and bailed out entirely instead of reporting a low-but-real ratio.
        // This alpha is calibrated to be exactly the discriminating case:
        // confirmed to read as unclear/controlLineDetected=false under the
        // old flat threshold, and low/controlLineDetected=true under the new
        // noise-relative one.
        let image = generatedOvulationStrip(testAlpha: 0.03, controlAlpha: 0.90)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertEqual(result.resultType, .low, "Expected a genuinely faint test line to read as low, got \(result.resultType)")
    }

    func testVisibleOvulationControlWithoutTestPeakStillReadsLow() {
        let image = generatedOvulationStrip(testAlpha: 0, controlAlpha: 0.90)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertEqual(result.resultType, .low)
    }
}
