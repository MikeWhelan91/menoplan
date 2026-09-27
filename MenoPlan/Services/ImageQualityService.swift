import CoreImage
import UIKit

struct ImageQualityResult: Equatable {
    var status: ImageQualityStatus
    var brightness: Double
    var blurScore: Double
    var overexposure: Double
    var message: String { status.title }
}

final class ImageQualityService {
    /// A test reader must only inspect a plausible piece of test housing or
    /// membrane. This deliberately checks surface material, not
    /// line contrast: skin and patterned fabric can contain line-like edges,
    /// but neither has the broad, near-neutral white region of a cassette or
    /// a test's live membrane.
    func hasPlausibleTestSurface(_ image: UIImage, testType: TestType) -> Bool {
        guard let ciImage = CIImage(image: ImageHelpers.resized(image, maxDimension: 360)) else {
            return false
        }
        let gridSize = 24
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return false }
        let scale = CGAffineTransform(scaleX: CGFloat(gridSize) / extent.width, y: CGFloat(gridSize) / extent.height)
        let downsampled = ciImage.transformed(by: scale)
        var bitmap = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        ImageHelpers.ciContext.render(
            downsampled,
            toBitmap: &bitmap,
            rowBytes: gridSize * 4,
            bounds: CGRect(x: 0, y: 0, width: gridSize, height: gridSize),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var neutralMembranePixels = 0
        var pinkMembranePixels = 0
        for pixel in 0..<(gridSize * gridSize) {
            let offset = pixel * 4
            let red = Double(bitmap[offset]) / 255
            let green = Double(bitmap[offset + 1]) / 255
            let blue = Double(bitmap[offset + 2]) / 255
            let brightness = (red + green + blue) / 3
            let saturation = max(red, green, blue) - min(red, green, blue)
            // `0.20` was too warm: a close-up of skin passed it and the line
            // model hallucinated a faint result. Test housing/membrane is
            // near-neutral even when it is cream-coloured; real faint-strip
            // calibration photos retain >12% of pixels at <=0.10.
            if brightness >= 0.52 && saturation <= 0.10 { neutralMembranePixels += 1 }
            // Some strip brands have a broad pink membrane rather than a
            // white cassette window. It is materially more red-dominant than
            // skin: require both red-channel separations across a large area,
            // not a single warm-coloured patch.
            if brightness >= 0.60, red >= green + 0.16, red >= blue + 0.16 {
                pinkMembranePixels += 1
            }
        }
        // Both pregnancy and ovulation tests expose a broad pale membrane or
        // cassette surface. Keep the same conservative requirement so the
        // two local routes reject backgrounds consistently. `testType` is
        // intentionally part of this API so future product-specific surface
        // geometry can be calibrated without callers bypassing the gate.
        _ = testType
        let total = Double(gridSize * gridSize)
        return Double(neutralMembranePixels) / total >= 0.12
            || Double(pinkMembranePixels) / total >= 0.25
    }

    func hasPlausiblePregnancyTestSurface(_ image: UIImage) -> Bool {
        hasPlausibleTestSurface(image, testType: .pregnancy)
    }

    func hasPlausibleOvulationTestSurface(_ image: UIImage) -> Bool {
        hasPlausibleTestSurface(image, testType: .ovulation)
    }

    /// Detects a broad, pale-blue membrane/background. This is not a result
    /// classifier: callers must combine it with a positioned reader that
    /// found a control but no test line before treating a learned model's
    /// test-only prediction as an artefact.
    func hasPaleBlueMembraneDominance(_ image: UIImage) -> Bool {
        guard let ciImage = CIImage(image: ImageHelpers.resized(image, maxDimension: 360)) else {
            return false
        }
        let gridSize = 24
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return false }
        let downsampled = ciImage.transformed(by: CGAffineTransform(scaleX: CGFloat(gridSize) / extent.width, y: CGFloat(gridSize) / extent.height))
        var bitmap = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        ImageHelpers.ciContext.render(downsampled, toBitmap: &bitmap, rowBytes: gridSize * 4, bounds: CGRect(x: 0, y: 0, width: gridSize, height: gridSize), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let bluePixels = (0..<(gridSize * gridSize)).reduce(into: 0) { count, pixel in
            let offset = pixel * 4
            let red = Double(bitmap[offset]) / 255
            let green = Double(bitmap[offset + 1]) / 255
            let blue = Double(bitmap[offset + 2]) / 255
            let brightness = (red + green + blue) / 3
            if brightness >= 0.48, blue >= green + 0.05, blue >= red + 0.08 {
                count += 1
            }
        }
        return Double(bluePixels) / Double(gridSize * gridSize) >= 0.25
    }

    func score(_ image: UIImage) -> ImageQualityResult {
        guard let ciImage = CIImage(image: ImageHelpers.resized(image, maxDimension: 360)),
              let filter = CIFilter(name: "CIAreaAverage") else {
            return ImageQualityResult(status: .poor, brightness: 0, blurScore: 0, overexposure: 0)
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        var bitmap = [UInt8](repeating: 0, count: 4)
        ImageHelpers.ciContext.render(filter.outputImage!, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let brightness = (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / (3 * 255)
        let overexposure = fractionOfSaturatedPixels(ciImage)
        let blur = estimateContrast(ciImage)
        let status: ImageQualityStatus
        if brightness < 0.18 { status = .tooDark }
        // This threshold (0.78) was tuned against the *old* overexposure
        // formula (max average channel - see git history and
        // fractionOfSaturatedPixels' doc comment for why that was replaced
        // 2026-08-23) against three confirmed real cases of a genuine faint
        // positive read as negative, all with the old metric measured at
        // 0.81-0.84. The new metric's 0.78 is not yet validated against
        // those same cases or any other real photos - re-check against real
        // overexposed and real normally-exposed pale-strip photos before
        // trusting this number.
        else if overexposure > 0.78 { status = .overexposed }
        // Raised twice now - 0.015 originally, then 0.05. Three confirmed
        // real cases of a genuinely blurry, structureless photo (no test
        // visible at all) scored 0.0000, 0.0157, and 0.0588, each one
        // landing right at or just past whatever the cutoff was at the
        // time and getting waved through as "good," which let the model
        // hallucinate a faint line on pure noise. A genuinely sharp photo
        // in the same session scored 0.6902 - all three blurry scores sit
        // in a tight 0-0.06 cluster nowhere near that, so 0.10 still has
        // more than 6x margin below the one real sharp example.
        else if blur < 0.10 { status = .blurry }
        // A real test cassette's background is smooth moulded plastic with
        // only a few thin printed lines - most of the frame has almost no
        // edge content. A brightness-based version of this check (bright
        // pixels regardless of hue) was tried first and failed on a real
        // case: macro shots of woven fabric throw off many small bright
        // specular highlights from individual threads, easily clearing any
        // reasonable brightness bar while being unambiguously not a test.
        // Texture is the actual distinguishing signal - average edge energy
        // across the *whole* frame (not just the centre, unlike the blur
        // check above) stays low when it's mostly flat plastic, and goes up
        // fast when there's fine detail everywhere. Threshold kept high
        // (0.18) since this remains the least-validated check in the
        // pipeline - only real failure cases behind it, no confirmed real
        // test photos measured against it yet.
        else if textureDensity(ciImage) > 0.18 { status = .hardToDetect }
        else { status = .good }
        return ImageQualityResult(status: status, brightness: brightness, blurScore: blur, overexposure: overexposure)
    }

    /// Average edge intensity across the whole frame, not just the centre
    /// region estimateContrast() looks at. A smooth surface (plastic
    /// cassette body) averages low even where it has a couple of thin
    /// printed lines; a surface with fine detail everywhere (woven fabric,
    /// carpet, textured countertop) averages much higher.
    private func textureDensity(_ image: CIImage) -> Double {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0 }
        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
        filter.setValue(edges, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: edges.extent), forKey: kCIInputExtentKey)
        var bitmap = [UInt8](repeating: 0, count: 4)
        ImageHelpers.ciContext.render(filter.outputImage!, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Double(bitmap[0]) / 255
    }

    /// Fraction of pixels with every channel blown out, not the previous
    /// `max(avgR,avgG,avgB)/255` - that measured "how pale is the subject on
    /// average," which reads high for any white/light-coloured test strip
    /// filling the frame regardless of real exposure, and reads *higher*
    /// still now that the guide crop (2026-08-23) tightens the frame to
    /// mostly strip with barely any darker background. This measures actual
    /// highlight clipping instead - a real glare/glossy-reflection blowout
    /// leaves a contiguous patch of genuinely saturated pixels; a normally-
    /// exposed pale strip does not, even though its average is just as high.
    /// Sampled on a small grid rather than a single summary pixel, since
    /// clipping is a local property a whole-image average can't see.
    private func fractionOfSaturatedPixels(_ image: CIImage, gridSize: Int = 24, saturationThreshold: UInt8 = 250) -> Double {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return 0 }
        let scale = CGAffineTransform(scaleX: CGFloat(gridSize) / extent.width, y: CGFloat(gridSize) / extent.height)
        let downsampled = image.transformed(by: scale)
        var bitmap = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        ImageHelpers.ciContext.render(
            downsampled,
            toBitmap: &bitmap,
            rowBytes: gridSize * 4,
            bounds: CGRect(x: 0, y: 0, width: gridSize, height: gridSize),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var saturatedCount = 0
        let totalPixels = gridSize * gridSize
        for pixel in 0..<totalPixels {
            let offset = pixel * 4
            if bitmap[offset] >= saturationThreshold, bitmap[offset + 1] >= saturationThreshold, bitmap[offset + 2] >= saturationThreshold {
                saturatedCount += 1
            }
        }
        return Double(saturatedCount) / Double(totalPixels)
    }

    private func estimateContrast(_ image: CIImage) -> Double {
        guard let filter = CIFilter(name: "CIAreaMaximum") else { return 0.02 }
        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
        // A single sharp edge near the border (a device bezel, background
        // text, a reflection) can otherwise make an image score as "not
        // blurry" even when the centre — where the test itself sits — is
        // genuinely out of focus. Measuring the centre only keeps the same
        // statistic and threshold, just applied to the region that matters.
        let extent = edges.extent
        let centerRegion = extent.insetBy(dx: extent.width * 0.22, dy: extent.height * 0.22)
        filter.setValue(edges, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: centerRegion), forKey: kCIInputExtentKey)
        var bitmap = [UInt8](repeating: 0, count: 4)
        ImageHelpers.ciContext.render(filter.outputImage!, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Double(bitmap[0]) / 255
    }
}
