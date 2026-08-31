import Foundation
import Combine
import CloudKit

@MainActor
final class MenoStore: ObservableObject {
    @Published var selectedTab = 0
    @Published var entries: [TimelineEntry] = timelineDays.flatMap(\.entries) { didSet { stateDidChange() } }
    @Published var selectedCalendarDate = Calendar.current.startOfDay(for: .now)
    @Published var reminderEnabled = true
    @Published private(set) var dailyRecords: [String: MenoDailyRecord] = [:]
    @Published private(set) var fshReadings: [MenoFSHReading] = []
    @Published private(set) var experiments: [MenoExperiment] = []
    @Published var profile = MenoProfile() { didSet { stateDidChange() } }
    @Published private(set) var iCloudStatus = "Checking iCloud…"

    private var isApplyingCloudPayload = false
    private var cloudObserver: NSObjectProtocol?
    private static let cloudPayloadKey = "menocheck.cloudPayload.v1"
    private static let localModifiedKey = "menocheck.localModifiedAt"

    /// Simulator builds signed without capabilities should remain fully usable. On a
    /// provisioned device these checks pass and the private iCloud store is enabled.
    private var cloudStore: NSUbiquitousKeyValueStore? {
        Self.canUseICloud ? .default : nil
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "menocheck.entries"),
           let decoded = try? JSONDecoder().decode([TimelineEntry].self, from: data) {
            entries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "menocheck.dailyRecords"),
           let decoded = try? JSONDecoder().decode([String: MenoDailyRecord].self, from: data) {
            dailyRecords = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "menocheck.profile"),
           let decoded = try? JSONDecoder().decode(MenoProfile.self, from: data) {
            profile = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "menocheck.fshReadings"),
           let decoded = try? JSONDecoder().decode([MenoFSHReading].self, from: data) {
            fshReadings = decoded
        } else if entries.contains(where: { $0.title.localizedCaseInsensitiveContains("FSH") }) {
            // Keep the supplied demonstration history internally consistent on first launch.
            fshReadings = [0.42, 0.55, 0.71].enumerated().map { index, strength in
                MenoFSHReading(date: Calendar.current.date(byAdding: .day, value: -(2 - index) * 7, to: .now) ?? .now, testLineStrength: strength)
            }
            persistJourney()
        }
        if let data = UserDefaults.standard.data(forKey: "menocheck.experiments"),
           let decoded = try? JSONDecoder().decode([MenoExperiment].self, from: data) {
            experiments = decoded
        }
        configureICloudSync()
    }

    /// Saves a reading produced by a real `MenoAIAnalysisService.analyse(image:)` call.
    func addFSHReading(from response: MenoAIAnalysisResponse) {
        let reading = MenoFSHReading(
            date: .now,
            testLineStrength: response.testControlRatio,
            resultType: response.resultType,
            certaintyPercentage: response.certaintyPercentage,
            explanation: response.explanation,
            guidance: response.guidance
        )
        fshReadings.insert(reading, at: 0)
        entries.insert(TimelineEntry(time: Date.now.formatted(date: .omitted, time: .shortened),
                                     title: "FSH reading saved",
                                     detail: response.explanation,
                                     icon: "viewfinder"), at: 0)
    }

    func addSymptom(_ symptom: Symptom, intensity: Intensity, note: String) {
        let detail = ([intensity.label, note.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }).joined(separator: " · ")
        entries.insert(TimelineEntry(time: Date.now.formatted(date: .omitted, time: .shortened), title: symptom.rawValue, detail: detail, icon: symptom.icon), at: 0)
    }

    func record(for date: Date) -> MenoDailyRecord {
        dailyRecords[Self.dayKey(date)] ?? MenoDailyRecord(date: date)
    }

    func save(_ record: MenoDailyRecord) {
        dailyRecords[Self.dayKey(record.date)] = record
        persistJourney()
        let pieces = [record.hotFlashes > 0 ? "\(record.hotFlashes) hot flashes" : nil,
                      record.sleepHours > 0 ? "\(String(format: "%.1f", record.sleepHours))h sleep" : nil,
                      record.bleeding ? "bleeding logged" : nil].compactMap { $0 }
        if !pieces.isEmpty {
            entries.removeAll { $0.title == "Daily record" && $0.time == record.date.formatted(date: .omitted, time: .shortened) }
            entries.insert(TimelineEntry(time: record.date.formatted(date: .omitted, time: .shortened), title: "Daily record", detail: pieces.joined(separator: " · "), icon: "calendar"), at: 0)
        }
    }

    func applyHealthSleep(_ hours: Double, to date: Date = .now) {
        var updated = record(for: date)
        updated.sleepHours = hours
        save(updated)
    }

    func startExperiment(_ experiment: MenoExperiment) {
        guard !experiments.contains(where: { !$0.isComplete }) else { return }
        experiments.insert(experiment, at: 0)
        persistJourney()
    }

    func completeExperiment(_ experiment: MenoExperiment, reflection: String) {
        guard let index = experiments.firstIndex(where: { $0.id == experiment.id }) else { return }
        experiments[index].completedAt = .now
        experiments[index].reflection = reflection
        persistJourney()
    }

    static func dayKey(_ date: Date) -> String { date.formatted(.iso8601.year().month().day()) }

    private func stateDidChange() {
        guard !isApplyingCloudPayload else { return }
        persistJourney()
    }

    private var localModifiedAt: Date {
        get { UserDefaults.standard.object(forKey: Self.localModifiedKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Self.localModifiedKey) }
    }

    private func persistJourney(syncToICloud: Bool = true) {
        if let data = try? JSONEncoder().encode(dailyRecords) { UserDefaults.standard.set(data, forKey: "menocheck.dailyRecords") }
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "menocheck.profile") }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: "menocheck.entries") }
        if let data = try? JSONEncoder().encode(fshReadings) { UserDefaults.standard.set(data, forKey: "menocheck.fshReadings") }
        if let data = try? JSONEncoder().encode(experiments) { UserDefaults.standard.set(data, forKey: "menocheck.experiments") }

        guard syncToICloud, !isApplyingCloudPayload else { return }
        let modifiedAt = Date.now
        localModifiedAt = modifiedAt
        let payload = MenoCloudPayload(updatedAt: modifiedAt, entries: entries, dailyRecords: dailyRecords, fshReadings: fshReadings, experiments: experiments, profile: profile)
        guard let data = try? JSONEncoder().encode(payload), data.count < 900_000 else {
            iCloudStatus = "iCloud sync paused — record is too large"
            return
        }
        guard let cloudStore else {
            iCloudStatus = "iCloud will connect in a signed build"
            return
        }
        cloudStore.set(data, forKey: Self.cloudPayloadKey)
        cloudStore.synchronize()
    }

    private func configureICloudSync() {
        guard let cloudStore else {
            iCloudStatus = "iCloud will connect in a signed build"
            return
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.importCloudPayloadIfNewer() }
        }
        cloudStore.synchronize()
        importCloudPayloadIfNewer()
        persistJourney()
        Task { await refreshICloudStatus() }
    }

    private func importCloudPayloadIfNewer() {
        guard let cloudStore,
              let data = cloudStore.data(forKey: Self.cloudPayloadKey),
              let payload = try? JSONDecoder().decode(MenoCloudPayload.self, from: data),
              payload.updatedAt > localModifiedAt else { return }

        isApplyingCloudPayload = true
        entries = payload.entries
        dailyRecords = payload.dailyRecords
        fshReadings = payload.fshReadings
        experiments = payload.experiments
        profile = payload.profile
        localModifiedAt = payload.updatedAt
        persistJourney(syncToICloud: false)
        isApplyingCloudPayload = false
    }

    func refreshICloudStatus() async {
        guard Self.canUseICloud else {
            iCloudStatus = "iCloud will connect in a signed build"
            return
        }
        let status = await withCheckedContinuation { continuation in
            CKContainer(identifier: "iCloud.com.menocheck.app").accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .available: iCloudStatus = "iCloud connected"
        case .noAccount: iCloudStatus = "Sign in to iCloud to sync"
        case .restricted: iCloudStatus = "iCloud is restricted on this device"
        case .temporarilyUnavailable: iCloudStatus = "iCloud is temporarily unavailable"
        case .couldNotDetermine: iCloudStatus = "iCloud status unavailable"
        @unknown default: iCloudStatus = "iCloud status unavailable"
        }
    }

    private static var canUseICloud: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}

private struct MenoCloudPayload: Codable {
    let updatedAt: Date
    let entries: [TimelineEntry]
    let dailyRecords: [String: MenoDailyRecord]
    let fshReadings: [MenoFSHReading]
    let experiments: [MenoExperiment]
    let profile: MenoProfile
}

struct MenoFSHReading: Identifiable, Codable {
    var id = UUID()
    let date: Date
    /// The AI's `testControlRatio` for a real reading; a rough proxy value for seed/demo data.
    let testLineStrength: Double
    var resultType: String = "unclear"
    var certaintyPercentage: Int = 0
    var explanation: String = ""
    var guidance: String = ""

    private enum CodingKeys: String, CodingKey {
        case id, date, testLineStrength, resultType, certaintyPercentage, explanation, guidance
    }

    init(id: UUID = UUID(), date: Date, testLineStrength: Double, resultType: String = "unclear",
         certaintyPercentage: Int = 0, explanation: String = "", guidance: String = "") {
        self.id = id
        self.date = date
        self.testLineStrength = testLineStrength
        self.resultType = resultType
        self.certaintyPercentage = certaintyPercentage
        self.explanation = explanation
        self.guidance = guidance
    }

    // Backward-compatible with FSH readings persisted before these fields existed.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try values.decode(Date.self, forKey: .date)
        testLineStrength = try values.decode(Double.self, forKey: .testLineStrength)
        resultType = try values.decodeIfPresent(String.self, forKey: .resultType) ?? "unclear"
        certaintyPercentage = try values.decodeIfPresent(Int.self, forKey: .certaintyPercentage) ?? 0
        explanation = try values.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        guidance = try values.decodeIfPresent(String.self, forKey: .guidance) ?? ""
    }
}

struct MenoExperiment: Identifiable, Codable {
    let id: UUID
    let title: String
    let detail: String
    let startedAt: Date
    let durationDays: Int
    var completedAt: Date?
    var reflection: String = ""

    init(id: UUID = UUID(), title: String, detail: String, startedAt: Date = .now, durationDays: Int = 7) {
        self.id = id
        self.title = title
        self.detail = detail
        self.startedAt = startedAt
        self.durationDays = durationDays
    }

    var endDate: Date { Calendar.current.date(byAdding: .day, value: durationDays, to: startedAt) ?? startedAt }
    var isComplete: Bool { completedAt != nil }
}

struct MenoDailyRecord: Identifiable, Codable {
    var date: Date
    var hotFlashes = 0
    var sleepHours = 0.0
    var bleeding = false
    var hrtTaken = false
    var note = ""
    var id: String { date.formatted(.iso8601.year().month().day()) }
}

struct MenoProfile: Codable {
    var name = "Alex"
    var age = ""
    var stage = "Not set"
    var lastPeriod = Date()
    var usesHRT = false
    var contraception = "Not set"
    var mainGoal = "Understand my symptoms"
    var hrtRegimen = ""
    var hrtReviewNotes = ""
    var hrtLastChanged: Date?

    private enum CodingKeys: String, CodingKey {
        case name, age, stage, lastPeriod, usesHRT, contraception, mainGoal, hrtRegimen, hrtReviewNotes, hrtLastChanged
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Alex"
        age = try values.decodeIfPresent(String.self, forKey: .age) ?? ""
        stage = try values.decodeIfPresent(String.self, forKey: .stage) ?? "Not set"
        lastPeriod = try values.decodeIfPresent(Date.self, forKey: .lastPeriod) ?? .now
        usesHRT = try values.decodeIfPresent(Bool.self, forKey: .usesHRT) ?? false
        contraception = try values.decodeIfPresent(String.self, forKey: .contraception) ?? "Not set"
        mainGoal = try values.decodeIfPresent(String.self, forKey: .mainGoal) ?? "Understand my symptoms"
        hrtRegimen = try values.decodeIfPresent(String.self, forKey: .hrtRegimen) ?? ""
        hrtReviewNotes = try values.decodeIfPresent(String.self, forKey: .hrtReviewNotes) ?? ""
        hrtLastChanged = try values.decodeIfPresent(Date.self, forKey: .hrtLastChanged)
    }
}

enum Symptom: String, CaseIterable, Identifiable, Sendable {
    case hotFlash = "Hot flash"
    case nightSweat = "Night sweat"
    case sleep = "Sleep"
    case brainFog = "Brain fog"
    case mood = "Mood"
    case bleeding = "Bleeding"
    case joints = "Aches"
    case hrt = "HRT change"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hotFlash: "thermometer.sun"
        case .nightSweat: "moon.stars"
        case .sleep: "bed.double"
        case .brainFog: "cloud"
        case .mood: "heart"
        case .bleeding: "drop"
        case .joints: "figure.walk"
        case .hrt: "pills"
        }
    }
}

/// Intensity is a named scale, not a bare number — "3" means nothing to a clinician
/// reading the export, and nothing to the person logging it six weeks later.
enum Intensity: Int, CaseIterable, Identifiable, Sendable {
    case mild = 1, noticeable, moderate, strong, severe

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .mild: "Mild"
        case .noticeable: "Noticeable"
        case .moderate: "Moderate"
        case .strong: "Strong"
        case .severe: "Severe"
        }
    }
}

/// One day of logged data.
/// `id` is the day index, never the label — two weekdays share an initial, and using the
/// label as the identity silently merged Tuesday into Thursday in the charts.
struct SymptomDay: Identifiable, Sendable {
    let id: Int
    let label: String
    let hotFlashes: Int
    let sleepHours: Double
}

let weekOfSymptoms: [SymptomDay] = [
    SymptomDay(id: 0, label: "Mon", hotFlashes: 1, sleepHours: 7.4),
    SymptomDay(id: 1, label: "Tue", hotFlashes: 2, sleepHours: 6.8),
    SymptomDay(id: 2, label: "Wed", hotFlashes: 0, sleepHours: 7.9),
    SymptomDay(id: 3, label: "Thu", hotFlashes: 3, sleepHours: 5.6),
    SymptomDay(id: 4, label: "Fri", hotFlashes: 1, sleepHours: 7.1),
    SymptomDay(id: 5, label: "Sat", hotFlashes: 2, sleepHours: 6.2),
    SymptomDay(id: 6, label: "Sun", hotFlashes: 1, sleepHours: 7.6),
]

extension Array where Element == SymptomDay {
    var hotFlashTotal: Int { reduce(0) { $0 + $1.hotFlashes } }
    var hotFlashPeak: Int { map(\.hotFlashes).max() ?? 0 }
}

struct TimelineEntry: Identifiable, Sendable, Codable {
    var id = UUID()
    let time: String
    let title: String
    let detail: String?
    let icon: String
}

struct TimelineDay: Identifiable, Sendable {
    let id = UUID()
    let heading: String
    let entries: [TimelineEntry]
}

let timelineDays: [TimelineDay] = [
    TimelineDay(heading: "Today · Thursday 15 May", entries: [
        TimelineEntry(time: "08:42", title: "FSH reading saved", detail: "Reading 3 of 5 · good image quality", icon: "viewfinder"),
        TimelineEntry(time: "14:18", title: "Hot flash", detail: "Moderate · about 4 minutes", icon: "thermometer.sun"),
        TimelineEntry(time: "22:05", title: "Night sweat", detail: "Strong · woke twice", icon: "moon.stars"),
    ]),
    TimelineDay(heading: "Wednesday 14 May", entries: [
        TimelineEntry(time: "07:30", title: "Sleep", detail: "5h 40m · restless", icon: "bed.double"),
        TimelineEntry(time: "13:05", title: "Brain fog", detail: "Noticeable, through the afternoon", icon: "cloud"),
        TimelineEntry(time: "19:00", title: "HRT dose noted", detail: "No change to routine", icon: "pills"),
    ]),
]

struct Article: Identifiable, Sendable {
    let id = UUID()
    let category: String
    let title: String
    let summary: String
    let minutes: Int
}

let articles: [Article] = [
    Article(category: "Hormones", title: "Understanding FSH",
            summary: "What this hormone can — and cannot — tell you about where you are.", minutes: 4),
    Article(category: "Your body", title: "What changes during perimenopause?",
            summary: "A practical guide to a cycle that stops behaving predictably.", minutes: 7),
    Article(category: "Care", title: "Preparing for your appointment",
            summary: "Bring the story, not just the symptoms.", minutes: 5),
    Article(category: "Tracking", title: "What is worth writing down?",
            summary: "Build a record that is actually useful to you and your clinician.", minutes: 3),
]
