import UIKit

@Observable
final class EnhancerViewModel {
    var settings = EnhancementSettings()
    var showEnhancedPreview = true
    let service = ImageEnhancementService()

    func enhancedImage(from image: UIImage) -> UIImage {
        service.enhance(image, settings: settings)
    }
}
