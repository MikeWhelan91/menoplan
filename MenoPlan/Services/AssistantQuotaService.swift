import Foundation

final class AssistantQuotaService {
    func refreshIfNeeded(_ settings: UserSettings) {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: settings.assistantRepliesResetDate)
        let today = calendar.startOfDay(for: .now)
        guard lastDay != today else { return }
        settings.assistantRepliesUsedToday = 0
        settings.assistantRepliesResetDate = .now
    }

    func canAccess(_ settings: UserSettings) -> Bool {
        settings.proUnlocked
    }

    func repliesRemaining(_ settings: UserSettings) -> Int {
        Int.max
    }

    func canSend(_ settings: UserSettings) -> Bool {
        canAccess(settings)
    }

    @discardableResult
    func consume(_ settings: UserSettings) -> Bool {
        settings.proUnlocked
    }

    func resetLabel(_ settings: UserSettings) -> String {
        refreshIfNeeded(settings)
        return DateFormatting.shortTime.string(from: nextResetDate())
    }

    func nextResetDate(from date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
    }

    func resetCountdown(from date: Date = .now) -> String {
        let seconds = max(0, Int(nextResetDate(from: date).timeIntervalSince(date)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }
}

final class AICompareQuotaService {
    func refreshIfNeeded(_ settings: UserSettings) {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: settings.aiComparesResetDate)
        let today = calendar.startOfDay(for: .now)
        guard lastDay != today else { return }
        settings.aiComparesUsedToday = 0
        settings.aiComparesResetDate = .now
    }

    func canAccess(_ settings: UserSettings) -> Bool {
        settings.proUnlocked
    }

    func comparesRemaining(_ settings: UserSettings) -> Int {
        refreshIfNeeded(settings)
        return max(0, LineAnalysisConstants.premiumAIComparesPerDay - settings.aiComparesUsedToday)
    }

    func canSend(_ settings: UserSettings) -> Bool {
        canAccess(settings) && comparesRemaining(settings) > 0
    }

    @discardableResult
    func consume(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        guard settings.proUnlocked else { return false }
        guard settings.aiComparesUsedToday < LineAnalysisConstants.premiumAIComparesPerDay else { return false }
        settings.aiComparesUsedToday += 1
        return true
    }

    func resetLabel(_ settings: UserSettings) -> String {
        refreshIfNeeded(settings)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return DateFormatting.shortTime.string(from: tomorrow)
    }
}
