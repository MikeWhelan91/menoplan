import CoreGraphics

/// Pure geometry for mapping the on-screen guide box shown over a live,
/// aspect-filled camera preview into a pixel-space crop rect on the captured
/// photo. Kept free of UIKit/live-layout so it can be unit tested without a
/// device camera.
enum GuidedCaptureCropMath {
    /// - Parameters:
    ///   - overlayBounds: The overlay view's own bounds, in points. Assumed to
    ///     exactly match the live camera preview's on-screen bounds (true
    ///     when `showsCameraControls == false` and a custom, full-bounds
    ///     `cameraOverlayView` is used, as this app does).
    ///   - guideFrame: The visible guide box's frame, converted into the
    ///     overlay's own coordinate space.
    ///   - imagePixelSize: The captured photo's pixel dimensions (already
    ///     normalized to `.up` orientation).
    ///   - marginFraction: Extra padding added around `guideFrame`, as a
    ///     fraction of its own size, before mapping to pixels. The live
    ///     preview's field of view is not guaranteed to be pixel-identical to
    ///     the final captured photo's field of view on every device/capture
    ///     mode; a small margin means that mismatch is far more likely to
    ///     include a little extra membrane than to clip a real line.
    static func pixelCropRect(
        overlayBounds: CGRect,
        guideFrame: CGRect,
        imagePixelSize: CGSize,
        marginFraction: CGFloat = 0.06
    ) -> CGRect? {
        guard overlayBounds.width > 0, overlayBounds.height > 0,
              guideFrame.width > 0, guideFrame.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }

        // Aspect-fill: the preview scales up until it covers the overlay
        // bounds entirely, then centers, letterboxing off-screen on one axis.
        let previewScale = max(
            overlayBounds.width / imagePixelSize.width,
            overlayBounds.height / imagePixelSize.height
        )
        let displayedSize = CGSize(
            width: imagePixelSize.width * previewScale,
            height: imagePixelSize.height * previewScale
        )
        let displayedOrigin = CGPoint(
            x: (overlayBounds.width - displayedSize.width) / 2,
            y: (overlayBounds.height - displayedSize.height) / 2
        )

        let paddedGuide = guideFrame.insetBy(
            dx: -guideFrame.width * marginFraction,
            dy: -guideFrame.height * marginFraction
        )

        let pixels = CGRect(
            x: (paddedGuide.minX - displayedOrigin.x) / previewScale,
            y: (paddedGuide.minY - displayedOrigin.y) / previewScale,
            width: paddedGuide.width / previewScale,
            height: paddedGuide.height / previewScale
        ).integral.intersection(CGRect(origin: .zero, size: imagePixelSize))

        guard pixels.width > 20, pixels.height > 20 else { return nil }
        return pixels
    }
}
