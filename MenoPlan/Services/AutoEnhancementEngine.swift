import UIKit

struct AutoEnhancementResult {
    var enhancedImage: UIImage
    var settings: EnhancementSettings
    var analysis: LineAnalysisResult
    var summary: String
}

final class AutoEnhancementEngine {
    private let enhancer = ImageEnhancementService()
    private let qualityService = ImageQualityService()

    func run(on image: UIImage, testType: TestType) async -> AutoEnhancementResult {
        await Task.yield()
        let (enhancedImage, settings) = enhancer.enhanceAuto(image)
        return AutoEnhancementResult(
            enhancedImage: enhancedImage,
            settings: settings,
            analysis: placeholderAnalysis(for: enhancedImage, testType: testType),
            summary: "Auto enhanced the image for line contrast and readability."
        )
    }

    private func placeholderAnalysis(for image: UIImage, testType: TestType) -> LineAnalysisResult {
        LineAnalysisResult(
            resultType: .unclear,
            confidencePercentage: 0,
            certaintyPercentage: 0,
            controlLineDetected: false,
            testLineDetected: false,
            testControlRatio: 0,
            lineStrength: 0,
            quality: qualityService.score(image),
            explanation: "Auto enhancement adjusts the image only. Run a local scan or Luna Check for a result."
        )
    }
}
