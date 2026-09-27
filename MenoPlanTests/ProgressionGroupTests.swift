import XCTest
@testable import MenoPlan

final class ProgressionGroupTests: XCTestCase {
    func testScanIDsRoundTripThroughRawStorage() {
        let ids = [UUID(), UUID(), UUID()]
        let group = ProgressionGroup(name: "Sept cycle", testType: .ovulation, scanIDs: ids)

        XCTAssertEqual(group.scanIDs, ids)
        XCTAssertEqual(group.scanIDsRaw.components(separatedBy: "|").count, 3)
    }

    func testAppendingPreservesOrderAndUpdatesTimestamp() {
        let group = ProgressionGroup(name: "Sept cycle", testType: .pregnancy)
        let originalUpdatedAt = group.updatedAt
        let first = UUID()
        let second = UUID()

        Thread.sleep(forTimeInterval: 0.01)
        group.scanIDs = [first, second]

        XCTAssertEqual(group.scanIDs, [first, second])
        XCTAssertGreaterThan(group.updatedAt, originalUpdatedAt)
    }

    func testEmptyGroupHasNoScanIDs() {
        let group = ProgressionGroup(name: "Empty", testType: .pregnancy)
        XCTAssertTrue(group.scanIDs.isEmpty)
    }
}
