import UIKit

@Observable
final class CaptureViewModel {
    var testType: TestType = .ovulation
    var testFormat: TestFormat = .unspecified
    var analysisMode: AnalysisMode = .aiQuickCheck
    var capturedImage: UIImage?
}
