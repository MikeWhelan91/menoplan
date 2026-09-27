import XCTest
@testable import MenoPlan

/// Not a pass/fail correctness test - a diagnostic harness that runs the
/// local heuristic scanner against a real, human-labelled reference set
/// bundled as test resources (LineCheckTests/Fixtures/guided-tc-sample).
///
/// Sourced from a verified ROI export (line-roi variant, ROI [0.3,0.1,0.7,0.9]
/// - an exact match for TestTemplateGeometry.lineRegion) covering all 432
/// pregnancy rows, so every image here is already cropped exactly the way
/// TestTemplateGeometry.analysisImage(testType: .pregnancy) crops a real
/// aligned photo in production. Earlier attempts using
/// Training/data/manifest-v12-guided-tc.csv directly were unreliable: most
/// of its images are raw/unaligned photos or a different crop convention
/// entirely, and the only images matching this heuristic's expected input
/// shape turned out to be synthetic renders at the wrong (portrait) aspect
/// ratio for this test type. The Simulator's test process can't read
/// arbitrary host paths outside its sandbox, so the sample is bundled
/// rather than read from disk directly.
final class LineAnalysisEngineCalibrationTests: XCTestCase {
    private struct Row {
        let file: String
        let id: String
        let controlPresent: Bool
        let testPresent: Bool
        let strength: Double
    }

    private func loadManifest() -> [Row] {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "manifest", withExtension: "csv", subdirectory: "Fixtures/guided-tc-sample"),
              let csv = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // Written with \r\n line endings; Swift's Character treats CRLF as
        // a single grapheme cluster, so splitting on "\n" alone finds
        // nothing - split on any newline character set instead.
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }.dropFirst()
        return lines.compactMap { line -> Row? in
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 5 else { return nil }
            return Row(
                file: cols[0],
                id: cols[1],
                controlPresent: cols[2] == "1",
                testPresent: cols[3] == "1",
                strength: Double(cols[4]) ?? 0
            )
        }
    }

}
