import SwiftUI
import UIKit

/// The app's type scale.
///
/// iPad is held further from the eye than a phone and has far more room, so the
/// phone's point sizes read small and leave screens looking sparse. Every fixed
/// `.system(size:)` in the app goes through this, so the whole type ramp moves
/// together instead of individual labels drifting out of proportion.
///
/// Keyed off the *idiom*, deliberately, not the size class: an iPad in Slide
/// Over is still an iPad at arm's length. That also makes the value constant for
/// the life of the process, which is what lets this be a plain `static let` that
/// non-`View` code and static font helpers can reach.
@MainActor
enum LineType {
    static let scale: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 1.45 : 1.0

    /// Scales a point size. Returns `points` unchanged on iPhone, so the phone's
    /// type is byte-for-byte what it has always been.
    static func size(_ points: CGFloat) -> CGFloat {
        scale == 1 ? points : (points * scale).rounded()
    }
}

/// How much horizontal room a screen actually has to lay itself out in.
///
/// This is deliberately *not* "iPhone vs iPad". An iPad in Slide Over is as
/// narrow as a phone and must use the phone layout, while a large iPad in
/// Split View is wide enough for the regular one. Resolving from the size
/// class (with width as a tiebreaker) means every layout decision in the app
/// follows the space available rather than the hardware, so multitasking and
/// rotation are handled by construction instead of by special cases.
enum LineLayoutClass: Equatable {
    /// Every iPhone, plus iPad in Slide Over or a narrow Split View column.
    case compact
    /// iPad full screen, or a Split View column wide enough for two columns.
    case regular
}

/// The resolved layout metrics for the current screen size.
///
/// Screens read this from the environment instead of hard-coding padding, so
/// the compact values stay byte-identical to the long-standing iPhone design
/// and the regular values are the only thing that changes on iPad.
struct LineLayoutMetrics: Equatable {
    var layoutClass: LineLayoutClass
    /// The width the metrics were resolved against — the width of the content
    /// area, not the window, so a sidebar is already excluded.
    var width: CGFloat

    var isRegular: Bool { layoutClass == .regular }
    var isCompact: Bool { layoutClass == .compact }

    /// Widest a single column of reading content should ever get. Long lines of
    /// body text stop being readable well before an iPad's full width, so wide
    /// layouts gain columns rather than gaining line length.
    ///
    /// Scales with the screen rather than sitting at a flat 720: that constant
    /// was picked against the 11" iPad (834pt) and left the 13" (1032pt) with a
    /// column stranded in the middle of the screen, reading as far too narrow
    /// for the device. The upper bound still keeps body text off unreadable
    /// line lengths, and 11" resolves to the same 720 it always did.
    var contentMaxWidth: CGFloat {
        guard isRegular else { return .infinity }
        return min(max(720, width * 0.86), 920)
    }

    /// Widest a two-column dashboard should get before it stops filling the
    /// screen and starts floating in the middle of it.
    var wideContentMaxWidth: CGFloat {
        isRegular ? 1120 : .infinity
    }

    /// Up-scale for hand-placed icon, tile and control sizes on large regular
    /// screens.
    ///
    /// Every fixed point size in the app was drawn against the phone and
    /// carried to iPad unchanged. At 11" that reads correctly, which is why
    /// this resolves to exactly 1 there and nothing about that layout moves. On
    /// a 13" the same 36pt icon sits in a card half again as wide and reads as
    /// undersized, so those constants scale with the screen instead. Text using
    /// Dynamic Type styles is unaffected; this is for the numbers we placed by
    /// hand.
    var uiScale: CGFloat {
        guard isRegular else { return 1 }
        return min(max(1, width / 834), 1.24)
    }

    /// Scales a hand-placed point size for the current screen.
    func scaled(_ value: CGFloat) -> CGFloat { value * uiScale }

    /// The page gutter, applied inside the content column.
    ///
    /// Only modestly larger than the phone's 16pt: on iPad the column is capped
    /// and centred, so it's `contentMaxWidth` — not the gutter — that keeps
    /// cards off the bezel. A large gutter on top of the cap would just squeeze
    /// the content twice.
    var horizontalPadding: CGFloat {
        isRegular ? 24 : 16
    }

    /// Top padding for a screen's first row of content.
    var topPadding: CGFloat {
        isRegular ? 28 : 24
    }

    /// Space a scrolling screen must leave at the bottom so its last row isn't
    /// hidden behind the floating tab bar. Both size classes use that same tab
    /// bar, so both reserve the same room; this exists as one named source of
    /// truth rather than the constant repeated at a dozen call sites.
    var bottomContentInset: CGFloat {
        AppLayout.floatingTabBarContentPadding
    }

    /// How wide the floating tab bar is allowed to get.
    ///
    /// Unconstrained on compact — the phone's tab bar spans the screen as it
    /// always has. On iPad a capsule stretched across 1300pt puts the five items
    /// impossibly far apart, so it stays roughly phone-sized and centred.
    var tabBarMaxWidth: CGFloat {
        isRegular ? 560 : .infinity
    }

    /// Column count for a grid of equally-weighted cards (scan tiles, history
    /// entries, settings groups).
    var cardColumns: Int {
        guard isRegular else { return 1 }
        return width >= 1000 ? 3 : 2
    }

    /// Column count for a grid of small tiles (quick links, stat chips).
    var tileColumns: Int {
        guard isRegular else { return 2 }
        return width >= 1000 ? 4 : 3
    }

    /// Spacing between cards in a grid.
    var gridSpacing: CGFloat {
        isRegular ? 18 : 14
    }

    /// True when there is room to show a primary column and a secondary
    /// companion column side by side rather than stacking them.
    var supportsSideBySide: Bool {
        isRegular && width >= 820
    }

    /// `contentMaxWidth` computed from a measured width alone.
    ///
    /// For screens presented outside the app shell - a full-screen cover, say -
    /// which never receive the shell's resolved metrics and so must derive the
    /// column from their own geometry. Kept here so there is one definition of
    /// how wide a reading column gets, rather than a second constant drifting
    /// out of step with the first.
    static func readableColumn(forWidth width: CGFloat) -> CGFloat {
        guard width >= 700 else { return width }
        return min(max(720, width * 0.86), 920)
    }

    static func resolve(sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> LineLayoutMetrics {
        // The class comes from the size class alone, never from width. The size
        // class is a scene-level trait, so the window and the detail column
        // inside it always agree — the app can't end up showing the sidebar
        // while the screen beside it lays itself out as a phone. Width is still
        // measured, but it only ever tunes *how many* columns a regular layout
        // gets, never whether it is regular at all.
        LineLayoutMetrics(layoutClass: sizeClass == .regular ? .regular : .compact, width: width)
    }
}

private struct LineLayoutKey: EnvironmentKey {
    // A phone-width compact default so any view rendered outside a provider
    // (previews, detached sheets) keeps today's iPhone layout.
    static let defaultValue = LineLayoutMetrics(layoutClass: .compact, width: 393)
}

extension EnvironmentValues {
    var lineLayout: LineLayoutMetrics {
        get { self[LineLayoutKey.self] }
        set { self[LineLayoutKey.self] = newValue }
    }
}

extension View {
    /// Measures the receiver and publishes `\.lineLayout` to its children.
    ///
    /// Apply this to a *content area*, not the window, so the published width
    /// excludes any sidebar and screens size themselves against the room they
    /// were actually given.
    func providesLineLayout() -> some View {
        modifier(LineLayoutProvider())
    }

    /// Constrains a screen's content to a readable single-column width and
    /// centres it. A no-op on compact, where `contentMaxWidth` is `.infinity`.
    func lineContentColumn(_ maxWidth: CGFloat? = nil) -> some View {
        modifier(LineContentColumn(explicitMaxWidth: maxWidth))
    }

    /// Bottom padding that clears the floating tab bar on compact, and shrinks
    /// to a plain margin on regular where the sidebar replaces that tab bar.
    ///
    /// This reads the environment itself so call sites don't each have to
    /// declare an `@Environment` property — several of them live in small
    /// private view structs where that would be pure noise.
    ///
    /// - Parameters:
    ///   - adjust: Added to the inset, for screens that already sat closer to
    ///     the tab bar than the default.
    ///   - atLeast: A floor, for screens that must also clear the home indicator.
    func lineBottomInset(adjust: CGFloat = 0, atLeast minimum: CGFloat = 0) -> some View {
        modifier(LineBottomInset(adjust: adjust, minimum: minimum))
    }
}

private struct LineBottomInset: ViewModifier {
    @Environment(\.lineLayout) private var layout
    let adjust: CGFloat
    let minimum: CGFloat

    func body(content: Content) -> some View {
        content.padding(.bottom, max(minimum, max(0, layout.bottomContentInset + adjust)))
    }
}

private struct LineLayoutProvider: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .environment(\.lineLayout, .resolve(sizeClass: sizeClass, width: width))
    }
}

private struct LineContentColumn: ViewModifier {
    @Environment(\.lineLayout) private var layout
    let explicitMaxWidth: CGFloat?

    func body(content: Content) -> some View {
        let limit = explicitMaxWidth ?? layout.contentMaxWidth
        // `.infinity` here means "unconstrained", which is exactly the compact
        // behaviour, so the phone layout passes through this untouched.
        content
            .frame(maxWidth: limit)
            .frame(maxWidth: .infinity)
    }
}
