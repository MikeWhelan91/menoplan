import Foundation

struct MenoAssistantConversationTurn: Encodable, Sendable {
    var role: String
    var text: String
}

struct MenoAssistantReadingContext: Encodable, Sendable {
    var date: String
    var resultType: String
    var certaintyPercentage: Int
    var explanation: String
}

struct MenoAssistantSymptomContext: Encodable, Sendable {
    var date: String
    var hotFlashes: Int
    var sleepHours: Double
    var bleeding: Bool
    var note: String
}

struct MenoAssistantUserContext: Encodable, Sendable {
    var userName: String?
    var stage: String
    var usesHRT: Bool
    var mainGoal: String
}

private struct MenoAssistantRequest: Encodable, Sendable {
    var message: String
    var conversation: [MenoAssistantConversationTurn]
    var recentReadings: [MenoAssistantReadingContext]
    var recentSymptoms: [MenoAssistantSymptomContext]
    var userContext: MenoAssistantUserContext
}

struct MenoAssistantSuggestion: Decodable, Hashable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case fshScan, logSymptom, careSummary
    }
    var id: String { [kind.rawValue, title].joined(separator: "-") }
    var kind: Kind
    var title: String
    var detail: String
}

struct MenoAssistantResponse: Decodable, Sendable {
    var reply: String
    var suggestions: [MenoAssistantSuggestion]
    var model: String?
}

private struct MenoAssistantErrorBody: Decodable { let error: String? }

enum MenoAssistantServiceError: LocalizedError {
    case endpointNotConfigured
    case badStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured: "Luna isn't set up yet."
        case .badStatus(_, let message): message
        case .invalidResponse: "Luna could not answer that. Please try again."
        }
    }
}

final class MenoAssistantService: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func reply(
        message: String,
        conversation: [MenoAssistantConversationTurn],
        recentReadings: [MenoAssistantReadingContext],
        recentSymptoms: [MenoAssistantSymptomContext],
        userContext: MenoAssistantUserContext
    ) async throws -> MenoAssistantResponse {
        guard let endpoint = Self.endpoint else { throw MenoAssistantServiceError.endpointNotConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Self.clientToken {
            request.setValue(token, forHTTPHeaderField: "x-menoplan-client-token")
        }
        let payload = MenoAssistantRequest(
            message: message,
            conversation: conversation,
            recentReadings: recentReadings,
            recentSymptoms: recentSymptoms,
            userContext: userContext
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MenoAssistantServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? decoder.decode(MenoAssistantErrorBody.self, from: data))?.error
            throw MenoAssistantServiceError.badStatus(http.statusCode, serverMessage ?? "Luna is temporarily unavailable. Please try again.")
        }

        return try decoder.decode(MenoAssistantResponse.self, from: data)
    }

    private static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MenoAssistantEndpoint") as? String else { return nil }
        guard !value.isEmpty, !value.contains("YOUR_") else { return nil }
        return URL(string: value)
    }

    private static var clientToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MenoAIClientToken") as? String else { return nil }
        guard !value.isEmpty, !value.contains("OPTIONAL_SHARED_SECRET") else { return nil }
        return value
    }
}

/// Single source of truth for what gets sent to Luna as context, so the payload can't
/// silently drift out of sync with what the server-side prompt actually expects.
enum MenoAssistantContextBuilder {
    static func userContext(profile: MenoProfile) -> MenoAssistantUserContext {
        MenoAssistantUserContext(
            userName: profile.name.isEmpty ? nil : profile.name,
            stage: profile.stage,
            usesHRT: profile.usesHRT,
            mainGoal: profile.mainGoal
        )
    }

    /// Matches the server's recentReadings cap (api/menoplan-assistant.js, validatePayload).
    static func recentReadings(_ readings: [MenoFSHReading]) -> [MenoAssistantReadingContext] {
        let formatter = ISO8601DateFormatter()
        return readings.prefix(5).map {
            MenoAssistantReadingContext(
                date: formatter.string(from: $0.date),
                resultType: $0.resultType,
                certaintyPercentage: $0.certaintyPercentage,
                explanation: $0.explanation
            )
        }
    }

    /// Matches the server's recentSymptoms cap (api/menoplan-assistant.js, validatePayload).
    static func recentSymptoms(_ records: [MenoDailyRecord]) -> [MenoAssistantSymptomContext] {
        let formatter = ISO8601DateFormatter()
        return records
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map {
                MenoAssistantSymptomContext(
                    date: formatter.string(from: $0.date),
                    hotFlashes: $0.hotFlashes,
                    sleepHours: $0.sleepHours,
                    bleeding: $0.bleeding,
                    note: String($0.note.prefix(240))
                )
            }
    }
}
