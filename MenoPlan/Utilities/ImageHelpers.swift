import CoreGraphics
import CoreImage
import UIKit

enum ImageHelpers {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func uiImage(from ciImage: CIImage, scale: CGFloat = 1, orientation: UIImage.Orientation = .up) -> UIImage? {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let factor = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    static func cropped(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let imageRect = CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height))
        let cropRect = CGRect(
            x: normalizedRect.origin.x * imageRect.width,
            y: normalizedRect.origin.y * imageRect.height,
            width: normalizedRect.width * imageRect.width,
            height: normalizedRect.height * imageRect.height
        )
        .intersection(imageRect)
        .integral

        guard cropRect.width > 20, cropRect.height > 20 else { return nil }
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

}
