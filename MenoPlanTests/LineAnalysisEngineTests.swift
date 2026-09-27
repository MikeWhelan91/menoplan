import XCTest
import UIKit
@testable import MenoPlan


final class LineAnalysisEngineTests: XCTestCase {
    private let engine = LineAnalysisEngine()

    func testPregnancyNegativeFixtureMapsToNegative() {
        XCTAssertEqual(engine.pregnancyResult(test: 0.01, ratio: 0.05, testDetected: false), .appearsNegative)
    }

    func testPregnancyFaintFixtureMapsToFaintOrPositive() {
        XCTAssertEqual(engine.pregnancyResult(test: 0.11, ratio: 0.25, testDetected: true), .faintLineDetected)
    }

    func testPregnancyPositiveFixtureMapsToPositive() {
        XCTAssertEqual(engine.pregnancyResult(test: 0.4, ratio: 0.5, testDetected: true), .appearsPositive)
    }

    func testInvalidNoControlLineMapsToInvalid() {
        let quality = ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2)
        let result = LineAnalysisResult(resultType: .invalid, confidencePercentage: 0, certaintyPercentage: 45, controlLineDetected: false, testLineDetected: false, testControlRatio: 0, lineStrength: 0, quality: quality, explanation: "The control line was not detected.")
        XCTAssertEqual(result.resultType, .invalid)
        XCTAssertFalse(result.controlLineDetected)
    }

    func testGeneratedPositiveImageDetectsControlAndTestLines() {
        let image = generatedPregnancyTestImage(result: .appearsPositive)
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue(result.testLineDetected)
        XCTAssertTrue([.appearsPositive, .faintLineDetected].contains(result.resultType))
    }

    func testRotatedPositiveImageStillDetectsLines() {
        let image = generatedPregnancyTestImage(result: .appearsPositive)
        let rotated = rotateClockwise(image)
        let result = engine.analyse(rotated, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue(result.testLineDetected)
        XCTAssertTrue([.appearsPositive, .faintLineDetected].contains(result.resultType))
    }

    func testGeneratedNegativeImageDetectsOnlyControlLine() {
        let image = generatedPregnancyTestImage(result: .appearsNegative)
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertFalse(result.testLineDetected)
        XCTAssertEqual(result.resultType, .appearsNegative)
    }

    func testBlueControlLineInTheRightGuideHalfIsDetected() {
        let image = generatedPregnancyTestImage(
            result: .appearsNegative,
            lineColor: UIColor(red: 0.10, green: 0.25, blue: 0.88, alpha: 1)
        )
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertEqual(result.resultType, .appearsNegative)
    }

    func testPaleBlueMembraneWithOnlyControlLineStaysNegative() {
        let image = generatedPregnancyTestImage(
            result: .appearsNegative,
            windowColor: UIColor(red: 0.66, green: 0.83, blue: 0.90, alpha: 1)
        )
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertEqual(result.resultType, .appearsNegative)
        XCTAssertFalse(result.testLineDetected)
    }

    func testRealTestLineWithoutControlMapsToInvalid() throws {
        try assertTestLineOnlyFixtureIsInvalid("invalid-test-line-only-5169.JPG")
    }

    func testDeviceSavedTestLineWithoutControlMapsToInvalid() throws {
        try assertTestLineOnlyFixtureIsInvalid("invalid-test-line-only-5172-device.JPG")
    }

    private func assertTestLineOnlyFixtureIsInvalid(_ filename: String) throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Training/data/calibration-images/\(filename)")
        let alignedImage = try XCTUnwrap(UIImage(contentsOfFile: sourceURL.path))
        let lineRegion = TestTemplateGeometry.analysisImage(from: alignedImage, testType: .pregnancy)
        let result = engine.analyse(lineRegion, testType: .pregnancy)

        XCTAssertEqual(result.resultType, .invalid)
        XCTAssertFalse(result.controlLineDetected)
        XCTAssertTrue(result.testLineDetected)
    }

    func testShiftedControlAnchorsTheTestLineSearch() {
        let image = generatedPregnancyTestImage(
            result: .faintLineDetected,
            testAlpha: 0.24,
            testX: 300,
            controlX: 430
        )
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue(result.testLineDetected)
        XCTAssertTrue([.faintLineDetected, .appearsPositive].contains(result.resultType))
    }

    func testFullHeightNeutralSeamIsReportedAsNotClearRatherThanAColoredLine() {
        let image = generatedPregnancyTestImage(
            result: .appearsNegative,
            artifact: CGRect(x: 320, y: 116, width: 8, height: 68)
        )
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertFalse(result.testLineDetected)
        XCTAssertEqual(result.resultType, .unclear)
    }

    func testBarelyVisiblePregnancyMarkIsReportedAsFaintRatherThanNegative() {
        let image = generatedPregnancyTestImage(result: .faintLineDetected, testAlpha: 0.10)
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertEqual(result.resultType, .faintLineDetected)
        XCTAssertTrue(result.testLineDetected)
        XCTAssertLessThanOrEqual(result.certaintyPercentage, 82)
    }

    func testShortWindowArtifactIsNotAcceptedAsPregnancyLine() {
        let image = generatedPregnancyTestImage(
            result: .appearsNegative,
            artifact: CGRect(x: 320, y: 116, width: 13, height: 18)
        )
        let result = engine.analyse(image, testType: .pregnancy)

        XCTAssertFalse(result.testLineDetected)
        XCTAssertFalse([.appearsPositive, .faintLineDetected].contains(result.resultType))
    }

    func testPregnancyNegativeIsNeverOverriddenByEnhancedLocalDisagreement() {
        let ai = result(.appearsNegative, certainty: 96, testDetected: false)
        let original = result(.appearsNegative, certainty: 70, testDetected: false)
        let enhanced = result(.faintLineDetected, certainty: 81, testDetected: true)

        let reconciled = AIResultReconciler.reconcilePregnancyNegative(
            ai: ai,
            originalLocal: original,
            enhancedLocal: enhanced
        )

        XCTAssertEqual(reconciled.resultType, .appearsNegative)
        XCTAssertEqual(reconciled.certaintyPercentage, 96)
    }

    func testPregnancyNegativeIsNeverOverriddenEvenWhenBothLocalReadsDisagree() {
        // Regression test for a real false positive: a genuinely negative
        // test (single control line) whose local pixel reads mistook the
        // control line's own edge/enhancement artifact for a second line.
        // Local evidence must never overwrite Luna's own read, however
        // confidently it disagrees.
        let ai = result(.appearsNegative, certainty: 96, testDetected: false)
        let original = result(.faintLineDetected, certainty: 70, testDetected: true)
        let enhanced = result(.appearsPositive, certainty: 81, testDetected: true)

        let reconciled = AIResultReconciler.reconcilePregnancyNegative(
            ai: ai,
            originalLocal: original,
            enhancedLocal: enhanced
        )

        XCTAssertEqual(reconciled.resultType, .appearsNegative)
        XCTAssertEqual(reconciled.certaintyPercentage, 96)
    }

    func testMissingLocalEvidenceLeavesAIResultUnchanged() {
        let ai = result(.appearsNegative, certainty: 90, testDetected: false)

        let reconciled = AIResultReconciler.reconcilePregnancyNegative(
            ai: ai,
            originalLocal: nil,
            enhancedLocal: nil
        )

        XCTAssertEqual(reconciled, ai)
    }

    func testWeakAIPregnancyPositiveIsTightenedToFaint() {
        let ai = LineAnalysisResult(
            resultType: .appearsPositive,
            confidencePercentage: 92,
            certaintyPercentage: 92,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: 0.31,
            lineStrength: 0.26,
            quality: ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2),
            explanation: "Positive"
        )

        let reconciled = AIResultReconciler.tightenPregnancyPositive(ai)

        XCTAssertEqual(reconciled.resultType, .faintLineDetected)
        XCTAssertEqual(reconciled.certaintyPercentage, 92)
    }

    func testStrongAIPregnancyPositiveRemainsPositive() {
        let ai = LineAnalysisResult(
            resultType: .appearsPositive,
            confidencePercentage: 88,
            certaintyPercentage: 88,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: 0.72,
            lineStrength: 0.65,
            quality: ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2),
            explanation: "A clear result mark is visible."
        )

        XCTAssertEqual(AIResultReconciler.tightenPregnancyPositive(ai), ai)
    }

    func testLunaImagePreparationPreservesFaithfulCrop() {
        let image = generatedPregnancyTestImage(result: .faintLineDetected, testAlpha: 0.18)
        let prepared = LunaImagePreparationService.prepare(image)

        XCTAssertEqual(prepared.size, image.size)
        XCTAssertEqual(prepared.pngData(), image.pngData())
    }

    func testResizeReturnsOriginalImageWhenAlreadyWithinLimit() {
        let image = generatedPregnancyTestImage(result: .faintLineDetected, testAlpha: 0.18)
        let resized = ImageHelpers.resized(image, maxDimension: 1_400)

        XCTAssertTrue(resized === image)
    }


    func testGeneratedLowOvulationStripDoesNotMapToPeak() {
        let image = generatedOvulationStrip(testAlpha: 0.16, controlAlpha: 0.92)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue([.low, .rising].contains(result.resultType), "Expected weak test line to stay below high/peak, got \(result.resultType) at ratio \(result.testControlRatio)")
        XCTAssertLessThan(result.testControlRatio, 0.75)
    }

    func testGeneratedLowOvulationStripWithPurpleHandleAndCropArtifactDoesNotMapToPeak() {
        let image = generatedOvulationStrip(testAlpha: 0.14, controlAlpha: 0.90, purpleHandle: true, leftCropArtifact: true)
        let result = engine.analyse(image, testType: .ovulation)

        XCTAssertTrue(result.controlLineDetected)
        XCTAssertTrue([.low, .rising].contains(result.resultType), "Expected purple handle text and crop artifact to be ignored, got \(result.resultType) at ratio \(result.testControlRatio)")
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
        XCTAssertEqual(result.resultType, .peak)
        XCTAssertGreaterThanOrEqual(result.testControlRatio, 0.95)
    }

    func testStandaloneLocalOvulationConsensusKeepsPeakInsteadOfAmbiguous() {
        let quality = ImageQualityResult(status: .hardToDetect, brightness: 0.5, blurScore: 0.4, overexposure: 0.2)
        let primary = LineAnalysisResult(
            resultType: .peak,
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
            resultType: .high,
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

        XCTAssertEqual(localResult.resultType, .peak)
        XCTAssertEqual(localResult.testControlRatio, 1.20, accuracy: 0.001)
    }

    func testLocalPregnancyConsensusKeepsTwoFaintReadsFaint() {
        let primary = result(.faintLineDetected, certainty: 74, testDetected: true)
        let fallback = result(.faintLineDetected, certainty: 80, testDetected: true)

        let reconciled = engine.preferredPregnancyResult(primary: primary, fallback: fallback)

        XCTAssertEqual(reconciled.resultType, .faintLineDetected)
        XCTAssertTrue(reconciled.testLineDetected)
        XCTAssertLessThanOrEqual(reconciled.certaintyPercentage, 82)
    }

    func testEnhancedOnlyFaintLineIsNotPromotedOverANegativeOriginal() {
        let primary = result(.appearsNegative, certainty: 80, testDetected: false)
        let fallback = result(.faintLineDetected, certainty: 68, testDetected: true)

        let reconciled = engine.preferredPregnancyResult(primary: primary, fallback: fallback)

        XCTAssertEqual(reconciled.resultType, .unclear)
        XCTAssertTrue(reconciled.controlLineDetected)
        XCTAssertFalse(reconciled.testLineDetected)
        XCTAssertEqual(reconciled.certaintyPercentage, 52)
    }

    func testAIOvulationResultIsNotOverriddenByLocalMeasurement() {
        let quality = ImageQualityResult(status: .good, brightness: 0.5, blurScore: 0.2, overexposure: 0.2)
        let ai = LineAnalysisResult(
            resultType: .high,
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
            resultType: .peak,
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

        XCTAssertEqual(reconciled.resultType, .high)
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

    private func generatedPregnancyTestImage(
        result: ScanResultType,
        testAlpha: CGFloat = 1,
        artifact: CGRect? = nil,
        testX: CGFloat = 320,
        controlX: CGFloat = 385,
        lineColor: UIColor = UIColor(red: 0.94, green: 0.12, blue: 0.43, alpha: 1),
        windowColor: UIColor = .white
    ) -> UIImage {
        let size = CGSize(width: 720, height: 300)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let body = UIBezierPath(
                roundedRect: CGRect(x: 40, y: 65, width: 640, height: 170),
                cornerRadius: 54
            )
            UIColor(white: 0.97, alpha: 1).setFill()
            body.fill()

            let window = UIBezierPath(
                roundedRect: CGRect(x: 270, y: 104, width: 180, height: 92),
                cornerRadius: 28
            )
            windowColor.setFill()
            window.fill()

            lineColor.setFill()
            UIBezierPath(roundedRect: CGRect(x: controlX, y: 116, width: 13, height: 68), cornerRadius: 5).fill()
            if result != .appearsNegative {
                lineColor.withAlphaComponent(testAlpha).setFill()
                UIBezierPath(roundedRect: CGRect(x: testX, y: 116, width: 13, height: 68), cornerRadius: 5).fill()
            }
            if let artifact {
                UIColor(white: 0.35, alpha: 0.45).setFill()
                UIBezierPath(roundedRect: artifact, cornerRadius: 4).fill()
            }
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
