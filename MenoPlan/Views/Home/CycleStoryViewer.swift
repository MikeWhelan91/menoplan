import SwiftUI

enum CycleStory: String, Identifiable, CaseIterable {
    case cycleDay, hormones, fertileTiming, timeline, whenToTest, dueDate
    var id: String { rawValue }

    static func stories(for timeline: ConceptionTimeline, tryingToConceive: Bool, on date: Date = .now) -> [CycleStory] {
        let today = Calendar.current.startOfDay(for: date)
        return allCases.filter { story in
            switch story {
            case .fertileTiming: tryingToConceive && today <= timeline.fertileEnd
            default: true
            }
        }
    }

    func cardTitle(_ timeline: ConceptionTimeline) -> String {
        switch self {
        case .cycleDay: "Day \(timeline.cycleDay) of your cycle"
        case .hormones: "Hormones today"
        case .fertileTiming: "Best days to try"
        case .timeline: "Your pregnancy timeline"
        case .whenToTest: "When to test"
        case .dueDate: "If you conceive this cycle"
        }
    }

    var symbol: String {
        switch self {
        case .cycleDay: "circle.dashed"
        case .hormones: "waveform.path.ecg"
        case .fertileTiming: "heart.fill"
        case .timeline: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .whenToTest: "calendar.badge.clock"
        case .dueDate: "sparkles"
        }
    }

    var colors: [Color] {
        switch self {
        case .cycleDay: [Color(red: 0.99, green: 0.86, blue: 0.90), Color(red: 1.0, green: 0.95, blue: 0.96)]
        case .hormones: [Color(red: 0.84, green: 0.95, blue: 0.93), Color(red: 0.95, green: 0.99, blue: 0.98)]
        case .fertileTiming: [Color(red: 1.0, green: 0.84, blue: 0.88), Color(red: 1.0, green: 0.93, blue: 0.90)]
        case .timeline: [Color(red: 0.88, green: 0.87, blue: 1.0), Color(red: 0.96, green: 0.95, blue: 1.0)]
        case .whenToTest: [Color(red: 1.0, green: 0.92, blue: 0.82), Color(red: 1.0, green: 0.97, blue: 0.92)]
        case .dueDate: [Color(red: 0.85, green: 0.93, blue: 1.0), Color(red: 0.95, green: 0.97, blue: 1.0)]
        }
    }

    var accent: Color {
        switch self {
        case .cycleDay, .fertileTiming: .linePink
        case .hormones: Color.lineTeal
        case .timeline: .linePurple
        case .whenToTest: Color(red: 0.85, green: 0.45, blue: 0.05)
        case .dueDate: Color(red: 0.20, green: 0.45, blue: 0.75)
        }
    }
}

enum CycleStoryAction {
    case remindToTest(Date)
    case scanPregnancyTest
}

// MARK: - Card row on Home

struct CycleStoryRow: View {
    let timeline: ConceptionTimeline
    let stories: [CycleStory]
    let seen: Set<String>
    var onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your cycle insights")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                Text("· Today")
                    .font(.app(.headline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.45))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(stories.enumerated()), id: \.element) { index, story in
                        Button { onOpen(index) } label: { card(story, isSeen: seen.contains(story.rawValue)) }
                            .buttonStyle(PressScaleButtonStyle())
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                    .opacity(phase.isIdentity ? 1 : 0.8)
                            }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func card(_ story: CycleStory, isSeen: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(story.cardTitle(timeline))
                .font(.app(size: LineType.size(15), weight: .heavy))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            HStack {
                Spacer()
                Image(systemName: story.symbol)
                    .font(.system(size: LineType.size(34), weight: .semibold))
                    .foregroundStyle(story.accent.opacity(0.85))
            }
        }
        .padding(12)
        .frame(width: LineType.size(118), height: LineType.size(150), alignment: .topLeading)
        .background(LinearGradient(colors: story.colors, startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSeen ? Color.lineNavy.opacity(0.08) : Color.linePink, lineWidth: isSeen ? 1 : 2.5)
        )
        .accessibilityLabel(story.cardTitle(timeline))
    }
}

// MARK: - Full-screen viewer

struct CycleStoryViewer: View {
    let timeline: ConceptionTimeline
    let stories: [CycleStory]
    @State var index: Int
    var onSeen: (CycleStory) -> Void
    var onAction: (CycleStoryAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var isPaused = false
    @State private var movingForward = true
    @State private var dragOffset: CGFloat = 0
    @State private var pressStart: Date?

    private let duration: Double = 7

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(red: 0.975, green: 0.955, blue: 0.95))

                    storyContent(stories[index])
                        .id(index)
                        .transition(storyTransition)
                        .padding(.top, 60)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .top) { header }
                .overlay { gestureLayer(width: proxy.size.width) }
                .scaleEffect(1 - min(dragOffset, 300) / 1600)
                .offset(y: dragOffset)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
        .statusBarHidden()
        .task(id: index) { await runTimer() }
        .onAppear { onSeen(stories[index]) }
        .onChange(of: index) { _, new in onSeen(stories[new]) }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: index)
    }

    private var storyTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96))
        )
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(stories.indices, id: \.self) { item in
                    GeometryReader { bar in
                        Capsule().fill(Color.lineNavy.opacity(0.14))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.lineNavy.opacity(0.85))
                                    .frame(width: bar.size.width * fill(for: item))
                            }
                    }
                    .frame(height: 3)
                }
            }
            HStack {
                Text(Date.now.formatted(.dateTime.month(.wide).day()) + " · Cycle day \(timeline.cycleDay)")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.lineNavy)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .zIndex(2)
    }

    private func fill(for item: Int) -> CGFloat {
        if item < index { return 1 }
        if item > index { return 0 }
        return CGFloat(progress)
    }

    /// One drag gesture handles everything a story viewer needs: hold to
    /// pause, tap left/right to step, and pull down to close.
    private func gestureLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .padding(.top, 70)
            .padding(.bottom, 90)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressStart == nil { pressStart = .now }
                        isPaused = true
                        if value.translation.height > 0 { dragOffset = value.translation.height }
                    }
                    .onEnded { value in
                        let held = Date.now.timeIntervalSince(pressStart ?? .now)
                        pressStart = nil
                        isPaused = false
                        if value.translation.height > 120 {
                            dismiss()
                            return
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 }
                        let moved = abs(value.translation.width) + abs(value.translation.height)
                        guard held < 0.3, moved < 12 else { return }
                        if value.location.x < width * 0.33 { step(-1) } else { step(1) }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Story \(index + 1) of \(stories.count)")
            .accessibilityAdjustableAction { direction in
                step(direction == .increment ? 1 : -1)
            }
    }

    private func step(_ delta: Int) {
        let target = index + delta
        guard stories.indices.contains(target) else {
            if delta > 0 { dismiss() } else { progress = 0 }
            return
        }
        movingForward = delta > 0
        progress = 0
        index = target
    }

    private func runTimer() async {
        progress = 0
        let tick = 0.05
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(tick * 1000)))
            guard !Task.isCancelled else { return }
            if isPaused { continue }
            progress = min(1, progress + tick / duration)
            if progress >= 1 {
                step(1)
                return
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func storyContent(_ story: CycleStory) -> some View {
        switch story {
        case .cycleDay:
            CycleDayStory(timeline: timeline)
        case .hormones:
            HormoneStory(timeline: timeline)
        case .fertileTiming:
            StoryPage(
                title: "When to have sex for pregnancy",
                highlightCaption: "Your most fertile time this cycle may last until",
                highlight: timeline.fertileEnd.formatted(.dateTime.month(.wide).day()),
                accent: story.accent,
                message: "Having sex every day or every other day during the fertile window gives the best chance of conceiving, according to the American College of Obstetricians and Gynecologists. Sperm can survive for up to five days, so the days before ovulation count too.",
                footnote: "Estimated from your cycle. Ovulation tests can narrow it down."
            )
        case .timeline:
            TimelineStory(timeline: timeline)
        case .whenToTest:
            StoryPage(
                title: "When to take a pregnancy test",
                highlightCaption: "Earliest early-result test",
                highlight: timeline.earliestTestDate.formatted(.dateTime.month(.wide).day()),
                accent: story.accent,
                message: "Sensitive tests can sometimes show hCG from about 10 days after ovulation, but many people won’t see a line that early. For the clearest answer, test from \(timeline.reliableTestDate.formatted(.dateTime.month(.wide).day())), the day your period is due.",
                footnote: nil,
                primaryAction: ("Remind me to test", { onAction(.remindToTest(timeline.earliestTestDate)); dismiss() })
            )
        case .dueDate:
            StoryPage(
                title: "If you conceive this cycle, your baby may be born around",
                highlightCaption: nil,
                highlight: timeline.dueDate.formatted(.dateTime.month(.wide).day().year()),
                accent: story.accent,
                message: timeline.ovulationIsConfirmed
                    ? "That’s 266 days after your recorded ovulation, the standard way to date a pregnancy from a known ovulation day."
                    : "That’s 40 weeks from the first day of your last period, adjusted for your \(timeline.cycleLength)-day cycle, the same method used at a first appointment.",
                footnote: "For educational purposes only. All dates are estimates based on your cycle data."
            )
        }
    }
}

/// Staggers children in once when a story appears.
private struct StoryReveal: ViewModifier {
    let order: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.08 + Double(order) * 0.09)) { shown = true }
            }
    }
}

private extension View {
    func storyReveal(_ order: Int) -> some View { modifier(StoryReveal(order: order)) }
}

private struct StoryPage: View {
    let title: String
    let highlightCaption: String?
    let highlight: String
    let accent: Color
    let message: String
    let footnote: String?
    var primaryAction: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title)
                .font(.app(size: LineType.size(28), weight: .heavy))
                .foregroundStyle(Color.lineNavy.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .storyReveal(0)

            VStack(spacing: 0) {
                if let highlightCaption {
                    Text(highlightCaption)
                        .font(.app(size: LineType.size(16), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(accent.opacity(0.14))
                }
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: LineType.size(22), weight: .semibold))
                    Text(highlight)
                        .font(.app(size: LineType.size(30), weight: .heavy))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .storyReveal(1)

            Text(message)
                .font(.app(size: LineType.size(16), weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .storyReveal(2)

            Spacer(minLength: 0)

            if let primaryAction {
                Button(primaryAction.0, action: primaryAction.1)
                    .buttonStyle(.primaryLine)
                    .storyReveal(3)
            }

            if let footnote {
                Text(footnote)
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.5))
                    .storyReveal(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CycleDayStory: View {
    let timeline: ConceptionTimeline
    @State private var drawn = false

    private func fraction(_ date: Date) -> CGFloat {
        let day = Calendar.current.dateComponents([.day], from: timeline.cycleStart, to: date).day ?? 0
        return CGFloat(day) / CGFloat(timeline.cycleLength)
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 2) {
                Text("Day \(timeline.cycleDay)")
                Text("of your cycle")
            }
            .font(.app(size: LineType.size(34), weight: .heavy))
            .foregroundStyle(Color.lineNavy.opacity(0.8))
            .storyReveal(0)

            ZStack {
                Circle().stroke(Color.lineNavy.opacity(0.08), lineWidth: 26)
                Circle()
                    .trim(from: 0, to: drawn ? min(5.0 / CGFloat(timeline.cycleLength), 1) : 0)
                    .stroke(Color.linePink, style: StrokeStyle(lineWidth: 26, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: drawn ? fraction(timeline.fertileStart) : fraction(timeline.fertileStart),
                          to: drawn ? min(fraction(timeline.fertileEnd) + 1 / CGFloat(timeline.cycleLength), 1) : fraction(timeline.fertileStart))
                    .stroke(Color.lineFertileSoft, style: StrokeStyle(lineWidth: 26, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                marker(at: fraction(timeline.ovulationDate) + 0.5 / CGFloat(timeline.cycleLength), symbol: "heart.fill", tint: HomePhaseStyle.fertile)
                marker(at: (CGFloat(timeline.cycleDay) - 0.5) / CGFloat(timeline.cycleLength), symbol: "circle.fill", tint: .lineNavy)
                    .scaleEffect(drawn ? 1 : 0.2)

                VStack(spacing: 4) {
                    Text("You are here")
                        .font(.app(size: LineType.size(22), weight: .heavy))
                        .foregroundStyle(Color.lineNavy.opacity(0.8))
                    Image(systemName: "arrow.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                }
            }
            .frame(width: 250, height: 250)
            .padding(.top, 8)
            .storyReveal(1)

            HStack(spacing: 16) {
                legend(Color.linePink, "Period")
                legend(Color.lineFertileSoft, "Fertile days")
                legend(Color.lineNavy, "Today")
            }
            .storyReveal(2)

            Spacer(minLength: 0)
            Text("This prediction is based on the periods you’ve logged\(timeline.ovulationIsConfirmed ? " and your recorded ovulation" : "").")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .storyReveal(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).delay(0.25)) { drawn = true }
        }
    }

    private func marker(at fraction: CGFloat, symbol: String, tint: Color) -> some View {
        let angle = Angle.degrees(Double(fraction) * 360 - 90)
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .offset(x: cos(angle.radians) * 125, y: sin(angle.radians) * 125)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.app(.caption, weight: .semibold)).foregroundStyle(Color.lineNavy.opacity(0.65))
        }
    }
}

private struct HormoneStory: View {
    let timeline: ConceptionTimeline
    @State private var drawn: CGFloat = 0

    private var todayFraction: CGFloat {
        min(max((CGFloat(timeline.cycleDay) - 0.5) / CGFloat(timeline.cycleLength), 0), 1)
    }
    private var ovulationFraction: CGFloat {
        let day = Calendar.current.dateComponents([.day], from: timeline.cycleStart, to: timeline.ovulationDate).day ?? 14
        return CGFloat(day) / CGFloat(timeline.cycleLength)
    }

    private var phaseText: (String, String) {
        let today = Calendar.current.startOfDay(for: .now)
        if timeline.cycleDay <= 5 {
            return ("Period", "Oestrogen and progesterone are at their lowest, and a new cycle begins. Tiredness and cramps are common.")
        }
        if today < timeline.fertileStart {
            return ("Follicular phase", "Oestrogen is rising as an egg matures. Many people notice more energy and a lift in mood.")
        }
        if today <= timeline.ovulationDate {
            return ("Around ovulation", "Oestrogen peaks and LH surges, the signal that triggers ovulation. This is what an ovulation test picks up.")
        }
        return ("Luteal phase", "Progesterone rises after ovulation, which can bring a small temperature rise, breast tenderness and PMS-like symptoms.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hormones and your body")
                .font(.app(size: LineType.size(28), weight: .heavy))
                .foregroundStyle(Color.lineNavy.opacity(0.82))
                .storyReveal(0)

            VStack(alignment: .leading, spacing: 8) {
                Text(phaseText.0.uppercased())
                    .font(.app(.caption, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Color.lineTeal)
                Text(phaseText.1)
                    .font(.app(size: LineType.size(18), weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .storyReveal(1)

            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack(alignment: .topLeading) {
                        curve(size: size) { x in
                            // Oestrogen: rise to a pre-ovulation peak, dip, second luteal hump.
                            let o = Double(ovulationFraction)
                            return 0.18 + 0.62 * gauss(x, o - 0.03, 0.07) + 0.3 * gauss(x, o + 0.3, 0.12)
                        }
                        .trim(from: 0, to: drawn)
                        .stroke(Color.lineTeal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                        curve(size: size) { x in
                            let o = Double(ovulationFraction)
                            return 0.08 + 0.78 * gauss(x, o, 0.025)
                        }
                        .trim(from: 0, to: drawn)
                        .stroke(Color.linePurple, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                        curve(size: size) { x in
                            let o = Double(ovulationFraction)
                            return 0.06 + 0.6 * gauss(x, o + 0.3, 0.13) * (x > o ? 1 : gauss(x, o, 0.05) * 0.4 + 0.2)
                        }
                        .trim(from: 0, to: drawn)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                        Path { path in
                            path.move(to: CGPoint(x: todayFraction * size.width, y: 0))
                            path.addLine(to: CGPoint(x: todayFraction * size.width, y: size.height))
                        }
                        .stroke(Color.lineNavy.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .opacity(drawn)

                        Text("Today")
                            .font(.app(.caption2, weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                            .fixedSize()
                            .position(x: min(max(todayFraction * size.width, 20), size.width - 20), y: -8)
                            .opacity(drawn)
                    }
                }
                .frame(height: 170)
                .padding(.top, 14)

                HStack {
                    Text("Period"); Spacer(); Text("Ovulation"); Spacer(); Text("Next period")
                }
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.55))
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .storyReveal(2)

            HStack(spacing: 14) {
                legend(Color.lineTeal, "Oestrogen")
                legend(.linePurple, "LH")
                legend(.orange, "Progesterone")
            }
            .storyReveal(3)

            Spacer(minLength: 0)
            Text("A simplified illustration of a typical cycle, not a measurement of your levels.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { withAnimation(.easeInOut(duration: 1.4).delay(0.3)) { drawn = 1 } }
    }

    private func gauss(_ x: Double, _ mean: Double, _ sd: Double) -> Double {
        exp(-0.5 * pow((x - mean) / sd, 2))
    }

    private func curve(size: CGSize, value: @escaping (Double) -> Double) -> Path {
        Path { path in
            for step in 0...80 {
                let x = Double(step) / 80
                let point = CGPoint(x: x * size.width, y: size.height * (1 - min(max(value(x), 0), 1)))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(.app(.caption, weight: .semibold)).foregroundStyle(Color.lineNavy.opacity(0.65))
        }
    }
}

private struct TimelineStory: View {
    let timeline: ConceptionTimeline
    @State private var lineDrawn: CGFloat = 0

    private func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.month(.wide).day())
    }

    private var steps: [(String, String, String)] {
        [
            (timeline.ovulationIsConfirmed ? "Recorded ovulation" : "Predicted ovulation", day(timeline.ovulationDate), "sparkle"),
            ("Estimated implantation", "\(day(timeline.implantationStart)) – \(day(timeline.implantationEnd))", "circle.circle"),
            ("Earliest early-result test", day(timeline.earliestTestDate), "testtube.2"),
            ("Reliable test · period due", day(timeline.reliableTestDate), "checkmark.seal")
        ]
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Your potential pregnancy timeline")
                .font(.app(size: LineType.size(28), weight: .heavy))
                .foregroundStyle(Color.lineNavy.opacity(0.82))
                .multilineTextAlignment(.center)
                .storyReveal(0)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Image(systemName: step.2)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.linePurple, in: Circle())
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(Color.linePurple.opacity(0.3))
                                    .frame(width: 2, height: 30)
                                    .scaleEffect(y: lineDrawn, anchor: .top)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.0)
                                .font(.app(size: LineType.size(14), weight: .semibold))
                                .foregroundStyle(Color.lineNavy.opacity(0.6))
                            Text(step.1)
                                .font(.app(size: LineType.size(18), weight: .heavy))
                                .foregroundStyle(Color.linePurple)
                        }
                        .padding(.top, 4)
                    }
                    .storyReveal(index + 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Image(systemName: "arrow.down")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.linePurple.opacity(0.6))
                .storyReveal(5)

            VStack(spacing: 4) {
                Text("Potential due date")
                    .font(.app(size: LineType.size(16), weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.65))
                Text(timeline.dueDate.formatted(.dateTime.month(.wide).day().year()))
                    .font(.app(size: LineType.size(30), weight: .heavy))
                    .foregroundStyle(Color.linePink)
            }
            .storyReveal(6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { withAnimation(.easeOut(duration: 1.2).delay(0.3)) { lineDrawn = 1 } }
    }
}
