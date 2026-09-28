import Foundation

struct AssistantRecentScanContext: Encodable, Sendable {
    var date: String
    var testType: String
    var resultType: String
    var certaintyPercentage: Int
    var confidencePercentage: Int
    var lineStrength: Double
    var testControlRatio: Double
    var analysisMode: String
    var notes: String
    var autoEnhancementSummary: String
}

struct AssistantReminderContext: Encodable, Sendable {
    var title: String
    var reminderType: String
    var scheduledDate: String
    var isCompleted: Bool
}

struct AssistantUserContext: Encodable, Sendable {
    var userName: String?
    var trackingFocus: String
    var menopauseStage: String
    /// The HRT the person has said they use (names only, never doses).
    var hrtRegimen: [String] = []
    var hrtStartDate: String? = nil
    var hrtDose: String? = nil
    var hrtLastChanged: String? = nil
    /// The symptoms the person said affect them most.
    var focusSymptoms: [String] = []
    var nextAppointment: String? = nil
    var expectedPeriodDate: String?
    var lastPeriodStartDate: String?
    var averageCycleLength: Int?
    var cycleSummaries: [String] = []
    var dailyTrackingSummaries: [String] = []
    var cycleLengthVariabilityDays: Int? = nil
    var isIrregularCycle: Bool? = nil
    var autoRemindersEnabled: Bool? = nil
    var temperatureUnit: String? = nil
    /// Plain-English reasoning behind the current predicted date/window,
    /// identical to what the app's own "Why?" disclosure shows - so Luna
    /// explains predictions using the same grounds the UI already gives the
    /// user, instead of inventing its own reasoning.
    var predictionExplanationBullets: [String] = []
    /// Personalisation answers (age, regularity, conditions, recent birth
    /// control) so Luna doesn't have to ask again.
    var healthProfile: [String] = []
    /// Observations CycleSignalsEngine found in this person's data (temperature
    /// shift, late period, short sleep, contraception in Health...), filtered
    /// to the surface asking. The same wording the app shows on screen.
    var signals: [String] = []
    /// Recent weight, sleep, resting heart rate, HRV, activity and water from
    /// the daily log and Apple Health, as short aggregates rather than raw days.
    var bodyAndActivity: [String] = []
}

struct AssistantConversationContext: Encodable, Sendable {
    var role: String
    var text: String
}

struct AssistantRequest: Encodable, Sendable {
    var message: String
    var mode: String?
    var userSafetyId: String
    var conversation: [AssistantConversationContext]
    var recentScans: [AssistantRecentScanContext]
    var reminders: [AssistantReminderContext]
    var userContext: AssistantUserContext
}

struct AssistantResponse: Decodable, Sendable {
    var reply: String
    var suggestions: [AssistantSuggestion]
    var model: String?
}

struct AssistantSuggestion: Codable, Hashable, Identifiable, Sendable {
    /// Must include every kind api/assistant.js can return (SUGGESTION_KINDS).
    enum Kind: String, Codable, Sendable {
        case fshScan
        case logSymptom
        case careSummary
        case reminder
        case ovulationScan
        case calendar
        case settingUpdate
        case history
        case compare
        case cycleTiming
    }

    enum SettingKey: String, Codable, Sendable {
        case expectedPeriodDate
        case lastPeriodStartDate
        case averageCycleLength
    }

    var id: String {
        [kind.rawValue, title, String(offsetHours ?? 0), settingKey?.rawValue ?? "", proposedValue ?? ""]
            .joined(separator: "-")
    }
    var kind: Kind
    var title: String
    var detail: String
    var offsetHours: Int?
    var reminderType: String?
    var settingKey: SettingKey?
    var proposedValue: String?
}

private struct AssistantErrorBody: Decodable {
    let error: String?
}

enum AssistantServiceError: LocalizedError {
    case endpointNotConfigured
    case badStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured: "Luna is temporarily unavailable."
        case .badStatus(_, let message): message
        case .invalidResponse: "Luna could not answer that request. Please try again."
        }
    }
}

/// Single source of truth for what Luna's userContext contains - used by
/// both the main "Ask Luna" chat and AI Compare. These used to be built by
/// two independently hand-written functions, and Compare's silently fell
/// behind: it was missing cycle summaries, daily tracking summaries, cycle
/// irregularity, auto-reminders state, and temperature unit entirely,
/// despite the shared struct having always carried those fields.
enum AssistantContextBuilder {
    static func healthProfileSummary(_ profile: HealthProfile) -> [String] {
        var lines: [String] = []
        if let age = profile.age() { lines.append("age=\(age)") }
        if let regularity = profile.regularity { lines.append("recentPeriods=\(regularity.rawValue)") }
        if !profile.conditions.isEmpty { lines.append("healthHistory=\(profile.conditions.map(\.title).sorted().joined(separator: ", "))") }
        if let other = profile.otherCondition, !other.isEmpty { lines.append("otherConditionDescribedByUser=\(other)") }
        if let birthControl = profile.birthControl { lines.append("hormonalContraception=\(birthControl.rawValue)") }
        if let heightCm = profile.heightCm { lines.append("heightCm=\(Int(heightCm.rounded()))") }
        if let weightKg = profile.weightKg { lines.append(String(format: "weightKg=%.1f", weightKg)) }
        if let bmi = profile.bmi, let category = profile.bmiCategory { lines.append(String(format: "bmi=%.1f (%@)", bmi, category.rawValue)) }
        return lines
    }

    static func userContext(
        settings: UserSettings,
        cycles: [CycleRecord],
        dailyLogs: [DailyFertilityLog],
        periodEvents: [PeriodEvent],
        maximumCycleSummaries: Int = 3,
        maximumDailySummaries: Int = 14,
        allDailyLogs: [DailyFertilityLog]? = nil,
        healthMetrics: [DailyHealthMetrics] = [],
        scans: [Scan] = [],
        signalSurface: CycleSignalSurface = .luna
    ) -> AssistantUserContext {
        let formatter = ISO8601DateFormatter()
        let realPeriods = periodEvents.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        let variability = CycleTrackingService.cycleLengthVariability(from: realPeriods)
        let realCycles = cycles.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        let activeCycle = CycleTrackingService.activeCycle(records: realCycles)
        let currentWindow = CycleTrackingService.window(records: realCycles, periods: realPeriods, settings: settings)
        let explanationBullets = currentWindow
            .map { PredictionExplanationBuilder.bullets(window: $0, cycle: activeCycle, settings: settings) } ?? []
        // Signals need the whole cycle's logs (a temperature shift spans
        // weeks), even when only the last few days are summarised below.
        let signalLogs = allDailyLogs ?? dailyLogs
        let signals = CycleSignalsEngine.signals(for: signalSurface, CycleSignalInputs(
            window: currentWindow,
            activeCycle: activeCycle,
            logs: signalLogs,
            metrics: healthMetrics,
            scans: scans,
            profile: settings.healthProfile
        ))
        return AssistantUserContext(
            userName: settings.userName.isEmpty ? nil : settings.userName,
            trackingFocus: settings.trackingFocus.rawValue,
            menopauseStage: settings.menopauseStage.rawValue,
            hrtRegimen: settings.hrtRegimen,
            hrtStartDate: settings.hrtStartDate.map { formatter.string(from: $0) },
            hrtDose: settings.hrtDoseText,
            hrtLastChanged: settings.hrtLastChangedDate.map { formatter.string(from: $0) },
            focusSymptoms: settings.focusSymptoms,
            nextAppointment: settings.upcomingAppointment.map { formatter.string(from: $0) },
            expectedPeriodDate: settings.expectedPeriodDate.map { formatter.string(from: $0) },
            lastPeriodStartDate: settings.lastPeriodStartDate.map { formatter.string(from: $0) },
            averageCycleLength: settings.averageCycleLengthValue,
            cycleSummaries: cycles.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }.prefix(maximumCycleSummaries).map { cycle in
                let end = cycle.endDate.map { formatter.string(from: $0) } ?? "active"
                let ovulation = cycle.effectiveOvulationDate.map { formatter.string(from: $0) } ?? "unconfirmed"
                return "start=\(formatter.string(from: cycle.startDate)); end=\(end); ovulation=\(ovulation); source=\(cycle.startSource.rawValue)"
            },
            dailyTrackingSummaries: dailyLogs
                .filter { !$0.notes.contains("[LineCheck Screenshot Sample]") && $0.hasContent }
                .prefix(maximumDailySummaries)
                .map { log in
                    var parts = ["date=\(formatter.string(from: log.date))"]
                    if let impact = log.dayImpact { parts.append("dayImpact=\(impact.rawValue)") }
                    if let flow = log.flowIntensity { parts.append("flow=\(flow.rawValue)") }
                    if let hot = log.hotFlushCount { parts.append("hotFlushes=\(hot)") }
                    if let sweats = log.nightSweatCount { parts.append("nightSweats=\(sweats)") }
                    if let severity = log.vasomotorSeverity { parts.append("flushSeverity=\(severity.rawValue)") }
                    if let sleep = log.sleepQuality { parts.append("sleep=\(sleep.rawValue)") }
                    if !log.hrtTaken.isEmpty { parts.append("hrtTaken=\(log.hrtTaken.joined(separator: ","))") }
                    if let wrist = log.wristTemperatureCelsius { parts.append("appleWatchWristTemperature=\(String(format: "%.2f°C", wrist))") }
                    if let weight = log.weightKg { parts.append(String(format: "weightKg=%.1f", weight)) }
                    if let water = log.waterMl { parts.append("waterMl=\(Int(water.rounded()))") }
                    if !log.healthKitObservations.isEmpty { parts.append("appleHealth=\(log.healthKitObservations.joined(separator: ","))") }
                    if !log.symptoms.isEmpty { parts.append("symptoms=\(log.ratedSymptomsText)") }
                    if !log.moods.isEmpty { parts.append("moods=\(log.moods.joined(separator: ","))") }
                    if !log.supplements.isEmpty { parts.append("supplements=\(log.supplements.joined(separator: ","))") }
                    if !log.notes.isEmpty { parts.append("notes=\(String(log.notes.prefix(120)))") }
                    return parts.joined(separator: "; ")
                },
            cycleLengthVariabilityDays: variability,
            isIrregularCycle: variability.map { $0 >= FertilityWindowCalculator.irregularCycleThresholdDays },
            autoRemindersEnabled: settings.autoRemindersEnabled,
            temperatureUnit: settings.temperatureUnit.rawValue,
            predictionExplanationBullets: explanationBullets,
            healthProfile: healthProfileSummary(settings.healthProfile),
            signals: signals.prefix(6).map(\.lunaFact),
            bodyAndActivity: CycleSignalsEngine.bodySummary(logs: signalLogs, metrics: healthMetrics)
        )
    }

    /// Matches the server's validatePayload truncation limits (api/assistant.js,
    /// textFieldsExceed) - a scan whose notes/autoEnhancementSummary exceed 500
    /// characters would otherwise get the whole request rejected with a 400.
    static func recentScan(_ scan: Scan, includeFreeText: Bool = true) -> AssistantRecentScanContext {
        AssistantRecentScanContext(
            date: ISO8601DateFormatter().string(from: scan.createdAt),
            testType: scan.testType.rawValue,
            resultType: scan.resultType.rawValue,
            certaintyPercentage: scan.certaintyPercentage,
            confidencePercentage: scan.confidencePercentage,
            lineStrength: scan.lineStrength,
            testControlRatio: scan.testControlRatio,
            analysisMode: scan.analysisMode.rawValue,
            notes: includeFreeText ? String(scan.notes.prefix(160)) : "",
            autoEnhancementSummary: includeFreeText ? String(scan.autoEnhancementSummary.prefix(160)) : ""
        )
    }

    /// Matches the server's reminders.length > 8 cap (api/assistant.js).
    /// Excludes completed reminders - otherwise one finished hours ago can
    /// still read as pending to Luna, who then references it as upcoming.
    static func reminders(_ reminders: [Reminder], maximum: Int = 4) -> [AssistantReminderContext] {
        reminders
            .filter { !$0.isCompleted && $0.scheduledDate >= Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .distantPast }
            .prefix(maximum)
            .map {
                AssistantReminderContext(
                    title: String($0.title.prefix(120)),
                    reminderType: $0.reminderType.rawValue,
                    scheduledDate: ISO8601DateFormatter().string(from: $0.scheduledDate),
                    isCompleted: $0.isCompleted
                )
            }
    }
}

final class AssistantService: @unchecked Sendable {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func reply(
        message: String,
        conversation: [AssistantConversationContext] = [],
        recentScans: [AssistantRecentScanContext],
        reminders: [AssistantReminderContext],
        userContext: AssistantUserContext,
        mode: String? = nil
    ) async throws -> AssistantResponse {
        guard let endpoint = Self.endpoint else { throw AssistantServiceError.endpointNotConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Self.clientToken {
            request.setValue(token, forHTTPHeaderField: "x-menoplan-client-token")
        }

        let payload = AssistantRequest(
            message: message,
            mode: mode,
            userSafetyId: Self.userSafetyId,
            conversation: conversation,
            recentScans: recentScans,
            reminders: reminders,
            userContext: userContext
        )
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssistantServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // The server's real error (e.g. a validatePayload rejection like
            // "Too many recent scans") was previously discarded here in
            // favor of an always-identical generic message, which turned
            // every failure - including ones caused by a real client bug -
            // into an unreconstructable dead end. Surface it when present.
            let serverMessage = (try? decoder.decode(AssistantErrorBody.self, from: data))?.error
            #if DEBUG
            print("AssistantService: \(http.statusCode) - \(serverMessage ?? "<no error body>")")
            #endif
            throw AssistantServiceError.badStatus(
                http.statusCode,
                serverMessage ?? "Luna is temporarily unavailable. Please try again."
            )
        }

        return try decoder.decode(AssistantResponse.self, from: data)
    }

    private static var endpoint: URL? {
        guard let analysisValue = Bundle.main.object(forInfoDictionaryKey: "LineCheckAIEndpoint") as? String else { return nil }
        guard !analysisValue.isEmpty else { return nil }
        // The assistant lives beside the analysis route: /api/analyse-fsh -> /api/assistant.
        return URL(string: analysisValue)?.deletingLastPathComponent().appendingPathComponent("assistant")
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
}
