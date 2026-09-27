import SwiftUI

extension CycleSignal {
    /// Which part of the person's life the observation comes from - shown as a
    /// small chip so a list mixing temperature, sleep and test factors scans.
    var category: String {
        switch id {
        case "temperatureShift", "sustainedHighTemperature", "noTemperatureShiftYet", "possibleFever": "Temperature"
        case "fertileMucus", "healthLHSurge", "midCyclePain", "lutealSpotting", "periodLate", "longCycle": "Cycle"
        case "highFluidIntake", "pcosLH": "Test reading"
        case "hormonalContraception", "breastfeeding", "healthPregnancy": "Apple Health"
        case "shortSleep", "restingHeartRateUp", "hrvDown", "highTrainingLoad": "Lifestyle"
        case "weightChange", "bmi": "Body"
        default: "Insight"
        }
    }

    var toneLabel: String {
        switch tone {
        case .attention: "Worth a look"
        case .positive: "Good sign"
        case .info: "Good to know"
        }
    }

    var toneColors: [Color] {
        switch tone {
        case .attention: [Color.linePink, Color(red: 0.93, green: 0.30, blue: 0.62)]
        case .positive: [Color.linePurple, Color(red: 0.55, green: 0.36, blue: 0.96)]
        case .info: [Color.lineBlue, Color(red: 0.36, green: 0.56, blue: 0.98)]
        }
    }
}

/// One observation: its tone ("Worth a look"...), the title, and the
/// explanation - two lines until tapped open.
struct CycleSignalRow: View {
    let signal: CycleSignal
    let isExpanded: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(signal.toneLabel)
                        .font(.app(size: LineType.size(11), weight: .heavy))
                        .foregroundStyle(signal.toneColors.first ?? .linePurple)
                    Text(signal.title)
                        .font(.app(size: LineType.size(15), weight: .heavy))
                        .foregroundStyle(Color.lineNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(signal.detail)
                        .font(.app(.caption))
                        .foregroundStyle(Color.lineNavy.opacity(0.7))
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: LineType.size(12), weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.35))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .padding(.top, 2)
            }
            .padding(14)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke((signal.toneColors.first ?? .clear).opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Collapses the explanation" : "Shows the full explanation")
    }
}

/// The compact version under a test result: "What may affect this reading".
struct CycleSignalsCard: View {
    let title: String
    let signals: [CycleSignal]

    @State private var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "sparkles")
                .font(.app(.headline, weight: .bold))
                .foregroundStyle(Color.lineNavy)
                .symbolRenderingMode(.hierarchical)
            ForEach(signals) { signal in
                CycleSignalRow(signal: signal, isExpanded: expandedID == signal.id) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        expandedID = expandedID == signal.id ? nil : signal.id
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.linePurpleSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Home's info popup: what LineCheck has noticed in the person's data today.
struct BodySignalsPopup: View {
    let signals: [CycleSignal]
    var onAskLuna: () -> Void
    var onClose: () -> Void
    /// Set when Apple Health isn't connected yet.
    var onConnectHealth: (() -> Void)?

    private var summary: String {
        let attention = signals.filter { $0.tone == .attention }.count
        if signals.isEmpty { return "Nothing to flag today" }
        if attention > 0 { return attention == 1 ? "1 thing worth a look today" : "\(attention) things worth a look today" }
        return signals.count == 1 ? "1 thing noticed today" : "\(signals.count) things noticed today"
    }

    var body: some View {
        BrandedModalCard {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("What your body\nis telling us")
                        .font(.app(size: LineType.size(26), weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(colors: [Color.linePurple, Color.linePink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .lineSpacing(-2)
                    Text(summary)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                }
                .multilineTextAlignment(.center)
                // Popups propose a tight height; without this the title
                // truncates at larger text sizes instead of wrapping.
                .fixedSize(horizontal: false, vertical: true)

                if signals.isEmpty {
                    Text("MenoPlan keeps an eye on your cycle, daily log and Apple Health, and anything worth knowing will show up here.")
                        .font(.app(.subheadline))
                        .foregroundStyle(Color.lineNavy.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                                if index > 0 {
                                    Divider().overlay(Color.lineNavy.opacity(0.08)).padding(.vertical, 12)
                                }
                                VStack(alignment: .center, spacing: 4) {
                                    Text(signal.toneLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .font(.app(size: LineType.size(11), weight: .heavy))
                                        .foregroundStyle(signal.toneColors.first ?? .linePurple)
                                    Text(signal.title)
                                        .font(.app(size: LineType.size(16), weight: .heavy))
                                        .foregroundStyle(Color.lineNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(signal.detail)
                                        .font(.app(.subheadline))
                                        .foregroundStyle(Color.lineNavy.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 340)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let onConnectHealth {
                    VStack(spacing: 8) {
                        Text("Connect Apple Health and MenoPlan can spot more, like a temperature rise that backs up ovulation or sleep that could delay it.")
                            .font(.app(.caption))
                            .foregroundStyle(Color.lineNavy.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onConnectHealth) {
                            Label("Connect Apple Health", systemImage: "heart.fill")
                                .font(.app(.subheadline, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.secondaryLine)
                    }
                }

                VStack(spacing: 8) {
                    if !signals.isEmpty {
                        Button("Ask Luna", action: onAskLuna)
                            .buttonStyle(.primaryLine)
                    }
                    Button("Close", action: onClose)
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                        .frame(minHeight: 40)
                }
            }
            .padding(22)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Home's occasional reminder that Apple Health can be connected.
struct HealthConnectPromptPopup: View {
    var onConnect: () -> Void
    var onNotNow: () -> Void
    var onNeverAsk: () -> Void

    var body: some View {
        BrandedModalCard {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Connect Apple Health")
                        .font(.app(size: LineType.size(24), weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [Color.linePurple, Color.linePink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Let MenoPlan fill in your calendar and spot patterns for you. It's free.")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.6))
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    benefit("Periods, temperatures and symptoms appear automatically")
                    benefit("A temperature rise can confirm ovulation and sharpen predictions")
                    benefit("What you log here is saved back to Health")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    Button("Connect Apple Health", action: onConnect)
                        .buttonStyle(.primaryLine)
                    Button("Not now", action: onNotNow)
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(Color.lineNavy.opacity(0.55))
                        .frame(minHeight: 36)
                    Button("Don't ask again", action: onNeverAsk)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(Color.lineNavy.opacity(0.4))
                }
            }
            .padding(22)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: LineType.size(15), weight: .bold))
                .foregroundStyle(Color.linePurple)
            Text(text)
                .font(.app(.subheadline))
                .foregroundStyle(Color.lineNavy.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
