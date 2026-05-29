# P14_H: Add trend window policy

- Thread ID: 019e01b3-3265-7a22-9f98-e0cd33733c12
- Created: 2026-05-07 14:39:41 (Asia/Kolkata)
- Updated: 2026-05-07 15:19:35 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T14-39-41-019e01b3-3265-7a22-9f98-e0cd33733c12.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a8305d617f2abab60b3b8df7bd7426bfdc252375
- Exported visible messages: 12
- Extracted input images: 0

## Conversation

### User - 2026-05-07 14:39:44

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

TASK
TrendEngine.mostRepeatedCue, cameraFrictionCount, ExerciseTrendSummary.cueCounts, and
several SignalExtractor counts use the entire history with no time decay. Once a user
fixes a problem, the signal keeps re-firing because old events dominate the count.

GOAL
Introduce a `TrendWindowPolicy` that, by default, restricts cue counts and friction
counts to the most recent N sessions OR most recent K days, whichever is shorter:
- mostRepeatedCue: last 7 sessions.
- cameraFrictionCount: last 14 days.
- ExerciseTrendSummary.cueCounts: last 5 sessions of that exercise type.
- repeatedCue evidenceRefs: only count cue events whose timestamp is within the window.

DESIGN
- Add `TrendWindowPolicy` struct with named static defaults
  (.recentCues, .recentSetup, .recentExerciseFriction). Make them tunable via
  init parameters so tests can pin the window.
- TrendEngine, SignalExtractor: thread the policy through; existing call sites use
  defaults so behavior changes uniformly.

CONSTRAINTS
- Must preserve the existing interfaces externally (default windows applied if not
  supplied).
- Persisted snapshot need not change.

ACCEPTANCE
- New tests: a user with 3 cue-X events in summaries 12 sessions ago and 1 cue-Y event
  this week → mostRepeatedCue == "Y" with default window.
- cameraFrictionCount > 0 only if events occurred within last 14 days.
- All existing TrendEngineTests pass (or are updated to pass appropriate windows where
  intentional).

### Assistant - 2026-05-07 14:39:51

I’ll start by mapping the project and reading the trend-related code paths before touching anything. I’ll keep the live camera stack out of scope unless the dependency graph unexpectedly forces us there.

### Assistant - 2026-05-07 14:40:03

The repo is already carrying a set of modified and untracked files, including the trend and insight areas we’ll touch. I’ll treat those as existing work, read around them carefully, and keep the patch narrowly layered on top.

### Assistant - 2026-05-07 14:40:21

The trend engine is already nicely separated from SwiftUI, which is good news. The stale-signal problem sits in count aggregation and evidence selection, so the smallest good fix is a shared window policy used at those aggregation boundaries.

### Assistant - 2026-05-07 14:43:29

I’m going to add the policy as a small model-level value type, then thread it through `TrendEngine` by defaulted initializer parameters. The key engineering choice is to window at the aggregation/evidence boundaries, not inside the camera/pose/live pipeline, so the raw session data remains local and unchanged while stale coaching signals age out.

### Assistant - 2026-05-07 14:46:08

The extractor is now using the same policies for repeated-cue evidence, camera-friction evidence, and related cue-cluster evidence. I also windowed exercise-level friction counters so an old rough patch stops keeping an exercise marked as “struggling” after the recent sessions are clean.

### Assistant - 2026-05-07 14:47:06

The regression tests now cover the exact failure mode: old cue X can be louder in lifetime history but newer cue Y wins inside the default window; camera setup cues expire after 14 days; exercise cue/friction counts only use recent exercise exposures; repeated-cue evidence no longer pulls old events back into the signal. Next I’m going to let Xcode tell us what I missed.

### Assistant - 2026-05-07 14:48:09

The targeted `TrendEngineTests` build has compiled and is in the simulator test phase now. No compile error has surfaced so far, so we’re past the riskiest part of adding the new source file and initializer threading.

### Assistant - 2026-05-07 14:48:18

Targeted trend tests passed. I’m going to run the full app test suite now because the trend snapshot feeds several insight paths, and I want to catch any unintended change in downstream coaching signals.

### Assistant - 2026-05-07 14:49:05

Full-suite test is still running through the simulator with no failure output yet. Since the targeted suite already passed, this is mostly checking collateral impact in insight, dashboard, and plan tests.

### Assistant - 2026-05-07 14:49:19

Full suite passed too. I’m doing one quick local review pass over the diff now, looking specifically for policy leaks, stale evidence edge cases, and accidental UI/live-pipeline touch points.

### Assistant - 2026-05-07 14:50:03

Implemented the trend-window fix and kept it out of the live camera/MediaPipe path.

**Changed**
- Added [TrendWindowPolicy.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/TrendWindowPolicy.swift:3>) with tunable `maxSessions` / `maxDays` and defaults:
  `recentCues = 7 sessions`, `recentSetup = 14 days`, `recentExerciseFriction = 5 exercise sessions`.
- Updated [TrendEngine.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/TrendEngine.swift:3>) so `mostRepeatedCue`, camera friction count, exercise cue counts, and exercise friction counters use those windows.
- Updated [SignalExtractor.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/SignalExtractor.swift:496>) so repeated-cue, camera-friction, and cue-cluster evidence only come from the active window.
- Added regression coverage in [TrendEngineTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/TrendEngineTests.swift:198>).

**Before / After**
Before: if someone got “knee caves in” three times 12 sessions ago, then fixed it, that old cue could still beat a newer current cue.  
After: the coach now looks at the recent window, so a newer cue like “keep your chest tall” wins if that is what is happening now.

Before: a camera setup issue from 15 days ago could still count as setup friction.  
After: camera friction only counts if the setup cue happened in the last 14 days.

**Tests**
- Passed: `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:VirtualTrainerTests/TrendEngineTests`
- Passed: `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`

**Manual Test Plan**
1. Do several clean recent workouts after older bad-form sessions. Confirm dashboard/profile insight stops repeating the old cue.
2. Save a workout with a camera cue, then simulate/seed it older than 14 days. Confirm camera-friction insight does not appear.
3. Run both flows:
   - Camera tab free analysis: save summary, confirm trends/insights still generate.
   - Planned workout session: complete a plan, confirm recap and trends still generate.
4. Repeat one cue in two recent sessions. Confirm repeated-cue insight shows only recent evidence refs.

**Post-Build Review**
The highest-leverage extra I implemented was extending the same windowing to cue-cluster evidence and exercise-level friction counters, because those can also keep stale coaching alive. Good next steps: add “resolved cue” signals, severity-weighted decay, and per-user adaptive windows once there is enough history.
