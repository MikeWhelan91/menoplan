import CoreImage
import CoreML
import UIKit

struct LocalModelPrediction: Sendable {
    let imageUsable: Double
    let controlLinePresent: Double
    let testLinePresent: Double
    let testLineStrength: Double

    static func mean(_ first: Self, _ second: Self) -> Self {
        Self(
            imageUsable: (first.imageUsable + second.imageUsable) / 2,
            controlLinePresent: (first.controlLinePresent + second.controlLinePresent) / 2,
            testLinePresent: (first.testLinePresent + second.testLinePresent) / 2,
            testLineStrength: (first.testLineStrength + second.testLineStrength) / 2
        )
    }

    var pregnancyResult: String {
        if imageUsable < 0.5 { return "Unclear" }
        if controlLinePresent < 0.5 { return "Invalid" }
        // Pregnancy tests are safety-biased: a weak detected line is positive.
        // This threshold is intentionally lower than the generic classifier cutoff.
        if testLinePresent < LocalPregnancyModelMetadata.testLineThreshold { return "Appears negative" }
        return testLineStrength >= 0.48 ? "Positive" : "Positive — faint line detected"
    }
}

enum LocalPregnancyModelMetadata {
    static let resourceName = "LineCheckVisionSiamese-v9-reddit-150"
    // Siamese/reference-comparison architecture, ConvNeXt-Tiny backbone,
    // continued from v7 using the expanded 753-image manifest, including the
    // newly labelled Reddit batch of 150 images. Same single-image in / 4-value out contract as the
    // ConvNeXt export (LocalModelService is unchanged) - the reference
    // prototype is baked into the model as a constant.
    //
    // NOT YET RECALIBRATED: OnDevicePregnancyReconciler's thresholds below
    // (testLineThreshold, highConfidenceTestLineThreshold, and the 0.18
    // faint/positive split in OnDevicePregnancyAnalysisService) were tuned
    // against v9/v24's specific probability calibration, with real production
    // incidents behind several of them. A quick distribution check against
    // the locked test set (2026-08-23) found this model's raw scores aren't
    // wildly incompatible with those same thresholds, but that's a sanity
    // check, not a recalibration - do that properly before relying on this
    // as the sole decision-maker (i.e. before the cloud API is actually
    // removed), not by guessing new numbers from one snapshot.
    static let version = "pregnancy-siamese-v9-reddit-150-faint-safety"
    static let testLineThreshold = 0.50
    // Lower bound for the below-threshold rescue in OnDevicePregnancyReconciler
    // (2026-08-23) - a score below this is left as a clean negative regardless
    // of spatial evidence; between this and testLineThreshold, independent
    // spatial/inversion support can still promote it to faint. Set below the
    // real 0.4381 near-miss case that motivated this, and above the bulk of
    // the earlier model's confidently-negative locked-test scores (mostly 0.2-0.35) so a
    // clearly-negative photo isn't rescued just because spatial evidence
    // happens to coincidentally agree. Not yet validated against a live
    // incident the way testLineThreshold's siblings were - watch for both
    // directions (still-missed faints, newly-flipped genuine negatives).
    static let nearMissModelProbability = 0.35
    static let highConfidenceTestLineThreshold = 0.80
    static let possibleSpatialLineStrength = 0.05
    static let maximumStrengthOnlyModelProbability = 0.72
    static let minimumHighModelPartialDyeRatio = 0.01
    static let inversionRevealedLineStrength = 0.15
    static let inversionRevealedLineGain = 0.065
    static let moderateSpatialLineStrength = 0.05
    static let moderateSpatialLineRatio = 0.03
    static let edgeSpatialLineStrength = 0.048
    static let edgeSpatialLineRatio = 0.02
}

enum LocalModelError: LocalizedError {
    case modelMissing
    case imagePreparationFailed
    case unexpectedOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The on-device MenoPlan model is not bundled in this build."
        case .imagePreparationFailed:
            "The selected image could not be prepared for the local model."
        case .unexpectedOutput:
            "The local model returned an unexpected output."
        }
    }
}

final class LocalModelService {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func predict(image: UIImage) async throws -> LocalModelPrediction {
        guard let modelURL = Bundle.main.url(forResource: LocalPregnancyModelMetadata.resourceName, withExtension: "mlmodelc") else {
            throw LocalModelError.modelMissing
        }
        let model = try MLModel(contentsOf: modelURL)
        guard let buffer = pixelBuffer(for: image, size: 384) else {
            throw LocalModelError.imagePreparationFailed
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["test_image": buffer])
        let result = try await model.prediction(from: provider)
        guard let values = result.featureValue(for: "predictions")?.multiArrayValue,
              values.count >= 4 else {
            throw LocalModelError.unexpectedOutput
        }
        return LocalModelPrediction(
            imageUsable: values[0].doubleValue,
            controlLinePresent: values[1].doubleValue,
            testLinePresent: values[2].doubleValue,
            testLineStrength: values[3].doubleValue
        )
    }

    private func pixelBuffer(for image: UIImage, size: Int) -> CVPixelBuffer? {
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            size,
            size,
            kCVPixelFormatType_32BGRA,
            attributes,
            &buffer
        ) == kCVReturnSuccess, let buffer else { return nil }

        let oriented = image.normalizedOrientation()
        let sourceSize = oriented.size
        let scale = min(CGFloat(size) / sourceSize.width, CGFloat(size) / sourceSize.height)
        let renderedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(x: (CGFloat(size) - renderedSize.width) / 2, y: (CGFloat(size) - renderedSize.height) / 2)
        guard let source = CIImage(image: oriented) else { return nil }
        let transformed = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
        CVPixelBufferLockBaseAddress(buffer, [])
        let background = CIImage(color: CIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        context.render(
            transformed.composited(over: background),
            to: buffer
        )
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

#if DEBUG
typealias DebugLocalPrediction = LocalModelPrediction
typealias DebugLocalModelError = LocalModelError
typealias DebugLocalModelService = LocalModelService
#endif

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
