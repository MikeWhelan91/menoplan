import SwiftData
import SwiftUI

/// Entry screen for the Pro "Progression" tool: a list of user-named,
/// saved groups of 3+ scans, each analyzable together with Luna. Presented
/// as a sheet from History (see HistoryView's "Progression" pill), separate
/// from History's own pairwise Compare mode since picking 3+ scans needs
/// real multi-select rather than compare's tap-two interaction.
struct ProgressionListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lineLayout) private var layout
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \ProgressionGroup.updatedAt, order: .reverse) private var groups: [ProgressionGroup]
    @Query private var settingsQuery: [UserSettings]
    @State private var showNewGroup = false
    @State private var showPremium = false
    @State private var newGroupName = ""
    @State private var newGroupTestType: TestType = .pregnancy
    @State private var justCreatedGroup: ProgressionGroup?

    private var settings: UserSettings? { UserSettings.canonical(from: settingsQuery) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if groups.isEmpty {
                        EmptyStateView(
                            title: "No progressions yet",
                            message: "Group 3 or more saved tests together to see the sequence side by side and get an AI-written trend summary.",
                            buttonTitle: "New Progression",
                            action: startNewGroup,
                            illustrationStyle: .icon(name: "rectangle.stack.fill", tint: .linePurple),
                            isCard: false
                        )
                        .padding(.top, 40)
                    } else {
                        Text("Group saved tests together to see the sequence side by side and get an AI-written trend summary.")
                            .font(.lineCaption())
                            .foregroundStyle(Color.lineNavy.opacity(0.6))
                            .padding(.bottom, 4)

                        ForEach(groups) { group in
                            NavigationLink {
                                ProgressionGroupDetailView(group: group)
                            } label: {
                                groupRow(group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 12)
                .lineBottomInset()
                .lineContentColumn()
            }
            .background { LineCheckBrandBackdrop() }
            .navigationTitle("Progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: startNewGroup) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNewGroup) { newGroupSheet }
            .fullScreenCover(isPresented: $showPremium) { PremiumView() }
            .navigationDestination(item: $justCreatedGroup) { group in
                ProgressionGroupDetailView(group: group)
            }
        }
        .tint(Color.lineBlue)
    }

    /// Viewing this list (including its empty state) is free; creating a
    /// group is the moment that actually commits someone to the feature,
    /// so that's where Pro is required - not on the Home tile tap, which
    /// would block even seeing what Progression is before deciding.
    private func startNewGroup() {
        guard settings?.proUnlocked == true else {
            appState.paywallSource = "progression_locked"
            showPremium = true
            return
        }
        showNewGroup = true
    }

    private func groupRow(_ group: ProgressionGroup) -> some View {
        AppCard {
            HStack(spacing: 12) {
                Image(systemName: group.testType == .pregnancy ? "testtube.2" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: LineType.size(16), weight: .bold))
                    .foregroundStyle(group.testType.tint)
                    .frame(width: 40, height: 40)
                    .background(group.testType.tint.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.lineHeadline())
                        .foregroundStyle(Color.lineNavy)
                    Text("\(group.scanIDs.count) tests · \(group.testType.shortTitle) · Updated \(DateFormatting.shortDate.string(from: group.updatedAt))")
                        .font(.lineCaption())
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.3))
            }
        }
    }

    private var newGroupSheet: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. \"Sept cycle\")", text: $newGroupName)
                Picker("Test type", selection: $newGroupTestType) {
                    ForEach(TestType.allCases) { Text($0.title).tag($0) }
                }
                Button("Create") { createGroup() }
                    .buttonStyle(.primaryLine)
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("New Progression")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showNewGroup = false } } }
        }
        .tint(Color.lineBlue)
    }

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = ProgressionGroup(name: trimmed, testType: newGroupTestType)
        modelContext.insert(group)
        try? modelContext.save()
        AppAnalytics.log("linecheck_progression_group_created", ["test_type": newGroupTestType.rawValue])
        newGroupName = ""
        showNewGroup = false
        justCreatedGroup = group
    }
}
