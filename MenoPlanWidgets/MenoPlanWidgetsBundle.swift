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
    /// Sample data for the widget gallery and Xcode previews - never shown
    /// as if it were the user's data.
    static var preview: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func key(_ offset: Int) -> String { dayKey(calendar.date(byAdding: .day, value: offset, to: today) ?? today) }
        return WidgetSnapshot(
            isSetUp: true,
            tracksCycle: true,
            lastPeriodStart: calendar.date(byAdding: .day, value: -23, to: today),
            periodDays: Set(((-23)...(-19)).map(key)),
            loggedDays: Set([0, -1, -2, -4, -5, -8, -9, -10, -12, -15].map(key)),
            focus: ["Sleep", "Anxiety", "Brain Fog"]
        )
    }
}
