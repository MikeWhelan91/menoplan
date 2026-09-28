import SwiftData
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case ovulation = "FSH"

    var id: String { rawValue }

    var testType: TestType { .ovulation }
}

enum HistoryCycleFilter: Equatable, Identifiable {
    case all
    case unassigned
    case cycle(UUID)

    var id: String {
        switch self {
        case .all: "all"
        case .unassigned: "unassigned"
        case .cycle(let id): id.uuidString
        }
    }
}

private struct ScanTrackingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CycleRecord.startDate) private var cycles: [CycleRecord]
    @Query(sort: \Scan.createdAt) private var allScans: [Scan]
    @Query private var settings: [UserSettings]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    let scan: Scan
    @State private var date: Date
    @State private var result: ScanResultType
    @State private var brand: String
    @State private var notes: String
    @State private var cycleID: UUID?
    @State private var isExcluded: Bool

    init(scan: Scan) {
        self.scan = scan
        _date = State(initialValue: scan.createdAt)
        _result = State(initialValue: scan.resultType)
        _brand = State(initialValue: scan.brandName ?? "")
        _notes = State(initialValue: scan.notes)
        _cycleID = State(initialValue: scan.cycleRecordID)
        _isExcluded = State(initialValue: scan.excludedFromCalculations)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Test date", selection: $date, in: ...Date.now)
                Picker("Saved result", selection: $result) {
                    ForEach(validResults) { Text($0.title).tag($0) }
                }
                TextField("Brand", text: $brand)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
                Picker("Cycle", selection: $cycleID) {
                    Text("Unassigned").tag(Optional<UUID>.none)
                    ForEach(cycles.reversed()) { cycle in
                        Text("Cycle starting \(DateFormatting.shortDate.string(from: cycle.startDate))").tag(Optional(cycle.id))
                    }
                }
                Section {
                    Toggle("Exclude from patterns & predictions", isOn: $isExcluded)
                    Text("Keeps this test in your history, but leaves it out of trend lines, progression, and predicted dates. Use this if a reading was unreliable - a bad photo, an unusual test, or a result you don't trust.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("Manual corrections are marked on the saved scan. The original photo is never changed.")
                        .font(.app(.caption))
                }
                Button("Save Changes") { save() }
                    .buttonStyle(.primaryLine)
            }
            .navigationTitle("Edit Test")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Color.lineBlue)
    }

    private var validResults: [ScanResultType] {
        [.low, .borderline, .elevated, .unclear, .invalid, .manualSaved]
    }

    private func save() {
        let previousResult = scan.resultTypeRaw
        let previousExclusion = scan.excludedFromCalculations
        scan.createdAt = date
        scan.resultTypeRaw = result.rawValue
        scan.brandName = brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : brand.trimmingCharacters(in: .whitespacesAndNewlines)
        scan.notes = notes
        scan.cycleRecordID = cycleID
        scan.excludedFromCalculations = isExcluded
        scan.resultWasManuallyAdjusted = true
        if previousResult != result.rawValue {
            scan.resultSource = .userOverride
            AppAnalytics.log("linecheck_result_manually_corrected", [
                "test_type": scan.testType.rawValue,
                "previous_result": previousResult,
                "new_result": result.rawValue,
                "source": "history_edit"
            ])
        }
        if previousExclusion != isExcluded {
            AppAnalytics.log("linecheck_scan_exclusion_toggled", [
                "test_type": scan.testType.rawValue,
                "excluded": isExcluded ? "true" : "false"
            ])
        }
        try? modelContext.save()
        resyncRemindersIfNeeded()
        dismiss()
    }

    // A result edit/exclusion change can shift the reconciled ovulation
    // estimate, which moves fertile-peak/period-expected reminder timing -
    // resync so reminders don't keep firing on a now-stale date.
    private func resyncRemindersIfNeeded() {
        guard let settings = UserSettings.canonical(from: settings), settings.autoRemindersEnabled else { return }
        guard let cycle = cycles.first(where: { $0.id == (cycleID ?? scan.cycleRecordID) }) else { return }
        guard let window = CycleTrackingService.window(for: cycle.startDate, records: cycles, settings: settings) else { return }
        Task {
            await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: reminders, context: modelContext)
        }
    }
}

private struct HistoryTimelineItem: Identifiable {
    enum Kind {
        case scan(Scan)
        case comparison(ScanComparison)
    }

    let id: String
    let createdAt: Date
    let kind: Kind
}

private struct HistoryCycleGroup: Identifiable {
    let cycle: CycleRecord?
    let scans: [Scan]
    let fallbackDate: Date

    var id: String { cycle.map { "cycle-\($0.id)" } ?? "unassigned-\(fallbackDate.timeIntervalSince1970)" }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lineLayout) private var layout
    @State private var listViewportHeight: CGFloat = 0
    @Environment(AppState.self) private var appState
    @Query(sort: \Scan.createdAt) private var scans: [Scan]
    @Query(sort: \ScanComparison.createdAt) private var comparisons: [ScanComparison]
    @Query(sort: \CycleRecord.startDate) private var cycles: [CycleRecord]
    @Query private var settings: [UserSettings]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @State private var filter: HistoryFilter = .ovulation
    @State private var search = ""
    @State private var cycleFilter: HistoryCycleFilter = .all
    @State private var dateRange: ClosedRange<Date>?
    @State private var showDateRangeFilter = false
    @State private var pendingRangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var pendingRangeEnd = Date.now
    @State private var isCompareMode = false
    @State private var compareBaseScan: Scan?
    @State private var compareRoute: CompareRoute?
    @State private var selectedComparison: ScanComparison?
    @State private var showCompareHelp = false

    var filtered: [Scan] {
        scans.filter { scan in
            let byFilter = switch filter {
            case .ovulation: scan.testType == .ovulation
            }
            let bySearch = search.isEmpty || scan.resultType.title.localizedCaseInsensitiveContains(search) || scan.notes.localizedCaseInsensitiveContains(search)
            let byCycle = switch cycleFilter {
            case .all: true
            case .unassigned: cycle(for: scan) == nil
            case .cycle(let id): cycle(for: scan)?.id == id
            }
            let byDateRange = dateRange.map { $0.contains(scan.createdAt) } ?? true
            return byFilter && bySearch && byCycle && byDateRange
        }
    }

    /// Cycles that actually have at least one scan of the currently selected
    /// test type, most recent first - offering a cycle with nothing to show
    /// would just be a dead end in the picker.
    private var cyclesWithScans: [CycleRecord] {
        let typedScans = scans.filter { scan in
            switch filter {
            case .ovulation: scan.testType == .ovulation
            }
        }
        let presentIDs = Set(typedScans.compactMap { cycle(for: $0)?.id })
        return cycles.filter { presentIDs.contains($0.id) }.sorted { $0.startDate > $1.startDate }
    }

    private var hasUnassignedScans: Bool {
        scans.contains { scan in
            let matchesType = switch filter {
            case .ovulation: scan.testType == .ovulation
            }
            return matchesType && cycle(for: scan) == nil
        }
    }

    private var isFiltering: Bool { cycleFilter != .all || dateRange != nil }

    private func cycleFilterTitle(_ option: HistoryCycleFilter) -> String {
        switch option {
        case .all: return "All Cycles"
        case .unassigned: return "Unassigned"
        case .cycle(let id):
            guard let cycle = cycles.first(where: { $0.id == id }) else { return "Cycle" }
            return cycle.endDate == nil
                ? "Current cycle"
                : "Cycle · \(DateFormatting.shortDate.string(from: cycle.startDate))"
        }
    }

    private var dateRangeButtonTitle: String {
        guard let dateRange else { return "Date range" }
        return "\(DateFormatting.shortDate.string(from: dateRange.lowerBound))–\(DateFormatting.shortDate.string(from: dateRange.upperBound))"
    }

    var displayedScans: [Scan] {
        guard isCompareMode, let compareBaseScan else { return filtered }
        return filtered.filter { compatibleForComparison(compareBaseScan, $0) }
    }

    private func compatibleForComparison(_ base: Scan, _ candidate: Scan) -> Bool {
        guard candidate.id != base.id, candidate.testType == base.testType else { return false }
        if base.testType == .ovulation, let firstCycle = base.cycleRecordID, let secondCycle = candidate.cycleRecordID, firstCycle != secondCycle { return false }
        return true
    }

    var filteredComparisons: [ScanComparison] {
        guard !isCompareMode else { return [] }
        return comparisons.filter { comparison in
            let byFilter = switch filter {
            case .ovulation: comparison.testType == .ovulation
            }
            let searchable = [
                comparison.testType.title,
                comparison.earlierResult.title,
                comparison.laterResult.title,
                comparison.localSummaryTitle,
                comparison.localSummaryDetail,
                comparison.aiSummary ?? ""
            ].joined(separator: " ")
            let bySearch = search.isEmpty || searchable.localizedCaseInsensitiveContains(search)
            return byFilter && bySearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    searchCard

                    testTypeToggle

                    filterBar

                    if isCompareMode {
                        compareSelectionCard
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .lineContentColumn()
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color.lineBackground.ignoresSafeArea(edges: .top))
                .zIndex(1)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if groupedCycles.isEmpty {
                            EmptyStateView(
                                title: isCompareMode ? "No matching scans" : "No scans yet",
                                message: isCompareMode ? "Choose another first scan or clear the comparison." : "Saved checks and comparisons will appear here.",
                                buttonTitle: isCompareMode ? "Clear Compare" : "Start Scan",
                                action: isCompareMode ? clearCompare : { appState.startScan(testType: filter.testType) },
                                illustrationStyle: .homeTile(filter.testType),
                                isCard: false
                            )
                            .padding(.horizontal, layout.horizontalPadding)
                        } else {
                            VStack(alignment: .leading, spacing: 28) {
                                ForEach(groupedCycles) { group in
                                    cycleSection(group)
                                        .id(group.id)
                                }
                            }
                            .padding(.horizontal, layout.horizontalPadding)
                        }
                    }
                    .padding(.top, 12)
                    .lineBottomInset()
                    .lineContentColumn()
                    // Fill the viewport when there are fewer scans than fill a
                    // screen, so bottom-anchoring has no slack to push the list
                    // down and leave a gap above it. Once the list is longer
                    // than the viewport this minimum stops applying and the
                    // anchor does its real job — opening on the newest test
                    // rather than the oldest.
                    .frame(minHeight: listViewportHeight, alignment: .top)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listViewportHeight = $0 }
                .defaultScrollAnchor(.bottom)
            }
            .background { LineCheckBrandBackdrop() }
            .sheet(item: $compareRoute) { route in
                CompareView(initialFirst: route.first, initialSecond: route.second)
            }
            .sheet(item: $selectedComparison) { comparison in
                ComparisonHistoryDetailView(comparison: comparison)
            }
            .sheet(isPresented: $showDateRangeFilter) { dateRangeFilterSheet }
            .overlay {
                if showCompareHelp {
                    BrandedNoticeOverlay(
                        icon: "rectangle.split.2x1",
                        imageName: "HomeCompareIcon",
                        title: "Compare scans",
                        message: "Choose two saved scans of the same test type.",
                        primaryTitle: "Got it",
                        primaryAction: { showCompareHelp = false }
                    )
                }
            }
        }
        .tint(Color.lineBlue)
        .onAppear(perform: consumeLunaRoute)
        .onChange(of: appState.historyRoute) { _, _ in
            consumeLunaRoute()
        }
    }

    private func consumeLunaRoute() {
        guard let route = appState.historyRoute else { return }
        appState.historyRoute = nil
        search = ""
        filter = .ovulation
        cycleFilter = .all
        dateRange = nil
        switch route {
        case .recent:
            isCompareMode = false
            compareBaseScan = nil
        case .compare:
            isCompareMode = true
            compareBaseScan = nil
            showCompareHelp = true
        }
    }

    private var searchCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search by result or note", text: $search)
                .font(.lineSubheadline())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.88), Color.linePurpleSoft.opacity(0.48)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.80), lineWidth: 1)
        )
        .shadow(color: Color.linePurple.opacity(0.06), radius: 8, y: 3)
    }

    private var testTypeToggle: some View {
        Picker("Test type", selection: $filter) {
            ForEach(HistoryFilter.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("History test type")
    }

    private var filterBar: some View {
        // ScrollView's content is measured with an unbounded proposed width
        // along its scroll axis, so `.frame(maxWidth: .infinity)` on the
        // HStack inside it is a no-op and never actually centers anything.
        // ViewThatFits tries the plain centered row first and only falls
        // back to the scrollable version if the chips don't fit.
        ViewThatFits(in: .horizontal) {
            filterChips
                .frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                filterChips
            }
            .scrollClipDisabled()
        }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All Cycles") { cycleFilter = .all }
                if hasUnassignedScans {
                    Button("Unassigned") { cycleFilter = .unassigned }
                }
                if !cyclesWithScans.isEmpty {
                    Divider()
                    ForEach(cyclesWithScans) { cycle in
                        Button(cycleFilterTitle(.cycle(cycle.id))) { cycleFilter = .cycle(cycle.id) }
                    }
                }
            } label: {
                filterChip(title: cycleFilterTitle(cycleFilter), isActive: cycleFilter != .all)
            }

            Button {
                if let dateRange {
                    pendingRangeStart = dateRange.lowerBound
                    pendingRangeEnd = dateRange.upperBound
                }
                showDateRangeFilter = true
            } label: {
                filterChip(title: dateRangeButtonTitle, isActive: dateRange != nil)
            }

            Button {
                if isCompareMode {
                    clearCompare()
                } else {
                    isCompareMode = true
                    compareBaseScan = nil
                    showCompareHelp = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.app(.caption2, weight: .bold))
                    Text(isCompareMode ? "Cancel Compare" : "Compare")
                }
                .font(.lineCaption(.semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
            }

            if isFiltering {
                Button {
                    cycleFilter = .all
                    dateRange = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .font(.lineCaption(.semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
    }

    private func filterChip(title: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.app(.caption2, weight: .bold))
        }
        .font(.lineCaption(.semibold))
        .foregroundStyle(isActive ? Color.white : Color.lineNavy.opacity(0.72))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isActive ? AnyShapeStyle(Color.lineBlue) : AnyShapeStyle(Color.white.opacity(0.88)), in: Capsule())
        .overlay(Capsule().stroke(isActive ? Color.clear : Color.black.opacity(0.08), lineWidth: 1))
    }

    private var dateRangeFilterSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $pendingRangeStart, in: ...pendingRangeEnd, displayedComponents: .date)
                DatePicker("To", selection: $pendingRangeEnd, in: pendingRangeStart...Date.now, displayedComponents: .date)
                Section {
                    Button("Apply") {
                        let start = Calendar.current.startOfDay(for: pendingRangeStart)
                        dateRange = start...endOfDay(pendingRangeEnd)
                        showDateRangeFilter = false
                    }
                    .buttonStyle(.primaryLine)
                    if dateRange != nil {
                        Button("Clear Date Range", role: .destructive) {
                            dateRange = nil
                            showDateRangeFilter = false
                        }
                    }
                }
            }
            .navigationTitle("Filter By Date")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDateRangeFilter = false } } }
        }
        .tint(Color.lineBlue)
    }

    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }

    private var compareSelectionCard: some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: compareBaseScan == nil ? "1.circle.fill" : "2.circle.fill")
                    .font(.system(size: LineType.size(24), weight: .bold))
                    .foregroundStyle(Color.lineBlue)
                    .frame(width: 38, height: 38)
                    .background(Color.lineBlue.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(compareBaseScan == nil ? "Choose the first scan" : "Choose another \(compareBaseScan?.testType.shortTitle ?? "") scan")
                        .font(.lineSubheadline(.semibold))
                        .foregroundStyle(Color.lineNavy)
                    Text(compareBaseScan.map { "Selected \($0.resultType.title) from \(DateFormatting.shortDate.string(from: $0.createdAt))." } ?? "Tap any saved scan to start a comparison.")
                        .font(.lineCaption())
                        .foregroundStyle(Color.lineNavy.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if compareBaseScan != nil {
                    Button("Clear") {
                        compareBaseScan = nil
                    }
                    .buttonStyle(.secondaryLine)
                    .frame(width: 86)
                }
            }
        }
    }

    private func cycleSection(_ group: HistoryCycleGroup) -> some View {
        let tint: Color = .linePurple
        return VStack(alignment: .leading, spacing: 10) {
            cycleDividerCard(group)

            VStack(spacing: layout.isRegular ? 8 : 0) {
                    ForEach(Array(group.scans.enumerated()), id: \.element.id) { index, scan in
                        scanListRow(scan)
                            // Wide rows are tall enough that a hairline no longer
                            // reads as a boundary; each test gets its own surface.
                            .background {
                                if layout.isRegular {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.55))
                                }
                            }
                            .padding(.horizontal, layout.isRegular ? 8 : 0)

                        if index < group.scans.count - 1, !layout.isRegular {
                            Divider()
                                .padding(.leading, 78)
                        }
                    }
            }
            .padding(.vertical, layout.isRegular ? 8 : 0)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.97), tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint.opacity(0.13)))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func cycleDividerCard(_ group: HistoryCycleGroup) -> some View {
        HStack {
            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(cycleTitle(for: group))
                    .font(.lineSubheadline(.bold))
                    .foregroundStyle(Color.lineNavy)
                    .multilineTextAlignment(.center)

                Text(cycleSummary(for: group))
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.lineBlue.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.lineBlue.opacity(0.13)))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func comparisonRow(_ comparison: ScanComparison) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: LineType.size(18), weight: .bold))
                .foregroundStyle(Color.lineBlue)
                .frame(width: 46, height: 46)
                .background(Color.lineBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(comparison.testType.shortTitle) Comparison")
                        .font(.lineSubheadline(.bold))
                        .foregroundStyle(Color.lineNavy)
                        .fixedSize(horizontal: false, vertical: true)

                    if comparison.aiSummary?.isEmpty == false {
                        Text("AI")
                            .font(.app(.caption2, weight: .bold))
                            .foregroundStyle(Color.lineBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.linePurpleSoft.opacity(0.7), in: Capsule())
                    }
                }

                Text("\(DateFormatting.shortDate.string(from: comparison.earlierDate)) → \(DateFormatting.shortDate.string(from: comparison.laterDate))")
                    .font(.lineCaption())
                    .foregroundStyle(Color.lineNavy.opacity(0.55))

                Text(comparison.localSummaryTitle)
                    .font(.lineCaption(.semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                ResultBadge(result: comparison.laterResult)
                Text(comparisonDelta(comparison))
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ item: HistoryTimelineItem) -> some View {
        switch item.kind {
        case .scan(let scan):
            scanListRow(scan)
                .contextMenu {
                    Button {
                        startCompare(with: scan)
                    } label: {
                        Label("Compare With...", systemImage: "rectangle.split.2x1")
                    }

                    Button {
                        scan.isFavourite.toggle()
                        appState.toast = scan.isFavourite ? "Favourite added" : "Favourite removed"
                    } label: {
                        Label(scan.isFavourite ? "Unfavourite" : "Favourite", systemImage: scan.isFavourite ? "star.slash" : "star")
                    }

                    Button(role: .destructive) {
                        delete(scan)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        case .comparison(let comparison):
            Button {
                selectedComparison = comparison
            } label: {
                comparisonRow(comparison)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    delete(comparison)
                } label: {
                    Label("Delete Comparison", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func scanListRow(_ scan: Scan) -> some View {
        if isCompareMode {
            Button {
                handleCompareTap(scan)
            } label: {
                HistoryStripRow(scan: scan, cycleDay: cycleDay(for: scan))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ResultDetailView(scan: scan)
            } label: {
                HistoryStripRow(scan: scan, cycleDay: cycleDay(for: scan))
            }
            .buttonStyle(.plain)
        }
    }

    private func cycleDay(for scan: Scan) -> Int? {
        let cycle = scan.cycleRecordID.flatMap { id in cycles.first { $0.id == id } }
            ?? cycles.last { $0.startDate <= scan.createdAt && ($0.endDate == nil || scan.createdAt <= $0.endDate!) }
        guard let cycle else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: cycle.startDate), to: Calendar.current.startOfDay(for: scan.createdAt)).day.map { $0 + 1 }
    }

    private var groupedCycles: [HistoryCycleGroup] {
        let byCycle = Dictionary(grouping: displayedScans) { scan in
            cycle(for: scan)?.id
        }
        return byCycle.compactMap { id, scans in
            let ordered = scans.sorted { $0.createdAt < $1.createdAt }
            guard let fallbackDate = ordered.first?.createdAt else { return nil }
            return HistoryCycleGroup(
                cycle: id.flatMap { target in cycles.first { $0.id == target } },
                scans: ordered,
                fallbackDate: fallbackDate
            )
        }
        .sorted { $0.scans.first?.createdAt ?? .distantPast < $1.scans.first?.createdAt ?? .distantPast }
    }

    private func cycle(for scan: Scan) -> CycleRecord? {
        if let id = scan.cycleRecordID, let assigned = cycles.first(where: { $0.id == id }) {
            return assigned
        }
        return cycles.last {
            $0.startDate <= scan.createdAt && ($0.endDate == nil || scan.createdAt < $0.endDate!)
        }
    }

    private func cycleTitle(for group: HistoryCycleGroup) -> String {
        guard let cycle = group.cycle else { return "Tests without a logged cycle" }
        if cycle.endDate == nil { return "Current cycle" }
        let start = DateFormatting.shortDate.string(from: cycle.startDate)
        let end = DateFormatting.shortDate.string(from: cycle.endDate ?? group.fallbackDate)
        return "Cycle · \(start)–\(end)"
    }

    private func cycleSummary(for group: HistoryCycleGroup) -> String {
        let testLabel = "\(group.scans.count) FSH test\(group.scans.count == 1 ? "" : "s")"
        let peakSuffix = (filter == .ovulation && group.scans.contains(where: { $0.resultType == .elevated })) ? " · Elevated reading" : ""

        guard let cycle = group.cycle else {
            return testLabel + peakSuffix + ". Add a period in Calendar to place them in a cycle."
        }
        if cycle.endDate != nil {
            return testLabel + peakSuffix
        }
        let start = DateFormatting.shortDate.string(from: cycle.startDate)
        return "Started \(start) · \(testLabel)" + peakSuffix
    }

    private func delete(_ scan: Scan) {
        AppAnalytics.log("linecheck_scan_deleted", ["test_type": scan.testType.rawValue])
        ImageStorageService.shared.delete(filename: scan.imageFilename)
        ImageStorageService.shared.delete(filename: scan.enhancedImageFilename)
        ImageStorageService.shared.delete(filename: scan.autoEnhancedImageFilename)
        ImageStorageService.shared.delete(filename: scan.thumbnailFilename)
        for comparison in comparisons where comparison.earlierScanID == scan.id || comparison.laterScanID == scan.id {
            modelContext.delete(comparison)
        }
        let affectedCycleID = scan.cycleRecordID
        modelContext.delete(scan)
        try? modelContext.save()
        // Deleting a scan (e.g. a peak result) can shift the reconciled
        // ovulation estimate, which moves fertile-peak/period-expected
        // reminder timing - resync so reminders don't keep firing stale.
        if let settings = UserSettings.canonical(from: settings), settings.autoRemindersEnabled,
           let cycle = cycles.first(where: { $0.id == affectedCycleID }),
           let window = CycleTrackingService.window(for: cycle.startDate, records: cycles, settings: settings) {
            Task {
                await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: reminders, context: modelContext)
            }
        }
        appState.toast = "Scan deleted"
    }

    private func delete(_ comparison: ScanComparison) {
        modelContext.delete(comparison)
        try? modelContext.save()
        appState.toast = "Comparison deleted"
    }

    private func comparisonDelta(_ comparison: ScanComparison) -> String {
        let value = comparison.testType == .ovulation
            ? comparison.laterRatio - comparison.earlierRatio
            : comparison.laterLineStrength - comparison.earlierLineStrength
        let formatted = abs(value).formatted(.number.precision(.fractionLength(2)))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return "0.00"
    }

    private func startCompare(with scan: Scan) {
        isCompareMode = true
        compareBaseScan = scan
        showCompareHelp = true
    }

    private func handleCompareTap(_ scan: Scan) {
        guard let base = compareBaseScan else {
            compareBaseScan = scan
            return
        }
        guard base.id != scan.id else { return }
        guard base.testType == scan.testType else {
            appState.toast = "Choose another \(base.testType.shortTitle) scan"
            return
        }
        compareRoute = CompareRoute(first: base, second: scan)
        clearCompare()
    }

    private func clearCompare() {
        isCompareMode = false
        compareBaseScan = nil
    }
}

private struct HistoryStripRow: View {
    @Environment(\.lineLayout) private var layout
    let scan: Scan
    let cycleDay: Int?

    private var image: UIImage? {
        ImageStorageService.shared.load(scan.compactImageRef)
    }

    /// A wide pregnancy row has nothing left for the trailing column once the
    /// badge is gone, so it collapses rather than reserving empty space.
    private var trailingColumnWidth: CGFloat? {
        guard layout.isRegular else { return 64 }
        return scan.excludedFromCalculations ? 40 : nil
    }

    /// One line of whatever this particular scan actually knows about itself,
    /// most specific first. Returns nil rather than filler when there is
    /// nothing worth saying.
    private var contextLine: String? {
        if let brand = scan.brandName?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            return brand
        }
        let note = scan.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        var parts: [String] = []
        if scan.testType == .ovulation {
            parts.append("Ratio \(scan.testControlRatio.formatted(.number.precision(.fractionLength(2))))")
        }
        if scan.certaintyPercentage > 0 {
            parts.append("Readability \(scan.certaintyPercentage)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                if let cycleDay {
                    Text("CD \(cycleDay)")
                        .font(.app(size: LineType.size(12), weight: .semibold))
                        .foregroundStyle(scan.testType.tint)
                }
                Text(scan.createdAt, format: .dateTime.day().month())
                    .font(.app(size: LineType.size(15), weight: .semibold))
                    .foregroundStyle(Color.lineNavy)
                Text(scan.createdAt, format: .dateTime.hour().minute())
                    .font(.app(size: LineType.size(12), weight: .regular))
                    .foregroundStyle(Color.lineNavy.opacity(0.55))
            }
            .frame(width: layout.isRegular ? 92 : 54, alignment: .leading)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.linePurpleSoft, Color.linePink.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                        Image(systemName: "testtube.2")
                            .foregroundStyle(Color.lineNavy.opacity(0.35))
                    }
                }
            }
            .frame(maxWidth: layout.isRegular ? 320 : .infinity)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08)))
            .layoutPriority(1)

            if layout.isRegular {
                // Capping the strip leaves slack in the row. Rather than pad it
                // out, the extra width carries detail the phone row has no space
                // for — the full result wording plus whatever context the scan
                // actually has (brand, note, or the measured ratio).
                VStack(alignment: .leading, spacing: 3) {
                    Text(scan.resultType.title)
                        .font(.app(size: LineType.size(14), weight: .bold))
                        .foregroundStyle(scan.resultType.tint)
                        .lineLimit(1)

                    if let context = contextLine {
                        Text(context)
                            .font(.app(size: LineType.size(11), weight: .medium))
                            .foregroundStyle(Color.lineNavy.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            }

            VStack(alignment: .trailing, spacing: 5) {
                // The bare ratio floating at the end of a wide row read as a
                // stray number; on iPad it moves into the detail line, which
                // says what it is.
                if scan.testType == .ovulation, !layout.isRegular {
                    Text(scan.testControlRatio.formatted(.number.precision(.fractionLength(2))))
                        .font(.app(size: LineType.size(13), weight: .medium))
                        .monospacedDigit()
                }
                // The result badge only earns its place on the phone row, where
                // nothing else states the result. The wide row spells it out in
                // the detail column, so repeating it here is noise.
                if !layout.isRegular {
                    Text(scan.resultType.badgeTitle)
                        .font(.app(size: LineType.size(11), weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(scan.resultType == .elevated ? Color.white : scan.resultType.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(scan.resultType == .elevated ? scan.resultType.tint : scan.resultType.tint.opacity(0.11), in: Capsule())
                }
                if scan.excludedFromCalculations {
                    Label("Excluded", systemImage: "eye.slash.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: LineType.size(10), weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.45))
                        .accessibilityLabel("Excluded from calculations")
                }
            }
            .frame(width: trailingColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cycleDay.map { "Cycle day \($0), " } ?? "")\(scan.resultType.title)\(scan.excludedFromCalculations ? ", excluded from calculations" : ""), \(scan.createdAt.formatted())")
    }
}

private struct CompareRoute: Identifiable {
    let first: Scan
    let second: Scan

    var id: String { "\(first.id)-\(second.id)" }
}

private struct ComparisonHistoryDetailView: View {
    @Environment(\.lineLayout) private var layout
    @Environment(\.dismiss) private var dismiss
    let comparison: ScanComparison

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AppScreenHeader(
                        title: "Saved Comparison",
                        subtitle: "\(comparison.testType.title) · \(DateFormatting.shortDate.string(from: comparison.createdAt))"
                    )

                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "rectangle.split.2x1")
                                    .font(.system(size: LineType.size(18), weight: .bold))
                                    .foregroundStyle(Color.lineBlue)
                                    .frame(width: 44, height: 44)
                                    .background(Color.lineBlue.opacity(0.10), in: Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(comparison.localSummaryTitle)
                                        .font(.lineHeadline())
                                        .foregroundStyle(Color.lineNavy)
                                    Text(comparison.localSummaryDetail)
                                        .font(.lineSubheadline())
                                        .foregroundStyle(Color.lineNavy.opacity(0.68))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Divider()

                            detail("Earlier result", "\(comparison.earlierResult.title) · \(DateFormatting.shortDate.string(from: comparison.earlierDate))")
                            detail("Later result", "\(comparison.laterResult.title) · \(DateFormatting.shortDate.string(from: comparison.laterDate))")

                            if comparison.testType == .ovulation {
                                detail("Earlier test/control value", comparison.earlierRatio.formatted(.number.precision(.fractionLength(2))))
                                detail("Later test/control value", comparison.laterRatio.formatted(.number.precision(.fractionLength(2))))
                                detail("Change", signed(comparison.laterRatio - comparison.earlierRatio))
                            } else {
                                detail("Earlier strength", comparison.earlierLineStrength.formatted(.number.precision(.fractionLength(2))))
                                detail("Later strength", comparison.laterLineStrength.formatted(.number.precision(.fractionLength(2))))
                                detail("Change", signed(comparison.laterLineStrength - comparison.earlierLineStrength))
                            }
                        }
                    }

                    if let aiSummary = comparison.aiSummary, !aiSummary.isEmpty {
                        AppCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .center, spacing: 12) {
                                    LunaAvatarView(size: 42)
                                        .padding(4)
                                        .background(Color.linePurpleSoft.opacity(0.75), in: Circle())
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Luna’s comparison")
                                            .font(.lineHeadline())
                                            .foregroundStyle(Color.lineNavy)
                                        Text("Saved premium guidance for this comparison.")
                                            .font(.lineCaption())
                                            .foregroundStyle(Color.lineNavy.opacity(0.60))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(AISummaryFormatting.sections(from: aiSummary)) { section in
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
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.linePurpleSoft.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.lineBlue.opacity(0.10), lineWidth: 1)
                                )
                            }
                        }
                    }

                    SafetyFooter()
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 16)
                .lineBottomInset()
                .lineContentColumn()
            }
            .background { LineCheckBrandBackdrop() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .tint(Color.lineBlue)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
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

    private func signed(_ value: Double) -> String {
        let formatted = abs(value).formatted(.number.precision(.fractionLength(2)))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return "0.00"
    }

}

struct ResultDetailView: View {
    @Environment(\.lineLayout) private var layout
    var scan: Scan
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \Scan.createdAt, order: .reverse) private var scans: [Scan]
    @Query(sort: \ScanComparison.createdAt) private var comparisons: [ScanComparison]
    @Query(sort: \CycleRecord.startDate) private var cycles: [CycleRecord]
    @Query private var settingsRows: [UserSettings]
    @Query(sort: \Reminder.scheduledDate) private var reminders: [Reminder]
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var compareRoute: CompareRoute?
    @State private var showEdit = false
    @State private var showDeleteConfirmation = false

    private var reportImage: UIImage? {
        ImageStorageService.shared.load(scan.displayImageRef)
    }

    private var previousComparableScan: Scan? {
        scans
            .filter { compatible($0) && $0.createdAt < scan.createdAt }
            .first
            ?? scans.filter(compatible).first
    }

    private var isSelfSelected: Bool {
        scan.analysisMode == .manualEnhance && scan.resultSource == .userOverride
    }

    private func compatible(_ candidate: Scan) -> Bool {
        guard candidate.id != scan.id, candidate.testType == scan.testType else { return false }
        if scan.testType == .ovulation, let firstCycle = scan.cycleRecordID, let secondCycle = candidate.cycleRecordID, firstCycle != secondCycle { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(scan.testType.title) · \(scan.analysisMode.title)")
                    .font(.lineSubheadline(.medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                AppCard {
                    VStack(spacing: 8) {
                        if isSelfSelected {
                            Text("You marked this as")
                                .font(.app(.caption, weight: .semibold))
                                .foregroundStyle(Color.lineNavy.opacity(0.56))
                        }
                        Text(isSelfSelected ? scan.resultType.badgeTitle : scan.resultType.title)
                            .font(.app(.title3, weight: .bold))
                            .foregroundStyle(scan.resultType.tint)

                        if !isSelfSelected, scan.certaintyPercentage > 0 {
                            Text("Image readability: \(scan.certaintyPercentage)%")
                                .font(.app(.caption, weight: .semibold))
                                .foregroundStyle(Color.lineNavy.opacity(0.60))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let image = reportImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }

                AppCard {
                    VStack(spacing: 10) {
                        detail("Test Type", scan.testType.title)
                        detail("Analysis Mode", scan.analysisMode.title)
                        detail("Date", "\(DateFormatting.shortDate.string(from: scan.createdAt)) \(DateFormatting.shortTime.string(from: scan.createdAt))")
                        if isSelfSelected {
                            detail("Result Source", "Selected by you")
                        } else {
                            detail("Control Line", scan.controlLineDetected ? "Detected" : "Not detected")
                            detail("Test Line", scan.testLineDetected ? "Detected" : "Not detected")

                            if scan.testType == .ovulation {
                                detail("Test/control photo value", scan.testControlRatio.formatted(.number.precision(.fractionLength(2))))
                            }

                            detail("Line Strength", scan.lineStrength.formatted(.number.precision(.fractionLength(2))))
                        }

                        if !scan.notes.isEmpty {
                            detail("Notes", scan.notes)
                        }

                        if scan.excludedFromCalculations {
                            detail("Included in patterns", "No - excluded by you")
                        }
                    }
                }

                Button("Share Report") {
                    share()
                }
                .buttonStyle(.primaryLine)

                Button("Edit Tracking Details") { showEdit = true }
                    .buttonStyle(.secondaryLine)

                if let previousComparableScan {
                    Button("Compare to Previous") {
                        compareRoute = CompareRoute(first: previousComparableScan, second: scan)
                    }
                    .buttonStyle(.secondaryLine)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Test", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryLine)

                SafetyFooter()
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, 16)
            .lineBottomInset()
            .lineContentColumn()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Result Details")
                    .font(.app(.headline, weight: .bold))
                    .foregroundStyle(Color.lineNavy)
            }
        }
        .background { LineCheckBrandBackdrop() }
        .tint(Color.lineBlue)
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems, onDismiss: { showShare = false }) }
        .sheet(item: $compareRoute) { route in
            CompareView(initialFirst: route.first, initialSecond: route.second)
        }
        .sheet(isPresented: $showEdit) {
            ScanTrackingEditor(scan: scan)
        }
        .confirmationDialog(
            "Delete this test? This can't be undone.",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Test", role: .destructive) { deleteScan() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteScan() {
        AppAnalytics.log("linecheck_scan_deleted", ["test_type": scan.testType.rawValue])
        ImageStorageService.shared.delete(filename: scan.imageFilename)
        ImageStorageService.shared.delete(filename: scan.enhancedImageFilename)
        ImageStorageService.shared.delete(filename: scan.autoEnhancedImageFilename)
        ImageStorageService.shared.delete(filename: scan.thumbnailFilename)
        for comparison in comparisons where comparison.earlierScanID == scan.id || comparison.laterScanID == scan.id {
            modelContext.delete(comparison)
        }
        let affectedCycleID = scan.cycleRecordID
        modelContext.delete(scan)
        try? modelContext.save()
        // Deleting a scan (e.g. a peak result) can shift the reconciled
        // ovulation estimate, which moves fertile-peak/period-expected
        // reminder timing - resync so reminders don't keep firing stale.
        if let settings = UserSettings.canonical(from: settingsRows), settings.autoRemindersEnabled,
           let cycle = cycles.first(where: { $0.id == affectedCycleID }),
           let window = CycleTrackingService.window(for: cycle.startDate, records: cycles, settings: settings) {
            Task {
                await ReminderAutomationService.syncPredictedReminders(cycle: cycle, window: window, settings: settings, existingReminders: reminders, context: modelContext)
            }
        }
        appState.toast = "Test deleted"
        dismiss()
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(Color.lineNavy.opacity(0.55))
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.lineNavy)
        }
        .font(.app(.subheadline))
    }

    private func share() {
        if let url = PDFExportHelper.makeReport(scan: scan, image: reportImage) {
            shareItems = [url]
            showShare = true
        }
    }
}
