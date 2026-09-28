import Foundation

/// Compiled into both the app and the widget extension. The app does the
/// work; the widget only reads this precomputed snapshot from the App Group,
/// so it never opens the SwiftData/CloudKit store itself.
enum WidgetShared {
    static let appGroupID = "group.com.menocheck.app"
    static let snapshotKey = "widgetSnapshot.v3"
    // Kind strings kept from LineCheck so widgets people have placed survive.
    static let cycleWidgetKind = "LineCheckCycleWidget"
    static let todayPlanWidgetKind = "LineCheckTodayPlanWidget"
    static let urlScheme = "menoplan"
}

/// Deep links the widgets open. Kept here so the widget and RootView's
/// onOpenURL agree on the same hosts.
enum WidgetDeepLink: String {
    case checkIn = "check-in", calendar, setupCycle = "setup-cycle", scanOvulation = "scan-ovulation"

    var url: URL { URL(string: "\(WidgetShared.urlScheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == WidgetShared.urlScheme, let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}

/// Only facts, never predictions: which days were logged, which were period
/// days, and when the last period started. Everything a widget says is
/// derived from these at render time, so it stays right past midnight.
struct WidgetSnapshot: Codable, Hashable {
    var isSetUp: Bool
    var tracksCycle: Bool
    var lastPeriodStart: Date?
    /// Day keys (see `dayKey`) of logged period days, recent months only.
    var periodDays: Set<String>
    /// Day keys of days with anything in the daily log.
    var loggedDays: Set<String>
    /// The person's check-in symptoms, for the check-in widget.
    var focus: [String]

    static let empty = WidgetSnapshot(isSetUp: false, tracksCycle: false, lastPeriodStart: nil, periodDays: [], loggedDays: [], focus: [])

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func isLogged(_ date: Date, calendar: Calendar = .current) -> Bool { loggedDays.contains(Self.dayKey(date, calendar: calendar)) }
    func isPeriod(_ date: Date, calendar: Calendar = .current) -> Bool { periodDays.contains(Self.dayKey(date, calendar: calendar)) }
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
        guard let defaults, let data = try? encoder.encode(SortedSnapshot(snapshot)) else { return false }
        if defaults.data(forKey: WidgetShared.snapshotKey) == data { return false }
        defaults.set(data, forKey: WidgetShared.snapshotKey)
        return true
    }

    /// Sets encode in hash order, which changes run to run; sorted arrays keep
    /// an unchanged snapshot byte-identical. Decodes as a WidgetSnapshot.
    private struct SortedSnapshot: Encodable {
        let base: WidgetSnapshot
        init(_ base: WidgetSnapshot) { self.base = base }
        enum Keys: String, CodingKey { case isSetUp, tracksCycle, lastPeriodStart, periodDays, loggedDays, focus }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(base.isSetUp, forKey: .isSetUp)
            try container.encode(base.tracksCycle, forKey: .tracksCycle)
            try container.encodeIfPresent(base.lastPeriodStart, forKey: .lastPeriodStart)
            try container.encode(base.periodDays.sorted(), forKey: .periodDays)
            try container.encode(base.loggedDays.sorted(), forKey: .loggedDays)
            try container.encode(base.focus, forKey: .focus)
        }
    }
}
