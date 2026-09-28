# MenoPlan

iOS 18+ SwiftUI app for perimenopause and postmenopause: symptom and cycle-change tracking, a clinician-ready appointment summary, Luna (AI guide), and home FSH test reading as a supporting feature.

## Forked from LineCheck

This app is a fork of LineCheck (`/Users/mike/Dev/Apps/preg`) and should keep the same layouts and styling. To make it easy to bring LineCheck design changes across:

- Folders are renamed (`LineCheck/` → `MenoPlan/`, `LineCheckWidgets/` → `MenoPlanWidgets/`, `LineCheckTests/` → `MenoPlanTests/`), but **internal Swift identifiers keep LineCheck's names** (`Color.lineNavy`, `LineCheckBrandBackdrop`, `LineCheckApp`, Info.plist keys like `LineCheckAIEndpoint`). Don't rename them for cosmetic reasons.
- User-facing text says **MenoPlan**.
- When porting a LineCheck change, diff the equivalent file path with the folder prefix swapped.

## Identifiers (never reuse LineCheck's)

- Bundle ID `com.menocheck.app`, widgets `com.menocheck.app.widgets`
- App Group `group.com.menocheck.app`, iCloud `iCloud.com.menocheck.app`
- StoreKit products `menoplan_pro_monthly`, `menoplan_pro_yearly`, `menoplan_pro_lifetime`
- AdMob app `ca-app-pub-1257499604453174~6070339424` (banner and interstitial set; rewarded still Google's test unit)
- Still to set up: RevenueCat key (`REVENUECAT_API_KEY` in `project.yml`), `GoogleService-Info.plist` (Firebase is skipped until it exists), Meta app (`Configuration/Meta.xcconfig`), AI client token (`LineCheckAIClientToken` in Info.plist)

## Build

`xcodegen generate`, then build the `MenoPlan` scheme. The AI API lives in `api/` (Vercel: `analyse-fsh.js`, `assistant.js`).

## Cycle engine (transitional)

Fertility and pregnancy tracking are removed. The period estimate still comes from LineCheck's `FertilityWindowCalculator` / `CycleTrackingService` (it computes ovulation internally to place the next period), but nothing user-facing shows fertile days, ovulation, BBT or luteal data, and saved tests never move period dates. Home, widgets and the summary use `CycleChangeCalculator` (cycle lengths, 7+ day changes, 60+ day gaps, 12-month progress) and never show predicted dates; the Calendar still draws LineCheck's predicted periods.

## FSH test and AI API

The scan reads home FSH tests. `TestType.ovulation` keeps LineCheck's case name (and "ovulation" rawValue / deep link) but is titled "FSH Test"; `ScanResultType` bands are low / borderline / elevated (test line <0.40, <0.75, else, relative to control), matching `api/analyse-fsh.js` exactly. Luna Check is on-device: `OnDeviceOvulationAnalysisService` runs LineCheck's Core ML comparator (trained on LH strips, T left / C right in the guide box) and still needs an FSH-trained replacement; LineCheck's training pipeline is in `/Users/mike/Dev/Apps/preg/Training`. Manual Check is the pixel heuristic in `LineAnalysisEngine`. The server FSH API is only used by the Pro "Look Again" second opinion. `api/assistant.js` accepts the app's `AssistantRequest` (recentScans, reminders, userContext, optional mode: resultNarrative / weeklyDigest / compare) and returns suggestion kinds the app's `AssistantSuggestion.Kind` must include. Both APIs check the `x-menoplan-client-token` header against `MENOPLAN_API_SHARED_SECRET`. Run `npm test` for the API contract tests.

`MenopauseStage` (perimenopause / postmenopause / unsure) is chosen in onboarding and Settings; only perimenopause asks for cycle dates.

## Home

Built from user research (App Store reviews, studies, Reddit via Codex): people want low-effort logging of *their own* symptoms, a doctor-ready summary, and patterns, not predictions. Order: `CheckInCard` hero (day impact: not at all / a bit / a lot, then the person's pinned `FocusSymptoms`, tap to rate mild → moderate → severe; hot flushes / night sweats counted; sleep uses sleep quality), `RecentChangeCard` (`RecentChangeCalculator`, needs 7+ logged days in 14, phrased as an observation not a cause), `AppointmentCard` (moves to the top within 7 days of `nextAppointmentDate`), `HRTTodayCard` (only with a regimen; daily repeating reminder), `CycleChangeCard` (perimenopause only: last period and cycle lengths, never predicted or "late" dates), then a tools row (Ask Luna, FSH Test, Trends). Only the postmenopause bleeding nudge sits above the check-in. No streaks. Focus symptoms are picked in onboarding ("What's affecting you most?") and Settings; defaults don't lead with hot flushes.

## Appointment summary and widgets

`AppointmentSummaryBuilder` + `AppointmentSummaryView` make the one-page A4 summary (top three concerns, daily-life impact, sleep, periods/bleeding, HRT as prescribed, home tests, the person's own questions), shared as a vector PDF. Widgets (`WidgetSnapshot` v3) carry facts only - logged days, period days, last period start, check-in symptoms - and never show predicted or "late" dates. Widget kind strings keep LineCheck's names so placed widgets survive.

## Daily log

`DailyFertilityLog` (name kept from LineCheck) holds hot flush / night sweat counts (nil = not logged), a flush severity, sleep quality, HRT taken (names from `UserSettings.hrtRegimen`, never doses), bleeding, symptoms, moods and supplements. Section order comes from `DailyLogSection.ordered(for:)`: bleeding leads only in perimenopause, and outside perimenopause logging flow never starts a period and shows a see-your-clinician notice. Apple Health hot flashes / night sweats fill the counts only on days the person hasn't counted.

## Product rules

- Never diagnose peri/menopause; FSH is one data point, not a verdict.
- Bleeding logged by someone in postmenopause mode should prompt contacting a clinician.
- Record HRT doses and changes as the person states them; never suggest or advise on doses, and direct medication questions to the prescriber.
