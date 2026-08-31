import SwiftUI

struct SymptomLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MenoStore
    @State private var selected: Symptom?
    @State private var intensity: Intensity = .moderate
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MenoSpace.xl) {
                    Text("What would you like to note?")
                        .font(MenoFont.secondary)
                        .foregroundStyle(MenoColor.inkSecondary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: MenoSpace.m),
                                        GridItem(.flexible(), spacing: MenoSpace.m)],
                              spacing: MenoSpace.m) {
                        ForEach(Symptom.allCases) { symptom in
                            SymptomChip(symptom: symptom, isSelected: selected == symptom) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    selected = selected == symptom ? nil : symptom
                                }
                            }
                        }
                    }

                    if selected != nil {
                        MenoSection(title: "How strong was it?", trailing: intensity.label) {
                            IntensityPicker(intensity: $intensity)
                        }

                        MenoSection(title: "Add a note", trailing: "Optional") {
                            TextField("", text: $note,
                                      prompt: Text("Anything worth remembering"),
                                      axis: .vertical)
                                .font(MenoFont.body)
                                .lineLimit(2...4)
                                .padding(MenoSpace.m)
                                .background(MenoColor.surfaceAlt,
                                            in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
                            Text("Will be logged at \(Date.now.formatted(date: .omitted, time: .shortened))")
                                .font(MenoFont.caption)
                                .foregroundStyle(MenoColor.inkTertiary)
                        }
                    }
                }
                .padding(.horizontal, MenoSpace.gutter)
                .padding(.bottom, MenoSpace.xxl)
            }
            .background { MenoBrandBackdrop() }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button("Save to journal", systemImage: "checkmark") { if let selected { store.addSymptom(selected, intensity: intensity, note: note) }; dismiss() }
                    .buttonStyle(MenoPrimaryButtonStyle())
                    .disabled(selected == nil)
                    .opacity(selected == nil ? 0.45 : 1)
                    .padding(.horizontal, MenoSpace.gutter)
                    .padding(.vertical, MenoSpace.m)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) { MenoRule() }
            }
            .navigationTitle("Quick log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct SymptomChip: View {
    let symptom: Symptom
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenoSpace.s) {
                Image(systemName: symptom.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? MenoColor.primary : MenoColor.inkSecondary)
                Text(symptom.rawValue)
                    .font(MenoFont.body)
                    .foregroundStyle(MenoColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MenoSpace.m)
            .frame(maxWidth: .infinity, minHeight: MenoMetric.touchTarget + 4, alignment: .leading)
            .background(isSelected
                        ? LinearGradient(colors: [MenoColor.primarySoft, MenoColor.accentSoft.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [MenoColor.surface, MenoColor.primarySoft.opacity(0.34)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous)
                    .strokeBorder(isSelected ? MenoColor.primary : MenoColor.rule,
                                  lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Named stops rather than five bare numbers — "4" meant nothing to the person logging
/// it, or to the clinician reading the export six weeks later.
private struct IntensityPicker: View {
    @Binding var intensity: Intensity

    var body: some View {
        VStack(spacing: MenoSpace.s) {
            HStack(spacing: MenoSpace.s) {
                ForEach(Intensity.allCases) { level in
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { intensity = level }
                    } label: {
                        Capsule()
                            .fill(level.rawValue <= intensity.rawValue ? MenoColor.primary : MenoColor.surfaceAlt)
                            .frame(height: 10)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: MenoMetric.touchTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(level.label)
                    .accessibilityAddTraits(level == intensity ? [.isButton, .isSelected] : .isButton)
                }
            }
            HStack {
                Text(Intensity.mild.label)
                Spacer()
                Text(Intensity.severe.label)
            }
            .font(MenoFont.caption)
            .foregroundStyle(MenoColor.inkSecondary)
            .accessibilityHidden(true)
        }
    }
}
