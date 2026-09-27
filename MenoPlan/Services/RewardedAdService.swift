import Foundation
@preconcurrency import GoogleMobileAds
@_spi(Experimental) import RevenueCatAdMob
import SwiftUI
import UIKit

extension InterstitialAd: @unchecked @retroactive Sendable {}
extension RewardedAd: @unchecked @retroactive Sendable {}

enum AdPresentation {
    @MainActor
    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topPresentedViewController
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topPresentedViewController
        }
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topPresentedViewController ?? navigationController
        }
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topPresentedViewController ?? tabBarController
        }
        return self
    }
}

/// Banner sizing: the largest standard IAB size that fits the slot.
///
/// A fixed `AdSizeBanner` (320x50) used to be hard-coded, which on iPad looked
/// like a phone-sized island in a full-width bar and only ever requested the
/// smallest format - never the 728x90 and 468x60 inventory tablets are eligible
/// for.
///
/// These are exact standard sizes rather than an anchored adaptive banner on
/// purpose. An adaptive banner is as wide as the slot it's given, but the
/// creative that fills it is still a standard size, so anything narrower than
/// the slot renders letterboxed against the SDK's black container - very
/// visible on iPad, where the slot is hundreds of points wider than the ad.
/// Requesting an exact size and framing the view at exactly that size means the
/// creative always fills it and there is no letterboxing by construction.
enum BannerAdLayout {
    /// The ad size to request for a slot of `width` points.
    ///
    /// Falls back to the phone banner when the width hasn't been measured yet,
    /// so the slot always has a sensible height to reserve.
    static func adSize(forWidth width: CGFloat) -> AdSize {
        guard width > 0 else { return AdSizeBanner }
        if width >= AdSizeLeaderboard.size.width { return AdSizeLeaderboard }
        if width >= AdSizeFullBanner.size.width { return AdSizeFullBanner }
        return AdSizeBanner
    }

    /// The banner's dimensions for a slot of `width` points.
    ///
    /// Returns a plain `CGSize` so views can lay the slot out without importing
    /// the ads SDK just to name its size type.
    static func size(forWidth width: CGFloat) -> CGSize {
        adSize(forWidth: width).size
    }
}

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    /// Width of the slot the banner sits in. Anchored adaptive banners size
    /// themselves from the width they're handed, and that width changes with
    /// rotation and with iPad Split View / Slide Over, so it's passed in rather
    /// than assumed.
    let width: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: BannerAdLayout.adSize(forWidth: width))
        banner.adUnitID = adUnitID
        context.coordinator.update(banner, width: width)
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        context.coordinator.update(uiView, width: width)
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        private var didLoadAd = false
        private var isLoading = false
        /// The width the ad currently on screen was requested at, so a resize
        /// can tell "same width, already loaded" from "new width, stale ad".
        private var loadedWidth: CGFloat = 0
        private var retryTask: Task<Void, Never>?

        deinit {
            retryTask?.cancel()
        }

        func update(_ banner: BannerView, width: CGFloat) {
            banner.rootViewController = AdPresentation.rootViewController()

            guard width > 0 else {
                scheduleRetry(for: banner, width: width)
                return
            }

            // A width change means the adaptive size the current ad was
            // requested against is stale. Re-request at the new size rather
            // than leaving an ad sized for the old width in a differently
            // sized slot.
            if abs(width - loadedWidth) > 1 {
                let adSize = BannerAdLayout.adSize(forWidth: width)
                if abs(banner.adSize.size.width - adSize.size.width) > 1 {
                    banner.adSize = adSize
                }
                didLoadAd = false
                isLoading = false
            }

            guard AdConsentService.shared.canRequestAds, AdConsentService.shared.adsStarted else {
                scheduleRetry(for: banner, width: width)
                return
            }
            guard banner.rootViewController != nil else {
                scheduleRetry(for: banner, width: width)
                return
            }
            guard isLoading == false, didLoadAd == false else { return }
            retryTask?.cancel()
            retryTask = nil
            isLoading = true
            loadedWidth = width
            banner.loadAndTrack(
                request: Request(),
                placement: "app_banner",
                delegate: self
            )
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            isLoading = false
            didLoadAd = true
            #if DEBUG
            print("AdMob banner loaded (\(bannerView.adSize.size.width)x\(bannerView.adSize.size.height))")
            #endif
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            isLoading = false
            didLoadAd = false
            #if DEBUG
            print("AdMob banner failed: \(error.localizedDescription)")
            #endif
            scheduleRetry(for: bannerView, width: loadedWidth)
        }

        private func scheduleRetry(for banner: BannerView, width: CGFloat) {
            guard retryTask == nil else { return }
            retryTask = Task { @MainActor [weak self, weak banner] in
                try? await Task.sleep(for: .milliseconds(350))
                guard Task.isCancelled == false, let self, let banner else { return }
                self.retryTask = nil
                self.update(banner, width: width)
            }
        }
    }
}

@MainActor
final class InterstitialAdService: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isReady = false
    private var interstitial: InterstitialAd?

    func load() {
        guard FeatureFlags.enableInterstitialAds, AdConsentService.shared.canRequestAds else { return }
        InterstitialAd.loadAndTrack(
            withAdUnitID: AdMobConstants.interstitialAdUnitID,
            request: Request(),
            placement: "scan_interstitial",
            fullScreenContentDelegate: self
        ) { [weak self] ad, _ in
            guard let self else { return }
            Task { @MainActor in
                self.interstitial = ad
                self.isReady = ad != nil
            }
        }
    }

    func showIfReady() {
        guard FeatureFlags.enableInterstitialAds, AdConsentService.shared.canRequestAds, let interstitial else {
            load()
            return
        }
        interstitial.present(from: AdPresentation.rootViewController())
        self.interstitial = nil
        isReady = false
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        load()
    }
}

@MainActor
final class RewardedAdService: NSObject, ObservableObject, FullScreenContentDelegate {
    private static var activeRewardRequest = false
    @Published var isAvailable = FeatureFlags.enableRewardedAds
    private var coordinator: RewardedAdCoordinator?

    func showRewardedAd() async -> Bool {
        await AdConsentService.shared.requestTrackingAndConsentIfNeeded()
        guard FeatureFlags.enableRewardedAds, AdConsentService.shared.canRequestAds else { return false }
        guard Self.activeRewardRequest == false else { return false }
        Self.activeRewardRequest = true
        defer { Self.activeRewardRequest = false }
        #if DEBUG
        if FeatureFlags.enableDevelopmentAdFallback {
            try? await Task.sleep(for: .seconds(1))
            return true
        }
        #endif
        let watched = await withCheckedContinuation { continuation in
            guard let presenter = AdPresentation.rootViewController() else {
                continuation.resume(returning: false)
                return
            }
            let coordinator = RewardedAdCoordinator(
                continuation: continuation,
                onFinish: { [weak self] in
                    self?.coordinator = nil
                }
            )
            self.coordinator = coordinator

            RewardedAd.loadAndTrack(
                withAdUnitID: AdMobConstants.rewardedAdUnitID,
                request: Request(),
                placement: "luna_check_rewarded",
                fullScreenContentDelegate: coordinator
            ) { [weak self, weak coordinator] ad, _ in
                guard let ad else {
                    coordinator?.finish(returning: false)
                    return
                }
                guard let self, let coordinator, self.coordinator === coordinator else {
                    coordinator?.finish(returning: false)
                    return
                }
                ad.present(from: presenter) {
                    coordinator.rewardEarned()
                }
            }
        }
        AppAnalytics.log("linecheck_rewarded_ad_watched", ["completed": watched])
        return watched
    }
}

@MainActor
private final class RewardedAdCoordinator: NSObject, FullScreenContentDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private let onFinish: () -> Void
    private var earnedReward = false

    init(continuation: CheckedContinuation<Bool, Never>, onFinish: @escaping () -> Void) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func rewardEarned() {
        earnedReward = true
        finish(returning: true)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish(returning: earnedReward)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        finish(returning: false)
    }

    func finish(returning value: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
        onFinish()
    }
}
