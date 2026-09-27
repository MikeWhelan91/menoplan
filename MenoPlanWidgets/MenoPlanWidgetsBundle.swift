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
    /// shown as if it were the user's data. Sits in the wait after ovulation,
    /// when Today's Plan is most useful.
    static var preview: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        // 28-day cycle, today is cycle day 24 (9 days after ovulation), period due in 5 days.
        let start = -23
        let cycle = Cycle(
            cycleStart: day(start), opkStart: day(start + 7), fertileStart: day(start + 9), fertileEnd: day(start + 14),
            ovulation: day(start + 14), nextPeriod: day(start + 28), isIrregular: false, ovulationConfirmed: false
        )
        var phases: [String: DayPhase] = [:]
        for offset in start...(start + 4) { phases[dayKey(day(offset))] = .period }
        for offset in (start + 7)...(start + 8) { phases[dayKey(day(offset))] = .opkWindow }
        for offset in (start + 9)...(start + 13) { phases[dayKey(day(offset))] = .fertile }
        phases[dayKey(day(start + 14))] = .ovulation
        for offset in (start + 15)...(start + 27) { phases[dayKey(day(offset))] = .luteal }
        for offset in (start + 28)...(start + 32) { phases[dayKey(day(offset))] = .predictedPeriod }

        return WidgetSnapshot(
            cycleState: .tracking,
            cycle: cycle,
            dayPhases: phases,
            ovulationTestDays: Set(((start + 7)...(start + 14)).map { dayKey(day($0)) }),
            latestOvulationTest: LatestTest(date: day(start + 14), resultRaw: "peak")
        )
    }
}
