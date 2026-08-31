import SwiftUI

/// Mirrors Linecheck's own capture shape: choose Luna Check (AI) or Manual Check
/// (brighten it yourself, then Luna confirms) before any capture happens.
enum MenoScanMode: Hashable { case lunaCheck, manualCheck }

private enum MenoScanStep { case guide, manualEnhance, analysing }

struct FSHCheckStartView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: MenoScanMode?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MenoSpace.l) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MenoColor.ink.opacity(0.70))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.90), in: Circle())
                        }
                        .accessibilityLabel("Cancel")
                    }

                    TestStripDiagram(controlLine: 1, testLine: 0.55)
                        .frame(height: 48)
                        .padding(.horizontal, MenoSpace.xl)
                        .accessibilityHidden(true)

                    VStack(spacing: 7) {
                        Text("FSH Test Check")
                            .font(MenoFont.title)
                            .foregroundStyle(MenoColor.ink)
                        Text("Choose how to check your test.")
                            .font(MenoFont.secondary)
                            .foregroundStyle(MenoColor.inkSecondary)
                    }

                    VStack(spacing: MenoSpace.m) {
                        modeCard(.lunaCheck, title: "Luna Check",
                                 detail: "Luna reads the control and test lines and explains the result.",
                                 icon: "LunaCheckIcon", tint: MenoColor.accent, background: MenoColor.accentSoft)
                        modeCard(.manualCheck, title: "Manual Check",
                                 detail: "Brighten the photo yourself, then Luna confirms what you see.",
                                 icon: "ManualCheckIcon", tint: MenoColor.primary, background: MenoColor.primarySoft)
                    }

                    MenoDisclaimer(text: "This reads the visible lines in your photo only. It does not measure hormone levels or diagnose menopause — FSH levels vary naturally from day to day.")
                }
                .padding(MenoSpace.xl)
                .background {
                    LinearGradient(colors: [MenoColor.primarySoft, MenoColor.accentSoft, .white.opacity(0.96)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.76), lineWidth: 1)
                }
                .padding(MenoSpace.gutter)
            }
            .background { MenoBrandBackdrop() }
            .navigationDestination(item: $selectedMode) { mode in ScanFSHView(mode: mode) }
        }
    }

    private func modeCard(_ mode: MenoScanMode, title: String, detail: String, icon: String, tint: Color, background: Color) -> some View {
        Button { selectedMode = mode } label: {
            HStack(spacing: 13) {
                Image(icon)
                    .resizable().scaledToFit()
                    .padding(7)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(tint)
                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MenoColor.ink.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint.opacity(0.55))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(background.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.30)))
        }
        .buttonStyle(.plain)
    }
}

struct ScanFSHView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: MenoScanMode

    @State private var step: MenoScanStep = .guide
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var capturedImage: UIImage?
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1
    @State private var userOpinion: MenoUserStatedOpinion?
    @State private var analysisError: String?
    @State private var result: MenoAIAnalysisResponse?
    @State private var showResult = false

    private let service = MenoAIAnalysisService()

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .guide: guideView
                case .manualEnhance: manualEnhanceView
                case .analysing: analysingView
                }
            }
            .background { MenoBrandBackdrop() }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            MenoCameraCapture(sourceType: .camera) { image in handleCapture(image) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibraryPicker) {
            MenoCameraCapture(sourceType: .photoLibrary) { image in handleCapture(image) }
        }
        .sheet(isPresented: $showResult) {
            if let result {
                FSHResultView(response: result, wasManuallyEnhanced: mode == .manualCheck, onSave: { showResult = false; dismiss() })
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .guide: "Capture guide"
        case .manualEnhance: "Adjust & confirm"
        case .analysing: mode == .lunaCheck ? "Luna Check" : ""
        }
    }

    private func handleCapture(_ image: UIImage) {
        capturedImage = image
        if mode == .manualCheck {
            brightness = 0
            contrast = 1
            userOpinion = nil
            step = .manualEnhance
        } else {
            step = .analysing
            Task { await runAnalysis(image: image, opinion: nil) }
        }
    }

    // MARK: Guide

    private var guideView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MenoSpace.xl) {
                VStack(spacing: MenoSpace.s) {
                    TestStripDiagram(controlLine: 1, testLine: 0.5)
                        .frame(height: 64)
                        .padding(.horizontal, MenoSpace.xl)
                    HStack(spacing: MenoSpace.s) {
                        guidePill("Flat surface", "rectangle.compress.vertical")
                        guidePill("Low glare", "sun.max")
                        guidePill("Lines visible", "checkmark.circle")
                    }
                }

                VStack(alignment: .leading, spacing: MenoSpace.s) {
                    Label("Before you continue", systemImage: "checklist")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MenoColor.ink)
                    tip("Fit the whole test inside the frame before taking the photo", icon: "viewfinder")
                    tip("Use even light and avoid glare on the result window", icon: "sun.max")
                    tip("Keep both the control (C) and test (T) lines visible", icon: "character.textbox")
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MenoColor.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MenoColor.primary.opacity(0.10)))

                if !MenoCameraCapture.isCameraAvailable {
                    Text("No camera on this device — choose a photo instead.")
                        .font(MenoFont.caption)
                        .foregroundStyle(MenoColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, MenoSpace.gutter)
            .padding(.top, MenoSpace.l)
            .padding(.bottom, MenoSpace.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: MenoSpace.m) {
                Button("Choose photo", systemImage: "photo.on.rectangle") { showLibraryPicker = true }
                    .buttonStyle(MenoSecondaryButtonStyle())
                Button("I'm ready", systemImage: "camera") { showCamera = true }
                    .buttonStyle(MenoPrimaryButtonStyle())
                    .disabled(!MenoCameraCapture.isCameraAvailable)
                    .opacity(MenoCameraCapture.isCameraAvailable ? 1 : 0.45)
            }
            .padding(.horizontal, MenoSpace.gutter)
            .padding(.vertical, MenoSpace.m)
            .background(MenoColor.canvas.opacity(0.96))
            .overlay(alignment: .top) { MenoRule() }
        }
    }

    private func guidePill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(MenoColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(MenoColor.primary.opacity(0.08), in: Capsule())
    }

    private func tip(_ text: String, icon: String) -> some View {
        HStack(spacing: MenoSpace.m) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(MenoColor.primary)
                .frame(width: 22)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(MenoColor.inkSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Manual enhance

    private var manualEnhanceView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: MenoSpace.xl) {
                if let capturedImage {
                    Image(uiImage: MenoImageHelpers.adjusted(capturedImage, brightness: brightness, contrast: contrast))
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous).stroke(MenoColor.rule))
                }

                MenoSection(title: "Adjust the photo", detail: "Adjust until the control and test lines are easy to see.") {
                    sliderRow("Brightness", value: $brightness, range: -0.3...0.3)
                    sliderRow("Contrast", value: $contrast, range: 0.7...1.6)
                    Button("Reset", systemImage: "arrow.counterclockwise") { brightness = 0; contrast = 1 }
                        .buttonStyle(.plain)
                        .font(MenoFont.caption.weight(.semibold))
                        .foregroundStyle(MenoColor.primary)
                }

                MenoSection(title: "What do you think you see?", detail: "Optional — Luna treats this as a helpful hint, not the final answer.") {
                    HStack(spacing: MenoSpace.s) {
                        opinionChip("Low", .low)
                        opinionChip("Borderline", .borderline)
                        opinionChip("Elevated", .elevated)
                    }
                }

                if let analysisError {
                    Text(analysisError).font(MenoFont.caption).foregroundStyle(MenoColor.caution)
                }
            }
            .padding(.horizontal, MenoSpace.gutter)
            .padding(.top, MenoSpace.l)
            .padding(.bottom, MenoSpace.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Ask Luna to confirm", systemImage: "sparkles") {
                guard let capturedImage else { return }
                let enhanced = MenoImageHelpers.adjusted(capturedImage, brightness: brightness, contrast: contrast)
                step = .analysing
                Task { await runAnalysis(image: enhanced, opinion: userOpinion) }
            }
            .buttonStyle(MenoPrimaryButtonStyle())
            .padding(.horizontal, MenoSpace.gutter)
            .padding(.vertical, MenoSpace.m)
            .background(MenoColor.canvas.opacity(0.96))
            .overlay(alignment: .top) { MenoRule() }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: MenoSpace.xs) {
            Text(title).font(MenoFont.label).foregroundStyle(MenoColor.ink)
            Slider(value: value, in: range).tint(MenoColor.primary)
        }
    }

    private func opinionChip(_ title: String, _ value: MenoUserStatedOpinion) -> some View {
        Button {
            userOpinion = (userOpinion == value) ? nil : value
        } label: {
            Text(title)
                .font(MenoFont.label)
                .foregroundStyle(userOpinion == value ? MenoColor.onPrimary : MenoColor.primary)
                .padding(.horizontal, MenoSpace.m)
                .padding(.vertical, MenoSpace.s)
                .background(userOpinion == value ? MenoColor.primary : MenoColor.primarySoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Analysing

    private var analysingView: some View {
        VStack(spacing: MenoSpace.l) {
            Spacer()
            if let analysisError {
                VStack(spacing: MenoSpace.m) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(MenoColor.caution)
                    Text(analysisError)
                        .font(MenoFont.secondary)
                        .foregroundStyle(MenoColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again", systemImage: "arrow.counterclockwise") {
                        self.analysisError = nil
                        capturedImage = nil
                        step = .guide
                    }
                    .buttonStyle(MenoSecondaryButtonStyle())
                }
            } else {
                ProgressView().scaleEffect(1.4).tint(MenoColor.primary)
                Text("Reading your test…")
                    .font(MenoFont.secondary)
                    .foregroundStyle(MenoColor.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, MenoSpace.gutter)
    }

    private func runAnalysis(image: UIImage, opinion: MenoUserStatedOpinion?) async {
        analysisError = nil
        do {
            let response = try await service.analyse(image: image, userStatedOpinion: opinion)
            result = response
            showResult = true
        } catch {
            analysisError = error.localizedDescription
        }
    }
}

struct FSHResultView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MenoStore
    let response: MenoAIAnalysisResponse
    var wasManuallyEnhanced = false
    var onSave: (() -> Void)? = nil

    private var resultTint: Color {
        switch response.resultType {
        case "elevated": MenoColor.accent
        case "borderline": MenoColor.caution
        case "invalid", "unclear": MenoColor.inkTertiary
        default: MenoColor.positive
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MenoSpace.xl) {
                    VStack(alignment: .leading, spacing: MenoSpace.m) {
                        MenoBadge(text: response.resultLabel, icon: "checkmark", tint: resultTint)
                        Text(response.explanation)
                            .font(MenoFont.display)
                            .foregroundStyle(MenoColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(wasManuallyEnhanced ? "Manual Check · brightened photo · Luna-confirmed" : "Luna Check · AI-read analysis · \(response.certaintyPercentage)% readable")
                            .font(MenoFont.caption)
                            .foregroundStyle(MenoColor.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    MenoSection(title: "Your test", trailing: "As we read it") {
                        TestStripDiagram(controlLine: response.controlLineDetected ? 1 : 0, testLine: response.testControlRatio)
                            .accessibilityElement()
                            .accessibilityLabel(response.observedLinePattern ?? response.explanation)
                    }

                    MenoSection(title: "What this means", detail: response.guidance) {
                        HStack(spacing: MenoSpace.xl) {
                            MenoMetricView(value: response.certaintyPercentage >= 70 ? "High" : "Fair", label: "Photo quality", compact: true)
                            MenoMetricView(value: response.controlLineDetected ? "Clear" : "Not found", label: "Control line", compact: true)
                            Spacer()
                        }
                        if let nextBestAction = response.nextBestAction, !nextBestAction.isEmpty {
                            MenoRule()
                            Text(nextBestAction)
                                .font(MenoFont.secondary)
                                .foregroundStyle(MenoColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    MenoDisclaimer()

                    VStack(spacing: MenoSpace.m) {
                        Button("Save reading", systemImage: "checkmark") {
                            store.addFSHReading(from: response)
                            if let onSave { onSave() } else { dismiss() }
                        }
                        .buttonStyle(MenoPrimaryButtonStyle())
                        Button("Retake photo", systemImage: "arrow.counterclockwise") { dismiss() }
                            .buttonStyle(MenoSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, MenoSpace.gutter)
                .padding(.bottom, MenoSpace.xxl)
            }
            .background { MenoBrandBackdrop() }
            .scrollIndicators(.hidden)
            .navigationTitle("Your reading")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
