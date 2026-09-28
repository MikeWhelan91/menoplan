import SwiftUI
import WidgetKit

/// App colours from Constants.swift - duplicated because the extension
/// doesn't compile the app's UI layer. Each has a dark-mode variant so the
/// widgets follow the Home Screen's appearance (the app itself stays light).
extension Color {
    static let wNavy = adaptive(light: (0.03, 0.10, 0.31), dark: (0.93, 0.94, 0.99))
    static let wPink = adaptive(light: (1.0, 0.19, 0.47), dark: (1.0, 0.40, 0.60))
    static let wPurple = adaptive(light: (0.38, 0.20, 0.95), dark: (0.64, 0.55, 1.0))
    static let wTeal = adaptive(light: (0.02, 0.62, 0.70), dark: (0.25, 0.80, 0.86))
    static let wPinkSoft = Color(red: 1.0, green: 0.91, blue: 0.94)
    static let wPurpleSoft = Color(red: 0.93, green: 0.90, blue: 1.0)
    /// Chips and secondary buttons sitting on the backdrop.
    static let wSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 1, alpha: 0.80) })
    /// Text drawn on a solid `wNavy` fill (today's date).
    static let wOnInk = adaptive(light: (1, 1, 1), dark: (0.07, 0.07, 0.07))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

struct WidgetBrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        Image("WidgetBrandMark")
            .resizable()
            .widgetAccentedRenderingMode(.accentedDesaturated)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// Not set up or ended: nothing to count down, so a centred
/// message with one clear next step instead of an empty countdown.
/// Shown before setup, or while a person still having periods hasn't
/// logged one yet.
struct WidgetIdleView: View {
    let summary: WidgetCycleSummary
    var compact = false

    private var icon: String { summary.state == .needsPeriod ? "calendar.badge.plus" : "sparkles" }
    private var action: String { summary.state == .needsPeriod ? "Add period" : "Open MenoPlan" }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: compact ? 18 : 20, weight: .bold))
                .foregroundStyle(Color.wPink)
                .frame(width: 40, height: 40)
                .background(Color.wPink.opacity(0.12), in: Circle())
                .widgetAccentable()
            Text(summary.state == .needsPeriod ? "Add your last period" : "Set up MenoPlan")
                .font(.widget(size: 17, weight: .heavy))
                .foregroundStyle(Color.wNavy)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if !compact {
                Text(summary.detail)
                    .font(.widget(.caption, weight: .medium))
                    .foregroundStyle(Color.wNavy.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(action)
                .font(.widget(.caption, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.wPink, in: Capsule())
                .widgetAccentable()
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WidgetBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.13), Color(white: 0.07)]
                : [Color.white, Color.wPinkSoft.opacity(0.55), Color.wPurpleSoft.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// One entry per midnight for a week: everything shown is derived from the
/// entry date, so it stays correct without the app refreshing the snapshot.
enum WidgetTimeline {
    static func dates(from now: Date, days: Int = 7, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return [now] + (1...days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
}

/// The app's typeface (Plus Jakarta Sans, bundled in the extension too), with
/// the same weight mapping as the app's `AppFont`.
extension Font {
    private static func widgetFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: "PlusJakartaSans-Regular"
        case .medium: "PlusJakartaSans-Medium"
        case .semibold: "PlusJakartaSans-SemiBold"
        case .bold, .heavy: "PlusJakartaSans-Bold"
        default: "PlusJakartaSans-ExtraBold"
        }
    }

    static func widget(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(widgetFace(weight), fixedSize: size)
    }

    static func widget(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat = switch style {
        case .headline, .body: 17
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
        return .custom(widgetFace(weight), size: size, relativeTo: style)
    }
}
