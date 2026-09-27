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

}
