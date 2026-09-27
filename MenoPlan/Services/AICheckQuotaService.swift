import Foundation

final class AICheckQuotaService {
    /// Weekly reset for the Luna Check pool - free checks, rewarded bank
    /// and claims all reset together each calendar week.
    func refreshIfNeeded(_ settings: UserSettings) {
        let calendar = Calendar.current
        let lastWeek = calendar.component(.weekOfYear, from: settings.lastAICheckResetDate)
        let thisWeek = calendar.component(.weekOfYear, from: .now)
        let lastYear = calendar.component(.yearForWeekOfYear, from: settings.lastAICheckResetDate)
        let thisYear = calendar.component(.yearForWeekOfYear, from: .now)
        guard lastWeek != thisWeek || lastYear != thisYear else { return }
        settings.freeAIChecksUsedToday = 0
        settings.rewardedChecksAvailable = 0
        settings.rewardedChecksClaimedThisWeek = 0
        settings.lastAICheckResetDate = .now
    }

    func checksRemaining(_ settings: UserSettings) -> Int? {
        refreshIfNeeded(settings)
        if settings.proUnlocked { return nil }
        return max(0, LineAnalysisConstants.weeklyFreeAIChecks - settings.freeAIChecksUsedToday) + settings.rewardedChecksAvailable
    }

    func quotaText(_ settings: UserSettings) -> String {
        if settings.proUnlocked { return "Unlimited with Pro" }
        let remaining = checksRemaining(settings) ?? 0
        if remaining > 0 { return "\(remaining) Luna Check\(remaining == 1 ? "" : "s") left" }
        if settings.rewardedChecksClaimedThisWeek >= LineAnalysisConstants.maxRewardedChecksPerWeek {
            return "Weekly free limit reached"
        }
        return "Watch an ad for 1 more Luna Check"
    }

    func canUseAI(_ settings: UserSettings) -> Bool {
        if settings.proUnlocked { return true }
        return (checksRemaining(settings) ?? 0) > 0
    }

    /// Whether the next ovulation Luna Check will consume the included free
    /// allowance, rather than a banked rewarded check or Pro entitlement.
    func willConsumeFreeOvulationLuna(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        return !settings.proUnlocked
            && settings.rewardedChecksAvailable == 0
            && settings.freeAIChecksUsedToday < LineAnalysisConstants.weeklyFreeAIChecks
    }

    func consumeAI(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        if settings.proUnlocked {
            AppAnalytics.log("linecheck_luna_check_used", ["test_type": "ovulation", "source": "pro"])
            return true
        }
        if settings.rewardedChecksAvailable > 0 {
            settings.rewardedChecksAvailable -= 1
            AppAnalytics.log("linecheck_luna_check_used", ["test_type": "ovulation", "source": "rewarded"])
            return true
        }
        if settings.freeAIChecksUsedToday < LineAnalysisConstants.weeklyFreeAIChecks {
            settings.freeAIChecksUsedToday += 1
            AppAnalytics.log("linecheck_luna_check_used", ["test_type": "ovulation", "source": "free"])
            return true
        }
        return false
    }

    func canClaimRewardedCheck(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        if settings.proUnlocked { return false }
        return settings.rewardedChecksClaimedThisWeek < LineAnalysisConstants.maxRewardedChecksPerWeek
    }

    @discardableResult
    func addRewardedChecks(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        guard canClaimRewardedCheck(settings) else { return false }
        settings.rewardedChecksAvailable += LineAnalysisConstants.rewardedChecks
        settings.rewardedChecksClaimedThisWeek += 1
        return true
    }
}
