# P14_J: Update goal-aware ranking

- Thread ID: 019e01c9-a179-7933-b51e-174cad5d54f1
- Created: 2026-05-07 15:04:11 (Asia/Kolkata)
- Updated: 2026-05-07 15:22:43 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T15-04-11-019e01c9-a179-7933-b51e-174cad5d54f1.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a8305d617f2abab60b3b8df7bd7426bfdc252375
- Exported visible messages: 11
- Extracted input images: 0

## Conversation

### User - 2026-05-07 15:04:15

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
14. Share an end to end manual testing plan of the changes done. In simple words explain what we have fixed with real life examples if possible to understand. better (before - after)
15. Post building, Review the implementation and suggest ways to expand and deepen this coaching engine. Implement the highest leverage ones ensuring the code is stable and does not break existing functionalities. 

Codex Prompt 1.H — Goal-aware ranking, drill-down evidence sheet, weekly story
TASK
Three related upgrades that compound into the engine feeling "smart":

1. GOAL-AWARE RANKING
   In InsightRanker.score, replace the flat `relatedGoal != nil → +4` with:
   - +10 if `candidate.relatedGoal == profile.primaryGoal`
   - +3 if `candidate.relatedGoal != nil` but mismatched
   - additionally, per-goal type weights:
       .strength    → boost progressionReadiness, qualityPR, exerciseMastery (+6)
       .longevity   → boost recovery, planFit, sessionFit, restResponse (+8)
       .performance → boost progressionReadiness, qualityCapacity, formImprovement (+6)
   Pass `profile: UserProfile` into ranker.score (call sites already have it).

2. DRILL-DOWN EVIDENCE SHEET
   Add `InsightEvidenceSheetView` that opens from any insight card. It shows:
   - The headline + long message.
   - "Based on" list: each evidenceRef rendered as a tappable row (workout date,
     exercise, set, rep) that opens the relevant WorkoutDetailSheetView.
   - "Confidence: high/medium" pill.
   - "Was this helpful?" engagement (👍 / 👎) wired to InsightStore.recordEngagement
     from prompt 1.A.

3. WEEKLY STORY
   Add `Services/WeeklyRecapBuilder.swift` that produces one composite insight per ISO
   week:
     WeeklyRecap {
        let weekStart, weekEnd
        let headline, narrative
        let stats: [LabeledStat]   // sessions, avg form, total reps, hold seconds, trophies earned
        let topMoment, biggestSurprise, nextWeekFocus
     }
   Surface it on Profile and on Dashboard once per week (Sunday evening or Monday
   morning depending on user's timezone). Persist its dedupeKey so it appears once
   per week per surface.

CONSTRAINTS
- Existing tests must still pass.
- WeeklyRecap must include at least one piece of evidence and a forward-looking nudge.

ACCEPTANCE
- InsightRankerTests cover all four goal × signal-type combinations.
- New EvidenceSheet snapshot test.
- New WeeklyRecapBuilderTests cover empty week, normal week, and "all rest week"
  (no sessions). The empty-week recap should still acknowledge the rest.

Share a very detailed manual testing plan after implementing the above as it is slightly more complex to do the above.

### Assistant - 2026-05-07 15:04:19

I’ll first map the project and read the existing insight/session code paths so the changes land where the app already expects them. After that I’ll make the smallest stable implementation pass, build/test it, then do the requested second review pass for high-leverage coaching improvements.

### Assistant - 2026-05-07 15:04:40

The repo is an iOS Swift app with a fairly focused split: `Models`, `Services`, `UI`, `Coaching`, `Camera`, `Vision`, and tests. There are already uncommitted insight-related changes in the exact area we need, so I’m going to treat those as existing user work and thread new changes through them carefully rather than flattening them.

### Assistant - 2026-05-07 15:05:25

I found the existing insight engine already has evidence objects with workout IDs, exercise, set and rep metadata, plus a persisted `InsightStore.recordEngagement` hook. That means the evidence sheet can stay local-first and open existing workout detail views without touching the camera pipeline.

### Assistant - 2026-05-07 15:09:43

I’ve got enough context now. I’m going to keep the ranking change inside `InsightRanker`, add a small weekly recap builder/service rather than mixing that logic into views, and use the existing `WorkoutDetailSheetView` as the drill-down target so evidence stays tied to saved workout summaries only.

### Assistant - 2026-05-07 15:16:04

The first implementation slice is in place: rank scoring now receives the profile, weekly recap is a service model, and insight cards have a route to an evidence sheet. I’m adding focused tests next, including a lightweight rendered snapshot test that follows the repo’s current UIKit rendering pattern.

### Assistant - 2026-05-07 15:18:27

I’m at the verification point. I’m going to ask Xcode for an available simulator and then run the unit test target; if the first run exposes compile drift from the already-dirty insight branch, I’ll fix the smallest compile/test issues and rerun.

### Assistant - 2026-05-07 15:19:25

The app and test bundle have built; the simulator run is in the quiet part where XCTest is launching and executing. No compile errors have surfaced so far, which is a good sign after touching ranker signatures and view wiring.

### Assistant - 2026-05-07 15:19:57

The full test run passed. In the review pass, the highest-leverage safe improvement I see is to treat opening the evidence sheet as an explicit engagement signal: it deepens the feedback loop without changing camera data, storage policy, or live-session behavior. I’m wiring that now and will rerun the targeted tests plus a full build/test if needed.

### Assistant - 2026-05-07 15:21:13

The second pass is running cleanly through the simulator again. The only behavior added after the first green run is engagement-aware evidence opens, so this rerun is mainly guarding against accidental view/test regressions.

### Assistant - 2026-05-07 15:22:43

Implemented and verified. The coaching engine now has goal-aware insight ranking, a drill-down evidence sheet, weekly recap cards on Dashboard/Profile, and a small engagement feedback improvement after the build review.

**What Changed**
- Goal-aware ranking in [InsightRanker.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/InsightRanker.swift>):
  - Primary goal match: `+10`
  - Mismatched but goal-related: `+3`
  - Strength/performance signal boosts: `+6`
  - Longevity/recovery boosts: `+8`
  - Opening evidence now records as engagement and adds a small future ranking boost.

- Profile-aware ranking flow through [InsightEngine.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/InsightEngine.swift>) and [InsightStore.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/InsightStore.swift>).

- New evidence drill-down sheet in [InsightEvidenceSheetView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/InsightEvidenceSheetView.swift>):
  - Shows headline, long message, confidence pill.
  - Lists evidence by workout date, exercise, set, rep.
  - Tapping workout-backed evidence opens `WorkoutDetailSheetView`.
  - Helpful / not helpful is wired to `InsightStore.recordEngagement`.

- New weekly recap builder in [WeeklyRecapBuilder.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/WeeklyRecapBuilder.swift>):
  - Builds one ISO-week recap with sessions, avg form, reps, hold time, trophies.
  - Handles normal weeks, empty weeks, and rest weeks.
  - Uses the user’s profile timezone.
  - Surfaces Sunday evening or Monday morning, once per week per surface.

- UI wiring:
  - [HomeDashboardView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/HomeDashboardView.swift>)
  - [ProfileView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/ProfileView.swift>)
  - [WorkoutPreviewView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/WorkoutPreviewView.swift>)
  - [WorkoutSummaryView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/WorkoutSummaryView.swift>)
  - [PlannedWorkoutSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/PlannedWorkoutSessionView.swift>)

**Tests**
Added:
- [InsightRankerTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/InsightRankerTests.swift>)
- [WeeklyRecapBuilderTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/WeeklyRecapBuilderTests.swift>)
- [InsightEvidenceSheetSnapshotTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/InsightEvidenceSheetSnapshotTests.swift>)

Ran twice:

```sh
xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'
```

Result: `TEST SUCCEEDED`.

**Before / After**
- Before: every goal-related insight got a flat `+4`.
  After: a strength user sees strength progression evidence ranked higher than generic goal-adjacent content.

- Before: an insight said “Push-Up form dropped” but did not show why.
  After: opening evidence shows the workout, exercise, set, rep, then opens the saved workout detail.

- Before: Dashboard/Profile had fresh insights, but no weekly story.
  After: Sunday evening or Monday morning, the user gets a once-per-week recap like “2 sessions, 18 reps, 1:30 holds, next week repeat the cleanest movement first.”

- Before: opening evidence did not teach the engine anything.
  After: opening evidence is recorded as engagement, so the system can learn which kinds of insight deserve more attention.

**Manual Testing Plan**
1. Launch app with an existing profile and workout history.
2. Open Dashboard. Confirm normal cards still render and weekly recap appears only if local time is Sunday evening or Monday morning.
3. Tap a Dashboard insight. Confirm evidence sheet opens.
4. Tap an evidence row with a workout date/exercise/set/rep. Confirm `WorkoutDetailSheetView` opens.
5. Tap 👍 and 👎 in the evidence sheet. Relaunch app and confirm no crash or lost insight state.
6. Open Profile. Confirm weekly recap and coach insights both render.
7. Open an insight from Profile and repeat evidence/detail drill-down.
8. Open a planned workout preview. Confirm plan insight still appears and “Evidence” opens the same sheet.
9. Complete a planned workout. Confirm summary still saves, trophy logic still runs, and summary insight evidence opens.
10. Use Camera tab free analysis. Save to history and open saved detail to confirm the free flow still works.
11. For weekly recap: set simulator/device date to Sunday after 6 PM in the profile timezone. Confirm recap appears.
12. Relaunch on the same date. Confirm the same weekly recap does not appear again on that same surface.
13. Change to Monday morning of the next ISO week with no sessions. Confirm rest is acknowledged rather than treated as failure.
14. Switch primary goal between Strength, Performance, Longevity and generate insights from history. Confirm ranking feels goal-aligned.
15. Check app support JSON files: only summaries/insights/engagement metadata are persisted, not raw camera frames, video, face images, or raw pose streams.

**Follow-Ups**
- Add a dedicated full weekly recap detail sheet with evidence rows.
- Route non-workout evidence, like trophy-only evidence, to trophy details instead of showing it as non-tappable.
- Learn from repeated helpful/not-helpful patterns by signal type, not only dedupe key.
- Add goal-specific “next drill” recommendations from the evidence row itself.
