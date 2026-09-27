import UIKit

@Observable
final class CaptureViewModel {
    var testType: TestType = .pregnancy
    var testFormat: TestFormat = .unspecified
    var analysisMode: AnalysisMode = .aiQuickCheck
    var capturedImage: UIImage?
}
