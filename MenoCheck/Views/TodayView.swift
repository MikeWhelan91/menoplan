import SwiftUI

/// Linecheck's Home composition, translated to FSH check-ins.
struct TodayView: View {
    @EnvironmentObject private var store: MenoStore
    @EnvironmentObject private var health: MenoHealthStore
    @State private var showScanner = false
    @State private var showLog = false
    @State private var showDailyCheckIn = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                journeyOverview

                VStack(spacing: 14) {
                    dailyCheckInCard
                    scanTile
                }

                quickLinks
                reminderCard
                recentChecksCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 100)
        }
        .background { MenoBrandBackdrop() }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showScanner) { FSHCheckStartView() }
        .sheet(isPresented: $showLog) { SymptomLogView() }
        .sheet(isPresented: $showDailyCheckIn) { MenoDayEditor(date: .now) }
        .task { await health.refresh() }
    }

    private var isTodayLogged: Bool {
        store.dailyRecords[MenoStore.dayKey(.now)] != nil
    }

    private var dailyCheckInCard: some View {
        Button { showDailyCheckIn = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isTodayLogged ? MenoColor.positive : .white)
                        .frame(width: 46, height: 46)
                    Image(systemName: isTodayLogged ? "checkmark" : "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isTodayLogged ? .white : MenoColor.primary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(MenoColor.onPrimary.opacity(0.72))
                    Text(Calendar.current.isDateInToday(store.selectedCalendarDate) ? "Today's check-in" : "Quick daily check-in")
                        .font(.subheadline.weight(.bold)).foregroundStyle(MenoColor.onPrimary)
                    Text(checkInDetail)
                        .font(.footnote).foregroundStyle(MenoColor.onPrimary.opacity(0.86))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(MenoColor.onPrimary.opacity(0.85))
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(LinearGradient(colors: [MenoColor.primary, MenoColor.primary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
            .shadow(color: MenoColor.primary.opacity(0.22), radius: 12, y: 5)
        }.buttonStyle(.plain)
    }

    private var checkInDetail: String {
        if let sleep = health.lastNightSleepHours {
            return "Apple Health found \(sleep.formatted(.number.precision(.fractionLength(1))))h sleep — add it to today"
        }
        return isTodayLogged ? "Logged — tap to update today's record" : "Log symptoms, sleep and medication in under a minute"
    }

    private var journeyOverview: some View {
        VStack(spacing: 10) {
            Text("\(greeting), \(store.profile.name.isEmpty ? "there" : store.profile.name)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(MenoColor.ink)
                .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text("Your FSH check-in series")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MenoColor.ink)
                Text("Next test · tomorrow morning")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MenoColor.accent)
            }
            MenoSeriesCurve().padding(.top, 4)
            Text("\(store.fshReadings.count) readings saved · spacing helps show the fuller picture")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenoColor.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanTile: some View {
        Button { showScanner = true } label: {
            GeometryReader { proxy in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("FSH Test Check")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(MenoColor.accent)
                        Text("Scan a home menopause test")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(MenoColor.ink.opacity(0.82))
                    }
                    .frame(width: min(max(proxy.size.width * 0.56, 185), 224), alignment: .leading)
                    .layoutPriority(1)
                    MenoHomeTestIllustration()
                        .frame(width: max(88, proxy.size.width * 0.3), height: 84)
                        .allowsHitTesting(false)
                }
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 104)
            .background(LinearGradient(colors: [MenoColor.accentSoft, MenoColor.primarySoft.opacity(0.68), MenoColor.surface], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous).stroke(MenoColor.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("FSH Test Check")
    }

    private var quickLinks: some View {
        HStack(spacing: 12) {
            homeLink("Trends", icon: "chart.line.uptrend.xyaxis", tint: MenoColor.primary, action: { store.selectedTab = 2 })
            homeLink("Compare", icon: "rectangle.on.rectangle", tint: MenoColor.accent, action: { store.selectedTab = 1 })
            homeLink("Ask Luna", icon: "bubble.left.and.bubble.right.fill", tint: MenoColor.primary, action: { store.selectedTab = 3 })
        }
    }

    private func homeLink(_ title: String, icon: String, tint: Color, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint).frame(height: 32)
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(MenoColor.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(LinearGradient(colors: [MenoColor.surface.opacity(0.96), tint.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous).stroke(tint.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private var reminderCard: some View {
        Button { showScanner = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge.fill").font(.body).foregroundStyle(MenoColor.primary).frame(width: 44, height: 40).background(MenoColor.primarySoft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("FSH test reminder").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(MenoColor.ink)
                    Text("Tomorrow · 07:30").font(.footnote.weight(.medium)).foregroundStyle(MenoColor.inkSecondary)
                }
                Spacer(minLength: 8); Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(MenoColor.primary.opacity(0.65))
            }
            .padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 60)
            .background(LinearGradient(colors: [MenoColor.surface.opacity(0.94), MenoColor.primary.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous).stroke(MenoColor.primary.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var recentChecksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Recent checks").font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(MenoColor.ink); Spacer(); Text("View all").font(.footnote.weight(.bold)).foregroundStyle(MenoColor.primary) }
            VStack(spacing: 0) {
                ForEach(Array(store.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.icon).foregroundStyle(MenoColor.primary).frame(width: 44, height: 40).background(MenoColor.primarySoft, in: RoundedRectangle(cornerRadius: MenoMetric.radiusSmall, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) { Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(MenoColor.ink); Text(entry.detail ?? entry.time).font(.footnote).foregroundStyle(MenoColor.inkSecondary) }
                        Spacer(); MenoBadge(text: entry.time, tint: MenoColor.accent)
                    }
                    .padding(.vertical, 11)
                    if index < 2 { Divider().padding(.leading, 56) }
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [MenoColor.surface.opacity(0.96), MenoColor.primary.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous).stroke(MenoColor.primary.opacity(0.13)))
    }
}

private struct MenoSeriesCurve: View {
    @EnvironmentObject private var store: MenoStore
    var body: some View {
        VStack(spacing: 6) {
            HStack { Text("Reading 1").font(.footnote.weight(.bold)).foregroundStyle(MenoColor.inkSecondary); Spacer(); Text("Next reading").font(.footnote.weight(.bold)).foregroundStyle(MenoColor.primary) }
            TracePlot(values: store.fshReadings.count < 2 ? [0.42, 0.42] : store.fshReadings.reversed().map(\.testLineStrength)).frame(height: 56)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(MenoColor.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
    }
}

/// A label-free thumbnail, matching Linecheck's photographic hero treatment.
private struct MenoHomeTestIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
            HStack(spacing: 10) {
                Circle().stroke(MenoColor.inkTertiary.opacity(0.65), lineWidth: 2).frame(width: 26, height: 26)
                RoundedRectangle(cornerRadius: 8).fill(MenoColor.primarySoft).frame(width: 70, height: 38)
                    .overlay {
                        HStack(spacing: 16) {
                            Capsule().fill(MenoColor.accent).frame(width: 6, height: 28)
                            Capsule().fill(MenoColor.primary).frame(width: 6, height: 28)
                        }
                    }
            }
        }
        .rotationEffect(.degrees(-5))
    }
}
