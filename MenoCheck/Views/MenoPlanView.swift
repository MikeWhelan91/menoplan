import SwiftUI

/// Non-medical, time-boxed self-care experiments. The result is a reflection on the
/// user's own record, never a clinical conclusion.
struct MenoPlanView: View {
    @EnvironmentObject private var store: MenoStore
    @State private var completing: MenoExperiment?

    private let suggestions = [
        ("Earlier caffeine cut-off", "Try no caffeine after 2pm and log sleep and flushes for 7 days.", "cup.and.saucer"),
        ("Cooler nights", "Use a cooler bedroom or layered bedding for 7 nights and track night sweats.", "thermometer.snowflake"),
        ("Gentle wind-down", "Try a consistent 10-minute wind-down before bed for one week.", "moon.zzz"),
        ("Strength and movement", "Plan two short strength or weight-bearing sessions this week.", "figure.strengthtraining.traditional"),
    ]

    var body: some View {
        MenoScreen(title: "Your plan", subtitle: "Small, optional experiments that help you notice what feels useful. They are not treatment advice.") {
            if let active = store.experiments.first(where: { !$0.isComplete }) {
                MenoSection(title: "In progress", trailing: active.endDate.formatted(.dateTime.day().month())) {
                    Text(active.title).font(MenoFont.body.weight(.bold)).foregroundStyle(MenoColor.ink)
                    Text(active.detail).font(MenoFont.secondary).foregroundStyle(MenoColor.inkSecondary)
                    Button("Finish and reflect", systemImage: "checkmark") { completing = active }
                        .buttonStyle(MenoSecondaryButtonStyle())
                }
            }

            if store.experiments.allSatisfy(\.isComplete) {
                MenoSection(title: "Try an experiment", detail: "Choose one thing at a time, keep your normal tracking routine, then decide whether it was worth keeping.") {
                ForEach(suggestions, id: \.0) { item in
                    Button {
                        store.startExperiment(MenoExperiment(title: item.0, detail: item.1))
                    } label: {
                        HStack(spacing: MenoSpace.m) {
                            Image(systemName: item.2).foregroundStyle(MenoColor.primary).frame(width: 36, height: 36).background(MenoColor.primarySoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.0).font(MenoFont.body.weight(.semibold)).foregroundStyle(MenoColor.ink)
                                Text(item.1).font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(MenoColor.primary)
                        }
                    }.buttonStyle(.plain)
                    if item.0 != suggestions.last?.0 { MenoRule() }
                }
            }
            }

            if store.experiments.contains(where: \.isComplete) {
                MenoSection(title: "What you've learned") {
                    ForEach(store.experiments.filter(\.isComplete)) { experiment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(experiment.title).font(MenoFont.body.weight(.semibold)).foregroundStyle(MenoColor.ink)
                            Text(experiment.reflection.isEmpty ? "No reflection saved." : experiment.reflection).font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
                        }
                    }
                }
            }
        }
        .sheet(item: $completing) { experiment in MenoExperimentReflectionSheet(experiment: experiment) }
    }
}

private struct MenoExperimentReflectionSheet: View {
    @EnvironmentObject private var store: MenoStore
    @Environment(\.dismiss) private var dismiss
    let experiment: MenoExperiment
    @State private var reflection = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Your reflection") {
                    Text(experiment.title).font(.headline)
                    TextField("What did you notice?", text: $reflection, axis: .vertical).lineLimit(4...7)
                }
                Section {
                    Text("This saves your experience alongside your records. It does not show that the experiment caused a change.").font(.footnote)
                }
            }
            .navigationTitle("Finish experiment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.completeExperiment(experiment, reflection: reflection); dismiss() } }
            }
        }
    }
}
