import UIKit

enum LocalPregnancyDecision: Equatable {
    case negative(spatiallyConfirmed: Bool)
    case faint(spatiallyConfirmed: Bool)
    case positive(spatiallyConfirmed: Bool)
    case invalid
    case unclear(LocalPregnancyUnclearReason)
}

enum LocalPregnancyUnclearReason: Equatable {
    case imageQuality
}

enum LocalPregnancyReadability {
    static func score(_ quality: ImageQualityResult) -> Int {
        // Bright, evenly exposed photos are easiest to read. Keep this
        // continuous so two photos do not collapse onto a hardcoded floor.
        let brightness = max(0, min(1, 1 - abs(quality.brightness - 0.60) / 0.60))
        let exposure = max(0, min(1, 1 - max(0, quality.overexposure - 0.72) / 0.28))
        let sharpness = max(0, min(1, quality.blurScore / 0.25))
        return Int((100 * (brightness * 0.35 + exposure * 0.40 + sharpness * 0.25)).rounded())
    }
}

struct LocalPregnancyDiagnostics: Equatable {
    let modelVersion: String
    let imageWidth: Int
    let imageHeight: Int
    let originalTestLinePresent: Double
    let invertedTestLinePresent: Double
    let originalTestLineStrength: Double
    let invertedTestLineStrength: Double
    let imageUsable: Double
    let controlLinePresent: Double
    let testLinePresent: Double
    let testLineStrength: Double
    let spatialControlDetected: Bool
    let spatialTestDetected: Bool
    let spatialTestControlRatio: Double
    let spatialLineStrength: Double
    let reconciliationDecision: String
    let finalResult: ScanResultType
    let qualityStatus: ImageQualityStatus
    let brightness: Double
    let blurScore: Double
    let overexposure: Double
    // The exact candidate image the model and spatial detector both actually
    // analysed (post guide-crop, pre any further processing) - not the
    // user's original photo. Added 2026-08-24 so a real failure case can be
    // inspected pixel-for-pixel instead of guessed at from diagnostic
    // numbers alone. Not persisted anywhere; held only for this session's
    // debug panel.
    let analyzedImage: UIImage?

    var report: String {
        """
        model=\(modelVersion)
        input=\(imageWidth)x\(imageHeight); spatialROI=\(TestTemplateGeometry.diagnosticDescription)
        original.test=\(originalTestLinePresent.formatted(.number.precision(.fractionLength(4)))); strength=\(originalTestLineStrength.formatted(.number.precision(.fractionLength(4))))
        inverted.test=\(invertedTestLinePresent.formatted(.number.precision(.fractionLength(4)))); strength=\(invertedTestLineStrength.formatted(.number.precision(.fractionLength(4))))
        ensemble.usable=\(imageUsable.formatted(.number.precision(.fractionLength(4))))
        ensemble.control=\(controlLinePresent.formatted(.number.precision(.fractionLength(4))))
        ensemble.test=\(testLinePresent.formatted(.number.precision(.fractionLength(4))))
        ensemble.strength=\(testLineStrength.formatted(.number.precision(.fractionLength(4))))
        spatial.mode=positionAwareControlV3
        spatial.control=\(spatialControlDetected)
        spatial.test=\(spatialTestDetected)
        spatial.ratio=\(spatialTestControlRatio.formatted(.number.precision(.fractionLength(4))))
        spatial.strength=\(spatialLineStrength.formatted(.number.precision(.fractionLength(4))))
        reconciliation=\(reconciliationDecision)
        final=\(finalResult.rawValue)
        quality=\(qualityStatus.rawValue); brightness=\(brightness.formatted(.number.precision(.fractionLength(4)))); blur=\(blurScore.formatted(.number.precision(.fractionLength(4)))); overexposure=\(overexposure.formatted(.number.precision(.fractionLength(4))))
        """
    }
}

struct LocalPregnancyAnalysis: Equatable {
    let result: LineAnalysisResult
    let diagnostics: LocalPregnancyDiagnostics
}

/// Combines the learned visual model with the independent spatial detector.
/// The bundled Siamese model is the primary classifier. The older spatial detector is fallible
/// supporting evidence: agreement can increase confidence, but disagreement
/// must not veto an otherwise readable model result.
enum OnDevicePregnancyReconciler {
    static func decide(
        imageUsable: Double,
        controlLinePresent: Double,
        testLinePresent: Double,
        testLineStrength: Double,
        spatialControlLineDetected: Bool = true,
        spatialTestLineDetected: Bool,
        spatialLineStrength: Double,
        spatialTestControlRatio: Double,
        originalTestLineStrength: Double = 0,
        invertedTestLineStrength: Double = 0,
        overexposure: Double = 0,
        qualityStatus: ImageQualityStatus = .good,
        testSurfaceDetected: Bool = true,
        suppressModelOnlyTestOnPaleBlueMembrane: Bool = false
    ) -> LocalPregnancyDecision {
        guard imageUsable >= 0.50 else { return .unclear(.imageQuality) }
        // This checks for the broad test/membrane material before trusting
        // any line-shaped contrast. It blocks fabric, wallpaper, and other
        // patterned backgrounds that can fool both line readers. A tightly
        // framed real strip can, however, contain mostly pink membrane and
        // no longer satisfy the broad neutral-surface heuristic. In that
        // narrow case allow it through only when *both* independent readers
        // strongly corroborate the control line; backgrounds do not get this
        // exception from one model score alone.
        let corroboratedStrongControl = controlLinePresent >= 0.90 && spatialControlLineDetected
        guard testSurfaceDetected || corroboratedStrongControl else { return .invalid }
        // The model's own imageUsable score is a self-assessment - it can be
        // overconfident on a genuinely blurry photo with no real line
        // structure (confirmed case: imageUsable 0.94, controlLinePresent
        // 0.92 on a photo the independent pixel-based quality check flags as
        // blurry). Corroborate with that independent heuristic rather than
        // trusting the model's confidence alone; this is a second signal,
        // not a threshold tweak on the same one.
        // hardToDetect means the independent pixel check found no plausible
        // test membrane/window in the frame (for example a wall, keyboard,
        // or fabric). It must not reach the line classifier at all.
        guard qualityStatus != .hardToDetect else { return .invalid }
        // The spatial reader is strict and can miss a real control when the
        // guided crop is shifted. The preceding test-surface gate rejects
        // patterned backgrounds, so use the local model's control score for
        // a plausible test surface instead of treating a spatial miss as an
        // invalid test.
        // Once a control is physically located, blur means the test is real
        // but its result cannot be read confidently — preserve Not Clear for
        // that distinct case instead of calling the test itself invalid.
        guard qualityStatus != .blurry else { return .unclear(.imageQuality) }
        // The guide fixes the control to the right half of the T/C box. The
        // position-aware local reader can therefore validate a real control
        // even when the learned model is less certain about an unusual dye
        // colour (notably blue controls).
        guard controlLinePresent >= 0.50 || spatialControlLineDetected else { return .invalid }
        if suppressModelOnlyTestOnPaleBlueMembrane {
            return .negative(spatiallyConfirmed: true)
        }

        // The spatial detector measures pixel contrast, which overexposure
        // directly washes out - its silence carries less evidence on a
        // photo we already know is overexposed. Reuse the same 0.72 cutoff
        // LocalPregnancyReadability already treats as where exposure starts
        // degrading, rather than inventing a new threshold. Confirmed false
        // negative case: model 0.60 (moderate, not "high confidence"),
        // spatial found nothing (contrast washed out), overexposure 0.83 -
        // a real line got read as negative because the veto didn't know the
        // photo it was judging was already unreliable.
        let spatialEvidenceUnreliable = overexposure >= 0.72
        // The anchored reader deliberately keeps its strict coloured-line flag
        // conservative. A pale, overexposed line can still leave a coherent
        // local contrast measurement. Allow that weaker spatial evidence to
        // support a borderline model result, while requiring the model itself
        // to remain above its line threshold.
        let strengthOnlySupportsLine = spatialLineStrength >= LocalPregnancyModelMetadata.possibleSpatialLineStrength
            && testLinePresent <= LocalPregnancyModelMetadata.maximumStrengthOnlyModelProbability
        // Confirmed real case 2026-08-23: model 0.7712 (confident, just under
        // the 0.80 high-confidence bar), spatial strength only 0.0254 (below
        // possibleSpatialLineStrength, so strengthOnlySupportsLine can't
        // fire) but spatial ratio 0.0187 - a real, nonzero dye-colour ratio,
        // not the exact-zero seen in the shadow/ambiguous cases. This
        // mechanism already existed (minimumHighModelPartialDyeRatio) for
        // exactly "confident model + a small real dye ratio," proven safe by
        // testHighModelFaintRegressionUsesSmallMeasuredDyeRatio (model
        // 0.7705, ratio 0.0158) - but it was nested behind the strength gate
        // above, which defeated its purpose whenever strength alone (unlike
        // ratio) stayed low. Ratio is chroma-only, immune to the luminance
        // issue the LineAnalysisEngine fix addressed, so it doesn't need a
        // strength floor to be trustworthy on its own.
        let highModelWithPartialDyeRatio = testLinePresent > LocalPregnancyModelMetadata.maximumStrengthOnlyModelProbability
            && spatialTestControlRatio >= LocalPregnancyModelMetadata.minimumHighModelPartialDyeRatio
        let inversionRevealedLine = invertedTestLineStrength >= LocalPregnancyModelMetadata.inversionRevealedLineStrength
            && invertedTestLineStrength - originalTestLineStrength >= LocalPregnancyModelMetadata.inversionRevealedLineGain
        let edgeSpatialSupport = testLinePresent <= LocalPregnancyModelMetadata.maximumStrengthOnlyModelProbability
            && spatialLineStrength >= LocalPregnancyModelMetadata.edgeSpatialLineStrength
            && spatialTestControlRatio >= LocalPregnancyModelMetadata.edgeSpatialLineRatio
        // Tried and reverted 2026-08-23: a "moderate model confidence + any
        // non-trivial spatial strength, ratio not required" path, meant to
        // rescue a confirmed real case (model 0.66, spatial strength 0.048,
        // ratio 0.0000, genuine faint line). Reverted because it broke
        // testShadowedSingleControlRegressionRejectsStrengthWithoutDyeRatio,
        // a *different* confirmed real case (a window shadow: model 0.7688,
        // spatial strength 0.1756, ratio 0 - correctly negative) - that
        // shadow case scores *higher* than the faint-line case on both
        // model and strength, so any threshold loose enough to rescue the
        // faint line also rescues the shadow. These two real cases
        // genuinely overlap on the only signals computed here; per this
        // project's own calibration discipline (data/CALIBRATION.md), that
        // calls for a richer feature (e.g. real dye-colour vs. neutral-
        // shadow discrimination in LineAnalysisEngine), not a narrower
        // cutoff guessed between two data points. Left unfixed rather than
        // reintroducing a fixed incident to patch a different one.
        let spatialSupportsLine = spatialTestLineDetected
            || strengthOnlySupportsLine
            || highModelWithPartialDyeRatio
            || inversionRevealedLine
            || edgeSpatialSupport
            || (spatialLineStrength >= LocalPregnancyModelMetadata.moderateSpatialLineStrength
                && spatialTestControlRatio >= LocalPregnancyModelMetadata.moderateSpatialLineRatio)

        guard testLinePresent >= LocalPregnancyModelMetadata.testLineThreshold else {
            // A score just under the line-present threshold used to be an
            // unconditional negative - this branch never looked at spatial or
            // inversion evidence at all, even though the exact same evidence
            // is consulted for every score *above* the threshold. Confirmed
            // real case 2026-08-23: a genuine faint positive scored 0.4381
            // (threshold 0.50) and was called negative outright, with the
            // spatial detector also silent - independently traced to the
            // photo's own faint line being low-contrast to begin with, not
            // fixed by the overexposure-metric correction made the same day.
            // Bounded below by nearMissModelProbability so a clearly-negative
            // score isn't rescued just because spatial evidence happens to
            // coincidentally agree - this only softens the boundary right at
            // the cutoff, matching the project's stated priority that missing
            // a faint positive costs more than a difficult negative.
            guard testLinePresent >= LocalPregnancyModelMetadata.nearMissModelProbability,
                  spatialSupportsLine || spatialEvidenceUnreliable else {
                return .negative(spatiallyConfirmed: !spatialTestLineDetected)
            }
            return .faint(spatiallyConfirmed: spatialTestLineDetected)
        }

        // Removed 2026-08-24: this used to guard on
        // `modelIsHighConfidence || spatialSupportsLine || spatialEvidenceUnreliable`,
        // requiring independent corroboration for any model score below 0.80.
        // That existed for one confirmed incident (a window shadow scoring
        // 0.7688). Deliberately removed after ten real-device photos in one
        // session, all at model scores >=0.50: every one was a genuine faint
        // positive per the user, and the spatial ratio/strength readings
        // never discriminated positive from negative even once, clustering
        // in the same ~0-0.02 band regardless of ground truth (a confirmed
        // real negative even read ratio=0.0182, indistinguishable from a
        // confirmed real positive's 0.0187). The corroboration requirement
        // was doing far more harm (repeated real missed positives) than the
        // one shadow case it prevents is worth, given this project's own
        // stated priority that a missed faint positive costs more than an
        // accepted difficult negative. Known, accepted tradeoff: the shadow
        // case can recur (see testShadowedSingleControlRegressionRejectsStrengthWithoutDyeRatio,
        // updated the same day to reflect this deliberate choice) - fixing
        // that properly still needs the richer colour-vs-shadow feature in
        // LineAnalysisEngine this session never got real pixel access to
        // build, not another reconciler threshold.
        // NOTE: a same-night attempt to treat a confidently+substantially
        // spatially-detected line (spatialTestLineDetected && spatialLineStrength
        // >= 0.20) as sufficient for .positive on its own was reverted - a real
        // on-device case showed the spatial scan's ratio/strength can look
        // almost identical (0.38/0.31) for a single ambiguous colour region as
        // for a genuine two-line positive (0.38/0.42), so that pair of numbers
        // alone isn't reliable enough to skip the model's own judgement. The
        // model's testLineStrength regression is known to be miscalibrated
        // (see git history around 2026-08-22) - fixing this properly needs a
        // retrain with the strength-loss weighting corrected, not another
        // reconciliation threshold guessed from a handful of photos.
        return testLineStrength >= 0.18
            ? .positive(spatiallyConfirmed: spatialTestLineDetected)
            : .faint(spatiallyConfirmed: spatialTestLineDetected)
    }
}

final class OnDevicePregnancyAnalysisService {
    private let model = LocalModelService()
    private let qualityService = ImageQualityService()
    private let spatialLineEngine = LineAnalysisEngine()

    func analyse(_ image: UIImage) async throws -> LineAnalysisResult {
        try await analyseWithDiagnostics(image).result
    }

    func analyseWithDiagnostics(_ image: UIImage) async throws -> LocalPregnancyAnalysis {
        var invertSettings = EnhancementSettings()
        invertSettings.invert = true
        let invertedImage = ImageEnhancementService().enhance(image, settings: invertSettings)
        // Sequential, not concurrent (async let), because both calls share
        // this instance's `model` - running them side by side risked a data
        // race the compiler correctly flagged once this service was moved
        // off @MainActor. Still runs off the main thread either way, which
        // is the part that mattered for not blocking the loading screen's
        // animation.
        let originalPrediction = try await model.predict(image: image)
        let invertedPrediction = try await model.predict(image: invertedImage)
        // testLinePresent/testLineStrength use max, not mean, of the two
        // passes - confirmed real case 2026-08-24: original alone scored
        // 0.6079 (correctly above the line-present threshold), but
        // inversion read only 0.3496 on the same genuine faint line,
        // averaging them down to 0.4788 and flipping a correct read to
        // negative. Inversion exists to *reveal* a line the original pass
        // might miss (see inversionRevealedLine in the reconciler) - it was
        // never meant to be trusted equally when it does worse than the
        // original, only when it does better. imageUsable/controlLinePresent
        // are unaffected by this specific failure mode and stay averaged.
        let prediction = LocalModelPrediction(
            imageUsable: (originalPrediction.imageUsable + invertedPrediction.imageUsable) / 2,
            controlLinePresent: (originalPrediction.controlLinePresent + invertedPrediction.controlLinePresent) / 2,
            testLinePresent: max(originalPrediction.testLinePresent, invertedPrediction.testLinePresent),
            testLineStrength: max(originalPrediction.testLineStrength, invertedPrediction.testLineStrength)
        )
        let quality = qualityService.score(image)
        let testSurfaceDetected = qualityService.hasPlausiblePregnancyTestSurface(image)

        // The learned v9 model was trained on the aligned outer crop. The
        // independent line reader searches only the exact inner T/C guide box.
        // A future model may switch to that crop only after guide-aligned
        // training data passes the same locked safety gates.
        let spatialImage = TestTemplateGeometry.localReaderImage(from: image)
        let spatialResult = spatialLineEngine.analyse(spatialImage, testType: .pregnancy)
        let suppressModelOnlyTestOnPaleBlueMembrane = qualityService.hasPaleBlueMembraneDominance(image)
            && spatialResult.controlLineDetected
            && !spatialResult.testLineDetected
        let decision = OnDevicePregnancyReconciler.decide(
            imageUsable: prediction.imageUsable,
            controlLinePresent: prediction.controlLinePresent,
            testLinePresent: prediction.testLinePresent,
            testLineStrength: prediction.testLineStrength,
            spatialControlLineDetected: spatialResult.controlLineDetected,
            spatialTestLineDetected: spatialResult.testLineDetected,
            spatialLineStrength: spatialResult.lineStrength,
            spatialTestControlRatio: spatialResult.testControlRatio,
            originalTestLineStrength: originalPrediction.testLineStrength,
            invertedTestLineStrength: invertedPrediction.testLineStrength,
            overexposure: quality.overexposure,
            qualityStatus: quality.status,
            testSurfaceDetected: testSurfaceDetected,
            suppressModelOnlyTestOnPaleBlueMembrane: suppressModelOnlyTestOnPaleBlueMembrane
        )
        let presentation = presentation(for: decision, testLineStrength: prediction.testLineStrength, quality: quality)
        let finalResult = result(
            type: presentation.type,
            prediction: prediction,
            quality: quality,
            confidence: certainty(for: decision, prediction: prediction),
            readability: LocalPregnancyReadability.score(quality),
            explanation: presentation.explanation
        )
        let diagnostics = LocalPregnancyDiagnostics(
            modelVersion: LocalPregnancyModelMetadata.version,
            imageWidth: Int(image.size.width.rounded()),
            imageHeight: Int(image.size.height.rounded()),
            originalTestLinePresent: originalPrediction.testLinePresent,
            invertedTestLinePresent: invertedPrediction.testLinePresent,
            originalTestLineStrength: originalPrediction.testLineStrength,
            invertedTestLineStrength: invertedPrediction.testLineStrength,
            imageUsable: prediction.imageUsable,
            controlLinePresent: prediction.controlLinePresent,
            testLinePresent: prediction.testLinePresent,
            testLineStrength: prediction.testLineStrength,
            spatialControlDetected: spatialResult.controlLineDetected,
            spatialTestDetected: spatialResult.testLineDetected,
            spatialTestControlRatio: spatialResult.testControlRatio,
            spatialLineStrength: spatialResult.lineStrength,
            reconciliationDecision: diagnosticName(for: decision),
            finalResult: finalResult.resultType,
            qualityStatus: quality.status,
            brightness: quality.brightness,
            blurScore: quality.blurScore,
            overexposure: quality.overexposure,
            analyzedImage: image
        )
        return LocalPregnancyAnalysis(result: finalResult, diagnostics: diagnostics)
    }

    private func diagnosticName(for decision: LocalPregnancyDecision) -> String {
        switch decision {
        case .negative(let confirmed): "negative(spatialConfirmed:\(confirmed))"
        case .faint(let confirmed): "faint(spatialConfirmed:\(confirmed))"
        case .positive(let confirmed): "positive(spatialConfirmed:\(confirmed))"
        case .invalid: "invalid(controlOrTestSurfaceRejected)"
        case .unclear(.imageQuality): "unclear(imageUsableBelowThreshold)"
        }
    }

    /// User-facing advice, not a description of how the reading was produced.
    /// Rewritten 2026-08-24 - the previous copy ("the on-device model
    /// detected...the local line detector agreed") described internal
    /// mechanics no user can act on. Every branch here should instead answer
    /// "what does this mean for me, and what should I actually do next,"
    /// with wording that varies by how strong/certain the actual reading
    /// was, not just which of the five result buckets it landed in.
    private func presentation(
        for decision: LocalPregnancyDecision,
        testLineStrength: Double,
        quality: ImageQualityResult
    ) -> (type: ScanResultType, explanation: String) {
        // Stable for one scan, but varied across different measurements so
        // the results page does not repeat one canned paragraph indefinitely.
        let copySeed = abs(Int((testLineStrength * 10_000).rounded()) + Int((quality.brightness * 1_000).rounded()))
        func varied(_ options: [String]) -> String {
            options[copySeed % options.count]
        }

        switch decision {
        case .negative(let confirmed):
            return confirmed
                ? (.appearsNegative, varied([
                    "Only the control line is visible, so this test appears negative. If you tested before your expected period, it may simply be too early. Try again in 2–3 days with first-morning urine if your period has not arrived.",
                    "This looks negative: the control line developed, but no second line is visible. Early results can change, so consider repeating the test in a few days if your period is late or the timing was early.",
                    "One clear control line and no test line indicates a negative result at the time of testing. If this does not match what you expected, wait a couple of days and retest using first-morning urine."
                ]))
                : (.appearsNegative, varied([
                    "This photo leans negative, with no clear second line beside the control. Because the image was less straightforward than usual, check the physical test within its reading window and retake the photo in even light if needed.",
                    "No definite test line is visible here, so the result appears negative. If you remain unsure, use a fresh test in 2–3 days rather than relying on repeated photos of this one.",
                    "The control line is present and a second line is not clear enough to count, which suggests a negative result. If the timing was early, repeating in a few days should give a clearer answer."
                ]))
        case .faint(let confirmed):
            if !confirmed {
                return (.faintLineDetected, varied([
                    "There may be a very light second line here, but it is too subtle for a firm answer from this photo. Check the test itself in good light and within its reading window, then retest in 2–3 days if you are still unsure.",
                    "A possible second line is showing, though it remains uncertain. Save this photo and compare it with a fresh test taken in a couple of days, ideally using first-morning urine.",
                    "This could be an early faint line, but the mark is not distinct enough to call confidently. Repeat with a new test in 48–72 hours for a clearer answer."
                ]))
            }
            switch testLineStrength {
            case ..<0.08:
                return (.faintLineDetected, varied([
                    "There is only the slightest hint of a second line. At this strength it could be an early positive, but marks seen after the test's reading window can be misleading. Retest in about 48 hours and compare the results.",
                    "An extremely light mark appears beside the control line. Treat this as a possible faint result rather than a definite positive, and use a fresh test in 2–3 days for a clearer comparison."
                ]))
            case 0.08..<0.14:
                return (.faintLineDetected, varied([
                    "A faint second line is visible next to the control. This can happen early when hormone levels are still low. Save this result and retest in 48–72 hours to see whether the line becomes clearer.",
                    "There is a light but visible test line here, which may be an early positive. Repeating the test in a couple of days under similar conditions will make any change easier to judge."
                ]))
            default:
                return (.faintLineDetected, varied([
                    "A second line is visible, although it remains lighter than a clear positive. This is a promising early result; testing again in 2–3 days should make the pattern easier to interpret.",
                    "The test line is faint but distinct enough to notice. Consider this a possible early positive and confirm it with another test in a few days or with a healthcare professional."
                ]))
            }
        case .positive(let confirmed):
            if !confirmed {
                return (.appearsPositive, varied([
                    "A second line is visible next to the control, so this test appears positive. Provided it appeared within the test's reading window, a lighter line still counts. A healthcare professional can confirm the result when you are ready.",
                    "This test shows both a control line and a test line, which indicates a positive result when read within the instructed time. Consider confirming with another test or a healthcare professional.",
                    "Two lines can be seen here, so the result appears positive. Line intensity can vary; what matters is that the second line developed within the manufacturer's reading window."
                ]))
            }
            return testLineStrength < 0.35
                ? (.appearsPositive, varied([
                    "A clear second line has developed beside the control, so this result is positive. It is lighter than the control, which is common early on. You may wish to confirm it with a healthcare professional.",
                    "Both lines are visible and the test line is clear enough to indicate a positive result. A lighter test line can still be positive when it appears within the correct reading time.",
                    "This reads as positive: the control line is present and a definite second line has appeared. Confirm with another test or a healthcare professional if you would like additional certainty."
                ]))
                : (.appearsPositive, varied([
                    "A strong second line is visible beside the control, giving a clear positive result. When you are ready, a healthcare professional can confirm the pregnancy and discuss next steps.",
                    "This is a clear positive line pattern, with both the control and test lines well developed. Consider arranging confirmation and any support you need from a healthcare professional.",
                    "Two distinct, strong lines are present, so the test appears positive. Take whatever time you need, and seek professional confirmation when it feels right for you."
                ]))
        case .invalid:
            return (.invalid, varied([
                "The control line did not appear, so this test is invalid even if another line is visible. Use a fresh test and follow its sampling and timing instructions carefully.",
                "This test cannot be interpreted because its control line is missing. That means the test did not run correctly; please repeat it with a new one.",
                "No valid control line developed, so this is not a positive or negative result. Try again with a fresh test and read it within the time stated in the instructions."
            ]))
        case .unclear(.imageQuality):
            switch quality.status {
            case .tooDark:
                return (.unclear, "This photo was too dark to read with confidence. Try again in bright, even lighting - natural daylight near a window usually works well - rather than a dim room.")
            case .overexposed:
                return (.unclear, "This photo had too much glare or brightness to read confidently, which can wash out a faint line entirely. Try angling the test away from direct light or camera flash, and watch for reflections off its glossy plastic window.")
            case .blurry:
                return (.unclear, "This photo wasn't sharp enough to read with confidence. Hold the camera steady, let it focus on the result window, and try moving a little closer rather than zooming in digitally.")
            case .hardToDetect:
                return (.unclear, "We had trouble locating the result window clearly in this photo. Make sure the whole test is visible and lines up with the guide, without anything else in the frame overlapping it.")
            case .good, .poor:
                return (.unclear, "This photo couldn't be read with confidence. Retake it in even lighting, hold the camera steady, and make sure the whole result window is visible and in focus.")
            }
        }
    }

    private func certainty(for decision: LocalPregnancyDecision, prediction: LocalModelPrediction) -> Int {
        switch decision {
        case .negative(let confirmed): adjustedConfidence(1 - prediction.testLinePresent, confirmed: confirmed)
        case .faint(let confirmed), .positive(let confirmed): adjustedConfidence(prediction.testLinePresent, confirmed: confirmed)
        case .invalid: confidence(1 - prediction.controlLinePresent)
        case .unclear: min(65, confidence(abs(prediction.testLinePresent - LocalPregnancyModelMetadata.testLineThreshold)))
        }
    }

    private func adjustedConfidence(_ value: Double, confirmed: Bool) -> Int {
        let raw = confidence(value)
        return confirmed ? raw : min(72, max(45, raw - 15))
    }

    private func result(
        type: ScanResultType,
        prediction: LocalModelPrediction,
        quality: ImageQualityResult,
        confidence: Int,
        readability: Int,
        explanation: String
    ) -> LineAnalysisResult {
        // Without a detected control line, "test line strength" has no
        // meaningful denominator to be measured against - showing a real
        // number here (as history, progression, and Luna's own context all
        // do) reads as a genuine reading rather than the noise it actually
        // is. Matches the same zeroing every other `.invalid` result in
        // LineAnalysisEngine.swift already does.
        let isInvalid = type == .invalid
        return LineAnalysisResult(
            resultType: type,
            confidencePercentage: confidence,
            certaintyPercentage: readability,
            controlLineDetected: prediction.controlLinePresent >= 0.50,
            testLineDetected: type == .appearsPositive || type == .faintLineDetected,
            testControlRatio: isInvalid ? 0 : min(2, max(0, prediction.testLineStrength)),
            lineStrength: isInvalid ? 0 : min(1, max(0, prediction.testLineStrength)),
            quality: quality,
            explanation: explanation
        )
    }

    private func confidence(_ value: Double) -> Int {
        min(96, max(40, Int((value * 100).rounded())))
    }
}
