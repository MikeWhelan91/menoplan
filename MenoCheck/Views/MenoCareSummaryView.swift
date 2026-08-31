import SwiftUI
import UIKit

/// A concise, shareable appointment brief. It deliberately reports observations rather than
/// interpreting them clinically, so a clinician can see the underlying record.
struct MenoCareSummaryView: View {
    @EnvironmentObject private var store: MenoStore
    @State private var pdfURL: URL?

    private var records: [MenoDailyRecord] {
        store.dailyRecords.values.sorted { $0.date > $1.date }
    }

    private var report: String {
        let profile = store.profile
        let recent = records.prefix(14)
        let flashes = recent.reduce(0) { $0 + $1.hotFlashes }
        let sleepValues = recent.filter { $0.sleepHours > 0 }.map(\.sleepHours)
        let averageSleep = sleepValues.isEmpty ? "Not logged" : String(format: "%.1f hours", sleepValues.reduce(0, +) / Double(sleepValues.count))
        let bleedingDates = recent.filter(\.bleeding).map { $0.date.formatted(date: .abbreviated, time: .omitted) }
        let noteLines = recent.compactMap { record -> String? in
            guard !record.note.isEmpty else { return nil }
            return "• \(record.date.formatted(date: .abbreviated, time: .omitted)): \(record.note)"
        }
        let notes = noteLines.isEmpty ? "No recent notes." : noteLines.joined(separator: "\n")
        return """
        Menoplan appointment summary
        Created \(Date.now.formatted(date: .abbreviated, time: .shortened))

        ABOUT ME
        Name: \(profile.name.isEmpty ? "Not provided" : profile.name)
        Age: \(profile.age.isEmpty ? "Not provided" : profile.age)
        Menopause stage: \(profile.stage)
        Uses HRT: \(profile.usesHRT ? "Yes" : "No")
        HRT routine: \(profile.hrtRegimen.isEmpty ? "Not recorded" : profile.hrtRegimen)
        HRT notes: \(profile.hrtReviewNotes.isEmpty ? "None" : profile.hrtReviewNotes)
        Main goal: \(profile.mainGoal)

        RECENT RECORD — LAST \(recent.count) DAYS LOGGED
        Hot flashes logged: \(flashes)
        Average logged sleep: \(averageSleep)
        Bleeding logged on: \(bleedingDates.isEmpty ? "None" : bleedingDates.joined(separator: ", "))
        FSH strip records saved: \(store.fshReadings.count) (mock test-line records; not hormone measurements)
        Personal experiments completed: \(store.experiments.filter(\.isComplete).count)

        NOTES
        \(notes)

        QUESTIONS TO DISCUSS
        • Could these symptoms be related to perimenopause or menopause?
        • What options fit my symptoms, history and preferences?
        • What should I track before our next review?

        This is a personal record, not a diagnosis or treatment recommendation.
        """
    }

    var body: some View {
        MenoScreen(title: "Care summary", subtitle: "A concise record to take into an appointment.") {
            MenoSection(title: "Your last 14 days", detail: "Reported observations only — no clinical interpretation.") {
                HStack(spacing: MenoSpace.xl) {
                    MenoMetricView(value: "\(records.prefix(14).reduce(0) { $0 + $1.hotFlashes })", label: "Hot flashes")
                    MenoMetricView(value: "\(store.fshReadings.count)", label: "FSH records")
                    MenoMetricView(value: "\(records.filter(\.bleeding).count)", label: "Bleeding days")
                    Spacer()
                }
            }
            MenoSection(title: "What to discuss") {
                Text("Your main goal: \(store.profile.mainGoal)").font(MenoFont.body.weight(.semibold)).foregroundStyle(MenoColor.ink)
                Text("Bring this alongside any medicines, test packaging and questions you have. It is designed to support—not replace—a clinical conversation.").font(MenoFont.secondary).foregroundStyle(MenoColor.inkSecondary)
            }
            ShareLink(item: report, subject: Text("Menoplan care summary"), message: Text("My personal menopause record")) {
                Label("Share care summary", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(MenoPrimaryButtonStyle())
            if let pdfURL {
                ShareLink(item: pdfURL, subject: Text("Menoplan care summary PDF")) {
                    Label("Share PDF summary", systemImage: "doc.richtext")
                }
                .buttonStyle(MenoSecondaryButtonStyle())
            } else {
                Button("Create PDF summary", systemImage: "doc.richtext") {
                    pdfURL = MenoPDFExporter.makeCareSummary(report)
                }
                .buttonStyle(MenoSecondaryButtonStyle())
            }
        }
    }
}

private enum MenoPDFExporter {
    static func makeCareSummary(_ text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "Menoplan-care-summary.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let title = "Menoplan care summary"
                title.draw(at: CGPoint(x: 44, y: 42), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor(red: 0.16, green: 0.10, blue: 0.07, alpha: 1),
                ])
                let bodyRect = CGRect(x: 44, y: 84, width: 507, height: 714)
                text.draw(in: bodyRect, withAttributes: [
                    .font: UIFont.systemFont(ofSize: 10.5),
                    .foregroundColor: UIColor(red: 0.24, green: 0.17, blue: 0.13, alpha: 1),
                ])
            }
            return url
        } catch {
            return nil
        }
    }
}
