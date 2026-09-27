import Foundation
import SwiftUI

struct MedicalSource: Identifiable {
    let title: String
    let publisher: String
    let detail: String
    let url: URL

    var id: String { url.absoluteString }
}

enum AppConstants {
    static let safetyCopy = "MenoPlan is not a medical device and does not diagnose pregnancy, infertility, ovulation, or any medical condition. Results are for reference only. Follow your test instructions and seek a doctor's advice in addition to using this app and before making medical decisions."
    static let certaintyCopy = "Image readability reflects how clearly the app could compare the visible lines in the photo. It is not medical certainty."
    static let localPrivacyCopy = "Your test images and scan history stay on this device unless you choose Luna Check or Luna chat, which securely send the photo or relevant result context for analysis."
    static let medicalSources: [MedicalSource] = [
        MedicalSource(
            title: "Home-use pregnancy tests",
            publisher: "U.S. Food and Drug Administration",
            detail: "hCG detection, pregnancy test timing, false negatives, repeat testing, and following the test instructions.",
            url: URL(string: "https://www.fda.gov/medical-devices/home-use-tests/pregnancy")!
        ),
        MedicalSource(
            title: "Home-use test precautions",
            publisher: "U.S. Food and Drug Administration",
            detail: "Home tests support health care but do not replace a clinician's evaluation or regular care.",
            url: URL(string: "https://www.fda.gov/medical-devices/in-vitro-diagnostics/home-use-tests")!
        ),
        MedicalSource(
            title: "Home pregnancy tests",
            publisher: "Mayo Clinic",
            detail: "Practical guidance on test timing, false negatives, repeat testing, and when to contact a healthcare professional.",
            url: URL(string: "https://www.mayoclinic.org/healthy-lifestyle/getting-pregnant/in-depth/home-pregnancy-tests/art-20047940")!
        ),
        MedicalSource(
            title: "Ovulation urine tests",
            publisher: "U.S. Food and Drug Administration",
            detail: "LH surge basics, ovulation predictor kit limits, and the need to follow kit instructions carefully.",
            url: URL(string: "https://www.fda.gov/medical-devices/home-use-tests/ovulation-urine-test")!
        ),
        MedicalSource(
            title: "Fertility window basics",
            publisher: "Johns Hopkins Medicine",
            detail: "Cycle length, estimated fertile windows, ovulation timing, and ovulation predictor kit context.",
            url: URL(string: "https://www.hopkinsmedicine.org/health/wellness-and-prevention/calculating-your-monthly-fertility-window")!
        )
    ]
}

enum FeatureFlags {
    /// The "I'm pregnant" mode: the Settings option, Home's "You saved a
    /// positive test" prompt, and any copy that suggests switching. People
    /// already in pregnancy mode keep seeing it so they can switch back.
    static let pregnancyModeEnabled = false

    #if DEBUG
    static let enableRewardedAds = true
    static let enableBannerAds = true
    static let enableInterstitialAds = true
    static let enableStoreKitPurchases = true
    static let enableDevelopmentAdFallback = false
    #else
    static let enableRewardedAds = true
    static let enableBannerAds = true
    static let enableInterstitialAds = true
    static let enableStoreKitPurchases = true
    static let enableDevelopmentAdFallback = false
    #endif
}

enum LineAnalysisConstants {
    // Matches the server's ratio tiering exactly (api/analyse-test.js
    // normaliseResult: <0.40 low, <0.75 rising, <0.95 high, else peak) so the
    // same photo can't land in a different tier between Local Scan and Luna
    // Check purely from a boundary rounding difference.
    static let ovulationLowUpper = 0.40
    static let ovulationRisingUpper = 0.75
    static let ovulationHighUpper = 0.95
    static let pregnancyFaintThreshold = 0.20
    static let pregnancyPositiveThreshold = 0.42
    static let controlThreshold = 0.18
    static let minCertainty = 40
    static let maxCertainty = 95
    // Despite the generic name, every call site that reads this quota
    // (AICheckQuotaService.canUseAI/consumeAI) branches pregnancy off to its
    // own separate canUsePregnancyLuna/Pro-gated path first - in practice
    // this pool is exclusively the ovulation Luna Check quota. Free users
    // already have an unlimited, ad-supported fallback in "Manual Check"
    // (the on-device heuristic scanner, not this model), so Luna
    // Check itself - the trained model - stays deliberately scarce to
    // protect the reason to go Pro, rather than being generously available
    // for free.
    // Tightened from 3/3 (2026-09-23): 28-day Analytics showed only ~12% of
    // active Luna users ever hit linecheck_ai_quota_exhausted, and the
    // rewarded-ad backstop (matching the free quota 1:1/week) let a chunk of
    // engaged users dodge the paywall entirely without converting. Pulling
    // both down pushes the highest-intent users to the wall sooner.
    static let weeklyFreeAIChecks = 2
    static let rewardedChecks = 1
    static let maxRewardedChecksPerWeek = 2
    // Pregnancy used to run on its own rolling cooldown (1 free check every
    // N days) rather than a weekly counter - two different mental models for
    // what was meant to be the same "free allowance" idea, which made the
    // pregnancy side harder to reason about and to explain in the UI. Unified
    // onto the same weekly-counter shape as weeklyFreeAIChecks above (shares
    // AICheckQuotaService.refreshIfNeeded's weekly reset), just with its own
    // smaller allowance since pregnancy testing is naturally lower-frequency.
    static let weeklyFreePregnancyChecks = 1
    static let maxPregnancyRewardedChecksPerWeek = 1
    static let premiumAIComparesPerDay = 10
}

enum AdMobConstants {
    #if DEBUG
    static let appID = "ca-app-pub-3940256099942544~1458002511"
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let appID = "ca-app-pub-1257499604453174~6070339424"
    static let bannerAdUnitID = "ca-app-pub-1257499604453174/2806890990"
    static let interstitialAdUnitID = "ca-app-pub-1257499604453174/7731914616"
    // TODO: MenoPlan rewarded ad unit not created yet - Google's test unit
    // until then. Must be replaced before release.
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    #endif
}

enum AppLayout {
    static let floatingTabBarContentPadding: CGFloat = 124
    static let floatingTabBarBottomPadding: CGFloat = 8
    static let bannerAdTopPadding: CGFloat = 8
    /// Height to reserve before the slot has been measured - the fixed phone
    /// banner, which is also the SDK's fallback size.
    static let fallbackBannerAdHeight: CGFloat = 50

    /// Room a screen must leave at the top for the banner sitting above it.
    ///
    /// Derived from the banner's measured height rather than a constant: an
    /// anchored adaptive banner is 50pt on a phone but up to 90pt on iPad, and
    /// the old fixed 66 (8 + 50 + 8) let the ad overlap content there.
    static func bannerAdContentPadding(forBannerHeight height: CGFloat) -> CGFloat {
        bannerAdTopPadding + height + 8
    }
}

extension Color {
    static let lineBackground = Color(red: 0.97, green: 0.98, blue: 1.0)
    static let lineCard = Color(.secondarySystemGroupedBackground)
    static let lineNavy = Color(red: 0.03, green: 0.10, blue: 0.31)
    static let lineBlue = Color(red: 0.38, green: 0.20, blue: 0.95)
    static let linePink = Color(red: 1.0, green: 0.19, blue: 0.47)
    static let linePinkSoft = Color(red: 1.0, green: 0.91, blue: 0.94)
    static let linePurple = Color(red: 0.38, green: 0.20, blue: 0.95)
    static let linePurpleSoft = Color(red: 0.93, green: 0.90, blue: 1.0)
    static let lineTeal = Color(red: 0.02, green: 0.62, blue: 0.70)
    /// Cycle phases: pink period, soft purple fertile days, solid purple
    /// ovulation, and teal for the luteal days - a rose here read as a
    /// lighter period, so the phase after ovulation gets its own hue.
    static let lineFertileSoft = Color(red: 0.61, green: 0.52, blue: 0.96)
    static let lineLuteal = Color(red: 0.024, green: 0.486, blue: 0.549)
    static let lineLutealSoft = Color(red: 0.55, green: 0.83, blue: 0.86)
}

/// The app's typeface: Plus Jakarta Sans, bundled as one static file per
/// weight (Resources/Fonts). Weights resolve to an exact face by name.
enum AppFont {
    static let family = "Plus Jakarta Sans"

    static func faceName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: "PlusJakartaSans-Regular"
        case .medium: "PlusJakartaSans-Medium"
        case .semibold: "PlusJakartaSans-SemiBold"
        // Heavy was the old SF Rounded display weight; in this face Bold
        // carries the same hierarchy without shouting.
        case .bold, .heavy: "PlusJakartaSans-Bold"
        default: "PlusJakartaSans-ExtraBold"
        }
    }

    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }

    /// UIKit twin for navigation bars and other UIKit chrome.
    static func uiFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        UIFont(name: faceName(weight), size: size) ?? .systemFont(ofSize: size)
    }
}

extension Font {
    /// Fixed-size text in the app typeface.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.faceName(weight), fixedSize: size)
    }

    /// A Dynamic Type style in the app typeface.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        .custom(AppFont.faceName(weight ?? AppFont.defaultWeight(for: style)), size: AppFont.size(for: style), relativeTo: style)
    }

    @MainActor
    static func lineTitle(_ size: CGFloat = 34, weight: Font.Weight = .bold) -> Font {
        .app(size: LineType.size(size), weight: weight)
    }

    static func lineHeadline(_ weight: Font.Weight = .semibold) -> Font {
        .app(.headline, weight: weight)
    }

    static func lineSubheadline(_ weight: Font.Weight = .regular) -> Font {
        .app(.subheadline, weight: weight)
    }

    static func lineCaption(_ weight: Font.Weight = .regular) -> Font {
        .app(.caption, weight: weight)
    }
}
