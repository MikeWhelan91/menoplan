import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID = UUID()
    var defaultTestTypeRaw: String = TestType.ovulation.rawValue
    var defaultTestFormatRaw: String = TestFormat.unspecified.rawValue
    var useFaceID: Bool = false
    var localStorageOnly: Bool = false
    var notificationsEnabled: Bool = false
    var darkModePreferenceRaw: String = DarkModePreference.system.rawValue
    var proUnlocked: Bool = false
    var freeAIChecksUsedToday: Int = 0
    var rewardedChecksAvailable: Int = 0
    var lastAICheckResetDate: Date = Date.now
    @Attribute(originalName: "assistantRepliesUsedToday") private var assistantRepliesUsedTodayValue: Int?
    @Attribute(originalName: "assistantRepliesResetDate") private var assistantRepliesResetDateValue: Date?
    @Attribute(originalName: "aiComparesUsedToday") private var aiComparesUsedTodayValue: Int?
    @Attribute(originalName: "aiComparesResetDate") private var aiComparesResetDateValue: Date?
    /// Rewarded-ad checks claimed since the last weekly reset, capped at
    /// LineAnalysisConstants.maxRewardedChecksPerWeek - replaced the old
    /// per-day claim limit now that ovulation's free quota has no daily cap.
    @Attribute(originalName: "rewardedChecksClaimedThisWeek") private var rewardedChecksClaimedThisWeekValue: Int?
    @Attribute(originalName: "hasSeenCalendarIntro") private var hasSeenCalendarIntroValue: Bool?
    @Attribute(originalName: "hasSeenPostUseNotificationPrompt") private var hasSeenPostUseNotificationPromptValue: Bool?
    @Attribute(originalName: "hasSeenRatingPrompt") private var hasSeenRatingPromptValue: Bool?
    @Attribute(originalName: "dismissedCycleVariabilityDays") private var dismissedCycleVariabilityDaysValue: Int?
    var hasCompletedOnboarding: Bool = false
    var preferredAnalysisModeRaw: String = AnalysisMode.aiQuickCheck.rawValue
    var lastPeriodStartDate: Date?
    var averageCycleLengthValue: Int?
    var lutealPhaseLengthValue: Int?
    var menopauseStageRaw: String?
    var expectedPeriodDate: Date?
    var knownOvulationDate: Date?
    var trackingFocusRaw: String?
    var hasMigratedCycleHistoryValue: Bool?
    var userNameValue: String?
    var autoRemindersEnabled: Bool = false
    @Attribute(originalName: "autoPeriodExpectedRemindersEnabled") private var autoPeriodExpectedRemindersEnabledValue: Bool?
    @Attribute(originalName: "autoPeriodCheckInRemindersEnabled") private var autoPeriodCheckInRemindersEnabledValue: Bool?
    @Attribute(originalName: "autoPeriodLateRemindersEnabled") private var autoPeriodLateRemindersEnabledValue: Bool?
    var temperatureUnitRaw: String?
    @Attribute(originalName: "healthKitSyncEnabled") private var healthKitSyncEnabledValue: Bool?
    @Attribute(originalName: "healthKitAdvancedSignalsEnabled") private var healthKitAdvancedSignalsEnabledValue: Bool?
    @Attribute(originalName: "lastHealthKitSyncDate") private var lastHealthKitSyncDateValue: Date?
    // Personalisation quiz answers - all optional so existing rows and CloudKit
    // records migrate without a default having to be invented for them.
    var birthYearValue: Int?
    var cycleRegularityRaw: String?
    var reproductiveConditionsRaw: String?
    var birthControlRecencyRaw: String?
    var hasCompletedPersonalizationValue: Bool?
    var dismissedPersonalizationPromptValue: Bool?
    var dismissedDoctorSuggestionValue: Bool?
    /// What the person typed for "Something else" on the conditions question.
    var otherConditionTextValue: String?
    /// Body measurements from onboarding / the daily log / Apple Health.
    /// Stored metric; `bodyMeasurementUnit` only changes how they're shown.
    var heightCmValue: Double?
    var weightKgValue: Double?
    var bodyMeasurementUnitRaw: String?
    /// Height's own unit, so people can mix - pounds with centimetres, say.
    var heightUnitRaw: String?
    var weightUnitRaw: String?
    /// Usual period length from onboarding. Logged periods with an end date
    /// take over once there are any (CycleTrackingService.learnedPeriodLength).
    var periodLengthValue: Int?
    /// Bumped whenever LineCheck starts asking Health for more types, so an
    /// existing connection can offer the new permissions once.
    var healthKitPermissionsVersionValue: Int?
    /// Pacing for Home's occasional "connect Apple Health" reminder.
    var healthPromptFirstSeenValue: Date?
    var healthPromptLastShownValue: Date?
    var healthPromptCountValue: Int?
    var healthPromptOptOutValue: Bool?
    /// Set when onboarding was skipped with "Just scan a test": drives the
    /// post-scan "Want predictions?" prompt and Home's setup checklist.
    var skippedOnboardingSetupValue: Bool?
    /// Which Health categories have had their history imported. People who
    /// connected before a category existed get one full backfill for it.
    var healthKitBackfillVersionValue: Int?
    var hasSeenSetupPromptValue: Bool?
    var dismissedSetupChecklistValue: Bool?

    init() {
        self.id = UUID()
        self.defaultTestTypeRaw = TestType.ovulation.rawValue
        self.defaultTestFormatRaw = TestFormat.unspecified.rawValue
        self.useFaceID = false
        self.localStorageOnly = false
        self.notificationsEnabled = false
        self.darkModePreferenceRaw = DarkModePreference.system.rawValue
        self.proUnlocked = false
        self.freeAIChecksUsedToday = 0
        self.rewardedChecksAvailable = 0
        self.lastAICheckResetDate = .now
        self.assistantRepliesUsedTodayValue = 0
        self.assistantRepliesResetDateValue = .now
        self.aiComparesUsedTodayValue = 0
        self.aiComparesResetDateValue = .now
        self.rewardedChecksClaimedThisWeekValue = 0
        self.hasSeenCalendarIntroValue = false
        self.hasSeenPostUseNotificationPromptValue = false
        self.hasSeenRatingPromptValue = false
        self.hasCompletedOnboarding = false
        self.preferredAnalysisModeRaw = AnalysisMode.aiQuickCheck.rawValue
        self.lastPeriodStartDate = nil
        self.averageCycleLengthValue = 28
        self.lutealPhaseLengthValue = 14
        self.menopauseStageRaw = MenopauseStage.perimenopause.rawValue
        self.expectedPeriodDate = nil
        self.knownOvulationDate = nil
        self.trackingFocusRaw = TrackingFocus.ovulation.rawValue
        self.hasMigratedCycleHistoryValue = false
        self.userNameValue = nil
        self.autoRemindersEnabled = false
        self.autoPeriodExpectedRemindersEnabledValue = true
        self.autoPeriodCheckInRemindersEnabledValue = true
        self.autoPeriodLateRemindersEnabledValue = true
        self.temperatureUnitRaw = nil
        self.healthKitSyncEnabledValue = false
        self.healthKitAdvancedSignalsEnabledValue = false
        self.lastHealthKitSyncDateValue = nil
    }

    var defaultTestType: TestType {
        get { TestType(rawValue: defaultTestTypeRaw) ?? .ovulation }
        set { defaultTestTypeRaw = newValue.rawValue }
    }
    var defaultTestFormat: TestFormat {
        get { TestFormat(rawValue: defaultTestFormatRaw) ?? .unspecified }
        set { defaultTestFormatRaw = newValue.rawValue }
    }
    var darkModePreference: DarkModePreference {
        get { DarkModePreference(rawValue: darkModePreferenceRaw) ?? .system }
        set { darkModePreferenceRaw = newValue.rawValue }
    }
    var preferredAnalysisMode: AnalysisMode {
        get { AnalysisMode(rawValue: preferredAnalysisModeRaw) ?? .aiQuickCheck }
        set { preferredAnalysisModeRaw = newValue.rawValue }
    }
    var assistantRepliesUsedToday: Int {
        get { assistantRepliesUsedTodayValue ?? 0 }
        set { assistantRepliesUsedTodayValue = newValue }
    }
    var assistantRepliesResetDate: Date {
        get { assistantRepliesResetDateValue ?? .now }
        set { assistantRepliesResetDateValue = newValue }
    }
    var aiComparesUsedToday: Int {
        get { aiComparesUsedTodayValue ?? 0 }
        set { aiComparesUsedTodayValue = newValue }
    }
    var aiComparesResetDate: Date {
        get { aiComparesResetDateValue ?? .now }
        set { aiComparesResetDateValue = newValue }
    }
    var rewardedChecksClaimedThisWeek: Int {
        get { rewardedChecksClaimedThisWeekValue ?? 0 }
        set { rewardedChecksClaimedThisWeekValue = newValue }
    }
    var hasSeenCalendarIntro: Bool {
        get { hasSeenCalendarIntroValue ?? false }
        set { hasSeenCalendarIntroValue = newValue }
    }
    /// The cycle-length variability figure (in days) the user last dismissed the "cycles have
    /// been varying" banner at - nil means never dismissed. Kept as the exact figure, not a
    /// bool, so the banner can resurface once a new cycle changes the number rather than
    /// staying silenced forever on stale data.
    var dismissedCycleVariabilityDays: Int? {
        get { dismissedCycleVariabilityDaysValue }
        set { dismissedCycleVariabilityDaysValue = newValue }
    }
    var hasSeenPostUseNotificationPrompt: Bool {
        get { hasSeenPostUseNotificationPromptValue ?? false }
        set { hasSeenPostUseNotificationPromptValue = newValue }
    }
    var hasSeenRatingPrompt: Bool {
        get { hasSeenRatingPromptValue ?? false }
        set { hasSeenRatingPromptValue = newValue }
    }
    var averageCycleLength: Int {
        get { averageCycleLengthValue ?? 28 }
        set { averageCycleLengthValue = newValue }
    }
    var lutealPhaseLength: Int {
        get { lutealPhaseLengthValue ?? 14 }
        set { lutealPhaseLengthValue = newValue }
    }
    var periodLength: Int {
        get { periodLengthValue ?? FertilityWindowCalculator.defaultPeriodLength }
        set { periodLengthValue = newValue }
    }
    /// Unit for weight (kg / lb), and for water and distance with it.
    var bodyMeasurementUnit: BodyMeasurementUnit {
        get { BodyMeasurementUnit(rawValue: bodyMeasurementUnitRaw ?? "") ?? .localeDefault }
        set { bodyMeasurementUnitRaw = newValue.rawValue }
    }
    /// kg, lb or stone. Water follows it (ml for kg and stone, fl oz for
    /// pounds); distance uses WeightUnit.distanceSystem (miles for lb and st).
    var weightUnit: WeightUnit {
        get {
            if let unit = weightUnitRaw.flatMap(WeightUnit.init(rawValue:)) { return unit }
            if let system = bodyMeasurementUnitRaw.flatMap(BodyMeasurementUnit.init(rawValue:)) {
                return system == .imperial ? .pounds : .kilograms
            }
            return .localeDefault
        }
        set {
            // Height used to follow the weight unit's system by default; pin
            // it first so changing weight to stone can't flip height to cm.
            if heightUnitRaw == nil { heightUnitRaw = heightUnit.rawValue }
            weightUnitRaw = newValue.rawValue
            bodyMeasurementUnit = newValue.system
        }
    }
    /// Unit for height (cm / ft·in), independent of weight. Falls back to
    /// the weight unit so existing choices carry over.
    var heightUnit: BodyMeasurementUnit {
        get { BodyMeasurementUnit(rawValue: heightUnitRaw ?? "") ?? bodyMeasurementUnit }
        set { heightUnitRaw = newValue.rawValue }
    }
    var menopauseStage: MenopauseStage {
        get { MenopauseStage(rawValue: menopauseStageRaw ?? "") ?? .perimenopause }
        set { menopauseStageRaw = newValue.rawValue }
    }
    var trackingFocus: TrackingFocus {
        get { TrackingFocus(rawValue: trackingFocusRaw ?? "") ?? .ovulation }
        set {
            trackingFocusRaw = newValue.rawValue
            defaultTestType = newValue.defaultTestType
        }
    }
    var hasMigratedCycleHistory: Bool {
        get { hasMigratedCycleHistoryValue ?? false }
        set { hasMigratedCycleHistoryValue = newValue }
    }
    var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: temperatureUnitRaw ?? "") ?? .localeDefault }
        set { temperatureUnitRaw = newValue.rawValue }
    }
    var autoPeriodExpectedRemindersEnabled: Bool {
        get { autoPeriodExpectedRemindersEnabledValue ?? false }
        set { autoPeriodExpectedRemindersEnabledValue = newValue }
    }
    var autoPeriodCheckInRemindersEnabled: Bool {
        get { autoPeriodCheckInRemindersEnabledValue ?? false }
        set { autoPeriodCheckInRemindersEnabledValue = newValue }
    }
    var autoPeriodLateRemindersEnabled: Bool {
        get { autoPeriodLateRemindersEnabledValue ?? false }
        set { autoPeriodLateRemindersEnabledValue = newValue }
    }
    var healthKitSyncEnabled: Bool {
        get { healthKitSyncEnabledValue ?? false }
        set { healthKitSyncEnabledValue = newValue }
    }
    var lastHealthKitSyncDate: Date? {
        get { lastHealthKitSyncDateValue }
        set { lastHealthKitSyncDateValue = newValue }
    }
    /// Optional reproductive signals are kept separate from the core period
    /// and temperature sync because they are more personal and less commonly
    /// populated in Apple Health.
    var healthKitAdvancedSignalsEnabled: Bool {
        get { healthKitAdvancedSignalsEnabledValue ?? false }
        set { healthKitAdvancedSignalsEnabledValue = newValue }
    }
    var cycleRegularity: CycleRegularity? {
        get { cycleRegularityRaw.flatMap(CycleRegularity.init(rawValue:)) }
        set { cycleRegularityRaw = newValue?.rawValue }
    }
    var reproductiveConditions: Set<ReproductiveCondition> {
        get { Set((reproductiveConditionsRaw ?? "").split(separator: "|").compactMap { ReproductiveCondition(rawValue: String($0)) }) }
        set { reproductiveConditionsRaw = newValue.isEmpty ? nil : newValue.map(\.rawValue).sorted().joined(separator: "|") }
    }
    var birthControlRecency: BirthControlRecency? {
        get { birthControlRecencyRaw.flatMap(BirthControlRecency.init(rawValue:)) }
        set { birthControlRecencyRaw = newValue?.rawValue }
    }
    var hasCompletedPersonalization: Bool {
        get { hasCompletedPersonalizationValue ?? false }
        set { hasCompletedPersonalizationValue = newValue }
    }
    var dismissedPersonalizationPrompt: Bool {
        get { dismissedPersonalizationPromptValue ?? false }
        set { dismissedPersonalizationPromptValue = newValue }
    }
    var dismissedDoctorSuggestion: Bool {
        get { dismissedDoctorSuggestionValue ?? false }
        set { dismissedDoctorSuggestionValue = newValue }
    }
    var healthProfile: HealthProfile {
        HealthProfile(
            birthYear: birthYearValue,
            regularity: cycleRegularity,
            conditions: reproductiveConditions,
            birthControl: birthControlRecency,
            otherCondition: otherConditionTextValue,
            heightCm: heightCmValue,
            weightKg: weightKgValue
        )
    }
    var userName: String {
        get { userNameValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            userNameValue = cleaned.isEmpty ? nil : String(cleaned.prefix(40))
        }
    }

    /// Picks the row to treat as *the* settings when more than one exists.
    ///
    /// Installing on a second device creates a local row before iCloud has
    /// delivered the first one, so a synced account can genuinely end up with
    /// two. Ranking has to be a pure function of the rows — every device must
    /// independently reach the same answer — so it prefers the row carrying
    /// real use, and falls back to the id for a stable tiebreak rather than
    /// leaving `first` to whatever order the store hands back.
    static func canonical(from rows: [UserSettings]) -> UserSettings? {
        rows.max { lhs, rhs in lhs.canonicalRank < rhs.canonicalRank }
    }

    private var canonicalRank: (Int, Int, Int, Int, String) {
        (
            hasCompletedOnboarding ? 1 : 0,
            proUnlocked ? 1 : 0,
            lastPeriodStartDate != nil ? 1 : 0,
            userName.isEmpty ? 0 : 1,
            id.uuidString
        )
    }

    /// Folds anything worth keeping out of a duplicate before it is deleted.
    /// Deliberately narrow: only the fields where losing the other device's
    /// value is actually harmful, rather than a field-by-field merge that
    /// would have to guess which side is newer.
    func absorb(_ duplicate: UserSettings) {
        hasCompletedOnboarding = hasCompletedOnboarding || duplicate.hasCompletedOnboarding
        proUnlocked = proUnlocked || duplicate.proUnlocked
        if lastPeriodStartDate == nil { lastPeriodStartDate = duplicate.lastPeriodStartDate }
        if expectedPeriodDate == nil { expectedPeriodDate = duplicate.expectedPeriodDate }
        if knownOvulationDate == nil { knownOvulationDate = duplicate.knownOvulationDate }
        if userName.isEmpty { userName = duplicate.userName }
        if heightCmValue == nil { heightCmValue = duplicate.heightCmValue }
        if weightKgValue == nil { weightKgValue = duplicate.weightKgValue }
        if periodLengthValue == nil { periodLengthValue = duplicate.periodLengthValue }
    }

    func resetOnboardingState() {
        hasCompletedOnboarding = false
        expectedPeriodDate = nil
        knownOvulationDate = nil
        lastPeriodStartDate = nil
        averageCycleLength = 28
        lutealPhaseLength = 14
        periodLengthValue = nil
    }
}
