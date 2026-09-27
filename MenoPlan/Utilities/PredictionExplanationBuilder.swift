import Foundation

/// Turns the inputs behind a fertile-window/ovulation prediction into plain-
/// English bullets. Every bullet describes a value FertilityWindowCalculator
/// actually used - nothing here re-derives, guesses, or adds new modelling.
/// Used both for the on-screen "Why?" disclosure (Home/Calendar) and as
/// grounding context sent to Luna, so the two explanations always agree.
enum PredictionExplanationBuilder {
    static func bullets(window: FertilityWindow, cycle: CycleRecord?, settings: UserSettings) -> [String] {
        var bullets: [String] = []

        // Read back what the window actually used - the settings values can
        // differ (learned history, a hand-set length, a confirmed ovulation).
        let cycleLength = Calendar.current.dateComponents([.day], from: window.cycleStart, to: window.nextPeriodDate).day ?? settings.averageCycleLength
        let luteal = cycle?.lutealPhaseLengthAtStart ?? settings.lutealPhaseLength
        if cycle?.userSetCycleLength != nil {
            bullets.append("You set this cycle’s length to \(cycleLength) days yourself, so that’s used instead of the average from your logged periods. Your typical luteal phase (ovulation to next period) is \(luteal) days.")
        } else {
            bullets.append("This cycle is expected to last \(cycleLength) days, and your typical luteal phase (ovulation to next period) is \(luteal) days.")
        }
        bullets.append("Upcoming periods are drawn as \(window.periodLength) days long.")
        bullets.append("Your last period started \(DateFormatting.shortDate.string(from: window.cycleStart)).")

        if let confirmed = cycle?.confirmedOvulationDate {
            bullets.append("You confirmed ovulation on \(DateFormatting.shortDate.string(from: confirmed)), so that date is used directly instead of a calendar estimate.")
        } else if cycle?.ovulationSource == .testSupported {
            bullets.append("Your most recent peak ovulation test supports an estimated ovulation date of \(DateFormatting.shortDate.string(from: window.predictedOvulationDate)).")
        } else if cycle?.ovulationSource == .temperatureSupported {
            bullets.append("Your temperatures rose and stayed up after \(DateFormatting.shortDate.string(from: window.predictedOvulationDate)), so ovulation is placed there and the next period is counted from it.")
        } else {
            bullets.append("No confirmed or peak ovulation test yet this cycle, so ovulation is estimated from your average cycle length alone.")
        }

        if window.isIrregular, let variability = window.cycleLengthVariabilityDays {
            bullets.append("Your recent cycles have varied by about \(variability) days, so MenoPlan has widened this window rather than showing one exact date.")
        }
        if let widening = window.profileWidening {
            bullets.append(widening.explanation)
        }

        if window.isPastExpectedPeriod(on: .now) {
            bullets.append("The expected period date has passed without a new period start. MenoPlan has not assumed a new cycle; this estimate stays linked to the last one you logged.")
        }

        bullets.append("Symptoms, cervical mucus, and temperature notes appear in your trends but do not automatically move these predicted dates. A saved LH peak, a sustained temperature rise or a confirmed ovulation date can change them.")

        return bullets
    }
}
