import GoogleMobileAds
import AppTrackingTransparency
import UIKit
import UserMessagingPlatform

@MainActor
@Observable
final class AdConsentService {
    static let shared = AdConsentService()

    private let consentInfo = ConsentInformation.shared
    private var isRequestInFlight = false
    private var didStartAds = false

    var canRequestAds = false
    var adsStarted = false
    var consentResolved = false
    var privacyOptionsRequired = false

    private init() {
        canRequestAds = consentInfo.canRequestAds
        privacyOptionsRequired = consentInfo.privacyOptionsRequirementStatus == .required
        if canRequestAds {
            startAdsIfNeeded()
        }
    }

    func requestTrackingAndConsentIfNeeded() async {
        guard FeatureFlags.enableBannerAds || FeatureFlags.enableInterstitialAds || FeatureFlags.enableRewardedAds else { return }
        // Order matters here and is the whole fix for a real App Review
        // rejection (Guideline 5.1.1(iv)): showing the GDPR/UMP consent form
        // AFTER the ATT prompt reads as asking to track again once someone
        // has already picked "Ask App Not to Track" on that native prompt,
        // even though the two are technically different permissions. Apple's
        // own rejection notice states that showing the GDPR prompt before
        // ATT needs no wording changes at all, so consent goes first.
        await requestConsentIfNeeded()
        await requestTrackingAuthorizationIfNeeded()
        MetaAppEventsService.shared.activateIfAuthorized()
    }

    func requestConsentIfNeeded() async {
        guard FeatureFlags.enableBannerAds || FeatureFlags.enableInterstitialAds || FeatureFlags.enableRewardedAds else { return }
        guard isRequestInFlight == false else { return }

        if consentResolved, canRequestAds {
            startAdsIfNeeded()
            return
        }

        isRequestInFlight = true
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        do {
            try await consentInfo.requestConsentInfoUpdate(with: parameters)
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.lineCheckTopViewController)
        } catch {
            // UMP can still allow ad requests from a previous session after a refresh error.
        }

        finishConsentRequest()
    }

    func showPrivacyOptions() async -> Bool {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.lineCheckTopViewController)
            finishConsentRequest()
            return true
        } catch {
            finishConsentRequest()
            return false
        }
    }

    private func finishConsentRequest() {
        canRequestAds = consentInfo.canRequestAds
        privacyOptionsRequired = consentInfo.privacyOptionsRequirementStatus == .required
        consentResolved = true
        isRequestInFlight = false
        if canRequestAds {
            startAdsIfNeeded()
        }
    }

    private func startAdsIfNeeded() {
        guard didStartAds == false else { return }
        didStartAds = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                self?.adsStarted = true
            }
        }
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }

        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }
}

private extension UIApplication {
    var lineCheckTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .lineCheckPresentedViewController
    }
}

private extension UIViewController {
    var lineCheckPresentedViewController: UIViewController {
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.lineCheckPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.lineCheckPresentedViewController
        }

        if let presentedViewController {
            return presentedViewController.lineCheckPresentedViewController
        }

        return self
    }
}
