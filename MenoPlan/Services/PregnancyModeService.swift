import Foundation
import SwiftData

/// Moves the active cycle in and out of pregnancy mode. Home, the pregnancy
/// details sheet and Settings all go through here so the cycle record, the
/// settings mirror and the automatic reminders always change together.
enum PregnancyModeService {
    @MainActor
    static func confirmPregnancy(cycle: CycleRecord, settings: UserSettings, context: ModelContext) async {
        cycle.pregnancyState = .confirmedPregnant
        settings.pregnancyJourneyState = .confirmedPregnant
        settings.pregnancyConfirmedDateValue = .now
        try? context.save()
        AppAnalytics.log("linecheck_pregnancy_mode_entered")
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context)
    }

    /// Used when pregnancy mode was switched on by mistake (or a positive
    /// turned out not to be one): the cycle goes back to ordinary tracking.
    @MainActor
    static func returnToCycleTracking(cycle: CycleRecord, settings: UserSettings, context: ModelContext) async {
        cycle.pregnancyState = .trying
        settings.pregnancyJourneyState = .trying
        settings.pregnancyConfirmedDateValue = nil
        try? context.save()
        AppAnalytics.log("linecheck_pregnancy_mode_exited")
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context)
    }

    @MainActor
    static func markPregnancyEnded(cycle: CycleRecord, settings: UserSettings, context: ModelContext) async {
        cycle.pregnancyState = .ended
        settings.pregnancyJourneyState = .ended
        settings.pregnancyConfirmedDateValue = nil
        try? context.save()
        AppAnalytics.log("linecheck_pregnancy_mode_ended")
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context)
    }

    /// Lets the user correct the due date after a midwife/dating scan gives
    /// a different one than our cycle-based estimate.
    @MainActor
    static func setManualDueDate(_ dueDate: Date, cycle: CycleRecord, settings: UserSettings, context: ModelContext) async {
        cycle.manualDueDateOverride = dueDate
        try? context.save()
        AppAnalytics.log("linecheck_pregnancy_due_date_overridden")
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context)
    }

    /// Reverts to the cycle-based estimate, discarding any manual override.
    @MainActor
    static func clearManualDueDate(cycle: CycleRecord, settings: UserSettings, context: ModelContext) async {
        cycle.manualDueDateOverride = nil
        try? context.save()
        AppAnalytics.log("linecheck_pregnancy_due_date_reset")
        await ReminderAutomationService.syncCurrentPredictions(settings: settings, context: context)
    }
}
