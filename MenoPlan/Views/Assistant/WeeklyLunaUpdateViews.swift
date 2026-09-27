import SwiftUI

/// The teaser shown at the top of the Assistant inbox once at least one weekly digest exists.
/// Nothing is shown before that - there's no value in advertising a feature that hasn't
/// produced anything yet (see WeeklyLunaUpdateService.isDue).
struct WeeklyLunaUpdateCard: View {
    let update: WeeklyLunaUpdate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Luna Weekly Update · \(update.weekRangeTitle)")
                .font(.app(size: LineType.size(15), weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .overlay(alignment: .leading) {
                    if !update.isRead {
                        Circle()
                            .fill(Color.linePink)
                            .frame(width: 8, height: 8)
                            .padding(.leading, 16)
                    }
                }
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.right")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.35))
                        .padding(.trailing, 16)
                }
            .background(
                LinearGradient(colors: [Color.linePurpleSoft.opacity(0.55), Color.white.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
            .shadow(color: Color.lineNavy.opacity(0.07), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }
}

/// Every past weekly digest, newest first. Marks the newest one read as soon as this appears,
/// since opening the sheet is the "I saw it" signal.
struct WeeklyLunaUpdatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let updates: [WeeklyLunaUpdate]
    @State private var currentPage = 0

    private let reportsPerPage = 5

    private var pageCount: Int {
        max(1, Int(ceil(Double(updates.count) / Double(reportsPerPage))))
    }

    private var currentPageUpdates: [WeeklyLunaUpdate] {
        let start = currentPage * reportsPerPage
        return Array(updates.dropFirst(start).prefix(reportsPerPage))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(currentPageUpdates) { update in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Luna Weekly Update")
                                .font(.app(size: LineType.size(20), weight: .bold))
                                .foregroundStyle(Color.lineNavy)
                            Text(update.weekRangeTitle)
                                .font(.app(size: LineType.size(13), weight: .semibold))
                                .foregroundStyle(Color.linePurple)

                            ForEach(WeeklyReportSection.sections(from: update.reply)) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.app(size: LineType.size(12), weight: .bold))
                                        .foregroundStyle(Color.linePurple)
                                        .tracking(0.6)
                                    Text(section.body)
                                        .font(.app(size: LineType.size(16), weight: .medium))
                                        .foregroundStyle(Color.lineNavy.opacity(0.82))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.linePurple.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
                    }

                    if pageCount > 1 {
                        weeklyReportPagination
                    }
                }
                .padding(18)
            }
            .background { LineCheckBrandBackdrop() }
            .navigationTitle("Weekly Updates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .tint(Color.lineBlue)
        .onAppear {
            guard let latest = updates.first, !latest.isRead else { return }
            latest.isRead = true
            try? modelContext.save()
        }
    }

    private var weeklyReportPagination: some View {
        VStack(spacing: 10) {
            Text("Page \(currentPage + 1) of \(pageCount)")
                .font(.app(size: LineType.size(13), weight: .semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.58))

            HStack(spacing: 8) {
                Button {
                    currentPage = max(0, currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.app(.caption, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.9), in: Circle())
                }
                .disabled(currentPage == 0)
                .opacity(currentPage == 0 ? 0.35 : 1)
                .accessibilityLabel("Previous page")

                ForEach(0..<pageCount, id: \.self) { page in
                    Button {
                        currentPage = page
                    } label: {
                        Text("\(page + 1)")
                            .font(.app(size: LineType.size(14), weight: .bold))
                            .foregroundStyle(page == currentPage ? Color.white : Color.linePurple)
                            .frame(width: 34, height: 34)
                            .background(page == currentPage ? Color.linePurple : Color.white.opacity(0.9), in: Circle())
                            .overlay(Circle().stroke(Color.linePurple.opacity(0.16), lineWidth: 1))
                    }
                    .accessibilityLabel("Page \(page + 1)")
                }

                Button {
                    currentPage = min(pageCount - 1, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.app(.caption, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.9), in: Circle())
                }
                .disabled(currentPage == pageCount - 1)
                .opacity(currentPage == pageCount - 1 ? 0.35 : 1)
                .accessibilityLabel("Next page")
            }
            .foregroundStyle(Color.linePurple)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private extension WeeklyLunaUpdate {
    var weekRangeTitle: String {
        "\(weekStartDate.ordinalDay) – \(weekEndDate.ordinalDay) \(weekEndDate.formatted(.dateTime.month(.wide)))"
    }
}

private extension Date {
    var ordinalDay: String {
        let day = Calendar.current.component(.day, from: self)
        let suffix: String
        switch day % 100 {
        case 11...13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}

private struct WeeklyReportSection: Identifiable {
    let title: String
    let body: String
    var id: String { title }

    static func sections(from reply: String) -> [WeeklyReportSection] {
        let titles = ["THIS WEEK": "This week", "WHAT IT MAY MEAN": "What it may mean", "NEXT STEPS": "Next steps"]
        var sections: [WeeklyReportSection] = []
        var currentTitle: String?
        var lines: [String] = []

        func appendCurrent() {
            guard let currentTitle, !lines.isEmpty else { return }
            sections.append(WeeklyReportSection(title: currentTitle, body: lines.joined(separator: "\n")))
        }

        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title = titles[line.uppercased()] {
                appendCurrent()
                currentTitle = title
                lines = []
            } else if !line.isEmpty {
                lines.append(line)
            }
        }
        appendCurrent()
        return sections.isEmpty ? [WeeklyReportSection(title: "This week", body: reply)] : sections
    }
}
