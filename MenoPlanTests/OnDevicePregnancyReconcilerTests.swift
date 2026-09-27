import XCTest
@testable import MenoPlan

final class OnDevicePregnancyReconcilerTests: XCTestCase {
    func testReadabilityVariesWithMeasuredImageQuality() {
        let clear = LocalPregnancyReadability.score(
            ImageQualityResult(status: .good, brightness: 0.60, blurScore: 0.30, overexposure: 0.70)
        )
        let overexposed = LocalPregnancyReadability.score(
            ImageQualityResult(status: .overexposed, brightness: 0.84, blurScore: 0.30, overexposure: 0.85)
        )
        let darkAndSoft = LocalPregnancyReadability.score(
            ImageQualityResult(status: .tooDark, brightness: 0.12, blurScore: 0.02, overexposure: 0.20)
        )

        XCTAssertEqual(clear, 100)
        XCTAssertLessThan(overexposed, clear)
        XCTAssertLessThan(darkAndSoft, overexposed)
        XCTAssertNotEqual(overexposed, 45)
    }

    func testOriginalAndInvertedPredictionsAreAveraged() {
        let original = LocalModelPrediction(
            imageUsable: 0.9, controlLinePresent: 0.8,
            testLinePresent: 0.84, testLineStrength: 0.30
        )
        let inverted = LocalModelPrediction(
            imageUsable: 0.7, controlLinePresent: 1.0,
            testLinePresent: 0.20, testLineStrength: 0.10
        )

        let combined = LocalModelPrediction.mean(original, inverted)

        XCTAssertEqual(combined.imageUsable, 0.8, accuracy: 0.0001)
        XCTAssertEqual(combined.controlLinePresent, 0.9, accuracy: 0.0001)
        XCTAssertEqual(combined.testLinePresent, 0.52, accuracy: 0.0001)
        XCTAssertEqual(combined.testLineStrength, 0.20, accuracy: 0.0001)
    }

    func testAgreedNegativeIsNegative() {
        XCTAssertEqual(decide(testProbability: 0.20, strength: 0, spatial: false), .negative(spatiallyConfirmed: true))
    }

    func testAgreedFaintLineIsFaint() {
        XCTAssertEqual(decide(testProbability: 0.76, strength: 0.12, spatial: true), .faint(spatiallyConfirmed: true))
    }

    func testAgreedStrongLineIsPositive() {
        XCTAssertEqual(decide(testProbability: 0.90, strength: 0.44, spatial: true), .positive(spatiallyConfirmed: true))
    }

    func testHighConfidenceModelOnlyLineRemainsFaint() {
        XCTAssertEqual(decide(testProbability: 0.84, strength: 0.15, spatial: false), .faint(spatiallyConfirmed: false))
    }

    // Changed 2026-08-24: was .negative, required spatial support for any
    // model score below 0.80. Removed after ten real-device photos in one
    // session (all model >=0.50, all genuine faint positives per the user)
    // showed spatial ratio/strength never discriminated positive from
    // negative even once - see OnDevicePregnancyAnalysisService.swift for
    // the full account. The model's own score is now trusted directly once
    // it clears the base threshold.
    func testBorderlineModelLineRequiresSpatialSupport() {
        XCTAssertEqual(decide(testProbability: 0.62, strength: 0.15, spatial: false), .faint(spatiallyConfirmed: false))
    }

    func testBorderlineModelLineWithSpatialSupportIsFaint() {
        XCTAssertEqual(decide(testProbability: 0.62, strength: 0.15, spatial: true), .faint(spatiallyConfirmed: true))
    }

    /// Real on-device miss (candidate-13, 2026-08-22): a genuinely faint but
    /// visible line was read as negative. The model leaned positive (0.6045)
    /// but not "high confidence"; the spatial scan found nothing because the
    /// photo was overexposed (0.8275), and its silence alone vetoed the
    /// model. Overexposure washes out exactly the pixel contrast the spatial
    /// scan depends on, so its "no support" carries less evidence on a photo
    /// already known to be degraded.
    func testOverexposedBorderlineLineIsNotVetoedBySpatialSilence() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6045,
                strength: 0.0389,
                spatial: false,
                spatialStrength: 0.0176,
                spatialRatio: 0.0276,
                overexposure: 0.8275
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    /// Changed 2026-08-24: this used to require spatial support outside the
    /// overexposed case specifically (was .negative). Superseded by the same
    /// aggregate real-device evidence as testBorderlineModelLineRequiresSpatialSupport -
    /// the model's own score is now trusted directly regardless of exposure.
    func testBorderlineModelLineWithoutOverexposureStillRequiresSpatialSupport() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6045,
                strength: 0.0389,
                spatial: false,
                spatialStrength: 0.0176,
                spatialRatio: 0.0276,
                overexposure: 0.50
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    /// Overexposure can only matter once the model itself is at least at the
    /// base test-line threshold - it must never turn a confidently negative
    /// model read into a positive just because the photo is overexposed.
    func testOverexposureNeverRescuesADefinitiveModelNegative() {
        XCTAssertEqual(
            decide(testProbability: 0.20, strength: 0, spatial: false, overexposure: 0.95),
            .negative(spatiallyConfirmed: true)
        )
    }

    /// Reverted attempt (2026-08-22, same night): treating a confidently and
    /// substantially spatially-detected line as sufficient for .positive on
    /// its own. A follow-up real photo showed the spatial scan's ratio/
    /// strength can look almost identical for a single ambiguous colour
    /// region (ratio 0.3804, strength 0.3065, .positive) as for a genuine
    /// two-line result - so that signal alone isn't trustworthy enough to
    /// bypass the model. Documented here as a guardrail against retrying the
    /// same fix: a detected-and-substantial spatial line must still defer to
    /// the model's own testLineStrength, pending a real recalibration.
    func testSubstantialSpatialLineAloneDoesNotForcePositive() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6707,
                strength: 0.0645,
                spatial: true,
                spatialStrength: 0.4180,
                spatialRatio: 0.3845
            ),
            .faint(spatiallyConfirmed: true)
        )
    }

    func testOverexposedFaintRegressionUsesMeasuredPossibleMark() {
        XCTAssertEqual(
            decide(
                testProbability: 0.5906,
                strength: 0.0676,
                spatial: false,
                spatialStrength: 0.1540,
                spatialRatio: 0
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    /// Changed 2026-08-24 (was .negative): this exact ratio (0.0068) is
    /// functionally indistinguishable from a confirmed real positive's
    /// ratio the same night (0.0072) - direct evidence the spatial ratio
    /// doesn't discriminate ground truth at this magnitude, which is the
    /// premise the whole spatial-corroboration requirement was resting on.
    /// Trading this known case for the ten real misses it was causing.
    func testDefinitiveNegativeRegressionIgnoresNegligibleSpatialStrength() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6616,
                strength: 0.1202,
                spatial: false,
                spatialStrength: 0.0060,
                spatialRatio: 0.0068
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testOverexposedFaintRetryUsesModerateStrengthAndRatio() {
        XCTAssertEqual(
            decide(
                testProbability: 0.5784,
                strength: 0.0645,
                spatial: false,
                spatialStrength: 0.0585,
                spatialRatio: 0.0348
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    // Changed 2026-08-24 (was .negative) - same structural change as the
    // other reconciler tests updated this date.
    func testSingleControlLineRegressionRejectsMarginalSpatialArtifact() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6306,
                strength: 0.0942,
                spatial: false,
                spatialStrength: 0.0409,
                spatialRatio: 0.0262
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testVisibleFaintRegressionUsesStrongPartialMarkDespiteLowRatio() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6853,
                strength: 0.0933,
                spatial: false,
                spatialStrength: 0.0661,
                spatialRatio: 0.0236
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    /// Changed 2026-08-24 (was .negative): this is the specific known,
    /// deliberately-accepted regression - see the removed-guard comment in
    /// OnDevicePregnancyAnalysisService.swift for the full reasoning. This
    /// window-shadow case (model 0.7688) can recur as a false .faint; judged
    /// a smaller cost than the repeated real misses removing the
    /// corroboration requirement fixed. Fixing this one properly still needs
    /// real dye-colour vs. neutral-shadow discrimination in
    /// LineAnalysisEngine, not a reconciler threshold.
    func testShadowedSingleControlRegressionRejectsStrengthWithoutDyeRatio() {
        XCTAssertEqual(
            decide(
                testProbability: 0.7688,
                strength: 0.0663,
                spatial: false,
                spatialStrength: 0.1756,
                spatialRatio: 0
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testHighModelFaintRegressionUsesSmallMeasuredDyeRatio() {
        XCTAssertEqual(
            decide(
                testProbability: 0.7705,
                strength: 0.0998,
                spatial: false,
                spatialStrength: 0.0912,
                spatialRatio: 0.0158
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testVeryFaintRegressionUsesPartialMarkInUncertainModelBand() {
        XCTAssertEqual(
            decide(
                testProbability: 0.7136,
                strength: 0.0520,
                spatial: false,
                spatialStrength: 0.0527,
                spatialRatio: 0
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testBorderlineFaintRegressionIsRevealedByInversion() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.9790,
                controlLinePresent: 0.9829,
                testLinePresent: 0.6277,
                testLineStrength: 0.1152,
                spatialTestLineDetected: false,
                spatialLineStrength: 0.0148,
                spatialTestControlRatio: 0.0153,
                originalTestLineStrength: 0.0729,
                invertedTestLineStrength: 0.1575
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    // Changed 2026-08-24 (was .negative) - same known case as
    // testDefinitiveNegativeRegressionIgnoresNegligibleSpatialStrength
    // (identical testLinePresent/spatialLineStrength/spatialTestControlRatio),
    // exercised here via the full decide() signature instead of the test
    // helper's shorthand.
    func testKnownNegativeInversionGainIsTooSmallToCreateLine() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.9827,
                controlLinePresent: 0.9856,
                testLinePresent: 0.6616,
                testLineStrength: 0.1202,
                spatialTestLineDetected: false,
                spatialLineStrength: 0.0060,
                spatialTestControlRatio: 0.0068,
                originalTestLineStrength: 0.0948,
                invertedTestLineStrength: 0.1455
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testBorderlineFaintRetryToleratesSmallCropVariationInInversionGain() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.9807,
                controlLinePresent: 0.9839,
                testLinePresent: 0.6592,
                testLineStrength: 0.1171,
                spatialTestLineDetected: false,
                spatialLineStrength: 0.0192,
                spatialTestControlRatio: 0.0234,
                originalTestLineStrength: 0.0826,
                invertedTestLineStrength: 0.1516
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testExtremelyFaintRegressionUsesTwoSignalEdgeSupport() {
        XCTAssertEqual(
            decide(
                testProbability: 0.6323,
                strength: 0.0998,
                spatial: false,
                spatialStrength: 0.0490,
                spatialRatio: 0.0219
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testPixelOnlyLineDoesNotOverrideModelNegative() {
        XCTAssertEqual(decide(testProbability: 0.18, strength: 0.05, spatial: true), .negative(spatiallyConfirmed: false))
    }

    func testMissingControlIsInvalid() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.95,
                controlLinePresent: 0.20,
                testLinePresent: 0.80,
                testLineStrength: 0.30,
                spatialControlLineDetected: false,
                spatialTestLineDetected: true,
                spatialLineStrength: 0.30,
                spatialTestControlRatio: 0.30
            ),
            .invalid
        )
    }

    func testModelControlRemainsValidWhenSpatialControlMisses() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.9402,
                controlLinePresent: 0.9226,
                testLinePresent: 0.7715,
                testLineStrength: 0.2317,
                spatialControlLineDetected: false,
                spatialTestLineDetected: true,
                spatialLineStrength: 0.0889,
                spatialTestControlRatio: 0.2685
            ),
            .positive(spatiallyConfirmed: true)
        )
    }

    func testModelControlCanValidateAPlausibleTestWhenSpatialControlMisses() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.95,
                controlLinePresent: 0.98,
                testLinePresent: 0.72,
                testLineStrength: 0.12,
                spatialControlLineDetected: false,
                spatialTestLineDetected: false,
                spatialLineStrength: 0,
                spatialTestControlRatio: 0
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testPositionAwareControlCanValidateAnUnusualDyeColour() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.95,
                controlLinePresent: 0.35,
                testLinePresent: 0.63,
                testLineStrength: 0.12,
                spatialControlLineDetected: true,
                spatialTestLineDetected: false,
                spatialLineStrength: 0.01,
                spatialTestControlRatio: 0.01
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testNonTestFrameIsInvalidRatherThanUnclear() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.95,
                controlLinePresent: 0.98,
                testLinePresent: 0.72,
                testLineStrength: 0.18,
                spatialTestLineDetected: false,
                spatialLineStrength: 0,
                spatialTestControlRatio: 0,
                qualityStatus: .hardToDetect
            ),
            .invalid
        )
    }

    func testBlurryFrameWithoutASpatialControlIsUnclearNotInvalid() {
        // Once a control is physically located by the model, blur means the
        // test is real but unreadable - decide() deliberately returns
        // .unclear(.imageQuality) here rather than .invalid (see the comment
        // above the `qualityStatus != .blurry` guard).
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.95,
                controlLinePresent: 0.98,
                testLinePresent: 0.72,
                testLineStrength: 0.18,
                spatialControlLineDetected: false,
                spatialTestLineDetected: false,
                spatialLineStrength: 0,
                spatialTestControlRatio: 0,
                qualityStatus: .blurry
            ),
            .unclear(.imageQuality)
        )
    }

    func testPatternedNonTestSurfaceIsInvalidBeforeLineClassification() {
        // controlLinePresent is kept below the 0.90 `corroboratedStrongControl`
        // bar (see decide()'s tightly-cropped-strip exception) so this stays a
        // genuine test of the surface gate itself, not a case that legitimately
        // qualifies for that narrow rescue.
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.95,
                controlLinePresent: 0.85,
                testLinePresent: 0.72,
                testLineStrength: 0.18,
                spatialControlLineDetected: true,
                spatialTestLineDetected: true,
                spatialLineStrength: 0.20,
                spatialTestControlRatio: 0.64,
                testSurfaceDetected: false
            ),
            .invalid
        )
    }

    func testStrongControlCorroborationCanValidateATightlyCroppedPinkStrip() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.96,
                controlLinePresent: 0.95,
                testLinePresent: 0.63,
                testLineStrength: 0.12,
                spatialControlLineDetected: true,
                spatialTestLineDetected: false,
                spatialLineStrength: 0.008,
                spatialTestControlRatio: 0.012,
                testSurfaceDetected: false
            ),
            .faint(spatiallyConfirmed: false)
        )
    }

    func testUnusableImageIsUnclearBeforeOtherEvidence() {
        XCTAssertEqual(
            OnDevicePregnancyReconciler.decide(
                imageUsable: 0.20,
                controlLinePresent: 0.95,
                testLinePresent: 0.80,
                testLineStrength: 0.30,
                spatialTestLineDetected: true,
                spatialLineStrength: 0.30,
                spatialTestControlRatio: 0.30
            ),
            .unclear(.imageQuality)
        )
    }

    private func decide(
        testProbability: Double,
        strength: Double,
        spatial: Bool,
        spatialStrength: Double = 0,
        spatialRatio: Double = 0,
        overexposure: Double = 0
    ) -> LocalPregnancyDecision {
        OnDevicePregnancyReconciler.decide(
            imageUsable: 0.95,
            controlLinePresent: 0.95,
            testLinePresent: testProbability,
            testLineStrength: strength,
            spatialTestLineDetected: spatial,
            spatialLineStrength: spatialStrength,
            spatialTestControlRatio: spatialRatio,
            overexposure: overexposure
        )
    }
}

final class OnDeviceOvulationReconcilerTests: XCTestCase {
    func testModelControlCanValidateAPlausibleTestWhenSpatialReaderMisses() {
        XCTAssertTrue(OnDeviceOvulationReconciler.hasValidControl(modelControlPresent: 0.92, spatialControlDetected: true))
        XCTAssertTrue(OnDeviceOvulationReconciler.hasValidControl(modelControlPresent: 0.92, spatialControlDetected: false))
        XCTAssertTrue(OnDeviceOvulationReconciler.hasValidControl(modelControlPresent: 0.49, spatialControlDetected: true))
        XCTAssertFalse(OnDeviceOvulationReconciler.hasValidControl(modelControlPresent: 0.49, spatialControlDetected: false))
    }
}
