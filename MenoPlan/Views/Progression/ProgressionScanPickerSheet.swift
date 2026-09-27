import SwiftData
import SwiftUI

/// The one genuinely new UI pattern this feature needs - no multi-select
/// exists elsewhere in the app. Lists scans compatible with the group's
/// test type (mirroring CompareView.isCompatible's same-cycle-for-ovulation
/// rule) that aren't already in the group, with a checkmark per row.
struct ProgressionScanPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.lineLayout) private var layout
    @Bindable var group: ProgressionGroup
    let allScans: [Scan]
    @State private var selectedIDs: Set<UUID> = []

    private var candidates: [Scan] {
        let existing = Set(group.scanIDs)
        return allScans
            .filter { $0.testType == group.testType && !existing.contains($0.id) }
            .filter { candidate in
                guard group.testType == .ovulation, let firstMemberCycle = firstMemberCycleID else { return true }
                guard let candidateCycle = candidate.cycleRecordID else { return true }
                return candidateCycle == firstMemberCycle
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Once a group has its first ovulation scan, later additions are kept
    /// to the same cycle - matching CompareView's isCompatible rule, so a
    /// progression never silently mixes LH data from two different cycles.
    private var firstMemberCycleID: UUID? {
        guard group.testType == .ovulation, let firstID = group.scanIDs.first else { return nil }
        return allScans.first(where: { $0.id == firstID })?.cycleRecordID
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if candidates.isEmpty {
                EmptyStateView(
                    title: "Nothing left to add",
                    message: "Every compatible saved test is already in this progression.",
                    buttonTitle: nil,
                    action: nil,
                    illustrationStyle: .homeTile(group.testType),
                    isCard: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scanList
            }

            addButton
        }
        .background { LineCheckBrandBackdrop() }
        .tint(Color.lineBlue)
        // A plain VStack, deliberately — not a NavigationStack. `.fitted` sizes
        // a sheet to its content's ideal height, and a NavigationStack reports
        // almost none, which collapses the sheet to a stub. A stack of real
        // views measures correctly. Still only applied when the content is a
        // fixed list rather than a greedy ScrollView.
        .modifier(FittedSheetWhenRegular(isRegular: usesFittedSheet))
    }

    private var header: some View {
        ZStack {
            Text("Add Tests")
                .font(.app(size: LineType.size(17), weight: .bold))
                .foregroundStyle(Color.lineNavy)

            HStack {
                Button("Cancel") { dismiss() }
                    .font(.app(size: LineType.size(16), weight: .semibold))
                    .foregroundStyle(Color.lineBlue)
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// A short list on iPad renders as a plain stack so the sheet can size to
    /// it. Anything longer stays scrollable at the standard sheet size.
    private var usesFittedSheet: Bool {
        layout.isRegular && !candidates.isEmpty && candidates.count <= 6
    }

    @ViewBuilder
    private var scanList: some View {
        if usesFittedSheet {
            rows
        } else {
            ScrollView {
                rows
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 10) {
            ForEach(candidates) { scan in
                row(scan)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: layout.isRegular ? 560 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private func row(_ scan: Scan) -> some View {
        let isSelected = selectedIDs.contains(scan.id)
        return Button {
            toggle(scan)
        } label: {
            HStack(spacing: 13) {
                thumbnail(scan)

                VStack(alignment: .leading, spacing: 5) {
                    Text(DateFormatting.shortDate.string(from: scan.createdAt))
                        .font(.app(size: LineType.size(15), weight: .bold))
                        .foregroundStyle(Color.lineNavy)

                    Text(scan.resultType.title)
                        .font(.app(size: LineType.size(11), weight: .semibold))
                        .foregroundStyle(scan.resultType == .peak ? Color.white : scan.resultType.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            scan.resultType == .peak ? scan.resultType.tint : scan.resultType.tint.opacity(0.13),
                            in: Capsule()
                        )
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(measurementLabel(scan))
                        .font(.app(size: LineType.size(13), weight: .bold))
                        .foregroundStyle(Color.lineNavy)
                        .monospacedDigit()
                    Text("Readability \(scan.certaintyPercentage)%")
                        .font(.app(size: LineType.size(11), weight: .medium))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
                .lineLimit(1)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: LineType.size(22), weight: .semibold))
                    .foregroundStyle(isSelected ? Color.lineBlue : Color.lineNavy.opacity(0.22))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                isSelected ? Color.lineBlue.opacity(0.09) : Color.white.opacity(0.92),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.lineBlue.opacity(0.45) : Color.lineNavy.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addButton: some View {
        Button("Add \(selectedIDs.count) Selected") { addSelected() }
            .buttonStyle(.primaryLine)
            .disabled(selectedIDs.isEmpty)
            .frame(maxWidth: layout.isRegular ? 320 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
    }

    private func measurementLabel(_ scan: Scan) -> String {
        let value = scan.testType == .ovulation ? scan.testControlRatio : scan.lineStrength
        let formatted = value.formatted(.number.precision(.fractionLength(2)))
        return scan.testType == .ovulation ? "Ratio \(formatted)" : "Strength \(formatted)"
    }

    private func toggle(_ scan: Scan) {
        if selectedIDs.contains(scan.id) {
            selectedIDs.remove(scan.id)
        } else {
            selectedIDs.insert(scan.id)
        }
    }

    private func thumbnail(_ scan: Scan) -> some View {
        Group {
            if let image = ImageStorageService.shared.load(scan.compactImageRef) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // A flat block of colour read as a missing element. An icon on
                // the test's own tint reads as "no photo saved" instead.
                ZStack {
                    LinearGradient(
                        colors: [scan.testType.tint.opacity(0.16), scan.testType.tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "testtube.2")
                        .font(.system(size: LineType.size(17), weight: .semibold))
                        .foregroundStyle(scan.testType.tint.opacity(0.55))
                }
            }
        }
        // A saved test photo is a wide strip. Cropping it to a square (which
        // `scaledToFill` does, from the centre) throws away both ends —
        // including, on a cassette test, the result window. iPad has the width
        // to show it in its real proportions; the phone keeps the 44pt square
        // it has always used.
        .frame(width: layout.isRegular ? 104 : 44, height: layout.isRegular ? 58 : 44)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.lineNavy.opacity(0.08))
        )
    }

    private func addSelected() {
        let toAdd = allScans.filter { selectedIDs.contains($0.id) }
        group.scanIDs = (group.scanIDs + toAdd.map(\.id))
        try? modelContext.save()
        AppAnalytics.log("linecheck_progression_scans_added", [
            "test_type": group.testType.rawValue,
            "added_count": toAdd.count,
            "total_count": group.scanIDs.count
        ])
        dismiss()
    }
}

/// `presentationSizing` values are distinct opaque types, so the choice can't
/// be a ternary — it has to be a branch on the view itself.
private struct FittedSheetWhenRegular: ViewModifier {
    let isRegular: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRegular {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}
