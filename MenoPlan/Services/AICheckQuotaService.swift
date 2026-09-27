import Foundation

final class AICheckQuotaService {
    func canUsePregnancyLuna(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        if settings.proUnlocked { return true }
        return isPregnancyFreeLunaAvailable(settings) || settings.pregnancyRewardedChecksAvailable > 0
    }

    /// Just the free-check slot specifically, ignoring any banked rewarded
    /// check - used where the UI needs to know "is the free one open" (e.g.
    /// the "1 left" badge, or whether a consumption should count as the
    /// included free one) rather than "can they check at all."
    func isPregnancyFreeLunaAvailable(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        return settings.pregnancyFreeChecksUsedThisWeek < LineAnalysisConstants.weeklyFreePregnancyChecks
    }

    func canClaimPregnancyRewardedCheck(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        if settings.proUnlocked { return false }
        return settings.pregnancyRewardedChecksClaimedThisWeek < LineAnalysisConstants.maxPregnancyRewardedChecksPerWeek
    }

    @discardableResult
    func addPregnancyRewardedCheck(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        guard canClaimPregnancyRewardedCheck(settings) else { return false }
        settings.pregnancyRewardedChecksAvailable += LineAnalysisConstants.rewardedChecks
        settings.pregnancyRewardedChecksClaimedThisWeek += 1
        return true
    }

    @discardableResult
    func consumePregnancyLuna(_ settings: UserSettings) -> Bool {
        refreshIfNeeded(settings)
        if settings.proUnlocked {
            AppAnalytics.log("linecheck_luna_check_used", ["test_type": "pregnancy", "source": "pro"])
            return true
        }
        if settings.pregnancyRewardedChecksAvailable > 0 {
            settings.pregnancyRewardedChecksAvailable -= 1
            AppAnalytics.log("linecheck_luna_check_used", ["test_type": "pregnancy", "source": "rewarded"])
            return true
        }
        if settings.pregnancyFreeChecksUsedThisWeek < LineAnalysisConstants.weeklyFreePregnancyChecks {
            settings.pregnancyFreeChecksUsedThisWeek += 1
            AppAnalytics.log("linecheck_luna_check_used", ["test_type": "pregnancy", "source": "free"])
            return true
        }
        return false
    }

    /// Weekly reset shared by both Luna Check pools - ovulation's free
    /// checks/rewarded bank/claims, and pregnancy's, all reset together on
    /// the same calendar-week cycle, so "your free checks reset every week"
    /// is one story instead of two different mechanics.
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
        settings.pregnancyFreeChecksUsedThisWeek = 0
        settings.pregnancyRewardedChecksAvailable = 0
        settings.pregnancyRewardedChecksClaimedThisWeek = 0
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
