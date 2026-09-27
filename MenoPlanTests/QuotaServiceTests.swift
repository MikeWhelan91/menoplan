import XCTest
@testable import MenoPlan


final class QuotaServiceTests: XCTestCase {
    func testManualEnhanceDoesNotUseQuotaContract() {
        let settings = UserSettings()
        let service = AICheckQuotaService()
        XCTAssertEqual(service.checksRemaining(settings), LineAnalysisConstants.weeklyFreeAIChecks)
        XCTAssertTrue(service.consumeAI(settings))
        XCTAssertEqual(service.checksRemaining(settings), LineAnalysisConstants.weeklyFreeAIChecks - 1)
    }

    func testOvulationQuotaHasNoDailyCap() {
        let settings = UserSettings()
        let service = AICheckQuotaService()
        for _ in 0..<LineAnalysisConstants.weeklyFreeAIChecks {
            XCTAssertTrue(service.consumeAI(settings))
        }
        XCTAssertEqual(service.checksRemaining(settings), 0)
        XCTAssertFalse(service.consumeAI(settings))
    }

    func testIncludedOvulationLunaCheckIsIdentifiedButRewardedCheckIsNot() {
        let settings = UserSettings()
        let service = AICheckQuotaService()

        XCTAssertTrue(service.willConsumeFreeOvulationLuna(settings))
        XCTAssertTrue(service.consumeAI(settings))

        XCTAssertTrue(service.addRewardedChecks(settings))
        XCTAssertFalse(service.willConsumeFreeOvulationLuna(settings))
    }

    func testRewardedCheckClaimsAreCappedPerWeekNotPerDay() {
        let settings = UserSettings()
        let service = AICheckQuotaService()
        for _ in 0..<LineAnalysisConstants.maxRewardedChecksPerWeek {
            XCTAssertTrue(service.addRewardedChecks(settings))
        }
        XCTAssertFalse(service.canClaimRewardedCheck(settings))
        XCTAssertFalse(service.addRewardedChecks(settings))
        XCTAssertEqual(settings.rewardedChecksAvailable, LineAnalysisConstants.maxRewardedChecksPerWeek * LineAnalysisConstants.rewardedChecks)
    }

    func testRewardedChecksMatchConfiguredRewardValue() {
        let settings = UserSettings()
        let service = AICheckQuotaService()
        service.addRewardedChecks(settings)
        XCTAssertEqual(settings.rewardedChecksAvailable, LineAnalysisConstants.rewardedChecks)
    }

    func testProIsUnlimited() {
        let settings = UserSettings()
        settings.proUnlocked = true
        XCTAssertNil(AICheckQuotaService().checksRemaining(settings))
    }

    func testPregnancyLunaStartsWithOneFreeCheckPerWeek() {
        let settings = UserSettings()
        let service = AICheckQuotaService()

        XCTAssertTrue(service.canUsePregnancyLuna(settings))
        XCTAssertTrue(service.consumePregnancyLuna(settings))
        XCTAssertEqual(settings.pregnancyFreeChecksUsedThisWeek, LineAnalysisConstants.weeklyFreePregnancyChecks)
        XCTAssertFalse(service.canUsePregnancyLuna(settings))
    }

    func testPregnancyRewardedCheckIsSpentBeforeTheFreeQuotaResets() {
        let settings = UserSettings()
        let service = AICheckQuotaService()

        // Free check used for the week - claim and spend a rewarded one
        // instead of waiting for next week's reset.
        XCTAssertTrue(service.consumePregnancyLuna(settings))
        XCTAssertFalse(service.canUsePregnancyLuna(settings))

        XCTAssertTrue(service.addPregnancyRewardedCheck(settings))
        XCTAssertTrue(service.consumePregnancyLuna(settings))
        XCTAssertEqual(settings.pregnancyRewardedChecksAvailable, 0)

        // A second claim is correctly refused once the weekly claim cap is
        // hit, same shape as the ovulation pool's maxRewardedChecksPerWeek.
        XCTAssertFalse(service.canClaimPregnancyRewardedCheck(settings))
        XCTAssertFalse(service.addPregnancyRewardedCheck(settings))
    }
}
