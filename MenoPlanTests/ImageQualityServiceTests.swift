import XCTest
import UIKit
@testable import MenoPlan

final class ImageQualityServiceTests: XCTestCase {
    private let service = ImageQualityService()

    func testGlareRangeIsFlaggedOverexposed() {
        // Three confirmed real cases had a genuine faint positive read as
        // negative, each with roughly 81-84% of the frame blown out to a
        // saturated highlight - overexposure is fractionOfSaturatedPixels
        // (the share of pixels with every RGB channel >= 250), not average
        // brightness. A flat solid colour at 210/255 measures 0% saturated
        // pixels (210 is below the 250 cutoff) and would fall through to the
        // blur check instead. This fixture blows out ~82% of the frame to
        // pure white and leaves the rest a mid-tone, matching the confirmed
        // incidents' actual saturated-pixel share.
        let size = CGSize(width: 200, height: 200)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 1.0, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.82, width: size.width, height: size.height * 0.18))
        }
        let result = service.score(image)
        XCTAssertEqual(result.status, .overexposed)
        XCTAssertGreaterThan(result.overexposure, 0.78)
    }

    func testOrdinaryBrightPhotoStaysGood() {
        // A flat solid colour has zero texture and would trip the unrelated
        // blur check regardless of brightness, so this uses a checkerboard
        // averaging to the same brightness with real local contrast - this
        // is testing the overexposure threshold specifically, not blur.
        let image = checkerboardImage(averageWhite: 170, delta: 30)
        let result = service.score(image)
        XCTAssertEqual(result.status, .good)
    }

    func testPregnancyTestSurfaceGateRequiresBroadBrightNeutralMaterial() {
        XCTAssertTrue(service.hasPlausiblePregnancyTestSurface(solidColorImage(white: 220)))
        XCTAssertFalse(service.hasPlausiblePregnancyTestSurface(checkerboardImage(averageWhite: 58, delta: 38)))
    }

    func testOvulationTestSurfaceGateUsesTheSameNonTestProtection() {
        XCTAssertTrue(service.hasPlausibleOvulationTestSurface(solidColorImage(white: 220)))
        XCTAssertFalse(service.hasPlausibleOvulationTestSurface(checkerboardImage(averageWhite: 58, delta: 38)))
    }

    func testWarmSkinLikeSurfaceCannotPassAsATest() {
        let warmSurface = solidColorImage(red: 0.76, green: 0.68, blue: 0.60)
        XCTAssertFalse(service.hasPlausiblePregnancyTestSurface(warmSurface))
        XCTAssertFalse(service.hasPlausibleOvulationTestSurface(warmSurface))
    }

    func testBroadPinkTestMembranePassesTheSurfaceGate() {
        let pinkMembrane = solidColorImage(red: 0.92, green: 0.58, blue: 0.58)
        XCTAssertTrue(service.hasPlausiblePregnancyTestSurface(pinkMembrane))
        XCTAssertTrue(service.hasPlausibleOvulationTestSurface(pinkMembrane))
    }


    private func solidColorImage(white: CGFloat, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: white / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func solidColorImage(red: CGFloat, green: CGFloat, blue: CGFloat, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func checkerboardImage(averageWhite: CGFloat, delta: CGFloat, size: CGSize = CGSize(width: 200, height: 200), cell: CGFloat = 10) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let light = UIColor(white: min(255, averageWhite + delta) / 255, alpha: 1)
            let dark = UIColor(white: max(0, averageWhite - delta) / 255, alpha: 1)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    ((row + col).isMultiple(of: 2) ? light : dark).setFill()
                    context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}
