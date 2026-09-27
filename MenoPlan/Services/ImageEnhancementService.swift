import CoreImage
import UIKit

struct EnhancementSettings: Equatable {
    var brightness = 0.0
    var contrast = 1.0
    var exposure = 0.0
    var gamma = 1.0
    var sharpen = 0.0
    var saturation = 1.0
    var warmth = 0.0
    var greyscale = false
    var invert = false
}

extension EnhancementSettings {
    /// Base, non-user-adjustable settings used to derive the single enhanced
    /// rendering sent to Luna Check for pregnancy (see `lunaCheckAuto(forSourceBrightness:)`
    /// below for the adaptive, actually-applied version) and as the starting
    /// point for the "Check It Yourself" manual sliders.
    static let lunaCheckAuto = EnhancementSettings(
        brightness: 0.06,
        contrast: 1.64,
        exposure: -0.84,
        gamma: 1.45,
        sharpen: 1.5,
        saturation: 1.5,
        warmth: -0.51
    )

    /// Scales `.lunaCheckAuto`'s exposure/gamma darkening down for an
    /// already-dim source photo. The base preset's -0.84 EV cut and 1.45
    /// gamma were tuned against well-lit photos, where darkening further
    /// boosts contrast against the membrane's white; applied unscaled to a
    /// dim bathroom/bedroom photo, the two compound into a near-unreadable
    /// dark, blue-tinted result. Full darkening only applies above
    /// `brightPoint`; it fades to none by `dimPoint`, which matches
    /// ImageQualityService's own "too dark" cutoff.
    static func lunaCheckAuto(forSourceBrightness brightness: Double) -> EnhancementSettings {
        let dimPoint = 0.18
        let brightPoint = 0.55
        let scale = min(max((brightness - dimPoint) / (brightPoint - dimPoint), 0), 1)
        var settings = lunaCheckAuto
        settings.exposure *= scale
        settings.gamma = 1 + (settings.gamma - 1) * scale
        return settings
    }
}

final class ImageEnhancementService {
    func enhance(_ image: UIImage, settings: EnhancementSettings) -> UIImage {
        guard var ciImage = CIImage(image: image) else { return image }
        ciImage = ciImage
            .applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: settings.brightness,
                kCIInputContrastKey: settings.contrast,
                kCIInputSaturationKey: settings.greyscale ? 0 : settings.saturation
            ])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: settings.exposure])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": settings.gamma])

        if settings.warmth != 0 {
            ciImage = ciImage.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500 + settings.warmth * 1200, y: 0),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }
        if settings.sharpen > 0 {
            ciImage = ciImage.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: settings.sharpen
            ])
        }
        if settings.invert {
            ciImage = ciImage.applyingFilter("CIColorInvert")
        }
        return ImageHelpers.uiImage(from: ciImage, orientation: image.imageOrientation) ?? image
    }

    /// The single auto-enhance entry point for Luna Check and the "Check It
    /// Yourself" starting point. Scales the darkening to the source photo's
    /// own brightness, then verifies the *result* actually landed above the
    /// "too dark" floor and lifts it back up once if not — a backstop
    /// against any edge case in the scaling math, not just the common case.
    func enhanceAuto(_ image: UIImage) -> (image: UIImage, settings: EnhancementSettings) {
        let quality = ImageQualityService()
        let sourceBrightness = quality.score(image).brightness
        let settings = EnhancementSettings.lunaCheckAuto(forSourceBrightness: sourceBrightness)
        let enhanced = enhance(image, settings: settings)

        let dimFloor = 0.16
        let resultBrightness = quality.score(enhanced).brightness
        guard resultBrightness < dimFloor else { return (enhanced, settings) }

        var lifted = settings
        lifted.exposure += (dimFloor - resultBrightness) * 2.2
        return (enhance(image, settings: lifted), lifted)
    }
}
