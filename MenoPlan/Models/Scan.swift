import Foundation
import SwiftData

@Model
final class Scan {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var testTypeRaw: String = TestType.ovulation.rawValue
    var testFormatRaw: String = TestFormat.unspecified.rawValue
    var resultTypeRaw: String = ScanResultType.unclear.rawValue
    var confidencePercentage: Int = 0
    var certaintyPercentage: Int = 0
    var controlLineDetected: Bool = false
    var testLineDetected: Bool = false
    var testControlRatio: Double = 0
    var lineStrength: Double = 0
    var analysisModeRaw: String = AnalysisMode.aiQuickCheck.rawValue
    var imageFilename: String = ""
    var enhancedImageFilename: String?
    var autoEnhancedImageFilename: String?
    var thumbnailFilename: String?
    /// Image bytes mirrored into private iCloud so a second device can show
    /// the scan. The filenames above stay the local-disk cache key: they are
    /// generated per device, so on a synced-in scan they simply name the file
    /// this device will write once it materialises the blob.
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var enhancedImageData: Data?
    @Attribute(.externalStorage) var autoEnhancedImageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var notes: String = ""
    var brandName: String?
    var isFavourite: Bool = false
    var imageQualityStatusRaw: String = ImageQualityStatus.good.rawValue
    var autoEnhancementSummary: String = ""
    var cycleRecordID: UUID?
    var resultWasManuallyAdjusted: Bool?
    var resultSourceRaw: String = ScanResultSource.aiOriginal.rawValue
    var hasUsedLookAgain: Bool = false
    /// User-controlled: keeps the scan in history but leaves it out of trend
    /// lines, progression, and predicted-date calculations. Never set
    /// automatically - only a person can judge that a reading was unreliable.
    var excludedFromCalculations: Bool = false
    // Quietly kept for future accuracy analysis when Look Again overwrites
    // the displayed result - never shown in the app UI.
    var preRecheckResultTypeRaw: String?
    var preRecheckCertaintyPercentage: Int?
    var lookAgainUserOpinionRaw: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        testType: TestType,
        testFormat: TestFormat,
        resultType: ScanResultType,
        confidencePercentage: Int = 0,
        certaintyPercentage: Int = 0,
        controlLineDetected: Bool = false,
        testLineDetected: Bool = false,
        testControlRatio: Double = 0,
        lineStrength: Double = 0,
        analysisMode: AnalysisMode,
        imageFilename: String,
        enhancedImageFilename: String? = nil,
        autoEnhancedImageFilename: String? = nil,
        thumbnailFilename: String? = nil,
        notes: String = "",
        brandName: String? = nil,
        isFavourite: Bool = false,
        imageQualityStatus: ImageQualityStatus = .good,
        autoEnhancementSummary: String = ""
        , cycleRecordID: UUID? = nil
        , resultWasManuallyAdjusted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.testTypeRaw = testType.rawValue
        self.testFormatRaw = testFormat.rawValue
        self.resultTypeRaw = resultType.rawValue
        self.confidencePercentage = confidencePercentage
        self.certaintyPercentage = certaintyPercentage
        self.controlLineDetected = controlLineDetected
        self.testLineDetected = testLineDetected
        self.testControlRatio = testControlRatio
        self.lineStrength = lineStrength
        self.analysisModeRaw = analysisMode.rawValue
        self.imageFilename = imageFilename
        self.enhancedImageFilename = enhancedImageFilename
        self.autoEnhancedImageFilename = autoEnhancedImageFilename
        self.thumbnailFilename = thumbnailFilename
        self.notes = notes
        self.brandName = brandName
        self.isFavourite = isFavourite
        self.imageQualityStatusRaw = imageQualityStatus.rawValue
        self.autoEnhancementSummary = autoEnhancementSummary
        self.cycleRecordID = cycleRecordID
        self.resultWasManuallyAdjusted = resultWasManuallyAdjusted
    }

    var testType: TestType { TestType(rawValue: testTypeRaw) ?? .ovulation }
    var testFormat: TestFormat { TestFormat(rawValue: testFormatRaw) ?? .unspecified }
    var resultType: ScanResultType { ScanResultType(rawValue: resultTypeRaw) ?? .unclear }
    var resultSource: ScanResultSource {
        get { ScanResultSource(rawValue: resultSourceRaw) ?? .aiOriginal }
        set { resultSourceRaw = newValue.rawValue }
    }
    var preRecheckResultType: ScanResultType? { preRecheckResultTypeRaw.flatMap(ScanResultType.init(rawValue:)) }
    var analysisMode: AnalysisMode { AnalysisMode(rawValue: analysisModeRaw) ?? .manualEnhance }
    var imageQualityStatus: ImageQualityStatus { ImageQualityStatus(rawValue: imageQualityStatusRaw) ?? .good }
}

@Model
final class CycleRecord {
    var id: UUID = UUID()
    var startDate: Date = Date.now
    var endDate: Date?
    var statusRaw: String = CycleRecordStatus.active.rawValue
    var startSourceRaw: String = TrackingDataSource.userConfirmed.rawValue
    var predictedOvulationDate: Date?
    var confirmedOvulationDate: Date?
    var ovulationSourceRaw: String?
    var expectedPeriodDate: Date?
    var averageCycleLengthAtStart: Int = 28
    var lutealPhaseLengthAtStart: Int = 14
    /// A cycle length the person set by hand for this cycle (Calendar setup,
    /// Settings, Luna). Wins over the learned median until the next period
    /// starts a new cycle, which goes back to learning from history.
    var userSetCycleLength: Int?
    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        status: CycleRecordStatus = .active,
        startSource: TrackingDataSource = .userConfirmed,
        predictedOvulationDate: Date? = nil,
        confirmedOvulationDate: Date? = nil,
        ovulationSource: TrackingDataSource? = nil,
        expectedPeriodDate: Date? = nil,
        averageCycleLengthAtStart: Int = 28,
        lutealPhaseLengthAtStart: Int = 14,
        notes: String = ""
    ) {
        self.id = id
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.statusRaw = status.rawValue
        self.startSourceRaw = startSource.rawValue
        self.predictedOvulationDate = predictedOvulationDate
        self.confirmedOvulationDate = confirmedOvulationDate
        self.ovulationSourceRaw = ovulationSource?.rawValue
        self.expectedPeriodDate = expectedPeriodDate
        self.averageCycleLengthAtStart = averageCycleLengthAtStart
        self.lutealPhaseLengthAtStart = lutealPhaseLengthAtStart
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }

    var status: CycleRecordStatus {
        get { CycleRecordStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }
    var startSource: TrackingDataSource { TrackingDataSource(rawValue: startSourceRaw) ?? .estimated }
    var ovulationSource: TrackingDataSource? {
        get { ovulationSourceRaw.flatMap(TrackingDataSource.init(rawValue:)) }
        set { ovulationSourceRaw = newValue?.rawValue; updatedAt = .now }
    }
    var effectiveOvulationDate: Date? { confirmedOvulationDate ?? predictedOvulationDate }
}

@Model
final class PeriodEvent {
    var id: UUID = UUID()
    var startDate: Date = Date.now
    var endDate: Date?
    var sourceRaw: String = TrackingDataSource.userConfirmed.rawValue
    var cycleRecordID: UUID?
    var notes: String = ""
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil, source: TrackingDataSource = .userConfirmed, cycleRecordID: UUID? = nil, notes: String = "") {
        self.id = id
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.sourceRaw = source.rawValue
        self.cycleRecordID = cycleRecordID
        self.notes = notes
        self.createdAt = .now
    }

    var source: TrackingDataSource { TrackingDataSource(rawValue: sourceRaw) ?? .userConfirmed }
}

/// One canonical journal entry per calendar day. Comparisons stay derived from
/// scans; only observations the user actually records belong in persistence.
@Model
final class DailyFertilityLog {
    var id: UUID = UUID()
    var date: Date = Date.now
    var symptomsRaw: String = ""
    var moodsRaw: String = ""
    var supplementsRaw: String = ""
    var flowIntensityRaw: String?
    var basalBodyTemperatureCelsius: Double?
    /// Where basalBodyTemperatureCelsius came from - a manual edit always sets this back to
    /// .userConfirmed so HealthKitSyncService knows never to overwrite it on a later sync.
    var basalBodyTemperatureSourceRaw: String = TrackingDataSource.userConfirmed.rawValue
    /// Apple Watch sleeping wrist temperature. Kept apart from BBT: it reads
    /// around 1-2°C lower than an oral/vaginal BBT, so mixing the two in one
    /// series would look like a temperature shift that never happened.
    var wristTemperatureCelsius: Double?
    /// Read-only test observations imported from Apple Health. These are deliberately
    /// separate from LineCheck scans: they were recorded elsewhere and must never be
    /// shown as an image analysis result.
    var healthKitObservationsRaw: String = ""
    /// Body weight for the day. Same ownership rule as BBT: a value the person
    /// typed is never overwritten by a later Apple Health sync.
    var weightKg: Double?
    var weightSourceRaw: String?
    /// Water drunk that day, in millilitres.
    var waterMl: Double?
    var waterSourceRaw: String?
    /// Hot flushes and night sweats counted that day. nil is "not logged";
    /// a day with other entries and no count reads as none on the trends.
    var hotFlushCount: Int?
    var nightSweatCount: Int?
    var vasomotorSeverityRaw: String?
    var sleepQualityRaw: String?
    /// HRT ticked off as taken that day, by name (see HRTOptions).
    var hrtTakenRaw: String = ""
    var notes: String = ""
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), date: Date, symptoms: [String] = [], moods: [String] = [], supplements: [String] = [], flowIntensity: FlowIntensity? = nil, basalBodyTemperatureCelsius: Double? = nil, basalBodyTemperatureSource: TrackingDataSource = .userConfirmed, notes: String = "") {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.symptomsRaw = symptoms.joined(separator: "|")
        self.moodsRaw = moods.joined(separator: "|")
        self.supplementsRaw = supplements.joined(separator: "|")
        self.flowIntensityRaw = flowIntensity?.rawValue
        self.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
        self.basalBodyTemperatureSourceRaw = basalBodyTemperatureSource.rawValue
        self.notes = notes
        self.updatedAt = .now
    }

    var basalBodyTemperatureSource: TrackingDataSource {
        get { TrackingDataSource(rawValue: basalBodyTemperatureSourceRaw) ?? .userConfirmed }
        set { basalBodyTemperatureSourceRaw = newValue.rawValue; updatedAt = .now }
    }
    var weightSource: TrackingDataSource {
        get { weightSourceRaw.flatMap(TrackingDataSource.init(rawValue:)) ?? .userConfirmed }
        set { weightSourceRaw = newValue.rawValue; updatedAt = .now }
    }
    var waterSource: TrackingDataSource {
        get { waterSourceRaw.flatMap(TrackingDataSource.init(rawValue:)) ?? .userConfirmed }
        set { waterSourceRaw = newValue.rawValue; updatedAt = .now }
    }
    var symptoms: [String] { get { split(symptomsRaw) } set { symptomsRaw = newValue.joined(separator: "|"); updatedAt = .now } }
    var moods: [String] { get { split(moodsRaw) } set { moodsRaw = newValue.joined(separator: "|"); updatedAt = .now } }
    var supplements: [String] { get { split(supplementsRaw) } set { supplementsRaw = newValue.joined(separator: "|"); updatedAt = .now } }
    var hrtTaken: [String] { get { split(hrtTakenRaw) } set { hrtTakenRaw = newValue.joined(separator: "|"); updatedAt = .now } }
    var vasomotorSeverity: SymptomSeverity? {
        get { vasomotorSeverityRaw.flatMap(SymptomSeverity.init(rawValue:)) }
        set { vasomotorSeverityRaw = newValue?.rawValue; updatedAt = .now }
    }
    var sleepQuality: SleepQuality? {
        get { sleepQualityRaw.flatMap(SleepQuality.init(rawValue:)) }
        set { sleepQualityRaw = newValue?.rawValue; updatedAt = .now }
    }
    /// "3 hot flushes · 1 night sweat · Moderate", or nil if none were counted.
    var vasomotorSummary: String? {
        var parts: [String] = []
        if let hot = hotFlushCount, hot > 0 { parts.append("\(hot) hot \(hot == 1 ? "flush" : "flushes")") }
        if let sweats = nightSweatCount, sweats > 0 { parts.append("\(sweats) night \(sweats == 1 ? "sweat" : "sweats")") }
        guard !parts.isEmpty else { return nil }
        if let severity = vasomotorSeverity { parts.append(severity.title) }
        return parts.joined(separator: " · ")
    }
    var healthKitObservations: [String] { get { split(healthKitObservationsRaw) } set { healthKitObservationsRaw = newValue.joined(separator: "|"); updatedAt = .now } }
    var flowIntensity: FlowIntensity? {
        get { flowIntensityRaw.flatMap(FlowIntensity.init(rawValue:)) }
        set { flowIntensityRaw = newValue?.rawValue; updatedAt = .now }
    }
    var hasContent: Bool { !symptoms.isEmpty || !moods.isEmpty || !supplements.isEmpty || flowIntensityRaw != nil || basalBodyTemperatureCelsius != nil || wristTemperatureCelsius != nil || weightKg != nil || waterMl != nil || !healthKitObservations.isEmpty || !notes.isEmpty || hotFlushCount != nil || nightSweatCount != nil || vasomotorSeverityRaw != nil || sleepQualityRaw != nil || !hrtTakenRaw.isEmpty }
    private func split(_ value: String) -> [String] { value.split(separator: "|").map(String.init) }
}

/// Read-only daily activity and vitals from Apple Health, one row per day.
/// Kept apart from DailyFertilityLog on purpose: nothing here is something the
/// person logged in LineCheck, every value is replaced on the next sync, and
/// none of it should make a day look "logged" on the calendar.
@Model
final class DailyHealthMetrics {
    var id: UUID = UUID()
    var date: Date = Date.now
    var steps: Double?
    var walkingRunningKm: Double?
    var activeEnergyKcal: Double?
    var exerciseMinutes: Double?
    var workoutCount: Int?
    var workoutMinutes: Double?
    var restingHeartRate: Double?
    var heartRateVariabilityMs: Double?
    var sleepHours: Double?
    var updatedAt: Date = Date.now

    init(date: Date) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.updatedAt = .now
    }

    var hasContent: Bool {
        [steps, walkingRunningKm, activeEnergyKcal, exerciseMinutes, workoutMinutes,
         restingHeartRate, heartRateVariabilityMs, sleepHours]
            .contains { $0 != nil } || workoutCount != nil
    }
}

/// A CycleSignalsEngine observation, kept on the day it first appeared so the
/// calendar can show what LineCheck noticed and when. Signals themselves are
/// recalculated live; this is only the history. A signal seen on consecutive
/// days extends `lastSeen` rather than creating a new entry.
@Model
final class NoticedSignal {
    var id: UUID = UUID()
    var signalID: String = ""
    var firstSeen: Date = Date.now
    var lastSeen: Date = Date.now
    var toneRaw: Int = 0
    var title: String = ""
    var detail: String = ""
    /// When the person opened Home's signals popup while this was showing -
    /// clears it from the badge count.
    var seenAt: Date?

    init(signal: CycleSignal, on day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        self.id = UUID()
        self.signalID = signal.id
        self.firstSeen = start
        self.lastSeen = start
        self.toneRaw = signal.tone.rawValue
        self.title = signal.title
        self.detail = signal.detail
    }

    var tone: CycleSignal.Tone { CycleSignal.Tone(rawValue: toneRaw) ?? .info }
}

@Model
final class ScanComparison {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var testTypeRaw: String = TestType.ovulation.rawValue
    var earlierScanID: UUID = UUID()
    var laterScanID: UUID = UUID()
    var earlierDate: Date = Date.now
    var laterDate: Date = Date.now
    var earlierResultRaw: String = ScanResultType.unclear.rawValue
    var laterResultRaw: String = ScanResultType.unclear.rawValue
    var earlierRatio: Double = 0
    var laterRatio: Double = 0
    var earlierLineStrength: Double = 0
    var laterLineStrength: Double = 0
    var localSummaryTitle: String = ""
    var localSummaryDetail: String = ""
    var aiSummary: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        testType: TestType,
        earlierScanID: UUID,
        laterScanID: UUID,
        earlierDate: Date,
        laterDate: Date,
        earlierResult: ScanResultType,
        laterResult: ScanResultType,
        earlierRatio: Double,
        laterRatio: Double,
        earlierLineStrength: Double,
        laterLineStrength: Double,
        localSummaryTitle: String,
        localSummaryDetail: String,
        aiSummary: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.testTypeRaw = testType.rawValue
        self.earlierScanID = earlierScanID
        self.laterScanID = laterScanID
        self.earlierDate = earlierDate
        self.laterDate = laterDate
        self.earlierResultRaw = earlierResult.rawValue
        self.laterResultRaw = laterResult.rawValue
        self.earlierRatio = earlierRatio
        self.laterRatio = laterRatio
        self.earlierLineStrength = earlierLineStrength
        self.laterLineStrength = laterLineStrength
        self.localSummaryTitle = localSummaryTitle
        self.localSummaryDetail = localSummaryDetail
        self.aiSummary = aiSummary
    }

    var testType: TestType { TestType(rawValue: testTypeRaw) ?? .ovulation }
    var earlierResult: ScanResultType { ScanResultType(rawValue: earlierResultRaw) ?? .unclear }
    var laterResult: ScanResultType { ScanResultType(rawValue: laterResultRaw) ?? .unclear }
}

