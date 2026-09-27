import Foundation
import RevenueCat
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published private(set) var packages: [Package] = []
    @Published var state: PurchaseState = .free

    private let offeringID = "linecheck"
    private let entitlementID = "MenoPlan"
    private let legacyProductIDs = Set([
        "menoplan_pro_monthly",
        "menoplan_pro_yearly",
        "menoplan_pro_lifetime"
    ])
    private let migrationKey = "linecheck.revenuecat.storekit2MigrationCompleted"
    #if DEBUG
    private let debugPremiumOverrideKey = "linecheck.debug.premiumOverrideActive"
    private let debugPremiumValueKey = "linecheck.debug.premiumEnabled"
    #endif

    /// RevenueCat deliberately traps when `shared` is accessed before configuration.
    /// Keep local/dev builds functional when their xcconfig does not contain a key.
    private var canUseRevenueCat: Bool {
        #if DEBUG
        // Debug builds deliberately skip Purchases.configure(...) (see
        // LineCheckApp.swift) so local testing doesn't pollute production
        // RevenueCat stats. Use setDebugPremium(_:settings:) to test Pro locally.
        return false
        #else
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String else { return false }
        return !key.isEmpty && !key.contains("$(")
        #endif
    }

    #if DEBUG
    var debugPremiumEnabled: Bool {
        UserDefaults.standard.bool(forKey: debugPremiumValueKey)
    }

    func setDebugPremium(_ enabled: Bool, settings: UserSettings) {
        UserDefaults.standard.set(true, forKey: debugPremiumOverrideKey)
        UserDefaults.standard.set(enabled, forKey: debugPremiumValueKey)
        settings.proUnlocked = enabled
        state = enabled ? .pro : .free
    }
    #endif

    func loadProducts() async {
        guard FeatureFlags.enableStoreKitPurchases, canUseRevenueCat else {
            state = .unavailable
            return
        }

        state = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.offering(identifier: offeringID) else {
                packages = []
                state = .unavailable
                return
            }
            packages = offering.availablePackages
            state = packages.isEmpty ? .unavailable : .free
        } catch {
            packages = []
            state = .unavailable
        }
    }

    func purchase(_ package: Package, settings: UserSettings) async -> LineCheckPurchaseOutcome {
        guard canUseRevenueCat else { state = .unavailable; return .failed }
        state = .loading
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                state = settings.proUnlocked ? .pro : .free
                return .cancelled
            }

            let unlocked = apply(result.customerInfo, to: settings)
            return unlocked ? .success : .failed
        } catch {
            state = settings.proUnlocked ? .pro : .free
            switch (error as NSError).asErrorCode {
            case .purchaseCancelledError:
                return .cancelled
            case .paymentPendingError:
                return .pending
            default:
                state = settings.proUnlocked ? .pro : .failed
                return .failed
            }
        }
    }

    func restore(settings: UserSettings) async -> Bool {
        guard canUseRevenueCat else { state = .unavailable; return false }
        state = .loading
        do {
            return apply(try await Purchases.shared.restorePurchases(), to: settings)
        } catch {
            state = settings.proUnlocked ? .pro : .failed
            return false
        }
    }

    @discardableResult
    func syncEntitlements(settings: UserSettings) async -> Bool {
        guard FeatureFlags.enableStoreKitPurchases, canUseRevenueCat else {
            // DEBUG builds always take this branch (canUseRevenueCat is
            // hard-coded false), and this runs on every cold launch - it
            // was unconditionally resetting proUnlocked to false here,
            // silently undoing the Debug Premium toggle on every relaunch
            // before apply(_:to:)'s override check ever got a chance to run.
            #if DEBUG
            if UserDefaults.standard.bool(forKey: debugPremiumOverrideKey) {
                let unlocked = UserDefaults.standard.bool(forKey: debugPremiumValueKey)
                settings.proUnlocked = unlocked
                state = unlocked ? .pro : .free
                return unlocked
            }
            #endif
            settings.proUnlocked = false
            state = .unavailable
            return false
        }

        await migrateLegacyStoreKitPurchasesIfNeeded()

        do {
            return apply(try await Purchases.shared.customerInfo(), to: settings)
        } catch {
            state = settings.proUnlocked ? .pro : .failed
            return settings.proUnlocked
        }
    }

    func observeEntitlementUpdates(
        settings: UserSettings,
        onChange: @escaping @MainActor () -> Void = {}
    ) async {
        guard FeatureFlags.enableStoreKitPurchases, canUseRevenueCat else { return }
        for await customerInfo in Purchases.shared.customerInfoStream {
            _ = apply(customerInfo, to: settings)
            onChange()
        }
    }

    private func apply(_ customerInfo: CustomerInfo, to settings: UserSettings) -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: debugPremiumOverrideKey) {
            let unlocked = UserDefaults.standard.bool(forKey: debugPremiumValueKey)
            settings.proUnlocked = unlocked
            state = unlocked ? .pro : .free
            return unlocked
        }
        #endif
        let unlocked = customerInfo.entitlements.active[entitlementID] != nil
        settings.proUnlocked = unlocked
        state = unlocked ? .pro : .free
        return unlocked
    }

    private func migrateLegacyStoreKitPurchasesIfNeeded() async {
        guard canUseRevenueCat else { return }
        guard UserDefaults.standard.bool(forKey: migrationKey) == false else { return }

        var hasLegacyPurchase = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               legacyProductIDs.contains(transaction.productID) {
                hasLegacyPurchase = true
                break
            }
        }

        do {
            if hasLegacyPurchase {
                _ = try await Purchases.shared.syncPurchases()
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            // Retry on the next launch so existing customers are not stranded by a transient failure.
        }
    }
}

enum LineCheckPurchaseOutcome {
    case success
    case pending
    case cancelled
    case failed
}
