import XCTest
@testable import MenoPlan

/// Diagnostic harness (not pass/fail correctness) that runs the two
/// shipped CoreML models - LineCheckVisionSiamese-v9-reddit-150
/// (pregnancy) and LineCheckOvulationPairComparator-v12-direct-guide-box
/// (ovulation) - against their own real, held-out TEST splits, so their
/// on-device accuracy is measured against real data instead of assumed.
///
/// Fixtures are the exact images each model's training run withheld from
/// training for evaluation, confirmed by matching row counts against each
/// checkpoint's own artifacts:
/// - Pregnancy: Training/output/manifest.csv, split=="test" (68 rows) -
///   matches linecheck-siamese-v9-reddit-150-faint-safety-test.json's
///   count of 68 exactly. Images use crop_method=="guided", the ~4.21:1
///   "aligned outer crop" the model receives raw (no further cropping) in
///   OnDevicePregnancyAnalysisService.
/// - Ovulation: Training/output/ovulation-control-anchor-clean-base/
///   manifest-numeric-reviewed.csv, split=="test" (111 rows) - geometry
///   (~2.10:1) matches TestTemplateGeometry.lineRegion applied to that
///   same 4.21:1 outer crop, i.e. exactly what
///   OnDeviceOvulationAnalysisService crops to before calling its model.
final class OnDeviceModelCalibrationTests: XCTestCase {
    private struct PregnancyRow {
        let file: String
        let id: String
        let controlPresent: Bool
        let testPresent: Bool
        let strength: Double
    }

    private struct OvulationRow {
        let file: String
        let id: String
        let controlPresent: Bool
        let testPresent: Bool
        let ratio: Double
        let tier: String
    }

    private func loadCSV(subdirectory: String) -> [[String]] {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "manifest", withExtension: "csv", subdirectory: subdirectory),
              let csv = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // Written with \r\n line endings; Swift's Character treats CRLF as
        // a single grapheme cluster, so splitting on "\n" alone finds
        // nothing - split on any newline character set instead.
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }.dropFirst()
        return lines.map { $0.components(separatedBy: ",") }
    }

    private func loadImage(file: String, subdirectory: String) -> UIImage? {
        guard let url = Bundle(for: Self.self).url(forResource: file, withExtension: nil, subdirectory: subdirectory),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func testOvulationModelAgainstHeldOutTestSplit() async throws {
        let rows = loadCSV(subdirectory: "Fixtures/ovulation-model-test").compactMap { cols -> OvulationRow? in
            guard cols.count >= 6 else { return nil }
            return OvulationRow(file: cols[0], id: cols[1], controlPresent: cols[2] == "1", testPresent: cols[3] == "1", ratio: Double(cols[4]) ?? 0, tier: cols[5])
        }
        try XCTSkipIf(rows.isEmpty, "Ovulation model test fixtures not found - skipping.")

        let service = OnDeviceOvulationAnalysisService()
        let heuristicEngine = LineAnalysisEngine()
        var tierMatches = 0, tierMismatches = 0, errors = 0
        var absoluteRatioErrors: [Double] = []
        var mismatchDetails: [String] = []
        var confusion: [String: [String: Int]] = [:]
        var rawPairs: [String] = []

        for row in rows {
            guard let image = loadImage(file: row.file, subdirectory: "Fixtures/ovulation-model-test") else { continue }
            do {
                let analysis = try await service.analysePreCropped(image, recentRatios: [])
                let heuristicResult = heuristicEngine.analyse(image, testType: .ovulation)
                let predictedTier = analysis.result.resultType.rawValue
                confusion[row.tier, default: [:]][predictedTier, default: 0] += 1
                absoluteRatioErrors.append(abs(analysis.result.testControlRatio - row.ratio))
                rawPairs.append("\(row.file),\(row.tier),\(row.ratio),\(predictedTier),\(analysis.result.testControlRatio),\(analysis.diagnostics.pairValid ?? -1),\(analysis.diagnostics.controlPresent ?? -1),\(analysis.diagnostics.predictedRatio ?? -1),\(heuristicResult.testControlRatio),\(heuristicResult.controlLineDetected),\(heuristicResult.testLineDetected)")
                if predictedTier == row.tier {
                    tierMatches += 1
                } else {
                    tierMismatches += 1
                    mismatchDetails.append("\(row.file) (\(row.id)): truth=\(row.tier) ratio=\(row.ratio) got=\(predictedTier) ratio=\(String(format: "%.3f", analysis.result.testControlRatio))")
                }
            } catch {
                errors += 1
                print("Ovulation model error on \(row.file): \(error)")
            }
        }

        let total = tierMatches + tierMismatches
        let meanAbsoluteRatioError = absoluteRatioErrors.isEmpty ? 0 : absoluteRatioErrors.reduce(0, +) / Double(absoluteRatioErrors.count)
        print("=== Ovulation on-device model (v12-direct-guide-box) vs its own held-out test split (n=\(total), errors=\(errors)) ===")
        print("tier accuracy=\(total > 0 ? Double(tierMatches) / Double(total) : 0) (\(tierMatches)/\(total))")
        print("mean absolute ratio error=\(meanAbsoluteRatioError)")
        print("confusion (truth -> [predicted: count]): \(confusion)")
        print("--- tier mismatches, \(mismatchDetails.count) ---")
        for m in mismatchDetails { print(m) }
        print("--- RAW_PAIRS_CSV_START ---")
        print("file,truth_tier,truth_ratio,pred_tier,pred_ratio,pairValid,controlPresent,rawPredictedRatio,heuristicRatio,heuristicControlDetected,heuristicTestDetected")
        for p in rawPairs { print(p) }
        print("--- RAW_PAIRS_CSV_END ---")
    }

    /// Production-faithful end-to-end check of the ensemble + gate + threshold
    /// fix: calls the real analyse(_:recentRatios:) (not the pre-cropped test
    /// hook) on the wide aligned-crop fixtures, so it exercises the exact
    /// same code path (proposal crop, model call, heuristic ensemble,
    /// recalibrated thresholds) production actually runs.
    func testOvulationEnsembleEndToEndOnWideCrop() async throws {
        let wideRows = loadCSV(subdirectory: "Fixtures/ovulation-model-test-wide").compactMap { cols -> OvulationRow? in
            guard cols.count >= 6 else { return nil }
            return OvulationRow(file: cols[0], id: cols[1], controlPresent: cols[2] == "1", testPresent: cols[3] == "1", ratio: Double(cols[4]) ?? 0, tier: cols[5])
        }
        try XCTSkipIf(wideRows.isEmpty, "Wide-crop ovulation fixtures not found - skipping.")

        let service = OnDeviceOvulationAnalysisService()
        var matches = 0, mismatches = 0, errors = 0
        var mismatchDetails: [String] = []
        for row in wideRows {
            guard let image = loadImage(file: row.file, subdirectory: "Fixtures/ovulation-model-test-wide") else { continue }
            do {
                let analysis = try await service.analyse(image, recentRatios: [])
                let predictedTier = analysis.result.resultType.rawValue
                if predictedTier == row.tier {
                    matches += 1
                } else {
                    mismatches += 1
                    mismatchDetails.append("\(row.file) (\(row.id)): truth=\(row.tier) ratio=\(row.ratio) got=\(predictedTier) ratio=\(String(format: "%.3f", analysis.result.testControlRatio))")
                }
            } catch {
                errors += 1
                print("Ensemble end-to-end error on \(row.file): \(error)")
            }
        }
        let total = matches + mismatches
        print("=== Ovulation ensemble end-to-end (analyse(), wide crop, n=\(total), errors=\(errors)) ===")
        print("tier accuracy=\(total > 0 ? Double(matches) / Double(total) : 0) (\(matches)/\(total))")
        print("--- mismatches, \(mismatchDetails.count) ---")
        for m in mismatchDetails { print(m) }
    }

    /// The heuristic's ovulation reader searches the *complete* physical
    /// strip itself to locate the T/C window (see LineAnalysisEngine's
    /// ovulationColorStripResult) - unlike the model, it needs the wider
    /// aligned outer crop, not the tight window already applied in the
    /// main ovulation fixture set. This uses a matched subset (91 of the
    /// 111 test rows, where a wide-crop sibling could be located) so the
    /// heuristic is tested on its own correct input shape, to check
    /// whether combining it with the model's prediction is worth pursuing.
    func testOvulationHeuristicControlThresholdData() throws {
        let wideRows = loadCSV(subdirectory: "Fixtures/ovulation-model-test-wide").compactMap { cols -> OvulationRow? in
            guard cols.count >= 6 else { return nil }
            return OvulationRow(file: cols[0], id: cols[1], controlPresent: cols[2] == "1", testPresent: cols[3] == "1", ratio: Double(cols[4]) ?? 0, tier: cols[5])
        }
        try XCTSkipIf(wideRows.isEmpty, "Wide-crop ovulation fixtures not found - skipping.")

        let engine = LineAnalysisEngine()
        var captured: [String] = []
        LineAnalysisEngine.debugHook = { line in
            if line.hasPrefix("ovulationColorStripResult: pair found") {
                captured.append(line)
            }
        }
        var lines: [String] = []
        for row in wideRows {
            guard let image = loadImage(file: row.file, subdirectory: "Fixtures/ovulation-model-test-wide") else { continue }
            captured.removeAll()
            _ = engine.analyse(image, testType: .ovulation)
            let pairLine = captured.first ?? "NONE"
            lines.append("\(row.file),\(row.tier),\(row.ratio),\(pairLine)")
        }
        LineAnalysisEngine.debugHook = nil
        print("--- CONTROL_THRESHOLD_CSV_START ---")
        for l in lines { print(l) }
        print("--- CONTROL_THRESHOLD_CSV_END ---")
    }

    func testOvulationHeuristicSingleFailureDebug() throws {
        guard let image = loadImage(file: "0052.jpg", subdirectory: "Fixtures/ovulation-model-test-wide") else {
            throw XCTSkip("fixture not found")
        }
        let engine = LineAnalysisEngine()
        LineAnalysisEngine.debugHook = { print("DEBUG: \($0)") }
        let result = engine.analyse(image, testType: .ovulation)
        LineAnalysisEngine.debugHook = nil
        print("=== single failure debug (0039.jpg, truth=low ratio=0.21) ===")
        print("resultType=\(result.resultType.rawValue) control=\(result.controlLineDetected) test=\(result.testLineDetected) ratio=\(result.testControlRatio)")
    }

    func testOvulationNoPairFoundDiagnostics() throws {
        let wideRows = loadCSV(subdirectory: "Fixtures/ovulation-model-test-wide").compactMap { cols -> OvulationRow? in
            guard cols.count >= 6 else { return nil }
            return OvulationRow(file: cols[0], id: cols[1], controlPresent: cols[2] == "1", testPresent: cols[3] == "1", ratio: Double(cols[4]) ?? 0, tier: cols[5])
        }
        try XCTSkipIf(wideRows.isEmpty, "Wide-crop ovulation fixtures not found - skipping.")

        let engine = LineAnalysisEngine()
        var captured: [String] = []
        LineAnalysisEngine.debugHook = { line in captured.append(line) }

        var noPairCount = 0
        var rejectReasonCounts: [String: Int] = [:]
        var closestDistances: [Double] = []

        for row in wideRows {
            guard let image = loadImage(file: row.file, subdirectory: "Fixtures/ovulation-model-test-wide") else { continue }
            captured.removeAll()
            let result = engine.analyse(image, testType: .ovulation)
            guard !result.controlLineDetected else { continue }
            noPairCount += 1
            let rejectLine = captured.first { $0.contains("REJECT") } ?? "NO_REJECT_LINE_CAPTURED"
            let reasonKey: String
            if rejectLine.contains("window too narrow") { reasonKey = "window too narrow" }
            else if rejectLine.contains("fewer than 2 peaks") { reasonKey = "fewer than 2 peaks" }
            else if rejectLine.contains("no pair within spacing") { reasonKey = "no pair within spacing" }
            else { reasonKey = "other/none" }
            rejectReasonCounts[reasonKey, default: 0] += 1
            if reasonKey == "no pair within spacing",
               let range = rejectLine.range(of: "closestRejectedDistance="),
               let value = Double(rejectLine[range.upperBound...].trimmingCharacters(in: .whitespaces)) {
                closestDistances.append(value)
            }
            print("=== NO PAIR: \(row.file) tier=\(row.tier) ratio=\(row.ratio) reason=\(reasonKey) ===")
            for line in captured { print("  \(line)") }
        }
        LineAnalysisEngine.debugHook = nil

        print("=== SUMMARY: noPairCount=\(noPairCount)/\(wideRows.count) ===")
        print("reasonCounts=\(rejectReasonCounts)")
        print("closestRejectedDistances=\(closestDistances.sorted())")
    }

    func testOvulationHeuristicOnWideCropForEnsembleCheck() throws {
        let wideRows = loadCSV(subdirectory: "Fixtures/ovulation-model-test-wide").compactMap { cols -> OvulationRow? in
            guard cols.count >= 6 else { return nil }
            return OvulationRow(file: cols[0], id: cols[1], controlPresent: cols[2] == "1", testPresent: cols[3] == "1", ratio: Double(cols[4]) ?? 0, tier: cols[5])
        }
        try XCTSkipIf(wideRows.isEmpty, "Wide-crop ovulation fixtures not found - skipping.")

        let heuristicEngine = LineAnalysisEngine()
        var pairs: [String] = []
        for row in wideRows {
            guard let wideImage = loadImage(file: row.file, subdirectory: "Fixtures/ovulation-model-test-wide") else { continue }
            let heuristicResult = heuristicEngine.analyse(wideImage, testType: .ovulation)
            pairs.append("\(row.file),\(row.tier),\(row.ratio),\(heuristicResult.testControlRatio),\(heuristicResult.controlLineDetected),\(heuristicResult.testLineDetected)")
        }
        print("--- WIDE_HEURISTIC_CSV_START ---")
        print("file,truth_tier,truth_ratio,heuristicRatio,heuristicControlDetected,heuristicTestDetected")
        for p in pairs { print(p) }
        print("--- WIDE_HEURISTIC_CSV_END ---")
    }
}
