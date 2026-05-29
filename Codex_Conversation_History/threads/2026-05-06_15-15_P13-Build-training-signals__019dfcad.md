# P13: Build training signals

- Thread ID: 019dfcad-8767-7633-b95c-8983b64bb3c7
- Created: 2026-05-06 15:15:24 (Asia/Kolkata)
- Updated: 2026-05-06 16:55:57 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/06/rollout-2026-05-06T15-15-24-019dfcad-8767-7633-b95c-8983b64bb3c7.jsonl
- Git branch at thread start: main
- Git SHA at thread start: b3041953e69a2e7d55c8d3a24a17640add1be2d0
- Exported visible messages: 34
- Extracted input images: 0

## Conversation

### User - 2026-05-06 15:19:25

Before changing code:
1. Deeply inspect the current repo structure.
2. Read the relevant files before editing.
3. Treat this prompt as the implementation reference, not a blind spec. If the codebase reveals a better engineering decision, make it and explain why.
4. Do not rewrite MediaPipe, CameraManager, PoseEstimator, UniversalRepCounter, FormFeedbackEngine, HandGestureDetector, ExertionAnalyzer, or the core live camera pipeline unless absolutely necessary.
5. Preserve both live flows:
   - Camera tab free analysis
   - Planned workout sessions
6. Keep UI functional and simple for now. Do not do the final visual design-system revamp unless explicitly requested.
7. Keep business logic out of SwiftUI views wherever practical.
8. Keep existing local-first behavior.
9. Do not store or upload raw camera frames, raw video, face images, raw pose streams, or raw biometric face data.
10. Do not print or expose secret values.
11. Keep the app compiling after the phase.
12. Run available tests/build commands and summarize results.
13. Summarize changed files, key decisions, and known follow-up items.
14. Share an end to end manual testing plan of the changes done

Use the common Spotter Codex preflight block.

Phase 13 goal:
Build the trend and signal layer that powers user-centric AI insights, profile snapshot, plan feedback, and future progression.

Important files to inspect:
- WorkoutSessionSummary.swift
- WorkoutHistoryStore.swift
- WorkoutDetailSheetView.swift
- UserProfile.swift
- StatsEngine from Phase 12
- TrophyStore from Phase 11
- PlanGenerator.swift
- PlanService.swift

Do not build final AI copy in this phase.
This phase extracts meaningful facts and trends.

Create models:

1. UserTrainingSignal
- id
- type
- exerciseType optional
- movementPattern optional
- goal optional
- title
- value
- comparisonValue optional
- delta optional
- confidence
- evidenceRefs
- createdAt

2. TrainingSignalType
- consistency
- formImprovement
- formDropOff
- volumeIncrease
- volumeDrop
- completion
- fatigue
- restBehavior
- skippedExercise
- repeatedCue
- exerciseMastery
- exerciseStruggle
- planFit
- trophyProximity
- cameraFriction

3. SignalConfidence
- high
- medium
- low

4. TrendWindow
- latestWorkout
- threeWorkout
- sevenWorkout
- currentWeek
- currentMonth

5. ExerciseTrendSummary
- exerciseType
- sessions
- totalReps
- totalHoldSeconds
- averageFormScore
- bestFormScore
- recentFormDelta
- mostCommonCue
- breakdownRepIndex
- improvementRepIndex
- goodFormRepCount
- excellentFormRepCount

6. UserTrainingTrendSnapshot
- generatedAt
- totalWorkouts
- currentStreak
- workoutsThisWeek
- weeklyConsistencyStatus
- overallFormTrend
- volumeTrend
- fatigueTrend
- strongestExercise
- improvingExercise
- strugglingExercise
- mostRepeatedCue
- trophyNearMisses
- cameraFrictionCount
- exerciseTrends

Create services:

1. TrendEngine
- buildSnapshot(history, profile, trophies)
- dailyWorkoutCounts
- dailyTotalReps
- dailyHoldSeconds
- dailyAverageForm
- dailyDuration
- currentStreak
- longestStreak
- threeWorkoutComparison
- sevenWorkoutComparison
- monthSnapshot

2. SignalExtractor
- extractSignals(snapshot, history, profile, trophies)

Signal extraction examples:
- form improved by meaningful threshold
- form dropped in second half of sets
- repeated cue appears across multiple sessions
- user completed more reps than previous comparable session
- user repeatedly skips/rest-extends a movement
- streak is close to a milestone
- trophy is near unlock
- a limitation conflicts with repeated exercise struggles
- camera readiness or visibility friction appears repeatedly

3. WorkoutCalendarSnapshot
- days
- currentMonth
- completedDays
- streak

4. CalendarSnapshotView
- raw grid for profile
- empty state safe
- local timezone

Rules:
- Do not shame missed days.
- Do not make medical claims.
- Do not use unsupported calorie/fat-loss claims.
- Do not infer heart rate from face-effort proxy.
- Prefer high-confidence signals. 
- feel free to add more models or signals, evaluate your ideas and implement the high conviction, high impact ones in addition to the ones listed in the prompt above. goal is to have a very strong deeply user-first and engaging trend, signal engine.

Tests:
1. Current streak calculation.
2. Longest streak calculation.
3. Multiple workouts same day count once for streak.
4. 7-day average form calculation.
5. Strongest exercise detection.
6. Improving exercise detection.
7. Struggling exercise detection from repeated cues/form drop.
8. Trophy proximity signal.
9. Camera friction signal if data exists.
10. Empty history produces safe empty snapshot.
11. Timezone boundaries are stable.

Acceptance criteria:
- TrendEngine produces stable snapshots.
- SignalExtractor produces user-meaningful signals.
- Profile can render a calendar/snapshot from real data.
- AI insight engine can consume signals instead of raw scattered data.

### Assistant - 2026-05-06 15:19:38

I’ll start by mapping the repo and looking for the project’s own preflight conventions before touching code. Then I’ll read the phase-relevant model/service/view files and let the existing architecture steer the implementation.

### Assistant - 2026-05-06 15:19:47

Repo shape is a straightforward SwiftUI/Xcode app with models, services, UI, and XCTest targets. I don’t see an obvious preflight snippet yet, so I’m going to inspect the README/context docs around the phase history and then read the named Swift files in depth.

### Assistant - 2026-05-06 15:20:35

The existing data layer already has most of the raw ingredients: per-set cue events, rep-quality summaries, rest/skipped flags, structured effort proxy, trophy progress, and profile limitations. I’m going to keep the new phase as deterministic models/services plus a light profile rendering path, instead of pushing logic into SwiftUI or touching the live camera stack.

### Assistant - 2026-05-06 15:21:23

I found the test command in the README and the project is using Xcode’s file-system-synchronized groups, so new Swift files should be picked up without hand-editing the project file. The preflight I’m applying is: workspace build/test path, clean worktree except branch ahead, no live pipeline edits, no raw camera data persistence, and deterministic local facts only.

### Assistant - 2026-05-06 15:22:47

I’m ready to edit now. I’ll add the trend/signal layer as new model/service files, then swap the profile’s placeholder weekly strip for a reusable calendar snapshot and deterministic signal list.

### Assistant - 2026-05-06 15:29:38

The core services are now in place. I’m going to wire them into Profile in a narrow way: build the snapshot once for the view, render the calendar from the snapshot model, and show signal rows rather than writing any final “AI coach” prose.

### Assistant - 2026-05-06 15:30:56

Profile wiring is in. I’m adding focused tests next so the phase behavior is pinned down around streaks, timezone boundaries, exercise trends, trophy proximity, camera friction, and empty history safety.

### Assistant - 2026-05-06 15:32:49

The Phase 13 tests are written. I’m going to run the focused trend test target first so compiler/type issues surface quickly, then I’ll run the broader workspace test/build path from the README.

### Assistant - 2026-05-06 15:33:16

The first focused run caught a small Swift call-site issue in `SignalExtractor` before tests started. I’m patching that and rerunning the focused suite.

### Assistant - 2026-05-06 15:34:09

The focused build now gets through compilation and is waiting/running in the simulator test phase. I’m letting it finish rather than interrupting, since the MediaPipe app target has a bit of simulator startup overhead.

### Assistant - 2026-05-06 15:34:24

Focused Phase 13 tests passed: 11/11. I’m moving to the full workspace test command now, then I’ll do a simulator build as a final compile check.

### Assistant - 2026-05-06 15:34:59

Full tests are in the simulator phase now. The compile step is clean; I’m waiting on the full XCTest run to finish so I can catch any cross-suite regression, not just the new trend tests.

### Assistant - 2026-05-06 15:35:20

Full XCTest passed. I’m doing the separate `xcodebuild build` now as the final compile/package check, matching the project’s existing verification habit.

### Assistant - 2026-05-06 15:35:36

Tests and build are green. I’m doing a quick diff/whitespace/privacy sanity pass now, then I’ll summarize the exact changed files and the manual end-to-end QA path.

### Assistant - 2026-05-06 15:36:38

Implemented Phase 13’s deterministic trend and signal layer.

**What Changed**
- Added trend/signal models in [TrainingTrendModels.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/TrainingTrendModels.swift:3>).
- Added [TrendEngine.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/TrendEngine.swift:3>) for snapshots, streaks, daily aggregates, exercise trends, trophy near-misses, camera friction, and month calendar data.
- Added [SignalExtractor.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/SignalExtractor.swift:3>) for user-meaningful structured signals.
- Added [CalendarSnapshotView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/CalendarSnapshotView.swift:3>) and wired Profile to real trend/calendar data in [ProfileView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/ProfileView.swift:57>).
- Added focused Phase 13 coverage in [TrendEngineTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/TrendEngineTests.swift:1>).

**Key Decisions**
- I did not touch MediaPipe, CameraManager, PoseEstimator, UniversalRepCounter, feedback engines, gesture detection, exertion analysis, or the live camera pipeline.
- I kept PlanGenerator/PlanService unchanged for now. The new `planFit` and struggle signals create the facts future plan feedback can consume without risking current live flows.
- Signals store only derived evidence refs: workout IDs, exercise IDs, set/rep indexes, cue labels, and dates. No raw frames, raw video, raw pose streams, face images, or biometric face data.
- UI stays simple and functional: profile now shows a raw calendar snapshot plus structured signal rows, not final AI copy.

**Verification**
- `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VirtualTrainerTests/TrendEngineTests` passed, 11/11.
- Full `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` succeeded.
- `xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` succeeded.
- `git diff --check` clean.
- Secret/raw-data term scan over changed files found no matches.

**Manual Test Plan**
1. Launch app, complete onboarding if needed, open Profile with empty history. Confirm calendar empty state and no crashes.
2. Use Camera tab free analysis, save a session, return to Profile. Confirm workout day appears, stats/history update, detail sheet still opens.
3. Start a planned workout from the plan preview, complete sets/rest, save summary. Confirm Profile calendar, stats, history, trophies, and signal rows update.
4. Create repeated cue/rest/skipped-set scenarios through saved sessions. Confirm repeated cue, rest behavior, skipped exercise, or struggle signals appear.
5. Check Trophy/Profile after near-threshold trophy progress. Confirm trophy proximity signal appears without unsupported heart-rate/calorie claims.
6. Run both live flows again: Camera tab free analysis and planned session. Confirm no regression in camera startup, set completion, rest, and summary save.

### User - 2026-05-06 16:41:20

[compact your context first before proceeding with this prompt] 
Do another in-depth deep audit of the entire codebase and check if there are any unwired code or dependencies or app crashes [ app crashes prevention are important] or bugs - evaluate and resolve them. ALso look for possible incomplete codes, logics, and ways to improve / strengthen existing - evaluate them deeply and only implement the highest confidence and priority ones. especially review the recent code changes (phase 11 (trophye engine) and phase 12 (profile hub) and phase 13 (training signals and trends)) and the older code deeply and check for errors, crashes or new bugs. 

Post the above, share an end to end manual testing plan for the features in this chat. think deeply and use highest level of reasoning. be very detailed and in depth and evaluate the code with the highest possible technical lens for bugs, etc - code quality can be skipped, we will improve that later. looking for funtiomnal bugs, crashes, suspicious screens - for parts that are sus and might require a round of manual review - call them out and mention in the end to end testing plan so i can verify those too. Post this we will proceed to phase 14 - the AI coach.

Understand each and every exercise and implications of recent changes on them. Evaluate if there is anything to be fixed or improved there and implement the high priority ones. We need the code to be tight and error free. Do not increase the strictness of any exercises or achievements - try to expand and deepen. 

Be very detailed and comprehensive in your evaluation.  We want to build the best exercise insights and trophy engine there is in the fitness industry that drives repeat visitors and stickiness and engagement. deeply analyse with this perspective and suggest improvements. 

IMPORTANT: IF YOU DO NOT FIND ANYTHING PRESSING WORTH FIXING OR IMPROVING - CALL THAT OUT AND DO NOT DO ANYTHING. YOU DON'T HAVE TO MANDATORILY FIND STUFF TO IMPROVE.

### Assistant - 2026-05-06 16:41:36

Context checkpoint before I touch anything: current repo is a SwiftUI/Xcode iOS app with local-first history, trophies, profile hub, and the new Phase 13 trend/signal layer. I’ll audit for functional bugs/crashes/unwired paths first, then only patch issues that look high-confidence and high-impact.

### Assistant - 2026-05-06 16:42:04

I’ve confirmed the current worktree is the Phase 13 uncommitted set on top of `main` and the project is still using file-system-synchronized Xcode groups, so the new files compile without project-file wiring. Next I’m narrowing the audit from noisy text hits into actual crash/logic risk patterns: force unwraps/casts, persistence decode paths, trophy/profile/signal assumptions, and per-exercise metadata invariants.

### Assistant - 2026-05-06 16:43:10

I’ve kept the Phase 13 context intact and I’m continuing from the audit rather than starting over. I’m going to read the crash-prone and recently touched areas next, then I’ll only patch anything that looks both high-confidence and worth fixing now.

### Assistant - 2026-05-06 16:43:35

The first pass is separating noisy pattern matches from real risk. So far the indexed areas I checked mostly have guards around them; I’m drilling into the plan editing and recent trend/signal logic where a subtle bug would be more likely than an obvious crash.

### Assistant - 2026-05-06 16:45:20

One concrete Phase 13 logic issue is emerging: the snapshot already calculates weekly active days, but the user-facing completion signal still describes “workouts this week,” so two same-day sessions can look like a weekly day target was met. That’s not a crash, but it is a high-confidence insight bug, and it’s exactly the kind of thing that would make the signal layer feel off.

### Assistant - 2026-05-06 16:46:33

I’m going to patch that weekly-target signal now. The change is deliberately small: keep raw session count for stats, add active-day count to the trend snapshot, and make the completion signal use days so repeated same-day workouts don’t inflate consistency feedback.

### Assistant - 2026-05-06 16:47:37

The patch is in. I’m moving into verification now: first the focused TrendEngine suite, then the full project test/build if that passes.

### Assistant - 2026-05-06 16:48:45

Focused TrendEngine tests passed, including the new same-day active-day signal check. I’m running the full suite now so we catch regressions outside the new layer too.

### Assistant - 2026-05-06 16:49:34

The full suite is still running; no failure output so far. While it runs, the remaining audit notes are mostly “watch manually” rather than patch-worthy: summary coach-copy is still placeholder-grade, and profile/dashboard streaks outside TrendEngine still use their injected/current calendars rather than the profile timezone.

### Assistant - 2026-05-06 16:50:18

Full tests passed. I’m doing a plain build plus a whitespace/diff sanity check now; after that I’ll wrap the audit with the specific fixes, non-fixes, and a manual test plan.

### Assistant - 2026-05-06 16:51:39

**Audit Result**
I found one high-confidence Phase 13 insight bug worth fixing: weekly completion signals were based on session count even though the consistency engine correctly uses unique active days. Two workouts on the same day could make the AI signal sound more “on target” than it really was.

Fixed by adding `workoutDaysThisWeek` to the trend snapshot and making completion signals use active training days:
[TrainingTrendModels.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/TrainingTrendModels.swift:238>)  
[TrendEngine.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/TrendEngine.swift:19>)  
[SignalExtractor.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/SignalExtractor.swift:104>)  
[TrendEngineTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/TrendEngineTests.swift:242>)

**What I Audited**
I reviewed repo structure, CocoaPods/MediaPipe wiring, Xcode file synchronization, live camera entry points, planned workout flow, free analysis flow, history persistence, trophies, profile hub, trend/signal extraction, workout detail rendering, plan generation, exercise metadata, and crash-prone indexing/force patterns.

I did not rewrite MediaPipe, `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, `FormFeedbackEngine`, `HandGestureDetector`, `ExertionAnalyzer`, or the live camera pipeline. Recent changes remain local-first and do not store raw frames, raw video, raw pose streams, face images, or biometric face data.

**What Looked Solid**
Crash-risk indexed areas in plan editing, planned workout coordination, frame analysis, quick-start plan generation, hand gesture fallback, onboarding flow layout, and summary/detail views are guarded or covered by tests.

Exercise implications looked stable: every `ExerciseType` has metadata and an `ExerciseLibrary` definition, planned workout eligibility is metadata-driven, camera switch limits are tested, and all exercise trend extraction consumes saved summary facts rather than changing rep-counting strictness.

No dependency issue stood out. `Podfile` and `Podfile.lock` are aligned on `MediaPipeTasksVision 0.10.33`, and the filesystem-synchronized Xcode groups mean the new Phase 13 files are compiled without project file churn.

**Not Fixed**
I did not change these because they are not pressing bugs:
- Workout summary “Coach Insight” copy is still placeholder-grade until Phase 14.
- Profile/dashboard legacy stats still count “workouts this week” as sessions, while the new signal layer now uses active days for consistency. This is acceptable as stats, but worth UX review.
- Live camera behavior still needs real-device/manual validation because simulator tests cannot validate camera permission, MediaPipe model runtime, lighting, framing, and gesture readiness end to end.

**Verification**
- `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VirtualTrainerTests/TrendEngineTests` passed, 12 TrendEngine tests.
- `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `git diff --check` passed.

**Manual Testing Plan**
1. Fresh install/onboarding: complete onboarding with each goal, strength/performance/longevity, and verify Dashboard, Trophies, Camera, Profile tabs open without empty-state crashes.

2. Camera free analysis: run at least squat, pushup, plank, lunge, bicep curl, jumping jack, and one yoga hold. Save each summary, open detail, confirm reps/holds/form/cues appear and Profile signals update.

3. Planned workouts: generate Smart Start and Daily Plan, preview, edit reps/sets/hold targets, swap one exercise, start session, complete all sets, extend rest once, skip one rest once, save, and verify history/detail/trophies/signals.

4. Trophy flows: verify first saved workout unlocks The Spark, calibration unlocks Calibrated, near-progress trophies show “Closest Trophy,” coming-soon trophies stay unavailable, and no heart-rate or load trophy unlocks from face-effort proxy.

5. Profile hub: with no history, verify calendar and signals show safe empty states. With history, verify calendar dots, streak, form trend, volume trend, repeated cue, strongest/improving/struggling exercise, camera friction, and trophy proximity.

6. Weekly active-day edge case: save two workouts on the same calendar day. Profile can show 2 workouts this week, but Training Signals should say 1 active day toward the weekly target.

7. Timezone edge case: test a workout near midnight local time, especially Asia/Kolkata, then confirm calendar day and streak do not shift unexpectedly.

8. Camera friction: intentionally stand too close, too far, and partly out of frame in free analysis and planned workout. Save sessions and confirm repeated visibility cues can surface as camera friction signals.

9. Exercise coverage smoke pass: manually open free-analysis readiness for every listed exercise category. Confirm setup copy, required view, and camera readiness do not crash before starting.

10. App-crash pass: background/foreground during readiness, active set, rest screen, summary sheet, trophy sheet, and profile detail sheet. Confirm camera stops on exit and no stale session resumes unexpectedly.

### User - 2026-05-06 16:53:00

We want to build the best exercise insights and trophy engine there is in the fitness industry that drives repeat visitors and stickiness and engagement. deeply analyse with this perspective and suggest improvements. Want to try to expand and deepen. give a detailed list of what we can do and then we will proceed building the ones that make sense now.

### Assistant - 2026-05-06 16:53:19

I’ll ground this in the current trophy, trend, and saved-history shape first so the suggestions are tied to what the app can actually measure today, not fantasy metrics. Then I’ll give you a prioritized menu of improvements with what each one would unlock.

### Assistant - 2026-05-06 16:54:20

I’ll re-ground this in the actual Spotter data model before suggesting anything, so the recommendations stay buildable instead of becoming a shiny wish list. I’m going to inspect the current trend, trophy, workout-summary, plan, and profile wiring without changing files.

### Assistant - 2026-05-06 16:54:34

The first pass confirms the app already has the right “facts” to build from: saved sessions, per-set cue events, rep-quality events, rest/skips, completion, calibration, trophy progress, and trend snapshots. I’m checking the exercise catalog next so the improvement list respects the actual movement patterns and doesn’t accidentally invent unsupported signals.

### Assistant - 2026-05-06 16:54:50

The catalog is broader than a basic demo: 47 tracked movements across lower, upper, full-body/core, and yoga, with camera-position and isometric metadata already available. That means the strongest next layer is not “more raw tracking”; it is richer derived facts, smarter trophy surfacing, and plan feedback that reuses the current local summaries.

### Assistant - 2026-05-06 16:55:57

I inspected the current repo shape first. No code changed.

Grounding: Spotter already has enough local, derived data to build a very strong insight loop: saved sessions, reps, holds, average form, rep-quality events, cue events, rest extensions, skipped sets, completion, calibration, camera-friction cues, profile limitations, plan metadata, movement patterns, and trophy progress. The biggest opportunity is not more raw tracking yet; it is turning those facts into a tight “what changed, what matters, what should I chase next” layer.

**Highest-Value Build Now**
1. **Personal Records Engine**
   Track per-exercise PRs: best reps in a session, best set, best hold, best average form, best cue-free set, best good-form rep streak, best excellent-form rep streak. This creates a win after almost every workout.

2. **Trophy Recommendation Engine**
   Move beyond nearest progress. Rank trophies by: close to unlock, relevant to user goal, supported by current equipment, compatible with limitations, and realistically achievable in the next 1-3 sessions.

3. **Exercise Mastery Ladder**
   Add local mastery levels per exercise: Started, Building, Reliable, Sharp, Mastered. Use sessions, volume, form, cue rate, recent improvement, and camera friction. Avoid making trophies stricter; this should add more ways to feel progress.

4. **Cue Journey Engine**
   Detect cue trends: repeated cue, cue improving, cue disappeared, cue shifted from warning to low severity, cue returns under fatigue. This is one of the most user-centric insight layers because it makes form feel learnable.

5. **Plan Fit Snapshot**
   Create a derived snapshot for future AI coach and plan feedback: exercises completed smoothly, exercises repeatedly skipped, rest-extended, form-faded, camera-friction-heavy, or conflicting with profile limitations.

6. **Movement Pattern Coverage**
   Show balanced training across squat, hinge, lunge, push, pull, core flexion, core anti-extension, rotation, balance, cardio, mobility, and yoga holds. Phrase as opportunity, not guilt.

7. **Weekly Recap Facts**
   Generate local weekly facts: strongest exercise, biggest improvement, most repeated cue, trophy closest to unlock, best active day pattern, volume/form direction, and one suggested focus.

8. **Camera Friction Reducer**
   Group camera issues by exercise and camera position. Example: “Side-view movements caused most visibility cues this week.” This can power pre-session setup prompts and camera trophies.

9. **Fatigue/Recovery Signals, Carefully Worded**
   Use only supported facts: form fade, rest extension, skipped sets, completion drop, and effort proxy. Do not infer heart rate, calories, medical readiness, or overtraining.

10. **Trophy Families and Tiers**
   Expand the catalog with families: consistency, form, movement patterns, exercise mastery, comeback, plan completion, camera setup, and cue improvement. Add bronze/silver/gold style tiers without changing existing unlock strictness.

**Exercise-Specific Opportunities**
- Lower body: squat/sumo/chair/wall-sit trophies around clean depth, consistency, hold time, and knee-tracking cue improvement.
- Lunges/step-ups: balance/control signals, repeated side/framing issues, lower-body unilateral mastery.
- Hinges/glutes: hinge consistency, lower-back-sensitive plan-fit checks, posterior-chain volume trophies.
- Upper push: pushup/incline/tricep/press mastery, shoulder/wrist limitation conflict detection.
- Pull/curl: dumbbell equipment-aware trophies and volume progression.
- Core: plank/side-plank hold PRs, anti-extension mastery, core rotation volume.
- Cardio/full-body: high-impact-safe handling for jumping jacks, high knees, mountain climbers; no calorie claims.
- Yoga/mobility: hold duration, balance stability, mobility consistency, longevity-goal alignment.

**Engagement Loops**
- “Next best chase”: one trophy or PR to pursue before each workout.
- “One thing improved”: immediate post-workout fact, not AI fluff.
- “One thing to clean up”: repeated cue or camera setup issue.
- “Comeback” recognition after gaps, without shaming missed days.
- Profile snapshot cards: PRs, mastery, trophy chase, weekly recap.
- Workout detail sheet: evidence refs behind every signal.

**Defer Until Data Exists**
- Heart-rate trophies remain coming soon unless a real HR source is added.
- Load/KG volume trophies remain coming soon unless user-entered or connected weight data exists.
- Calorie/fat-loss claims should stay out.
- No raw frames, raw video, raw pose streams, or biometric face data should be stored.

My recommended next build bundle is: **Personal Records Engine + Trophy Recommendation Engine + Exercise Mastery Ladder + Plan Fit Snapshot + Weekly Recap Facts**. That gives Phase 14 AI coach clean, high-confidence facts to consume instead of scattered workout history.
