import SwiftData
import SwiftUI

/// One named Progression group: its scans in chronological order, each
/// shown with the same on-device metrics already computed at scan time
/// (never re-derived here), plus an optional saved Luna trend summary.
/// Mirrors CompareView's AI-compare flow (same Pro gate, same
/// AICompareQuotaService allowance, same AssistantService.reply shape) but
/// generalized from exactly two scans to the group's full ordered sequence.
struct ProgressionGroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lineLayout) private var layout
    @Environment(AppState.self) private var appState
    @Bindable var group: ProgressionGroup
    @Query(sort: \Scan.createdAt) private var allScans: [Scan]
    @Query private var settingsQuery: [UserSettings]
    @Query(sort: \CycleRecord.startDate, order: .reverse) private var cycleRecords: [CycleRecord]
    @Query(sort: \PeriodEvent.startDate) private var periodEvents: [PeriodEvent]
    @Query(sort: \DailyFertilityLog.date, order: .reverse) private var dailyLogs: [DailyFertilityLog]
    @Query(sort: \DailyHealthMetrics.date) private var healthMetrics: [DailyHealthMetrics]
    @State private var showPicker = false
    @State private var showPremium = false
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    private var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }

    /// Resolved live against current Scan data every time, rather than a
    /// snapshot - a dangling id (its Scan later deleted from History) is
    /// simply skipped instead of leaving a broken row.
    private var groupScans: [Scan] {
        let ids = group.scanIDs
        let byID = Dictionary(uniqueKeysWithValues: allScans.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AppScreenHeader(title: group.name, subtitle: "\(groupScans.count) tests · \(group.testType.title)")

                if groupScans.isEmpty {
                    EmptyStateView(
                        title: "No scans yet",
                        message: "Tap + to add saved tests from your history.",
                        buttonTitle: "Add Tests",
                        action: { showPicker = true },
                        illustrationStyle: .homeTile(group.testType)
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(groupScans) { scan in
                            scanRow(scan)
                        }
                    }
                }

                if let aiSummary = group.aiSummary {
                    aiSummaryCard(aiSummary)
                }

                if let analysisError {
                    Text(analysisError)
                        .font(.app(.caption))
                        .foregroundStyle(.red)
                }

                analyzeButton
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 12)
            .lineBottomInset()
            .lineContentColumn()
        }
        .background { LineCheckBrandBackdrop() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showPicker = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showPicker) {
            ProgressionScanPickerSheet(group: group, allScans: allScans)
        }
        .fullScreenCover(isPresented: $showPremium) { PremiumView() }
        .tint(Color.lineBlue)
    }

    private func scanRow(_ scan: Scan) -> some View {
        AppCard {
            HStack(spacing: 10) {
                thumbnail(scan)

                VStack(alignment: .leading, spacing: 3) {
                    Text(DateFormatting.shortDate.string(from: scan.createdAt))
                        .font(.lineSubheadline(.semibold))
                        .foregroundStyle(Color.lineNavy)
                    Text(scan.resultType.title)
                        .font(.lineCaption())
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if scan.testType == .ovulation {
                        Text("Ratio \(scan.testControlRatio.formatted(.number.precision(.fractionLength(2))))")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(Color.lineNavy)
                    } else {
                        Text("Strength \(scan.lineStrength.formatted(.number.precision(.fractionLength(2))))")
                            .font(.app(.caption, weight: .semibold))
                            .foregroundStyle(Color.lineNavy)
                    }
                    Text("Readability \(scan.certaintyPercentage)%")
                        .font(.app(.caption2))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                remove(scan)
            } label: {
                Label("Remove from Progression", systemImage: "minus.circle")
            }
        }
    }

    private func thumbnail(_ scan: Scan) -> some View {
        Group {
            if let image = ImageStorageService.shared.load(scan.compactImageRef) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // A flat block of colour read as a missing element; an icon on
                // the test's own tint reads as "no photo saved".
                ZStack {
                    LinearGradient(
                        colors: [scan.testType.tint.opacity(0.16), scan.testType.tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "testtube.2")
                        .font(.system(size: LineType.size(16), weight: .semibold))
                        .foregroundStyle(scan.testType.tint.opacity(0.55))
                }
            }
        }
        // Matches the picker sheet: a saved test is a wide strip, and a square
        // crop keeps only its middle. iPad has the width to show its real shape.
        .frame(width: layout.isRegular ? 104 : 48, height: layout.isRegular ? 58 : 48)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
    }

    private func remove(_ scan: Scan) {
        group.scanIDs = group.scanIDs.filter { $0 != scan.id }
        try? modelContext.save()
    }

    @ViewBuilder
    private var analyzeButton: some View {
        let isPro = settings?.proUnlocked == true
        Button {
            guard isPro else {
                appState.paywallSource = "progression_locked"
                showPremium = true
                return
            }
            Task { await runAnalysis() }
        } label: {
            HStack {
                if isAnalyzing { ProgressView().tint(.white) }
                Text(isPro ? "Analyze Progression with AI" : "Unlock AI Progression Analysis")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primaryLine)
        .disabled(groupScans.count < 3 || isAnalyzing)
        .opacity(groupScans.count < 3 ? 0.5 : 1)
    }

    private func aiSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Luna’s progression summary")
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
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.lineBlue.opacity(0.10), lineWidth: 1))
    }

    private func runAnalysis() async {
        guard let settings else { return }
        let quota = AICompareQuotaService()
        guard quota.canSend(settings) else {
            analysisError = "You’ve used today’s AI compares. Try again after \(quota.resetLabel(settings))."
            return
        }

        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }

        let scansForAnalysis = groupScans
        do {
            let response = try await AssistantService().reply(
                message: "Analyze this progression of \(scansForAnalysis.count) saved \(group.testType.title.lowercased()) tests, in chronological order, and describe the trend.",
                recentScans: scansForAnalysis.map { AssistantContextBuilder.recentScan($0, includeFreeText: false) },
                reminders: [],
                userContext: AssistantContextBuilder.userContext(
                    settings: settings,
                    cycles: cycleRecords,
                    dailyLogs: [],
                    periodEvents: periodEvents,
                    maximumCycleSummaries: 2,
                    maximumDailySummaries: 0,
                    allDailyLogs: dailyLogs,
                    healthMetrics: healthMetrics,
                    scans: allScans,
                    signalSurface: group.testType == .ovulation ? .ovulationResult : .pregnancyResult
                ),
                mode: "progression"
            )
            _ = quota.consume(settings)
            group.aiSummary = response.reply
            group.updatedAt = .now
            try? modelContext.save()
            AppAnalytics.log("linecheck_progression_analyzed", [
                "test_type": group.testType.rawValue,
                "scan_count": scansForAnalysis.count
            ])
        } catch {
            analysisError = error.localizedDescription
        }
    }
}
