import Foundation
import UIKit
import CoreImage

/// Mirrors the shape returned by `preg/api/analyse-fsh.js` on LineCheck's shared backend.
struct MenoAIAnalysisResponse: Decodable, Sendable {
    var resultType: String
    var confidencePercentage: Int
    var certaintyPercentage: Int
    var controlLineDetected: Bool
    var testLineDetected: Bool
    var testControlRatio: Double
    var lineStrength: Double
    var observedLinePattern: String?
    var nextBestAction: String?
    var imageQualityStatus: String
    var explanation: String
    var trendSummary: String
    var guidance: String
    var qualityNotes: [String]
    var model: String?

    var resultLabel: String {
        switch resultType {
        case "low": "Low"
        case "borderline": "Borderline"
        case "elevated": "Elevated"
        case "invalid": "Invalid test"
        default: "Unclear"
        }
    }
}

/// `low` / `borderline` / `elevated` / `notSure` — mirrors LineCheck's recheck `userStatedOpinion`.
enum MenoUserStatedOpinion: String, Sendable {
    case low, borderline, elevated, notSure
}

private struct MenoAIAnalysisRequest: Encodable, Sendable {
    var imageBase64: String
    var userStatedOpinion: String?
}

private struct MenoAIErrorBody: Decodable { let error: String?; let detail: String? }

enum MenoAIAnalysisServiceError: LocalizedError {
    case endpointNotConfigured
    case imageEncodingFailed
    case badStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured: "The AI test reader isn't set up yet."
        case .imageEncodingFailed: "Could not prepare this photo for analysis."
        case .badStatus(_, let message): message
        case .invalidResponse: "Could not read this test. Please try again."
        }
    }
}

final class MenoAIAnalysisService: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func analyse(image: UIImage, userStatedOpinion: MenoUserStatedOpinion? = nil) async throws -> MenoAIAnalysisResponse {
        guard let endpoint = Self.endpoint else { throw MenoAIAnalysisServiceError.endpointNotConfigured }
        let resized = MenoImageHelpers.resized(image, maxDimension: 1400)
        guard let imageBase64 = resized.jpegData(compressionQuality: 0.92)?.base64EncodedString() else {
            throw MenoAIAnalysisServiceError.imageEncodingFailed
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Self.clientToken {
            request.setValue(token, forHTTPHeaderField: "x-menoplan-client-token")
        }
        request.httpBody = try JSONEncoder().encode(MenoAIAnalysisRequest(imageBase64: imageBase64, userStatedOpinion: userStatedOpinion?.rawValue))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MenoAIAnalysisServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = http.statusCode >= 500
                ? "The AI test reader is temporarily unavailable. Please try again later."
                : ((try? decoder.decode(MenoAIErrorBody.self, from: data))?.error ?? "Could not read this test.")
            throw MenoAIAnalysisServiceError.badStatus(http.statusCode, message)
        }

        return try decoder.decode(MenoAIAnalysisResponse.self, from: data)
    }

    private static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MenoAIEndpoint") as? String else { return nil }
        guard !value.isEmpty, !value.contains("YOUR_") else { return nil }
        return URL(string: value)
    }

    private static var clientToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MenoAIClientToken") as? String else { return nil }
        guard !value.isEmpty, !value.contains("OPTIONAL_SHARED_SECRET") else { return nil }
        return value
    }
}

enum MenoImageHelpers {
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    private static let ciContext = CIContext()

    /// `brightness` in roughly -0.3...0.3, `contrast` in roughly 0.7...1.6 — the same
    /// CIColorControls knobs LineCheck's Manual Check adjustment screen exposes.
    static func adjusted(_ image: UIImage, brightness: Double, contrast: Double) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter?.setValue(contrast, forKey: kCIInputContrastKey)
        guard let output = filter?.outputImage,
              let cgImage = ciContext.createCGImage(output, from: ciImage.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
