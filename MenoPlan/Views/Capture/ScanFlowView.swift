@preconcurrency import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

struct ScanFlowView: View {
    @Environment(AppState.self) private var appState
    @Bindable var flow: ScanFlow
    @State private var showExitConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if flow.step != .mode {
                    scanHeader
                }
                Group {
                    switch flow.step {
                    case .mode: ModeSelectionView(flow: flow)
                    case .guide: CaptureGuideView(flow: flow)
                    case .capture: CameraImportView(flow: flow)
                    case .crop: TemplateAlignView(flow: flow)
                    case .manual: ManualEnhanceView(flow: flow)
                    case .analysing:
                        switch flow.mode {
                        case .manualEnhance: LocalHeuristicCheckView(flow: flow)
                        case .aiQuickCheck: OnDeviceCheckView(flow: flow)
                        }
                    case .result: ResultView(flow: flow)
                    }
                }
            }
            .background { LineCheckBrandBackdrop() }
        }
        // The scan flow is presented as a full-screen cover attached outside
        // the root's `providesLineLayout()` and `dynamicTypeSize()`, so it is
        // a sibling of those rather than a child and inherits neither: the
        // layout fell back to the compact default and every semantic font
        // (.headline, .caption) stayed phone-sized while the fixed LineType
        // sizes around them scaled up. Both are re-applied for this shell.
        .providesLineLayout()
        .dynamicTypeSize(LineType.scale > 1 ? .xxLarge... : .xSmall...)
        .overlay {
            if showExitConfirmation {
                BrandedNoticeOverlay(
                    icon: "xmark.circle",
                    showsIcon: false,
                    title: "Exit this scan?",
                    message: "Your current scan will close. Saved results remain in history.",
                    primaryTitle: "Keep editing",
                    secondaryTitle: "Exit to Home",
                    primaryAction: { showExitConfirmation = false },
                    secondaryAction: exitToHome
                )
            }
        }
    }

    private var scanHeader: some View {
        ZStack {
            Text(headerTitle)
                .font(.app(.headline, weight: .semibold))
                .foregroundStyle(flow.step == .result ? resultHeaderTint : Color.lineNavy)

            HStack {
                Spacer()
                if flow.step == .manual {
                    resetButton
                }
                if flow.step == .result, flow.analysisResult != nil {
                    resultHeaderActions
                }
                if flow.step != .result && flow.step != .analysing {
                    exitButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.lineBackground)
    }

    private var resultHeaderTint: Color {
        flow.testType == .ovulation ? Color.linePurple : Color.linePink
    }

    private var headerTitle: String {
        switch flow.step {
        case .guide:
            "Capture Guide"
        case .capture:
            "Camera / Import"
        case .crop:
            flow.mode == .manualEnhance ? "Crop & Align" : "Frame Test"
        case .manual:
            "Adjust & Choose"
        case .analysing:
            flow.mode == .manualEnhance ? "" : "Luna Check"
        case .result:
            "Result"
        case .mode:
            ""
        }
    }

    private var resetButton: some View {
        return Button {
            flow.manualResetToken += 1
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: LineType.size(17), weight: .semibold))
                .foregroundStyle(Color.lineNavy)
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.07), lineWidth: 1))
        }
        .accessibilityLabel("Reset adjustments")
    }

    private var resultHeaderActions: some View {
        HStack(spacing: 8) {
            Button {
                flow.pendingResultAction = .saveImage
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: LineType.size(15), weight: .semibold))
                    .foregroundStyle(resultHeaderTint)
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.07), lineWidth: 1))
            }
            .accessibilityLabel("Save image to Photos")

            Button {
                flow.pendingResultAction = .exportPDF
            } label: {
                Image(systemName: "doc.richtext")
                    .font(.system(size: LineType.size(15), weight: .semibold))
                    .foregroundStyle(resultHeaderTint)
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.07), lineWidth: 1))
            }
            .accessibilityLabel("Export PDF report")
        }
    }

    private var exitButton: some View {
        Button {
            showExitConfirmation = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: LineType.size(17), weight: .bold))
                .foregroundStyle(Color.lineNavy.opacity(0.78))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.96), in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
        .accessibilityLabel("Exit scan")
    }

    private func exitToHome() {
        appState.selectedTab = .home
        appState.activeFlow = nil
    }
}

struct ModeSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Bindable var flow: ScanFlow
    @State private var showLunaCheckOptions = false
    @State private var isUnlockingRewardedCheck = false
    private let quota = AICheckQuotaService()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button {
                    appState.activeFlow = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.70))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.90), in: Circle())
                }
                .accessibilityLabel("Cancel")
            }

            TestPhotoPreview(testType: flow.testType)

            VStack(spacing: 7) {
                Text("\(flow.testType.shortTitle) Test Check")
                    .font(.app(.title3, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)
                Text(modeSubtitle)
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            testDetailsCard

            VStack(spacing: 12) {
                modeCard(.aiQuickCheck, title: "Luna Check", message: aiModeCopy, primary: true)
                modeCard(.manualEnhance, title: "Manual Check", message: manualModeCopy, primary: false)
                
            }

        }
        .padding(18)
        .background {
            LinearGradient(
                colors: [.linePurpleSoft, .linePinkSoft, .white.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.linePurple.opacity(0.20), radius: 28, y: 16)
        .frame(maxWidth: 430)
        .overlay {
            if showLunaCheckOptions {
                LunaCheckGateOverlay(
                    title: "No Luna Checks left right now",
                    message: "Watch an ad for 1 more check, or upgrade for unlimited AI reads.",
                    adButtonTitle: "Watch ad for 1 more Luna Check",
                    cornerRadius: 28,
                    onWatchAd: {
                        Task { await unlockAndContinueIfPossible() }
                    },
                    onUpgrade: {
                        appState.paywallSource = "luna_check_quota"
                        appState.showPremium = true
                        showLunaCheckOptions = false
                    },
                    onClose: {
                        showLunaCheckOptions = false
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.24), value: showLunaCheckOptions)
    }

    private var modeSubtitle: String {
        "Choose how to check your test."
    }

    private var testDetailsCard: some View {
        HStack(spacing: 10) {
            testDateRow

            Divider()
                .frame(height: 26)

            Image(systemName: "tag")
                .font(.system(size: LineType.size(14), weight: .semibold))
                .foregroundStyle(Color.linePurple)
            TextField("Add brand", text: $flow.brandName)
                .textInputAutocapitalization(.words)
                .font(.app(.subheadline))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 13)
        .frame(height: 52)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.linePurple.opacity(0.08)))
    }

    @ViewBuilder
    private var testDateRow: some View {
        if flow.usesCustomTestDate {
            HStack(spacing: 6) {
                testDateIcon
                DatePicker("Taken", selection: $flow.testDate, in: ...Date.now, displayedComponents: [.date])
                    .font(.app(.caption, weight: .semibold))
                    .labelsHidden()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        flow.usesCustomTestDate = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.lineNavy.opacity(0.35))
                }
                .accessibilityLabel("Use today's date")
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    flow.usesCustomTestDate = true
                    flow.testDate = .now
                }
            } label: {
                HStack(spacing: 6) {
                    testDateIcon
                    Text(Date.now, format: .dateTime.day().month(.abbreviated).year())
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change test date")
        }
    }

    private var testDateIcon: some View {
        Image(systemName: "clock")
            .font(.system(size: LineType.size(16), weight: .semibold))
            .foregroundStyle(Color.linePurple)
            .frame(width: 20)
    }

    private var aiModeCopy: String {
        "Our trained AI model reads the line and explains the result."
    }

    private var manualModeCopy: String {
        "A local scanner on your device."
    }

    private func modeCard(_ mode: AnalysisMode, title: String, message: String, primary: Bool) -> some View {
        let tint: Color = switch mode {
        case .aiQuickCheck: .linePink
        case .manualEnhance: .linePurple
        }
        let background: Color = switch mode {
        case .aiQuickCheck: .linePinkSoft
        case .manualEnhance: .linePurpleSoft
        }
        let iconName = switch mode {
        case .aiQuickCheck: "LunaCheckIcon"
        case .manualEnhance: "ManualCheckIcon"
        }
        return Button {
            if mode == .aiQuickCheck {
                guard let settings = appState.settings else { return }
                if !quota.canUseAI(settings) {
                    showLunaCheckOptions = true
                    return
                }
            }
            flow.mode = mode
            flow.step = .guide
        } label: {
            HStack(spacing: 13) {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.app(.headline))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        if let settings = appState.settings, !settings.proUnlocked {
                            Text(mode == .manualEnhance ? "FREE · ADS" : shortQuotaText(settings))
                                .font(.app(.caption2, weight: .bold))
                                .foregroundStyle(Color.lineBlue)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.lineBlue.opacity(0.09), in: Capsule())
                        }
                    }
                    Text(message)
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.68))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(tint.opacity(0.55))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                background.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.30)))
        }
        .buttonStyle(.plain)
    }

    private func shortQuotaText(_ settings: UserSettings) -> String {
        if settings.proUnlocked { return "Unlimited" }
        let remaining = quota.checksRemaining(settings) ?? 0
        return "\(remaining) left"
    }

    private func unlockAndContinueIfPossible() async {
        guard let settings = appState.settings else { return }
        guard !isUnlockingRewardedCheck else { return }
        guard quota.canClaimRewardedCheck(settings) else {
            appState.toast = "This week's rewarded Luna Checks have been used"
            return
        }
        isUnlockingRewardedCheck = true
        defer { isUnlockingRewardedCheck = false }
        if await RewardedAdService().showRewardedAd(), quota.addRewardedChecks(settings) {
            appState.toast = "1 Luna Check added"
            flow.suppressCompletionInterstitial = true
            flow.mode = .aiQuickCheck
            flow.step = .guide
        } else {
            appState.toast = quota.canClaimRewardedCheck(settings) ? "Rewarded ad unavailable" : "This week's rewarded Luna Checks have been used"
        }
    }
}

private struct TestPhotoPreview: View {
    var testType: TestType

    var body: some View {
        TestImage(testType: testType)
            .aspectRatio(contentMode: .fit)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .accessibilityHidden(true)
    }
}

private struct TestImage: View {
    var testType: TestType

    var body: some View {
        TestIllustration(testType: testType, result: .borderline)
    }
}

struct CaptureGuideView: View {
    @Environment(\.lineLayout) private var layout
    @Bindable var flow: ScanFlow
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var cameraDenied = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ProgressSteps(current: 1, third: flow.mode == .manualEnhance ? "Adjust" : "Analyse")
                    Text("Capture Your \(flow.testType.shortTitle) Test")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)
                    captureFrame
                        .padding(.top, 26)
                    beforeYouContinueCard
                    if cameraDenied {
                        Text("Camera permission is unavailable. You can import a photo from your library or enable camera access in Settings.")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .lineContentColumn()
            }

        }
        .background { LineCheckBrandBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            guideActions
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 12)
                .lineContentColumn()
                .background(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(testType: flow.testType) { image, _ in
                flow.resetForNewCapture(keepingStep: flow.mode == .manualEnhance ? .manual : .analysing)
                flow.image = image
                flow.markImageCaptured()
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .sheet(isPresented: $showPhotoPicker, onDismiss: {
            isImporting = false
        }) {
            LibraryPhotoPicker(
                onImage: handleImportedImage,
                onFailure: handleImportFailure,
                onCancel: { isImporting = false }
            )
        }
        .overlay {
            if let importErrorMessage {
                BrandedNoticeOverlay(
                    icon: "photo.badge.exclamationmark",
                    title: "Couldn’t import photo",
                    message: importErrorMessage,
                    primaryTitle: "Choose another photo",
                    secondaryTitle: "Cancel",
                    primaryAction: {
                        self.importErrorMessage = nil
                        isImporting = true
                        showPhotoPicker = true
                    },
                    secondaryAction: {
                        self.importErrorMessage = nil
                    }
                )
            }
        }
    }

    /// Phone-tuned 48pt bar; on iPad it reads as a thin strip under content
    /// that has scaled up around it.
    private var actionButtonHeight: CGFloat { layout.isRegular ? 68 : 48 }

    private var guideActions: some View {
        GeometryReader { proxy in
            let buttonWidth = max((proxy.size.width - 12) / 2, 0)
            let importing = isImporting
            HStack(spacing: 12) {
                Button {
                    importErrorMessage = nil
                    isImporting = true
                    showPhotoPicker = true
                } label: {
                    ImportPhotoLabel(isImporting: importing)
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .frame(width: buttonWidth, height: actionButtonHeight)
                .contentShape(Rectangle())

                Button(action: requestCamera) {
                    Text("I’m Ready")
                        .font(.app(size: LineType.size(17), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.lineBlue, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .frame(width: buttonWidth, height: actionButtonHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: actionButtonHeight)
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                Task { @MainActor in allowed ? (showCamera = true) : (cameraDenied = true) }
            }
        default:
            cameraDenied = true
        }
    }

    private func handleImportedImage(_ image: UIImage) {
        isImporting = false
        flow.resetForNewCapture(keepingStep: .crop)
        flow.image = image
        flow.imageWasImported = true
        flow.importedImageHasBeenCropped = false
        flow.markImageCaptured()
    }

    private func handleImportFailure(_ error: Error) {
        isImporting = false
        importErrorMessage = error.localizedDescription
    }

    private var captureFrame: some View {
        VStack(spacing: 8) {
            CaptureGuidePhoto(testType: flow.testType)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .padding(.top, 6)

            HStack(spacing: 8) {
                guidePill("Flat surface", "rectangle.compress.vertical")
                guidePill("Low glare", "sun.max")
                guidePill("Lines visible", "checkmark.circle")
            }
            .padding(.horizontal, 2)
        }
    }

    private var beforeYouContinueCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Before you continue", systemImage: "checklist")
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Color.lineNavy)

            captureTip("Fit the test inside the camera guide before taking the photo", icon: "viewfinder")
            captureTip("Keep the C and T labels beside the result window in view", icon: "character.textbox")
            captureTip("Read it at the time your test's instructions say", icon: "timer")
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(flow.testType.tint.opacity(0.10)))
    }

    private func captureTip(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(flow.testType.tint)
                .frame(width: 24)
            Text(text)
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.68))
            Spacer(minLength: 0)
        }
    }

    private func guidePill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.app(.caption, weight: .bold))
            .foregroundStyle(Color.lineNavy)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(flow.testType.tint.opacity(0.08), in: Capsule())
    }

}

/// A drawn FSH cassette rather than a photo, so no brand's markings are
/// implied: control and test lines with their C/T labels.
private struct CaptureGuidePhoto: View {
    var testType: TestType

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.linePurple.opacity(0.10), Color.linePink.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            TestIllustration(testType: testType, result: .borderline)
                .scaleEffect(1.7)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(testType.tint.opacity(0.28), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

struct LunaCheckGateOverlay: View {
    var title: String
    var message: String
    var adButtonTitle: String
    var cornerRadius: CGFloat? = nil
    var onWatchAd: () -> Void
    var onUpgrade: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            LunaCheckGateSheet(
                title: title,
                message: message,
                adButtonTitle: adButtonTitle,
                onWatchAd: onWatchAd,
                onUpgrade: onUpgrade,
                onClose: onClose
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var scrim: some View {
        if let cornerRadius {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.16))
        } else {
            Color.black.opacity(0.16)
        }
    }
}

struct LunaCheckGateSheet: View {
    var title: String
    var message: String
    var adButtonTitle: String
    var onWatchAd: () -> Void
    var onUpgrade: () -> Void
    var onClose: () -> Void

    var body: some View {
        BrandedModalCard {
            VStack(spacing: 18) {
                AppIconBrandMark(size: 68)

                VStack(spacing: 7) {
                    Text(title)
                        .font(.app(size: LineType.size(23), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.62))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button(action: onWatchAd) {
                        Label(adButtonTitle, systemImage: "play.rectangle.fill")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryLine)

                    Button("Upgrade", action: onUpgrade)
                        .buttonStyle(.secondaryLine)
                }

                Button("Not now", action: onClose)
                    .buttonStyle(.plain)
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
        }
    }
}

private struct ImportPhotoLabel: View {
    var isImporting: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isImporting {
                ProgressView().tint(Color.lineBlue)
                Text("Importing Photo")
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: LineType.size(17), weight: .semibold))
                Text("Import Photo")
            }
        }
        .font(.app(size: LineType.size(17), weight: .semibold))
        .foregroundStyle(Color.lineBlue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.lineBlue.opacity(0.55)))
    }
}

private enum LibraryPhotoImportError: LocalizedError {
    case unsupportedSelection
    case failed

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            "The selected item is not a readable photo. Choose another image and try again."
        case .failed:
            "Photos could not provide this image. Choose another photo or take a new picture."
        }
    }
}

/// PHPickerViewController, not the older UIImagePickerController: the app
/// never needs Photos permission for it (it runs out-of-process), and it
/// hands back an NSItemProvider that loads the image asynchronously - which
/// properly waits for an iCloud-hosted photo to finish downloading. The
/// UIImagePickerController version this replaced read `.originalImage`
/// synchronously off the delegate callback's info dictionary, which could
/// come back empty for exactly that reason on a photo not yet cached
/// locally - matching a reported "first import of a session fails, retries
/// work" pattern (the retry's asset was presumably already cached by then).
private struct LibraryPhotoPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onFailure: (Error) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: LibraryPhotoPicker

        init(_ parent: LibraryPhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onCancel()
                parent.dismiss()
                return
            }
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onFailure(LibraryPhotoImportError.unsupportedSelection)
                parent.dismiss()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [parent] object, error in
                let loadedImage = object as? UIImage
                let loadError = error
                DispatchQueue.main.async {
                    if let image = loadedImage {
                        parent.onImage(image)
                    } else {
                        parent.onFailure(loadError ?? LibraryPhotoImportError.failed)
                    }
                    parent.dismiss()
                }
            }
        }
    }
}

struct ProgressSteps: View {
    var current: Int
    var third: String
    let titles = ["Guide", "Capture", "Adjust", "Result"]
    var body: some View {
        HStack {
            ForEach(1...4, id: \.self) { index in
                VStack(spacing: 5) {
                    Text("\(index)").font(.app(.caption, weight: .bold)).foregroundStyle(index <= current ? .white : .lineNavy).frame(width: 24, height: 24).background(index <= current ? Color.lineBlue : Color(.systemGray6), in: Circle())
                    Text(index == 3 ? third : titles[index - 1]).font(.app(.caption2)).foregroundStyle(.secondary)
                }
                if index < 4 { Rectangle().fill(.quaternary).frame(height: 1) }
            }
        }
    }
}

struct CameraImportView: View {
    @Bindable var flow: ScanFlow
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var cameraDenied = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Camera / Import").font(.app(.headline))
            ProgressSteps(current: 2, third: flow.mode == .manualEnhance ? "Adjust" : "Analyse")
            ZStack {
                Color.black
                RoundedRectangle(cornerRadius: 20).stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [12, 8])).padding(38)
                Image(systemName: "viewfinder").font(.system(size: LineType.size(80))).foregroundStyle(.white.opacity(0.7))
            }.frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 18))
            if cameraDenied {
                Text("Camera permission is unavailable. You can import a photo from your library or enable camera access in Settings.").font(.app(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Take Photo") { requestCamera() }.buttonStyle(.primaryLine)
            let importing = isImporting
            Button {
                importErrorMessage = nil
                isImporting = true
                showPhotoPicker = true
            } label: {
                ImportPhotoLabel(isImporting: importing)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
        }
        .padding(18)
        .background { LineCheckBrandBackdrop() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(testType: flow.testType) { image, _ in
                flow.resetForNewCapture(keepingStep: flow.mode == .manualEnhance ? .manual : .analysing)
                flow.image = image
                flow.markImageCaptured()
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .sheet(isPresented: $showPhotoPicker, onDismiss: {
            isImporting = false
        }) {
            LibraryPhotoPicker(
                onImage: handleImportedImage,
                onFailure: handleImportFailure,
                onCancel: { isImporting = false }
            )
        }
        .overlay {
            if let importErrorMessage {
                BrandedNoticeOverlay(
                    icon: "photo.badge.exclamationmark",
                    title: "Couldn’t import photo",
                    message: importErrorMessage,
                    primaryTitle: "Choose another photo",
                    secondaryTitle: "Cancel",
                    primaryAction: {
                        self.importErrorMessage = nil
                        isImporting = true
                        showPhotoPicker = true
                    },
                    secondaryAction: {
                        self.importErrorMessage = nil
                    }
                )
            }
        }
    }

    private func handleImportedImage(_ image: UIImage) {
        isImporting = false
        flow.resetForNewCapture(keepingStep: .crop)
        flow.image = image
        flow.imageWasImported = true
        flow.importedImageHasBeenCropped = false
        flow.markImageCaptured()
    }

    private func handleImportFailure(_ error: Error) {
        isImporting = false
        importErrorMessage = error.localizedDescription
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                Task { @MainActor in allowed ? (showCamera = true) : (cameraDenied = true) }
            }
        default: cameraDenied = true
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var testType: TestType
    var onImage: (UIImage, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CameraSessionViewController {
        CameraSessionViewController(
            testType: testType,
            onImage: { image, wasCroppedToGuide in
                onImage(image, wasCroppedToGuide)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }

    func updateUIViewController(_ uiViewController: CameraSessionViewController, context: Context) {}
}

/// Custom AVFoundation capture screen. The user lines the test up inside the
/// on-screen guide box; the delivered photo is cropped to exactly that
/// region so the guide is the actual frame that gets sent on, not just a
/// visual suggestion. The preview layer is `.resizeAspectFill`, pinned to
/// the view's own bounds, with its rotation locked to match the photo
/// output exactly, so the guide box's on-screen rect and the photo share
/// the same field of view — see `PhotoCaptureProcessor.guidedCrop` for the
/// mapping.
final class CameraSessionViewController: UIViewController {
    private let testType: TestType
    private let onImage: (UIImage, Bool) -> Void
    private let onCancel: () -> Void

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var activePhotoCapture: PhotoCaptureProcessor?
    private var reviewView: PhotoReviewView?

    private lazy var overlay = CameraOverlayView(
        testType: testType,
        onCapture: { [weak self] in self?.capturePhoto() },
        onCancel: { [weak self] in self?.onCancel() },
        onFlip: { [weak self] in self?.flipCamera() }
    )

    init(testType: TestType, onImage: @escaping (UIImage, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.testType = testType
        self.onImage = onImage
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        configureInput(for: currentPosition)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        session.commitConfiguration()
        updateRotation()
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func configureInput(for position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if let videoInput { session.removeInput(videoInput) }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        videoInput = input

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        device.unlockForConfiguration()
    }

    /// This capture screen is portrait-only in practice (its layout is built
    /// entirely from fixed point constants), so both the preview and the
    /// photo output are pinned to portrait once here rather than tracked
    /// live via `AVCaptureDevice.RotationCoordinator`. That coordinator's
    /// angle can be computed before the preview layer is actually attached
    /// to a window, and letting the preview and photo-output connections
    /// disagree on rotation is exactly what turns the guide-box crop
    /// sideways relative to the delivered photo.
    private func updateRotation() {
        let portraitAngle: CGFloat = 90
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(portraitAngle) {
            connection.videoRotationAngle = portraitAngle
        }
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(portraitAngle) {
            connection.videoRotationAngle = portraitAngle
        }
    }

    private func flipCamera() {
        currentPosition = currentPosition == .back ? .front : .back
        session.beginConfiguration()
        configureInput(for: currentPosition)
        session.commitConfiguration()
        updateRotation()
    }

    private func capturePhoto() {
        let overlayBounds = view.bounds
        let guideFrame = overlay.guideBoxFrame(in: view)

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality

        let processor = PhotoCaptureProcessor(overlayBounds: overlayBounds, guideFrame: guideFrame) { [weak self] image, wasCroppedToGuide in
            Task { @MainActor in
                self?.presentReview(for: image, wasCroppedToGuide: wasCroppedToGuide)
            }
        }
        activePhotoCapture = processor
        photoOutput.capturePhoto(with: settings, delegate: processor)
    }

    /// Shows the photo that will actually be used — the guide crop, if it
    /// succeeded — full-screen with Retake/Use Photo, so a bad crop or a
    /// missed line gets caught here instead of surfacing three screens later
    /// as a wrong result.
    private func presentReview(for image: UIImage, wasCroppedToGuide: Bool) {
        let review = PhotoReviewView(
            image: image,
            onRetake: { [weak self] in self?.dismissReview() },
            onUsePhoto: { [weak self] in self?.onImage(image, wasCroppedToGuide) }
        )
        review.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(review)
        NSLayoutConstraint.activate([
            review.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            review.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            review.topAnchor.constraint(equalTo: view.topAnchor),
            review.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reviewView = review
    }

    private func dismissReview() {
        reviewView?.removeFromSuperview()
        reviewView = nil
    }
}

/// Runs the crop math off the delegate callback so a slow JPEG decode never
/// blocks the capture session; hands the final image back on the main actor.
private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let overlayBounds: CGRect
    private let guideFrame: CGRect
    private let completion: @Sendable (UIImage, Bool) -> Void

    init(overlayBounds: CGRect, guideFrame: CGRect, completion: @escaping @Sendable (UIImage, Bool) -> Void) {
        self.overlayBounds = overlayBounds
        self.guideFrame = guideFrame
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }

        let completion = completion
        let cropped = Self.guidedCrop(of: image, overlayBounds: overlayBounds, guideFrame: guideFrame)

        DispatchQueue.main.async {
            completion(cropped ?? image, cropped != nil)
        }
    }

    /// The preview layer is `.resizeAspectFill`, pinned to the view's own
    /// bounds, with its rotation locked to match the photo output exactly —
    /// so the live preview and the captured photo share the same field of
    /// view, and this plain aspect-fill arithmetic reproduces the same crop
    /// the user saw live. (`AVCaptureVideoPreviewLayer
    /// .metadataOutputRectConverted` was tried first since it's the "proper"
    /// API for this, but it was not producing a rect that matched the
    /// delivered photo's actual orientation with the angle-based rotation
    /// APIs — this sidesteps that by computing the mapping directly instead
    /// of trusting an undocumented system conversion.)
    private static func guidedCrop(of image: UIImage, overlayBounds: CGRect, guideFrame: CGRect, marginFraction: CGFloat = 0.05) -> UIImage? {
        let oriented = image.normalizedForCropping()
        guard let cgImage = oriented.cgImage,
              overlayBounds.width > 0, overlayBounds.height > 0,
              guideFrame.width > 0, guideFrame.height > 0 else { return nil }

        let imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let previewScale = max(overlayBounds.width / imagePixelSize.width, overlayBounds.height / imagePixelSize.height)
        let displayedSize = CGSize(width: imagePixelSize.width * previewScale, height: imagePixelSize.height * previewScale)
        let displayedOrigin = CGPoint(
            x: (overlayBounds.width - displayedSize.width) / 2,
            y: (overlayBounds.height - displayedSize.height) / 2
        )

        let paddedGuide = guideFrame.insetBy(dx: -guideFrame.width * marginFraction, dy: -guideFrame.height * marginFraction)

        let pixels = CGRect(
            x: (paddedGuide.minX - displayedOrigin.x) / previewScale,
            y: (paddedGuide.minY - displayedOrigin.y) / previewScale,
            width: paddedGuide.width / previewScale,
            height: paddedGuide.height / previewScale
        ).integral.intersection(CGRect(origin: .zero, size: imagePixelSize))

        guard pixels.width > 20, pixels.height > 20, let cropped = cgImage.cropping(to: pixels) else { return nil }
        return UIImage(cgImage: cropped, scale: oriented.scale, orientation: .up)
    }
}

private final class PhotoReviewView: UIView {
    private let onRetake: () -> Void
    private let onUsePhoto: () -> Void

    init(image: UIImage, onRetake: @escaping () -> Void, onUsePhoto: @escaping () -> Void) {
        self.onRetake = onRetake
        self.onUsePhoto = onUsePhoto
        super.init(frame: .zero)
        backgroundColor = .black

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Use this photo?"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: LineType.size(17), weight: .bold)
        titleLabel.textAlignment = .center

        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 16
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.06)

        let retakeButton = Self.makeButton(title: "Retake", filled: false)
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        let useButton = Self.makeButton(title: "Use Photo", filled: true)
        useButton.addTarget(self, action: #selector(useTapped), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [retakeButton, useButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        addSubview(titleLabel)
        addSubview(imageView)
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 18),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            imageView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -24),

            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func retakeTapped() { onRetake() }
    @objc private func useTapped() { onUsePhoto() }

    private static func makeButton(title: String, filled: Bool) -> UIButton {
        var config: UIButton.Configuration = filled ? .filled() : .tinted()
        config.title = title
        config.cornerStyle = .capsule
        config.baseBackgroundColor = filled ? .white : UIColor.white.withAlphaComponent(0.16)
        config.baseForegroundColor = filled ? .black : .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: LineType.size(16), weight: .bold)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

private final class CameraOverlayView: UIView {
    /// Gaps around the reference example above the guide box. The originals
    /// were fixed constants sized for a phone, where the guide is ~340pt wide;
    /// on an iPad the guide grows with the screen but these did not, leaving
    /// the example strip sitting almost on top of the guide it is meant to be
    /// distinguished from.
    private var endLabelGap: CGFloat { LineType.scale > 1 ? 14 : 8 }
    private var exampleGap: CGFloat { LineType.scale > 1 ? 34 : 14 }
    private var hintGap: CGFloat { LineType.scale > 1 ? 22 : 14 }

    /// How far the T/C markers sit inside the line-area box. Fixed 24/20pt
    /// insets put them ~9% in on an iPad, where the box is roughly twice the
    /// phone's width, so they read as labelling the box's edges rather than
    /// the test and control lines the user is meant to line up.
    private var lineMarkerLeadingInset: CGFloat { LineType.scale > 1 ? 62 : 24 }
    private var lineMarkerTrailingInset: CGFloat { LineType.scale > 1 ? 58 : 20 }

    private let testType: TestType
    private let onCapture: () -> Void
    private let onCancel: () -> Void
    private let onFlip: () -> Void
    private let captureFrameView = UIView()

    init(testType: TestType, onCapture: @escaping () -> Void, onCancel: @escaping () -> Void, onFlip: @escaping () -> Void) {
        self.testType = testType
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.onFlip = onFlip
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .clear

        let instructionCard = makeInstructionCard()

        let frameView = captureFrameView
        frameView.translatesAutoresizingMaskIntoConstraints = false
        frameView.layer.borderColor = UIColor.white.withAlphaComponent(0.62).cgColor
        frameView.layer.borderWidth = 2
        frameView.layer.cornerRadius = 22
        frameView.layer.shadowColor = UIColor.black.cgColor
        frameView.layer.shadowOpacity = 0.40
        frameView.layer.shadowRadius = 14

        let lineSearchRegion = makeResultRegion(title: "LINE AREA")
        frameView.addSubview(lineSearchRegion)

        let leftEndLabel = makeFrameLabel(testType == .ovulation ? "MAX / DIP END" : "TEST TIP")
        let rightEndLabel = makeFrameLabel(testType == .ovulation ? "HANDLE END" : "HANDLE")
        frameView.addSubview(leftEndLabel)
        frameView.addSubview(rightEndLabel)

        let controlHintLabel = UILabel()
        controlHintLabel.translatesAutoresizingMaskIntoConstraints = false
        controlHintLabel.text = "KEEP CONTROL LINE INSIDE BOX"
        controlHintLabel.textColor = .white
        controlHintLabel.font = .systemFont(ofSize: LineType.size(11), weight: .heavy)
        controlHintLabel.textAlignment = .center
        controlHintLabel.adjustsFontSizeToFitWidth = true
        controlHintLabel.minimumScaleFactor = 0.7
        frameView.addSubview(controlHintLabel)

        var referenceImageView: UIImageView?

        let controls = UIView()
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.backgroundColor = UIColor.black.withAlphaComponent(0.78)

        let shutter = makeShutterButton()
        shutter.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        let close = makeRoundButton(systemName: "xmark", accessibilityLabel: "Close camera")
        close.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let flip = makeRoundButton(systemName: "arrow.triangle.2.circlepath.camera", accessibilityLabel: "Flip camera")
        flip.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)

        let modeLabel = UILabel()
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.text = "PHOTO"
        modeLabel.textColor = UIColor(red: 0.72, green: 0.56, blue: 1.0, alpha: 1)
        modeLabel.font = .systemFont(ofSize: LineType.size(12), weight: .bold)
        modeLabel.textAlignment = .center

        addSubview(frameView)
        addSubview(instructionCard)
        addSubview(controls)
        controls.addSubview(shutter)
        controls.addSubview(close)
        controls.addSubview(flip)
        controls.addSubview(modeLabel)

        var constraints: [NSLayoutConstraint] = [
            frameView.centerXAnchor.constraint(equalTo: centerXAnchor),
            frameView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -62),
            frameView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.86),
            frameView.heightAnchor.constraint(equalTo: frameView.widthAnchor, multiplier: 0.28),

            lineSearchRegion.centerXAnchor.constraint(equalTo: frameView.centerXAnchor),
            lineSearchRegion.centerYAnchor.constraint(equalTo: frameView.centerYAnchor),
            lineSearchRegion.widthAnchor.constraint(equalTo: frameView.widthAnchor, multiplier: 0.38),
            lineSearchRegion.heightAnchor.constraint(equalTo: frameView.heightAnchor, multiplier: 0.62),

            leftEndLabel.leadingAnchor.constraint(equalTo: frameView.leadingAnchor, constant: 10),
            leftEndLabel.leadingAnchor.constraint(greaterThanOrEqualTo: frameView.leadingAnchor),
            leftEndLabel.bottomAnchor.constraint(equalTo: frameView.topAnchor, constant: -endLabelGap),
            rightEndLabel.trailingAnchor.constraint(equalTo: frameView.trailingAnchor, constant: -10),
            rightEndLabel.bottomAnchor.constraint(equalTo: frameView.topAnchor, constant: -endLabelGap),

            controlHintLabel.centerXAnchor.constraint(equalTo: frameView.centerXAnchor),
            controlHintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: frameView.leadingAnchor, constant: 8),
            controlHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: frameView.trailingAnchor, constant: -8),

            instructionCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            instructionCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            instructionCard.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 18),

            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.heightAnchor.constraint(equalToConstant: 210),

            shutter.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            shutter.topAnchor.constraint(equalTo: controls.topAnchor, constant: 26),
            shutter.widthAnchor.constraint(equalToConstant: 76),
            shutter.heightAnchor.constraint(equalToConstant: 76),
            modeLabel.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            modeLabel.topAnchor.constraint(equalTo: shutter.bottomAnchor, constant: 12),
            close.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            close.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 34),
            close.widthAnchor.constraint(equalToConstant: 52),
            close.heightAnchor.constraint(equalToConstant: 52),
            flip.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            flip.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -34),
            flip.widthAnchor.constraint(equalToConstant: 52),
            flip.heightAnchor.constraint(equalToConstant: 52)
        ]

        if let referenceImageView {
            constraints += [
                referenceImageView.centerXAnchor.constraint(equalTo: frameView.centerXAnchor),
                referenceImageView.widthAnchor.constraint(equalTo: frameView.widthAnchor),
                referenceImageView.heightAnchor.constraint(equalTo: referenceImageView.widthAnchor, multiplier: 63.0 / 680.0),
                referenceImageView.bottomAnchor.constraint(equalTo: leftEndLabel.topAnchor, constant: -exampleGap),
                controlHintLabel.bottomAnchor.constraint(equalTo: referenceImageView.topAnchor, constant: -hintGap)
            ]
        } else {
            constraints.append(controlHintLabel.bottomAnchor.constraint(equalTo: leftEndLabel.topAnchor, constant: -(exampleGap + 6)))
        }

        NSLayoutConstraint.activate(constraints)
    }

    private func makeInstructionCard() -> UIView {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 20
        blur.clipsToBounds = true

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Align test inside box"
        title.textColor = .white
        title.font = .systemFont(ofSize: LineType.size(17), weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 2

        let tip = UILabel()
        tip.translatesAutoresizingMaskIntoConstraints = false
        tip.text = testType == .ovulation
            ? "Both lines anywhere inside T–C area  •  Avoid glare"
            : "Both result lines inside T–C area  •  Avoid glare"
        tip.textColor = UIColor.white.withAlphaComponent(0.66)
        tip.font = .systemFont(ofSize: LineType.size(12), weight: .medium)
        tip.textAlignment = .center

        blur.contentView.addSubview(title)
        blur.contentView.addSubview(tip)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -18),
            title.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 13),
            tip.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            tip.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            tip.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            tip.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -12)
        ])
        return blur
    }

    private func makeResultRegion(title: String) -> UIView {
        let region = UIView()
        region.translatesAutoresizingMaskIntoConstraints = false
        region.backgroundColor = .clear
        region.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.96).cgColor
        region.layer.borderWidth = 2.5
        region.layer.cornerRadius = 8

        let testLabel = makeLineMarker("T")
        let controlLabel = makeLineMarker("C")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        titleLabel.font = .systemFont(ofSize: LineType.size(7), weight: .heavy)
        titleLabel.textAlignment = .center
        titleLabel.isHidden = true

        region.addSubview(testLabel)
        region.addSubview(controlLabel)
        region.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            // Keep the line markers comfortably inside the crop guide so they
            // correspond to real test/control lines rather than its edges.
            testLabel.leadingAnchor.constraint(equalTo: region.leadingAnchor, constant: lineMarkerLeadingInset),
            testLabel.centerYAnchor.constraint(equalTo: region.centerYAnchor),
            controlLabel.trailingAnchor.constraint(equalTo: region.trailingAnchor, constant: -lineMarkerTrailingInset),
            controlLabel.centerYAnchor.constraint(equalTo: region.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: region.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: region.trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(equalTo: region.bottomAnchor, constant: -5)
        ])
        return region
    }

    private func makeLineMarker(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: LineType.size(13), weight: .heavy)
        label.textAlignment = .center
        return label
    }

    func guideBoxFrame(in targetView: UIView) -> CGRect {
        layoutIfNeeded()
        return captureFrameView.convert(captureFrameView.bounds, to: targetView)
    }

    private func makeFrameLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor.white.withAlphaComponent(0.92)
        label.font = .systemFont(ofSize: LineType.size(9), weight: .heavy)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        return label
    }

    private func makeShutterButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.layer.cornerRadius = 38
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.34).cgColor
        button.layer.borderWidth = 7
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 8
        button.accessibilityLabel = "Take photo"
        return button
    }

    private func makeRoundButton(systemName: String, accessibilityLabel: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 26
        button.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    @objc private func captureTapped() { onCapture() }
    @objc private func cancelTapped() { onCancel() }
    @objc private func flipTapped() { onFlip() }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct TemplateAlignView: View {
    @Environment(\.lineLayout) private var layout
    @Bindable var flow: ScanFlow
    @State private var cropRect = CGRect(x: 0.06, y: 0.27, width: 0.88, height: 0.46)
    @State private var imageScale: CGFloat = 1
    @State private var imageOffset: CGSize = .zero
    @State private var gestureStartOffset: CGSize?
    @State private var gestureStartScale: CGFloat?
    @State private var didSetInitialScale = false
    var body: some View {
        VStack(spacing: 14) {
            ProgressSteps(current: 3, third: flow.mode == .manualEnhance ? "Adjust" : "Analyse")
            Text("Align Your Test").font(.app(.headline))
            Text(instruction)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            imageView
            controls
            HStack {
                Button("Retake") { flow.step = .guide }.buttonStyle(.secondaryLine)
                Button(continueButtonTitle) { continueWithCrop() }
                    .buttonStyle(.primaryLine)
            }
            if flow.mode == .manualEnhance {
                Text("Manual tools are on the next screen.").font(.app(.footnote)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, 16)
        .lineContentColumn()
        .background { LineCheckBrandBackdrop() }
    }

    /// Ovulation's manual check skips the enhance screen entirely (adjusting
    /// brightness/contrast on an OPK strip doesn't help - what matters is
    /// the raw color relationship between the test and control lines, which
    /// enhancement can actually distort), so its button reflects that it
    /// goes straight to a scan rather than an editing screen.
    private var continueButtonTitle: String {
        guard flow.mode == .manualEnhance else { return "Use This Photo" }
        return flow.testType == .ovulation ? "Manual Check" : "Enhance"
    }

    private var imageView: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let baseFrame = flow.image.map { aspectFitRect(imageSize: $0.size, containerSize: size) } ?? CGRect(origin: .zero, size: size)
            let viewport = alignmentViewport(in: size)
            ZStack {
                if let image = flow.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                } else {
                    Color.black.opacity(0.85)
                }
                alignmentOverlay(viewport: viewport)
            }
            .contentShape(Rectangle())
            .gesture(transformGesture(baseFrame: baseFrame, viewport: viewport))
            .onAppear {
                // A photo lands filling the stage, which leaves no margin to
                // drag or pinch it into the guide - it has to be shrunk before
                // it can be positioned. Starting backed off gives that room.
                if layout.isRegular, !didSetInitialScale {
                    didSetInitialScale = true
                    imageScale = 0.72
                }
                updateCropRect(baseFrame: baseFrame, viewport: viewport)
            }
            .onChange(of: imageScale) { _, _ in updateCropRect(baseFrame: baseFrame, viewport: viewport) }
            .onChange(of: imageOffset) { _, _ in updateCropRect(baseFrame: baseFrame, viewport: viewport) }
            .id(flow.image.map(ObjectIdentifier.init))
        }
        .frame(height: layout.isRegular ? 560 : 420)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// The dashed guide the user has to fit their test inside. The phone caps
    /// are tuned to a ~360pt-wide stage; on an iPad the stage is roughly twice
    /// that, so the same caps leave a small box floating in a large frame and
    /// make the test harder to line up, not easier.
    private func alignmentViewport(in size: CGSize) -> CGRect {
        let widthCap: CGFloat = layout.isRegular ? 640 : 360
        let heightCap: CGFloat = layout.isRegular ? 180 : 104
        let minHeight: CGFloat = layout.isRegular ? 132 : 76
        let width = min(size.width - 32, widthCap)
        let height = min(max(width / 4.2, minHeight), heightCap)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private var instruction: String {
        if flow.testType == .ovulation {
            return "Pinch or tap Zoom until one test fills the guide and both lines are easy to see. Keep both lines anywhere inside the shared T–C area."
        }
        return "Pinch or tap Zoom until one test fills the guide and both result lines are easy to see. Keep both lines inside the shared T–C area."
    }

    private func alignmentOverlay(viewport: CGRect) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.52)).reverseMask {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .frame(width: viewport.width, height: viewport.height)
                    .position(x: viewport.midX, y: viewport.midY)
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, dash: [11, 7]))
                .frame(width: viewport.width, height: viewport.height)
                .position(x: viewport.midX, y: viewport.midY)
            Text("KEEP CONTROL LINE INSIDE BOX")
                .font(.app(size: LineType.size(11), weight: .heavy))
                .tracking(0.3)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .position(x: viewport.midX, y: viewport.minY - 128)
            alignmentLabel(flow.testType == .ovulation ? "MAX / DIP" : "TEST TIP", x: viewport.minX + viewport.width * 0.11, viewport: viewport)
            let lineAreaMinX = viewport.minX + viewport.width * TestTemplateGeometry.lineRegion.minX
            let lineAreaMaxX = viewport.minX + viewport.width * TestTemplateGeometry.lineRegion.maxX
            let lineAreaWidth = lineAreaMaxX - lineAreaMinX
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.yellow.opacity(0.96), lineWidth: 2.5))
                .frame(
                    width: lineAreaMaxX - lineAreaMinX,
                    height: viewport.height * TestTemplateGeometry.lineRegion.height
                )
                .position(x: (lineAreaMinX + lineAreaMaxX) / 2, y: viewport.midY)
            // Mark the expected positions inside the template, rather than the
            // crop boundaries. This lets people line their actual T/C marks up.
            alignmentLabel("T", x: lineAreaMinX + lineAreaWidth * 0.30, viewport: viewport)
            alignmentLabel("C", x: lineAreaMinX + lineAreaWidth * 0.80, viewport: viewport)
            alignmentLabel("HANDLE", x: viewport.minX + viewport.width * 0.89, viewport: viewport)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func alignmentLabel(_ text: String, x: CGFloat, viewport: CGRect) -> some View {
        Text(text)
            .font(.app(size: LineType.size(8), weight: .heavy))
            .tracking(0.35)
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: viewport.width * 0.20)
            .position(x: x, y: viewport.minY - 14)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            control("Rotate", icon: "rotate.right") { rotatePhoto() }
            control("Flip", icon: "arrow.left.and.right") { flipPhoto() }
            control("Zoom", icon: "plus.magnifyingglass") { adjustZoom(by: 1.5) }
            control("Reset", icon: "arrow.counterclockwise") { resetAlignment() }
        }
    }

    private func control(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: LineType.size(17), weight: .semibold))
                Text(title).font(.app(.caption2, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Color.lineBlue)
            .frame(maxWidth: .infinity, minHeight: layout.isRegular ? 76 : 50)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.lineBlue.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func transformGesture(baseFrame: CGRect, viewport: CGRect) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 0),
            MagnificationGesture()
        )
        .onChanged { value in
            let startingOffset = gestureStartOffset ?? imageOffset
            let startingScale = gestureStartScale ?? imageScale
            if gestureStartOffset == nil { gestureStartOffset = startingOffset }
            if gestureStartScale == nil { gestureStartScale = startingScale }

            // A single-finger pan can still report a tiny, jittery
            // magnification value in SwiftUI even with no real pinch
            // happening - multiplied by an already-large startingScale
            // (up to 12x for ovulation), that noise becomes a visible
            // shake. Treat anything within 2% of "no change" as exactly 1.
            let rawMagnification = value.second ?? 1
            let magnification = abs(rawMagnification - 1) < 0.02 ? 1 : rawMagnification
            let translation = value.first?.translation ?? .zero
            let scale = min(
                max(minimumScale(baseFrame: baseFrame, viewport: viewport), startingScale * magnification),
                maximumScale
            )
            let proposedOffset = CGSize(
                width: startingOffset.width + translation.width,
                height: startingOffset.height + translation.height
            )
            imageScale = scale
            imageOffset = clampedOffset(proposedOffset, baseFrame: baseFrame, viewport: viewport, scale: scale)
        }
        .onEnded { _ in
            gestureStartOffset = nil
            gestureStartScale = nil
        }
    }

    private func minimumScale(baseFrame: CGRect, viewport: CGRect) -> CGFloat {
        0.35
    }

    /// Screenshots often contain a very small strip amid a full screen of
    /// UI. Let those imports zoom far enough to fill the fixed guide.
    private var maximumScale: CGFloat {
        flow.testType == .ovulation ? 12 : 5
    }

    private func clampedOffset(_ proposed: CGSize, baseFrame: CGRect, viewport: CGRect, scale: CGFloat) -> CGSize {
        let scaledWidth = baseFrame.width * scale
        let scaledHeight = baseFrame.height * scale
        // Permit the image to move beyond the template while retaining a small
        // visible portion so it cannot be lost completely off screen.
        let minimumVisible: CGFloat = 44
        let maximumX = max(0, (scaledWidth + viewport.width) / 2 - minimumVisible)
        let maximumY = max(0, (scaledHeight + viewport.height) / 2 - minimumVisible)
        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    private func updateCropRect(baseFrame: CGRect, viewport: CGRect) {
        guard baseFrame.width > 0, baseFrame.height > 0 else { return }
        let transformed = CGRect(
            x: baseFrame.midX - baseFrame.width * imageScale / 2 + imageOffset.width,
            y: baseFrame.midY - baseFrame.height * imageScale / 2 + imageOffset.height,
            width: baseFrame.width * imageScale,
            height: baseFrame.height * imageScale
        )
        cropRect = CGRect(
            x: (viewport.minX - transformed.minX) / transformed.width,
            y: (viewport.minY - transformed.minY) / transformed.height,
            width: viewport.width / transformed.width,
            height: viewport.height / transformed.height
        )
    }

    private func adjustZoom(by factor: CGFloat) {
        withAnimation(.smooth(duration: 0.18)) {
            imageScale = min(max(0.35, imageScale * factor), maximumScale)
        }
    }

    private func resetAlignment() {
        withAnimation(.smooth(duration: 0.18)) { imageScale = 1; imageOffset = .zero }
    }

    private func rotatePhoto() { flow.image = flow.image?.rotatedClockwise(); resetAlignment() }
    private func flipPhoto() { flow.image = flow.image?.flippedHorizontally(); resetAlignment() }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (containerSize.width - fitted.width) / 2, y: (containerSize.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func continueWithCrop() {
        if let image = flow.image, let cropped = image.croppedWithPadding(toNormalizedRect: cropRect) { flow.image = cropped }
        flow.adjustedImage = nil
        flow.analysisResult = nil
        flow.autoSummary = ""
        flow.analysisRequestToken = UUID()
        flow.wasLocallyScanned = false
        // Ovulation's manual check has no enhance screen to visit - it goes
        // straight to the local heuristic scan (flow.mode stays
        // .manualEnhance, so the .analysing step routes to
        // LocalHeuristicCheckView, not the AI screen).
        let skipsEnhanceScreen = flow.mode == .manualEnhance && flow.testType == .ovulation
        flow.step = (flow.mode == .manualEnhance && !skipsEnhanceScreen) ? .manual : .analysing
    }
}

private extension View {
    func reverseMask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    mask().blendMode(.destinationOut)
                }
        }
    }
}

private extension UIImage {
    func flippedHorizontally() -> UIImage {
        let oriented = normalizedForCropping()
        let format = UIGraphicsImageRendererFormat()
        format.scale = oriented.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: oriented.size, format: format).image { context in
            let graphics = context.cgContext
            graphics.translateBy(x: oriented.size.width, y: 0)
            graphics.scaleBy(x: -1, y: 1)
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
    }

    func rotatedClockwise() -> UIImage {
        let oriented = normalizedForCropping()
        let outputSize = CGSize(width: oriented.size.height, height: oriented.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = oriented.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            let graphics = context.cgContext
            graphics.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
            graphics.rotate(by: .pi / 2)
            oriented.draw(in: CGRect(
                x: -oriented.size.width / 2,
                y: -oriented.size.height / 2,
                width: oriented.size.width,
                height: oriented.size.height
            ))
        }
    }

    func croppedWithPadding(toNormalizedRect rect: CGRect) -> UIImage? {
        let oriented = normalizedForCropping()
        guard rect.width > 0, rect.height > 0 else { return nil }
        let outputSize = CGSize(width: rect.width * oriented.size.width, height: rect.height * oriented.size.height)
        guard outputSize.width > 20, outputSize.height > 20 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = oriented.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor(white: 0.96, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            oriented.draw(in: CGRect(
                x: -rect.minX * oriented.size.width,
                y: -rect.minY * oriented.size.height,
                width: oriented.size.width,
                height: oriented.size.height
            ))
        }
    }

    func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
