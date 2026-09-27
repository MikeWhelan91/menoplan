import Foundation
import SwiftData

struct AssistantChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Hashable, Codable {
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date
    var suggestions: [AssistantSuggestion] = []

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date, suggestions: [AssistantSuggestion] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.suggestions = suggestions
    }
}

private let assistantStarterMessage = AssistantChatMessage(
    role: .assistant,
    text: "Ask me about saved tests, when to test again, ovulation-test timing, or cycle dates.",
    createdAt: .now
)

private func assistantStarterMessage(for userName: String) -> AssistantChatMessage {
    let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    let greeting = name.isEmpty ? "Hi — I’m Luna." : "Hi \(name) — I’m Luna."
    return AssistantChatMessage(
        role: .assistant,
        text: "\(greeting) Ask me about saved tests, when to test again, ovulation-test timing, or cycle dates.",
        createdAt: .now
    )
}

@Model
final class AssistantConversation {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var title: String = "New chat"
    var preview: String = "Start a new conversation with Luna."
    var messagesData: Data = Data()

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String = "New chat",
        preview: String = "Start a new conversation with Luna.",
        messages: [AssistantChatMessage] = [assistantStarterMessage]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.preview = preview
        self.messagesData = (try? JSONEncoder().encode(messages)) ?? Data()
    }

    var messages: [AssistantChatMessage] {
        get {
            (try? JSONDecoder().decode([AssistantChatMessage].self, from: messagesData)) ?? [assistantStarterMessage]
        }
        set {
            messagesData = (try? JSONEncoder().encode(newValue)) ?? messagesData
        }
    }
}

@MainActor
@Observable
final class AssistantViewModel {
    static let maximumMessageLength = 2_000
    let assistantName = "Luna"
    var messages: [AssistantChatMessage] = []
    var composerText = ""
    var isSending = false
    var errorMessage: String?

    private let service: AssistantService
    init(service: AssistantService = AssistantService()) {
        self.service = service
        messages = [assistantStarterMessage]
    }

    func starterPrompts(for focus: TrackingFocus) -> [String] {
        switch focus {
        case .pregnancy:
            ["When should I retest?", "Do my recent scans look stronger?", "I’m spiralling a bit about these results"]
        case .ovulation:
            ["When should I test again today?", "Does this look close to my strongest result?", "When should I take ovulation tests this week?"]
        case .both:
            ["What should I do next based on my recent tests?", "Should I set a reminder?", "I’m worried this cycle isn’t going well"]
        }
    }

    func canUseAssistant(settings: UserSettings) -> Bool {
        settings.proUnlocked
    }

    func load(messages: [AssistantChatMessage], userName: String = "") {
        self.messages = messages.isEmpty ? [assistantStarterMessage(for: userName)] : messages
    }

    func persist(into conversation: AssistantConversation) {
        conversation.messages = messages
        conversation.updatedAt = messages.last?.createdAt ?? .now
        conversation.preview = messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).prefixString(96) ?? "Start a new conversation with Luna."
        if let firstUserMessage = messages.first(where: { $0.role == .user })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           firstUserMessage.isEmpty == false {
            conversation.title = firstUserMessage.prefixString(36)
        } else {
            conversation.title = "New chat"
        }
    }

    func send(
        text: String,
        settings: UserSettings,
        recentScans: [AssistantRecentScanContext],
        reminders: [AssistantReminderContext],
        userContext: AssistantUserContext
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.count <= Self.maximumMessageLength else {
            errorMessage = "Keep your message under \(Self.maximumMessageLength.formatted()) characters."
            return
        }
        guard isSending == false else { return }
        guard settings.proUnlocked else {
            errorMessage = "Luna is part of Pro."
            return
        }

        errorMessage = nil
        composerText = ""
        let conversation = messages
            .dropFirst()
            .suffix(2)
            .map { AssistantConversationContext(role: $0.role.rawValue, text: String($0.text.prefix(400))) }
        let pendingMessage = AssistantChatMessage(role: .user, text: trimmed, createdAt: .now)
        messages.append(pendingMessage)
        isSending = true

        do {
            let response = try await service.reply(
                message: trimmed,
                conversation: Array(conversation),
                recentScans: recentScans,
                reminders: reminders,
                userContext: userContext
            )
            messages.append(
                AssistantChatMessage(
                    role: .assistant,
                    text: response.reply,
                    createdAt: .now,
                    suggestions: response.suggestions
                )
            )
        } catch {
            messages.removeAll(where: { $0.id == pendingMessage.id })
            composerText = trimmed
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

}

private extension String {
    func prefixString(_ limit: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
