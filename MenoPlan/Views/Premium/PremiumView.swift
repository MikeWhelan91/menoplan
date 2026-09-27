import RevenueCat
import SwiftData
import SwiftUI

private enum LineCheckPlanCycle: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .lifetime: "Lifetime"
        }
    }

    var productID: String {
        switch self {
        case .monthly: "menoplan_pro_monthly"
        case .yearly: "menoplan_pro_yearly"
        case .lifetime: "menoplan_pro_lifetime"
        }
    }
}

private struct LineCheckPlanOption: Identifiable, Hashable {
    let id: String
    let cycle: LineCheckPlanCycle
    let badge: String?

    static let all: [LineCheckPlanOption] = [
        .init(id: LineCheckPlanCycle.yearly.productID, cycle: .yearly, badge: "Best value"),
        .init(id: LineCheckPlanCycle.monthly.productID, cycle: .monthly, badge: nil),
        .init(id: LineCheckPlanCycle.lifetime.productID, cycle: .lifetime, badge: "One-time")
    ]
}

private struct PremiumFeature: Identifiable {
    let id = UUID()
    let symbol: String
    var imageName: String? = nil
    let title: String
    let detail: String
    var isExpandable: Bool = false
}

private let premiumFeatures: [PremiumFeature] = [
    .init(symbol: "moon.fill", imageName: "LunaCheckIcon", title: "Unlimited Luna tools", detail: "Checks, comparisons and chat."),
    .init(symbol: "doc.text.fill", title: "Doctor Visit Reports", detail: "Share a clear fertility PDF.", isExpandable: true),
    .init(symbol: "calendar.badge.clock", title: "Luna Weekly Reports", detail: "Personal guidance, every week.", isExpandable: true),
    .init(symbol: "chart.xyaxis.line", imageName: "HomeTrendsIcon", title: "Full fertility trends", detail: "Pregnancy line, OPK, BBT and cycle-signal charts."),
    .init(symbol: "sparkles.rectangle.stack", title: "AI Progression Analysis", detail: "Choose 3+ saved tests and get a plain-language trend summary."),
    .init(symbol: "nosign", title: "No ads", detail: "An uninterrupted experience.")
]

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lineLayout) private var layout
    @Environment(AppState.self) private var appState
    @Query private var settingsQuery: [UserSettings]
    @StateObject private var purchase = PurchaseService.shared
    @State private var selectedPlan = LineCheckPlanOption.all[0]
    @State private var showAllFeatures = false

    /// Overrides the close behavior for callers that present this as a step
    /// in a larger flow (onboarding) rather than a modal - calling this
    /// instead of the environment `dismiss()` lets the presenter tear down
    /// the whole flow in one transition instead of first revealing whatever
    /// sat behind the modal.
    var onRequestDismiss: (() -> Void)? = nil

    private func closeScreen() {
        if let onRequestDismiss {
            onRequestDismiss()
        } else {
            dismiss()
        }
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 680
            let topPadding: CGFloat = compact ? 24 : 34
            let bottomPadding = max(18, geo.safeAreaInsets.bottom + 12)

            ZStack(alignment: .topTrailing) {
                LineCheckBrandBackdrop()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        titleBlock(compact: compact)

                        Spacer(minLength: compact ? 10 : 16)

                        featuresCard(compact: compact)

                        Spacer(minLength: compact ? 10 : 18)

                        planPicker(compact: compact)

                        Spacer(minLength: compact ? 8 : 12)

                        pricingCopy(compact: compact)

                        Spacer(minLength: compact ? 8 : 12)

                        ctaButton(compact: compact)

                        Spacer(minLength: compact ? 6 : 10)

                        restoreButton(compact: compact)
                    }
                    .frame(
                        maxWidth: layout.isRegular ? 700 : 620,
                        minHeight: max(0, geo.size.height - topPadding - bottomPadding),
                        alignment: .top
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                topBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.light)
        .presentationSizing(.page)
        .task {
            AppAnalytics.log("linecheck_paywall_shown", ["source": appState.paywallSource ?? "unknown"])
            appState.paywallSource = nil
            await purchase.loadProducts()
        }
    }

    /// This screen's type was tuned to fit a cramped phone sheet. On iPad it is
    /// presented as a full page sheet with room to spare, so it takes a further
    /// step up on top of the app-wide iPad scale — otherwise the feature list
    /// reads as fine print on a very large surface.
    private func paywallSize(_ points: CGFloat) -> CGFloat {
        LineType.size(points * (layout.isRegular ? 1.35 : 1))
    }

    /// Same idea for the boxes the type sits in.
    private func paywallMetric(_ points: CGFloat) -> CGFloat {
        layout.isRegular ? points * 1.35 : points
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                closeScreen()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: paywallSize(14), weight: .bold))
                    .foregroundStyle(Color.lineNavy.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.76), in: Circle())
                    .overlay(Circle().stroke(Color.linePurple.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 20)
        }
    }

    private func titleBlock(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 9) {
            AppIconBrandMark(size: compact ? 58 : 72)

            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Meno")
                        .foregroundStyle(Color.lineNavy)
                    Text("Plan")
                        .foregroundStyle(Color.linePink)
                    Text(" Pro")
                        .foregroundStyle(Color.linePurple)
                }
                .font(.app(size: paywallSize(compact ? 29 : 34), weight: .heavy))

                Text("More confidence when a line is hard to read")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lineNavy.opacity(0.66))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func featuresCard(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 7) {
            ForEach(premiumFeatures) { feature in
                if showAllFeatures || feature.isExpandable == false {
                    featureRow(feature, compact: compact)
                }
            }

            if premiumFeatures.contains(where: { $0.isExpandable }) {
                Button {
                    withAnimation(.snappy) {
                        showAllFeatures.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllFeatures ? "See less" : "See more")
                        Image(systemName: showAllFeatures ? "chevron.up" : "chevron.down")
                            .font(.system(size: paywallSize(10), weight: .bold))
                    }
                    .font(.app(size: paywallSize(compact ? 12.5 : 13.5), weight: .semibold))
                    .foregroundStyle(Color.linePurple)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func featureRow(_ feature: PremiumFeature, compact: Bool) -> some View {
        let tint = featureTint(feature)
        return HStack(spacing: 10) {
            Group {
                if let imageName = feature.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: paywallMetric(18), height: paywallMetric(16))
                } else {
                    Image(systemName: feature.symbol)
                        .font(.system(size: paywallSize(12), weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: paywallMetric(27), height: paywallMetric(27))
            .background(Color.white.opacity(0.78), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.app(size: paywallSize(compact ? 14 : 15.5), weight: .bold))
                    .foregroundStyle(Color.lineNavy)
                    .lineLimit(1)
                Text(feature.detail)
                    .font(.app(size: paywallSize(compact ? 11 : 12.5), weight: .medium))
                    .foregroundStyle(Color.lineNavy.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "checkmark")
                .font(.system(size: paywallSize(10), weight: .black))
                .foregroundStyle(tint)
                .frame(width: paywallMetric(27), height: paywallMetric(27))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 7 : 8)
        .background(tint.opacity(0.085), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func featureTint(_ feature: PremiumFeature) -> Color {
        guard let index = premiumFeatures.firstIndex(where: { $0.id == feature.id }) else {
            return .linePurple
        }
        return index.isMultiple(of: 2) ? .linePink : .linePurple
    }

    private func planPicker(compact: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(LineCheckPlanOption.all) { plan in
                Button {
                    selectedPlan = plan
                } label: {
                    VStack(spacing: compact ? 4 : 6) {
                        if let badge = badgeText(for: plan) {
                            Text(badge)
                                .font(.app(.caption2, weight: .bold))
                                .foregroundStyle(selectedPlan.id == plan.id ? .white : Color.lineNavy)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedPlan.id == plan.id ? Color.linePink : Color.linePink.opacity(0.12), in: Capsule())
                        } else {
                            Spacer().frame(height: 16)
                        }

                        Text(plan.cycle.title)
                            .font(.lineSubheadline(.semibold))
                            .foregroundStyle(selectedTextColor(for: plan))

                        Text(displayPrice(for: plan))
                            .font(.app(size: paywallSize(compact ? 18 : 21), weight: .bold))
                            // Real prices are short, but a long localized price
                            // or a "Not available" fallback must shrink rather
                            // than wrap and push the CTA off the sheet.
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .foregroundStyle(selectedTextColor(for: plan))

                        Text(planSubtitle(for: plan))
                            .font(.app(.caption))
                            .foregroundStyle(selectedSecondaryTextColor(for: plan))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: paywallMetric(compact ? 88 : 108))
                    .padding(.horizontal, 8)
                    .padding(.vertical, compact ? 6 : 9)
                    .background(planBackground(for: plan), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(planStroke(for: plan), lineWidth: selectedPlan.id == plan.id ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pricingCopy(compact: Bool) -> some View {
        VStack(spacing: 4) {
            Text(billingCopy(for: selectedPlan))
                .font((compact ? Font.caption : .subheadline).weight(.semibold))
                .foregroundStyle(Color.lineNavy.opacity(0.82))
                .multilineTextAlignment(.center)

            if let message = purchaseMessage, message.isEmpty == false {
                Text(message)
                    .font(.app(.caption))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func ctaButton(compact: Bool) -> some View {
        Button {
            Task {
                await buySelectedPlan()
            }
        } label: {
            Group {
                if purchase.state == .loading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(ctaTitle(for: selectedPlan))
                        .font(.app(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.primaryLine)
        .frame(maxWidth: layout.isRegular ? 420 : .infinity)
        .frame(maxWidth: .infinity)
        .disabled(purchaseProduct(for: selectedPlan) == nil)
        .opacity(purchaseProduct(for: selectedPlan) == nil ? 0.6 : 1)
    }

    private func restoreButton(compact: Bool) -> some View {
        Button("Restore Purchases") {
            Task { await restore() }
        }
        .buttonStyle(.plain)
        .font(compact ? .caption : .subheadline)
        .foregroundStyle(Color.lineNavy.opacity(0.62))
    }

    private var purchaseMessage: String? {
        switch purchase.state {
        case .failed:
            return "Purchase unavailable right now."
        case .unavailable:
            return "Subscription options are not available right now."
        default:
            return nil
        }
    }

    private func purchaseProduct(for plan: LineCheckPlanOption) -> Package? {
        purchase.packages.first { $0.storeProduct.productIdentifier == plan.cycle.productID }
    }

    private func storeProduct(for cycle: LineCheckPlanCycle) -> StoreProduct? {
        purchase.packages.first { $0.storeProduct.productIdentifier == cycle.productID }?.storeProduct
    }

    /// Yearly's savings vs. paying monthly for a year, computed from the
    /// actual loaded prices rather than a hardcoded guess so it never drifts
    /// out of sync with a real price change in App Store Connect.
    private var yearlySavingsPercent: Int? {
        guard let yearlyPerMonth = storeProduct(for: .yearly)?.pricePerMonth?.doubleValue,
              let monthlyPrice = storeProduct(for: .monthly)?.price,
              monthlyPrice > 0 else { return nil }
        let percent = Int(((1 - yearlyPerMonth / (monthlyPrice as NSDecimalNumber).doubleValue) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    private func badgeText(for plan: LineCheckPlanOption) -> String? {
        if plan.cycle == .yearly, let percent = yearlySavingsPercent {
            return "Save \(percent)%"
        }
        return plan.badge
    }

    private func planSubtitle(for plan: LineCheckPlanOption) -> String {
        switch plan.cycle {
        case .yearly:
            return "Billed yearly"
        case .monthly:
            return "Month to month"
        case .lifetime:
            return "One-time"
        }
    }

    private func planBackground(for plan: LineCheckPlanOption) -> some ShapeStyle {
        if selectedPlan.id == plan.id {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.linePurple, .linePink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color.white.opacity(0.78), Color.linePurpleSoft.opacity(0.66)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func planStroke(for plan: LineCheckPlanOption) -> Color {
        selectedPlan.id == plan.id ? Color.white.opacity(0.72) : Color.linePurple.opacity(0.16)
    }

    private func selectedTextColor(for plan: LineCheckPlanOption) -> Color {
        selectedPlan.id == plan.id ? .white : Color.lineNavy
    }

    private func selectedSecondaryTextColor(for plan: LineCheckPlanOption) -> Color {
        selectedPlan.id == plan.id ? .white.opacity(0.84) : Color.lineNavy.opacity(0.58)
    }

    private func displayPrice(for plan: LineCheckPlanOption) -> String {
        if let product = purchaseProduct(for: plan) {
            return product.localizedPriceString
        }

        return "Not available"
    }

    private func billingCopy(for plan: LineCheckPlanOption) -> String {
        let price = displayPrice(for: plan)
        let perWeek = storeProduct(for: plan.cycle)?.localizedPricePerWeek
        switch plan.cycle {
        case .monthly:
            if let perWeek {
                return "\(price) billed monthly - about \(perWeek)/week."
            }
            return "\(price) billed monthly."
        case .yearly:
            if let perWeek {
                return "\(price) billed yearly - about \(perWeek)/week."
            }
            return "\(price) billed yearly."
        case .lifetime:
            return "\(price) one-time purchase."
        }
    }

    private func ctaTitle(for plan: LineCheckPlanOption) -> String {
        switch plan.cycle {
        case .monthly:
            return "Start monthly"
        case .yearly:
            return "Unlock yearly"
        case .lifetime:
            return "Unlock lifetime"
        }
    }

    private func buySelectedPlan() async {
        guard let settings = UserSettings.canonical(from: settingsQuery) else { return }
        if let product = purchaseProduct(for: selectedPlan) {
            let outcome = await purchase.purchase(product, settings: settings)
            switch outcome {
            case .success:
                AppAnalytics.log("linecheck_purchase_completed", [
                    "product_id": product.storeProduct.productIdentifier,
                    "cycle": selectedPlan.cycle.rawValue
                ])
                appState.toast = "Pro unlocked"
                closeScreen()
            case .pending:
                AppAnalytics.log("linecheck_purchase_pending", [
                    "product_id": product.storeProduct.productIdentifier,
                    "cycle": selectedPlan.cycle.rawValue
                ])
                appState.toast = "Purchase pending approval"
            case .cancelled:
                AppAnalytics.log("linecheck_purchase_cancelled", [
                    "product_id": product.storeProduct.productIdentifier,
                    "cycle": selectedPlan.cycle.rawValue
                ])
            case .failed:
                AppAnalytics.log("linecheck_purchase_failed", [
                    "product_id": product.storeProduct.productIdentifier,
                    "cycle": selectedPlan.cycle.rawValue
                ])
                appState.toast = "Purchase unavailable"
            }
            return
        }
        appState.toast = "Purchase unavailable"
    }

    private func restore() async {
        guard let settings = UserSettings.canonical(from: settingsQuery) else { return }
        AppAnalytics.log("linecheck_restore_purchases_tapped")
        let restored = await purchase.restore(settings: settings)
        if restored {
            AppAnalytics.log("linecheck_restore_purchases_succeeded")
        }
        appState.toast = restored ? "Purchase restored" : "Purchase unavailable"
    }

}
