import SwiftUI

struct ChartTabItem: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    var iconAssetName: String? = nil
}

/// A single fixed chart in its own card - used where charts are stacked one after another
/// on the page instead of sharing one card behind a tab switcher, so every chart is visible
/// at once by scrolling rather than tapping between them.
struct ChartSectionCard<Content: View>: View {
    let title: String
    let icon: String
    var iconAssetName: String? = nil
    let tint: Color
    let helpTerm: String
    let helpExplanation: String
    /// Fixed height for content that needs a stable plot area (charts). Pass nil to let the
    /// card hug its content's natural size instead - for text-only content, a fixed height
    /// just leaves dead space above/below a couple of short lines.
    var contentHeight: CGFloat? = 300
    /// Shows a "PRO" badge in the title row when true. Purely cosmetic - the
    /// caller is responsible for actually gating the content itself (e.g.
    /// blurring it behind a lock button).
    var isLocked: Bool = false
    /// An optional compact control (e.g. a display-mode switcher) shown on
    /// the title row itself, trailing the help button - for something the
    /// user needs to see and reach for every time, not buried in the body.
    var titleAccessory: () -> AnyView = { AnyView(EmptyView()) }
    /// Tapping the content opens it full-screen at a taller height - most
    /// charts are squeezed into a small fixed card height on a page that
    /// stacks several of them, so there's no way to see fine detail without
    /// this. Defaults on; only text-only summary cards opt out.
    var allowsFullScreen: Bool = true
    @ViewBuilder var content: () -> Content

    @State private var showFullScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Group {
                    if let iconAssetName {
                        Image(iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 22)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: LineType.size(15), weight: .bold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10), in: Circle())
                Text(title)
                    .font(.app(size: LineType.size(16), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize()
                TermHelpButton(term: helpTerm, explanation: helpExplanation)
                titleAccessory()
                    .frame(maxWidth: .infinity)
                if isLocked {
                    Text("PRO")
                        .font(.app(.caption2, weight: .heavy))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.09), in: Capsule())
                }
            }
            content()
                .frame(minHeight: contentHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard allowsFullScreen, !isLocked else { return }
                    showFullScreen = true
                }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.white, tint.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.05)))
        .shadow(color: tint.opacity(0.10), radius: 22, y: 10)
        .fullScreenCover(isPresented: $showFullScreen) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        titleAccessory()
                        content()
                            .frame(minHeight: (contentHeight ?? 300) * 1.7)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
                .background { LineCheckBrandBackdrop() }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showFullScreen = false }
                    }
                }
            }
            .tint(tint)
        }
    }
}
