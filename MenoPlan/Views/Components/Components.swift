import SwiftUI
import UIKit
import PopupView

struct LineCheckBrandBackdrop: View {
    var animated: Bool = false
    var confineOrbsToTop: Bool = false
    @State private var pinkOffset: CGSize
    @State private var purpleOffset: CGSize
    @State private var blueOffset: CGSize
    @State private var purpleSmallOffset: CGSize
    @State private var rowTwoPinkOffset = CGSize(width: 100, height: -140)
    @State private var rowTwoPurpleOffset = CGSize(width: -110, height: -100)

    @State private var containerSize: CGSize = .zero

    private var mainOrbScale: CGFloat { confineOrbsToTop ? 1.1 : 1.0 }

    /// Wide enough that the phone-tuned fixed orb offsets no longer fill the
    /// screen. Measured, not derived from the idiom, so Split View and Slide
    /// Over get the layout that matches the room they actually have.
    private var isWide: Bool { containerSize.width >= 700 }

    init(animated: Bool = false, confineOrbsToTop: Bool = false) {
        self.animated = animated
        self.confineOrbsToTop = confineOrbsToTop
        if confineOrbsToTop {
            _pinkOffset = State(initialValue: CGSize(width: 120, height: -380))
            _purpleOffset = State(initialValue: CGSize(width: -140, height: -320))
            _blueOffset = State(initialValue: CGSize(width: 60, height: -280))
            _purpleSmallOffset = State(initialValue: CGSize(width: -90, height: -420))
        } else {
            _pinkOffset = State(initialValue: CGSize(width: 190, height: -310))
            _purpleOffset = State(initialValue: CGSize(width: -210, height: 300))
            _blueOffset = State(initialValue: CGSize(width: 150, height: 260))
            _purpleSmallOffset = State(initialValue: CGSize(width: -160, height: -260))
        }
    }

    var body: some View {
        ZStack {
            Color.lineBackground

            // Tuned for a phone, where it is one of only two orbs and has to
            // carry the whole backdrop. On a wide layout it sits among the
            // others, so its heavier opacity and hard 4pt edge make it stand
            // out as the one obvious disc on the screen - matched to the rest
            // there instead.
            let heroIsCrowded = isWide && !confineOrbsToTop
            Circle()
                .fill(Color.linePink.opacity(heroIsCrowded ? 0.07 : (confineOrbsToTop ? 0.10 : 0.12)))
                .frame(width: 330 * mainOrbScale, height: 330 * mainOrbScale)
                .blur(radius: heroIsCrowded ? 10 : 4)
                .offset(pinkOffset)

            // Centred on wide layouts: its phone offset puts it in the
            // bottom-left corner, which on an iPad reads as a stray disc in
            // the corner rather than part of the backdrop. Centred it also
            // sits behind the content, so it's lightened and softened to stay
            // ambient instead of becoming the focal point of the screen.
            let isCentred = isWide && !confineOrbsToTop
            Circle()
                .fill((confineOrbsToTop ? Color.linePink : Color.linePurple).opacity(isCentred ? 0.05 : 0.09))
                .frame(width: 300 * mainOrbScale, height: 300 * mainOrbScale)
                .blur(radius: isCentred ? 10 : 6)
                .offset(isCentred ? .zero : purpleOffset)

            // Extra orbs only render while animated, so this stays scoped to
            // loading screens and doesn't change the look of the 30+ static
            // background usages elsewhere in the app.
            if animated {
                Circle()
                    .fill(Color.lineBlue.opacity(0.08))
                    .frame(width: 220 * mainOrbScale, height: 220 * mainOrbScale)
                    .blur(radius: 5)
                    .offset(blueOffset)

                Circle()
                    .fill(Color.linePurple.opacity(0.06))
                    .frame(width: 170 * mainOrbScale, height: 170 * mainOrbScale)
                    .blur(radius: 5)
                    .offset(purpleSmallOffset)
            }

            // Second row of orbs, sitting below the first row but still
            // above the loading-screen content beneath.
            if confineOrbsToTop {
                Circle()
                    .fill(Color.linePink.opacity(0.07))
                    .frame(width: 220, height: 220)
                    .blur(radius: 6)
                    .offset(rowTwoPinkOffset)

                Circle()
                    .fill(Color.linePurple.opacity(0.06))
                    .frame(width: 240, height: 240)
                    .blur(radius: 6)
                    .offset(rowTwoPurpleOffset)
            }

            // The orbs above are fixed point sizes at fixed offsets, tuned so
            // two of them fill a phone. On an iPad they cover a fraction of
            // the screen and leave large empty areas - most visible on a
            // sparse screen like Luna's chat - so wide layouts get a second
            // set placed proportionally to the space actually available.
            GeometryReader { proxy in
                if proxy.size.width >= 700 {
                    wideOrbs(in: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .allowsHitTesting(false)
        .task {
            guard animated else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 3.2)) {
                    if confineOrbsToTop {
                        pinkOffset = CGSize(width: .random(in: 60...220), height: .random(in: -420...(-280)))
                        purpleOffset = CGSize(width: .random(in: -220...(-60)), height: .random(in: -380...(-240)))
                        blueOffset = CGSize(width: .random(in: 20...200), height: .random(in: -340...(-200)))
                        purpleSmallOffset = CGSize(width: .random(in: -200...(-20)), height: .random(in: -440...(-300)))
                        rowTwoPinkOffset = CGSize(width: .random(in: 40...180), height: .random(in: -180...(-60)))
                        rowTwoPurpleOffset = CGSize(width: .random(in: -190...(-40)), height: .random(in: -160...(-40)))
                    } else {
                        pinkOffset = CGSize(width: .random(in: 90...270), height: .random(in: -360...(-220)))
                        purpleOffset = CGSize(width: .random(in: -280...(-90)), height: .random(in: 220...360))
                        blueOffset = CGSize(width: .random(in: 60...220), height: .random(in: 160...320))
                        purpleSmallOffset = CGSize(width: .random(in: -260...(-80)), height: .random(in: -320...(-140)))
                    }
                }
                try? await Task.sleep(for: .seconds(3.2))
            }
        }
    }

    /// Positions are fractions of the container, so the same set works at any
    /// iPad size and in Split View rather than needing per-device offsets.
    /// Kept to the existing palette and opacity range so this reads as more of
    /// the same backdrop, not a different one.
    @ViewBuilder
    private func wideOrbs(in size: CGSize) -> some View {
        let unit = min(size.width, size.height)
        let orbs: [(x: CGFloat, y: CGFloat, d: CGFloat, color: Color, opacity: Double)] = [
            (0.86, 0.34, 0.50, .linePurple, 0.065),
            (0.08, 0.40, 0.42, .lineBlue, 0.055),
            (0.66, 0.72, 0.54, .linePink, 0.075),
            (0.30, 0.14, 0.38, .linePurple, 0.05),
            (0.92, 0.90, 0.44, .linePurple, 0.065),
            (0.18, 0.86, 0.46, .linePurple, 0.06),
            (0.06, 0.06, 0.34, .linePink, 0.05)
        ]
        ForEach(Array(orbs.enumerated()), id: \.offset) { _, orb in
            let diameter = unit * orb.d
            Circle()
                .fill(orb.color.opacity(orb.opacity))
                .frame(width: diameter, height: diameter)
                // Blur proportional to the orb rather than a fixed 6pt, which
                // at these sizes leaves a visibly hard edge. Kept near the
                // ratio the phone orbs use - push it much past this and they
                // stop reading as distinct bubbles and smear into one wash.
                .blur(radius: diameter * 0.03)
                .position(x: size.width * orb.x, y: size.height * orb.y)
        }
    }
}

struct AppIconBrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        Image("BrandAppIcon")
            .resizable()
            .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: max(2, size * 0.035))
        }
        .shadow(color: Color.linePurple.opacity(0.14), radius: size * 0.22, y: size * 0.10)
        .accessibilityHidden(true)
    }
}

struct BrandedModalCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.linePurpleSoft,
                            Color.linePinkSoft,
                            Color.white.opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color.linePink.opacity(0.10))
                        .frame(width: 190, height: 190)
                        .offset(x: 150, y: -140)

                    Circle()
                        .fill(Color.linePurple.opacity(0.08))
                        .frame(width: 160, height: 160)
                        .offset(x: -155, y: 155)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.76), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.linePurple.opacity(0.20), radius: 28, y: 16)
    }
}

struct BrandedLoadingScreen: View {
    var title: String
    var showsBackdrop = true
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            if showsBackdrop {
                LineCheckBrandBackdrop(animated: true)
            }

            VStack(spacing: 24) {
                AppIconBrandMark(size: 92)
                    .scaleEffect(isAnimating ? 1.04 : 0.94)

                Text(title)
                    .font(.app(size: LineType.size(36), weight: .heavy))
                    .foregroundStyle(Color.linePink)
                    .multilineTextAlignment(.center)

                Capsule()
                    .fill(Color.lineNavy.opacity(0.08))
                    .frame(width: 180, height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.linePurple, .linePink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 76, height: 8)
                            .offset(x: isAnimating ? 104 : 0)
                    }
                    .clipShape(Capsule())
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct LoadingStepDots: View {
    var count: Int
    var currentIndex: Int
    var accentColor: Color = .linePink

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? accentColor : Color.lineNavy.opacity(0.15))
                    .frame(width: index == currentIndex ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
    }
}

#if DEBUG
struct DebugLoadingScreenPreview: View {
    var onClose: () -> Void
    @State private var scanLineAtBottom = false
    @State private var statusPhraseIndex = 0

    private let statusPhrases = [
        "Comparing the visible control and test lines",
        "Checking line color against the background",
        "Measuring line position within the window",
        "Cross-checking against your adjusted photo",
        "Weighing image sharpness and lighting"
    ]

    var body: some View {
        ZStack {
            LineCheckBrandBackdrop(animated: true, confineOrbsToTop: true)

            VStack(spacing: 0) {
                Spacer()

                if let image = UIImage(named: "TestLineReference") {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                        .overlay {
                            GeometryReader { proxy in
                                LinearGradient(
                                    colors: [.clear, Color.linePink.opacity(0.9), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(height: 3)
                                .shadow(color: Color.linePink.opacity(0.55), radius: 8)
                                .offset(y: scanLineAtBottom ? max(0, proxy.size.height - 3) : 0)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .frame(maxWidth: 420)
                }

                Text(statusPhrases[statusPhraseIndex])
                    .font(.app(size: LineType.size(30), weight: .heavy))
                    .foregroundStyle(Color.linePink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 64)
                    .id(statusPhraseIndex)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .opacity
                    ))

                LoadingStepDots(count: statusPhrases.count, currentIndex: statusPhraseIndex)
                    .padding(.top, 36)

                Label("Your photo never leaves this device", systemImage: "lock.shield")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.45))
                    .padding(.top, 62)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 22)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: LineType.size(15), weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.86), in: Circle())
                            .contentShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                    .accessibilityLabel("Close loading screen preview")
                }
                Spacer()
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                scanLineAtBottom = true
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.4))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    statusPhraseIndex = (statusPhraseIndex + 1) % statusPhrases.count
                }
            }
        }
    }
}
#endif

struct BrandedNoticeOverlay: View {
    var icon: String
    var imageName: String? = nil
    var usesLunaArtwork: Bool = false
    var showsIcon: Bool = true
    var title: String
    var message: String
    var primaryTitle: String
    var secondaryTitle: String? = nil
    var primaryAction: () -> Void
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.lineNavy.opacity(0.30)
                .ignoresSafeArea()

            BrandedModalCard {
                VStack(spacing: 18) {
                    if showsIcon {
                        if usesLunaArtwork {
                            LunaAvatarView(size: 112)
                                .accessibilityHidden(true)
                        } else if let imageName {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 46, height: 42)
                                .frame(width: 68, height: 68)
                                .background(Color.white.opacity(0.76), in: Circle())
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: LineType.size(26), weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.linePurple, .linePink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .background(Color.white.opacity(0.76), in: Circle())
                        }
                    }

                    VStack(spacing: 7) {
                        Text(title)
                            .font(.app(size: LineType.size(24), weight: .heavy))
                            .foregroundStyle(Color.lineNavy)
                            .multilineTextAlignment(.center)
                        Text(message)
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(Color.lineNavy.opacity(0.64))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 10) {
                        Button(primaryTitle, action: primaryAction)
                            .buttonStyle(.primaryLine)

                        if let secondaryTitle, let secondaryAction {
                            Button(secondaryTitle, action: secondaryAction)
                                .buttonStyle(.secondaryLine)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: 390)
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(50)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

struct LineCheckLogoMark: View {
    var body: some View {
        ZStack {
            SealShape()
                .fill(Color.linePink)
            CheckShape()
                .stroke(Color.lineNavy, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .padding(18)
        }
        .accessibilityHidden(true)
    }
}

struct SealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let points = 16
        let outer = min(rect.width, rect.height) * 0.50
        let inner = outer * 0.84
        var path = Path()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = (Double(index) / Double(points * 2)) * Double.pi * 2 - Double.pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY + rect.height * 0.10))
        return path
    }
}

struct ResultBadge: View {
    var result: ScanResultType
    var body: some View {
        Text(result.badgeTitle)
            .font(.app(.caption2, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(result.tint)
            .background(result.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(result.title)
    }
}

struct TestIllustration: View {
    var testType: TestType
    var result: ScanResultType = .faintLineDetected
    var compact = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 10 : 16)
                .fill(Color.white)
                .stroke(Color.black.opacity(0.10))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
            HStack(spacing: compact ? 10 : 16) {
                window
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.965, green: 0.970, blue: 0.985))
                    .frame(width: compact ? 34 : 48, height: compact ? 24 : 34)
                    .overlay(Circle().stroke(Color.black.opacity(0.22), lineWidth: 1).frame(width: compact ? 16 : 22))
            }
            .padding(.horizontal, compact ? 10 : 16)
        }
        .frame(width: compact ? 78 : 156, height: compact ? 48 : 74)
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(red: 0.965, green: 0.970, blue: 0.985))
            .frame(width: compact ? 38 : 76, height: compact ? 24 : 36)
            .overlay(alignment: .center) {
                HStack(spacing: compact ? 10 : 18) {
                    line(alpha: testAlpha)
                    line(alpha: controlAlpha)
                }
            }
            .overlay(alignment: .top) {
                HStack(spacing: compact ? 8 : 16) {
                    Text("T")
                    Text("C")
                }
                .font(.system(size: LineType.size(compact ? 5 : 7), weight: .bold))
                .foregroundStyle(Color.lineNavy.opacity(0.20))
                .offset(y: compact ? -8 : -10)
            }
    }

    private var controlAlpha: Double { result == .invalid ? 0.08 : 0.95 }
    private var testAlpha: Double {
        switch result {
        case .appearsPositive, .peak: 0.95
        case .faintLineDetected, .high: 0.55
        case .rising: 0.34
        case .low: 0.16
        default: 0.06
        }
    }
    private func line(alpha: Double) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(testType.tint.opacity(alpha)).frame(width: compact ? 3 : 5, height: compact ? 18 : 28)
    }
}

struct ActionPanel: View {
    var title: String
    var subtitle: String
    var testType: TestType
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.lineHeadline()).foregroundStyle(testType.tint)
                    Text(subtitle).font(.lineSubheadline()).foregroundStyle(Color.lineNavy)
                }
                Spacer()
                TestIllustration(testType: testType, result: testType == .pregnancy ? .faintLineDetected : .high, compact: true)
            }
            .padding(16)
            .background(testType == .pregnancy ? Color.linePinkSoft : Color.linePurpleSoft, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct AppScreenHeader: View {
    var title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    var centered = false
    var titleSize: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: centered ? .center : .leading, spacing: subtitle == nil ? 0 : 6) {
                Text(title)
                    .font(.lineTitle(titleSize))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(centered ? .center : .leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.lineSubheadline(.medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.64))
                        .multilineTextAlignment(centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)

            if !centered {
                Spacer(minLength: 12)
            }

            if let trailing {
                trailing
            }
        }
    }
}

struct AppCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.88), Color.linePurpleSoft.opacity(0.48)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.80), lineWidth: 1)
            )
            .shadow(color: Color.linePurple.opacity(0.06), radius: 12, y: 6)
    }
}

struct AppFilterChip: View {
    var title: String
    var selected: Bool

    var body: some View {
        Text(title)
            .font(.app(.subheadline, weight: .semibold))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.lineNavy)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [.linePurple, .linePink], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.white.opacity(0.76)),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.lineBlue : Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

struct SettingsActionRow: View {
    var title: String
    var detail: String? = nil
    var tint: Color = .lineNavy
    var systemImage: String? = nil
    var isInteractive = false

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: LineType.size(15), weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.10), in: Circle())
            }

            Text(title)
                .font(.lineSubheadline(.semibold))
                .foregroundStyle(isInteractive ? tint : Color.lineNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            Spacer(minLength: 12)

            if let detail {
                Text(detail)
                    .font(.lineCaption(.semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(tint.opacity(0.72))
            }
        }
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.lineSubheadline(.semibold))
                .foregroundStyle(Color.lineNavy)
        }
        .tint(Color.lineBlue)
    }
}

struct EmptyStateView: View {
    enum IllustrationStyle {
        case none
        case generic
        case homeTile(TestType)
        /// A large SF Symbol in a tinted circle - for empty states about a
        /// concept (a feature, a grouping) rather than a specific saved test,
        /// where a pregnancy/ovulation test mockup wouldn't make sense.
        case icon(name: String, tint: Color)
    }

    var title: String
    var message: String
    var buttonTitle: String?
    var action: (() -> Void)?
    var illustrationStyle: IllustrationStyle = .generic
    var isCard: Bool = true

    var body: some View {
        VStack(spacing: 14) {
            illustration
            Text(title).font(.lineHeadline()).foregroundStyle(Color.lineNavy)
            Text(message).font(.lineSubheadline()).foregroundStyle(Color.lineNavy.opacity(0.62)).multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(.primaryLine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(isCard ? 24 : 0)
        .background {
            if isCard {
                LinearGradient(
                    colors: [Color.linePinkSoft.opacity(0.72), Color.linePurpleSoft.opacity(0.64)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .overlay {
            if isCard {
                RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.78))
            }
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch illustrationStyle {
        case .none:
            EmptyView()
        case .generic:
            TestIllustration(testType: .pregnancy, result: .faintLineDetected)
        case .homeTile(let testType):
            CalendarEmptyStateTestImage(testType: testType)
        case .icon(let name, let tint):
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 88, height: 88)
                Image(systemName: name)
                    .font(.system(size: LineType.size(36), weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

private struct CalendarEmptyStateTestImage: View {
    var testType: TestType

    private var assetName: String {
        testType == .pregnancy ? "HomePregnancyTest" : "HomeOvulationTest"
    }

    var body: some View {
        Group {
            if let uiImage = UIImage.lineCheckLibraryImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                TestIllustration(testType: testType, result: testType == .pregnancy ? .faintLineDetected : .high)
            }
        }
        .frame(maxWidth: 320)
        .frame(height: testType == .pregnancy ? 120 : 94)
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension UIImage {
    static func lineCheckLibraryImage(named name: String) -> UIImage? {
        if let image = UIImage(named: name) { return image }
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "images") {
            return UIImage(contentsOfFile: url.path)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }
}

struct InlineTip: View {
    var title: String
    var message: String
    var icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Color.lineBlue)
                .frame(width: 28, height: 28)
                .background(Color.lineBlue.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.lineSubheadline(.semibold))
                    .foregroundStyle(Color.lineNavy)
                Text(message)
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06)))
    }
}

struct SafetyFooter: View {
    var sourceAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(AppConstants.safetyCopy)
                .font(.app(.caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let sourceAction {
                Button("Medical Sources", action: sourceAction)
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lineBlue)
                    .buttonStyle(.plain)
            } else {
                Text("Sources are listed in Settings > Medical Sources.")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lineBlue.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MedicalSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppConstants.safetyCopy)
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Safety")
                }

                Section {
                    ForEach(AppConstants.medicalSources) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.title)
                                    .font(.app(.subheadline, weight: .semibold))
                                    .foregroundStyle(Color.lineNavy)
                                Text(source.publisher)
                                    .font(.app(.caption, weight: .semibold))
                                    .foregroundStyle(Color.lineBlue)
                                Text(source.detail)
                                    .font(.app(.caption))
                                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Sources")
                } footer: {
                    Text("MenoPlan uses these public references for general home-test, LH, hCG, fertile-window, and repeat-testing guidance. Brand test instructions remain the final reference for a specific test.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { LineCheckBrandBackdrop() }
            .navigationTitle("Medical Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.lineBlue)
    }
}

struct InfoSheet: View {
    var title: String
    var message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                bodyCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { LineCheckBrandBackdrop() }
        .safeAreaInset(edge: .bottom) {
            Button("Done") { dismiss() }
                .buttonStyle(.primaryLine)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.linePurple, Color.linePink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.lineBlue.opacity(0.18), radius: 20, y: 10)

                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: LineType.size(28), weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.app(size: LineType.size(28), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)

                Text("MenoPlan guide")
                    .font(.app(size: LineType.size(12), weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Color.lineBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.lineBlue.opacity(0.10), in: Capsule())
            }
        }
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.app(size: LineType.size(19), weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.78))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.fill")
                    .font(.system(size: LineType.size(14), weight: .bold))
                    .foregroundStyle(Color.linePurple)
                    .frame(width: 30, height: 30)
                    .background(Color.linePurple.opacity(0.10), in: Circle())

                Text("Ratios and labels are image-based guidance only. Use the physical test and its instructions as the final reference.")
                    .font(.app(size: LineType.size(14), weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.linePinkSoft.opacity(0.74), Color.linePurpleSoft.opacity(0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: Color.lineBlue.opacity(0.08), radius: 22, y: 10)
    }
}

/// One labeled section of a parsed Luna AI-summary reply. Shared by every
/// screen that renders a saved AI summary (Compare, History's saved
/// comparisons, Progression) so the same reply always looks the same
/// wherever it's shown, instead of each screen keeping its own copy of this
/// parsing logic.
struct AITextSection: Identifiable {
    let id = UUID()
    let title: String?
    let body: String
}

enum AISummaryFormatting {
    /// Splits a Luna reply into labeled sections (e.g. "Summary", "What
    /// changed") for a structured card layout. Falls back to one untitled
    /// section if the reply doesn't use any of the recognised labels.
    static func sections(from summary: String) -> [AITextSection] {
        let labels = ["Quick read", "Summary", "What changed", "Why it matters", "What to watch", "Read confidence note", "Next step"]
        var cleaned = summary
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for label in labels {
            cleaned = cleaned.replacingOccurrences(of: "\(label):", with: "\n\n\(label)\n")
            cleaned = cleaned.replacingOccurrences(of: "\(label) ", with: "\n\n\(label)\n")
        }

        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var sections: [AITextSection] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flush() {
            let body = currentBody.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            sections.append(AITextSection(title: currentTitle, body: body))
        }

        for line in lines {
            if labels.contains(line) {
                flush()
                currentTitle = line
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        flush()

        return sections.isEmpty ? [AITextSection(title: nil, body: cleaned)] : sections
    }

    /// Renders one section's body as Markdown when possible (bold/italics
    /// from the reply), falling back to plain text.
    static func formattedText(_ summary: String) -> Text {
        let cleaned = summary
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")

        if let attributed = try? AttributedString(markdown: cleaned) {
            return Text(attributed)
        }
        return Text(cleaned)
    }
}

/// Shows the plain-English reasoning behind a predicted date/window, built by
/// PredictionExplanationBuilder from the same values FertilityWindowCalculator
/// used - so what the user sees here always matches how the prediction was
/// actually made, rather than restating the date with more confidence.
struct PredictionWhySheet: View {
    let window: FertilityWindow
    let cycle: CycleRecord?
    let settings: UserSettings
    @Environment(\.dismiss) private var dismiss

    private var bullets: [String] {
        PredictionExplanationBuilder.bullets(window: window, cycle: cycle, settings: settings)
    }

    private static let bulletTints: [Color] = [.linePurple, .linePink, .lineBlue, .lineNavy]

    private func bulletTint(_ index: Int) -> Color {
        Self.bulletTints[index % Self.bulletTints.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .center, spacing: 10) {
                        Text("Why this estimate?")
                            .font(.app(size: LineType.size(26), weight: .bold))
                            .foregroundStyle(Color.linePink)
                        Text("Here's exactly what MenoPlan used to calculate your fertile window and ovulation date.")
                            .font(.app(.subheadline))
                            .foregroundStyle(Color.lineNavy.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 12) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(bulletTint(index).opacity(0.14))
                                        .frame(width: 28, height: 28)
                                    Text("\(index + 1)")
                                        .font(.app(.caption, weight: .bold))
                                        .foregroundStyle(bulletTint(index))
                                }
                                Text(bullet)
                                    .font(.lineSubheadline())
                                    .foregroundStyle(Color.lineNavy.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(bulletTint(index).opacity(0.14)))
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.app(.footnote))
                            .foregroundStyle(Color.lineNavy.opacity(0.4))
                        Text("This is a calendar and image-based estimate, not a medical diagnosis. It updates as you log more tests and periods.")
                            .font(.app(.caption))
                            .foregroundStyle(Color.lineNavy.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.lineNavy.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .background { LineCheckBrandBackdrop() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(Color.lineBlue)
    }
}

/// A small, reusable explanation button for terms that may be unfamiliar.
/// Keep the surrounding copy plain; use this only when the term itself is useful.
struct TermHelpButton: View {
    let term: String
    let explanation: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(Color.lineBlue.opacity(0.72))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What does \(term) mean?")
        .popup(isPresented: $isPresented) {
            TermHelpPopup(term: term, explanation: explanation) {
                isPresented = false
            }
        } customize: {
            $0.type(.default)
                .position(.center)
                .closeOnTap(false)
                .closeOnTapOutside(true)
                .backgroundColor(Color.lineNavy.opacity(0.30))
                .animation(.easeOut(duration: 0.2))
        }
    }
}

private struct TermHelpPopup: View {
    let term: String
    let explanation: String
    let dismiss: () -> Void

    var body: some View {
        BrandedModalCard {
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: LineType.size(24), weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.linePurple, .linePink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .background(Color.white.opacity(0.76), in: Circle())

                VStack(spacing: 8) {
                    Text(term)
                        .font(.app(size: LineType.size(20), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                        .multilineTextAlignment(.center)
                    Text(explanation)
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.70))
                        .multilineTextAlignment(.center)
                }

                Button("Got it", action: dismiss)
                    .buttonStyle(.primaryLine)
            }
            .padding(22)
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Supplies UIActivityViewController directly as the SwiftUI sheet's hosted
/// controller. Wrapping it in another UIViewController and presenting it as
/// a child creates two presentation layers; on device that can leave both
/// layers visible and neither one gets populated with share targets.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Called once the activity controller finishes (action completed or
    /// cancelled), so each caller can clear its presentation state.
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityController.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onDismiss()
            }
        }
        return activityController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// Widest a full-width action button is allowed to get.
///
/// Every primary and secondary button in the app is `maxWidth: .infinity`,
/// which is right on a phone and absurd on iPad — a single "Save" spanning
/// 700pt. Capping it here fixes every call site at once instead of each screen
/// remembering to do it. A single shared cap also keeps buttons aligned with
/// each other; sizing each one to its own label would leave them ragged.
private let lineButtonMaxWidth: CGFloat = 340

struct PrimaryLineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    // A `ButtonStyle` can't read `@Environment` directly, so the body is a real
    // view that can.
    private struct StyleBody: View {
        @Environment(\.lineLayout) private var layout
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.lineSubheadline(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.isRegular ? 20 : 14)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [.linePurple, .linePink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .opacity(configuration.isPressed ? 0.82 : 1),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .frame(maxWidth: layout.isRegular ? lineButtonMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
        }
    }
}

struct SecondaryLineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        @Environment(\.lineLayout) private var layout
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.lineSubheadline(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.isRegular ? 20 : 14)
                .foregroundStyle(Color.linePurple)
                .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.linePurple.opacity(0.30), lineWidth: 1.2)
                }
                .frame(maxWidth: layout.isRegular ? lineButtonMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
        }
    }
}

extension ButtonStyle where Self == PrimaryLineButtonStyle {
    static var primaryLine: PrimaryLineButtonStyle { PrimaryLineButtonStyle() }
}

extension ButtonStyle where Self == SecondaryLineButtonStyle {
    static var secondaryLine: SecondaryLineButtonStyle { SecondaryLineButtonStyle() }
}

extension View {
    func toast(message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.lineSubheadline(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.lineNavy, in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: message.wrappedValue)
    }
}
