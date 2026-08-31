import SwiftUI
import UIKit

// MARK: - Colour

/// Menoplan intentionally shares Linecheck's clear, high-contrast visual system. The
/// subject changes; the visual language does not.
enum MenoColor {
    static let canvas = Color(red: 0.97, green: 0.98, blue: 1.00)
    static let surface = Color.white
    static let surfaceAlt = Color(red: 0.93, green: 0.90, blue: 1.00)

    static let ink = Color(red: 0.03, green: 0.10, blue: 0.31)
    static let inkSecondary = ink.opacity(0.64)
    static let inkTertiary = ink.opacity(0.46)
    static let rule = Color(red: 0.85, green: 0.83, blue: 0.96)

    static let primary = Color(red: 0.38, green: 0.20, blue: 0.95)
    static let primarySoft = Color(red: 0.93, green: 0.90, blue: 1.00)
    static let accent = Color(red: 1.00, green: 0.19, blue: 0.47)
    static let accentSoft = Color(red: 1.00, green: 0.91, blue: 0.94)
    static let onPrimary = Color.white

    static let secondary = Color(red: 0.02, green: 0.62, blue: 0.70)
    static let positive = Color(red: 0.02, green: 0.62, blue: 0.70)
    static let caution = Color(red: 0.97, green: 0.55, blue: 0.14)
    static let alert = accent

    static let shadow = primary.opacity(0.08)

    static let uiCanvas = UIColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1)
    static let uiRule = UIColor(red: 0.85, green: 0.83, blue: 0.96, alpha: 1)
    static let uiInk = UIColor(red: 0.03, green: 0.10, blue: 0.31, alpha: 1)

}

// MARK: - Type

/// Rounded system type shares Linecheck's approachable clarity while retaining generous
/// sizes for easy reading.
enum MenoFont {
    static let display = Font.system(.title2, design: .rounded).weight(.bold)
    static let title = Font.system(.title3, design: .rounded).weight(.bold)
    static let heading = Font.system(.headline, design: .rounded).weight(.bold)

    /// Primary reading text — `.callout` (16pt), a clear step above secondary prose.
    static let body = Font.system(.callout)
    /// Secondary prose — `.subheadline` (15pt), one step down from body.
    static let secondary = Font.system(.subheadline)
    static let caption = Font.system(.footnote)
    static let label = Font.system(.footnote).weight(.medium)

    /// Figures use monospaced digits so columns align and values do not jitter.
    static let metric = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
    static let metricSmall = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
    static let mono = Font.system(.footnote).monospacedDigit()
}

// MARK: - Metrics

enum MenoSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 26
    static let xxxl: CGFloat = 32
    static let gutter: CGFloat = 16
}

enum MenoMetric {
    /// Softly rounded corners — friendly without tipping into decorative.
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 11
    static let hairline: CGFloat = 1
    /// Comfortably above the 44pt HIG minimum.
    static let touchTarget: CGFloat = 46
}
