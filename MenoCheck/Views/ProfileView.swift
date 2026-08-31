import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: MenoStore
    var body: some View {
        MenoScreen(title: "Your profile", subtitle: "Add the context that makes your record useful in appointments.") {
            VStack(alignment: .leading, spacing: MenoSpace.xl) {
                profileHeader

                MenoSection(title: "About you") {
                    TextField("First name", text: $store.profile.name)
                    Divider()
                    TextField("Age (optional)", text: $store.profile.age).keyboardType(.numberPad)
                    Divider()
                    Picker("Menopause stage", selection: $store.profile.stage) {
                        Text("Not set").tag("Not set")
                        Text("Perimenopause").tag("Perimenopause")
                        Text("Postmenopause").tag("Postmenopause")
                        Text("Not sure").tag("Not sure")
                    }
                    Toggle("I use HRT", isOn: $store.profile.usesHRT)
                    MenoRule()
                    Picker("Main goal", selection: $store.profile.mainGoal) {
                        Text("Understand my symptoms").tag("Understand my symptoms")
                        Text("Sleep better").tag("Sleep better")
                        Text("Prepare for an appointment").tag("Prepare for an appointment")
                        Text("Understand HRT options").tag("Understand HRT options")
                    }
                }

                MenoSection(title: "Your record") {
                    HStack(spacing: MenoSpace.xxl) {
                        MenoMetricView(value: "\(store.fshReadings.count)", label: "FSH readings")
                        MenoMetricView(value: "\(store.dailyRecords.count)", label: "Daily records")
                        Spacer()
                    }
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: MenoSpace.m) {
            Text("A")
                .font(MenoFont.title)
                .foregroundStyle(MenoColor.onPrimary)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [MenoColor.primary, MenoColor.accent], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            VStack(alignment: .leading, spacing: MenoSpace.xxs) {
                Text(store.profile.name.isEmpty ? "Your profile" : store.profile.name).font(MenoFont.heading).foregroundStyle(MenoColor.ink)
                Text(store.profile.stage == "Not set" ? "Add your menopause stage" : store.profile.stage).font(MenoFont.caption).foregroundStyle(MenoColor.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles").font(.title3).foregroundStyle(MenoColor.accent)
        }
        .padding(MenoSpace.l)
        .background(LinearGradient(colors: [MenoColor.primarySoft, MenoColor.accentSoft.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: MenoMetric.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
