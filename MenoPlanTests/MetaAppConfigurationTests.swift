import XCTest
@testable import MenoPlan

final class MetaAppConfigurationTests: XCTestCase {
    func testUnconfiguredBuildCannotInitializeMeta() {
        let configurations: [[String: Any]] = [
            [:],
            ["FacebookAppID": "", "FacebookClientToken": ""],
            ["FacebookAppID": "$(META_APP_ID)", "FacebookClientToken": "$(META_CLIENT_TOKEN)"],
            ["FacebookAppID": "123456789", "FacebookClientToken": "$(META_CLIENT_TOKEN)"],
            ["FacebookAppID": "123456789", "FacebookClientToken": "   "],
            ["FacebookAppID": "fb123456789", "FacebookClientToken": "test-client-token"]
        ]
        for info in configurations {
            XCTAssertNil(MetaAppConfiguration(info: info))
        }
    }

    func testConfiguredBuildReadsTrimmedValues() throws {
        let configuration = try XCTUnwrap(MetaAppConfiguration(info: [
            "FacebookAppID": " 123456789\n",
            "FacebookClientToken": " test-client-token\n"
        ]))
        XCTAssertEqual(configuration.appID, "123456789")
        XCTAssertEqual(configuration.clientToken, "test-client-token")
    }

    func testBundledDefaultsDisableAutomaticCollection() {
        let info = Bundle(for: FirebaseAppDelegate.self).infoDictionary ?? [:]
        for key in ["FacebookAutoInitEnabled", "FacebookAutoLogAppEventsEnabled",
                    "FacebookAdvertiserIDCollectionEnabled", "FacebookCodelessDebugLogEnabled"] {
            XCTAssertEqual(info[key] as? Bool, false, key)
        }
    }
}
