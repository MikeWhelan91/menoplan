import SwiftUI

// MARK: - Surfaces

extension View {
    /// The standard card: white surface, hairline definition, a shadow soft enough to
    /// read as lift rather than as decoration, and none of it in dark mode.
    func menoCard(padding: CGFloat = MenoSpace.l,
                  background: Color = MenoColor.surface) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [background.opacity(0.98), MenoColor.primarySoft.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous)
                    .strokeBorder(MenoColor.rule, lineWidth: MenoMetric.hairline)
            }
            .shadow(color: MenoColor.primary.opacity(0.09), radius: 11, y: 4)
    }
}

/// Shared atmospheric backdrop, adapted from Linecheck's soft colour-orb treatment.
struct MenoBrandBackdrop: View {
    var body: some View {
        ZStack {
            MenoColor.canvas
            Circle().fill(MenoColor.accent.opacity(0.12)).frame(width: 330, height: 330).blur(radius: 5).offset(x: 190, y: -310)
            Circle().fill(MenoColor.primary.opacity(0.09)).frame(width: 300, height: 300).blur(radius: 6).offset(x: -210, y: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// One scaffold for every screen, so margins and rhythm cannot drift apart.
struct MenoScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MenoSpace.l) {
                VStack(alignment: .leading, spacing: MenoSpace.xs) {
                    Text(title)
                        .font(MenoFont.display)
                        .foregroundStyle(MenoColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(MenoFont.secondary)
                            .foregroundStyle(MenoColor.inkSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, MenoSpace.xs)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MenoSpace.gutter)
            .padding(.top, MenoSpace.s)
            .padding(.bottom, 96)
        }
        .background { MenoBrandBackdrop() }
        .scrollIndicators(.hidden)
    }
}

struct MenoRule: View {
    var body: some View {
        Rectangle()
            .fill(MenoColor.rule)
            .frame(height: MenoMetric.hairline)
            .accessibilityHidden(true)
    }
}

/// A titled card. Weight and colour separate the heading from the content — no
/// letterspaced micro-caps, which are the first thing to become unreadable.
struct MenoSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    var trailing: String? = nil
    var padding: CGFloat = MenoSpace.l
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MenoSpace.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(MenoFont.heading)
                    .foregroundStyle(MenoColor.ink)
                Spacer(minLength: MenoSpace.s)
                if let trailing {
                    Text(trailing)
                        .font(MenoFont.caption)
                        .foregroundStyle(MenoColor.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let detail {
                Text(detail)
                    .font(MenoFont.secondary)
                    .foregroundStyle(MenoColor.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .menoCard(padding: padding)
    }
}

// MARK: - Buttons

struct MenoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MenoFont.body.weight(.semibold))
            .foregroundStyle(MenoColor.onPrimary)
            .frame(maxWidth: .infinity, minHeight: MenoMetric.touchTarget)
            .padding(.vertical, MenoSpace.m)
            .background(LinearGradient(colors: [MenoColor.primary, MenoColor.accent], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct MenoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MenoFont.body.weight(.semibold))
            .foregroundStyle(MenoColor.primary)
            .frame(maxWidth: .infinity, minHeight: MenoMetric.touchTarget)
            .padding(.vertical, MenoSpace.m)
            .background(MenoColor.surface.opacity(0.88),
                        in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous)
                    .strokeBorder(MenoColor.rule, lineWidth: MenoMetric.hairline)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Data display

struct MenoMetricView: View {
    let value: String
    let label: String
    var unit: String? = nil
    /// Word values ("High", "Clear") read as shouting at numeral scale.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: MenoSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: MenoSpace.xs) {
                Text(value)
                    .font(compact ? MenoFont.metricSmall : MenoFont.metric)
                    .foregroundStyle(MenoColor.ink)
                if let unit {
                    Text(unit)
                        .font(MenoFont.caption)
                        .foregroundStyle(MenoColor.inkSecondary)
                }
            }
            Text(label)
                .font(MenoFont.caption)
                .foregroundStyle(MenoColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A quiet status badge. Sentence case, generous padding, readable at a glance.
struct MenoBadge: View {
    let text: String
    var icon: String? = nil
    var tint: Color = MenoColor.primary

    var body: some View {
        HStack(spacing: MenoSpace.xs + 2) {
            if let icon {
                Image(systemName: icon).font(.footnote.weight(.semibold))
            }
            Text(text).font(MenoFont.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, MenoSpace.s + 2)
        .padding(.vertical, MenoSpace.xs)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// The row shared by every list in the app.
struct MenoRow: View {
    let title: String
    let detail: String
    var icon: String? = nil
    var accessory: String? = "chevron.right"

    var body: some View {
        HStack(spacing: MenoSpace.m) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MenoColor.primary)
                    .frame(width: 32, height: 32)
                    .background(MenoColor.primarySoft,
                                in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
            }
            VStack(alignment: .leading, spacing: MenoSpace.xxs) {
                Text(title)
                    .font(MenoFont.body.weight(.medium))
                    .foregroundStyle(MenoColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(MenoFont.caption)
                    .foregroundStyle(MenoColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let accessory {
                Image(systemName: accessory)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MenoColor.inkTertiary)
            }
        }
        .padding(.vertical, MenoSpace.s)
        .frame(minHeight: MenoMetric.touchTarget)
        .contentShape(.rect)
    }
}

/// Regulatory framing. It appears wherever a reading does, so it is a component.
struct MenoDisclaimer: View {
    var text: String = "Not a diagnosis. FSH levels vary naturally from day to day — please discuss your symptoms and your full test series with a healthcare professional."

    var body: some View {
        HStack(alignment: .top, spacing: MenoSpace.m) {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenoColor.inkTertiary)
            Text(text)
                .font(MenoFont.caption)
                .foregroundStyle(MenoColor.inkSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MenoSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MenoColor.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
    }
}
