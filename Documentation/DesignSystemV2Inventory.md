# Spotter Design System V2 Inventory

**Date:** 2026-05-17
**Phase:** D0 - design inventory and design-vs-code delta document
**Scope:** Documentation only. No SwiftUI, backend, sync, or live camera behavior is changed in D0.

## Read And Verified

- Required docs read: `README.md`, `DEBUG_LOG.md` latest entries plus DL-045, `Documentation/DEVELOPMENT_SETUP.md`, `Documentation/FirestoreShape.md`, `Documentation/SyncConflictResolution.md`, `Documentation/BackendQAChecklist.md`, and `Documentation/firestore.rules`.
- Required design/system files read: `VirtualTrainer/DesignSystem/Theme.swift`, `VirtualTrainer/DesignSystem/LiquidGlass.swift`, `VirtualTrainer/Services/FeatureFlags.swift`, `VirtualTrainer/Models/ThemeStore.swift`, and `VirtualTrainer/UI/MainTabView.swift`.
- D1-era files are not present yet: `SpotterV2Tokens.swift`, `SpotterV2Typography.swift`, `SpotterV2Components.swift`, and `DesignSystemV2ToggleStore.swift`.
- Toolchain check passed: `xcrun --find clang` and `xcrun --find swiftc` both resolve under `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`.
- Design artifacts counted: 29 HTML exports in `NEW_DESIGN/export-html/` and 29 screenshots in `NEW_DESIGN/screenshots/`. Every screenshot is `964 x 1908` PNG and has a matching HTML basename.

## Artifact Groups

| Feature area | HTML files | Screenshot files | Implementation phase |
|---|---|---|---|
| D2 shell and navigation | `liquid-glass-nav-iteration.html` | `liquid-glass-nav-iteration.png` | D2 |
| D3 onboarding and calibration | `welcome-screen.html`, `onboarding-identity.html`, `onboarding-stats-v2.html`, `onboarding-objective.html`, `calibration-1.html`, `camera-readiness.html` | matching PNGs | D3 |
| D4 dashboard and free analysis entry | `quick-start.html`, `form-check-selection.html`, `hyper-theme-preview-(copy).html`, `hyper-theme-preview-(copy)-(copy).html`, `hyper-theme-preview-(copy)-(copy)-(copy).html` | matching PNGs | D4 |
| D5 workout flow | `workout-preview.html`, `coach-selector.html`, `exercise-swap-sheet-v1.html`, `exercise-swap-sheet-v2.html`, `live-workout.html`, `live-workout-(copy).html`, `rest-screen.html`, `workout-summary.html` | matching PNGs | D5 |
| D6 profile, trophies, history, evidence, themes | `profile.html`, `trophies.html`, `trophy-collection---expanded.html`, `workout-detail-sheet.html`, `workout-evidence.html`, `hyper-theme-preview.html`, `hot-girl-theme-preview.html`, `warm-theme-preview.html`, `spicy-theme-preview.html` | matching PNGs | D6 |

## Exact HTML And Screenshot Pairs

| Feature area | HTML | Screenshot |
|---|---|---|
| D3 onboarding/calibration | `calibration-1.html` | `calibration-1.png` |
| D3 onboarding/calibration | `camera-readiness.html` | `camera-readiness.png` |
| D5 workout flow | `coach-selector.html` | `coach-selector.png` |
| D5 workout flow | `exercise-swap-sheet-v1.html` | `exercise-swap-sheet-v1.png` |
| D5 workout flow | `exercise-swap-sheet-v2.html` | `exercise-swap-sheet-v2.png` |
| D4 dashboard/camera | `form-check-selection.html` | `form-check-selection.png` |
| D6 themes/profile | `hot-girl-theme-preview.html` | `hot-girl-theme-preview.png` |
| D4 dashboard | `hyper-theme-preview-(copy)-(copy)-(copy).html` | `hyper-theme-preview-(copy)-(copy)-(copy).png` |
| D4 dashboard | `hyper-theme-preview-(copy)-(copy).html` | `hyper-theme-preview-(copy)-(copy).png` |
| D4 dashboard | `hyper-theme-preview-(copy).html` | `hyper-theme-preview-(copy).png` |
| D6 themes/profile | `hyper-theme-preview.html` | `hyper-theme-preview.png` |
| D2 shell/navigation | `liquid-glass-nav-iteration.html` | `liquid-glass-nav-iteration.png` |
| D5 workout flow | `live-workout-(copy).html` | `live-workout-(copy).png` |
| D5 workout flow | `live-workout.html` | `live-workout.png` |
| D3 onboarding/calibration | `onboarding-identity.html` | `onboarding-identity.png` |
| D3 onboarding/calibration | `onboarding-objective.html` | `onboarding-objective.png` |
| D3 onboarding/calibration | `onboarding-stats-v2.html` | `onboarding-stats-v2.png` |
| D6 profile | `profile.html` | `profile.png` |
| D4 dashboard/camera | `quick-start.html` | `quick-start.png` |
| D5 workout flow | `rest-screen.html` | `rest-screen.png` |
| D6 themes/profile | `spicy-theme-preview.html` | `spicy-theme-preview.png` |
| D6 trophies | `trophies.html` | `trophies.png` |
| D6 trophies | `trophy-collection---expanded.html` | `trophy-collection---expanded.png` |
| D6 themes/profile | `warm-theme-preview.html` | `warm-theme-preview.png` |
| D3 onboarding/calibration | `welcome-screen.html` | `welcome-screen.png` |
| D6 workout history/evidence | `workout-detail-sheet.html` | `workout-detail-sheet.png` |
| D6 workout history/evidence | `workout-evidence.html` | `workout-evidence.png` |
| D5 workout flow | `workout-preview.html` | `workout-preview.png` |
| D5 workout flow | `workout-summary.html` | `workout-summary.png` |

## Screen Inventory

| Screen | HTML and screenshot | Current SwiftUI equivalent | Stable hero strings | Key components | Design-only features to defer | Phase |
|---|---|---|---|---|---|---|
| Liquid glass nav iteration | `liquid-glass-nav-iteration.html` / `.png` | `MainTabView` today; no custom V2 shell yet | `Hello, Satvik`; `Status: Training Active`; `Next Milestone`; `Squat Depth: +2cm`; `94% Form Score`; `Consistency 14 Days` | Floating glass tab bar; dashboard metrics; avatar; milestone card | Dashboard sample values are placeholders; bind to real stats/trophy data only | D2 |
| Welcome screen | `welcome-screen.html` / `.png` | `WelcomeView` in `OnboardingViews.swift` | `Spotter AI`; `Your AI Form Coach`; `Never train alone again.`; `Live Tracking`; `Elite Form & REP AI`; `Real-time coaching for every set`; `PICK WHO GETS TO COACH YOU`; `100% LOCAL & SECURE`; `Get Started`; `Already have an account? Log in` | App mark eyebrow; hero heading; image hero card; coach preview card; privacy card; bottom CTA | Login/SIWA is not implemented; render disabled/coming soon or omit. Remote portrait imagery not bundled | D3 |
| Onboarding identity | `onboarding-identity.html` / `.png` | `OnboardingIdentityView` | `01 / 04`; `Who are we training?`; `Spotter customizes coaching to your body.`; `Male`; `Female`; `Other`; `How many years young?`; `CONTINUE` | Back button; progress eyebrow; gender tiles; age selector; bottom CTA | None. Add current code's name field if required, styled with V2 selector/input language | D3 |
| Onboarding stats | `onboarding-stats-v2.html` / `.png` | `OnboardingStatsView` | `02 / 04`; `Enter your vitals`; `Used to personalize your daily coaching.`; `Height`; `CM`; `FT`; `Weight`; `KG`; `LB`; `CONTINUE` | Unit segmented controls; numeric pickers; bottom CTA | None. Preserve current validation and unit conversion behavior | D3 |
| Onboarding objective | `onboarding-objective.html` / `.png` | `OnboardingGoalEquipmentView`; current flow also has coach/theme page | `03 / 04`; `Define your Objective`; `Your plan adjusts based on your focus.`; `Primary Focus`; `Strength`; `Performance`; `Longevity`; `Equipment Available`; `Bodyweight`; `Dumbbells`; `Kettlebell`; `CONTINUE` | Objective cards; equipment chips; bottom CTA | Design omits some current fields such as fitness level, limitations, session length, days per week, reminders, coach, and theme. Keep those code features and style with matching V2 cards | D3 |
| Calibration intro | `calibration-1.html` / `.png` | `CalibrationIntroView` | `Position your phone`; `Earn your first trophy`; `Track 3 Air squats to proceed`; `Let's Go!`; `Skip for now` | Illustration card; trophy cue; primary CTA; secondary skip | Remote setup illustration not bundled. Use local V2 illustration/SF fallback or existing camera live preview shell | D3 |
| Camera readiness | `camera-readiness.html` / `.png` | `CameraReadinessView`; readiness state from `WorkoutReadyCoordinator` | `Move back`; `Step away until your full body is visible to the coach.`; `Turn phone sideways for squats` | Camera preview card; body visibility prompt; orientation pill; close button | Remote camera preview image not bundled. Permission denied, failed, and skipped states are code-only and must be styled | D3 |
| Quick start hub | `quick-start.html` / `.png` | `HomeDashboardView`; `DashboardContentFactory`; `QuickStartPlanDeckService` | `Train Now`; `Recommended`; `Smart Start`; `"7-min core session to keep your 12-day streak alive today."`; `Go Now`; `Form Check`; `EXERCISE-SPECIFIC`; `Running Analysis`; `GAIT & FORM AI` | Quick action cards; Smart Start CTA; Form Check card; Running Analysis preview | Running Analysis is research/coming soon. Do not build active flow | D4 |
| Form check selection | `form-check-selection.html` / `.png` | `FormCheckSelectionView` in `CameraTabView.swift` | `Quick Start`; `Form Check`; `Upper Body`; `Lower Body`; `Core`; `Yoga`; `Push Ups`; `Pull Ups`; `Shoulder Press`; `Bicep Curls`; `Dips`; `Let's go!` | Category chips; exercise rows; CTA | Pull ups are not supported in the current exercise library. Omit unsupported exercises or mark unavailable | D4 |
| Dashboard theme preview, compact | `hyper-theme-preview-(copy).html` / `.png` | `HomeDashboardView` | `Hello, Satvik`; `Current Program`; `Day 2: Starter Strength`; `Daily Mission`; `35 MIN`; `Full Body Engine`; `Objective: Squat depth & Core stability through high-tension isometric holds.`; `Start Workout`; `94% Form Quality`; `Consistency 12 Active Days`; `SPOTTER Insight` | Dashboard hero plan; metric cards; insight card; bottom nav | Placeholder metrics and copy must bind to real stats/insights | D4 |
| Dashboard theme preview, expanded A | `hyper-theme-preview-(copy)-(copy).html` / `.png` | `HomeDashboardView`; trophy teaser overlaps `TrophiesView` | `SPOTTER AI`; `Keep it up, Satvik.`; `Day 12 - Power Build`; `Full Body Engine.`; `35 Minutes`; `Weights`; `High Volume`; `Launch Training`; `Form Quality 98%`; `CURRENT STREAK 14 Days`; `Spotter Intelligence`; `Hall of Gains`; `New Achievement Unlocked`; `Depth Charge` | Rich dashboard; plan launch CTA; metrics; insight quote; trophy teaser; bottom nav | Values are sample content. Trophy and stats must bind to store truth | D4 |
| Dashboard theme preview, expanded B | `hyper-theme-preview-(copy)-(copy)-(copy).html` / `.png` | Same as previous; duplicate visual variant | Same as `hyper-theme-preview-(copy)-(copy).html` | Same as previous | Same as previous | D4 |
| Workout preview | `workout-preview.html` / `.png` | `WorkoutPreviewView`; `TargetVolumeEditSheetView`; `PlannedWorkoutSessionView` | `Your Coach`; `Bennet`; `Day 2: Starter Strength`; `Full Body Engine`; `35 MIN`; `Hard`; `COACH BENNET`; `Workout Plan (4)`; `Swap All`; `Air Squats`; `3 Sets - 12 Reps`; `Push Ups`; `3 Sets - AMRAP`; `Lunges`; `3 Sets - 10 Per Leg`; `Start Session` | Hero image; coach badge; back button; metrics pills; exercise list; bottom CTA | `Swap All` is intentionally hidden; no plan-level swap UI | D5 |
| Coach selector | `coach-selector.html` / `.png` | Inline coach selector in `WorkoutPreviewView`; profile coach selector in `ProfileView` | `Select Your Coach`; `Coach Bennet`; `BELIEVES IN YOU MORE THAN YOU BELIEVE IN YOURSELF`; `Coach Fletcher`; `There are no 2 words more harmful than 'good job'`; `done, lfg!` | Bottom sheet; coach portrait cards; selection check; CTA | Uses external coach portraits, but repo already has `CoachBennet` and `CoachFletcher` image assets. Use those assets. Keep code truth: Bennett and Fletcher only | D5 |
| Exercise target sheet V1 | `exercise-swap-sheet-v1.html` / `.png` | `TargetVolumeEditSheetView` | `Adjust Movement`; `Air Squats`; `Target Volume`; `Sets`; `3`; `Reps`; `12`; `Save Changes`; `Reset to original plan` | Bottom sheet; stepper controls; primary and secondary buttons | None. This is the supported target-volume edit direction | D5 |
| Exercise swap sheet V2 | `exercise-swap-sheet-v2.html` / `.png` | No current supported UI; `PlanSwapService` exists but hidden | `Adjust Movement`; `Alternative Movements`; `AI Alternatives`; `Goblet Squats`; `Harder`; `Box Squats`; `Easier`; `Save Changes`; `Reset to original plan` | Bottom sheet; target controls; alternatives list; AI label | Smart swaps/AI alternatives are deferred. Do not expose in V2; use V1 target sheet styling only | D5 |
| Live workout HUD | `live-workout.html` / `.png` | `TrainerSessionView` and `TrainerOverlayView` | `Air Squats`; `Set 2 of 3`; `Skip`; `Go Deeper`; `Effort Rising`; `Form 92%`; `REPS 07 /12` | Full camera surface; top set pill; cue card; effort/form pills; rep counter | `placeholder:img-workout-man-squat` is not a repo image and must not replace the live camera. Keep existing camera pipeline and overlay only style the HUD | D5 |
| Live workout HUD copy | `live-workout-(copy).html` / `.png` | Same as `live-workout.html` | Same as `live-workout.html` | Duplicate live HUD reference | Same as previous | D5 |
| Rest screen | `rest-screen.html` / `.png` | `RestScreenView` | `Skip Rest`; `44 Seconds Left`; `Last Set`; `Pushups`; `12 Reps`; `Excellent Depth`; `Maintained 95% range of motion`; `Coach's Note`; `"Depth improved after rep 4. Keep it up."`; `Up Next`; `Pushups - Set 2 of 3`; `+15s Rest`; `Start Set 2` | Large countdown; last-set review; coach note; up-next card; rest extension; CTA | Range-of-motion percentage is not explicitly available as a generic metric. Use current form/cue/rest data and avoid fake range values | D5 |
| Workout summary | `workout-summary.html` / `.png` | `WorkoutSummaryView`; also reused from `FreeAnalysisSummaryView` after save | `Mission Complete`; `Full Body Engine - Oct 24`; `Time spent`; `34:12`; `Target Met`; `Form Quality 94%`; `Excellent`; `Exercises Logged`; `Coach Insight`; `Streak: 12 Days Strong`; `Done` | Completion hero; stat cards; exercise list; insight card; trophy/streak card; bottom CTA | The design omits Free Analysis summary. Keep free-analysis variant with code truth and V2 language | D5 |
| Profile | `profile.html` / `.png` | `ProfileView`; `TrainingHeatmapView`; `InsightEvidenceSheetView`; account controls in `ProfileView` | `Satvik Bansal`; `Level 12 - 4,800 XP`; `TROPHIES`; `App Theme`; `Hyper`; `Hot girl`; `Warm`; `Spicy`; `Stats`; `Workout Snapshot`; `Last 12 Weeks`; `Share Heatmap`; `Coach Insights`; `Workout History`; `View All` | Avatar; trophy strip; theme selector; preference rows; stat grid; heatmap; share CTA; insight cards; history list | `KCAL` in history is unsupported/unsafe to surface. Use duration/reps/hold/form instead. External Google avatar is not bundled; use initials/SF fallback | D6 |
| Trophies | `trophies.html` / `.png` | `TrophiesView` | `HALL OF GAINS`; `TROPHIES COLLECTED 04 / 10`; `The Spark`; `7-Day Inferno`; `Form Architect`; `Morning Glory`; `Neon Pulse`; `Heavy Metal`; `The Machine`; `Zen Master`; `Night Owl`; `Alpha Spotter`; `Share Collection` | Trophy list; earned/in-progress/locked cards; progress bars; share CTA | BPM and KG volume trophies are coming soon. Share Collection poster is not implemented; render disabled/coming soon | D6 |
| Trophy collection expanded | `trophy-collection---expanded.html` / `.png` | `TrophyCollectionView` inside `TrophiesView.swift` | `HALL OF GAINS`; `TROPHIES COLLECTED 12 / 20`; `Leg Day Legend`; `Titan Arms`; `Chest Cmdr`; `Core Crusader`; `Squat King`; `Iron Will`; `The Finisher`; `Neon Pulse`; `1K Club`; `Elite Form`; `Calibrated`; `Burpee Beast`; `Apex Spotter`; `Share My Collection` | Trophy grid; earned and locked states; ultimate title card; share CTA | Burpee Beast requires unsupported exercise; BPM and KG trophies coming soon; Share My Collection deferred | D6 |
| Workout detail sheet | `workout-detail-sheet.html` / `.png` | `WorkoutDetailSheetView` | `Monday, Oct 23`; `Mobility FLOW`; `18 MIN`; `form quality 94%`; `CALORIES 120 KCAL`; `Exercises Logged`; `Deep Squat Holds`; `Cobra Stretch`; `Coach Insight`; `Close Summary` | Detail sheet; hero stats; exercises; coach insight; close CTA | Calories/KCAL are not supported. Use duration, reps, holds, form, completion, effort, and cue evidence | D6 |
| Workout evidence | `workout-evidence.html` / `.png` | `WorkoutEvidenceTimelineSheet` in `WorkoutDetailSheetView.swift`; `WorkoutDetailEvidenceModel`; also `InsightEvidenceSheetView` | `Session Evidence`; `Session Effort`; `85 Peak RPE`; `Top Form Cue`; `Set Analysis`; `Event Loop`; `Chronological Evidence`; `Rep Analysis`; `AI Feedback` | Sticky header; metric cards; set analysis; quality breakdown; rationale card; timeline | Range/depth/velocity metrics in the mock are not all computed today. Render available data and mark missing metrics coming soon | D6 |
| Hyper theme preview | `hyper-theme-preview.html` / `.png` | No direct runtime screen; maps to `SpotterThemeOption.hyper` and future V2 theme selector/gallery | `Theme: Hyper`; `Spotter Pro`; `Status Prime Condition`; `Hyper Sprint`; `Start Training`; `12 Streak`; `94% Form IQ`; `AI Coaching` | Theme preview card set; stat cards; insight card | Placeholder values only; do not add fake form IQ | D6 |
| Hot Girl theme preview | `hot-girl-theme-preview.html` / `.png` | No direct runtime screen; maps to `SpotterThemeOption.hotGirl` and future V2 theme selector/gallery | `Theme: Hot Girl`; `Aura Check`; `Radiant Energy`; `Glute Sculpt`; `Let's Glow`; `850 Cals Burned`; `100% Flow state`; `Queen's Insight` | Theme preview; pink/cyan accents; insight card | Calories are unsupported. External avatar not bundled | D6 |
| Warm theme preview | `warm-theme-preview.html` / `.png` | No direct runtime screen; maps to `SpotterThemeOption.warm` and future V2 theme selector/gallery | `Theme: Warm`; `Sun State`; `High Focus`; `Golden Grit`; `Rise & Train`; `45m Active Time`; `3 New Records`; `Golden Note` | Theme preview; warm accent; stat cards; insight card | Placeholder records only; bind to real stats if used | D6 |
| Spicy theme preview | `spicy-theme-preview.html` / `.png` | No direct runtime screen; maps to `SpotterThemeOption.spicy` and future V2 theme selector/gallery | `Theme: Spicy`; `Red Line`; `Extreme Output`; `Inferno Circuit`; `Bring the Heat`; `12.4 MET Score`; `185 Peak HR`; `Spicy Tip` | Theme preview; orange/mint accents; warning/intensity cards | MET score and peak HR are unsupported. Do not surface as real metrics | D6 |

## Extracted Tokens

All 29 HTML files contain exactly one `:root` block, and every block is identical. The four theme preview HTML files do not override the root palette; theme differences appear as content and local accent colors inside cards. Swift should keep a constant V2 base palette and pull per-theme accent colors from `SpotterThemeOption`.

### Root Tokens

| Token | Value | Swift intent |
|---|---:|---|
| `--shape` | `round` | Rounded geometry |
| `--shape-multiplier` | `1` | No runtime shape scaling in D1 |
| `--background` | `#0D0D0D` | Main app background |
| `--foreground` | `#F2F0EB` | Primary text and cream border |
| `--primary` | `#C8FF00` | Hyper/default accent; override by theme where applicable |
| `--primary-foreground` | `#000000` | Text/icons on primary fill |
| `--secondary` | `#262626` | Secondary surface |
| `--secondary-foreground` | `#F2F0EB` | Text on secondary |
| `--muted` | `#262626` | Muted surface |
| `--muted-foreground` | `#A3A3A3` | Captions and secondary labels |
| `--accent` | `#C8FF00` | Same as primary in HTML; use theme accent in Swift |
| `--accent-foreground` | `#000000` | Text/icons on accent fill |
| `--destructive` | `#FF5C3A` | Errors/destructive affordances |
| `--card` | `#0D0D0D` | Cards often bleed into background |
| `--card-foreground` | `#F2F0EB` | Card text |
| `--popover` | `#0D0D0D` | Sheets/popovers |
| `--popover-foreground` | `#F2F0EB` | Popover text |
| `--border` | `#F2F0EB` | Cream outlines |
| `--input` | `#0D0D0D` | Inputs |
| `--ring` | `#C8FF00` | Focus ring; use theme accent |
| `--chart-1` | `#00D1FF` | Cyan chart/form accent |
| `--chart-2` | `#C8FF00` | Theme accent chart |
| `--chart-3` | `#FF5C3A` | Destructive chart |
| `--chart-4` | `#525252` | Grey chart |
| `--chart-5` | `#262626` | Dark chart |
| `--font-sans` | `"DM Sans"` | Do not bundle in D1; use system default |
| `--font-heading` | `"Space Grotesk"` | Do not bundle in D1; use system rounded/heavy |
| `--font-serif` | `"Playfair Display"` | Defer custom font use |
| `--font-mono` | `"JetBrains Mono"` | Use `.system(..., design: .monospaced)` |
| `--radius` | `1rem` | 16 px base |

### Typography

- HTML uses DM Sans for body, Space Grotesk for headings, JetBrains Mono for numerals, and Playfair Display rarely for accent copy.
- D0/D1 rule: do not bundle external fonts. Use system fonts only:
  - Heading/display: `.system(size:weight:design: .rounded)` or default system heavy where rounded feels too soft.
  - Body: `.system(size:weight:design: .default)`.
  - Metrics: `.system(size:weight:design: .monospaced).monospacedDigit()`.
- Used type sizes include `text-[7px]`, `8px`, `9px`, `10px`, `11px`, `12px`, `13px`, `14px`, `15px`, `17px`, `22px`, `26px`, Tailwind `text-xs` through `text-8xl`, and hero numerals at `92px`, `110px`, `140px`, `160px`, and `180px`.
- Used weights: medium, bold, black. Most display strings are uppercase and often italic.
- Tracking utilities include `tracking-tighter`, `tracking-tight`, `tracking-wider`, `tracking-widest`, and arbitrary positive tracking from `0.1em` through `0.4em`. The Swift implementation should avoid negative tracking per frontend guidance unless the repo explicitly accepts it; use compact heavy type without layout-breaking negative spacing.
- Leading utilities include `leading-[0.8]`, `leading-[0.85]`, `leading-[0.9]`, `leading-[1.1]`, `leading-none`, `leading-tight`, `leading-snug`, and `leading-relaxed`.

### Radius Scale

The HTML defines `--radius: 1rem` and Tailwind-derived radii:

| HTML radius | Pixel value | Swift token candidate |
|---|---:|---|
| `radius-xs` | 8 | `xs` |
| `radius-sm` | 12 | `sm` |
| `radius-md` | 14 | `mdTight` if needed |
| `radius-lg` | 16 | `md` |
| `radius-xl` | 20 | `lg` |
| `radius-2xl` | 24 | `xl` |
| `radius-3xl` | 32 | `xxl` |
| `radius-4xl` | 40 | `xxxl` |
| `rounded-full` | capsule/circle | `pill` |

Additional arbitrary radii used: 20, 24, 28, 32, 38, 40, 46, and 48 px. The nav pill specifically needs a 46 pt radius for a 92 pt height.

### Border Widths

- `border` = 1 px for fine separators and pills.
- `border-2` = 2 px for most cards, buttons, and tab chips.
- `border-4` = 4 px for hero cards, trophy cards, and large metric tiles.
- `border-b`, `border-b-2`, `border-t-2`, `border-t-4`, and `border-l-4` appear on headers, sheets, and callouts.
- `border-dashed` appears for placeholder/disabled surfaces.
- Border colors are mostly cream, primary/accent, cyan chart, destructive orange-red, and theme-local accent colors. Feature screens should not hardcode these; route through V2 tokens and `SpotterThemeOption`.

### Spacing Scale

Tailwind spacing maps to the standard 4 px grid:

| Utility | Value |
|---|---:|
| `p-3`, `m-3`, `gap-3`, `space-y-3` | 12 |
| `p-4`, `m-4`, `gap-4`, `space-y-4` | 16 |
| `p-5`, `m-5`, `gap-5` | 20 |
| `p-6`, `m-6`, `gap-6`, `space-y-6` | 24 |
| `p-8`, `m-8`, `space-y-8` | 32 |

Other used values: 2, 4, 6, 8, 10, 14, 40, 48, 64, 80, 96, 112, 128, and 144 px through utilities such as `p-12`, `pt-16`, `pt-20`, `pt-24`, `pb-28`, `pb-32`, and `pb-36`. Safe-area utilities appear in `pt-[env(safe-area-inset-top,44px)]` and `pb-[env(safe-area-inset-bottom,24px)]`.

### Shadows

- Hard offset shadows are a signature token. Common forms:
  - `3px 3px 0px 0px rgba(...)`
  - `4px 4px 0px 0px #C8FF00`
  - `4px 4px 0px 0px #FF00FF`
  - `4px 4px 0px 0px #FF6600`
  - `4px 4px 0px 0px #FFB000`
  - `8px 8px 0px 0px #C8FF00`
  - `8px 8px 0px 0px rgba(242,240,235,1)`
- Glow shadows appear around active/accent elements: `0 0 8/12/15/20/40px` with lime or per-theme accent opacity.
- Liquid glass nav uses `0 25px 50px -12px rgba(0,0,0,0.8)` plus `inset 0 1px 2px rgba(255,255,255,0.2)`.
- Bottom overlays use `0 -20px 50px rgba(0,0,0,0.5/0.8)`.
- Implementation note: SwiftUI has no exact hard-offset no-blur shadow API for all cases. Build offset shadows with a second rounded rectangle underlay.

### Motion

- Press states: `active:scale-95`, `active:scale-[0.98]`, `active:translate-x-1`, `active:translate-y-1`, and `active:shadow-none`.
- Hover/group states in HTML are reference-only for SwiftUI touch UI: border color changes, opacity changes, slight translate, and scale 1.10 on icon art.
- Repeating motion: `animate-pulse`, `animate-ping`, `animate-bounce`, and `animate-bounce-slow`.
- Transitions: `transition-all`, `transition-colors`, `transition-opacity`, `transition-transform`, with durations 300, 500, and 700 ms.
- V2 must respect Reduce Motion by disabling scale, opacity, bounce, ping, and pulse loops where they are decorative.

## Theme Accent Values

The constant HTML palette is shared. Per-theme accents should come from `SpotterThemeOption.accentColor` and `.secondaryAccentColor` in `VirtualTrainer/DesignSystem/Theme.swift`.

| Theme | Existing Swift accent | Existing Swift secondary accent | Design note |
|---|---:|---:|---|
| Hyper | approx `#C7FF00` (design root `#C8FF00`) | `#00D1FF` | Matches the base lime/cyan visual family, with minor numeric rounding in Swift |
| Hot Girl | `#FF00B8` | approx `#00FFEB` | HTML preview also uses hot pink `#FF00FF` locally; Swift source remains the authority |
| Warm | approx `#FFB000` | approx `#7D3BED` (design local `#7C3AED`) | Matches warm gold plus violet, with minor rounding |
| Spicy | approx `#FF5C00` | approx `#00FFC2` | Matches spicy orange plus mint |

## Design-Only Features To Defer

These are visible in the design but unsupported or intentionally hidden in code. Do not build them as real product behavior in V2.

| Feature | Screen refs | Code reality | V2 action |
|---|---|---|---|
| Login / `Already have an account? Log in` | `welcome-screen.html` | Apple linking currently throws backend unavailable; account management is not a real login surface yet | Hide or render disabled/coming soon |
| Smart swaps / AI alternatives | `exercise-swap-sheet-v2.html`; implied by workout preview | `PlanSwapService` exists but plan-detail swapping is intentionally hidden | Do not expose; use target edit only |
| Plan-level `Swap All` | `workout-preview.html`, `coach-selector.html` | Product decision says hidden | Omit |
| Pull Ups in form check list | `form-check-selection.html` | Not in current 47-exercise library | Omit or disabled unavailable |
| Running Analysis active flow | `quick-start.html` | Phase 20 research stub only | Coming Soon card |
| BPM / heart-rate trophies | `trophies.html`, `trophy-collection---expanded.html`, `spicy-theme-preview.html` | No HR sensor integration | Coming Soon |
| KG total volume trophies | `trophies.html` | No external load tracking | Coming Soon |
| Burpee Beast | `trophy-collection---expanded.html` | Burpees unsupported by current exercise library | Coming Soon or omit from active progress |
| Calories/KCAL | `profile.html`, `workout-detail-sheet.html`, `hot-girl-theme-preview.html` | No robust calorie model | Do not surface as real metrics |
| MET score | `spicy-theme-preview.html` | No validated MET model | Do not surface as real metric |
| Trophy/collection share artifact | `trophies.html`, `trophy-collection---expanded.html` | Heatmap share exists; trophy collection poster is deferred | Disabled/coming soon affordance |
| Rich range/depth/velocity metrics | `rest-screen.html`, `workout-evidence.html` | Some rep/form evidence exists, but generic range/depth/velocity metrics are not production fields | Use available evidence; mark missing sections coming soon |
| External profile/avatar imagery | theme previews, `profile.html`, `welcome-screen.html` | No user avatar pipeline today | Use initials or SF Symbol fallback |

## Code-Only Features To Style In V2

These are real product/code surfaces not represented in the HTML. Future D2-D6 phases should preserve them and style them with V2 tokens/components.

| Feature | File ref | V2 styling direction |
|---|---|---|
| Backend mode debug switch | `VirtualTrainer/UI/ProfileView.swift` | DEBUG-only profile/settings card with cream border and backend status chip |
| Backend status fallback banner | `BackendStatusStore` usage in `ProfileView.swift` and future dashboard | Muted warning card with destructive tint and sanitized copy |
| Sync diagnostics | `ProfileView.swift`, `SyncOrchestrator` | DEBUG-only V2 diagnostics card: last sync, pending, conflicts, listeners, last error |
| Firebase smoke test button | `ProfileView.swift` | DEBUG-only compact action row |
| Export My Data | `ProfileView.swift`, `DataExportService` | Account section secondary button with share icon |
| Delete My Account and Data | `ProfileView.swift`, `AccountDeletionService` | Destructive card/button with typed DELETE confirmation |
| Free Analysis summary | `CameraTabView.swift`, `WorkoutSummaryView.swift` | Reuse V2 summary with `FREE ANALYSIS` eyebrow and single-exercise stats |
| Weekly recap | `WeeklyRecapBuilder`, `HomeDashboardView.swift`, `ProfileView.swift` | V2 recap card using chart/metric language |
| Insight evidence sheet | `InsightEvidenceSheetView.swift` | Match `workout-evidence.html` evidence language where data exists |
| Insight engagement controls | `InsightEngagementControls.swift` | Small icon controls with selected accent/destructive states |
| 12-week heatmap drill-in | `TrainingHeatmapView.swift`, `ProfileView.swift` | Match profile heatmap module and preserve day drill-in sheets |
| Share Heatmap | `TrainingHeatmapView.swift`, `ShareCardRenderer.swift` | Keep enabled; style CTA with V2 secondary button |
| Calendar snapshot | `CalendarSnapshotView.swift`, `ProfileView.swift` | V2 collapsed card/list module |
| Calibration failed/skipped states | `CalibrationViews.swift`, `CalibrationStore` | Use same shell as calibration intro/readiness with state copy |
| Camera permission denied | `CameraTabView.swift`, `BodyVisibilityBannerView.swift` | Use camera-readiness visual language with Settings CTA |
| Empty states | Multiple V1 views | Bold V2 heading, one-line muted body, honest CTA |
| Workout delete from detail | `WorkoutDetailSheetView.swift` | V2 destructive button; preserve tombstone behavior |
| Cost snapshot/debug counters | `ProfileView.swift` | DEBUG-only backend diagnostics subcard |

## Design And Code Parity: Use Code Truth

| Design element | Implementation rule |
|---|---|
| Streak/form/rep/duration hero metrics | Use `StatsEngine`, `TrendEngine`, `WorkoutHistoryStore`, and workout summaries. Do not fake values |
| Quick Start and Daily Plan cards | Use generated plan data from `QuickStartPlanDeckService`, `PlanService`, and profile preferences |
| Coach selector | Bind to Bennett/Fletcher only via `CoachPreference` and `CoachPersonality` |
| Trophy states | Bind to `TrophyStore`/`TrophyEngine`, including coming-soon/unavailable confidence |
| Heatmap intensity | Use `TrendEngine.dailyIntensitySummary` |
| Planned workout and Free Analysis camera flows | Preserve shared live trainer stack. V2 can restyle shell/HUD only |
| Backend modes | Preserve `.local` and `.firebase` behavior and local fallback without Firebase plist |
| Theme selection | Use `ThemeStore` and `UserProfile.selectedTheme`; in Firebase mode it syncs through profile-backed theme behavior |

## Imagery Inventory And Decisions

| Source | Screen refs | Present in repo? | D0 decision |
|---|---|---|---|
| Supabase setup background `nh6aJcdq2mi.png` | `calibration-1.html` | No | Skip/bundle later only if licensed; D3 can use SF Symbol or V2 camera/setup illustration built in SwiftUI |
| Supabase camera preview `NYB5Q30elt4.png` | `camera-readiness.html` | No | Do not bundle; use live preview/readiness shell or SF `viewfinder`/`iphone` fallback |
| Supabase workout theme `LiVHeu9OKzi.png` | `workout-preview.html`, `coach-selector.html`, swap sheets | No | Do not bundle in D0-D5 unless asset is explicitly added/licensed; use gradient-free dark hero with exercise/coach assets or SF fallback |
| Supabase Coach Bennet JPG | `coach-selector.html` | Yes, equivalent `CoachBennet.imageset/Good_coach_Bennet.jpg` | Use existing asset |
| Supabase Coach Fletcher JPG | `coach-selector.html` | Yes, equivalent `CoachFletcher.imageset/Drill_Sargeant_Coach_Fletcher.jpg` | Use existing asset |
| Google avatar URL | profile/theme/dashboard/trophy previews | No | Use initials or `person.fill`; do not fetch remote avatar |
| Supabase component images `Q1i0CO80OIy.png`, `iuSP3ZeKnBX.png`, `ciIdrIxkQGp.png` | expanded hyper dashboard previews | No | Skip decorative imagery; use data cards and SF Symbols |
| `placeholder:img-workout-man-squat` | `live-workout.html`, copy | No | Do not replace live camera; existing camera preview remains source |
| Supabase welcome hero `4TeBMAGgWdP.png` | `welcome-screen.html` | No | Use built-in V2 card art/SF Symbol fallback unless an app-owned bitmap is added |
| randomuser portraits | `welcome-screen.html` | No | Do not bundle; use CoachBennet/CoachFletcher or SF initials |
| `generation-assets/placeholder/square.png` | `workout-preview.html` | No | Replace with existing coach asset or initials/SF fallback |

## D0 Notes For Future PR Summaries

- V2 components introduced in D0: none. This phase introduces documentation only.
- V1 surfaces unchanged in D0: all SwiftUI screens, live camera pipeline, backend repositories, Firestore rules, sync, onboarding, calibration, profile, trophies, and insights.
- Feature-flag-off screenshot description for D0: not applicable because no runtime UI changed; existing V1 remains the only rendered app.
- Feature-flag-on screenshot description for D0: not applicable because D1 toggle/root shell does not exist yet.
- Practical before/after: before D0, the new design exports were visual references without an implementation inventory. After D0, every exported screen is mapped to code reality, phase ownership, design-only deferrals, code-only preservation work, tokens, imagery decisions, and icon replacements.
