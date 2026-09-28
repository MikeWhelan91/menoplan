import SwiftUI

/// "What's affecting you most?" - up to five symptoms pinned to Home's
/// check-in, from the suggestions or the person's own words.
struct FocusSymptomPicker: View {
    @Binding var selection: [String]
    @State private var customText = ""
    @FocusState private var customFocused: Bool

    private var options: [String] {
        FocusSymptoms.suggested + selection.filter { !FocusSymptoms.suggested.contains($0) }
    }
    private var isFull: Bool { selection.count >= FocusSymptoms.maximum }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
            HStack(spacing: 8) {
                TextField("Add your own", text: $customText)
                    .focused($customFocused)
                    .submitLabel(.done)
                    .onSubmit(addCustom)
                    .font(.app(.subheadline))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.9), in: Capsule())
                    .overlay(Capsule().stroke(Color.lineNavy.opacity(0.08)))
                Button("Add", action: addCustom)
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.linePurple)
                    .disabled(trimmedCustom.isEmpty || isFull)
            }
            Text(isFull ? "That's five. Tap one to swap it out." : "Pick up to five. You can change these anytime.")
                .font(.app(.caption))
                .foregroundStyle(Color.lineNavy.opacity(0.55))
                .contentTransition(.opacity)
        }
        .animation(.snappy, value: selection)
    }

    private var trimmedCustom: String { customText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func addCustom() {
        let name = trimmedCustom.prefix(1).uppercased() + trimmedCustom.dropFirst()
        guard !name.isEmpty, !isFull else { return }
        if let match = options.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            if !selection.contains(match) { selection.append(match) }
        } else {
            selection.append(name)
        }
        customText = ""
        customFocused = false
    }

    private func chip(_ option: String) -> some View {
        let selected = selection.contains(option)
        let disabled = !selected && isFull
        return Button {
            if selected { selection.removeAll { $0 == option } } else if !isFull { selection.append(option) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark" : FocusSymptoms.symbol(for: option))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? Color.white : Color.linePurple)
                    .frame(width: 24, height: 24)
                    .background(selected ? Color.linePurple : Color.linePurple.opacity(0.12), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Text(option)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(selected ? Color.linePurple : Color.lineNavy.opacity(0.8))
            }
            .padding(.leading, 5)
            .padding(.trailing, 13)
            .padding(.vertical, 5)
            .background(selected ? Color.linePurple.opacity(0.14) : Color.white.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.linePurple.opacity(0.7) : Color.lineNavy.opacity(0.06), lineWidth: 1.2))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Home and Settings wrap the picker in a sheet.
struct FocusSymptomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String]
    var onSave: ([String]) -> Void

    init(initial: [String], onSave: @escaping ([String]) -> Void) {
        _selection = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("These appear in your daily check-in and lead your appointment summary.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.65))
                    FocusSymptomPicker(selection: $selection)
                }
                .padding(20)
            }
            .background { LineCheckBrandBackdrop() }
            .navigationTitle("What's affecting you most?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(selection); dismiss() }
                        .fontWeight(.bold)
                        .disabled(selection.isEmpty)
                }
            }
        }
        .tint(Color.linePurple)
    }
}
