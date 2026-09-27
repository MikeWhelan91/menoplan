import Foundation

/// Compiled into both the app and the widget extension. The app owns all the
/// cycle maths; the widget only reads this precomputed snapshot from the App
/// Group, so it never opens the SwiftData/CloudKit store itself.
enum WidgetShared {
    static let appGroupID = "group.com.menocheck.app"
    static let snapshotKey = "widgetSnapshot.v1"
    static let cycleWidgetKind = "LineCheckCycleWidget"
    static let todayPlanWidgetKind = "LineCheckTodayPlanWidget"
    static let urlScheme = "linecheck"
}

/// Deep links the widgets open. Kept here so the widget and RootView's
/// onOpenURL agree on the same hosts.
enum WidgetDeepLink: String {
    case calendar, setupCycle = "setup-cycle", scanPregnancy = "scan-pregnancy", scanOvulation = "scan-ovulation"

    var url: URL { URL(string: "\(WidgetShared.urlScheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == WidgetShared.urlScheme, let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}

struct WidgetSnapshot: Codable, Hashable {
    enum CycleState: String, Codable {
        case notSetUp, tracking, pregnant, ended
    }

    /// Mirrors CycleCalendarPhase without depending on app-only types.
    enum DayPhase: String, Codable {
        case period, predictedPeriod, opkWindow, fertile, ovulation, luteal
    }

    struct Cycle: Codable, Hashable {
        var cycleStart: Date
        var opkStart: Date
        var fertileStart: Date
        var fertileEnd: Date
        var ovulation: Date
        var nextPeriod: Date
        var isIrregular: Bool
        /// True when a saved test (not just the calendar) placed ovulation,
        /// so the widget can drop "estimated" wording.
        var ovulationConfirmed: Bool
    }

    struct LatestTest: Codable, Hashable {
        var date: Date
        var resultRaw: String
    }

    var cycleState: CycleState
    var cycle: Cycle?
    /// Keyed by `WidgetSnapshot.dayKey` - only non-regular days are stored.
    var dayPhases: [String: DayPhase]
    /// `dayKey`s of days with a saved (readable) test over the last ~60 days,
    /// so the widget can tell whether today's test is done.
    var pregnancyTestDays: Set<String>
    var ovulationTestDays: Set<String>
    var latestPregnancyTest: LatestTest?
    var latestOvulationTest: LatestTest?

    static let empty = WidgetSnapshot(
        cycleState: .notSetUp, cycle: nil,
        dayPhases: [:], pregnancyTestDays: [], ovulationTestDays: [], latestPregnancyTest: nil, latestOvulationTest: nil
    )

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func phase(on date: Date, calendar: Calendar = .current) -> DayPhase? {
        dayPhases[Self.dayKey(date, calendar: calendar)]
    }
}

enum WidgetSnapshotStore {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetShared.appGroupID) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: WidgetShared.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the stored value actually changed, so the caller only
    /// spends a widget reload when there is something new to show.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        let encoder = JSONEncoder()
        // Sorted so an unchanged snapshot encodes to identical bytes.
        encoder.outputFormatting = .sortedKeys
        guard let defaults, let data = try? encoder.encode(snapshot) else { return false }
        if defaults.data(forKey: WidgetShared.snapshotKey) == data { return false }
        defaults.set(data, forKey: WidgetShared.snapshotKey)
        return true
    }
}
