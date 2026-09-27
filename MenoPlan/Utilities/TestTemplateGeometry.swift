import CoreGraphics
import UIKit

/// Geometry shared by the guided alignment UI and local line analysis.
/// Coordinates are relative to the complete aligned-test crop.
enum TestTemplateGeometry {
    /// The live T/C membrane area shown by the inner template box. A small
    /// margin is retained for real-world alignment error while excluding the
    /// printed legend, handle, test tip, and surrounding background.
    static let lineRegion = CGRect(x: 0.30, y: 0.10, width: 0.40, height: 0.80)

    /// The non-ML line reader needs more lateral tolerance than the model
    /// crop. A faint T can sit close to the left guide edge in a real capture;
    /// clipping it out prevents even an honest Not Clear result.
    static let localReaderRegion = CGRect(x: 0.18, y: 0.08, width: 0.64, height: 0.84)

    static let diagnosticDescription = "guidedTCBox(x0.30,y0.10,w0.40,h0.80)"

    static func lineAnalysisImage(from alignedTestImage: UIImage) -> UIImage? {
        ImageHelpers.cropped(alignedTestImage, normalizedRect: lineRegion)
    }

    static func localReaderImage(from alignedTestImage: UIImage) -> UIImage {
        ImageHelpers.cropped(alignedTestImage, normalizedRect: localReaderRegion) ?? alignedTestImage
    }

    /// Pregnancy's fixed-window heuristic wants the tight T/C crop. The
    /// ovulation analyser deliberately scans the complete strip to locate
    /// its own T/C pair, so it must retain the legacy full-strip input.
    static func analysisImage(from alignedTestImage: UIImage, testType: TestType) -> UIImage {
        guard testType == .pregnancy else { return alignedTestImage }
        return lineAnalysisImage(from: alignedTestImage) ?? alignedTestImage
    }
}
