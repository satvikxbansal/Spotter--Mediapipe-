# P14_F: Add bootstrap signal branches

- Thread ID: 019e0138-f0c6-78b1-ba4b-36774d5d1e37
- Created: 2026-05-07 12:26:09 (Asia/Kolkata)
- Updated: 2026-05-07 12:46:42 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T12-26-09-019e0138-f0c6-78b1-ba4b-36774d5d1e37.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a8305d617f2abab60b3b8df7bd7426bfdc252375
- Exported visible messages: 8
- Extracted input images: 0

## Conversation

### User - 2026-05-07 12:26:11

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
Today, formImprovement / formDropOff / volumeIncrease / volumeDrop / qualityPR /
progressionReadiness / targetFit signals all require ≥6 sessions in history. New users
(the cohort with the fragilest retention) get silence on the most useful signals.

GOAL
Add bootstrap branches in SignalExtractor that produce informative signals for sessions
1–5 using single-session evidence:
- After session 1: `firstSession` consistency signal + `setupQuality` signal driven by
  cameraFrictionCueCount and bodyVisibility events. Also a `repCleanlinessIntro` signal:
  "75% of your reps were good-form on your first set" (uses qualitySummary.goodFormReps).
- After session 2 with at least one repeated exercise: `repeatExerciseProgress` signal
  comparing the two sessions' set-1 form averages on that exercise.
- After session 3: enable the existing trend signals using `count = 1` window
  (latest-vs-previous) instead of `count = 3` when totalWorkouts < 6.
- After any session: `personalBaseline` signal showing the user's running median form
  score for their dominant exercise so far.

DESIGN
- Add a new `SignalGenerationContext` struct passed to SignalExtractor that includes
  `historySessionCount`. Branch into a "warmup mode" inside extractSignals() when
  `historySessionCount < 6`.
- Bootstrap signals must still produce `evidenceRefs` and a confidence — keep them at
  `.medium` (never `.high`) to communicate "we're early".
- Cap bootstrap signals at 2 per surface to avoid drowning the real signals once
  history grows.

CONSTRAINTS
- Do not change any thresholds inside form rules or cue severity.
- All new signals must have unique TrainingSignalType raw values; extend the enum
  conservatively (`firstSession`, `setupQuality`, `repeatExerciseProgress`,
  `personalBaseline`).
- Update InsightCandidateBuilder.mappedInsight to map every new signal to a sensible
  InsightAction (mostly `.continuePlan` and `.focusCue`).

ACCEPTANCE
- New tests cover: history of 1, 2, 3, 5, 6 sessions and assert the right signals
  surface.
- Manually run the engine with 1 session and confirm the dashboard shows a relevant
  bootstrap insight (no longer empty).

### Assistant - 2026-05-07 12:26:19

I’ll start by mapping the repo and reading the signal/insight code plus existing tests, then I’ll make the smallest stable change that fits the current architecture. I’ll keep an eye on the live camera boundaries you called out and avoid touching that pipeline unless the code leaves no other route.

### Assistant - 2026-05-07 12:26:38

The worktree is already fairly active: the core insight/signal files and tests have uncommitted edits, plus a few new service/test files. I’m going to read those changed areas as they stand and treat them as user-owned context, so my patch layers onto the current state instead of flattening it.

### Assistant - 2026-05-07 12:27:45

I’ve got the main shape now: `SignalExtractor` already has a clean observation layer and derived signal helpers, so the best fit is to add bootstrap logic there using those observations instead of touching MediaPipe/camera/live-session code. I’m checking the existing diffs next so the new context struct and tests land around the current uncommitted work cleanly.

### Assistant - 2026-05-07 12:38:16

I’m going to make the signal-context change first, then wire the new signal types through candidate mapping and the one UI switch that renders signal icons. The notable engineering choice is to keep the actual camera/pose pipeline untouched and derive setup quality only from already-saved cue/event summaries, so we stay local-first and avoid storing any raw frame or pose stream.

### User - 2026-05-07 12:41:00

resume?

### Assistant - 2026-05-07 12:41:24

Resuming. I’ve added the model/context entry point and the first half of the extractor logic; next I’m filling the helper functions, then I’ll wire the new signal types through insight mapping and run the build/tests.

### Assistant - 2026-05-07 12:42:25

Small hiccup: the patch tool accepted the absolute-path edit but the file on disk did not change, so I’m reapplying with repo-relative paths. Nothing architectural changes here, just making sure the edits actually land in this workspace.
