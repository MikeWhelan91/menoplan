import XCTest
@testable import MenoPlan

final class GuidedCaptureCropMathTests: XCTestCase {
    func testMatchingAspectRatioMapsGuideDirectlyByPreviewScale() {
        // overlay 400x800 vs image 1200x2400 share an aspect ratio, so the
        // preview fills the overlay with no letterboxing: scale is exactly 1/3.
        let result = GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            guideFrame: CGRect(x: 100, y: 300, width: 200, height: 100),
            imagePixelSize: CGSize(width: 1200, height: 2400),
            marginFraction: 0
        )

        XCTAssertEqual(result, CGRect(x: 300, y: 900, width: 600, height: 300))
    }

    func testMarginExpandsTheCropSymmetrically() {
        let result = GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            guideFrame: CGRect(x: 100, y: 300, width: 200, height: 100),
            imagePixelSize: CGSize(width: 1200, height: 2400),
            marginFraction: 0.1
        )

        // guideFrame inset by -10% each side: x 100-20=80, width 200*1.2=240;
        // y 300-10=290, height 100*1.2=120. Then divided by the 1/3 preview scale.
        XCTAssertEqual(result, CGRect(x: 240, y: 870, width: 720, height: 360))
    }

    func testLetterboxedPreviewOffsetsTheDisplayedOrigin() {
        // overlay (300x800) is narrower than the image's aspect ratio
        // (900x1800), so the preview is pillarboxed left/right once
        // aspect-filled: previewScale = max(300/900, 800/1800) = 800/1800,
        // displayedSize = (400, 800), displayedOrigin = (-50, 0). Hand-worked:
        // pixels.x = (50 - -50) / (800/1800) = 225, pixels.y = 350 / (800/1800)
        // = 787.5, width = 200 / (800/1800) = 450, height = 100 / (800/1800)
        // = 225 — then .integral rounds y/height outward to (787, 226).
        let result = GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 300, height: 800),
            guideFrame: CGRect(x: 50, y: 350, width: 200, height: 100),
            imagePixelSize: CGSize(width: 900, height: 1800),
            marginFraction: 0
        )

        XCTAssertEqual(result, CGRect(x: 225, y: 787, width: 450, height: 226))
    }

    func testCropIsClampedToImageBounds() {
        // A guide box near the edge, padded, would extend past the image —
        // the result must be clamped, not negative-sized or out of bounds.
        let result = GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            guideFrame: CGRect(x: 350, y: 300, width: 50, height: 100),
            imagePixelSize: CGSize(width: 1200, height: 2400),
            marginFraction: 0.2
        )

        let imageBounds = CGRect(x: 0, y: 0, width: 1200, height: 2400)
        XCTAssertNotNil(result)
        if let result {
            XCTAssertTrue(imageBounds.contains(result))
        }
    }

    func testDegenerateInputsReturnNil() {
        XCTAssertNil(GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: .zero,
            guideFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imagePixelSize: CGSize(width: 100, height: 100)
        ))
        XCTAssertNil(GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            guideFrame: .zero,
            imagePixelSize: CGSize(width: 100, height: 100)
        ))
        XCTAssertNil(GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            guideFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imagePixelSize: .zero
        ))
    }

    func testTinyResultingCropReturnsNil() {
        // A guide box that maps to only a few pixels isn't a usable crop.
        let result = GuidedCaptureCropMath.pixelCropRect(
            overlayBounds: CGRect(x: 0, y: 0, width: 4000, height: 8000),
            guideFrame: CGRect(x: 100, y: 300, width: 5, height: 5),
            imagePixelSize: CGSize(width: 1200, height: 2400),
            marginFraction: 0
        )
        XCTAssertNil(result)
    }
}
