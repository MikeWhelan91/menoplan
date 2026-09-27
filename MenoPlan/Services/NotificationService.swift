import Foundation
import UserNotifications

struct ReminderNotification: Sendable {
    let id: UUID
    let title: String
    let reminderType: ReminderType
    let scheduledDate: Date

    init(id: UUID, title: String, reminderType: ReminderType = .custom, scheduledDate: Date) {
        self.id = id
        self.title = title
        self.reminderType = reminderType
        self.scheduledDate = scheduledDate
    }

    @MainActor
    init(reminder: Reminder) {
        self.id = reminder.id
        self.title = reminder.title
        self.reminderType = reminder.reminderType
        self.scheduledDate = reminder.scheduledDate
    }

    /// Notification copy should describe what is useful *now*, rather than
    /// repeat the delay that was selected when the reminder was created.
    var copy: NotificationCopy {
        switch reminderType {
        case .ovulationTest:
            NotificationCopy(
                title: "Time for your test",
                subtitle: "Test reminder",
                body: "Follow your test kit's instructions, then scan it in MenoPlan to keep your readings together."
            )
        case .periodExpected:
            NotificationCopy(
                title: "Period estimated around tomorrow",
                subtitle: "Cycle check-in",
                body: "This is an estimate, not a logged period. Your cycle stays open until you record a new start."
            )
        case .periodCheckIn:
            NotificationCopy(
                title: "Did your period start today?",
                subtitle: "Cycle check-in",
                body: "If it started, log the actual first day. If not, there's nothing to confirm."
            )
        case .periodLate:
            NotificationCopy(
                title: "Still waiting for your period?",
                subtitle: "Cycle check-in",
                body: "Your predicted date was only an estimate; your cycle stays open. You can log the actual first day whenever bleeding starts. Longer gaps between periods are common in perimenopause."
            )
        case .logTestResult:
            NotificationCopy(
                title: "Ready to log your result?",
                subtitle: "Test tracking",
                body: "Save today’s test in MenoPlan to make future comparisons easier."
            )
        case .medication:
            NotificationCopy(
                title: title.isEmpty ? "Time for your medication" : title,
                subtitle: "Medication reminder",
                body: "A small routine, right on time."
            )
        case .bodyCheckIn:
            NotificationCopy(
                title: "A quick check-in with yourself",
                subtitle: "Symptoms & Activities",
                body: "Log anything you’ve noticed today, only if it feels useful."
            )
        case .cycleSetup:
            NotificationCopy(
                title: "Finish setting up your cycle",
                subtitle: "Cycle tracking",
                body: "Adding a few details helps MenoPlan make more useful predictions."
            )
        case .custom:
            NotificationCopy(
                title: title.isEmpty ? "A reminder for you" : title,
                subtitle: "MenoPlan reminder",
                body: "A gentle nudge, right when you asked for it."
            )
        }
    }
}

struct NotificationCopy: Sendable, Equatable {
    let title: String
    let subtitle: String
    let body: String
}

final class NotificationService {
#if DEBUG
    /// Schedules each reminder style a few seconds apart without creating
    /// persistent Reminder records. This keeps lock-screen copy QA quick and
    /// prevents preview alerts from appearing in a user's calendar.
    func scheduleDebugPreviews() async throws {
        let previews: [(UUID, String, ReminderType)] = [
            (UUID(uuidString: "A82F4EE5-8142-46F3-8F79-ABC544921902")!, "Take your test", .ovulationTest),
            (UUID(uuidString: "A82F4EE5-8142-46F3-8F79-ABC544921904")!, "Take vitamins", .custom)
        ]

        let identifiers = previews.map { $0.0.uuidString }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)

        for (index, preview) in previews.enumerated() {
            let fireDate = Date.now.addingTimeInterval(TimeInterval(5 + (index * 7)))
            try await schedule(ReminderNotification(
                id: preview.0,
                title: preview.1,
                reminderType: preview.2,
                scheduledDate: fireDate
            ))
        }
    }
#endif

    func requestPermission() async -> Bool {
        let requestedGrant = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        let granted = requestedGrant ? true : await isAuthorized()
        AppAnalytics.log("linecheck_notification_permission", ["granted": granted])
        return granted
    }

    func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func schedule(_ notification: ReminderNotification) async throws {
        let content = UNMutableNotificationContent()
        let copy = notification.copy
        content.title = copy.title
        content.subtitle = copy.subtitle
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = "linecheck.reminders"
        content.relevanceScore = 0.7
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notification.scheduledDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notification.id.uuidString, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }


    /// Fires right away rather than at a scheduled date - used once a weekly Luna update has
    /// actually finished generating, since there's no content to notify about ahead of time.
    func sendImmediateNotification(id: UUID, title: String, subtitle: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = "linecheck.weeklyUpdate"
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
