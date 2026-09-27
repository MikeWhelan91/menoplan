import AppTrackingTransparency
import FacebookCore
import UIKit

/// Only install/activation measurement goes to Meta. Never forward AppAnalytics
/// events, scan results, cycle data, chat content, or user identifiers here.
@MainActor
final class MetaAppEventsService {
    static let shared = MetaAppEventsService()

    private var isInitialized = false
    private var activatedThisForeground = false
    private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

    private init() {}

    func prepare(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        self.launchOptions = launchOptions
    }

    func didEnterBackground() {
        activatedThisForeground = false
    }

    func activateIfAuthorized() {
        // Match the app's Firebase/RevenueCat policy: local runs do not send
        // production measurement. Missing credentials also leave Meta inert.
        #if !DEBUG
        guard let configuration = MetaAppConfiguration(info: Bundle.main.infoDictionary ?? [:]) else { return }
        let authorized = ATTrackingManager.trackingAuthorizationStatus == .authorized

        // ATT controls advertiser-ID access, not whether privacy-safe app
        // activation events may be sent. Meta needs activation events even
        // when a user declines tracking so Events Manager can verify the SDK.
        if isInitialized {
            Settings.shared.isAdvertiserIDCollectionEnabled = authorized
        }
        guard UIApplication.shared.applicationState == .active else { return }

        if !isInitialized {
            Settings.shared.appID = configuration.appID
            Settings.shared.clientToken = configuration.clientToken
            // Set explicitly as well as in Info.plist; automatic logging can
            // otherwise include purchase events and remotely configured events.
            Settings.shared.isAutoLogAppEventsEnabled = false
            Settings.shared.isCodelessDebugLogEnabled = false
            Settings.shared.isAdvertiserIDCollectionEnabled = true
            ApplicationDelegate.shared.application(
                UIApplication.shared,
                didFinishLaunchingWithOptions: launchOptions
            )
            isInitialized = true
            launchOptions = nil
        }

        guard !activatedThisForeground else { return }
        activatedThisForeground = true
        AppEvents.shared.activateApp()
        #endif
    }
}

struct MetaAppConfiguration {
    let appID: String
    let clientToken: String

    init?(info: [String: Any]) {
        guard let appID = info["FacebookAppID"] as? String,
              let clientToken = info["FacebookClientToken"] as? String else { return nil }
        let trimmedID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              trimmedID.utf8.allSatisfy({ (48...57).contains($0) }),
              !trimmedToken.isEmpty,
              !trimmedToken.contains("$(") else { return nil }
        self.appID = trimmedID
        self.clientToken = trimmedToken
    }
}
