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

    func testHandCroppedSanityCheck() throws {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "user_report_1_cropped", withExtension: "jpg", subdirectory: "Fixtures/guided-tc-sample"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            throw XCTSkip("hand-cropped sanity fixture not found")
        }
        let engine = LineAnalysisEngine()
        LineAnalysisEngine.debugHook = { print("DEBUG: \($0)") }
        let result = engine.analyse(image, testType: .pregnancy)
        LineAnalysisEngine.debugHook = nil
        print("=== hand-cropped sanity check (task-0107, should be strongly positive) ===")
        print("resultType=\(result.resultType.rawValue) control=\(result.controlLineDetected) test=\(result.testLineDetected) ratio=\(result.testControlRatio) certainty=\(result.certaintyPercentage)")
    }

    func testPregnancyHeuristicAgainstRealPhotoReferenceSet() throws {
        let rows = loadManifest()
        try XCTSkipIf(rows.isEmpty, "Reference manifest not found in bundle - skipping calibration diagnostic.")

        let engine = LineAnalysisEngine()
        var truePositive = 0, trueNegative = 0, falsePositive = 0, falseNegative = 0
        var fnByStrength: [Double: Int] = [:]
        var fnByStrengthTotal: [Double: Int] = [:]
        var fpDetails: [String] = []
        var fnDetails: [String] = []

        for row in rows {
            guard let url = Bundle(for: Self.self).url(forResource: row.file, withExtension: nil, subdirectory: "Fixtures/guided-tc-sample"),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { continue }
            let result = engine.analyse(image, testType: .pregnancy)
            let detected = result.testLineDetected

            if row.testPresent { fnByStrengthTotal[row.strength, default: 0] += 1 }

            switch (row.testPresent, detected) {
            case (true, true): truePositive += 1
            case (false, false): trueNegative += 1
            case (false, true):
                falsePositive += 1
                fpDetails.append("\(row.file) (\(row.id)): got \(result.resultType.rawValue) ratio=\(String(format: "%.3f", result.testControlRatio))")
            case (true, false):
                falseNegative += 1
                fnByStrength[row.strength, default: 0] += 1
                fnDetails.append("\(row.file) (\(row.id)): strength=\(row.strength) got \(result.resultType.rawValue) control=\(result.controlLineDetected) ratio=\(String(format: "%.3f", result.testControlRatio))")
            }
        }

        let total = truePositive + trueNegative + falsePositive + falseNegative
        print("=== Pregnancy heuristic vs verified real-photo ROI set (n=\(total)) ===")
        print("TP=\(truePositive) TN=\(trueNegative) FP=\(falsePositive) FN=\(falseNegative)")
        print("accuracy=\(total > 0 ? Double(truePositive + trueNegative) / Double(total) : 0)")
        print("--- false negative rate by ground-truth strength ---")
        for strength in fnByStrengthTotal.keys.sorted() {
            let missed = fnByStrength[strength] ?? 0
            let total = fnByStrengthTotal[strength] ?? 0
            print("strength=\(strength): missed \(missed)/\(total)")
        }
        print("--- false positives (phantom line on a negative), \(fpDetails.count) ---")
        for m in fpDetails { print(m) }
        print("--- false negatives (real line missed), \(fnDetails.count) ---")
        for m in fnDetails { print(m) }
    }
}
