import Foundation

struct PregnancyTimeline {
    var expectedPeriodDate: Date
    var ovulationDate: Date?
    var daysPastOvulation: Int?
    var daysUntilExpectedPeriod: Int
    var testingWindowStartDate: Date
    var retestDate: Date

    var isAfterExpectedPeriod: Bool { daysUntilExpectedPeriod < 0 }
    var isExpectedPeriodDay: Bool { daysUntilExpectedPeriod == 0 }

    func isTestingWindowDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: testingWindowStartDate)
            && day <= calendar.startOfDay(for: calendar.date(byAdding: .day, value: 7, to: expectedPeriodDate) ?? expectedPeriodDate)
    }
}

enum PregnancyTimelineCalculator {
    static func timeline(
        for date: Date = .now,
        expectedPeriodDate explicitExpectedPeriodDate: Date?,
        knownOvulationDate: Date?,
        fertilityWindow: FertilityWindow?,
        calendar: Calendar = .current
    ) -> PregnancyTimeline? {
        let explicitIsCurrent = explicitExpectedPeriodDate.map { explicit in
            guard let fertilityWindow else { return abs(calendar.dateComponents([.day], from: explicit, to: date).day ?? 0) <= 45 }
            let cycleStart = calendar.startOfDay(for: fertilityWindow.cycleStart)
            let graceEnd = calendar.date(byAdding: .day, value: 14, to: fertilityWindow.nextPeriodDate) ?? fertilityWindow.nextPeriodDate
            let value = calendar.startOfDay(for: explicit)
            return value >= cycleStart && value <= graceEnd
        } ?? false
        let expectedPeriodDate = explicitIsCurrent ? explicitExpectedPeriodDate : fertilityWindow?.nextPeriodDate
        guard let expectedPeriodDate else { return nil }

        let day = calendar.startOfDay(for: date)
        let expected = calendar.startOfDay(for: expectedPeriodDate)
        let knownOvulationIsCurrent = knownOvulationDate.map { known in
            guard let fertilityWindow else { return abs(calendar.dateComponents([.day], from: known, to: date).day ?? 0) <= 45 }
            let value = calendar.startOfDay(for: known)
            return value >= calendar.startOfDay(for: fertilityWindow.cycleStart) && value < calendar.startOfDay(for: fertilityWindow.nextPeriodDate)
        } ?? false
        let ovulationDate = knownOvulationIsCurrent ? knownOvulationDate : fertilityWindow?.predictedOvulationDate
        let dpo = ovulationDate.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: day).day ?? 0
        }
        let daysUntilExpectedPeriod = calendar.dateComponents([.day], from: day, to: expected).day ?? 0
        let testingWindowStartDate = calendar.date(byAdding: .day, value: -4, to: expected) ?? expected
        let retestDate = calendar.date(byAdding: .hour, value: 48, to: date) ?? date

        return PregnancyTimeline(
            expectedPeriodDate: expected,
            ovulationDate: ovulationDate.map { calendar.startOfDay(for: $0) },
            daysPastOvulation: dpo,
            daysUntilExpectedPeriod: daysUntilExpectedPeriod,
            testingWindowStartDate: testingWindowStartDate,
            retestDate: retestDate
        )
    }
}
