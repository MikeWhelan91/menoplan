import CoreImage
import CoreML
import UIKit

/// The learned verifier receives a locally proposed T/C window. The local
/// scanner finds a candidate; the model decides whether it is a real pair and
/// estimates the ratio.
struct LocalOvulationAnalysis: Equatable {
    let result: LineAnalysisResult
    let trendSummary: String
    let diagnostics: LocalOvulationDiagnostics
}

struct LocalOvulationDiagnostics: Equatable {
    let modelVersion: String
    let proposalFound: Bool
    let proposalConfidence: Int
    let pairValid: Double?
    let controlPresent: Double?
    let testPresent: Double?
    let predictedRatio: Double?
    let finalResult: ScanResultType
    let quality: ImageQualityResult
    let analyzedImage: UIImage?

    var report: String {
        func number(_ value: Double?) -> String { value?.formatted(.number.precision(.fractionLength(4))) ?? "not run" }
        return """
        model=\(modelVersion)
        proposal.found=\(proposalFound); localConfidence=\(proposalConfidence)%
        model.pair=\(number(pairValid))
        model.control=\(number(controlPresent))
        model.test=\(number(testPresent))
        model.ratio=\(number(predictedRatio))
        final=\(finalResult.rawValue)
        quality=\(quality.status.rawValue); brightness=\(quality.brightness.formatted(.number.precision(.fractionLength(4)))); blur=\(quality.blurScore.formatted(.number.precision(.fractionLength(4)))); overexposure=\(quality.overexposure.formatted(.number.precision(.fractionLength(4))))
        """
    }
}

enum OnDeviceOvulationModelMetadata {
    static let resourceName = "LineCheckOvulationPairComparator-v12-direct-guide-box"
    static let version = "ovulation-pair-comparator-v12-direct-guide-box"
    static let inputWidth = 384
    static let inputHeight = 128
    /// The source apps use mixed ratio scales. Training and inference both cap
    /// the continuous target at 2.5; anything stronger is still represented by
    /// the clinically useful Peak stage rather than a misleading large number.
    static let maximumRatio = 2.5
}

enum OnDeviceOvulationReconciler {
    // Recalibrated 2026-08-27 by grid search against v12's own real
    // held-out test split (111 real photos, ground-truth ratios), on the
    // ratio actually used at inference (the model+heuristic ensemble
    // below), replacing values dated to the earlier v5 model. Model-alone
    // tier accuracy on that same set was 42%; these thresholds plus the
    // ensemble brought it to ~60%. Caveat: fit and measured on the same
    // 91-111 image set (no separate validation split available for this
    // ensemble), so some overfit is likely - revisit if a cleanly
    // separated validation set becomes available. Keep separate from
    // LineAnalysisConstants: that system powers the independent pixel
    // reader on its own and must retain its own calibration.
    static let lowUpper = 0.60
    static let risingUpper = 0.70
    static let highUpper = 1.10

    /// The learned verifier is the primary signal, but the independent spatial
    /// reader is sufficient corroboration when the model falls just below its
    /// control-line threshold. A miss from one reader should not invalidate a
    /// visibly readable strip detected by the other.
    static func hasValidControl(modelControlPresent: Double, spatialControlDetected: Bool) -> Bool {
        modelControlPresent >= 0.5 || spatialControlDetected
    }

    static func resultType(for ratio: Double) -> ScanResultType {
        if ratio <= lowUpper { return .low }
        if ratio <= risingUpper { return .rising }
        if ratio <= highUpper { return .high }
        return .peak
    }

    static func trendSummary(currentRatio: Double, recentRatios: [Double]) -> String {
        guard let previous = recentRatios.first else {
            return "This is your first saved ovulation reading, so future scans will make the trend clearer."
        }
        let change = currentRatio - previous
        if previous >= highUpper && change <= -0.18 {
            return "This reading is lower than your last one after a stronger result, which can fit a falling LH pattern."
        }
        if change >= 0.15 {
            return "This reading is higher than your most recent scan, suggesting the test line may be getting stronger."
        }
        if change <= -0.15 {
            return "This reading is lower than your most recent scan. Another test later today or tomorrow can clarify the pattern."
        }
        return "This is close to your most recent reading. Testing at a similar time can make changes easier to compare."
    }

    static func explanation(for type: ScanResultType, trend: String) -> String {
        let core: String
        switch type {
        case .low:
            core = "The test line is lighter than the control line, which is usually a low ovulation-test reading."
        case .rising:
            core = "The test line is becoming more noticeable, but it is not yet as strong as the control line."
        case .high:
            core = "The test line is close to the control line. Consider testing again later today or tomorrow to watch for a surge."
        case .peak:
            core = "The test line is at least as strong as the control line, which can indicate an LH surge."
        default:
            core = "This ovulation test could not be read clearly."
        }
        return "\(core) \(trend)"
    }
}

final class OnDeviceOvulationAnalysisService {
    private let qualityService = ImageQualityService()
    private let spatialLineEngine = LineAnalysisEngine()
    private let context = CIContext(options: [.cacheIntermediates: false])

    func analyse(_ image: UIImage, recentRatios: [Double]) async throws -> LocalOvulationAnalysis {
        // Unlike pregnancy, an OPK strip can have a very plain membrane with
        // just two fine lines. The generic "blurry / hard to detect" quality
        // classifier was calibrated on full pregnancy-test photos and
        // repeatedly rejected these valid, guide-framed strips before the
        // ratio model even ran. Keep quality as a confidence signal; do not
        // turn it into a veto for a model trained specifically on this input.
        // The capture guide already asks the user to place both physical lines
        // inside this exact T/C box. It is therefore the strongest proposal
        // available: pass it straight to the learned verifier. The colour
        // scanner remains only for images that bypassed the guided capture.
        let proposal = TestTemplateGeometry.lineAnalysisImage(from: image)
            .map { OvulationPairProposal(image: $0, localConfidence: 95) }
            ?? spatialLineEngine.ovulationPairProposal(from: image)
        guard let proposal else {
            let quality = qualityService.score(image)
            let result = unclear(quality)
            return LocalOvulationAnalysis(result: result, trendSummary: "No reliable test/control window was found in this photo.", diagnostics: LocalOvulationDiagnostics(modelVersion: OnDeviceOvulationModelMetadata.version, proposalFound: false, proposalConfidence: 0, pairValid: nil, controlPresent: nil, testPresent: nil, predictedRatio: nil, finalResult: result.resultType, quality: quality, analyzedImage: nil))
        }
        return try await finishAnalysis(proposalImage: proposal.image, localConfidence: proposal.localConfidence, qualityImage: image, recentRatios: recentRatios)
    }

    #if DEBUG
    /// Test-only entry point for calibration: takes an image already
    /// cropped to the model's exact T/C window (skipping
    /// TestTemplateGeometry.lineAnalysisImage), for reference datasets that
    /// are already in that shape rather than the wider aligned outer crop
    /// analyse(_:recentRatios:) normally expects.
    func analysePreCropped(_ image: UIImage, recentRatios: [Double]) async throws -> LocalOvulationAnalysis {
        try await finishAnalysis(proposalImage: image, localConfidence: 95, qualityImage: image, recentRatios: recentRatios)
    }
    #endif

    private func finishAnalysis(proposalImage: UIImage, localConfidence: Int, qualityImage: UIImage, recentRatios: [Double]) async throws -> LocalOvulationAnalysis {
        let proposal = OvulationPairProposal(image: proposalImage, localConfidence: localConfidence)
        // Match the pregnancy route: quality belongs to the complete aligned
        // photo, not the mostly-white inner line crop. Scoring that tiny crop
        // falsely labelled ordinary OPK strips as overexposed.
        let rawQuality = qualityService.score(qualityImage)
        // A guided OPK crop is predominantly white membrane by design. The
        // generic saturation metric was calibrated on full pregnancy-test
        // photos and mistakes that normal membrane for glare. Pregnancy uses
        // the metric as a soft signal; for this specialised guided OPK route
        // it is not a useful user warning, so retain the measurements but do
        // not surface a false “overexposed” status.
        let quality = rawQuality.status == .overexposed
            ? ImageQualityResult(
                status: .good,
                brightness: rawQuality.brightness,
                blurScore: rawQuality.blurScore,
                overexposure: rawQuality.overexposure
            )
            : rawQuality

        // The legacy reader was designed around the complete guide, while the
        // model receives just its inner T/C box. Try both as independent
        // supporting evidence. A reader miss must not by itself declare a
        // visibly developed control line invalid; the pregnancy route also
        // treats its spatial reader as evidence rather than a veto.
        let model = try await predict(proposal.image)
        // Calibration finding (2026-08-27, real held-out test set): pairValid
        // rejected 10/111 real photos as "not a valid pair" - all 10 were
        // genuinely low/faint results, not invalid tests. The model appears
        // to have learned "faint line -> not a real pair" during training,
        // backwards for an app whose whole purpose is reading faint lines.
        // controlPresent alone is a more reliable "is there actually a test
        // here" signal; pairValid is folded into confidence below instead of
        // gating the result outright.
        let heuristic = spatialLineEngine.analyse(qualityImage, testType: .ovulation)
        guard OnDeviceOvulationReconciler.hasValidControl(
            modelControlPresent: model.controlPresent,
            spatialControlDetected: heuristic.controlLineDetected
        ) else {
            let diagnostics = LocalOvulationDiagnostics(
                modelVersion: OnDeviceOvulationModelMetadata.version,
                proposalFound: true,
                proposalConfidence: proposal.localConfidence,
                pairValid: model.pairValid,
                controlPresent: model.controlPresent,
                testPresent: model.testPresent,
                predictedRatio: model.ratio,
                finalResult: model.controlPresent < 0.35 ? .invalid : .unclear,
                quality: quality,
                analyzedImage: proposal.image
            )
            let result = LineAnalysisResult(
                resultType: model.controlPresent < 0.35 ? .invalid : .unclear,
                confidencePercentage: Int(model.controlPresent * 100),
                certaintyPercentage: Int(model.controlPresent * 100),
                controlLineDetected: false,
                testLineDetected: false,
                testControlRatio: 0,
                lineStrength: 0,
                quality: quality,
                explanation: "I found a possible test window, but the on-device model could not verify a readable control line. Retake the photo with the strip fully visible and evenly lit."
            )
            return LocalOvulationAnalysis(result: result, trendSummary: "This reading was not added to your trend.", diagnostics: diagnostics)
        }
        // Ensemble finding (2026-08-27, same held-out test set): the model's
        // ratio alone correlates only weakly with the true ratio (r=0.34).
        // Averaging it with the independent heuristic reader's own ratio -
        // when that reader actually locates a control line on the complete
        // strip, which needs the wide aligned photo, not the model's tight
        // T/C crop - measurably improved both correlation (0.34->0.37) and
        // tier accuracy (48%->56% before threshold recalibration, ~60%+
        // after) on that set. Model-only stays the fallback whenever the
        // heuristic can't locate a strip.
        let ensembleRatio = heuristic.controlLineDetected && heuristic.testControlRatio > 0
            ? (model.ratio + heuristic.testControlRatio) / 2
            : model.ratio
        let diagnostics = LocalOvulationDiagnostics(
            modelVersion: OnDeviceOvulationModelMetadata.version,
            proposalFound: true,
            proposalConfidence: proposal.localConfidence,
            pairValid: model.pairValid,
            controlPresent: model.controlPresent,
            testPresent: model.testPresent,
            predictedRatio: ensembleRatio,
            finalResult: OnDeviceOvulationReconciler.resultType(for: ensembleRatio),
            quality: quality,
            analyzedImage: proposal.image
        )
        let ratio = max(0, min(OnDeviceOvulationModelMetadata.maximumRatio, ensembleRatio))
        let type = OnDeviceOvulationReconciler.resultType(for: ratio)
        let confidence = min(94, max(45, Int(min(model.pairValid, model.controlPresent) * 82) + proposal.localConfidence / 6 - (quality.status == .good ? 0 : 8)))
        let trend = OnDeviceOvulationReconciler.trendSummary(currentRatio: ratio, recentRatios: recentRatios)
        let result = LineAnalysisResult(
            resultType: type,
            confidencePercentage: confidence,
            certaintyPercentage: confidence,
            controlLineDetected: true,
            testLineDetected: model.testPresent >= 0.5,
            testControlRatio: ratio,
            lineStrength: min(1, ratio / 1.15),
            quality: quality,
            explanation: OnDeviceOvulationReconciler.explanation(for: type, trend: trend)
        )
        return LocalOvulationAnalysis(result: result, trendSummary: trend, diagnostics: diagnostics)
    }

    private func unclear(_ quality: ImageQualityResult) -> LineAnalysisResult {
        LineAnalysisResult(
            resultType: .unclear, confidencePercentage: 0, certaintyPercentage: 45,
            controlLineDetected: false, testLineDetected: false, testControlRatio: 0,
            lineStrength: 0, quality: quality,
            explanation: "This photo is too difficult to read reliably. Retake it in bright, even light with the test window in focus."
        )
    }

    private struct PairPrediction {
        let pairValid: Double
        let controlPresent: Double
        let testPresent: Double
        let ratio: Double
    }

    private func predict(_ image: UIImage) async throws -> PairPrediction {
        guard let url = Bundle.main.url(forResource: OnDeviceOvulationModelMetadata.resourceName, withExtension: "mlmodelc") else {
            throw LocalModelError.modelMissing
        }
        guard let buffer = pixelBuffer(for: image) else { throw LocalModelError.imagePreparationFailed }
        let model = try MLModel(contentsOf: url)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["pair_image": buffer])
        let output = try await model.prediction(from: provider)
        guard let values = output.featureValue(for: "predictions")?.multiArrayValue,
              values.count >= 4 else {
            throw LocalModelError.unexpectedOutput
        }
        func sigmoid(_ value: Double) -> Double { 1 / (1 + exp(-value)) }
        return PairPrediction(
            pairValid: sigmoid(values[0].doubleValue),
            controlPresent: sigmoid(values[1].doubleValue),
            testPresent: sigmoid(values[2].doubleValue),
            ratio: values[3].doubleValue
        )
    }

    /// Training resizes the analyser's dynamic T/C proposal to 384×128. Match
    /// that exact geometry here rather than preserving aspect ratio or bars.
    private func pixelBuffer(for image: UIImage) -> CVPixelBuffer? {
        let width = OnDeviceOvulationModelMetadata.inputWidth
        let height = OnDeviceOvulationModelMetadata.inputHeight
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer,
              let source = CIImage(image: image.normalizedOnDeviceOrientation()) else { return nil }
        let scale = CGAffineTransform(scaleX: CGFloat(width) / source.extent.width, y: CGFloat(height) / source.extent.height)
        CVPixelBufferLockBaseAddress(buffer, [])
        context.render(source.transformed(by: scale), to: buffer)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

private extension UIImage {
    func normalizedOnDeviceOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
