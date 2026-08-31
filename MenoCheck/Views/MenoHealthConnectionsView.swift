import SwiftUI

struct MenoHealthConnectionsView: View {
    @EnvironmentObject private var health: MenoHealthStore
    @EnvironmentObject private var store: MenoStore

    var body: some View {
        MenoScreen(title: "Apple Health", subtitle: "Bring the sleep and activity context you choose into your daily record.") {
            MenoSection(title: "Connection", detail: "\(health.connectionStatus). Menoplan reads only sleep and step count; it does not write to Apple Health.") {
                Button(health.isLoading ? "Connecting…" : "Connect Apple Health", systemImage: "heart.fill") {
                    Task { await health.requestAccess() }
                }
                .disabled(health.isLoading || !health.isAvailable)
                .buttonStyle(MenoPrimaryButtonStyle())

                Button("Refresh health data", systemImage: "arrow.clockwise") {
                    Task { await health.refresh() }
                }
                .disabled(health.isLoading || !health.isAvailable)
                .buttonStyle(MenoSecondaryButtonStyle())
            }

            MenoSection(title: "Today from Health") {
                HStack(spacing: MenoSpace.l) {
                    MenoMetricView(value: health.lastNightSleepHours.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", label: "Last-night sleep", unit: "hours", compact: true)
                    MenoMetricView(value: health.todaySteps.map { $0.formatted() } ?? "—", label: "Today’s steps", compact: true)
                }
                if let sleep = health.lastNightSleepHours {
                    Button("Use \(sleep.formatted(.number.precision(.fractionLength(1)))) hours in today’s check-in", systemImage: "plus.circle.fill") {
                        store.applyHealthSleep(sleep)
                    }
                    .buttonStyle(MenoSecondaryButtonStyle())
                }
            }

            MenoDisclaimer(text: "Apple does not reveal whether read permission was granted. If no values appear after connecting, check Menoplan’s permissions in the Health app. Choosing ‘Use’ copies the sleep value into your Menoplan record, which may sync privately through iCloud.")
        }
        .task { await health.refresh() }
    }
}

struct MenoICloudSyncView: View {
    @EnvironmentObject private var store: MenoStore

    var body: some View {
        MenoScreen(title: "iCloud sync", subtitle: "Your Menoplan record stays private and can follow you across your own devices.") {
            MenoSection(title: "Private sync", detail: store.iCloudStatus) {
                Button("Check iCloud status", systemImage: "arrow.clockwise") {
                    Task { await store.refreshICloudStatus() }
                }
                .buttonStyle(MenoSecondaryButtonStyle())
            }
            MenoDisclaimer(text: "Menoplan mirrors your profile, check-ins, FSH readings and plans through your private iCloud account. Test photos stay on the device. When the same record changes on two devices, the most recently saved version is used.")
        }
        .task { await store.refreshICloudStatus() }
    }
}
