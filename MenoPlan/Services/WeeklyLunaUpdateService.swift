import Foundation
import SwiftData

/// Generates one automatic "weekly Luna update" roughly every 7 days: a short AI recap of
/// just the last 7 days of scans and body-signs logs, with a couple of grounded observations.
/// Pro-only, silent, and self-throttling - see `isDue`. Runs from RootView's app-launch task,
/// the same place entitlement/notification sync already happens.
@MainActor
enum WeeklyLunaUpdateService {
    private static let minimumDaysBetweenUpdates = 7

    enum GenerationResult {
        case generated
        case notPro
        case noRecentActivity
        case failed
    }

    /// Checks whether a new digest is due and, if so, generates and stores one. Safe to call on
    /// every app launch - it no-ops quickly when nothing is due or there's nothing to report.
    static func generateIfDue(
        settings: UserSettings,
        scans: [Scan],
        dailyLogs: [DailyFertilityLog],
        cycles: [CycleRecord],
        periods: [PeriodEvent],
        existingUpdates: [WeeklyLunaUpdate],
        context: ModelContext
    ) async {
        guard settings.proUnlocked else { return }
        guard isDue(existingUpdates: existingUpdates, scans: scans, dailyLogs: dailyLogs) else { return }

        _ = await generate(
            settings: settings,
            scans: scans,
            dailyLogs: dailyLogs,
            cycles: cycles,
            periods: periods,
            context: context
        )
    }

    /// Debug-only callers can bypass the seven-day throttle to preview a new report.
    /// It remains Pro-gated and still requires something in the current reporting window.
    static func generateForDebug(
        settings: UserSettings,
        scans: [Scan],
        dailyLogs: [DailyFertilityLog],
        cycles: [CycleRecord],
        periods: [PeriodEvent],
        context: ModelContext
    ) async -> GenerationResult {
        guard settings.proUnlocked else { return .notPro }
        return await generate(
            settings: settings,
            scans: scans,
            dailyLogs: dailyLogs,
            cycles: cycles,
            periods: periods,
            context: context
        )
    }

    private static func generate(
        settings: UserSettings,
        scans: [Scan],
        dailyLogs: [DailyFertilityLog],
        cycles: [CycleRecord],
        periods: [PeriodEvent],
        context: ModelContext
    ) async -> GenerationResult {

        let weekEnd = Date.now
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekEnd) ?? weekEnd
        let recentScans = scans.filter { $0.createdAt >= weekStart }
        let recentLogs = dailyLogs.filter { $0.date >= weekStart }
        // Nothing happened this week - skip rather than ask Luna to write a recap of silence.
        // isDue() isn't updated, so this is retried (cheaply) on the next launch.
        let healthMetrics = (try? context.fetch(FetchDescriptor<DailyHealthMetrics>())) ?? []
        // Apple Health alone (sleep, resting heart rate, temperature) is
        // enough to be worth a recap - the week may hold a signal to flag.
        let hasRecentHealthData = healthMetrics.contains { $0.date >= weekStart && $0.hasContent }
        guard !recentScans.isEmpty || recentLogs.contains(where: \.hasContent) || hasRecentHealthData else { return .noRecentActivity }
        let userContext = AssistantContextBuilder.userContext(
            settings: settings,
            cycles: cycles,
            dailyLogs: recentLogs,
            periodEvents: periods,
            maximumCycleSummaries: 1,
            maximumDailySummaries: 7,
            allDailyLogs: dailyLogs,
            healthMetrics: healthMetrics,
            scans: scans,
            signalSurface: .weekly
        )

        do {
            let response = try await AssistantService().reply(
                message: "Give me my weekly update.",
                recentScans: recentScans.prefix(12).map { AssistantContextBuilder.recentScan($0, includeFreeText: false) },
                reminders: [],
                userContext: userContext,
                mode: "weeklyDigest"
            )
            let update = WeeklyLunaUpdate(weekStartDate: weekStart, weekEndDate: weekEnd, reply: response.reply)
            context.insert(update)
            try? context.save()
            AppAnalytics.log("linecheck_weekly_update_generated")
            await NotificationService().sendImmediateNotification(
                id: update.id,
                title: "Luna Weekly Report Is Ready",
                subtitle: "",
                body: ""
            )
            return .generated
        } catch {
            AppAnalytics.log("linecheck_weekly_update_failed")
            return .failed
        }
    }

    private static func isDue(existingUpdates: [WeeklyLunaUpdate], scans: [Scan], dailyLogs: [DailyFertilityLog]) -> Bool {
        let calendar = Calendar.current
        if let latest = existingUpdates.map(\.createdAt).max() {
            let daysSince = calendar.dateComponents([.day], from: latest, to: .now).day ?? 0
            return daysSince >= minimumDaysBetweenUpdates
        }
        // No digest yet - only start once there's at least a week of history to look back on,
        // so the very first one isn't generated the day someone installs the app.
        guard let earliestActivity = (scans.map(\.createdAt) + dailyLogs.filter(\.hasContent).map(\.date)).min() else {
            return false
        }
        let daysSinceFirstActivity = calendar.dateComponents([.day], from: earliestActivity, to: .now).day ?? 0
        return daysSinceFirstActivity >= minimumDaysBetweenUpdates
    }
}
