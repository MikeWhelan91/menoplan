import Foundation

@Observable
final class CalendarViewModel {
    var selectedDate = Date()
}

/// Keep localized weekday headings and date positions on the same week origin.
enum CalendarMonthLayout {
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    static func cells(for month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let days = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + days.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }
    }
}
