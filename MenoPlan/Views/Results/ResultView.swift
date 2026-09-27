import Charts
import SwiftData
import SwiftUI
import TipKit

struct ResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lineLayout) private var layout
    @Environment(AppState.self) private var appState
    @Query(sort: \Scan.createdAt, order: .reverse) private var scans: [Scan]
    @Query(sort: \CycleRecord.startDate) private var cycleRecords: [CycleRecord]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @Query(sort: \DailyFertilityLog.date, order: .reverse) private var dailyLogs: [DailyFertilityLog]
    @Query(sort: \PeriodEvent.startDate, order: .reverse) private var periodEvents: [PeriodEvent]
    @Query(sort: \DailyHealthMetrics.date) private var healthMetrics: [DailyHealthMetrics]
    @Bindable var flow: ScanFlow
    @State private var notes = ""
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var savedScan: Scan?
    @State private var comparePair: ResultComparePair?
    @State private var didAttemptAutoSave = false
    @State private var didAttemptInterstitial = false
    @State private var revealLine = false
    @State private var revealedSectionCount = 0
    @State private var activeTerminologyInfo: TerminologyInfo?
    @State private var showMedicalSources = false
    @State private var showReminderEditor = false
    @State private var showRetryChoices = false
    @State private var isUnlockingRetry = false
    @State private var showDisputeChoice = false
    @State private var showLookAgainOpinionPicker = false
    @State private var showOverrideSheet = false
    @State private var isRunningLookAgain = false
    @State private var showZoomedImage = false
    @State private var showSelfAssessmentLunaGate = false
    @State private var isUnlockingSelfAssessmentLuna = false
    @State private var personalisedGuidance: AssistantResponse?
    @State private var isLoadingPersonalisedGuidance = false

    /// A complimentary Luna Check includes one personalised next-step readout
    /// for that same result. It does not unlock guidance for other free scans.
    private var canUsePersonalisedGuidance: Bool {
        appState.settings?.proUnlocked == true || flow.completedFreeLunaCheck
    }
    /// Picked once per result view so repeated tiers don't always show the
    /// exact same wording, while staying stable for the duration of viewing
    /// this one result (no reshuffling on every re-render).
    @State private var ovulationCopySeed = Int.random(in: 0..<10_000)
    private let tcTip = TCRatioTip()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .center, spacing: 24) {
                    if let result = flow.analysisResult {
                        resultImage
                            .resultSectionFade(index: 0, revealedCount: revealedSectionCount)
                        if isSelfAssessedResult {
                            resultHero(result)
                            resultSectionDivider
                            selfAssessmentExplanation(result)
                        } else if flow.wasLocallyScanned {
                            // "What To Do Now" is interpretive TTC
                            // guidance, and the stage stepper/evidence
                            // breakdown read as more diagnostic certainty
                            // than a pixel heuristic backs up - all three
                            // are reserved for an AI-backed result.
                            ovulationResultPanel(result, showStageDetail: false)
                            resultSectionDivider
                            localScanLunaNudge
                        } else {
                            ovulationResultPanel(result)
                            resultSectionDivider
                            ovulationInsight(result)
                        }
                        let readingSignals = resultSignals(result)
                        if !readingSignals.isEmpty {
                            CycleSignalsCard(title: "What may affect this reading", signals: readingSignals)
                                .resultSectionFade(index: 1, revealedCount: revealedSectionCount)
                        }
                        resultSectionDivider
                        ovulationCycleStats(result)
                            .resultSectionFade(index: 1, revealedCount: revealedSectionCount)
                        if !flow.wasLocallyScanned,
                           appState.settings?.proUnlocked == true || lineStrengthTrendScans.count >= 2 {
                            resultSectionDivider
                            lineStrengthTrendSection
                        }
                        resultSectionDivider
                        trackingDetails
                            .resultSectionFade(index: 5, revealedCount: revealedSectionCount)
                        if flow.wasLocallyScanned {
                            resultSectionDivider
                            localScanAccuracyNote
                        }
                        resultSectionDivider
                        resultActions
                            .resultSectionFade(index: 6, revealedCount: revealedSectionCount)
#if DEBUG
                        if let diagnostics = flow.localOvulationDiagnostics {
                            resultSectionDivider
                            localOvulationDebugPanel(diagnostics)
                        }
#endif
                    }
                    SafetyFooter {
                        showMedicalSources = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                // The long-standing 560 column is kept for every size it was
                // tuned at. Only the 13" iPad opts into the wider reading
                // column, where 560 inside a 1032pt screen left the page as a
                // thin strip down the middle. Presented as a full-screen cover,
                // this screen never receives the shell's resolved layout
                // metrics, so the column comes from its own geometry.
                .frame(
                    maxWidth: min(
                        proxy.size.width - 32,
                        proxy.size.width >= 1000
                            ? LineLayoutMetrics.readableColumn(forWidth: proxy.size.width)
                            : 560
                    ),
                    alignment: .center
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background { LineCheckBrandBackdrop() }
        .overlay {
            if showSelfAssessmentLunaGate {
                LunaCheckGateOverlay(
                    title: "No Luna Checks left right now",
                    message: "Watch an ad for one more check, or upgrade for unlimited Luna Checks.",
                    adButtonTitle: "Watch ad for one more Luna Check",
                    onWatchAd: { Task { await unlockLunaForSelfAssessment() } },
                    onUpgrade: {
                        showSelfAssessmentLunaGate = false
                        appState.paywallSource = "luna_check_quota"
                        appState.showPremium = true
                    },
                    onClose: { showSelfAssessmentLunaGate = false }
                )
            } else if showRetryChoices {
                TestAgainChoiceOverlay(
                    isUnlocking: isUnlockingRetry,
                    lunaButtonTitle: retryLunaButtonTitle,
                    onLuna: {
                        Task { await retryWithLuna() }
                    },
                    onLocalScan: retryWithLocalScan,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showRetryChoices = false
                        }
                    }
                )
            } else if showDisputeChoice {
                DisputeChoiceOverlay(
                    offersLookAgain: showsLookAgainOption,
                    onLookAgain: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showDisputeChoice = false
                            if appState.settings?.proUnlocked == true {
                                showLookAgainOpinionPicker = true
                            } else {
                                appState.paywallSource = "look_again_locked"
                                appState.showPremium = true
                            }
                        }
                    },
                    onSayItMyself: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showDisputeChoice = false
                            showOverrideSheet = true
                        }
                    },
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showDisputeChoice = false
                        }
                    }
                )
            } else if showLookAgainOpinionPicker {
                LookAgainOpinionOverlay(
                    testType: flow.testType,
                    onSubmit: { opinion in
                        showLookAgainOpinionPicker = false
                        Task { await performLookAgain(userOpinion: opinion) }
                    },
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showLookAgainOpinionPicker = false
                        }
                    }
                )
            } else if showOverrideSheet {
                ResultOverrideOverlay(
                    testType: flow.testType,
                    onSelect: { resultType, testControlRatio in
                        applyManualOverride(resultType, testControlRatio: testControlRatio)
                        showOverrideSheet = false
                    },
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showOverrideSheet = false
                        }
                    }
                )
            } else if isRunningLookAgain {
                BrandedLoadingScreen(title: "Looking again…")
            }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems, onDismiss: { showShare = false }) }
        .sheet(item: $comparePair) { pair in
            CompareView(initialFirst: pair.previous, initialSecond: pair.current)
        }
        .sheet(item: $activeTerminologyInfo) { info in
            InfoSheet(title: info.title, message: info.message)
        }
        .sheet(isPresented: $showMedicalSources) {
            MedicalSourcesSheet()
        }
        .sheet(isPresented: $showReminderEditor) {
            ReminderEditorView(
                initialType: .ovulationTest,
                initialDate: reminderDate(),
                initialTitle: reminderTitle()
            )
        }
        .toast(message: Binding(get: { appState.toast }, set: { appState.toast = $0 }))
        .task {
            if notes.isEmpty { notes = flow.notes }
            await autoSaveResultIfNeeded()
        }
        .onChange(of: flow.pendingResultAction) { _, action in
            guard let action else { return }
            flow.pendingResultAction = nil
            switch action {
            case .saveImage:
                saveDisplayedImage()
            case .exportPDF:
                if let result = flow.analysisResult {
                    if appState.settings?.proUnlocked == true {
                        export(result: result)
                    } else {
                        appState.paywallSource = "pdf_export"
                        appState.showPremium = true
                        appState.toast = "PDF export is included with MenoPlan Pro"
                    }
                }
            }
        }
        .onAppear {
            revealLine = false
            revealedSectionCount = 0
            showInterstitialIfNeeded()
            withAnimation(.easeInOut(duration: 1.1).delay(0.15)) {
                revealLine = true
            }
            Task { @MainActor in
                for count in 1...7 {
                    try? await Task.sleep(for: .milliseconds(count == 1 ? 180 : 95))
                    withAnimation(.easeOut(duration: 0.42)) {
                        revealedSectionCount = count
                    }
                }
            }
        }
        .onChange(of: notes) { _, value in
            flow.notes = value
            savedScan?.notes = value
            try? modelContext.save()
        }
    }

#if DEBUG
    private func localOvulationDebugPanel(_ diagnostics: LocalOvulationDiagnostics) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(diagnostics.report)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.lineNavy.opacity(0.78))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy diagnostics") {
                    UIPasteboard.general.string = diagnostics.report
                    appState.toast = "OPK diagnostics copied"
                }
                .buttonStyle(.secondaryLine)
                if let analyzedImage = diagnostics.analyzedImage {
                    Button("Save proposed T/C window to Photos") {
                        UIImageWriteToSavedPhotosAlbum(analyzedImage, nil, nil, nil)
                        appState.toast = "Saved the exact OPK window sent to the model"
                    }
                    .buttonStyle(.secondaryLine)
                }
            }
            .padding(.top, 12)
        } label: {
            Label("OPK Model Debug", systemImage: "ladybug.fill")
                .font(.app(.headline))
                .foregroundStyle(Color.lineNavy)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.orange.opacity(0.25))
        }
    }

#endif

    /// Shown because the person told us they have PCOS: LH can sit high for
    /// days, so a single High/Peak is weaker evidence of an imminent surge.
    /// Everything in this person's data that changes how this particular
    /// result should be read - hydration, contraception, breastfeeding, PCOS,
    /// a temperature shift, a late period... The same observations go to
    /// Luna's personalised readout (signalSurface below), so they agree.
    private func resultSignals(_ result: LineAnalysisResult) -> [CycleSignal] {
        guard let settings = appState.settings else { return [] }
        let realCycles = cycleRecords.filter { !$0.notes.contains("[LineCheck Screenshot Sample]") }
        let input = CycleSignalInputs(
            window: CycleTrackingService.window(records: realCycles, periods: periodEvents, settings: settings),
            activeCycle: CycleTrackingService.activeCycle(records: realCycles),
            logs: dailyLogs,
            metrics: healthMetrics,
            scans: Array(scans),
            profile: settings.healthProfile,
            tryingToConceive: settings.ovulationTrackingGoal == .tryingToConceive
        )
        let surface: CycleSignalSurface = .ovulationResult
        return CycleSignalsEngine.signals(for: surface, input)
            // PCOS only changes the reading of a High/Peak - on a Low it's noise.
            .filter { $0.id != "pcosLH" || [.high, .peak].contains(result.resultType) }
            .prefix(3)
            .map { $0 }
    }

    private var resultSectionDivider: some View {
        Divider()
            .overlay(Color.lineNavy.opacity(0.08))
            .resultSectionFade(index: max(0, revealedSectionCount - 1), revealedCount: revealedSectionCount)
    }

    private var trackingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Tracking Details")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                Spacer(minLength: 8)
                Label(
                    "Tested \(flow.effectiveTestDate.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "clock"
                )
                .lineLimit(1)
            }
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(Color.lineNavy.opacity(0.62))

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add a note about timing, symptoms, or the test")
                        .foregroundStyle(Color.secondary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                }
                TextField("", text: $notes, axis: .vertical)
                    .lineLimit(2...)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func resultHero(_ result: LineAnalysisResult) -> some View {
        VStack(alignment: .center, spacing: 16) {
            if isSelfAssessedResult {
                Label("You marked this as", systemImage: "hand.tap")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
            } else if flow.wasLocallyScanned {
                Label("Manual Check · Local Scan", systemImage: "viewfinder")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
            }
            Text(flow.wasLocallyScanned ? localScanHeroTitle(result) : result.resultType.referenceTitle)
                .font(.app(size: LineType.size(34), weight: .heavy))
                .foregroundStyle(flow.wasLocallyScanned ? Color.lineNavy : result.resultType.tint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(isSelfAssessedResult ? "Your selected result" : (flow.wasLocallyScanned ? localScanHeroSubtitle(result) : resultSubtitle(for: result)))
                .font(.app(.headline))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)

            if !isSelfAssessedResult && !flow.wasLocallyScanned {
                trendHintLabel(tint: Color.linePurple)

                VStack(alignment: .center, spacing: 8) {
                    HStack {
                        Text("Image Readability")
                        Spacer()
                        Text("\(result.certaintyPercentage)%")
                    }
                    .font(.app(.subheadline, weight: .medium))
                    certaintyBars(result)
                    Text(result.certaintyPercentage >= 80 ? "High image readability" : result.certaintyPercentage >= 58 ? "Moderate image readability" : "Low image readability")
                        .font(.app(.caption))
                        .foregroundStyle(result.resultType.tint)
                }
            } else if flow.wasLocallyScanned {
                localScanLunaNudge
            }

        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    /// A local scan only reports what its pixel heuristic found - it doesn't
    /// carry the same "we're confident this is X" weight a trained Luna read
    /// does, so the headline stays factual (line detected/not) rather than a
    /// diagnostic-style verdict like "Positive"/"Negative", and skips the
    /// AI-style readability confidence framing entirely.
    private func localScanHeroTitle(_ result: LineAnalysisResult) -> String {
        guard result.controlLineDetected else { return "Can’t Read This Test" }
        return result.testLineDetected ? "Line Detected" : "No Line Detected"
    }

    private func localScanHeroSubtitle(_ result: LineAnalysisResult) -> String {
        guard result.controlLineDetected else {
            return "The control line wasn’t clearly visible"
        }
        return result.testLineDetected
            ? "A second line was visible in your photo"
            : "No second line was visible in your photo"
    }

    private var localScanLunaNudge: some View {
        VStack(spacing: 14) {
            Label("A quick on-device estimate, not a confident read", systemImage: "exclamationmark.triangle")
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.55))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text("What Luna Check adds")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.linePurple)
                VStack(alignment: .leading, spacing: 6) {
                    Text("•  A confident AI read, not just what was detected")
                    Text("•  Personalised guidance on what to do next")
                    Text("•  Line-strength trends across your saved tests")
                }
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                startLunaForSelfAssessment()
            } label: {
                Label("Ask Luna to Analyse This Photo", systemImage: "moon.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryLine)
        }
        .padding(.horizontal, 16)
    }

    /// True only for a genuine self-report (the "Not the right result?"
    /// override) - a free local scan is still a real analysis, so it takes
    /// the normal explanation UI instead of the "you picked this, nothing
    /// analysed it" treatment.
    private var isSelfAssessedResult: Bool {
        flow.mode == .manualEnhance && !flow.wasLocallyScanned
    }

    private func selfAssessmentExplanation(_ result: LineAnalysisResult) -> some View {
        VStack(spacing: 14) {
            Label("Your Selection", systemImage: "hand.tap.fill")
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(result.resultType.resultTint(for: flow.testType))

            Text(selfAssessmentCopy(for: result.resultType))
                .font(.app(.body))
                .lineSpacing(4)
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("MenoPlan has saved what you selected; it has not independently analysed this photo.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.55))
                .multilineTextAlignment(.center)

            Button {
                startLunaForSelfAssessment()
            } label: {
                Label("Ask Luna to Analyse This Photo", systemImage: "moon.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryLine)
        }
        .frame(maxWidth: .infinity)
    }

    private func selfAssessmentCopy(for resultType: ScanResultType) -> String {
        switch resultType {
        case .unclear: "You selected unclear because you could not confidently choose another result. You can retake the photo or repeat the test according to its instructions."
        case .low: "You selected low, indicating that the test line looks much lighter than the control line."
        case .rising: "You selected rising, indicating that the test line is becoming more visible but remains lighter than the control line."
        case .high: "You selected high, indicating that the test line looks close to the control line."
        case .peak: "You selected peak, indicating that the test line looks as dark as or darker than the control line."
        default: "This is the result you selected and saved for your records."
        }
    }

    private func lineEvidence(label: String, status: String, detected: Bool, tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: detected ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .font(.system(size: LineType.size(22), weight: .bold))
                .foregroundStyle(detected ? tint : Color.lineNavy.opacity(0.38))

            Text(label)
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.50))
            Text(status)
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func ovulationEvidence(_ result: LineAnalysisResult) -> some View {
        let controlIsConfirmed = result.controlLineDetected
            && ![.unclear, .invalid].contains(result.resultType)
        let tint = result.resultType.ovulationTint
        return VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.system(size: LineType.size(19), weight: .bold))
                    .foregroundStyle(tint)
                Text("Visible Line Check")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
            }

            HStack(alignment: .top, spacing: 16) {
                lineEvidence(
                    label: "Test",
                    status: result.resultType.testLineLabel,
                    detected: result.testLineDetected,
                    tint: tint
                )
                lineEvidence(
                    label: "Control",
                    status: controlIsConfirmed ? "Detected" : "Not Clear",
                    detected: controlIsConfirmed,
                    tint: controlIsConfirmed ? tint : Color.lineNavy
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func resultMetric(title: String, value: String, symbol: String, info: TerminologyInfo? = nil) -> some View {
        VStack(alignment: .center, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: LineType.size(15), weight: .bold))
                .foregroundStyle(Color.linePink)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.72), in: Circle())
            HStack(spacing: 3) {
                Text(title)
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.48))
                if let info {
                    terminologyButton(info)
                }
            }
            Text(value)
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
        .padding(10)
    }

    private var trendHint: String? {
        guard let previous = previousComparableScan, let current = flow.analysisResult else { return nil }
        let dayText = relativeDayText(for: previous.createdAt)
        let delta = current.lineStrength - previous.lineStrength
        guard abs(delta) >= 0.03 else { return "Similar to your test from \(dayText)." }
        return delta > 0 ? "Line looks darker than your test from \(dayText)." : "Line looks lighter than your test from \(dayText)."
    }

    private func relativeDayText(for date: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    private func trendHintLabel(tint: Color) -> some View {
        Group {
            if let trendHint {
                HStack(spacing: 5) {
                    Image("HomeTrendsIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 14)
                    Text(trendHint)
                }
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.10), in: Capsule())
            }
        }
    }

    private var lineStrengthTrendScans: [Scan] {
        scans
            .filter {
                $0.testType == flow.testType
                    && $0.analysisMode == .aiQuickCheck
                    // An invalid or unclear read isn't a real measurement -
                    // charting it as a data point (even at 0) misrepresents
                    // "couldn't be read" as "no line detected".
                    && $0.resultType != .invalid
                    && $0.resultType != .unclear
            }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(10)
    }

    private struct LineStrengthPoint: Identifiable {
        let id: UUID
        let index: Int
        let strength: Double
        let dateLabel: String
        let isCurrent: Bool
        let resultColor: Color
    }

    /// Plotted by index rather than real elapsed time - scans logged close together in time
    /// (e.g. a retest an hour later) would otherwise bunch into a near-vertical zigzag on a
    /// real time axis, since the line has almost no horizontal room to work with between them.
    private var lineStrengthTrendPoints: [LineStrengthPoint] {
        lineStrengthTrendScans.enumerated().map { index, scan in
            LineStrengthPoint(
                id: scan.id,
                index: index,
                strength: scan.lineStrength,
                dateLabel: DateFormatting.axisDate.string(from: scan.createdAt),
                isCurrent: scan.id == savedScan?.id,
                resultColor: scan.resultType.resultTint(for: flow.testType)
            )
        }
    }

    private var lineStrengthTrendAxisIndices: [Int] {
        let stride = max(1, lineStrengthTrendPoints.count / 4)
        return lineStrengthTrendPoints.map(\.index).filter { $0 % stride == 0 }
    }

    private var lineStrengthTrendTint: Color {
        flow.analysisResult?.resultType.resultTint(for: flow.testType) ?? Color.linePurple
    }

    /// Tied to the test type (pink for pregnancy, purple for ovulation), not the specific
    /// result, so the line/area read as the app's normal brand color for this chart rather
    /// than "this whole trend is a positive/negative result" - the individual points still
    /// carry the actual per-scan result color.
    private var lineStrengthTrendLineColor: Color {
        Color.linePurple
    }

    private var lineStrengthTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                HStack(spacing: 6) {
                    Image("HomeTrendsIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 19, height: 16)
                    Text("Line Strength Trend")
                }
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(lineStrengthTrendTint)

                HStack {
                    Spacer()
                    if appState.settings?.proUnlocked != true {
                        Text("PRO")
                            .font(.app(.caption2, weight: .heavy))
                            .foregroundStyle(lineStrengthTrendTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(lineStrengthTrendTint.opacity(0.09), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ZStack {
                Group {
                    if lineStrengthTrendScans.count >= 2 {
                        Chart(lineStrengthTrendPoints) { point in
                            // The line/area are tied to the test type, not the specific
                            // result - it's the individual points that carry the per-scan
                            // meaning, so the trend as a whole doesn't read as "this whole
                            // chart is a positive/negative result".
                            AreaMark(
                                x: .value("Scan", point.index),
                                y: .value("Strength", point.strength)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [lineStrengthTrendLineColor.opacity(0.28), lineStrengthTrendLineColor.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Scan", point.index),
                                y: .value("Strength", point.strength)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(lineStrengthTrendLineColor)

                            PointMark(
                                x: .value("Scan", point.index),
                                y: .value("Strength", point.strength)
                            )
                            .symbolSize(point.isCurrent ? 90 : 55)
                            .foregroundStyle(point.resultColor)

                            PointMark(
                                x: .value("Scan", point.index),
                                y: .value("Strength", point.strength)
                            )
                            .symbolSize(point.isCurrent ? 34 : 20)
                            .foregroundStyle(.white)
                        }
                        .frame(height: 140)
                        .chartXAxis {
                            AxisMarks(values: lineStrengthTrendAxisIndices) { value in
                                if let index = value.as(Int.self), let label = lineStrengthTrendPoints.first(where: { $0.index == index })?.dateLabel {
                                    AxisValueLabel(label)
                                        .font(.app(.caption2, weight: .semibold))
                                        .foregroundStyle(Color.lineNavy.opacity(0.5))
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                                    .foregroundStyle(Color.lineNavy.opacity(0.12))
                                AxisValueLabel()
                                    .font(.app(.caption2, weight: .semibold))
                                    .foregroundStyle(Color.lineNavy.opacity(0.5))
                            }
                        }
                        // The last axis label is centered on its tick, which sits
                        // exactly at the chart's trailing edge - without this, its
                        // right half overflows past the plot area and gets clipped
                        // (e.g. "27 Aug" rendering as "27...").
                        .padding(.horizontal, 14)
                    } else {
                        Text("Save a couple more scans to see your trend over time.")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .blur(radius: appState.settings?.proUnlocked == true ? 0 : 2.5)

                if appState.settings?.proUnlocked != true {
                    Button {
                        appState.paywallSource = "locked_content"
                        appState.showPremium = true
                    } label: {
                        VStack(spacing: 5) {
                            Label("See how your line is changing", systemImage: "lock.fill")
                                .font(.app(.subheadline, weight: .bold))
                            Text("Unlock trends and comparisons with Pro")
                                .font(.app(.caption))
                        }
                        .foregroundStyle(lineStrengthTrendTint)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(lineStrengthTrendTint.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if appState.settings?.proUnlocked == true, lineStrengthTrendScans.count >= 2 {
                Text("Tracks how strong the test line has looked across your last \(lineStrengthTrendScans.count) ovulation scans.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A light, non-blocking reminder that this specific result came from
    /// the free local scanner - meaningfully less accurate than Luna Check
    /// per this app's own calibration testing - shown for every locally
    /// scanned result, not just as an upsell moment.
    private var localScanAccuracyNote: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.app(.footnote, weight: .bold))
                .foregroundStyle(Color.orange)
            Text("This local scan is less accurate than Luna Check. For anything that matters, confirm with Luna Check.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.22)))
    }

    private var previousComparableScan: Scan? {
        guard let current = savedScan else { return nil }
        return scans.first {
            $0.id != current.id &&
            $0.testType == current.testType &&
            ($0.cycleRecordID == nil || current.cycleRecordID == nil || $0.cycleRecordID == current.cycleRecordID) &&
            $0.createdAt < current.createdAt
        }
    }

    private var resultActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if savedScan != nil {
                Button {
                    // With no "Look Again" AI re-check to offer, the choice
                    // screen would show exactly one real option - skip
                    // straight to the classification picker instead of
                    // making the user tap through a screen with nothing to
                    // actually choose.
                    if showsLookAgainOption {
                        showDisputeChoice = true
                    } else {
                        showOverrideSheet = true
                    }
                } label: {
                    Label("Not the right result?", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryLine)
            }

            if let current = savedScan, let previous = previousComparableScan {
                Button {
                    comparePair = ResultComparePair(previous: previous, current: current)
                } label: {
                    Label("Compare with previous", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryLine)
            }

            if !flow.wasLocallyScanned {
                Button {
                    askLunaAboutThisResult()
                } label: {
                    Label("Ask Luna about this result", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryLine)
            }

            HStack(spacing: 12) {
                Button("Test Again") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        showRetryChoices = true
                    }
                }
                    .buttonStyle(.secondaryLine)
                    .frame(maxWidth: .infinity)
                Button("Done") { finishResultFlow() }
                    .buttonStyle(.primaryLine)
                    .frame(maxWidth: .infinity)
            }
            Text("Results are saved automatically to history.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }


    /// Visibility only - shown to every AI Quick Check user regardless of
    /// Pro status, since free users should see the option exists. Whether
    /// tapping it actually runs a recheck or opens the paywall is decided
    /// separately, at tap time, in the onLookAgain handler above.
    private var showsLookAgainOption: Bool {
        flow.mode == .aiQuickCheck && savedScan?.hasUsedLookAgain != true
    }

    private var retryLunaButtonTitle: String {
        guard let settings = appState.settings else { return "Watch ad for Luna Check" }
        return AICheckQuotaService().canUseAI(settings)
            ? "Use Luna Check"
            : "Watch ad for Luna Check"
    }

    @MainActor
    private func startLunaForSelfAssessment() {
        guard let settings = appState.settings else { return }
        let quota = AICheckQuotaService()

        if quota.canUseAI(settings) {
            beginLunaAnalysisOfCurrentPhoto()
        } else if quota.canClaimRewardedCheck(settings) {
            showSelfAssessmentLunaGate = true
        } else {
            AppAnalytics.log("linecheck_ai_quota_exhausted", ["test_type": flow.testType.rawValue])
            appState.paywallSource = "luna_check_quota"
            appState.showPremium = true
            appState.toast = "Unlock Pro for unlimited Luna Checks"
        }
    }

    @MainActor
    private func unlockLunaForSelfAssessment() async {
        guard !isUnlockingSelfAssessmentLuna, let settings = appState.settings else { return }
        let quota = AICheckQuotaService()
        isUnlockingSelfAssessmentLuna = true
        defer { isUnlockingSelfAssessmentLuna = false }

        guard await RewardedAdService().showRewardedAd() else {
            appState.toast = "Rewarded ad unavailable"
            return
        }

        let added = quota.addRewardedChecks(settings)
        guard added else {
            appState.toast = "A rewarded Luna Check is not available right now"
            return
        }

        try? modelContext.save()
        flow.suppressCompletionInterstitial = true
        showSelfAssessmentLunaGate = false
        beginLunaAnalysisOfCurrentPhoto()
    }

    @MainActor
    private func beginLunaAnalysisOfCurrentPhoto() {
        flow.mode = .aiQuickCheck
        flow.analysisRequestToken = UUID()
        flow.wasLocallyScanned = false
        flow.step = .analysing
    }

    @MainActor
    private func retryWithLuna() async {
        guard !isUnlockingRetry, let settings = appState.settings else { return }
        let quota = AICheckQuotaService()

        if quota.canUseAI(settings) {
            beginRetry(mode: .aiQuickCheck)
            return
        }

        guard quota.canClaimRewardedCheck(settings) else {
            appState.toast = "This week's rewarded Luna Checks have been used"
            return
        }

        isUnlockingRetry = true
        defer { isUnlockingRetry = false }
        if await RewardedAdService().showRewardedAd(),
           quota.addRewardedChecks(settings) {
            flow.suppressCompletionInterstitial = true
            try? modelContext.save()
            beginRetry(mode: .aiQuickCheck)
        } else {
            appState.toast = quota.canClaimRewardedCheck(settings)
                ? "Rewarded ad unavailable"
                : "This week's rewarded Luna Checks have been used"
        }
    }

    @MainActor
    private func retryWithLocalScan() {
        beginRetry(mode: .manualEnhance)
    }

    @MainActor
    private func beginRetry(mode: AnalysisMode) {
        showRetryChoices = false
        flow.mode = mode
        flow.resetForNewCapture(keepingStep: .guide)
    }

    private func resultSubtitle(for result: LineAnalysisResult) -> String {
        return result.resultType.referenceSubtitle(testType: flow.testType)
    }

    private func certaintyBars(_ result: LineAnalysisResult) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(index < Int(round(Double(result.certaintyPercentage) / 100.0 * 12.0)) ? result.resultType.resultTint(for: flow.testType) : Color.black.opacity(0.08))
                    .frame(height: 8)
            }
        }
    }

    private func revealMark(tint: Color, delayOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(delayOpacity))
            .frame(width: 9, height: 38)
            .scaleEffect(y: revealLine ? 1 : 0.15, anchor: .center)
    }

    private var resultImage: some View {
        VStack(spacing: 0) {
            if let image = flow.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 180)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { showZoomedImage = true }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.35), in: Circle())
                            .padding(10)
                    }
                    .fullScreenCover(isPresented: $showZoomedImage) {
                        ZoomableImageView(image: image) { showZoomedImage = false }
                    }
            }
        }
    }

    private func ovulationResultPanel(_ result: LineAnalysisResult, showStageDetail: Bool = true) -> some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: result.resultType.ovulationStatusIcon)
                .font(.system(size: LineType.size(20), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(result.resultType.ovulationTint, in: Circle())
            Text(result.resultType.referenceTitle)
                .font(.app(size: LineType.size(32), weight: .heavy))
                .foregroundStyle(result.resultType.ovulationTint)
                .multilineTextAlignment(.center)
            Text(result.resultType.ovulationRatioDescription)
                .font(.app(.headline))
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            trendHintLabel(tint: result.resultType.ovulationTint)

            HStack(alignment: .top, spacing: 0) {
                ovulationMetric(
                    title: "Line Ratio",
                    value: result.testControlRatio.formatted(.number.precision(.fractionLength(2))),
                    detail: "Test line ÷ control",
                    tint: result.resultType.ovulationTint,
                    help: TerminologyInfo(
                        title: "Test/control value",
                        message: "This is a photo-based comparison of the test line with the control line. It is not a laboratory LH measurement. A value near 1 means the lines looked similarly dark."
                    )
                )
                Divider().padding(.vertical, 4)
                ovulationMetric(
                    title: "Readability",
                    value: "\(result.certaintyPercentage)%",
                    detail: result.certaintyPercentage >= 80 ? "Clear photo" : "Check photo quality",
                    tint: result.resultType.ovulationTint,
                    help: TerminologyInfo(
                        title: "Image readability",
                        message: "Readability reflects lighting, focus, contrast, and how clearly the lines could be compared. It is not medical certainty."
                    )
                )
            }

            VStack(spacing: 7) {
                certaintyBars(result)
                // The bar sat unlabelled directly above the stage section, so
                // it read as part of it rather than as the readability figure
                // shown above.
                Text(result.certaintyPercentage >= 80 ? "High image readability" : result.certaintyPercentage >= 58 ? "Moderate image readability" : "Low image readability")
                    .font(.app(.caption))
                    .foregroundStyle(result.resultType.ovulationTint)
            }
            .padding(.bottom, layout.isRegular ? 14 : 0)

            // A local scan only reports the raw stage classification above -
            // the positional stepper and per-line evidence breakdown read as
            // more diagnostic certainty than a pixel heuristic backs up, so
            // they're reserved for an AI-backed (or self-assessed) result.
            if showStageDetail {
                ovulationProgress(result)
                Divider()
                    .overlay(Color.lineNavy.opacity(0.08))
                ovulationEvidence(result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func ovulationMetric(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        help: TerminologyInfo
    ) -> some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                terminologyButton(help)
            }
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(Color.lineNavy.opacity(0.58))

            Text(value)
                .font(.app(size: LineType.size(29), weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())

            Text(detail)
                .font(.app(.caption2, weight: .medium))
                .foregroundStyle(Color.lineNavy.opacity(0.54))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
        .padding(.horizontal, 8)
    }

    private func ovulationProgress(_ result: LineAnalysisResult) -> some View {
        let stages: [ScanResultType] = [.low, .rising, .high, .peak]
        return VStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                Text("Ovulation-Test Line Stage")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                terminologyButton(
                    TerminologyInfo(
                        title: "Ovulation-test line stage",
                        message: "This describes how the test line looks beside the control line: low is much lighter, rising is visible but lighter, high is close, and strongest means it looks about as dark as or darker than the control. Follow the labels and timing in your test instructions."
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.13))
                    .frame(height: 2)
                    .padding(.horizontal, 20)
                HStack {
                    ForEach(stages) { stage in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(stage == result.resultType ? stage.ovulationTint : Color.black.opacity(0.25), lineWidth: LineType.scale > 1 ? 2.5 : 2)
                                    .frame(width: LineType.size(18), height: LineType.size(18))
                                Circle()
                                    .fill(stage == result.resultType ? stage.ovulationTint : Color.white)
                                    .frame(width: LineType.size(10), height: LineType.size(10))
                            }
                            Text(stage.referenceTitle)
                                .font(.app(size: LineType.size(13), weight: stage == result.resultType ? .bold : .regular))
                                .foregroundStyle(stage == result.resultType ? stage.ovulationTint : Color.lineNavy)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func ovulationInsight(_ result: LineAnalysisResult) -> some View {
        VStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Label("What To Do Now", systemImage: result.resultType.ovulationInsightIcon)
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(result.resultType.ovulationTint)
                if flow.personalisedGuidance != nil {
                    Text("PERSONALISED")
                        .font(.app(.caption2, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.linePurple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.linePurple.opacity(0.10), in: Capsule())
                }
            }

            Text(flow.personalisedGuidance ?? ovulationGuidance(for: result.resultType))
                .font(.app(.subheadline))
                .lineSpacing(3)
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Deterministic for the life of this result view (stable via
    /// ovulationCopySeed), but different across results, so the same tier
    /// doesn't always read with identical wording. `offset` decorrelates
    /// multiple pickers sharing one seed.
    private func pick(_ variants: [String], offset: Int = 0) -> String {
        guard !variants.isEmpty else { return "" }
        let index = ((ovulationCopySeed + offset) % variants.count + variants.count) % variants.count
        return variants[index]
    }

    private func ovulationGuidance(for result: ScanResultType) -> String {
        switch result {
        case .peak: pick([
            "This looks like an LH surge. Ovulation often follows within about 1–2 days. If you’re trying to conceive, today and tomorrow are useful days to try — sex every 1–2 days across the fertile window gives good coverage.",
            "The test line is as dark as or darker than control, a strong surge signal. Ovulation typically follows within 24–48 hours, so this is peak fertile-window timing if you’re trying to conceive.",
            "A reading this strong usually means ovulation is close. Keep testing once a day over the next day or two and expect the line to start fading as the surge passes.",
            "Strong surge detected. This is typically the best window to try to conceive — most people ovulate within a day or two of a result like this."
        ])
        case .high: pick([
            "The test line is close to the control, so the surge may be approaching. Test again later today or tomorrow at a similar time, following your test brand’s timing instructions.",
            "This is a strong reading, just short of a full surge. Testing twice a day from here — morning and evening — can help you catch the moment it crosses over.",
            "You’re likely close to your surge. If you’re trying to conceive, it’s worth starting to be intimate now in case the surge arrives before your next test.",
            "The line is nearly as dark as control, a good sign a surge is coming soon. Keep testing at a consistent time each day so you don’t miss the peak."
        ])
        case .rising: pick([
            "The line is becoming more visible but is not yet as dark as the control. Continue testing consistently; adding cervical-mucus observations can provide useful context.",
            "LH is starting to climb. This isn’t a surge yet, but testing daily, or twice daily, from here helps you catch the peak when it arrives.",
            "A rising line usually means your fertile window is getting closer. Keep to a consistent testing time each day so the trend stays easy to read.",
            "The test line is gaining strength. No action needed yet beyond continuing to test — at this pace, a surge is often a few days out."
        ])
        case .low: pick([
            "No surge is visible in this photo. Continue testing on the calendar’s suggested days. A single low result does not mean you will not ovulate this cycle.",
            "This is a typical baseline reading. LH usually stays low until shortly before ovulation, so keep testing as you move toward your fertile window.",
            "Nothing unusual here — most days in a cycle read low. Check back on the suggested testing days as your predicted fertile window approaches.",
            "A low reading like this is expected outside the fertile window. No change needed; just keep testing on schedule."
        ])
        case .invalid: pick([
            "The control line is not readable, so this test cannot be interpreted. Repeat with a new test and follow that brand’s timing instructions.",
            "This test couldn’t confirm a control line, which usually points to timing, moisture, or the strip itself rather than your hormone levels. Retest with a fresh test."
        ])
        case .unclear: pick([
            "The lines cannot be compared confidently. Retake the photo in even light or repeat with a new test.",
            "This photo made the lines hard to compare clearly. Try again with brighter, even lighting and the strip flat in frame.",
            "There isn’t enough contrast to read this confidently. A clearer photo — even light, strip in focus — should give a clearer result."
        ], offset: 2)
        default: pick([
            "Keep testing consistently and use the trend across several results rather than relying on one image.",
            "Individual readings can vary — the clearest picture comes from comparing several results over the cycle, not just one."
        ])
        }
    }

    private func terminologyButton(_ info: TerminologyInfo) -> some View {
        Button {
            activeTerminologyInfo = info
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(info.title)
        .accessibilityHint("Shows a short explanation")
    }

    private func contextHelpRow(text: String, title: String, message: String) -> some View {
        Button {
            activeTerminologyInfo = TerminologyInfo(title: title, message: message)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.linePurple.opacity(0.78))

                Text(text)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .font(.app(.caption2, weight: .medium))
            .foregroundStyle(Color.lineNavy.opacity(0.52))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text) Learn about \(title).")
        .accessibilityHint("Shows a short explanation")
    }

    private func ovulationCycleStats(_ result: LineAnalysisResult) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .center, spacing: 6) {
                Text("Cycle Day")
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.75))
                Text(fertilityWindow.map { "\($0.cycleDay)" } ?? "--")
                    .font(.app(.title2, weight: .medium))
                    .foregroundStyle(Color.lineNavy)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Divider()
            VStack(alignment: .center, spacing: 6) {
                Text("Predicted Ovulation")
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.75))
                Text(predictedOvulationText(for: result.resultType))
                    .font(.app(.headline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var fertilityWindow: FertilityWindow? {
        CycleTrackingService.window(records: cycleRecords, settings: appState.settings)
    }

    private func predictedOvulationText(for result: ScanResultType) -> String {
        if result == .peak { return "Likely in 1–2 days" }
        guard let window = fertilityWindow else { return "Set cycle" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date.now), to: Calendar.current.startOfDay(for: window.predictedOvulationDate)).day ?? 0
        if abs(days) <= 1 { return "~24-36 hours" }
        if days > 1 { return "~\(days)-\(days + 1) days" }
        return "Passed"
    }

    private func readSummary(_ result: LineAnalysisResult) -> some View {
        VStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: result.resultType.meaningIcon)
                    .font(.system(size: LineType.size(22), weight: .medium))
                    .foregroundStyle(result.resultType.tint)
                Text("What This Means")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                if flow.personalisedGuidance != nil {
                    Text("PERSONALISED")
                        .font(.app(.caption2, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color.linePurple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.linePurple.opacity(0.10), in: Capsule())
                }
            }
            if flow.personalisedGuidance != nil {
                Text("Luna’s read, based on this result and your saved tracking")
                    .font(.app(.caption))
                    .foregroundStyle(Color.lineNavy.opacity(0.56))
            }
            Text(flow.personalisedGuidance ?? result.explanation)
                .font(.app(.body))
                .lineSpacing(4)
                .foregroundStyle(Color.lineNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func personalisedGuidanceSection(_ result: LineAnalysisResult) -> some View {
        let tint = result.resultType.resultTint(for: flow.testType)
        if canUsePersonalisedGuidance {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your personalised next step")
                            .font(.app(.headline, weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                        Text("Based on this result and your recent tracking")
                            .font(.app(.caption))
                            .foregroundStyle(Color.lineNavy.opacity(0.58))
                    }
                    Spacer(minLength: 0)
                    Text(appState.settings?.proUnlocked == true ? "PRO" : "LUNA CHECK")
                        .font(.app(.caption2, weight: .heavy))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.10), in: Capsule())
                }

                if let personalisedGuidance {
                    Text(personalisedGuidance.reply)
                        .font(.app(.subheadline))
                        .lineSpacing(3)
                        .foregroundStyle(Color.lineNavy.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        askLunaAboutThisResult()
                    } label: {
                        Label("Ask Luna a follow-up", systemImage: "bubble.left.and.bubble.right")
                            .font(.app(.subheadline, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if isLoadingPersonalisedGuidance {
                    HStack(spacing: 10) {
                        ProgressView().tint(tint)
                        Text("Preparing your next step…")
                            .font(.app(.subheadline))
                            .foregroundStyle(Color.lineNavy.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                } else {
                    Text("Your result is saved. Ask Luna if you would like help deciding what to do next.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.72))
                    Button("Ask Luna about this result") { askLunaAboutThisResult() }
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(tint)
                        .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.18)))
        } else {
            Button {
                appState.paywallSource = "result_personalised_guidance"
                appState.showPremium = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your personalised next step")
                            .font(.app(.subheadline, weight: .bold))
                            .foregroundStyle(Color.lineNavy)
                        Text("See how this result fits your recent checks and cycle signals.")
                            .font(.app(.caption))
                            .foregroundStyle(Color.lineNavy.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "lock.fill")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(tint)
                }
                .padding(13)
                .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func loadPersonalisedGuidanceIfNeeded() async {
        guard personalisedGuidance == nil,
              !isLoadingPersonalisedGuidance,
              canUsePersonalisedGuidance,
              let settings = appState.settings,
              let result = flow.analysisResult,
              !isSelfAssessedResult
        else { return }

        isLoadingPersonalisedGuidance = true
        defer { isLoadingPersonalisedGuidance = false }

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
        let prior = scans
            .filter { $0.testType == flow.testType && $0.id != savedScan?.id }
            .prefix(3)
            .map { AssistantContextBuilder.recentScan($0, includeFreeText: false) }

        do {
            personalisedGuidance = try await AssistantService().reply(
                message: "Write a concise personalised next-step readout for the current result.",
                recentScans: [current] + prior,
                reminders: [],
                userContext: AssistantContextBuilder.userContext(
                    settings: settings,
                    cycles: cycleRecords,
                    dailyLogs: Array(dailyLogs.prefix(7)),
                    periodEvents: periodEvents,
                    maximumCycleSummaries: 2,
                    maximumDailySummaries: 7,
                    allDailyLogs: dailyLogs,
                    healthMetrics: healthMetrics,
                    scans: Array(scans),
                    signalSurface: .ovulationResult
                ),
                mode: "resultNarrative"
            )
        } catch {
            // The local result explanation remains the user-visible fallback.
            #if DEBUG
            print("Personalised result guidance failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func metricPill(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(.caption2, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.app(.subheadline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tcRatioCard(_ result: LineAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Test and control line guide").font(.app(.subheadline, weight: .semibold))
                Spacer()
                Text(result.testControlRatio, format: .number.precision(.fractionLength(2))).font(.app(.headline)).foregroundStyle(Color.linePurple)
            }
            TipView(tcTip)
            HStack {
                ForEach([ScanResultType.low, .rising, .high, .peak]) { item in
                    VStack {
                        Circle().fill(item.tint).frame(width: 8, height: 8)
                        Text(item.title).font(.app(.caption2))
                    }.frame(maxWidth: .infinity)
                }
            }
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func ovulationActionCard(_ result: LineAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ovulationActionTitle(for: result.resultType), systemImage: "calendar.badge.clock")
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
            Text(ovulationActionCopy(for: result.resultType))
                .font(.app(.subheadline))
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.linePurple.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.linePurple.opacity(0.14)))
    }

    private func ovulationActionTitle(for result: ScanResultType) -> String {
        switch result {
        case .low: "Test line is still light"
        case .rising: "Test line is getting stronger"
        case .high: "Test line is close to the control"
        case .peak: "Strongest result"
        case .unclear: "Result is not clear"
        case .invalid: "Test may be invalid"
        default: "Keep tracking"
        }
    }

    private func ovulationActionCopy(for result: ScanResultType) -> String {
        switch result {
        case .low: "The test line looks lighter than the control line. Keep testing on the days suggested by your calendar and follow your test instructions."
        case .rising: "The test line is visible but still lighter than the control. Testing again later today or tomorrow may help you catch your strongest result."
        case .high: "The test line looks close to the control line. Keep testing consistently until the lines match or the test line becomes darker."
        case .peak: "The test line looks similar to or darker than the control line. This is your strongest saved result so far; follow your test instructions for what to do next."
        case .unclear: "The test and control lines can’t be compared clearly. Repeat the test with a new photo in even light."
        case .invalid: "The control line was not clear. Retake or repeat the test using the test instructions."
        default: "Keep comparing readings at similar times of day for a clearer trend."
        }
    }

    private func finishResultFlow() {
        persistResult(showToast: false, dismissAfterSave: false)
        queuePostScanPromptIfNeeded()
        appState.selectedTab = .home
        appState.activeFlow = nil
    }

    private func askLunaAboutThisResult() {
        persistResult(showToast: false, dismissAfterSave: false)
        appState.pendingLunaPrompt = lunaPromptText
        appState.selectedTab = .assistant
        appState.activeFlow = nil
    }

    private var lunaPromptText: String {
        let dateText = flow.effectiveTestDate.formatted(date: .abbreviated, time: .omitted)
        guard let result = flow.analysisResult else {
            return "Can you help me understand my ovulation test from \(dateText)?"
        }
        return "About my ovulation test from \(dateText): the result was \"\(result.resultType.referenceTitle)\". Can you help me understand what this means?"
    }

    private func queuePostScanPromptIfNeeded() {
        guard let settings = appState.settings, let savedScan else { return }
        let currentIsInQuery = scans.contains { $0.id == savedScan.id }
        let completedScanCount = scans.count + (currentIsInQuery ? 0 : 1)

        // Skipped setup to scan straight away: after that first result is the
        // moment predictions become interesting, so offer them once.
        if settings.skippedOnboardingSetupValue == true,
           settings.hasSeenSetupPromptValue != true,
           settings.lastPeriodStartDate == nil,
           !cycleRecords.contains(where: { !$0.notes.contains("[LineCheck Screenshot Sample]") }) {
            settings.hasSeenSetupPromptValue = true
            try? modelContext.save()
            appState.postScanPrompt = .setupCycle
            return
        }

        if completedScanCount >= 2, !settings.hasSeenRatingPrompt {
            settings.hasSeenRatingPrompt = true
            try? modelContext.save()
            appState.postScanPrompt = .rating
            return
        }

        guard completedScanCount >= 4,
              !settings.hasSeenPostUseNotificationPrompt,
              !settings.notificationsEnabled else { return }

        Task { @MainActor in
            let status = await NotificationService().authorizationStatus()
            guard status == .notDetermined else { return }
            settings.hasSeenPostUseNotificationPrompt = true
            try? modelContext.save()
            appState.postScanPrompt = .notifications
        }
    }

    @MainActor
    private func autoSaveResultIfNeeded() async {
        guard !didAttemptAutoSave else { return }
        didAttemptAutoSave = true
        persistResult(showToast: false, dismissAfterSave: false)
    }

    private func persistResult(showToast: Bool, dismissAfterSave: Bool) {
        guard let original = flow.image, let analysis = flow.analysisResult else { return }
        do {
            let scan: Scan
            let wasAlreadySaved = savedScan != nil || flow.persistedScan != nil
            let trimmedBrand = flow.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = savedScan ?? flow.persistedScan {
                existing.createdAt = flow.effectiveTestDate
                existing.testTypeRaw = flow.testType.rawValue
                existing.testFormatRaw = flow.format.rawValue
                existing.resultTypeRaw = analysis.resultType.rawValue
                existing.confidencePercentage = analysis.confidencePercentage
                existing.certaintyPercentage = analysis.certaintyPercentage
                existing.controlLineDetected = analysis.controlLineDetected
                existing.testLineDetected = analysis.testLineDetected
                existing.testControlRatio = analysis.testControlRatio
                existing.lineStrength = analysis.lineStrength
                existing.analysisModeRaw = flow.mode.rawValue
                existing.notes = notes
                existing.autoEnhancementSummary = flow.autoSummary
                existing.brandName = trimmedBrand.isEmpty ? nil : trimmedBrand
                existing.imageQualityStatusRaw = analysis.quality.status.rawValue
                if flow.mode == .manualEnhance {
                    existing.resultSource = flow.wasLocallyScanned ? .localScan : .userOverride
                    existing.resultWasManuallyAdjusted = !flow.wasLocallyScanned
                } else {
                    existing.resultSource = .aiOriginal
                    existing.resultWasManuallyAdjusted = false
                    existing.clearAdjustedImages()
                }
                scan = existing
            } else {
                let storage = ImageStorageService.shared
                let originalImage = try storage.saveSyncable(original)
                let adjusted = flow.adjustedImage.flatMap { try? storage.saveSyncable($0, prefix: flow.mode == .aiQuickCheck ? "ai-adjusted" : "enhanced") }
                let thumb = try storage.saveSyncableThumbnail(flow.displayImage ?? original)
                let imageName = originalImage.filename
                let adjustedName = adjusted?.filename
                scan = Scan(createdAt: flow.effectiveTestDate, testType: flow.testType, testFormat: flow.format, resultType: analysis.resultType, confidencePercentage: analysis.confidencePercentage, certaintyPercentage: analysis.certaintyPercentage, controlLineDetected: analysis.controlLineDetected, testLineDetected: analysis.testLineDetected, testControlRatio: analysis.testControlRatio, lineStrength: analysis.lineStrength, analysisMode: flow.mode, imageFilename: imageName, enhancedImageFilename: flow.mode == .manualEnhance ? adjustedName : nil, autoEnhancedImageFilename: flow.mode == .aiQuickCheck ? adjustedName : nil, thumbnailFilename: thumb.filename, notes: notes, brandName: trimmedBrand.isEmpty ? nil : trimmedBrand, imageQualityStatus: analysis.quality.status, autoEnhancementSummary: flow.autoSummary)
                scan.imageData = originalImage.data
                scan.thumbnailData = thumb.data
                if flow.mode == .aiQuickCheck {
                    scan.autoEnhancedImageData = adjusted?.data
                } else {
                    scan.enhancedImageData = adjusted?.data
                }
                if flow.mode == .manualEnhance {
                    scan.resultSource = flow.wasLocallyScanned ? .localScan : .userOverride
                    scan.resultWasManuallyAdjusted = !flow.wasLocallyScanned
                }
                CycleTrackingService.attach(scan, to: cycleRecords)
                if CycleTrackingService.applyPeakResult(from: scan, records: cycleRecords) != nil {
                    appState.toast = "Peak saved — ovulation estimate updated"
                }
                modelContext.insert(scan)
                AppAnalytics.log("linecheck_scan_completed", [
                    "test_type": flow.testType.rawValue,
                    "mode": flow.mode.rawValue,
                    "result_type": analysis.resultType.rawValue,
                    "image_quality": analysis.quality.status.rawValue
                ])
                if analysis.quality.status != .good {
                    AppAnalytics.log("linecheck_image_quality_flagged", [
                        "test_type": flow.testType.rawValue,
                        "quality_status": analysis.quality.status.rawValue
                    ])
                }
                completeMatchingReminder(for: scan)
                savedScan = scan
            }
            flow.persistedScan = scan
            savedScan = scan
            try modelContext.save()
            if scan.testType == .ovulation,
               let cycle = cycleRecords.first(where: { $0.id == scan.cycleRecordID }) {
                resyncAutoRemindersIfNeeded(for: cycle)
            }
            if showToast { appState.toast = wasAlreadySaved ? "Result updated" : "Result saved" }
            if dismissAfterSave {
                appState.activeFlow = nil
            }
        } catch {
            if showToast { appState.toast = "Image save failed" }
        }
    }

    private func completeMatchingReminder(for scan: Scan) {
        let expectedTypes: Set<ReminderType> = [.ovulationTest, .ovulationFollowUp]
        let lowerBound = Calendar.current.date(byAdding: .day, value: -3, to: scan.createdAt) ?? .distantPast
        let upperBound = Calendar.current.date(byAdding: .hour, value: 12, to: scan.createdAt) ?? scan.createdAt
        guard let reminder = reminders.filter({
            !$0.isCompleted && expectedTypes.contains($0.reminderType) && $0.scheduledDate >= lowerBound && $0.scheduledDate <= upperBound
        }).min(by: {
            abs($0.scheduledDate.timeIntervalSince(scan.createdAt)) < abs($1.scheduledDate.timeIntervalSince(scan.createdAt))
        }) else { return }
        reminder.isCompleted = true
        reminder.completedAt = scan.createdAt
        reminder.linkedScanId = scan.id
        NotificationService().cancel(id: reminder.id)
    }

    /// A peak OPK result moves the predicted ovulation/period dates. If the
    /// user has opted into automatic reminders, re-sync them now rather than
    /// leaving them pinned to the cycle's original, less-accurate baseline.
    private func resyncAutoRemindersIfNeeded(for cycle: CycleRecord) {
        guard let settings = appState.settings, settings.autoRemindersEnabled else { return }
        guard let window = CycleTrackingService.window(records: cycleRecords, settings: settings) else { return }
        Task {
            await ReminderAutomationService.syncPredictedReminders(
                cycle: cycle,
                window: window,
                settings: settings,
                existingReminders: reminders,
                context: modelContext
            )
        }
    }

    private func showInterstitialIfNeeded() {
        guard !didAttemptInterstitial,
              appState.settings?.proUnlocked == false,
              flow.suppressCompletionInterstitial == false else { return }

        if flow.mode == .manualEnhance {
            let savedLocalScanCount = scans.lazy
                .filter { $0.analysisMode == .manualEnhance }
                .count
            let currentScanWasSaved = savedScan?.analysisMode == .manualEnhance
            let priorLocalScanCount = max(0, savedLocalScanCount - (currentScanWasSaved ? 1 : 0))
            guard priorLocalScanCount > 0 else { return }
        }

        didAttemptInterstitial = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            // If the user reached the "Not the right result?" flow (any of
            // its overlays, or the premium paywall it can open) inside this
            // same 450ms window, showing an interstitial now would stack an
            // ad directly on top of - or immediately after dismissing - a
            // paywall. Skip it rather than retry later; this is a rare
            // timing edge case, not worth the added complexity of
            // rescheduling.
            guard !appState.showPremium,
                  !showDisputeChoice,
                  !showLookAgainOpinionPicker,
                  !showOverrideSheet,
                  !isRunningLookAgain
            else { return }
            appState.interstitialAds.showIfReady()
        }
    }

    private func reminderTitle() -> String {
        return switch flow.analysisResult?.resultType {
        case .rising, .high: "Repeat ovulation test"
        case .peak: "Check after strongest ovulation result"
        default: "Ovulation test"
        }
    }

    private func reminderDate() -> Date {
        guard flow.testType == .ovulation else {
            if flow.analysisResult?.resultType == .invalid {
                return Calendar.current.date(byAdding: .hour, value: 24, to: .now) ?? .now
            }
            return Calendar.current.date(byAdding: .hour, value: 48, to: .now) ?? .now
        }
        switch flow.analysisResult?.resultType {
        case .rising, .high:
            return Calendar.current.date(byAdding: .hour, value: 12, to: .now) ?? .now
        case .peak:
            return Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        default:
            return Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        }
    }

    private func export(result: LineAnalysisResult) {
        let tempScan = Scan(testType: flow.testType, testFormat: flow.format, resultType: result.resultType, certaintyPercentage: result.certaintyPercentage, testControlRatio: result.testControlRatio, analysisMode: flow.mode, imageFilename: "")
        if let url = PDFExportHelper.makeReport(scan: tempScan, image: flow.displayImage) {
            shareItems = [url]
            showShare = true
            appState.toast = "Export complete"
        }
    }

    private func saveDisplayedImage() {
        guard let image = flow.displayImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        appState.toast = "Saved to Photos"
    }

    @MainActor
    private func performLookAgain(userOpinion: String) async {
        guard !isRunningLookAgain,
              let settings = appState.settings, settings.proUnlocked,
              let image = flow.image
        else { return }
        isRunningLookAgain = true
        defer { isRunningLookAgain = false }

        do {
            let response = try await AIAnalysisService().analyse(
                image: image,
                testType: flow.testType,
                isRecheck: true,
                userStatedOpinion: userOpinion
            )
            guard AICheckQuotaService().consumeAI(settings) else { return }
            let reconciled = response.lineAnalysisResult
            applyRecheckResult(reconciled, userOpinion: userOpinion)
            showLookAgainOpinionPicker = false
            appState.toast = "Luna took another look"
        } catch {
            appState.toast = error.localizedDescription
        }
    }

    @MainActor
    private func applyRecheckResult(_ updated: LineAnalysisResult, userOpinion: String) {
        guard let savedScan else { return }
        if savedScan.preRecheckResultTypeRaw == nil {
            savedScan.preRecheckResultTypeRaw = savedScan.resultTypeRaw
            savedScan.preRecheckCertaintyPercentage = savedScan.certaintyPercentage
        }
        let previousResult = savedScan.resultTypeRaw
        savedScan.lookAgainUserOpinionRaw = userOpinion
        savedScan.hasUsedLookAgain = true
        savedScan.resultSource = .aiRecheck
        applyUpdatedResult(updated, to: savedScan)
        AppAnalytics.log("linecheck_look_again_used", [
            "test_type": savedScan.testType.rawValue,
            "previous_result": previousResult,
            "new_result": updated.resultType.rawValue,
            "result_changed": previousResult != updated.resultType.rawValue
        ])
    }

    @MainActor
    private func applyManualOverride(_ resultType: ScanResultType, testControlRatio: Double? = nil) {
        guard let savedScan else { return }
        let quality = flow.analysisResult?.quality ?? ImageQualityResult(status: .good, brightness: 0, blurScore: 0, overexposure: 0)
        let updated = LineAnalysisResult.manual(resultType: resultType, quality: quality, testControlRatioOverride: testControlRatio)
        let previousResult = savedScan.resultTypeRaw
        savedScan.resultWasManuallyAdjusted = true
        savedScan.resultSource = .userOverride
        flow.wasLocallyScanned = false
        applyUpdatedResult(updated, to: savedScan)
        AppAnalytics.log("linecheck_result_manually_corrected", [
            "test_type": savedScan.testType.rawValue,
            "previous_result": previousResult,
            "new_result": resultType.rawValue,
            "source": "result_screen"
        ])
        appState.toast = "Result updated"
    }

    /// Shared by Look Again and the manual override: writes the new result
    /// to both the live display (`flow.analysisResult`) and the persisted
    /// scan, then re-runs the same cycle-tracking reconciliation the initial
    /// save already does, since a changed result can change a peak/positive
    /// date estimate.
    @MainActor
    private func applyUpdatedResult(_ updated: LineAnalysisResult, to scan: Scan) {
        flow.analysisResult = updated
        scan.resultTypeRaw = updated.resultType.rawValue
        scan.confidencePercentage = updated.confidencePercentage
        scan.certaintyPercentage = updated.certaintyPercentage
        scan.controlLineDetected = updated.controlLineDetected
        scan.testLineDetected = updated.testLineDetected
        scan.testControlRatio = updated.testControlRatio
        scan.lineStrength = updated.lineStrength

        CycleTrackingService.reconcileOvulationEstimates(records: cycleRecords, scans: scans)
        _ = CycleTrackingService.applyPeakResult(from: scan, records: cycleRecords)
        try? modelContext.save()
        if scan.testType == .ovulation,
           let cycle = cycleRecords.first(where: { $0.id == scan.cycleRecordID }) {
            resyncAutoRemindersIfNeeded(for: cycle)
        }
    }
}

/// Shared card chrome for the dispute-flow overlays below, matching
/// TestAgainChoiceOverlay's exact scrim + BrandedModalCard styling so these
/// read as the same design language as the rest of the app's popups rather
/// than a generic system sheet.
private struct DisputeOverlayCard<Content: View>: View {
    var onBackgroundTap: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.lineNavy.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)

            BrandedModalCard {
                content()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
            }
            .padding(.horizontal, 28)
        }
    }
}

private struct DisputeChoiceOverlay: View {
    var offersLookAgain: Bool
    var onLookAgain: () -> Void
    var onSayItMyself: () -> Void
    var onCancel: () -> Void

    var body: some View {
        DisputeOverlayCard(onBackgroundTap: onCancel) {
            VStack(spacing: 20) {
                AppIconBrandMark(size: 72)

                VStack(spacing: 7) {
                    Text("Not the right result?")
                        .font(.app(size: LineType.size(25), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text("Choose how you'd like to fix it.")
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.64))
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    if offersLookAgain {
                        Button(action: onLookAgain) {
                            VStack(spacing: 3) {
                                Label("Ask Luna to look again", systemImage: "sparkle.magnifyingglass")
                                    .font(.app(.headline))
                                Text("A second, more careful AI read of this same photo")
                                    .font(.app(.caption))
                                    .opacity(0.82)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [.linePurple, .linePink], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onSayItMyself) {
                        VStack(spacing: 3) {
                            Label("I'll say it myself", systemImage: "pencil.circle")
                                .font(.app(.headline))
                                .foregroundStyle(Color.linePurple)
                            Text("Pick the result yourself, no AI involved")
                                .font(.app(.caption))
                                .foregroundStyle(Color.lineNavy.opacity(0.58))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(Color.linePurple.opacity(0.22), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button("Cancel", action: onCancel)
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.58))
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
            }
        }
    }
}

private struct LookAgainOpinionOverlay: View {
    let testType: TestType
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    private var options: [(value: String, title: String)] {
        [("peak", "Peak"), ("high", "High"), ("rising", "Rising"), ("low", "Low"), ("notSure", "Not sure")]
    }

    var body: some View {
        DisputeOverlayCard(onBackgroundTap: onCancel) {
            VStack(spacing: 20) {
                AppIconBrandMark(size: 72)

                VStack(spacing: 7) {
                    Text("What do you see?")
                        .font(.app(size: LineType.size(23), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text("This is one more piece of context for Luna's second look, not the final answer.")
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.64))
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(options, id: \.value) { option in
                        Button(option.title) { onSubmit(option.value) }
                            .buttonStyle(.secondaryLine)
                            .frame(maxWidth: .infinity)
                    }
                    Button("Cancel", action: onCancel)
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.58))
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
            }
        }
    }
}

private struct ResultOverrideOverlay: View {
    let testType: TestType
    var onSelect: (ScanResultType, Double?) -> Void
    var onCancel: () -> Void

    @State private var ratioOption: ScanResultType?
    @State private var ratioText = ""
    @FocusState private var isRatioFieldFocused: Bool

    private var options: [ScanResultType] {
        [.peak, .high, .rising, .low, .unclear, .invalid]
    }

    /// Only categories with a real line have a ratio worth fine-tuning -
    /// unclear/invalid have none, so they skip straight through.
    private var ratioAdjustableOptions: Set<ScanResultType> { [.peak, .high, .rising, .low] }

    var body: some View {
        DisputeOverlayCard(onBackgroundTap: onCancel) {
            if let ratioOption {
                ratioStep(for: ratioOption)
            } else {
                categoryStep
            }
        }
    }

    private var categoryStep: some View {
        VStack(spacing: 20) {
            AppIconBrandMark(size: 72)

            VStack(spacing: 7) {
                Text("What should this result be?")
                    .font(.app(size: LineType.size(23), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                Text("This replaces the saved result with your own call. The original photo is never changed.")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.64))
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button(option.title) {
                        if testType == .ovulation, ratioAdjustableOptions.contains(option) {
                            ratioText = LineAnalysisResult.defaultTestControlRatio(for: option).formatted(.number.precision(.fractionLength(2)))
                            ratioOption = option
                        } else {
                            onSelect(option, nil)
                        }
                    }
                    .buttonStyle(.secondaryLine)
                    .frame(maxWidth: .infinity)
                }
                Button("Cancel", action: onCancel)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
        }
    }

    private func ratioStep(for option: ScanResultType) -> some View {
        VStack(spacing: 20) {
            AppIconBrandMark(size: 72)

            VStack(spacing: 7) {
                Text("Fine-tune the T/C ratio")
                    .font(.app(size: LineType.size(23), weight: .heavy))
                    .foregroundStyle(Color.lineNavy)
                Text("\(option.title) typically sits around \(LineAnalysisResult.defaultTestControlRatio(for: option).formatted(.number.precision(.fractionLength(2)))). Adjust it if you measured something more specific, or leave it as is.")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.64))
            }
            .multilineTextAlignment(.center)

            TextField("T/C ratio", text: $ratioText)
                .keyboardType(.decimalPad)
                .focused($isRatioFieldFocused)
                .multilineTextAlignment(.center)
                .font(.app(size: LineType.size(28), weight: .bold))
                .foregroundStyle(Color.linePurple)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.lineBackground, in: RoundedRectangle(cornerRadius: 14))
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isRatioFieldFocused = false }
                    }
                }

            VStack(spacing: 10) {
                Button("Save") {
                    onSelect(option, Double(ratioText))
                }
                .buttonStyle(.primaryLine)
                .frame(maxWidth: .infinity)

                Button("Back") { ratioOption = nil }
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
        }
    }
}

private struct ZoomableImageView: View {
    let image: UIImage
    var onClose: () -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: LineType.size(17), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }
}

private struct TestAgainChoiceOverlay: View {
    var isUnlocking: Bool
    var lunaButtonTitle: String
    var onLuna: () -> Void
    var onLocalScan: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.lineNavy.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isUnlocking else { return }
                    onCancel()
                }

            VStack(spacing: 20) {
                AppIconBrandMark(size: 72)

                VStack(spacing: 7) {
                    Text("Check another test")
                        .font(.app(size: LineType.size(25), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                    Text("Choose how you want to check it.")
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.64))
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button(action: onLuna) {
                        HStack(spacing: 10) {
                            if isUnlocking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "play.rectangle.fill")
                            }
                            Text(isUnlocking ? "Opening ad…" : lunaButtonTitle)
                        }
                        .font(.app(.headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.linePurple, .linePink],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnlocking)

                    Button(action: onLocalScan) {
                        Label("Manual Check", systemImage: "hand.tap")
                            .font(.app(.headline))
                            .foregroundStyle(Color.linePurple)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                Color.white.opacity(0.68),
                                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(Color.linePurple.opacity(0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnlocking)

                    Button("Cancel", action: onCancel)
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.58))
                        .buttonStyle(.plain)
                        .disabled(isUnlocking)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.linePurpleSoft,
                            Color.linePinkSoft,
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.linePink.opacity(0.11))
                        .frame(width: 180, height: 180)
                        .offset(x: 150, y: -130)
                    Circle()
                        .fill(Color.linePurple.opacity(0.09))
                        .frame(width: 150, height: 150)
                        .offset(x: -155, y: 150)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.linePurple.opacity(0.20), radius: 28, y: 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: 430)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(10)
    }
}

private struct ResultComparePair: Identifiable {
    let id = UUID()
    let previous: Scan
    let current: Scan
}

private struct TerminologyInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ResultSectionFadeModifier: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
    }
}

private extension View {
    func resultSectionFade(index: Int, revealedCount: Int) -> some View {
        modifier(ResultSectionFadeModifier(isVisible: revealedCount > index))
    }
}

private extension ScanResultType {
    func resultTint(for testType: TestType) -> Color {
        testType == .ovulation ? ovulationTint : tint
    }

    var ovulationTint: Color {
        switch self {
        case .low: Color(red: 0.82, green: 0.52, blue: 0.02)
        case .rising: Color(red: 0.24, green: 0.52, blue: 0.22)
        case .high: Color(red: 0.05, green: 0.34, blue: 0.67)
        case .peak: Color.linePurple
        case .invalid: Color(red: 1.0, green: 0.42, blue: 0.0)
        default: tint
        }
    }

    var referenceTitle: String {
        switch self {
        case .invalid: "Invalid"
        case .low: "Low"
        case .rising: "Rising"
        case .high: "High"
        case .peak: "Peak"
        case .unclear: "Not Clear"
        case .manualSaved: "Manual"
        }
    }

    func referenceSubtitle(testType: TestType) -> String {
        switch self {
        case .invalid: "Result can’t be read"
        case .low: "LH appears low"
        case .rising: "LH may be rising"
        case .high: "LH appears high"
        case .peak: "LH surge likely"
        case .unclear: "Lines can’t be compared"
        case .manualSaved: "Ovulation check saved"
        }
    }

    var meaningIcon: String {
        switch self {
        case .low: "info.circle"
        case .invalid: "exclamationmark.circle"
        case .rising, .high, .peak: "waveform.path.ecg"
        case .unclear: "questionmark.circle"
        case .manualSaved: "square.and.pencil"
        }
    }

    var testLineLabel: String {
        switch self {
        case .rising, .high, .peak:
            "Line detected"
        case .low:
            "No strong line"
        case .invalid:
            "Control missing"
        case .unclear:
            "Can’t confirm"
        case .manualSaved:
            "Saved"
        }
    }

    var ovulationReferenceTitle: String {
        switch self {
        case .low: "Test line is light"
        case .rising: "Test line is getting stronger"
        case .high: "Test line is close"
        case .peak: "Strongest result"
        case .invalid: "Invalid"
        case .unclear: "Not Clear"
        default: referenceTitle
        }
    }

    var ovulationStatusIcon: String {
        switch self {
        case .low: "circle.fill"
        case .rising: "arrow.up"
        case .high: "arrow.up"
        case .peak: "star.circle.fill"
        case .invalid: "exclamationmark"
        default: "questionmark"
        }
    }

    var ovulationRatioDescription: String {
        switch self {
        case .low: "Test line much lighter than control"
        case .rising: "Test line visible but lighter than control"
        case .high: "Test line nearly as dark as control"
        case .peak: "Test line as dark as or darker than control"
        case .invalid: "Control line not readable"
        case .unclear: "Lines can’t be compared clearly"
        default: "Ovulation test result"
        }
    }

    var ovulationInsightIcon: String {
        switch self {
        case .low: "sun.max"
        case .rising: "chart.line.uptrend.xyaxis"
        case .high: "heart"
        case .peak: "crown"
        case .invalid: "exclamationmark.triangle"
        default: "info.circle"
        }
    }

    var ovulationInsightTitle: String {
        switch self {
        case .low: "No strong line yet."
        case .rising: "The test line is getting stronger."
        case .high: "The test line is close to the control."
        case .peak: "This is your strongest result."
        case .invalid: "This test may be invalid."
        case .unclear: "Repeat the test for a clearer result."
        default: "Ovulation result"
        }
    }

    var ovulationInsightCopy: String {
        switch self {
        case .low:
            "The test line is still much lighter than the control. Continue testing on the days suggested by your calendar."
        case .rising:
            "The test line looks stronger. Test again later today or tomorrow."
        case .high:
            "The test line is close to the control. Continue testing to identify your strongest result."
        case .peak:
            "The test line looks as dark as, or darker than, the control. Follow your test instructions for how to use this result."
        case .invalid:
            "The control line is missing, so use a new test and follow its instructions."
        case .unclear:
            "The lines cannot be compared clearly. Retake the photo in even light."
        default:
            "Follow your test instructions and continue tracking your results."
        }
    }
}
