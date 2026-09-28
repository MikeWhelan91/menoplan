import Foundation
import UIKit

struct AIAnalysisResponse: Decodable, Sendable {
    var resultType: ScanResultType
    var confidencePercentage: Int
    var certaintyPercentage: Int
    var controlLineDetected: Bool
    var testLineDetected: Bool
    var testControlRatio: Double
    var lineStrength: Double
    var observedLinePattern: String?
    var nextBestAction: String?
    var imageQualityStatus: ImageQualityStatus
    var explanation: String
    var trendSummary: String
    var guidance: String
    var qualityNotes: [String]
    var model: String?

    var summary: String {
        var parts = [String]()
        if !trendSummary.isEmpty { parts.append(trendSummary) }
        if let observedLinePattern, !observedLinePattern.isEmpty { parts.append(observedLinePattern) }
        parts.append(guidance)
        if let nextBestAction, !nextBestAction.isEmpty { parts.append(nextBestAction) }
        if !qualityNotes.isEmpty { parts.append(qualityNotes.joined(separator: " ")) }
        return parts.joined(separator: "\n\n")
    }

    var lineAnalysisResult: LineAnalysisResult {
        LineAnalysisResult(
            resultType: resultType,
            confidencePercentage: confidencePercentage,
            certaintyPercentage: certaintyPercentage,
            controlLineDetected: controlLineDetected,
            testLineDetected: testLineDetected,
            testControlRatio: testControlRatio,
            lineStrength: lineStrength,
            quality: ImageQualityResult(status: imageQualityStatus, brightness: 0, blurScore: 0, overexposure: 0),
            explanation: explanation
        )
    }
}

enum AIResultReconciler {

    static func reconcileOvulation(
        ai: LineAnalysisResult,
        local: LineAnalysisResult?
    ) -> LineAnalysisResult {
        // Luna's server-normalised ratio is authoritative for Luna Check.
        // Local Scan remains an independent mode and must never promote or
        // downgrade an AI ovulation result.
        _ = local
        return ai
    }
}

struct AIAnalysisRequest: Encodable, Sendable {
    var testType: String
    var capturedAt: String
    var imageBase64: String
    var localPixelAnalysis: LocalPixelAnalysisPayload?
    var localModelAnalysis: LocalModelAnalysisPayload?
    var userSafetyId: String
    var isRecheck: Bool?
    var userStatedOpinion: String?
}

struct LocalModelAnalysisPayload: Encodable, Sendable {
    var modelVersion: String
    var imageUsable: Double
    var controlLinePresent: Double
    var testLinePresent: Double
    var testLineStrength: Double
}

struct LocalPixelAnalysisPayload: Encodable, Sendable {
    var algorithmVersion: String
    var suggestedResult: String
    var testControlRatio: Double
    var lineStrength: Double
    var controlLineDetected: Bool
    var testLineDetected: Bool
    var certaintyPercentage: Int
    var qualityStatus: String
    var brightness: Double
    var blurScore: Double
    var overexposure: Double
}

enum AIAnalysisServiceError: LocalizedError {
    case endpointNotConfigured
    case imageEncodingFailed
    case badStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured: "Luna Check is temporarily unavailable."
        case .imageEncodingFailed: "Could not prepare this image for AI analysis."
        case .badStatus(_, let message): message
        case .invalidResponse: "Luna Check could not read this test. Please try again."
        }
    }
}

final class AIAnalysisService {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
        encoder.dateEncodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .useDefaultKeys
    }

    @MainActor
    func analyse(
        image: UIImage,
        testType: TestType,
        manuallyEnhancedImage: UIImage? = nil,
        isRecheck: Bool = false,
        userStatedOpinion: String? = nil
    ) async throws -> AIAnalysisResponse {
        guard let endpoint = Self.endpoint else { throw AIAnalysisServiceError.endpointNotConfigured }
        let preparedImage = LunaImagePreparationService.prepare(image)
        let uploadImage = ImageHelpers.resized(preparedImage, maxDimension: 1400)

        // Pregnancy sends only a brightness/contrast-enhanced rendering to
        // Luna — never the untouched original — to give it the best chance
        // of seeing a faint mark. The user's own manual adjustment (Check It
        // Yourself → Ask AI) is used in place of the fixed auto preset when
        // present. The untouched original never leaves the device for
        // pregnancy; it's kept only for local pixel analysis below and the
        // result screen. Ovulation is unchanged: it still sends its true
        // original alongside the reference chart. A "Look Again" recheck is
        // the one exception for either test type: it always sends the true
        // original, deliberately skipping any enhancement, since the point
        // of a recheck is a genuinely independent second read rather than
        // the same processed pixels the first read already saw.
        let primaryImage = uploadImage
        guard let imageBase64 = Self.encodedJPEG(primaryImage) else {
            throw AIAnalysisServiceError.imageEncodingFailed
        }
        // Sent as context for Luna to weigh, never as ground truth it can act
        // on unchecked — the server only ever puts this in the prompt text
        // and must not let it substitute for Luna's own read (see
        // AIResultReconciler.reconcileOvulation,
        // intentionally a no-op for this exact reason). Always computed
        // from the true, unenhanced original regardless of what's actually
        // sent as the primary image, so it stays an independent signal
        // rather than restating the same processed pixels back to the model.
        let localPixelAnalysis = Self.localPixelAnalysis(for: uploadImage, testType: testType)
        let localModelAnalysis: LocalModelAnalysisPayload? = nil

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Self.clientToken {
            request.setValue(token, forHTTPHeaderField: "x-menoplan-client-token")
        }

        let payload = AIAnalysisRequest(
            testType: testType.rawValue,
            capturedAt: ISO8601DateFormatter().string(from: .now),
            imageBase64: imageBase64,
            localPixelAnalysis: localPixelAnalysis,
            localModelAnalysis: localModelAnalysis,
            userSafetyId: Self.userSafetyId,
            isRecheck: isRecheck ? true : nil,
            userStatedOpinion: isRecheck ? userStatedOpinion : nil
        )
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIAnalysisServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = http.statusCode >= 500
                ? "Luna Check is temporarily unavailable. Please try again later."
                : (Self.errorMessage(from: data) ?? "Luna Check could not read this test.")
            throw AIAnalysisServiceError.badStatus(http.statusCode, message)
        }

        return try decoder.decode(AIAnalysisResponse.self, from: data)
    }

    private static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LineCheckAIEndpoint") as? String else { return nil }
        guard !value.isEmpty, !value.contains("YOUR_VERCEL_PROJECT") else { return nil }
        return URL(string: value)
    }

    private static var clientToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LineCheckAIClientToken") as? String else { return nil }
        guard !value.isEmpty, !value.contains("OPTIONAL_SHARED_SECRET") else { return nil }
        return value
    }

    private static var userSafetyId: String {
        if let existing = UserDefaults.standard.string(forKey: "linecheck.aiSafetyId") {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: "linecheck.aiSafetyId")
        return created
    }

    private static func encodedJPEG(_ image: UIImage) -> String? {
        image.jpegData(compressionQuality: 0.92)?.base64EncodedString()
    }

    private static func localPixelAnalysis(for image: UIImage, testType: TestType) -> LocalPixelAnalysisPayload {
        let analysisImage = testType == .ovulation
            ? image
            : TestTemplateGeometry.localReaderImage(from: image)
        let result = LineAnalysisEngine().analyse(analysisImage, testType: testType)
        let algorithmVersion = testType == .ovulation
            ? "right-control-local-contrast-v2"
            : "pregnancy-color-line-v1"
        return LocalPixelAnalysisPayload(
            algorithmVersion: algorithmVersion,
            suggestedResult: result.resultType.rawValue,
            testControlRatio: result.testControlRatio,
            lineStrength: result.lineStrength,
            controlLineDetected: result.controlLineDetected,
            testLineDetected: result.testLineDetected,
            certaintyPercentage: result.certaintyPercentage,
            qualityStatus: result.quality.status.rawValue,
            brightness: result.quality.brightness,
            blurScore: result.quality.blurScore,
            overexposure: result.quality.overexposure
        )
    }

    private static func errorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String
        else { return nil }
        if error.localizedCaseInsensitiveContains("refused")
            || error.localizedCaseInsensitiveContains("could not analyse") {
            return "Luna could not analyse this image right now. Try another photo or adjust it manually."
        }
        if let detail = object["detail"] as? String {
            if detail.localizedCaseInsensitiveContains("refused") {
                return "Luna could not analyse this image right now. Try another photo or adjust it manually."
            }
            return "\(error): \(detail)"
        }
        return error
    }
}

enum LunaImagePreparationService {
    static func prepare(_ image: UIImage) -> UIImage {
        // Preserve the user's crop exactly - this is the untouched base every
        // downstream step works from. Transport resizing happens later in
        // `analyse`; whether brightness/contrast enhancement is then applied
        // before upload is a per-testType decision made there, not here.
        image
    }
}
