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

Fertility and pregnancy tracking are removed. The period estimate still comes from LineCheck's `FertilityWindowCalculator` / `CycleTrackingService` (it computes ovulation internally to place the next period), but nothing user-facing shows fertile days, ovulation, BBT or luteal data, and saved tests never move period dates. This engine is due to be replaced by a cycle-change calculator (cycle-length variability, 60+ day gaps, 12-month countdown). The test scan path still uses `TestType.ovulation` and LH-style result tiers until it's converted to FSH.

`MenopauseStage` (perimenopause / postmenopause / unsure) is chosen in onboarding and Settings; only perimenopause asks for cycle dates.

## Daily log

`DailyFertilityLog` (name kept from LineCheck) holds hot flush / night sweat counts (nil = not logged), a flush severity, sleep quality, HRT taken (names from `UserSettings.hrtRegimen`, never doses), bleeding, symptoms, moods and supplements. Section order comes from `DailyLogSection.ordered(for:)`: bleeding leads only in perimenopause, and outside perimenopause logging flow never starts a period and shows a see-your-clinician notice. Apple Health hot flashes / night sweats fill the counts only on days the person hasn't counted.

## Product rules

- Never diagnose peri/menopause; FSH is one data point, not a verdict.
- Bleeding logged by someone in postmenopause mode should prompt contacting a clinician.
- No HRT dose advice; direct medication questions to the prescriber.
