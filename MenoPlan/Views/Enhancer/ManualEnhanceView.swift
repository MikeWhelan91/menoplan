import SwiftUI
import SwiftData
import TipKit

struct ManualEnhanceView: View {
    @Environment(AppState.self) private var appState
    @Bindable var flow: ScanFlow
    @State private var settings = EnhancementSettings()
    @State private var selectedTool: EnhanceTool?
    @State private var isAutoApplying = false
    @State private var autoSummary = ""
    private let enhancer = ImageEnhancementService()

    var enhanced: UIImage? {
        guard let image = flow.image else { return nil }
        return enhancer.enhance(image, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressSteps(current: 3, third: "Adjust")
                .padding(.horizontal, 18)
                .padding(.top, 12)

            Spacer(minLength: 16)

            Text("Adjust the photo until the lines are easy to see, then run a free local scan.")
                .font(.app(.subheadline))
                .foregroundStyle(Color.lineNavy.opacity(0.60))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            imagePreview
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Spacer(minLength: 16)

            bottomEditor
        }
        .background { LineCheckBrandBackdrop() }
        .onChange(of: flow.manualResetToken) { _, _ in
            resetAdjustments()
        }
    }

    private var imagePreview: some View {
        Group {
            if let image = enhanced ?? flow.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))
    }

    private var bottomEditor: some View {
        VStack(spacing: 14) {
            if selectedTool != nil, selectedTool != .auto {
                selectedControl
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, -2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(EnhanceTool.allCases) { tool in
                        Button {
                            handleToolTap(tool)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if tool == .auto, isAutoApplying {
                                        ProgressView()
                                            .tint(selectedTool == tool ? Color.linePink : Color.lineNavy)
                                    } else {
                                        Image(systemName: tool.icon)
                                            .font(.system(size: LineType.size(22), weight: .semibold))
                                    }
                                }
                                .frame(width: 40, height: 30)
                                Text(tool.title)
                                    .font(.app(.caption, weight: .medium))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(selectedTool == tool ? Color.linePink : Color.lineNavy)
                            .frame(minWidth: 58)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAutoApplying)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 6)
            }

            if !autoSummary.isEmpty {
                Text(autoSummary)
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            // Luna Check and "choose my result" both live on the Result
            // screen now ("Ask Luna about this result" / "Not the right
            // result?"), reachable after this free scan regardless of how
            // it read - not duplicated here too.
            Button {
                runLocalScan()
            } label: {
                Label("Local Scan", systemImage: "line.3.horizontal.decrease.circle")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryLine)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(.white)
    }

    @ViewBuilder
    private var selectedControl: some View {
        switch selectedTool {
        case .brightness:
            slider("Brightness", value: $settings.brightness, range: -0.4...0.4)
        case .contrast:
            slider("Contrast", value: $settings.contrast, range: 0.5...2.3)
        case .exposure:
            slider("Exposure", value: $settings.exposure, range: -1.0...1.0)
        case .gamma:
            slider("Gamma", value: $settings.gamma, range: 0.45...1.8)
        case .sharpen:
            slider("Sharpen", value: $settings.sharpen, range: 0...1.5)
        case .saturation:
            slider("Saturation", value: $settings.saturation, range: 0...1.8)
        case .warmth:
            slider("Warmth", value: $settings.warmth, range: -1...1)
        case .greyscale:
            toggleControl("Greyscale", isOn: $settings.greyscale)
        case .invert:
            toggleControl("Invert", isOn: $settings.invert)
        case .auto:
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.app(.subheadline, weight: .semibold))
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.app(.caption).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func toggleControl(_ title: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
            HStack {
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                Spacer()
            }
        }
    }

    @MainActor
    private func handleToolTap(_ tool: EnhanceTool) {
        if tool == .auto {
            Task { await applyAutoEnhancement() }
            return
        }
        selectedTool = selectedTool == tool ? nil : tool
    }

    @MainActor
    private func applyAutoEnhancement() async {
        guard !isAutoApplying else { return }
        guard let image = flow.image else {
            appState.toast = "No image available"
            return
        }
        selectedTool = .auto
        isAutoApplying = true
        defer { isAutoApplying = false }
        let result = await AutoEnhancementEngine().run(on: image, testType: flow.testType)
        settings = result.settings
        flow.adjustedImage = result.enhancedImage
        autoSummary = result.summary
        selectedTool = nil
        appState.toast = "Auto enhancement applied"
    }

    /// Runs the free, on-device heuristic scan (LocalHeuristicCheckView ->
    /// LineAnalysisEngine) - not Luna Check's trained model, and not a
    /// manual self-report either. flow.mode stays .manualEnhance so
    /// ScanFlowView's step switch routes .analysing to the heuristic
    /// screen instead of the AI one.
    @MainActor
    private func runLocalScan() {
        guard flow.image != nil else {
            appState.toast = "No image available"
            return
        }
        flow.adjustedImage = enhanced ?? flow.image
        flow.analysisRequestToken = UUID()
        flow.step = .analysing
    }

    private func resetAdjustments() {
        settings = EnhancementSettings()
        selectedTool = nil
        autoSummary = ""
        appState.toast = "Enhancements reset"
    }
}

private enum EnhanceTool: String, CaseIterable, Identifiable {
    case auto, brightness, contrast, exposure, gamma, sharpen, saturation, warmth, greyscale, invert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .exposure: "Exposure"
        case .gamma: "Gamma"
        case .sharpen: "Sharpen"
        case .saturation: "Saturation"
        case .warmth: "Warmth"
        case .greyscale: "Greyscale"
        case .invert: "Invert"
        }
    }

    var icon: String {
        switch self {
        case .auto: "wand.and.sparkles"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .exposure: "plusminus.circle"
        case .gamma: "camera.filters"
        case .sharpen: "wand.and.stars"
        case .saturation: "drop"
        case .warmth: "thermometer.sun"
        case .greyscale: "circle.grid.cross"
        case .invert: "circle.righthalf.filled"
        }
    }
}

private struct ScanningImagePreview: View {
    @Environment(\.lineLayout) private var layout
    let image: UIImage
    let scanColor: Color
    let scanLineAtBottom: Bool

    /// A test strip is wide and short, so this cap sets the preview's height
    /// as much as its width. 420pt fills a phone; on an iPad it leaves the
    /// strip as a thin band adrift in a mostly empty screen.
    private var maxPreviewWidth: CGFloat { layout.isRegular ? 760 : 420 }

    private var imageAspectRatio: CGFloat {
        guard image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, scanColor.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 3)
                    .shadow(color: scanColor.opacity(0.55), radius: 8)
                    .offset(y: scanLineAtBottom ? max(0, proxy.size.height - 3) : 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: maxPreviewWidth)
    }
}

struct OnDeviceCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Bindable var flow: ScanFlow
    @State private var failed = false
    @State private var errorMessage = ""
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

                if let image = flow.adjustedImage ?? flow.image {
                    ScanningImagePreview(
                        image: image,
                        scanColor: .linePink,
                        scanLineAtBottom: scanLineAtBottom
                    )
                }

                Text(statusPhrases[statusPhraseIndex])
                    .font(.app(size: LineType.size(30), weight: .heavy))
                    .foregroundStyle(flow.testType == .ovulation ? Color.linePurple : Color.linePink)
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

                LoadingStepDots(
                    count: statusPhrases.count,
                    currentIndex: statusPhraseIndex,
                    accentColor: flow.testType == .ovulation ? .linePurple : .linePink
                )
                    .padding(.top, 36)

                if failed {
                    VStack(spacing: 12) {
                        Text(errorMessage.isEmpty ? "Couldn’t check this photo." : errorMessage)
                            .font(.app(.footnote))
                            .foregroundStyle(Color.lineNavy.opacity(0.66))
                            .multilineTextAlignment(.center)
                        Button("Try another photo") { flow.resetForNewCapture(keepingStep: .guide) }
                            .buttonStyle(.secondaryLine)
                    }
                    .padding(16)
                    .padding(.top, 16)
                    .background(Color.linePinkSoft.opacity(0.74), in: RoundedRectangle(cornerRadius: 20))
                }

                Label("Your photo never leaves this device", systemImage: "lock.shield")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.45))
                    .padding(.top, 62)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 22)
        }
        .task { await analyse() }
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

    @MainActor
    private func analyse() async {
        guard let image = flow.adjustedImage ?? flow.image else {
            failed = true
            errorMessage = "No image was available for on-device analysis."
            return
        }
        let requestToken = flow.analysisRequestToken
        do {
            // Real on-device inference finishes in well under a second,
            // which reads as untrustworthy for a health result rather than
            // impressively fast - an instant answer doesn't feel like the
            // photo was actually looked at. Holding this screen for a
            // visible moment (letting the scan-line animation above
            // actually complete a few passes) sets more appropriate
            // expectations. Randomised within the range, not fixed, so
            // repeat scans don't feel robotically identical.
            async let minimumDisplay: Void = Task.sleep(for: .seconds(Double.random(in: 2.8...3.2)))
            guard let settings = appState.settings else {
                failed = true
                errorMessage = "Settings are unavailable."
                return
            }
            guard AICheckQuotaService().canUseAI(settings) else {
                failed = true
                errorMessage = "No Luna Checks are available right now. Return and choose another option."
                return
            }
            let usesIncludedFreeLuna = AICheckQuotaService().willConsumeFreeOvulationLuna(settings)
            let descriptor = FetchDescriptor<Scan>(sortBy: [SortDescriptor(\Scan.createdAt, order: .reverse)])
            let history = try modelContext.fetch(descriptor)
            let validOvulationScans = history.filter { scan in
                scan.testType == .ovulation
                    && scan.controlLineDetected
                    && scan.resultType != .invalid
                    && scan.resultType != .unclear
                    && !scan.excludedFromCalculations
            }
            let recentRatios = Array(validOvulationScans.prefix(8).map { $0.testControlRatio })
            async let analysisTask = OnDeviceOvulationAnalysisService().analyse(image, recentRatios: recentRatios)
            let (analysis, _) = try await (analysisTask, minimumDisplay)
            guard requestToken == flow.analysisRequestToken else { return }
            guard AICheckQuotaService().consumeAI(settings) else {
                failed = true
                errorMessage = "No Luna Checks are available right now. Return and choose another option."
                return
            }
            flow.completedFreeLunaCheck = usesIncludedFreeLuna
            try? modelContext.save()
            flow.analysisResult = analysis.result
            flow.localOvulationDiagnostics = analysis.diagnostics
            flow.autoSummary = "Analysed privately on this device. \(analysis.trendSummary)"
            guard requestToken == flow.analysisRequestToken else { return }
            if let settings = appState.settings,
               (settings.proUnlocked || flow.completedFreeLunaCheck),
               let result = flow.analysisResult {
                flow.personalisedGuidance = await personalisedGuidance(for: result, settings: settings)
            }
            guard requestToken == flow.analysisRequestToken else { return }
            flow.suppressCompletionInterstitial = true
            flow.step = .result
        } catch {
            guard requestToken == flow.analysisRequestToken else { return }
            failed = true
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func personalisedGuidance(for result: LineAnalysisResult, settings: UserSettings) async -> String? {
        do {
            let formatter = ISO8601DateFormatter()
            let current = AssistantRecentScanContext(
                date: formatter.string(from: flow.effectiveTestDate),
                testType: flow.testType.rawValue,
                resultType: result.resultType.rawValue,
                certaintyPercentage: result.certaintyPercentage,
                confidencePercentage: result.confidencePercentage,
                lineStrength: result.lineStrength,
                testControlRatio: result.testControlRatio,
                analysisMode: flow.mode.rawValue,
                notes: "",
                autoEnhancementSummary: ""
            )
            let scans = try modelContext.fetch(FetchDescriptor<Scan>(sortBy: [SortDescriptor(\Scan.createdAt, order: .reverse)]))
            let cycles = try modelContext.fetch(FetchDescriptor<CycleRecord>(sortBy: [SortDescriptor(\CycleRecord.startDate, order: .reverse)]))
            let logs = try modelContext.fetch(FetchDescriptor<DailyFertilityLog>(sortBy: [SortDescriptor(\DailyFertilityLog.date, order: .reverse)]))
            let periods = try modelContext.fetch(FetchDescriptor<PeriodEvent>(sortBy: [SortDescriptor(\PeriodEvent.startDate, order: .reverse)]))
            let metrics = try modelContext.fetch(FetchDescriptor<DailyHealthMetrics>())
            let response = try await AssistantService().reply(
                message: "Write a concise personalised next-step readout for the current result.",
                recentScans: [current] + scans.filter { $0.testType == flow.testType }.prefix(3).map { AssistantContextBuilder.recentScan($0, includeFreeText: false) },
                reminders: [],
                userContext: AssistantContextBuilder.userContext(
                    settings: settings,
                    cycles: cycles,
                    dailyLogs: Array(logs.prefix(7)),
                    periodEvents: periods,
                    maximumCycleSummaries: 2,
                    maximumDailySummaries: 7,
                    allDailyLogs: logs,
                    healthMetrics: metrics,
                    scans: scans,
                    signalSurface: flow.testType == .ovulation ? .ovulationResult : .pregnancyResult
                ),
                mode: "resultNarrative"
            )
            return response.reply
        } catch {
            #if DEBUG
            print("Personalised result guidance failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

struct LocalHeuristicCheckView: View {
    @Bindable var flow: ScanFlow
    @State private var failed = false
    @State private var errorMessage = ""
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

                if let image = flow.adjustedImage ?? flow.image {
                    ScanningImagePreview(
                        image: image,
                        scanColor: .linePink,
                        scanLineAtBottom: scanLineAtBottom
                    )
                }

                Text(statusPhrases[statusPhraseIndex])
                    .font(.app(size: LineType.size(30), weight: .heavy))
                    .foregroundStyle(flow.testType == .ovulation ? Color.linePurple : Color.linePink)
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

                LoadingStepDots(
                    count: statusPhrases.count,
                    currentIndex: statusPhraseIndex,
                    accentColor: flow.testType == .ovulation ? .linePurple : .linePink
                )
                    .padding(.top, 36)

                if failed {
                    VStack(spacing: 12) {
                        Text(errorMessage.isEmpty ? "Couldn’t check this photo." : errorMessage)
                            .font(.app(.footnote))
                            .foregroundStyle(Color.lineNavy.opacity(0.66))
                            .multilineTextAlignment(.center)
                        Button("Try another photo") { flow.resetForNewCapture(keepingStep: .guide) }
                            .buttonStyle(.secondaryLine)
                    }
                    .padding(16)
                    .padding(.top, 16)
                    .background(Color.linePinkSoft.opacity(0.74), in: RoundedRectangle(cornerRadius: 20))
                }

                Label("Your photo never leaves this device", systemImage: "lock.shield")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.45))
                    .padding(.top, 62)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 22)
        }
        .task { await analyse() }
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

    @MainActor
    private func analyse() async {
        guard let adjusted = flow.adjustedImage ?? flow.image else {
            failed = true
            errorMessage = "No image was available to check."
            return
        }
        let requestToken = flow.analysisRequestToken
        let original = flow.image
        let testType = flow.testType

        // Run the pixel scan on a background task rather than inline here -
        // this function is @MainActor, and the scan is a real synchronous
        // per-pixel pass that was blocking the scan-line animation from
        // rendering its first frames for a second or two. Racing it against
        // the minimum-display timer keeps this screen up without that
        // computation freezing the animation first. The real scan finishes
        // in well under a second, but a Manual Check that resolves near-
        // instantly reads as less considered than Luna Check - held longer
        // than the AI path on purpose, not shorter.
        async let computedResult = computeLocalScanResult(adjusted: adjusted, original: original, testType: testType)
        async let minimumDisplay: Void = Task.sleep(for: .seconds(Double.random(in: 8...10)))

        let (result, _) = await (computedResult, try? minimumDisplay)
        guard requestToken == flow.analysisRequestToken else { return }
        flow.analysisResult = result
        flow.autoSummary = localScanSummary(for: result, testType: testType)
        flow.wasLocallyScanned = true
        flow.step = .result
    }
}

private func computeLocalScanResult(adjusted: UIImage, original: UIImage?, testType: TestType) async -> LineAnalysisResult {
    // Ovulation keeps its original full-strip reader. Its legacy colour-pair
    // analyser locates the T/C window itself; constraining it to the new
    // pregnancy reader crop makes both lines collapse to a zero ratio.
    if testType == .ovulation {
        let localAnalyser = LineAnalysisEngine()
        let adjustedResult = localAnalyser.analyse(adjusted, testType: .ovulation)
        if let original {
            let originalResult = localAnalyser.analyse(original, testType: .ovulation)
            return localAnalyser.preferredOvulationResult(primary: originalResult, fallback: adjustedResult)
        }
        return adjustedResult
    }

    let qualityService = ImageQualityService()
    let sourceImage = original ?? adjusted
    let sourceQuality = qualityService.score(sourceImage)
    let surfaceDetected = qualityService.hasPlausibleTestSurface(sourceImage, testType: testType)
    let localAnalyser = LineAnalysisEngine()
    let adjustedInput = TestTemplateGeometry.localReaderImage(from: adjusted)
    let adjustedResult = localAnalyser.analyse(adjustedInput, testType: testType)
    let originalResult = original.map {
        localAnalyser.analyse(
            TestTemplateGeometry.localReaderImage(from: $0),
            testType: testType
        )
    }
    let result: LineAnalysisResult
    if let originalResult {
        result = localAnalyser.preferredOvulationResult(primary: originalResult, fallback: adjustedResult)
    } else {
        result = adjustedResult
    }
    // Surface colour can change dramatically after enhancement. A clear,
    // position-valid control line is stronger evidence that this is a real
    // test than the broad material-colour gate, so do not reject that image
    // before the line reader gets to report it. A wall still has neither.
    guard surfaceDetected || result.controlLineDetected
        || adjustedResult.controlLineDetected
        || originalResult?.controlLineDetected == true else {
        let testName = "ovulation"
        return LineAnalysisResult(
            resultType: .invalid,
            confidencePercentage: 0,
            certaintyPercentage: 45,
            controlLineDetected: false,
            testLineDetected: false,
            testControlRatio: 0,
            lineStrength: 0,
            quality: sourceQuality,
            explanation: "No readable \(testName)-test surface or control line was detected, so this image cannot be interpreted. Retake the photo with the result window clearly visible."
        )
    }
    return result
}

private func localScanSummary(for result: LineAnalysisResult, testType: TestType) -> String {
    let control = result.controlLineDetected ? "Control line detected." : "Control line not detected."
    let test = testType == .ovulation
        ? (result.testLineDetected ? "Surge line detected." : "No surge line detected.")
        : (result.testLineDetected ? "Possible test line detected." : "No test line detected.")
    return "\(control) \(test) This local scan used the adjusted image and did not send the photo off device."
}
