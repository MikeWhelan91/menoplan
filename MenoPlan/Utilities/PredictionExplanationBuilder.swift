import Foundation

/// Turns the inputs behind the next-period estimate into plain-English
/// bullets. Every bullet describes a value the cycle calculator actually
/// used - nothing here re-derives, guesses, or adds new modelling. Used both
/// for the on-screen "Why?" disclosure (Home/Calendar) and as grounding
/// context sent to Luna, so the two explanations always agree.
enum PredictionExplanationBuilder {
    static func bullets(window: FertilityWindow, cycle: CycleRecord?, settings: UserSettings) -> [String] {
        var bullets: [String] = []

        // Read back what the window actually used - the settings values can
        // differ (learned history or a hand-set length).
        let cycleLength = Calendar.current.dateComponents([.day], from: window.cycleStart, to: window.nextPeriodDate).day ?? settings.averageCycleLength
        bullets.append("Your last period started \(DateFormatting.shortDate.string(from: window.cycleStart)).")
        if cycle?.userSetCycleLength != nil {
            bullets.append("You set this cycle’s length to \(cycleLength) days yourself, so that’s used instead of the average from your logged periods.")
        } else {
            bullets.append("Your cycles have typically lasted about \(cycleLength) days, so your next period is expected around \(DateFormatting.shortDate.string(from: window.nextPeriodDate)).")
        }
        bullets.append("Upcoming periods are drawn as \(window.periodLength) days long.")

        if window.isIrregular, let variability = window.cycleLengthVariabilityDays {
            bullets.append("Your recent cycles have varied by about \(variability) days. That's common in perimenopause, so treat this date as a rough guide.")
        }
        if let widening = window.profileWidening {
            bullets.append(widening.explanation)
        }

        if window.isPastExpectedPeriod(on: .now) {
            bullets.append("The expected period date has passed without a new period start. MenoPlan has not assumed a new cycle; this estimate stays linked to the last one you logged.")
        }

        bullets.append("Symptoms and test readings appear in your trends but don't move this date. Logging each period is what keeps it accurate.")

        return bullets
    }
}
