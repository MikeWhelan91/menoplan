import CoreGraphics
import UIKit

struct LineAnalysisResult: Equatable {
    var resultType: ScanResultType
    var confidencePercentage: Int
    var certaintyPercentage: Int
    var controlLineDetected: Bool
    var testLineDetected: Bool
    var testControlRatio: Double
    var lineStrength: Double
    var quality: ImageQualityResult
    var explanation: String
}

/// A deliberately fallible geometry proposal from the local strip scanner.
/// It does not classify the test or calculate the reported ratio; the
/// dedicated OPK model verifies that work from this image.
struct OvulationPairProposal {
    let image: UIImage
    let localConfidence: Int
}

extension LineAnalysisResult {
    /// Builds a result the user stated directly (results-page "This isn't
    /// right" correction), with no AI or local-scan measurement backing it.
    /// testControlRatio/lineStrength are representative placeholders only -
    /// there's no real measurement behind a manually declared result.
    static func manual(resultType: ScanResultType, quality: ImageQualityResult, testControlRatioOverride: Double? = nil) -> LineAnalysisResult {
        let testLineDetected: Bool
        let testControlRatio: Double
        let lineStrength: Double
        switch resultType {
        case .appearsPositive: (testLineDetected, testControlRatio, lineStrength) = (true, 0.6, 0.6)
        case .faintLineDetected: (testLineDetected, testControlRatio, lineStrength) = (true, 0.25, 0.25)
        case .low: (testLineDetected, testControlRatio, lineStrength) = (true, 0.25, 0.22)
        case .rising: (testLineDetected, testControlRatio, lineStrength) = (true, 0.55, 0.42)
        case .high: (testLineDetected, testControlRatio, lineStrength) = (true, 0.85, 0.68)
        case .peak: (testLineDetected, testControlRatio, lineStrength) = (true, 1.05, 0.84)
        default: (testLineDetected, testControlRatio, lineStrength) = (false, 0, 0)
        }
        return LineAnalysisResult(
            resultType: resultType,
            confidencePercentage: 100,
            certaintyPercentage: 100,
            controlLineDetected: true,
            testLineDetected: testLineDetected,
            testControlRatio: testControlRatioOverride ?? testControlRatio,
            lineStrength: lineStrength,
            quality: quality,
            explanation: "This result was corrected by you and saved as \(resultType.title)."
        )
    }

    /// The representative T/C ratio for a manually-declared ovulation
    /// result, used to pre-fill the ratio field when the user wants to
    /// fine-tune it rather than accept the category's typical value.
    static func defaultTestControlRatio(for resultType: ScanResultType) -> Double {
        switch resultType {
        case .appearsPositive: 0.6
        case .faintLineDetected, .low: 0.25
        case .rising: 0.55
        case .high: 0.85
        case .peak: 1.05
        default: 0
        }
    }
}

final class LineAnalysisEngine {
    private let qualityService = ImageQualityService()
    #if DEBUG
    /// Lets LineAnalysisEngineCalibrationTests capture internal peak/pair
    /// diagnostics from controlAnchoredPregnancyResult without changing its
    /// production behavior.
    nonisolated(unsafe) static var debugHook: ((String) -> Void)?
    #endif

    func analyse(_ image: UIImage, testType: TestType) -> LineAnalysisResult {
        let rawQuality = qualityService.score(image)
        // A guided OPK crop is predominantly white membrane by design - the
        // generic saturation metric was calibrated on full pregnancy-test
        // photos and mistakes that normal membrane for glare. Ported from
        // the identical fix already applied in
        // OnDeviceOvulationAnalysisService (2026-08-27) - it was never
        // carried over to this engine, so Manual Check for ovulation kept
        // surfacing a false "overexposed" warning the AI path had already
        // learned to ignore for the same input.
        let quality = testType == .ovulation && rawQuality.status == .overexposed
            ? ImageQualityResult(status: .good, brightness: rawQuality.brightness, blurScore: rawQuality.blurScore, overexposure: rawQuality.overexposure)
            : rawQuality
        guard let cgImage = ImageHelpers.resized(image, maxDimension: 520).cgImage else {
            return unclear(quality: quality)
        }
        if testType == .pregnancy,
           let colorImage = rgbImage(from: cgImage),
           let grayscale = grayscaleImage(from: cgImage) {
            if let anchored = controlAnchoredPregnancyResult(
                color: colorImage,
                grayscale: grayscale,
                quality: quality
            ) {
                return anchored
            }
            if let colorResult = pregnancyColorLineResult(in: colorImage, quality: quality) {
                return colorResult
            }
        }
        if testType == .ovulation,
           let colorImage = rgbImage(from: cgImage) {
            if let colorResult = ovulationColorStripResult(in: colorImage, quality: quality) {
                return colorResult
            }
        }
        if testType == .ovulation {
            guard let grayscale = grayscaleImage(from: cgImage),
                  let specialised = ovulationStripResult(in: grayscale, quality: quality) else {
                return unclear(quality: quality)
            }
            return specialised
        }

        guard let grayscale = grayscaleImage(from: cgImage), let candidate = bestCandidate(in: grayscale) else {
            return unclear(quality: quality)
        }

        return genericResult(candidate: candidate, grayscale: grayscale, quality: quality, testType: testType)
    }

    /// Reads the T/C box the user positioned inside the capture guide.  This
    /// deliberately does not hunt through the rest of a strip for the two
    /// strongest marks: first it proves a control in the guide's right half,
    /// then it measures only the physically valid test area to its left.
    /// That keeps window edges, printing and enhanced-image artefacts from
    /// being promoted to either line.
    private func guidedTemplateResult(
        color: RGBImage,
        grayscale: GrayscaleImage,
        quality: ImageQualityResult,
        testType: TestType
    ) -> LineAnalysisResult? {
        let axis: ColorLineAxis = color.width >= color.height ? .verticalLines : .horizontalLines
        let grayAxis: LineAxis = color.width >= color.height ? .verticalLines : .horizontalLines
        let count = axis.primaryCount(in: color)
        let crossCount = axis.crossCount(in: color)
        guard count > 44, crossCount > 24 else { return nil }

        let crossStart = Int(Double(crossCount) * 0.24)
        let crossEnd = Int(Double(crossCount) * 0.76)
        let whiteBalance = estimateWhiteBalanceGains(
            color: color, axis: axis, primaryCount: count, crossCount: crossCount,
            crossStart: crossStart, crossEnd: crossEnd
        )
        let colorProfile = (0..<count).map { primary -> Double in
            (crossStart..<crossEnd).reduce(0.0) { sum, cross in
                sum + axis.pregnancyLineSignal(in: color, primary: primary, cross: cross, whiteBalance: whiteBalance)
            } / Double(max(1, crossEnd - crossStart))
        }
        let grayProfile = (0..<count).map { primary -> Double in
            (crossStart..<crossEnd).reduce(0.0) { sum, cross in
                sum + 1 - grayAxis.luminance(in: grayscale, primary: primary, cross: cross)
            } / Double(max(1, crossEnd - crossStart))
        }
        let colorContrast = localContrastProfile(colorProfile)
        let grayContrast = localContrastProfile(grayProfile)
        let colorNoise = max(0.0025, standardDeviation(colorContrast))
        let grayNoise = max(0.012, standardDeviation(grayContrast))

        func evidence(at index: Int) -> (color: Double, gray: Double, support: Int) {
            (
                colorContrast[index],
                grayContrast[index],
                anchoredLineSupport(
                    color: color, colorAxis: axis, primary: index,
                    crossStart: crossStart, crossEnd: crossEnd,
                    colorThreshold: max(0.0025, colorNoise * 0.55)
                )
            )
        }
        func score(_ index: Int) -> Double {
            let value = evidence(at: index)
            return value.color / colorNoise + value.gray / grayNoise * 0.58
        }

        // C is always on the right half of the shared guide. Keep a margin
        // from its edge so a plastic/window boundary cannot become control.
        let controlRange = Int(Double(count) * 0.50)..<min(count - 2, Int(Double(count) * 0.84))
        guard let controlIndex = controlRange.max(by: { score($0) < score($1) }) else { return nil }
        let control = evidence(at: controlIndex)
        let controlDetected = control.support >= 2 && (
            control.color > max(0.006, colorNoise * 1.1)
                || control.gray > max(0.030, grayNoise * 1.55)
        )
        // Returning nil permits the established invalid/non-test fallbacks to
        // run; this reader never calls a missing control a negative result.
        guard controlDetected else { return nil }

        // The test mark must be left of the anchored control and separated
        // enough not to be its own shoulder. The generous left boundary
        // accepts different brands without admitting the guide edge.
        let testLower = max(2, Int(Double(count) * 0.10))
        let testUpper = controlIndex - max(5, Int(Double(count) * 0.10))
        guard testUpper > testLower else { return nil }
        guard let testIndex = (testLower..<testUpper).max(by: { score($0) < score($1) }) else { return nil }
        let test = evidence(at: testIndex)
        // This is deliberately an absolute, line-supported floor rather than
        // a multiple of global colour noise. A strongly coloured control or
        // printed handle legitimately raises global variance and otherwise
        // hides a genuine faint T peak. The T/C template has already limited
        // this check to the expected test position, and it must repeat in at
        // least two vertical segments.
        let colouredTest = test.support >= 2 && test.color > 0.0018
        let grayAnomaly = !colouredTest && test.gray > max(0.018, grayNoise * 1.10)
        let controlMagnitude = control.color + control.gray * 0.12
        let testMagnitude = test.color + test.gray * 0.12
        let ratio = min(2, min(
            testMagnitude / max(controlMagnitude, 0.004),
            test.color / max(control.color, 0.003)
        ))
        let certainty = min(88, max(56, 58 + Int(score(controlIndex) * 4)))
        #if DEBUG
        Self.debugHook?("guidedTemplate type=\(testType) count=\(count) control=\(controlIndex) test=\(testIndex) controlColor=\(control.color) controlGray=\(control.gray) testColor=\(test.color) testGray=\(test.gray) support=\(test.support) colorNoise=\(colorNoise) grayNoise=\(grayNoise) coloured=\(colouredTest) grayAnomaly=\(grayAnomaly) ratio=\(ratio)")
        #endif

        if grayAnomaly {
            return LineAnalysisResult(
                resultType: .unclear, confidencePercentage: 52, certaintyPercentage: 52,
                controlLineDetected: true, testLineDetected: false,
                testControlRatio: ratio, lineStrength: min(1, score(testIndex) / 8),
                quality: quality,
                explanation: "A possible mark is visible in the test area, but this photo cannot confirm a coloured test line. Retake the photo in even light or repeat with a new test."
            )
        }

        if testType == .pregnancy {
            let result: ScanResultType = colouredTest
                ? (ratio >= LineAnalysisConstants.pregnancyPositiveThreshold ? .appearsPositive : .faintLineDetected)
                : .appearsNegative
            return LineAnalysisResult(
                resultType: result, confidencePercentage: certainty, certaintyPercentage: certainty,
                controlLineDetected: true, testLineDetected: colouredTest,
                testControlRatio: ratio, lineStrength: min(1, score(testIndex) / 8),
                quality: quality, explanation: explanation(for: result, ratio: ratio)
            )
        }

        let result = ovulationResult(ratio: ratio, testDetected: colouredTest)
        return LineAnalysisResult(
            resultType: result, confidencePercentage: certainty, certaintyPercentage: certainty,
            controlLineDetected: true, testLineDetected: colouredTest,
            testControlRatio: ratio, lineStrength: min(1, score(testIndex) / 8),
            quality: quality, explanation: explanation(for: result, ratio: ratio)
        )
    }

    /// Finds a plausible left-test/right-control window in the complete strip.
    /// The source image is never mirrored or rotated here. The returned window
    /// is only a candidate for the learned verifier, not a diagnosis.
    func ovulationPairProposal(from image: UIImage) -> OvulationPairProposal? {
        guard let cgImage = ImageHelpers.resized(image, maxDimension: 520).cgImage,
              let colorImage = rgbImage(from: cgImage) else { return nil }
        let width = colorImage.width
        let height = colorImage.height
        func fallbackProposal() -> OvulationPairProposal? {
            // The user has already aligned an OPK inside the phone guide. If
            // dye detection is inconclusive, preserve that broad physical
            // window and let the learned verifier decide whether it contains
            // a real T/C pair. Returning no image here made a fallible local
            // locator an accidental veto over the model.
            let left = Int((Double(width) * 0.06).rounded())
            let right = Int((Double(width) * 0.94).rounded())
            let top = Int((Double(height) * 0.08).rounded())
            let bottom = Int((Double(height) * 0.92).rounded())
            guard right > left, bottom > top,
                  let crop = cgImage.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) else { return nil }
            return OvulationPairProposal(image: UIImage(cgImage: crop), localConfidence: 20)
        }
        let xStart = Int(Double(width) * 0.03)
        let xEnd = Int(Double(width) * 0.97)
        let yStart = Int(Double(height) * 0.18)
        let yEnd = Int(Double(height) * 0.82)
        guard xEnd - xStart > 100, yEnd - yStart > 18 else { return nil }

        let dyeProfile = (xStart..<xEnd).map { x -> Double in
            (yStart..<yEnd).reduce(0.0) { $0 + colorImage.purpleLineSignal(x: x, y: $1) }
                / Double(max(1, yEnd - yStart))
        }
        let handleProfile = (xStart..<xEnd).map { x -> Double in
            (yStart..<yEnd).reduce(0.0) { $0 + colorImage.handleRegionSignal(x: x, y: $1) }
                / Double(max(1, yEnd - yStart))
        }
        let smoothed = smooth(dyeProfile)
        let sorted = smoothed.sorted()
        let scores = smoothed.map { max(0, $0 - sorted[sorted.count / 2]) }
        let noise = max(0.004, standardDeviation(scores))
        // Inputs are prepared in canonical source orientation: handle right,
        // test left, control right. Never infer a flip from coloured plastic
        // or printed MAX text.
        let detectedHandle = ovulationHandle(from: handleProfile)
        let boundary = detectedHandle?.side == .right
            ? detectedHandle!.boundaryIndex
            : Int(Double(scores.count) * 0.74)
        let handle = OvulationHandle(side: .right, boundaryIndex: boundary)
        guard let pair = strongestOvulationColorPair(in: scores, handle: handle, noise: noise) else {
            return fallbackProposal()
        }

        let testX = xStart + pair.left.index
        let controlX = xStart + pair.right.index
        let gap = controlX - testX
        guard gap > 8 else { return nil }
        let left = max(0, Int((Double(testX) - 1.35 * Double(gap)).rounded()))
        let right = min(width, Int((Double(controlX) + 1.35 * Double(gap)).rounded()))
        let top = Int((Double(height) * 0.08).rounded())
        let bottom = Int((Double(height) * 0.92).rounded())
        guard right > left, bottom > top,
              let crop = cgImage.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) else { return nil }
        let confidence = min(95, max(35, Int(min(pair.left.value, pair.right.value) / noise * 16)))
        return OvulationPairProposal(image: UIImage(cgImage: crop), localConfidence: confidence)
    }

    private func genericResult(candidate: LineCandidate, grayscale: GrayscaleImage, quality: ImageQualityResult, testType: TestType) -> LineAnalysisResult {
        let control = candidate.control
        let test = candidate.test
        let noise = candidate.noise
        let controlDetected = candidate.controlDetected
        let testDetected = candidate.testDetected
        let ratio = controlDetected ? min(2.0, test / max(control, 0.01)) : 0
        var certainty = conservativeCertainty(control: control, test: test, noise: noise, quality: quality, controlDetected: controlDetected)

        guard controlDetected else {
            return LineAnalysisResult(resultType: .invalid, confidencePercentage: 0, certaintyPercentage: max(40, certainty), controlLineDetected: false, testLineDetected: false, testControlRatio: 0, lineStrength: 0, quality: quality, explanation: "The control line was not detected. This test may be invalid or the photo may be unclear.")
        }
        if quality.status != .good && certainty < 58 {
            return LineAnalysisResult(resultType: .unclear, confidencePercentage: certainty, certaintyPercentage: certainty, controlLineDetected: true, testLineDetected: testDetected, testControlRatio: ratio, lineStrength: test, quality: quality, explanation: "This image may be hard to analyse. Try retaking it with even lighting.")
        }
        if testType == .pregnancy,
           !testDetected,
           candidate.plausibleSpacing,
           candidate.testSupport >= 2,
           test > max(0.018, noise * 0.92),
           ratio >= 0.09 {
            certainty = min(58, certainty)
            return LineAnalysisResult(
                resultType: .unclear,
                confidencePercentage: certainty,
                certaintyPercentage: certainty,
                controlLineDetected: true,
                testLineDetected: false,
                testControlRatio: ratio,
                lineStrength: test,
                quality: quality,
                explanation: "A faint mark may be present, but it can’t be confirmed from this image. Check the test within its reading window and repeat with a new test in a few days, or when the test instructions recommend."
            )
        }
        let pregnancyLineDetected = testDetected
        let ovulationLineDetected = testDetected || (test > max(noise * 1.08, 0.024) && ratio > 0.075)
        let mapped = testType == .pregnancy
            ? pregnancyResult(test: test, ratio: ratio, testDetected: pregnancyLineDetected)
            : ovulationResult(ratio: ratio, testDetected: ovulationLineDetected)
        if mapped == .faintLineDetected {
            certainty = min(82, certainty)
        } else if mapped == .appearsNegative {
            certainty = min(88, certainty)
        }
        let reportedTestDetected = testType == .pregnancy ? pregnancyLineDetected : ovulationLineDetected
        let lineResult = LineAnalysisResult(
            resultType: mapped,
            confidencePercentage: certainty,
            certaintyPercentage: certainty,
            controlLineDetected: true,
            testLineDetected: reportedTestDetected,
            testControlRatio: ratio,
            lineStrength: test,
            quality: quality,
            explanation: explanation(for: mapped, ratio: ratio)
        )

        if testType == .pregnancy,
           let crossResult = crossPregnancyResult(in: grayscale, quality: quality) {
            if mapped == .appearsPositive || mapped == .faintLineDetected {
                return mergedPregnancyResult(lineResult: lineResult, crossResult: crossResult)
            }
            return crossResult
        }

        return lineResult
    }


    func preferredOvulationResult(primary: LineAnalysisResult, fallback: LineAnalysisResult) -> LineAnalysisResult {
        let primaryRank = ovulationRank(primary.resultType)
        let fallbackRank = ovulationRank(fallback.resultType)
        let ratioGap = abs(primary.testControlRatio - fallback.testControlRatio)
        let consensusRatio = (primary.testControlRatio + fallback.testControlRatio) / 2

        // If both analysers found both lines and their combined measurement is
        // peak-strength, preserve that strong signal instead of turning a
        // disagreement in the individual estimates into an ambiguous result.
        if primary.controlLineDetected,
           fallback.controlLineDetected,
           primary.testLineDetected,
           fallback.testLineDetected,
           consensusRatio >= 0.95 {
            return LineAnalysisResult(
                resultType: .peak,
                confidencePercentage: max(68, min(primary.certaintyPercentage, fallback.certaintyPercentage)),
                certaintyPercentage: max(68, min(primary.certaintyPercentage, fallback.certaintyPercentage)),
                controlLineDetected: true,
                testLineDetected: true,
                testControlRatio: min(2, consensusRatio),
                lineStrength: max(primary.lineStrength, fallback.lineStrength),
                quality: primary.quality,
                explanation: explanation(for: .peak, ratio: consensusRatio)
            )
        }

        if primaryRank >= 0,
           fallbackRank >= 0,
           abs(primaryRank - fallbackRank) >= 2,
           ratioGap >= 0.28 {
            return LineAnalysisResult(
                resultType: .unclear,
                confidencePercentage: 52,
                certaintyPercentage: 52,
                controlLineDetected: primary.controlLineDetected || fallback.controlLineDetected,
                testLineDetected: primary.testLineDetected || fallback.testLineDetected,
                testControlRatio: (primary.testControlRatio + fallback.testControlRatio) / 2,
                lineStrength: max(primary.lineStrength, fallback.lineStrength),
                quality: primary.quality,
                explanation: "The test and control lines can’t be compared clearly. Repeat the test with a new photo in even light."
            )
        }

        if primary.quality.status == .good {
            if primaryRank == fallbackRank { return primary }
            if primaryRank > fallbackRank, primary.testControlRatio >= 0.60 { return primary }
            if ratioGap >= 0.22 && primary.certaintyPercentage >= fallback.certaintyPercentage { return primary }
        }

        if fallback.quality.status == .good && fallbackRank > primaryRank && fallback.testControlRatio >= 0.82 {
            return fallback
        }

        return primary.certaintyPercentage >= fallback.certaintyPercentage ? primary : fallback
    }

    /// Reconciles the faithful crop with the locally enhanced copy. Enhancement
    /// can reveal a faint mark, but it can also amplify shadows and plastic
    /// edges, so enhanced-only evidence is never promoted to a positive result.
    func preferredPregnancyResult(primary: LineAnalysisResult, fallback: LineAnalysisResult) -> LineAnalysisResult {
        let primaryPositive = primary.resultType == .appearsPositive || primary.resultType == .faintLineDetected
        let fallbackPositive = fallback.resultType == .appearsPositive || fallback.resultType == .faintLineDetected

        if primaryPositive && fallbackPositive {
            let bothStrong = primary.resultType == .appearsPositive
                && fallback.resultType == .appearsPositive
                && min(primary.testControlRatio, fallback.testControlRatio) >= LineAnalysisConstants.pregnancyPositiveThreshold
            let resultType: ScanResultType = bothStrong ? .appearsPositive : .faintLineDetected
            let certainty = bothStrong
                ? min(primary.certaintyPercentage, fallback.certaintyPercentage)
                : min(82, max(58, min(primary.certaintyPercentage, fallback.certaintyPercentage)))
            return LineAnalysisResult(
                resultType: resultType,
                confidencePercentage: certainty,
                certaintyPercentage: certainty,
                controlLineDetected: primary.controlLineDetected && fallback.controlLineDetected,
                testLineDetected: true,
                testControlRatio: min(2, (primary.testControlRatio + fallback.testControlRatio) / 2),
                lineStrength: max(primary.lineStrength, fallback.lineStrength),
                quality: primary.quality,
                explanation: explanation(for: resultType, ratio: (primary.testControlRatio + fallback.testControlRatio) / 2)
            )
        }

        if primaryPositive {
            var result = primary
            result.resultType = .faintLineDetected
            result.confidencePercentage = min(72, result.confidencePercentage)
            result.certaintyPercentage = min(72, result.certaintyPercentage)
            result.explanation = "A possible faint test line is visible in the original photo, but the adjusted view does not agree. Check within the test’s reading window and consider repeating the test."
            return result
        }

        if fallbackPositive {
            return LineAnalysisResult(
                resultType: .unclear,
                confidencePercentage: 52,
                certaintyPercentage: 52,
                controlLineDetected: primary.controlLineDetected || fallback.controlLineDetected,
                testLineDetected: false,
                testControlRatio: fallback.testControlRatio,
                lineStrength: fallback.lineStrength,
                quality: primary.quality,
                explanation: "A possible mark appears only after image adjustment, so this local check cannot confirm it. Review the original test and consider repeating with a new photo."
            )
        }

        if primary.resultType == .appearsNegative,
           fallback.resultType == .appearsNegative,
           primary.controlLineDetected,
           fallback.controlLineDetected {
            var result = primary.certaintyPercentage >= fallback.certaintyPercentage ? primary : fallback
            result.confidencePercentage = min(88, result.confidencePercentage)
            result.certaintyPercentage = min(88, result.certaintyPercentage)
            return result
        }

        if primary.controlLineDetected, primary.resultType != .invalid { return primary }
        if fallback.controlLineDetected, fallback.resultType != .invalid { return fallback }
        return primary.certaintyPercentage >= fallback.certaintyPercentage ? primary : fallback
    }

    private func mergedPregnancyResult(lineResult: LineAnalysisResult, crossResult: LineAnalysisResult) -> LineAnalysisResult {
        LineAnalysisResult(
            resultType: .appearsPositive,
            confidencePercentage: max(lineResult.confidencePercentage, crossResult.confidencePercentage),
            certaintyPercentage: max(lineResult.certaintyPercentage, crossResult.certaintyPercentage),
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: max(lineResult.testControlRatio, crossResult.testControlRatio),
            lineStrength: max(lineResult.lineStrength, crossResult.lineStrength),
            quality: lineResult.quality,
            explanation: crossResult.explanation
        )
    }

    func pregnancyResult(test: Double, ratio: Double, testDetected: Bool) -> ScanResultType {
        guard testDetected else { return .appearsNegative }
        if ratio >= LineAnalysisConstants.pregnancyPositiveThreshold { return .appearsPositive }
        if ratio >= LineAnalysisConstants.pregnancyFaintThreshold || test > 0 { return .faintLineDetected }
        return .appearsNegative
    }

    func ovulationResult(ratio: Double) -> ScanResultType {
        ovulationResult(ratio: ratio, testDetected: ratio > 0)
    }

    func ovulationResult(ratio: Double, testDetected: Bool) -> ScanResultType {
        guard testDetected else { return .low }
        if ratio <= LineAnalysisConstants.ovulationLowUpper { return .low }
        if ratio <= LineAnalysisConstants.ovulationRisingUpper { return .rising }
        if ratio <= LineAnalysisConstants.ovulationHighUpper { return .high }
        return .peak
    }

    private func ovulationRank(_ resultType: ScanResultType) -> Int {
        switch resultType {
        case .low: 0
        case .rising: 1
        case .high: 2
        case .peak: 3
        default: -1
        }
    }

    private func smooth(_ values: [Double]) -> [Double] {
        values.indices.map { index in
            let lo = max(0, index - 2)
            let hi = min(values.count - 1, index + 2)
            return values[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
    }

    private func grayscaleImage(from cgImage: CGImage) -> GrayscaleImage? {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard context != nil else { return nil }
        return GrayscaleImage(width: width, height: height, pixels: pixels)
    }

    private func rgbImage(from cgImage: CGImage) -> RGBImage? {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard context != nil else { return nil }
        return RGBImage(width: width, height: height, pixels: pixels)
    }

    private func bestCandidate(in image: GrayscaleImage) -> LineCandidate? {
        let axes: [LineAxis] = [.verticalLines, .horizontalLines]
        let primaryRanges: [ClosedRange<Double>] = [0.06...0.94, 0.15...0.85]
        let crossRanges: [ClosedRange<Double>] = [
            0.18...0.82,
            0.25...0.75,
            0.32...0.68,
            0.38...0.62
        ]

        var candidates: [LineCandidate] = []
        for axis in axes {
            for primaryRange in primaryRanges {
                for crossRange in crossRanges {
                    guard let profile = lineProfile(in: image, axis: axis, primaryRange: primaryRange, crossRange: crossRange) else { continue }
                    candidates.append(contentsOf: lineCandidates(from: profile, axis: axis))
                }
            }
        }

        return candidates.max { $0.score < $1.score }
    }

    private func crossPregnancyResult(in image: GrayscaleImage, quality: ImageQualityResult) -> LineAnalysisResult? {
        guard let candidate = bestCrossCandidate(in: image), candidate.isPositive else { return nil }
        let ratio = min(2.0, candidate.vertical / max(candidate.horizontal, 0.01))
        let certainty = min(
            LineAnalysisConstants.maxCertainty,
            max(62, 58 + Int(candidate.score * 9) - (quality.status == .good ? 0 : 10))
        )
        return LineAnalysisResult(
            resultType: .faintLineDetected,
            confidencePercentage: certainty,
            certaintyPercentage: certainty,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: ratio,
            lineStrength: max(candidate.vertical, candidate.horizontal),
            quality: quality,
            explanation: "A possible cross-style pregnancy mark is visible. Check the test instructions and consider testing again in a few days."
        )
    }

    private func bestCrossCandidate(in image: GrayscaleImage) -> CrossCandidate? {
        let minSide = min(image.width, image.height)
        let sizes = [0.14, 0.18, 0.22, 0.27].map { max(36, Int(Double(minSide) * $0)) }
        // Keep the cross search inside the actual viewing window area.
        // Printed result legends can create strong edges outside the result window.
        // was being mistaken for a positive result when we scanned the full image.
        let xCenters = stride(from: 0.30, through: 0.58, by: 0.05).map { Int($0 * Double(image.width)) }
        let yCenters = stride(from: 0.36, through: 0.64, by: 0.07).map { Int($0 * Double(image.height)) }
        var best: CrossCandidate?

        for size in sizes {
            for centerX in xCenters {
                for centerY in yCenters {
                    let rect = CGRect(
                        x: centerX - size / 2,
                        y: centerY - size / 2,
                        width: size,
                        height: size
                    )
                    guard let candidate = crossCandidate(in: image, rect: rect) else { continue }
                    if best == nil || candidate.score > best!.score {
                        best = candidate
                    }
                }
            }
        }
        return best
    }

    private func crossCandidate(in image: GrayscaleImage, rect: CGRect) -> CrossCandidate? {
        let x0 = max(0, Int(rect.minX))
        let y0 = max(0, Int(rect.minY))
        let x1 = min(image.width, Int(rect.maxX))
        let y1 = min(image.height, Int(rect.maxY))
        guard x1 - x0 >= 30, y1 - y0 >= 30 else { return nil }

        let width = x1 - x0
        let height = y1 - y0
        let bandX0 = x0 + Int(Double(width) * 0.22)
        let bandX1 = x0 + Int(Double(width) * 0.78)
        let bandY0 = y0 + Int(Double(height) * 0.22)
        let bandY1 = y0 + Int(Double(height) * 0.78)

        var rowProfile = [Double]()
        for y in bandY0..<bandY1 {
            var sum = 0.0
            for x in bandX0..<bandX1 {
                sum += 1.0 - image.luminance(x: x, y: y)
            }
            rowProfile.append(sum / Double(max(1, bandX1 - bandX0)))
        }

        var columnProfile = [Double]()
        for x in bandX0..<bandX1 {
            var sum = 0.0
            for y in bandY0..<bandY1 {
                sum += 1.0 - image.luminance(x: x, y: y)
            }
            columnProfile.append(sum / Double(max(1, bandY1 - bandY0)))
        }

        guard let horizontal = centeredLinePeak(in: rowProfile),
              let vertical = centeredLinePeak(in: columnProfile) else { return nil }
        let noise = max(0.012, (horizontal.noise + vertical.noise) / 2)
        let horizontalSignal = horizontal.value / noise
        let verticalSignal = vertical.value / noise
        let score = horizontalSignal + verticalSignal
        let smallerArm = min(horizontal.value, vertical.value)
        let largerArm = max(horizontal.value, vertical.value)
        let balance = smallerArm / max(largerArm, 0.01)
        let horizontalOffset = abs(horizontal.position - 0.5)
        let verticalOffset = abs(vertical.position - 0.5)
        let isPositive = horizontal.value > max(0.02, horizontal.noise * 1.30)
            && vertical.value > max(0.018, vertical.noise * 1.18)
            && balance > 0.42
            && horizontalOffset < 0.16
            && verticalOffset < 0.16
            && score > 4.75
        return CrossCandidate(horizontal: horizontal.value, vertical: vertical.value, score: score, isPositive: isPositive)
    }

    private func centeredLinePeak(in profile: [Double]) -> (value: Double, noise: Double, position: Double)? {
        guard profile.count >= 18 else { return nil }
        let smoothed = smooth(profile)
        let sorted = smoothed.sorted()
        let background = sorted[sorted.count / 2]
        let scores = smoothed.map { max(0, $0 - background) }
        let noise = max(0.01, standardDeviation(scores))
        let lower = Int(Double(scores.count) * 0.30)
        let upper = max(lower + 1, Int(Double(scores.count) * 0.70))
        let window = Array(scores[lower..<upper])
        guard let peak = window.max(), let peakOffset = window.firstIndex(of: peak) else { return nil }
        let peakIndex = lower + peakOffset
        let position = Double(peakIndex) / Double(max(scores.count - 1, 1))
        return (peak, noise, position)
    }

    private func lineProfile(in image: GrayscaleImage, axis: LineAxis, primaryRange: ClosedRange<Double>, crossRange: ClosedRange<Double>) -> LineProfile? {
        let primaryCount = axis.primaryCount(in: image)
        let crossCount = axis.crossCount(in: image)
        let primaryStart = max(0, Int(primaryRange.lowerBound * Double(primaryCount)))
        let primaryEnd = min(primaryCount, Int(primaryRange.upperBound * Double(primaryCount)))
        let crossStart = max(0, Int(crossRange.lowerBound * Double(crossCount)))
        let crossEnd = min(crossCount, Int(crossRange.upperBound * Double(crossCount)))
        guard primaryEnd - primaryStart > 24, crossEnd - crossStart > 12 else { return nil }

        let full = averageProfile(in: image, axis: axis, primaryStart: primaryStart, primaryEnd: primaryEnd, crossStart: crossStart, crossEnd: crossEnd)
        let segmentSize = max(1, (crossEnd - crossStart) / 3)
        let segments = (0..<3).map { segment in
            let start = crossStart + segment * segmentSize
            let end = segment == 2 ? crossEnd : min(crossEnd, start + segmentSize)
            return averageProfile(in: image, axis: axis, primaryStart: primaryStart, primaryEnd: primaryEnd, crossStart: start, crossEnd: end)
        }
        return LineProfile(values: full, segmentValues: segments)
    }

    private func averageProfile(in image: GrayscaleImage, axis: LineAxis, primaryStart: Int, primaryEnd: Int, crossStart: Int, crossEnd: Int) -> [Double] {
        (primaryStart..<primaryEnd).map { primary in
            var sum = 0.0
            var count = 0.0
            for cross in crossStart..<crossEnd {
                let luminance = axis.luminance(in: image, primary: primary, cross: cross)
                sum += 1.0 - luminance
                count += 1
            }
            return sum / max(count, 1)
        }
    }

    private func lineCandidates(from profile: LineProfile, axis: LineAxis) -> [LineCandidate] {
        guard profile.values.count > 24 else { return [] }
        let sorted = profile.values.sorted()
        let background = sorted[sorted.count / 2]
        let lineScores = smooth(profile.values).map { max(0, $0 - background) }
        let noise = max(0.018, standardDeviation(lineScores))

        let segmentScores = profile.segmentValues.map { values in
            let segmentBackground = values.sorted()[values.count / 2]
            return smooth(values).map { max(0, $0 - segmentBackground) }
        }

        return [makeTwoLineCandidate(lineScores: lineScores, segmentScores: segmentScores, noise: noise, axis: axis)]
    }

    private func ovulationStripResult(in image: GrayscaleImage, quality: ImageQualityResult) -> LineAnalysisResult? {
        let width = image.width
        let height = image.height
        // The guided crop places the complete T/C search box in the centre.
        // Keep MAX text and the coloured handle outside the fallback profile;
        // otherwise their dark edges can outscore a real faint test line.
        let xStart = Int(Double(width) * 0.32)
        let xEnd = Int(Double(width) * 0.60)
        let yStart = Int(Double(height) * 0.38)
        let yEnd = Int(Double(height) * 0.62)
        guard xEnd - xStart > 80, yEnd - yStart > 18 else { return nil }

        let profile = (xStart..<xEnd).map { x -> Double in
            var sum = 0.0
            for y in yStart..<yEnd {
                sum += 1.0 - image.luminance(x: x, y: y)
            }
            return sum / Double(max(1, yEnd - yStart))
        }

        let smoothed = smooth(profile)
        let sorted = smoothed.sorted()
        let background = sorted[sorted.count / 2]
        let scores = smoothed.map { max(0, $0 - background) }
        let noise = max(0.012, standardDeviation(scores))
        guard let pair = strongestOrderedPair(in: scores) else { return nil }

        // Compare each band with membrane immediately around that same band.
        // A global background makes a faint line in a shadow look as strong as
        // a darker control in a brighter part of the strip.
        let test = localLineContrast(in: smoothed, at: pair.left.index)
        let control = localLineContrast(in: smoothed, at: pair.right.index)
        let controlDetected = control > max(LineAnalysisConstants.controlThreshold * 0.55, noise * 1.9)
        let testDetected = test > max(0.018, noise * 1.08)
        guard controlDetected else { return nil }

        // Remove the minimum visible contrast floor from both bands before
        // forming T/C. This stops membrane texture/JPEG haze from inflating a
        // faint line while preserving equality for genuinely equal lines.
        let contrastFloor = 0.014
        let correctedTest = max(0, test - contrastFloor)
        let correctedControl = max(0, control - contrastFloor)
        let ratio = min(2.0, correctedTest / max(correctedControl, 0.01))
        let resultType = ovulationResult(ratio: ratio, testDetected: testDetected)
        let spacingBonus = pair.distanceFraction.map { max(0, 1.0 - abs($0 - 0.20) * 2.0) } ?? 0
        let certainty = min(
            LineAnalysisConstants.maxCertainty,
            max(
                LineAnalysisConstants.minCertainty,
                52 + Int((control / max(noise, 0.012)) * 7.5) + Int((test / max(noise, 0.012)) * 4.5) + Int(spacingBonus * 10)
            )
        )

        return LineAnalysisResult(
            resultType: resultType,
            confidencePercentage: certainty,
            certaintyPercentage: certainty,
            controlLineDetected: true,
            testLineDetected: testDetected,
            testControlRatio: ratio,
            lineStrength: test,
            quality: quality,
            explanation: explanation(for: resultType, ratio: ratio)
        )
    }

    /// Pink and purple test lines can be lighter than shadows, outlines, or text on
    /// a test body. The generic grayscale reader can therefore lock onto the wrong
    /// pair of features with high confidence. Prefer a chroma-based two-line read
    /// when a clearly colored pregnancy line pair is present, then retain the
    /// grayscale reader as the fallback for blue-dye and monochrome tests.
    private func pregnancyColorLineResult(in image: RGBImage, quality: ImageQualityResult) -> LineAnalysisResult? {
        let axes: [ColorLineAxis] = [.verticalLines, .horizontalLines]
        let crossRanges: [ClosedRange<Double>] = [0.24...0.76, 0.32...0.68, 0.38...0.62]
        var bestPair: ColorLinePair?

        for axis in axes {
            let primaryCount = axis.primaryCount(in: image)
            let crossCount = axis.crossCount(in: image)

            for crossRange in crossRanges {
                let crossStart = max(0, Int(crossRange.lowerBound * Double(crossCount)))
                let crossEnd = min(crossCount, Int(crossRange.upperBound * Double(crossCount)))
                guard crossEnd - crossStart > 12 else { continue }

                let profile = (0..<primaryCount).map { primary -> Double in
                    var sum = 0.0
                    for cross in crossStart..<crossEnd {
                        sum += axis.pregnancyLineSignal(in: image, primary: primary, cross: cross)
                    }
                    return sum / Double(crossEnd - crossStart)
                }

                guard let pair = strongestPregnancyColorPair(in: profile, axis: axis) else { continue }
                if bestPair == nil || pair.score > bestPair!.score {
                    bestPair = pair
                }
            }
        }

        guard let pair = bestPair else { return nil }
        let ratio = min(2.0, pair.weaker / max(pair.stronger, 0.01))
        let qualityPenalty = quality.status == .good ? 0 : 10
        let certainty = min(
            LineAnalysisConstants.maxCertainty,
            max(64, 68 + Int(pair.score * 34) - qualityPenalty)
        )

        return LineAnalysisResult(
            resultType: ratio >= LineAnalysisConstants.pregnancyPositiveThreshold ? .appearsPositive : .faintLineDetected,
            confidencePercentage: certainty,
            certaintyPercentage: certainty,
            controlLineDetected: true,
            testLineDetected: true,
            testControlRatio: ratio,
            lineStrength: pair.weaker,
            quality: quality,
            explanation: explanation(for: ratio >= LineAnalysisConstants.pregnancyPositiveThreshold ? .appearsPositive : .faintLineDetected, ratio: ratio)
        )
    }

    /// Reads a guided pregnancy result window by finding the control line
    /// first, then looking only at plausible test-line positions to its left.
    /// The same ordering applies after rotating a horizontal result window:
    /// "above control" becomes the lower primary coordinate.
    private func controlAnchoredPregnancyResult(
        color: RGBImage,
        grayscale: GrayscaleImage,
        quality: ImageQualityResult
    ) -> LineAnalysisResult? {
        // The guided result window is wider than it is tall for vertical
        // lines, and taller than it is wide after a quarter-turn. Searching
        // both axes lets a horizontal window edge masquerade as a control
        // line on otherwise valid-looking invalid tests.
        let axes: [(color: ColorLineAxis, gray: LineAxis)] = color.width >= color.height
            ? [(.verticalLines, .verticalLines)]
            : [(.horizontalLines, .horizontalLines)]
        var best: AnchoredPregnancyEvidence?

        for axesForDirection in axes {
            let primaryCount = axesForDirection.color.primaryCount(in: color)
            let crossCount = axesForDirection.color.crossCount(in: color)
            guard primaryCount > 44, crossCount > 24 else { continue }
            let crossStart = Int(Double(crossCount) * 0.24)
            let crossEnd = Int(Double(crossCount) * 0.76)
            // The margins outside crossStart/crossEnd are already excluded
            // from line detection as presumed background/housing, not
            // window - reuse them as an in-photo white-balance reference
            // (2026-08-24, after researching how Premom's calibrated strips
            // solve this problem with a printed reference patch this app
            // has no equivalent of). Correcting toward what that housing
            // "should" read as neutral before measuring dye colour is the
            // same principle, without needing a manufactured reference.
            let whiteBalance = estimateWhiteBalanceGains(
                color: color,
                axis: axesForDirection.color,
                primaryCount: primaryCount,
                crossCount: crossCount,
                crossStart: crossStart,
                crossEnd: crossEnd
            )

            let colorProfile = (0..<primaryCount).map { primary -> Double in
                var sum = 0.0
                for cross in crossStart..<crossEnd {
                    sum += axesForDirection.color.pregnancyLineSignal(
                        in: color,
                        primary: primary,
                        cross: cross,
                        whiteBalance: whiteBalance
                    )
                }
                return sum / Double(max(1, crossEnd - crossStart))
            }
            let grayProfile = (0..<primaryCount).map { primary -> Double in
                var sum = 0.0
                for cross in crossStart..<crossEnd {
                    sum += 1.0 - axesForDirection.gray.luminance(
                        in: grayscale,
                        primary: primary,
                        cross: cross
                    )
                }
                return sum / Double(max(1, crossEnd - crossStart))
            }

            let colorContrast = localContrastProfile(colorProfile)
            let grayContrast = localContrastProfile(grayProfile)
            let colorNoise = max(0.0025, standardDeviation(colorContrast))
            let grayNoise = max(0.012, standardDeviation(grayContrast))
            let combined = zip(colorContrast, grayContrast).map { colorValue, grayValue in
                colorValue / colorNoise + grayValue / grayNoise * 0.58
            }

            // Locate every plausible line position first, then decide roles
            // by position (test is always left of control - confirmed fixed
            // physical convention), not by picking "the strongest feature in
            // a fixed window" and calling it control. That conflated
            // strength with role: a strong, dark, recent test line can
            // outscore a lighter control line and fall inside what used to
            // be the fixed 48-82% "control" window, getting misread as
            // control while the real (weaker) control line - possibly
            // further right than a fixed cutoff allowed - was never
            // considered at all. Confirmed on a real photo during
            // calibration (2026-08-27): a strength-1.0 double-line positive
            // read as Negative because the fixed window handed the reader
            // its own test line as "control" and found nothing where it
            // then searched for "test" to that line's left.
            func lineSupport(at index: Int) -> (color: Double, gray: Double, support: Int) {
                let supportCount = anchoredLineSupport(
                    color: color,
                    colorAxis: axesForDirection.color,
                    primary: index,
                    crossStart: crossStart,
                    crossEnd: crossEnd,
                    colorThreshold: max(0.0028, colorNoise * 0.72)
                )
                return (colorContrast[index], grayContrast[index], supportCount)
            }
            func passesControlThreshold(_ evidence: (color: Double, gray: Double, support: Int)) -> Bool {
                evidence.support >= 2
                    && (evidence.color > max(0.007, colorNoise * 1.25)
                        || evidence.gray > max(0.027, grayNoise * 1.75))
            }
            func passesTestThreshold(_ evidence: (color: Double, gray: Double, support: Int)) -> Bool {
                evidence.support >= 2 && evidence.color > max(0.0035, colorNoise * 0.82)
            }

            // Keep clear of the extreme edges, where window borders and
            // printed-legend boundaries live.
            let searchLower = max(1, Int(Double(primaryCount) * 0.04))
            let searchUpper = min(primaryCount - 1, Int(Double(primaryCount) * 0.95))
            guard searchUpper > searchLower + 2 else { continue }
            var peakIndices: [Int] = []
            for index in searchLower...searchUpper {
                let value = combined[index]
                guard value > 0 else { continue }
                let previous = index > searchLower ? combined[index - 1] : -Double.infinity
                let next = index < searchUpper ? combined[index + 1] : -Double.infinity
                if value >= previous && value >= next {
                    peakIndices.append(index)
                }
            }
            peakIndices.sort { combined[$0] > combined[$1] }
            let candidatePeaks = Array(peakIndices.prefix(10))

            let minimumDistance = max(5, Int(Double(primaryCount) * 0.055))
            let maximumDistance = max(minimumDistance + 1, Int(Double(primaryCount) * 0.46))
            // The shared capture guide fixes C in the right half of the T/C
            // box. Enforce that physical invariant so a red/blue mark on the
            // test side, printed text, or a window edge cannot validate the
            // control merely because it is the strongest local peak.
            let controlLowerBound = Int(Double(primaryCount) * 0.50)
            // The last sliver of a guided crop can be the plastic window's
            // right border. It has enough luminance contrast to masquerade
            // as C and turn a test-only invalid strip into a false negative.
            // A real control this close to the edge is not reliably framed;
            // fail closed instead of declaring a negative result.
            let controlUpperBound = Int(Double(primaryCount) * 0.88)

            var chosenControlIndex: Int?
            var chosenTestIndex: Int?
            var bestPairScore = -Double.infinity
            for controlCandidate in candidatePeaks {
                guard controlCandidate >= controlLowerBound, controlCandidate <= controlUpperBound else { continue }
                let controlEvidence = lineSupport(at: controlCandidate)
                guard passesControlThreshold(controlEvidence) else { continue }
                for testCandidate in candidatePeaks where testCandidate < controlCandidate {
                    let distance = controlCandidate - testCandidate
                    guard distance >= minimumDistance, distance <= maximumDistance else { continue }
                    let pairScore = combined[controlCandidate] + combined[testCandidate]
                    if pairScore > bestPairScore {
                        bestPairScore = pairScore
                        chosenControlIndex = controlCandidate
                        chosenTestIndex = testCandidate
                    }
                }
            }

            // A clear control can be valid even when its test companion is
            // too faint to clear the stricter pair threshold. Resolve that
            // control independently before calling the image unclear: the
            // old pair-only rule made a plainly visible control disappear on
            // faint-line photos, including Manual Check originals.
            if chosenControlIndex == nil {
                if let standaloneControl = candidatePeaks.first(where: {
                    $0 >= controlLowerBound && $0 <= controlUpperBound && passesControlThreshold(lineSupport(at: $0))
                }) {
                    let controlEvidence = lineSupport(at: standaloneControl)
                    // A very faint line often never makes the global top-ten
                    // peak list: the clear control, window boundary, and
                    // mild enhancement artefacts all outrank it. Once C is
                    // independently established in the right half, search
                    // every physically plausible position to its left for a
                    // repeated coloured mark instead of discarding it before
                    // the weak-line logic gets a chance to assess it.
                    let weakTest = (searchLower..<standaloneControl)
                        .filter { candidate in
                            let distance = standaloneControl - candidate
                            guard distance >= minimumDistance,
                                  distance <= maximumDistance else { return false }
                            let evidence = lineSupport(at: candidate)
                            return evidence.support >= 2
                                && (
                                    evidence.color > max(0.0018, colorNoise * 0.42)
                                    || evidence.gray > max(0.018, grayNoise * 1.10)
                                )
                        }
                        .max { combined[$0] < combined[$1] }

                    if let weakTest {
                        chosenControlIndex = standaloneControl
                        chosenTestIndex = weakTest
                    } else {
                        let controlStrength = controlEvidence.color / max(colorNoise, 0.0025) * 0.75
                            + controlEvidence.gray / max(grayNoise, 0.012) * 0.25
                        let certainty = min(88, max(58, 58 + Int(controlStrength * 5)))
                        return LineAnalysisResult(
                            resultType: .appearsNegative,
                            confidencePercentage: certainty,
                            certaintyPercentage: certainty,
                            controlLineDetected: true,
                            testLineDetected: false,
                            testControlRatio: 0,
                            lineStrength: 0,
                            quality: quality,
                            explanation: explanation(for: .appearsNegative, ratio: 0)
                        )
                    }
                }
            }

            // No qualifying control anywhere. A prominent,
            // independently-qualifying peak with no control is an invalid
            // test, not a negative one.
            if chosenControlIndex == nil {
                if candidatePeaks.contains(where: { passesTestThreshold(lineSupport(at: $0)) }) {
                    return LineAnalysisResult(
                        resultType: .invalid,
                        confidencePercentage: 0,
                        certaintyPercentage: 82,
                        controlLineDetected: false,
                        testLineDetected: true,
                        testControlRatio: 0,
                        // Zeroed like every other .invalid branch in this file -
                        // without a control line this isn't a real measurement,
                        // so it must not read as a strong data point on the
                        // line-strength trend chart or anywhere else that
                        // treats lineStrength as a trustworthy reading.
                        lineStrength: 0,
                        quality: quality,
                        explanation: "A test line is visible, but the control line is missing. This test is invalid and should be repeated with a new test."
                    )
                }
                continue
            }

            let controlIndex = chosenControlIndex!
            var testIndex = chosenTestIndex!
            let controlColor = colorContrast[controlIndex]
            let controlGray = grayContrast[controlIndex]

            // With C anchored on the right, a genuine very faint line may be
            // visible chiefly as a narrow grayscale dip rather than a dye
            // peak. Prefer that physically valid T candidate over a weaker
            // colour/edge pair selected earlier by the generic peak ranking.
            let grayscaleTestCandidates = (searchLower..<controlIndex).filter { candidate in
                let distance = controlIndex - candidate
                return distance >= minimumDistance && distance <= maximumDistance
            }
            // A colour-supported T candidate is stronger evidence than a
            // darker, dye-free window edge. Only use the grayscale rescue
            // when the selected candidate does not qualify as a dyed line.
            if !passesTestThreshold(lineSupport(at: testIndex)),
               let grayscaleTest = grayscaleTestCandidates.max(by: { grayContrast[$0] < grayContrast[$1] }),
               grayContrast[grayscaleTest] > max(0.018, grayNoise * 1.10),
               grayContrast[grayscaleTest] > grayContrast[testIndex] {
                testIndex = grayscaleTest
            }

            #if DEBUG
            Self.debugHook?("axis=\(axesForDirection.color) primaryCount=\(primaryCount) crossCount=\(crossCount) crossStart=\(crossStart) crossEnd=\(crossEnd) controlIndex=\(controlIndex) testIndex=\(testIndex) controlColor=\(controlColor) controlGray=\(controlGray) colorNoise=\(colorNoise) grayNoise=\(grayNoise) peaks=\(candidatePeaks)")
            #endif

            let testColor = colorContrast[testIndex]
            let testGray = grayContrast[testIndex]
            let testEvidence = lineSupport(at: testIndex)
            let support = testEvidence.support
            let testDetected = passesTestThreshold(testEvidence)
            let weakMarkDetected = support >= 2
                && testColor > max(0.0025, colorNoise * 0.60)
            let ambiguousGrayMarkDetected = !weakMarkDetected
                // The control has already been anchored in the guide's right
                // half and this candidate is already constrained to the
                // physically valid T area on its left. At that point a
                // narrow grayscale anomaly is possible evidence, but not
                // enough to confirm a Faint Line.
                && testGray > max(0.018, grayNoise * 1.10)
            // Was max(color, gray) - let a purely luminance-driven signal (a
            // shadow: dark, but no real dye chroma) report the same strength
            // as a genuinely coloured line, since the gray term alone could
            // dominate independent of any color evidence. Confirmed real
            // case 2026-08-23 (calibration): a window shadow measured
            // testColor near zero but testGray high enough that max() still
            // reported strength=0.1756 - high enough to be mistaken for real
            // partial evidence upstream. Colour now dominates the blend; a
            // true line is expected to show both real chroma and luminance
            // contrast together, not luminance alone.
            let controlStrength = controlColor / max(colorNoise, 0.0025) * 0.75 + controlGray / max(grayNoise, 0.012) * 0.25
            let testStrength = testColor / max(colorNoise, 0.0025) * 0.75 + testGray / max(grayNoise, 0.012) * 0.25
            // Use absolute local contrast for the T/C ratio. Dividing both
            // bands by noise independently made a barely visible line look
            // equal to a strong control line.
            let controlMagnitude = controlColor + controlGray * 0.12
            let testMagnitude = testColor + testGray * 0.12
            let magnitudeRatio = testMagnitude / max(controlMagnitude, 0.004)
            let dyeRatio = testColor / max(controlColor, 0.003)
            let ratio = min(2, min(magnitudeRatio, dyeRatio))
            #if DEBUG
            Self.debugHook?("testIndex=\(testIndex) testColor=\(testColor) testGray=\(testGray) support=\(support) testDetected=\(testDetected) magnitudeRatio=\(magnitudeRatio) dyeRatio=\(dyeRatio) ratio=\(ratio)")
            #endif
            let evidence = AnchoredPregnancyEvidence(
                controlStrength: controlStrength,
                testStrength: testStrength,
                ratio: ratio,
                support: support,
                // A weak coloured mark repeated across at least two vertical
                // segments is real spatial evidence, even when it misses the
                // stricter confidence threshold used for a normal line. Do
                // not discard it into a negative result: manual scan must
                // surface it as a faint line for the user to review.
                testDetected: testDetected || weakMarkDetected,
                weakMarkDetected: weakMarkDetected,
                ambiguousGrayMarkDetected: ambiguousGrayMarkDetected,
                score: controlStrength * 1.8 + (testDetected ? testStrength : 0)
                    + (axesForDirection.color == .verticalLines ? 0.35 : 0)
            )
            if best == nil || evidence.score > best!.score { best = evidence }
        }

        guard let evidence = best else { return nil }
        if evidence.ambiguousGrayMarkDetected {
            return LineAnalysisResult(
                resultType: .unclear,
                confidencePercentage: 52,
                certaintyPercentage: 52,
                controlLineDetected: true,
                testLineDetected: false,
                testControlRatio: evidence.ratio,
                lineStrength: min(1, evidence.testStrength / 8),
                quality: quality,
                explanation: "A possible faint mark is visible in the test area, but this photo cannot confirm it. Retake the photo in even light or repeat with a new test."
            )
        }
        let mapped = pregnancyResult(
            test: evidence.testStrength,
            ratio: evidence.ratio,
            testDetected: evidence.testDetected
        )
        let qualityPenalty = quality.status == .good ? 0 : 10
        var certainty = min(
            LineAnalysisConstants.maxCertainty,
            max(52, 58 + Int(evidence.controlStrength * 5) + evidence.support * 4 - qualityPenalty)
        )
        if evidence.weakMarkDetected { certainty = min(82, certainty) }
        return LineAnalysisResult(
            resultType: mapped,
            confidencePercentage: mapped == .appearsNegative ? min(90, certainty) : min(84, certainty),
            certaintyPercentage: mapped == .appearsNegative ? min(90, certainty) : min(84, certainty),
            controlLineDetected: true,
            testLineDetected: evidence.testDetected,
            testControlRatio: evidence.ratio,
            lineStrength: min(1, evidence.testStrength / 8),
            quality: quality,
            explanation: explanation(for: mapped, ratio: evidence.ratio)
        )
    }

    /// Samples the presumed-background margins for pixels that plausibly
    /// *are* neutral housing (bright, low-saturation - excludes shadows,
    /// ink marks, and edges that might leak into the margin at an angle),
    /// then returns per-channel gains that would make their average read as
    /// true neutral gray. Falls back to no correction (1,1,1) if too few
    /// trustworthy samples are found, rather than risk a wrong correction
    /// from a margin that doesn't actually contain visible housing.
    private func estimateWhiteBalanceGains(
        color: RGBImage,
        axis: ColorLineAxis,
        primaryCount: Int,
        crossCount: Int,
        crossStart: Int,
        crossEnd: Int
    ) -> (r: Double, g: Double, b: Double) {
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, count = 0.0
        for (marginStart, marginEnd) in [(0, crossStart), (crossEnd, crossCount)] {
            guard marginEnd > marginStart else { continue }
            let crossStep = max(1, (marginEnd - marginStart) / 6)
            let primaryStep = max(1, primaryCount / 120)
            for primary in stride(from: 0, to: primaryCount, by: primaryStep) {
                for cross in stride(from: marginStart, to: marginEnd, by: crossStep) {
                    let sample: (r: Double, g: Double, b: Double)
                    switch axis {
                    case .verticalLines: sample = color.rgb(x: primary, y: cross)
                    case .horizontalLines: sample = color.rgb(x: cross, y: primary)
                    }
                    let brightness = (sample.r + sample.g + sample.b) / 3
                    let saturation = max(sample.r, sample.g, sample.b) - min(sample.r, sample.g, sample.b)
                    guard brightness > 0.55, saturation < 0.12 else { continue }
                    sumR += sample.r; sumG += sample.g; sumB += sample.b; count += 1
                }
            }
        }
        guard count >= 20 else { return (1, 1, 1) }
        let avgR = sumR / count, avgG = sumG / count, avgB = sumB / count
        let gray = (avgR + avgG + avgB) / 3
        guard gray > 0.1 else { return (1, 1, 1) }
        func clampedGain(_ value: Double) -> Double { min(1.35, max(0.75, value)) }
        return (
            r: clampedGain(gray / max(avgR, 0.05)),
            g: clampedGain(gray / max(avgG, 0.05)),
            b: clampedGain(gray / max(avgB, 0.05))
        )
    }

    private func localContrastProfile(_ values: [Double]) -> [Double] {
        guard values.count > 8 else { return values }
        let smoothed = smooth(values)
        let radius = max(5, values.count / 24)
        return smoothed.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(smoothed.count - 1, index + radius)
            let neighbours = smoothed[lower...upper].enumerated().compactMap { offset, value -> Double? in
                let absolute = lower + offset
                return abs(absolute - index) <= 2 ? nil : value
            }
            let baseline = neighbours.sorted()[neighbours.count / 2]
            return max(0, smoothed[index] - baseline)
        }
    }

    private func anchoredLineSupport(
        color: RGBImage,
        colorAxis: ColorLineAxis,
        primary: Int,
        crossStart: Int,
        crossEnd: Int,
        colorThreshold: Double
    ) -> Int {
        let segmentSize = max(1, (crossEnd - crossStart) / 3)
        return (0..<3).reduce(0) { support, segment in
            let start = crossStart + segment * segmentSize
            let end = segment == 2 ? crossEnd : min(crossEnd, start + segmentSize)
            var colorSum = 0.0
            for cross in start..<end {
                colorSum += colorAxis.pregnancyLineSignal(in: color, primary: primary, cross: cross)
            }
            let count = Double(max(1, end - start))
            return support + (colorSum / count > colorThreshold ? 1 : 0)
        }
    }

    private func strongestPregnancyColorPair(in profile: [Double], axis: ColorLineAxis) -> ColorLinePair? {
        guard profile.count > 40 else { return nil }
        let smoothed = smooth(profile)
        let sorted = smoothed.sorted()
        let background = sorted[sorted.count / 2]
        let scores = smoothed.map { max(0, $0 - background) }
        let noise = max(0.0025, standardDeviation(scores))
        let lower = Int(Double(scores.count) * 0.12)
        let upper = Int(Double(scores.count) * 0.88)
        let threshold = max(0.009, noise * 1.35)
        var peaks = [PeakSignal]()

        for index in lower..<(upper - 1) where index > 0 {
            let value = scores[index]
            if value >= scores[index - 1], value >= scores[index + 1], value > threshold {
                peaks.append(PeakSignal(index: index, value: value))
            }
        }

        peaks.sort { $0.value > $1.value }
        var best: ColorLinePair?
        for left in peaks.prefix(18) {
            for right in peaks.prefix(18) where right.index > left.index {
                let distance = Double(right.index - left.index) / Double(scores.count)
                // Two shoulders of one thick control line or its dye halo must
                // not be accepted as a control/test pair.
                guard (0.060...0.25).contains(distance) else { continue }
                let stronger = max(left.value, right.value)
                let weaker = min(left.value, right.value)
                let balance = weaker / max(stronger, 0.01)
                guard balance >= 0.10, weaker > max(0.009, noise * 1.15) else { continue }

                let midpoint = Double(left.index + right.index) / 2.0 / Double(scores.count)
                guard (0.18...0.78).contains(midpoint) else { continue }
                let centerBonus = max(0, 1.0 - abs(midpoint - 0.48) * 2.0)
                let spacingBonus = max(0, 1.0 - abs(distance - 0.10) * 5.0)
                let orientationBonus = axis == .verticalLines ? 0.04 : 0
                let score = stronger + weaker + balance * 0.10 + centerBonus * 0.04 + spacingBonus * 0.04 + orientationBonus
                let candidate = ColorLinePair(stronger: stronger, weaker: weaker, score: score)
                if best == nil || candidate.score > best!.score {
                    best = candidate
                }
            }
        }
        return best
    }

    private func ovulationColorStripResult(in image: RGBImage, quality: ImageQualityResult) -> LineAnalysisResult? {
        let width = image.width
        let height = image.height
        // OPK photos are no longer treated as a fixed centre crop. Their T/C
        // window moves materially between brands and manual alignments. Scan
        // the complete physical strip, retaining only a small edge margin;
        // dye chroma and the control-anchored pair rule below reject MAX ink,
        // blue/green handles and the strip border.
        let xStart = Int(Double(width) * 0.03)
        let xEnd = Int(Double(width) * 0.97)
        let yStart = Int(Double(height) * 0.18)
        let yEnd = Int(Double(height) * 0.82)
        guard xEnd - xStart > 100, yEnd - yStart > 18 else { return nil }

        let purpleProfile = (xStart..<xEnd).map { x -> Double in
            var sum = 0.0
            for y in yStart..<yEnd {
                sum += image.purpleLineSignal(x: x, y: y)
            }
            return sum / Double(max(1, yEnd - yStart))
        }
        let handleProfile = (xStart..<xEnd).map { x -> Double in
            var sum = 0.0
            for y in yStart..<yEnd {
                sum += image.handleRegionSignal(x: x, y: y)
            }
            return sum / Double(max(1, yEnd - yStart))
        }

        let smoothed = smooth(purpleProfile)
        let sorted = smoothed.sorted()
        let background = sorted[sorted.count / 2]
        let scores = smoothed.map { max(0, $0 - background) }
        let noise = max(0.004, standardDeviation(scores))
        // The guided ovulation viewport enforces MAX/dip on the left and handle
        // on the right, so default to that orientation rather than reacting to
        // a weak/spurious handle-colour signal elsewhere in the strip. Only
        // override it when the handle detector is confidently on the left
        // (its 18% margin requirement) — i.e. the photo is genuinely reversed,
        // such as after a manual Flip on an already-correct photo.
        let detectedHandle = ovulationHandle(from: handleProfile)
        let effectiveHandle: OvulationHandle
        if let detectedHandle, detectedHandle.side == .left {
            effectiveHandle = detectedHandle
        } else {
            let rightBoundary = detectedHandle?.side == .right
                ? detectedHandle!.boundaryIndex
                : Int(Double(scores.count) * 0.74)
            effectiveHandle = OvulationHandle(side: .right, boundaryIndex: rightBoundary)
        }
        #if DEBUG
        if let maxScore = scores.max(), let maxIndex = scores.firstIndex(of: maxScore) {
            Self.debugHook?("ovulationColorStripResult: width=\(width) height=\(height) xStart=\(xStart) xEnd=\(xEnd) scoresCount=\(scores.count) handleSide=\(effectiveHandle.side) boundaryIndex=\(effectiveHandle.boundaryIndex) globalMaxScore=\(maxScore) at index=\(maxIndex)")
        }
        #endif
        guard let pair = strongestOvulationColorPair(in: scores, handle: effectiveHandle, noise: noise) else {
            // Do not make a visible OPK control depend on finding a second,
            // potentially near-invisible test peak. A low result is still a
            // valid reading when only the control is clear. Pick a control
            // from the membrane side nearest the handle; this excludes the
            // MAX/dip end and mirrors the physical T/C ordering.
            if let standaloneControl = standaloneOvulationControl(in: scores, handle: effectiveHandle, noise: noise) {
                let certainty = min(
                    LineAnalysisConstants.maxCertainty,
                    max(LineAnalysisConstants.minCertainty, 54 + Int((standaloneControl.value / max(noise, 0.004)) * 5.5))
                )
                return LineAnalysisResult(
                    resultType: .low,
                    confidencePercentage: certainty,
                    certaintyPercentage: certainty,
                    controlLineDetected: true,
                    testLineDetected: false,
                    testControlRatio: 0,
                    lineStrength: 0,
                    quality: quality,
                    explanation: explanation(for: .low, ratio: 0)
                )
            }
            #if DEBUG
            Self.debugHook?("ovulationColorStripResult: no pair found. noise=\(noise) handleSide=\(effectiveHandle.side) scoresCount=\(scores.count) maxScore=\(scores.max() ?? -1)")
            #endif
            return nil
        }

        let test = effectiveHandle.side == .right ? pair.left.value : pair.right.value
        let control = effectiveHandle.side == .right ? pair.right.value : pair.left.value
        let controlDetected = control > max(0.010, noise * 2.0)
        let testDetected = test > max(0.0045, noise * 1.12)
        #if DEBUG
        Self.debugHook?("ovulationColorStripResult: pair found. test=\(test) control=\(control) noise=\(noise) controlDetected=\(controlDetected) testDetected=\(testDetected) leftIndex=\(pair.left.index) rightIndex=\(pair.right.index)")
        #endif
        guard controlDetected else { return nil }

        let ratio = min(2.0, test / max(control, 0.01))
        let resultType = ovulationResult(ratio: ratio, testDetected: testDetected)
        let spacingBonus = max(0, 1.0 - abs(pair.distanceFraction - 0.10) * 6.0)
        let certainty = min(
            LineAnalysisConstants.maxCertainty,
            max(
                LineAnalysisConstants.minCertainty,
                54 + Int((control / max(noise, 0.004)) * 5.5) + Int((test / max(noise, 0.004)) * 3.0) + Int(spacingBonus * 8)
            )
        )

        return LineAnalysisResult(
            resultType: resultType,
            confidencePercentage: certainty,
            certaintyPercentage: certainty,
            controlLineDetected: true,
            testLineDetected: testDetected,
            testControlRatio: ratio,
            lineStrength: test,
            quality: quality,
            explanation: explanation(for: resultType, ratio: ratio)
        )
    }

    private func makeTwoLineCandidate(lineScores: [Double], segmentScores: [[Double]], noise: Double, axis: LineAxis) -> LineCandidate {
        let mainIndex = strongestPeak(in: lineScores)
        let control = lineScores[mainIndex]
        let second = strongestNearbyPeak(in: lineScores, mainIndex: mainIndex)
        let test = second.value
        let testSupport = supportCount(for: second.index, segmentScores: segmentScores, noise: noise)
        let plausibleSpacing = second.distanceFraction.map { (0.08...0.42).contains($0) } ?? false
        let distanceBonus = second.distanceFraction.map { max(0, 1.0 - abs($0 - 0.24) * 2.5) } ?? 0
        let controlDetected = control > LineAnalysisConstants.controlThreshold || (control > noise * 2.05 && control > 0.035)
        let hintDetected = test > noise * 1.22 && test > 0.024 && test / max(control, 0.01) > 0.055
        let strongerSecondLine = test > 0.045 || test / max(control, 0.01) > 0.16
        let lineLikeSecondPeak = testSupport >= 2
        let testDetected = hintDetected && strongerSecondLine && lineLikeSecondPeak && plausibleSpacing
        let controlSignal = control / max(noise, 0.018)
        let testSignal = test / max(noise, 0.018)
        let orientationBonus = axis == .verticalLines ? 6.0 : 0.0
        let score = (controlDetected ? 58.0 : -60.0) + controlSignal * 14.0 + testSignal * 7.0 + distanceBonus * 10.0 + orientationBonus
        return LineCandidate(
            control: control,
            test: test,
            noise: noise,
            controlDetected: controlDetected,
            testDetected: testDetected,
            testSupport: testSupport,
            plausibleSpacing: plausibleSpacing,
            score: score
        )
    }

    private func strongestPeak(in scores: [Double]) -> Int {
        scores.indices.max { scores[$0] < scores[$1] } ?? 0
    }

    private func localLineContrast(in profile: [Double], at index: Int) -> Double {
        guard !profile.isEmpty else { return 0 }
        let centerRadius = max(2, profile.count / 180)
        let nearOffset = max(centerRadius + 4, profile.count / 55)
        let farOffset = max(nearOffset + 4, profile.count / 22)
        let centerLower = max(0, index - centerRadius)
        let centerUpper = min(profile.count - 1, index + centerRadius)
        // Use the representative peak at the centre of the band. Averaging its
        // pale edges disproportionately weakens a narrow, dark control line.
        let center = profile[centerLower...centerUpper].max() ?? profile[index]

        var surroundings = [Double]()
        let leftLower = max(0, index - farOffset)
        let leftUpper = max(0, index - nearOffset)
        if leftLower <= leftUpper { surroundings.append(contentsOf: profile[leftLower...leftUpper]) }
        let rightLower = min(profile.count - 1, index + nearOffset)
        let rightUpper = min(profile.count - 1, index + farOffset)
        if rightLower <= rightUpper { surroundings.append(contentsOf: profile[rightLower...rightUpper]) }
        guard !surroundings.isEmpty else { return 0 }
        surroundings.sort()
        let localBackground = surroundings[surroundings.count / 2]
        return max(0, center - localBackground)
    }

    private func strongestNearbyPeak(in scores: [Double], mainIndex: Int) -> (value: Double, index: Int?, distanceFraction: Double?) {
        guard scores.count > 8 else { return (0, nil, nil) }
        let minimumDistance = max(5, Int(Double(scores.count) * 0.055))
        let maximumDistance = max(minimumDistance + 1, Int(Double(scores.count) * 0.44))
        let searchRanges = [
            max(0, mainIndex - maximumDistance)..<max(0, mainIndex - minimumDistance),
            min(scores.count, mainIndex + minimumDistance)..<min(scores.count, mainIndex + maximumDistance)
        ]

        var bestValue = 0.0
        var bestIndex: Int?
        var bestDistance: Double?
        for range in searchRanges where !range.isEmpty {
            guard let index = range.max(by: { scores[$0] < scores[$1] }) else { continue }
            let value = scores[index]
            if value > bestValue {
                bestValue = value
                bestIndex = index
                bestDistance = Double(abs(index - mainIndex)) / Double(scores.count)
            }
        }
        return (bestValue, bestIndex, bestDistance)
    }

    private func strongestOrderedPair(in scores: [Double]) -> (left: PeakSignal, right: PeakSignal, distanceFraction: Double?)? {
        guard scores.count > 24 else { return nil }
        let lower = Int(Double(scores.count) * 0.12)
        let upper = Int(Double(scores.count) * 0.88)
        var peaks: [PeakSignal] = []

        for index in lower..<(upper - 1) {
            guard index > 0, index < scores.count - 1 else { continue }
            let value = scores[index]
            if value >= scores[index - 1], value >= scores[index + 1], value > 0.014 {
                peaks.append(PeakSignal(index: index, value: value))
            }
        }

        peaks.sort { $0.value > $1.value }

        var bestPair: (left: PeakSignal, right: PeakSignal, distance: Double, score: Double)?
        for left in peaks {
            for right in peaks where right.index > left.index {
                let distance = Double(right.index - left.index) / Double(scores.count)
                if (0.08...0.42).contains(distance) {
                    let midpoint = Double(left.index + right.index) / 2.0 / Double(scores.count)
                    let centerBonus = max(0, 1.0 - abs(midpoint - 0.46) * 2.0)
                    let pairScore = left.value + right.value + centerBonus * 0.08
                    if bestPair == nil || pairScore > bestPair!.score {
                        bestPair = (left, right, distance, pairScore)
                    }
                }
            }
        }

        if let bestPair {
            return (bestPair.left, bestPair.right, bestPair.distance)
        }

        guard peaks.count >= 2 else { return nil }
        let sortedByPosition = peaks.prefix(2).sorted { $0.index < $1.index }
        let distance = Double(sortedByPosition[1].index - sortedByPosition[0].index) / Double(scores.count)
        return (sortedByPosition[0], sortedByPosition[1], distance)
    }

    private func ovulationHandle(from handleProfile: [Double]) -> OvulationHandle? {
        guard handleProfile.count > 24 else { return nil }
        let smoothed = smooth(handleProfile)
        let sideWindow = max(1, smoothed.count / 3)
        let leftRange = 0..<sideWindow
        let rightRange = (smoothed.count - sideWindow)..<smoothed.count
        let left = leftRange.map { smoothed[$0] }.reduce(0, +) / Double(max(1, leftRange.count))
        let right = rightRange.map { smoothed[$0] }.reduce(0, +) / Double(max(1, rightRange.count))
        let side: LineSide
        if right > max(0.01, left * 1.18) {
            side = .right
        } else if left > max(0.01, right * 1.18) {
            side = .left
        } else {
            side = .right
        }

        let sorted = smoothed.sorted()
        let median = sorted[sorted.count / 2]
        let peak = smoothed.max() ?? median
        // A real photo's membrane-to-handle transition is a gradual colour
        // ramp (compression, antialiasing, an actual bevel), not a hard
        // step. A low threshold like the previous 0.38 fraction triggers
        // partway through that ramp, placing the boundary too far into the
        // membrane and risking exclusion of a real control line positioned
        // near the handle. Require signal close to the genuine peak
        // (saturated handle colour) so a gradient's intermediate values
        // don't count as "handle" yet.
        let threshold = median + max(0.018, (peak - median) * 0.70)
        let minRun = max(10, smoothed.count / 24)
        let fallbackBoundary = side == .right ? Int(Double(smoothed.count) * 0.74) : Int(Double(smoothed.count) * 0.26)
        var boundary: Int?

        if side == .right {
            var runStart: Int?
            var runLength = 0
            for index in stride(from: smoothed.count - 1, through: 0, by: -1) {
                if smoothed[index] > threshold {
                    runStart = index
                    runLength += 1
                } else if runLength >= minRun {
                    boundary = runStart
                    break
                } else {
                    runStart = nil
                    runLength = 0
                }
            }
            if boundary == nil, runLength >= minRun {
                boundary = runStart
            }
        } else {
            var runEnd: Int?
            var runLength = 0
            for index in 0..<smoothed.count {
                if smoothed[index] > threshold {
                    runEnd = index
                    runLength += 1
                } else if runLength >= minRun {
                    boundary = runEnd
                    break
                } else {
                    runEnd = nil
                    runLength = 0
                }
            }
            if boundary == nil, runLength >= minRun {
                boundary = runEnd
            }
        }

        return OvulationHandle(side: side, boundaryIndex: boundary ?? fallbackBoundary)
    }

    private func strongestOvulationColorPair(in scores: [Double], handle: OvulationHandle, noise: Double) -> (left: PeakSignal, right: PeakSignal, distanceFraction: Double)? {
        guard scores.count > 32 else { return nil }
        // The membrane-to-handle boundary is a sharp, high-contrast colour
        // transition (frequently a saturated green or purple plastic handle).
        // JPEG compression ringing and antialiasing at that exact edge can
        // otherwise leak a false dye-like colour signal right where a real
        // control line would plausibly be, even though purpleLineSignal
        // already rejects the handle's own interior colour. Keep a wider
        // buffer between the search zone and the detected boundary so that
        // edge artifact is excluded outright rather than relying on the
        // per-pixel colour rejection alone.
        let handleMargin = max(5, Int(Double(scores.count) * 0.018))
        let lower: Int
        let upper: Int
        let expectedMidpoint: Double

        // Search the complete non-handle membrane, not a fixed-width slice
        // anchored to the handle boundary. Real photos put meaningful blank
        // membrane between the T/C pair and the handle, and its extent
        // varies a lot with strip alignment - a narrow fixed-width window
        // that starts counting inward from the boundary routinely left the
        // true pair (often the whole pair) outside the search range
        // entirely. Confirmed on real photos during calibration
        // (2026-08-28): the one peak found sat right at the old window's
        // inner edge in every case, with the real second line further out,
        // beyond that edge - e.g. 0100.jpg's two clearly visible lines sit
        // at roughly 30-45% of the strip while the old window only covered
        // 56-92%.
        if handle.side == .right {
            upper = max(0, min(scores.count - 1, handle.boundaryIndex - handleMargin))
            lower = Int(Double(scores.count) * 0.08)
            expectedMidpoint = max(Double(lower) / Double(scores.count), Double(handle.boundaryIndex) / Double(scores.count) - 0.12)
        } else {
            lower = min(scores.count - 1, max(0, handle.boundaryIndex + handleMargin))
            upper = Int(Double(scores.count) * 0.92)
            expectedMidpoint = min(Double(upper) / Double(scores.count), Double(handle.boundaryIndex) / Double(scores.count) + 0.12)
        }
        #if DEBUG
        Self.debugHook?("strongestOvulationColorPair: window lower=\(lower) upper=\(upper) width=\(upper - lower) scoresCount=\(scores.count) handleSide=\(handle.side) boundaryIndex=\(handle.boundaryIndex) expectedMidpoint=\(expectedMidpoint) noise=\(noise)")
        #endif
        guard upper - lower > 24 else {
            #if DEBUG
            Self.debugHook?("strongestOvulationColorPair: REJECT window too narrow (\(upper - lower) <= 24)")
            #endif
            return nil
        }

        var peaks = [PeakSignal]()
        // A genuinely faint test line can register well under the old flat
        // 0.0035 floor - that floor was rejecting real candidates before the
        // more principled, noise-relative testDetected gate downstream
        // (max(0.0045, noise*1.12)) ever got a chance to evaluate them. This
        // stage only proposes candidates; let that later gate make the real
        // accept/reject call instead of a redundant, disconnected minimum here.
        let peakFloor = max(0.0008, noise * 0.35)

        for index in lower..<(upper - 1) {
            guard index > 0, index < scores.count - 1 else { continue }
            let value = scores[index]
            if value >= scores[index - 1], value >= scores[index + 1], value > peakFloor {
                peaks.append(PeakSignal(index: index, value: value))
            }
        }

        #if DEBUG
        let topPeaksForLog = peaks.sorted { $0.value > $1.value }.prefix(8)
            .map { "(\($0.index),\(String(format: "%.5f", $0.value)))" }.joined(separator: " ")
        Self.debugHook?("strongestOvulationColorPair: peakFloor=\(peakFloor) peaksFound=\(peaks.count) topPeaks=\(topPeaksForLog)")
        #endif
        guard peaks.count >= 2 else {
            #if DEBUG
            Self.debugHook?("strongestOvulationColorPair: REJECT fewer than 2 peaks (\(peaks.count))")
            #endif
            return nil
        }

        var bestPair: (left: PeakSignal, right: PeakSignal, distance: Double, score: Double)?
        var closestRejectedDistance: Double?
        for left in peaks {
            for right in peaks where right.index > left.index {
                let distance = Double(right.index - left.index) / Double(scores.count)
                guard (0.045...0.22).contains(distance) else {
                    if closestRejectedDistance == nil || abs(distance - 0.13) < abs(closestRejectedDistance! - 0.13) {
                        closestRejectedDistance = distance
                    }
                    continue
                }
                let midpoint = Double(left.index + right.index) / 2.0 / Double(scores.count)
                let midpointBonus = max(0, 1.0 - abs(midpoint - expectedMidpoint) * 4.0)
                let control = handle.side == .right ? right.value : left.value
                let test = handle.side == .right ? left.value : right.value
                let balancePenalty = min(0.018, max(0, test - control) * 0.08)
                let pairScore = left.value + right.value + midpointBonus * 0.035 - balancePenalty
                if bestPair == nil || pairScore > bestPair!.score {
                    bestPair = (left, right, distance, pairScore)
                }
            }
        }

        guard let bestPair else {
            #if DEBUG
            Self.debugHook?("strongestOvulationColorPair: REJECT no pair within spacing 0.045...0.22; closestRejectedDistance=\(closestRejectedDistance.map { String(format: "%.4f", $0) } ?? "n/a")")
            #endif
            return nil
        }
        return (bestPair.left, bestPair.right, bestPair.distance)
    }

    private func standaloneOvulationControl(in scores: [Double], handle: OvulationHandle, noise: Double) -> PeakSignal? {
        guard scores.count > 32 else { return nil }
        let margin = max(5, Int(Double(scores.count) * 0.018))
        let lower: Int
        let upper: Int
        if handle.side == .right {
            lower = Int(Double(scores.count) * 0.08)
            upper = max(lower, min(scores.count - 1, handle.boundaryIndex - margin))
        } else {
            lower = min(scores.count - 1, max(0, handle.boundaryIndex + margin))
            upper = Int(Double(scores.count) * 0.92)
        }
        guard upper - lower > 12 else { return nil }
        let floor = max(0.010, noise * 2.0)
        let candidates = (lower...upper).compactMap { index -> PeakSignal? in
            guard index > 0, index < scores.count - 1,
                  scores[index] >= scores[index - 1], scores[index] >= scores[index + 1],
                  scores[index] > floor else { return nil }
            return PeakSignal(index: index, value: scores[index])
        }
        // The guide fixes C in the right half after the user aligns or flips
        // the strip. Reject candidates on the T/MAX side even if they are
        // darker than the real control.
        let rightHalfCandidates = candidates.filter { $0.index >= scores.count / 2 }
        return rightHalfCandidates.max { $0.index < $1.index }
    }

    private func supportCount(for index: Int?, segmentScores: [[Double]], noise: Double) -> Int {
        guard let index else { return 0 }
        return segmentScores.reduce(0) { count, scores in
            guard !scores.isEmpty else { return count }
            let lower = max(0, index - 2)
            let upper = min(scores.count - 1, index + 2)
            let localPeak = scores[lower...upper].max() ?? 0
            return localPeak > max(0.018, noise * 1.05) ? count + 1 : count
        }
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(values.count, 1))
        return sqrt(variance)
    }

    private func conservativeCertainty(control: Double, test: Double, noise: Double, quality: ImageQualityResult, controlDetected: Bool) -> Int {
        guard controlDetected else { return 45 }
        let effectiveNoise = max(noise, 0.02)
        let controlSignal = min(4.0, control / effectiveNoise)
        let testSignal = min(3.0, test / effectiveNoise)
        var score = 46 + Int(controlSignal * 9) + Int(testSignal * 3)
        if quality.status != .good { score -= 18 }
        if (0.8...1.5).contains(test / effectiveNoise) { score -= 10 }
        return min(LineAnalysisConstants.maxCertainty, max(LineAnalysisConstants.minCertainty, score))
    }

    private func explanation(for result: ScanResultType, ratio: Double) -> String {
        switch result {
        case .appearsPositive, .faintLineDetected: "A line appears to be detected in the test region. Follow your test instructions and consider testing again in a few days."
        case .appearsNegative: "No test line was detected in this image. If you tested early, consider retesting in a few days."
        case .low: "The image appears to show a control line with no strong LH test line yet. Keep testing during your expected fertile window."
        case .rising: "The test line appears to be getting darker, but is still lighter than the control line. Consider testing again later or tomorrow."
        case .high: "The test line appears close to the control line. This can mean LH is rising, so keep testing consistently."
        case .peak: "The test line appears similar to the control line. This image is consistent with an LH surge on a home ovulation test."
        case .invalid: "The control line was not detected. This test may be invalid or the photo may be unclear."
        default: "The line reading is unclear from this image."
        }
    }

    private func unclear(quality: ImageQualityResult) -> LineAnalysisResult {
        LineAnalysisResult(resultType: .unclear, confidencePercentage: 40, certaintyPercentage: 40, controlLineDetected: false, testLineDetected: false, testControlRatio: 0, lineStrength: 0, quality: quality, explanation: "Line analysis could not process this image.")
    }
}

private struct GrayscaleImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func luminance(x: Int, y: Int) -> Double {
        Double(pixels[y * width + x]) / 255.0
    }
}

private struct RGBImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let offset = (y * width + x) * 4
        return (
            Double(pixels[offset]) / 255.0,
            Double(pixels[offset + 1]) / 255.0,
            Double(pixels[offset + 2]) / 255.0
        )
    }

    func purpleLineSignal(x: Int, y: Int) -> Double {
        let color = rgb(x: x, y: y)
        // Reject green-dominant pixels outright. Test-cassette handles are
        // commonly a saturated green plastic; the arithmetic below already
        // scores pure green as ~0, but a categorical veto is more robust
        // against a compression-blended or antialiased boundary pixel
        // between the membrane and the handle scoring a stray positive value
        // that the raw chroma formula wasn't explicitly designed to reject.
        if color.g > color.r + 0.04 && color.g > color.b + 0.04 {
            return 0
        }
        // Measure coloured dye relative to the local green channel. Previous
        // multipliers gave neutral grey/black print a positive score, allowing
        // MAX text or a membrane seam to be paired with T as a false control.
        let purpleChroma = min(color.r, color.b) - color.g
        let redChroma = color.r - max(color.g, color.b * 0.92)
        return max(0, purpleChroma) * 0.72 + max(0, redChroma) * 0.28
    }

    func handleRegionSignal(x: Int, y: Int) -> Double {
        let color = rgb(x: x, y: y)
        let high = max(color.r, color.g, color.b)
        let low = min(color.r, color.g, color.b)
        let brightness = (color.r + color.g + color.b) / 3.0
        return max(0, high - low) * max(0, 1.08 - brightness)
    }

    func pregnancyLineSignal(x: Int, y: Int, whiteBalance: (r: Double, g: Double, b: Double) = (1, 1, 1)) -> Double {
        let raw = rgb(x: x, y: y)
        let color = (
            r: min(1.3, raw.r * whiteBalance.r),
            g: min(1.3, raw.g * whiteBalance.g),
            b: min(1.3, raw.b * whiteBalance.b)
        )
        let redChroma = color.r - max(color.g, color.b) * 0.82
        let purpleChroma = min(color.r, color.b) - color.g * 0.88
        let blueChroma = color.b - max(color.r, color.g) * 0.82
        let brightness = (color.r + color.g + color.b) / 3
        // Blue-dye controls are dark enough to create a local line contrast.
        // A pale blue membrane is not dye; without this brightness weighting
        // its broad colour field and window edges can be paired as a false
        // pregnancy line after enhancement.
        let darkBlueDye = max(0, blueChroma) * max(0, 0.88 - brightness)
        return max(0, redChroma) * 0.76
            + max(0, purpleChroma) * 0.34
            + darkBlueDye * 1.25
    }
}

private enum ColorLineAxis {
    case verticalLines
    case horizontalLines

    func primaryCount(in image: RGBImage) -> Int {
        self == .verticalLines ? image.width : image.height
    }

    func crossCount(in image: RGBImage) -> Int {
        self == .verticalLines ? image.height : image.width
    }

    func pregnancyLineSignal(
        in image: RGBImage,
        primary: Int,
        cross: Int,
        whiteBalance: (r: Double, g: Double, b: Double) = (1, 1, 1)
    ) -> Double {
        switch self {
        case .verticalLines:
            image.pregnancyLineSignal(x: primary, y: cross, whiteBalance: whiteBalance)
        case .horizontalLines:
            image.pregnancyLineSignal(x: cross, y: primary, whiteBalance: whiteBalance)
        }
    }
}

private struct ColorLinePair {
    var stronger: Double
    var weaker: Double
    var score: Double
}

private struct AnchoredPregnancyEvidence {
    var controlStrength: Double
    var testStrength: Double
    var ratio: Double
    var support: Int
    var testDetected: Bool
    var weakMarkDetected: Bool
    var ambiguousGrayMarkDetected: Bool
    var score: Double
}

private enum LineSide {
    case left, right
}

private struct OvulationHandle {
    var side: LineSide
    var boundaryIndex: Int
}

private struct LineProfile {
    var values: [Double]
    var segmentValues: [[Double]]
}

private enum LineAxis {
    case verticalLines
    case horizontalLines

    func primaryCount(in image: GrayscaleImage) -> Int {
        switch self {
        case .verticalLines: image.width
        case .horizontalLines: image.height
        }
    }

    func crossCount(in image: GrayscaleImage) -> Int {
        switch self {
        case .verticalLines: image.height
        case .horizontalLines: image.width
        }
    }

    func luminance(in image: GrayscaleImage, primary: Int, cross: Int) -> Double {
        switch self {
        case .verticalLines: image.luminance(x: primary, y: cross)
        case .horizontalLines: image.luminance(x: cross, y: primary)
        }
    }
}

private struct LineCandidate {
    var control: Double
    var test: Double
    var noise: Double
    var controlDetected: Bool
    var testDetected: Bool
    var testSupport: Int
    var plausibleSpacing: Bool
    var score: Double
}

private struct CrossCandidate {
    var horizontal: Double
    var vertical: Double
    var score: Double
    var isPositive: Bool
}

private struct PeakSignal {
    var index: Int
    var value: Double
}
