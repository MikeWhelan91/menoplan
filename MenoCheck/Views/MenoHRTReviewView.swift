import SwiftUI

/// A medication memory aid, not an HRT recommendation engine.
struct MenoHRTReviewView: View {
    @EnvironmentObject private var store: MenoStore
    @State private var saved = false

    var body: some View {
        MenoScreen(title: "HRT review", subtitle: "Keep the details you want to bring to a clinician. Menoplan does not advise on dose, suitability or changes.") {
            MenoSection(title: "Your current routine") {
                Toggle("I currently use HRT", isOn: $store.profile.usesHRT)
                MenoRule()
                TextField("Product, route and dose (optional)", text: $store.profile.hrtRegimen, axis: .vertical)
                    .lineLimit(2...4)
                MenoRule()
                TextField("Changes, side effects or questions", text: $store.profile.hrtReviewNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
            MenoSection(title: "Before your review") {
                Text("Bring your current product packaging, any bleeding changes, symptom pattern and questions. A clinician can discuss options based on your history and preferences.").font(MenoFont.secondary).foregroundStyle(MenoColor.inkSecondary)
            }
            Button(saved ? "Saved to your care summary" : "Save HRT review", systemImage: saved ? "checkmark" : "checkmark.circle") {
                store.profile.hrtLastChanged = .now
                saved = true
            }
            .buttonStyle(MenoPrimaryButtonStyle())
        }
    }
}
