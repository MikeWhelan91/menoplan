import SwiftUI

/// Menoplan uses Linecheck's onboarding choreography and artwork while asking for
/// menopause-specific context. It is deliberately a short setup, not an oversized form.
struct MenoOnboardingView: View {
    private enum Page: Int, CaseIterable { case welcome, setup, finish }

    @EnvironmentObject private var store: MenoStore
    let onComplete: () -> Void

    @State private var page: Page = .welcome
    @State private var previousPage: Page = .welcome
    @State private var contentVisible = false
    @State private var revealedHighlights = 0

    var body: some View {
        VStack(spacing: 0) {
            if page != .welcome {
                MenoOnboardingProgress(activeIndex: page == .setup ? 0 : 1)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Spacer(minLength: 14)
            }

            ZStack {
                currentPage
                    .id(page)
                    .transition(pageTransition)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, page == .welcome ? 0 : 20)

            Spacer(minLength: 14)
            navigation
        }
        .background { MenoBrandBackdrop() }
        .tint(MenoColor.primary)
        .preferredColorScheme(.light)
        .task { animateContentIn() }
        .onChange(of: page) { _, _ in
            contentVisible = false
            animateContentIn()
        }
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.14), value: page)
        .animation(.easeOut(duration: 0.42), value: contentVisible)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var currentPage: some View {
        switch page {
        case .welcome: welcome
        case .setup: setup
        case .finish: finish
        }
    }

    private var welcome: some View {
        GeometryReader { proxy in
            let heroHeight = min(max(proxy.size.height * 0.25, 195), 225)
            ViewThatFits(in: .vertical) {
                welcomeContent(heroHeight: heroHeight)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                ScrollView(.vertical, showsIndicators: false) { welcomeContent(heroHeight: 185) }
            }
        }
        .background {
            ZStack {
                Circle().fill(MenoColor.accent.opacity(0.055)).frame(width: 330, height: 330).blur(radius: 10).offset(x: 210, y: 260)
                Circle().fill(MenoColor.primary.opacity(0.05)).frame(width: 280, height: 280).blur(radius: 12).offset(x: -220, y: 560)
            }
            .allowsHitTesting(false)
        }
    }

    private func welcomeContent(heroHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            MenoLottieView(name: "welcome")
                .frame(width: heroHeight * 1.25, height: heroHeight)
                .clipped()

            VStack(spacing: 9) {
                Text("WELCOME")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MenoColor.primary)

                HStack(spacing: 0) {
                    Text("Meno").foregroundStyle(MenoColor.ink)
                    Text("plan").foregroundStyle(MenoColor.accent)
                }
                .font(.system(size: 34, weight: .heavy, design: .rounded))

                Text("Track symptoms, test results, and the small changes worth bringing to your next appointment.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(MenoColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            welcomeHighlights.padding(.top, 14)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private var welcomeHighlights: some View {
        VStack(alignment: .leading, spacing: 9) {
            welcomeHighlight(0, "thermometer.sun.fill", "Track symptoms and sleep", tint: MenoColor.accent)
            welcomeHighlight(1, "viewfinder", "Save FSH test checks", tint: MenoColor.primary)
            welcomeHighlight(2, "calendar", "Build a useful symptom history", tint: MenoColor.accent)
            welcomeHighlight(3, "sparkles", "Ask Luna about menopause", tint: MenoColor.primary)
        }
        .task {
            revealedHighlights = 0
            for count in 1...4 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(count == 1 ? 180 : 145))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    revealedHighlights = count
                }
            }
        }
    }

    private func welcomeHighlight(_ index: Int, _ icon: String, _ title: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.76), in: Circle())
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MenoColor.ink.opacity(0.76))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(tint.opacity(0.085), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.74), lineWidth: 1) }
        .opacity(revealedHighlights > index ? 1 : 0)
        .offset(x: revealedHighlights > index ? 0 : 24)
    }

    private var setup: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                MenoLottieView(name: "calendar - woman")
                    .frame(width: 150, height: 84)
                    .clipped()

                pageIntro(eyebrow: "SETUP", title: "A few details", subtitle: "You can change these whenever you like.")

                VStack(spacing: 0) {
                    compactTextRow(title: "First name", placeholder: "Name", text: $store.profile.name, contentType: .givenName)
                    MenoRule().padding(.leading, 14)
                    compactTextRow(title: "Age", placeholder: "Optional", text: $store.profile.age, keyboard: .numberPad)
                    MenoRule().padding(.leading, 14)
                    HStack(spacing: 10) {
                        Text("Menopause stage").font(.system(.footnote, design: .rounded).weight(.semibold)).foregroundStyle(MenoColor.ink)
                        Spacer(minLength: 10)
                        Picker("Menopause stage", selection: $store.profile.stage) {
                            Text("Not sure yet").tag("Not sure yet")
                            Text("Perimenopause").tag("Perimenopause")
                            Text("Postmenopause").tag("Postmenopause")
                            Text("Surgical / early menopause").tag("Surgical / early menopause")
                        }
                        .pickerStyle(.menu)
                        .tint(MenoColor.primary)
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    MenoRule().padding(.leading, 14)
                    Toggle("I use HRT", isOn: $store.profile.usesHRT)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .tint(MenoColor.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                }
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MenoColor.primary.opacity(0.14), lineWidth: 1) }
                .shadow(color: MenoColor.primary.opacity(0.05), radius: 8, y: 3)
            }
            .padding(.bottom, 8)
        }
    }

    private func compactTextRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(MenoColor.ink)
            Spacer(minLength: 10)
            TextField(placeholder, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(contentType == .givenName ? .words : .never)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(MenoColor.ink)
                .frame(maxWidth: 150)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private var finish: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                MenoLottieView(name: "check", loopMode: .playOnce)
                    .frame(width: 210, height: 126)
                    .clipped()

                pageIntro(eyebrow: "YOUR FOCUS", title: "What would help most?", subtitle: "Choose the first thing you want Menoplan to make easier.")

                VStack(spacing: 8) {
                    ForEach(["Understand my symptoms", "Sleep better", "Prepare for an appointment", "Understand HRT options"], id: \.self) { goal in
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) { store.profile.mainGoal = goal }
                        } label: {
                            HStack(spacing: 10) {
                                Text(goal)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(MenoColor.ink)
                                Spacer()
                                Image(systemName: store.profile.mainGoal == goal ? "checkmark.circle.fill" : "circle")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(store.profile.mainGoal == goal ? MenoColor.primary : MenoColor.ink.opacity(0.34))
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(store.profile.mainGoal == goal ? MenoColor.primarySoft.opacity(0.82) : .white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(store.profile.mainGoal == goal ? MenoColor.primary.opacity(0.22) : .white.opacity(0.74), lineWidth: 1.2) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func pageIntro(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(MenoColor.primary)
            Text(title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(MenoColor.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MenoColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            if page != .welcome {
                Button("Back") { move(to: Page(rawValue: page.rawValue - 1)!, forward: false) }
                    .buttonStyle(MenoSecondaryLineButtonStyle())
            }
            Button(page == .welcome ? "Set up my record" : (page == .finish ? "Start using Menoplan" : "Continue")) {
                if page == .finish { onComplete() }
                else { move(to: Page(rawValue: page.rawValue + 1)!) }
            }
            .buttonStyle(MenoPrimaryLineButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.32) }
    }

    private var pageTransition: AnyTransition {
        let insertion: Edge = page.rawValue >= previousPage.rawValue ? .trailing : .leading
        let removal: Edge = page.rawValue >= previousPage.rawValue ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: insertion).combined(with: .opacity), removal: .move(edge: removal).combined(with: .opacity))
    }

    private func move(to destination: Page, forward: Bool = true) {
        previousPage = page
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.14)) {
            page = destination
        }
    }

    private func animateContentIn() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeOut(duration: 0.42)) { contentVisible = true }
        }
    }
}

private struct MenoOnboardingProgress: View {
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(index <= activeIndex ? MenoColor.primary : MenoColor.primary.opacity(0.14))
                    .frame(width: index == activeIndex ? 34 : 16, height: 8)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: activeIndex)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MenoPrimaryLineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [MenoColor.primary, MenoColor.accent], startPoint: .leading, endPoint: .trailing).opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct MenoSecondaryLineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(MenoColor.primary)
            .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(MenoColor.primary.opacity(0.30), lineWidth: 1.2) }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
