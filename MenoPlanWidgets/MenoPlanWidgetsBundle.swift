import SwiftUI
import WidgetKit

@main
struct LineCheckWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CycleWidget()
        TodayPlanWidget()
    }
}

extension WidgetSnapshot {
    /// Sample cycle used for the widget gallery and Xcode previews - never
    /// shown as if it were the user's data.
    static var preview: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        // 31-day cycle, today is cycle day 24, period due in 8 days.
        let start = -23
        let cycle = Cycle(cycleStart: day(start), nextPeriod: day(start + 31), isIrregular: true)
        var phases: [String: DayPhase] = [:]
        for offset in start...(start + 4) { phases[dayKey(day(offset))] = .period }
        for offset in (start + 31)...(start + 35) { phases[dayKey(day(offset))] = .predictedPeriod }
        return WidgetSnapshot(cycleState: .tracking, cycle: cycle, dayPhases: phases)
    }
}
