import SwiftData
import SwiftUI

struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lineLayout) private var layout
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Scan.createdAt, order: .reverse) private var scans: [Scan]
    @Query(sort: \ScanComparison.createdAt, order: .reverse) private var comparisons: [ScanComparison]
    @Query private var settingsQuery: [UserSettings]
    @Query(sort: \CycleRecord.startDate, order: .reverse) private var cycleRecords: [CycleRecord]
    @Query(sort: \DailyFertilityLog.date, order: .reverse) private var dailyLogs: [DailyFertilityLog]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Query(sort: \DailyHealthMetrics.date) private var healthMetrics: [DailyHealthMetrics]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @State private var first: Scan?
    @State private var second: Scan?
    @State private var sharePayload: ComparisonSharePayload?
    @State private var aiSummary: String?
    @State private var aiError: String?
    @State private var isLoadingAI = false
    @State private var showPremium = false

    init(initialFirst: Scan? = nil, initialSecond: Scan? = nil) {
        _first = State(initialValue: initialFirst)
        _second = State(initialValue: initialSecond)
    }

    private var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }
    private var comparableScans: [Scan] {
        scans.filter { candidate in
            guard let first else { return true }
            return isCompatible(first, candidate)
        }
    }
    private var orderedPair: (earlier: Scan, later: Scan)? {
        guard let first, let second, first.id != second.id, isCompatible(first, second) else { return nil }
        return first.createdAt <= second.createdAt ? (first, second) : (second, first)
    }

    private func isCompatible(_ first: Scan, _ second: Scan) -> Bool {
        guard first.testType == second.testType else { return false }
        if first.testType == .ovulation,
           let firstCycle = first.cycleRecordID,
           let secondCycle = second.cycleRecordID,
           firstCycle != secondCycle {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    compareHeader

                    if orderedPair == nil {
                        pickerCard
                    }

                    if let pair = orderedPair {
                        comparison(pair.earlier, pair.later)
                    } else {
                        EmptyStateView(
                            title: "Compare scans",
                            message: "Choose two checks of the same type and—when comparing ovulation tests—from the same cycle.",
                            buttonTitle: nil,
                            action: nil
                        )
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 16)
                .lineBottomInset()
                .lineContentColumn()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background { LineCheckBrandBackdrop() }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: [payload.text], onDismiss: { sharePayload = nil })
            }
            .fullScreenCover(isPresented: $showPremium) {
                PremiumView()
            }
        }
        .tint(Color.lineBlue)
    }

    private var compareHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compare scans")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)
                Text("See whether saved tests look stronger, lighter, or similar over time.")
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: LineType.size(14), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close compare")
        }
    }

    private var pickerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose two saved checks")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)

                Picker("First scan", selection: $first) {
                    Text("Select first").tag(Optional<Scan>.none)
                    ForEach(scans) { scan in
                        Text(pickerTitle(for: scan)).tag(Optional(scan))
                    }
                }
                .tint(Color.lineBlue)

                Picker("Second scan", selection: $second) {
                    Text("Select second").tag(Optional<Scan>.none)
                    ForEach(comparableScans) { scan in
                        Text(pickerTitle(for: scan)).tag(Optional(scan))
                    }
                }
                .tint(Color.lineBlue)
            }
        }
    }

    private func comparison(_ earlier: Scan, _ later: Scan) -> some View {
        let summary = localSummary(earlier, later)

        return VStack(alignment: .leading, spacing: 16) {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 12) {
                        compareImage(earlier, title: "Earlier")
                        Image(systemName: "arrow.down")
                            .font(.system(size: LineType.size(14), weight: .bold))
                            .foregroundStyle(Color.lineNavy.opacity(0.45))
                        compareImage(later, title: "Later")
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: summary.icon)
                            .font(.system(size: LineType.size(22), weight: .bold))
                            .foregroundStyle(summary.tint)
                            .frame(width: 40, height: 40)
                            .background(summary.tint.opacity(0.10), in: Circle())

                        VStack(alignment: .leading, spacing: 5) {
                            Text(summary.title)
                                .font(.lineHeadline())
                                .foregroundStyle(summary.tint)
                            Text(summary.detail)
                                .font(.lineSubheadline())
                                .foregroundStyle(Color.lineNavy.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            metricCard(earlier, later, summary: summary)
            aiCompareCard(earlier, later)

            HStack(spacing: 12) {
                Button("Share Comparison") {
                    share(earlier, later, summary: summary)
                }
                .buttonStyle(.secondaryLine)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.primaryLine)
            }

            SafetyFooter()
        }
        .task(id: comparisonID(earlier, later)) {
            await MainActor.run {
                syncSavedComparison(earlier, later)
            }
        }
    }

    private func compareImage(_ scan: Scan, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.lineCaption(.bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.56))
                    Text(DateFormatting.shortDate.string(from: scan.createdAt))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.56))
                }

                Spacer(minLength: 8)

                ResultBadge(result: scan.resultType)
            }

            ZStack {
                Color(red: 0.985, green: 0.982, blue: 0.990)
                if let image = ImageStorageService.shared.load(scan.displayImageRef) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    TestIllustration(testType: scan.testType, result: scan.resultType, compact: true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(_ earlier: Scan, _ later: Scan, summary: CompareSummary) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("How the tests compare")
                    .font(.lineHeadline())
                    .foregroundStyle(Color.lineNavy)

                compareMetricRow("Earlier result", earlier.resultType.title)
                compareMetricRow("Later result", later.resultType.title)

                DisclosureGroup {
                    VStack(spacing: 10) {
                        if earlier.testType == .ovulation {
                            compareMetricRow("Earlier test/control value", earlier.testControlRatio.formatted(.number.precision(.fractionLength(2))))
                            compareMetricRow("Later test/control value", later.testControlRatio.formatted(.number.precision(.fractionLength(2))))
                            compareMetricRow("Difference", signed(later.testControlRatio - earlier.testControlRatio))
                        } else {
                            compareMetricRow("Earlier photo line value", earlier.lineStrength.formatted(.number.precision(.fractionLength(2))))
                            compareMetricRow("Later photo line value", later.lineStrength.formatted(.number.precision(.fractionLength(2))))
                            compareMetricRow("Difference", signed(later.lineStrength - earlier.lineStrength))
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 3) {
                        Text("Show photo measurements")
                            .font(.app(.subheadline, weight: .semibold))
                        TermHelpButton(term: "Photo measurements", explanation: "These values compare how the lines look in the saved photos. They are not hormone measurements and should not be read as hCG or LH levels.")
                    }
                    .foregroundStyle(Color.lineBlue)
                }

                Text(summary.metricNote)
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compareMetricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(Color.lineNavy.opacity(0.56))
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.lineNavy)
        }
        .font(.app(.subheadline))
    }

    private func aiCompareCard(_ earlier: Scan, _ later: Scan) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    LunaAvatarView(size: 46)
                        .padding(4)
                        .background(Color.linePurpleSoft.opacity(0.75), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Compare")
                            .font(.lineHeadline())
                            .foregroundStyle(Color.lineNavy)
                        Text("Extra guidance based on these two saved photos, their dates, and how the lines changed.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let aiSummary {
                    aiSummaryCard(aiSummary)
                }

                if let aiError {
                    Text(aiError)
                        .font(.lineCaption(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                aiCompareButton(earlier, later)
            }
        }
    }

    private func aiSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Luna’s comparison")
                .font(.lineCaption(.bold))
                .foregroundStyle(Color.lineBlue)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(AISummaryFormatting.sections(from: summary)) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        if let title = section.title {
                            Text(title)
                                .font(.lineCaption(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(Color.lineBlue)
                        }

                        AISummaryFormatting.formattedText(section.body)
                            .font(.lineSubheadline())
                            .lineSpacing(4)
                            .foregroundStyle(Color.lineNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.linePurpleSoft.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.lineBlue.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func aiCompareButton(_ earlier: Scan, _ later: Scan) -> some View {
        if settings?.proUnlocked == true {
            Button {
                guard aiSummary == nil else { return }
                Task { await runAICompare(earlier, later) }
            } label: {
                HStack {
                    if isLoadingAI {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(aiSummary == nil ? "Ask Luna to Compare" : "Luna Compare Complete")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryLine)
            .disabled(isLoadingAI || aiSummary != nil)
            .opacity(aiSummary == nil ? 1 : 0.62)
        } else {
            Button {
                Task { await runAICompare(earlier, later) }
            } label: {
                HStack {
                    if isLoadingAI {
                        ProgressView()
                            .tint(Color.lineBlue)
                    }
                    Text("Unlock AI Compare")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryLine)
            .disabled(isLoadingAI)
        }
    }

    private func localSummary(_ earlier: Scan, _ later: Scan) -> CompareSummary {
        let delta = later.testControlRatio - earlier.testControlRatio
        if delta > 0.08 {
            return CompareSummary(
                title: "The later test line looks stronger",
                detail: "The later ovulation test line appears closer to the control line.",
                metricNote: "Photo measurements can help show the test line moving closer to the control line, but always follow your test instructions.",
                icon: "arrow.up.right",
                tint: ovulationTint(for: later.resultType)
            )
        }
        if delta < -0.08 {
            return CompareSummary(
                title: "The later test line looks lighter",
                detail: "The later ovulation test appears lighter than the earlier saved result.",
                metricNote: "Ovulation-test lines can change quickly depending on timing, hydration, and the test’s reading window.",
                icon: "arrow.down.right",
                tint: Color.lineTeal
            )
        }
        return CompareSummary(
            title: "Results look similar",
            detail: "The test line looks similar in these two saved ovulation-test photos.",
            metricNote: "Testing at similar times of day makes comparisons more useful.",
            icon: "equal",
            tint: Color.lineNavy
        )
    }

    private func runAICompare(_ earlier: Scan, _ later: Scan) async {
        guard let settings else { return }
        guard settings.proUnlocked else {
            appState.paywallSource = "luna_compare_locked"
            showPremium = true
            return
        }

        let quota = AICompareQuotaService()
        guard quota.canSend(settings) else {
            aiError = "You’ve used today’s AI compares. Try again after \(quota.resetLabel(settings))."
            return
        }

        isLoadingAI = true
        aiError = nil
        defer { isLoadingAI = false }

        do {
            let response = try await AssistantService().reply(
                message: aiPrompt(earlier, later),
                recentScans: recentTrendContext(for: earlier, and: later),
                reminders: [],
                userContext: assistantUserContext(settings, testType: earlier.testType),
                mode: "compare"
            )
            _ = quota.consume(settings)
            aiSummary = response.reply
            saveComparison(earlier, later, aiSummary: response.reply)
            appState.toast = "Comparison saved"
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func syncSavedComparison(_ earlier: Scan, _ later: Scan) {
        let record = saveComparison(earlier, later)
        aiSummary = record.aiSummary
        aiError = nil
    }

    @discardableResult
    private func saveComparison(_ earlier: Scan, _ later: Scan, aiSummary: String? = nil) -> ScanComparison {
        let summary = localSummary(earlier, later)
        let record: ScanComparison

        if let existing = existingComparison(earlier, later) {
            record = existing
            record.testTypeRaw = earlier.testType.rawValue
            record.earlierDate = earlier.createdAt
            record.laterDate = later.createdAt
            record.earlierResultRaw = earlier.resultType.rawValue
            record.laterResultRaw = later.resultType.rawValue
            record.earlierRatio = earlier.testControlRatio
            record.laterRatio = later.testControlRatio
            record.earlierLineStrength = earlier.lineStrength
            record.laterLineStrength = later.lineStrength
            record.localSummaryTitle = summary.title
            record.localSummaryDetail = summary.detail
        } else {
            record = ScanComparison(
                testType: earlier.testType,
                earlierScanID: earlier.id,
                laterScanID: later.id,
                earlierDate: earlier.createdAt,
                laterDate: later.createdAt,
                earlierResult: earlier.resultType,
                laterResult: later.resultType,
                earlierRatio: earlier.testControlRatio,
                laterRatio: later.testControlRatio,
                earlierLineStrength: earlier.lineStrength,
                laterLineStrength: later.lineStrength,
                localSummaryTitle: summary.title,
                localSummaryDetail: summary.detail
            )
            modelContext.insert(record)
            AppAnalytics.log("linecheck_comparison_saved", [
                "test_type": earlier.testType.rawValue,
                "has_ai_summary": aiSummary != nil
            ])
        }

        if let aiSummary {
            record.aiSummary = aiSummary
        }

        try? modelContext.save()
        return record
    }

    private func existingComparison(_ earlier: Scan, _ later: Scan) -> ScanComparison? {
        comparisons.first {
            $0.earlierScanID == earlier.id && $0.laterScanID == later.id
        }
    }

    private func comparisonID(_ earlier: Scan, _ later: Scan) -> String {
        "\(earlier.id.uuidString)-\(later.id.uuidString)"
    }

    private func aiPrompt(_ earlier: Scan, _ later: Scan) -> String {
        """
        Compare these saved \(earlier.testType.title.lowercased()) metrics only. Do not re-read images.
        Earlier: \(scanSummary(earlier))
        Later: \(scanSummary(later))
        recentScans has up to 6 more of this user's saved \(earlier.testType.title.lowercased()) checks for wider pattern context - use it, don't just restate the two above.
        """
    }

    /// Up to 6 of the user's other saved checks of the same test type, most recent first,
    /// so Luna can speak to the wider pattern instead of only the two points being compared.
    private func recentTrendContext(for earlier: Scan, and later: Scan) -> [AssistantRecentScanContext] {
        scans
            .filter { $0.testType == earlier.testType && $0.id != earlier.id && $0.id != later.id }
            .prefix(6)
            .map { AssistantContextBuilder.recentScan($0, includeFreeText: false) }
    }

    private func scanSummary(_ scan: Scan) -> String {
        "date \(ISO8601DateFormatter().string(from: scan.createdAt)), result \(scan.resultType.title), certainty \(scan.certaintyPercentage)%, line strength \(scan.lineStrength.formatted(.number.precision(.fractionLength(2)))), T/C \(scan.testControlRatio.formatted(.number.precision(.fractionLength(2))))"
    }

    private func assistantUserContext(_ settings: UserSettings, testType: TestType) -> AssistantUserContext {
        AssistantContextBuilder.userContext(
            settings: settings,
            cycles: cycleRecords,
            dailyLogs: [],
            periodEvents: periodEvents,
            maximumCycleSummaries: 2,
            maximumDailySummaries: 0,
            allDailyLogs: dailyLogs,
            healthMetrics: healthMetrics,
            scans: scans,
            signalSurface: .ovulationResult
        )
    }

    private func share(_ earlier: Scan, _ later: Scan, summary: CompareSummary) {
        sharePayload = ComparisonSharePayload(
            text: """
            LineCheck Comparison

            \(earlier.testType.title)
            Earlier: \(DateFormatting.shortDate.string(from: earlier.createdAt)) · \(earlier.resultType.title)
            Later: \(DateFormatting.shortDate.string(from: later.createdAt)) · \(later.resultType.title)

            \(summary.title)
            \(summary.detail)

            \(aiSummary.map { "Luna's comparison\n\n\($0)\n" } ?? "")

            \(AppConstants.safetyCopy)
            """
        )
    }

    private func pickerTitle(for scan: Scan) -> String {
        "\(DateFormatting.shortDate.string(from: scan.createdAt)) · \(scan.testType.shortTitle) · \(scan.resultType.badgeTitle)"
    }

    private func signed(_ value: Double) -> String {
        let formatted = abs(value).formatted(.number.precision(.fractionLength(2)))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return "0.00"
    }

    private func ovulationTint(for result: ScanResultType) -> Color {
        switch result {
        case .low: Color(red: 0.82, green: 0.52, blue: 0.02)
        case .rising: Color(red: 0.24, green: 0.52, blue: 0.22)
        case .high: Color(red: 0.05, green: 0.34, blue: 0.67)
        case .peak: Color.linePurple
        case .invalid: Color(red: 1.0, green: 0.42, blue: 0.0)
        default: result.tint
        }
    }
}

private struct CompareSummary {
    let title: String
    let detail: String
    let metricNote: String
    let icon: String
    let tint: Color
}


private struct ComparisonSharePayload: Identifiable {
    let id = UUID()
    let text: String
}
