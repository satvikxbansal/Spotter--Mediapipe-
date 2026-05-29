# P10.5D: Add calibration foundation

- Thread ID: 019dfc21-2bef-7550-9393-43d5e32bc0e6
- Created: 2026-05-06 12:42:05 (Asia/Kolkata)
- Updated: 2026-05-06 13:03:58 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/06/rollout-2026-05-06T12-42-05-019dfc21-2bef-7550-9393-43d5e32bc0e6.jsonl
- Git branch at thread start: main
- Git SHA at thread start: b4e1df4ce5e2115f70d6ac512df4357b50f16cb8
- Exported visible messages: 16
- Extracted input images: 0

## Conversation

### User - 2026-05-06 12:42:17

You are working in the Spotter iOS Swift repository.

Before changing code:
1. Deeply inspect the current repo structure and debug log.
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
14. Audit all the changes in extreme detail, fix discrepancies and Share a manual end to end testing plan in the end.


Bridge 10.5D — Calibration foundation
Why this is still needed
The design has calibration as an early user moment and the trophy collection includes Calibrated. This should be first-class before trophies.
Prompt

Use the common Spotter Codex preflight block.

Bridge 10.5D goal:
Add a lightweight calibration foundation that reuses the existing live camera analysis path and prepares for the Calibrated trophy.

Important current files to inspect:
- VirtualTrainer/UI/OnboardingViews.swift
- VirtualTrainer/UI/CameraTabView.swift
- VirtualTrainer/UI/TrainerSessionView.swift
- VirtualTrainer/Models/LiveSessionContext.swift
- VirtualTrainer/Models/WorkoutSessionContext.swift
- VirtualTrainer/Models/WorkoutSessionSummary.swift
- VirtualTrainer/Models/WorkoutHistoryStore.swift
- VirtualTrainer/Coaching/WorkoutReadyCoordinator.swift
- VirtualTrainer/VirtualTrainerApp.swift

Tasks:

1. Add calibration model.

Create:
- CalibrationStatus
  - notStarted
  - completed
  - skipped
  - failed

Create:
- CalibrationRecord
  - id
  - status
  - exerciseType
  - targetReps
  - completedReps
  - startedAt
  - completedAt
  - visibilityPassed
  - averageFormScore
  - notes optional

2. Add CalibrationStore.

- local Codable persistence
- load status
- save completed
- save skipped
- reset for debug

3. Add calibration session flow.

Default calibration:
- exercise: squat / air squat, matching current ExerciseType naming
- target: 3 reps
- goal: verify camera placement and basic body tracking
- use existing readiness and TrainerSessionView where possible

Implementation options:
- Add SessionMode.calibration if clean
or
- Use plannedWorkout/freeAnalysis with a calibration flag if less disruptive

Prefer the smallest safe change.

4. Add CalibrationIntroView / CalibrationSessionView.

After onboarding completion:
- show calibration intro
- explain: “Track 3 air squats to verify your space.”
- allow Start Calibration
- allow Skip for now
- skipped should be persisted

5. On successful completion:
- save CalibrationRecord.completed
- optionally save a lightweight WorkoutSessionSummary if it does not pollute workout history
- emit/store enough information for TrophyEngine to unlock Calibrated later

6. Tests.

Add:
- CalibrationStore persists completed status
- skipped status persists
- successful 3-rep calibration creates completed record
- calibration does not break free-analysis mode
- calibration does not require backend
- missing camera permission can fail gracefully

Acceptance criteria:
- Calibration is a real app state.
- Calibrated trophy can be unlocked later.
- Camera pipeline remains shared.

### Assistant - 2026-05-06 12:42:28

I’ll start with the repo map and the existing diagnostic artifacts before touching code, then I’ll read the calibration-adjacent session/onboarding files in context. After that I’ll make the smallest change that keeps both live camera paths intact.

### Assistant - 2026-05-06 12:43:02

The repo has a normal iOS/Xcode structure, plus `DEBUG_LOG.md` at the root and a set of design exports. Git is clean on `main` apart from being one commit ahead, so I have a good baseline for a focused patch.

### Assistant - 2026-05-06 12:43:32

The debug log has recent camera-pipeline lifecycle fixes, so I’m going to keep calibration as a caller of the existing readiness/session handoff instead of inserting new camera ownership. That lines up with the “do not rewrite pipeline” guardrail and avoids reopening those bugs.

### Assistant - 2026-05-06 12:45:47

I’ve got enough shape now to implement. The smallest safe design is: a local `CalibrationStore` plus `SessionMode.calibration`, then a calibration wrapper that drives the existing readiness screen and `TrainerSessionView`; no workout-history write, so calibration becomes trophy evidence without inflating workout stats.

### Assistant - 2026-05-06 12:46:45

I’m going to add the calibration model/store first, then wire it through app gating and the existing readiness/session views. The only camera-layer change I’m making is exposing permission status so calibration can fail gracefully instead of hanging on a black/idle camera state.

### Assistant - 2026-05-06 12:52:22

The core patch is in place now: calibration has its own persisted record and it rides the same readiness-to-live-session handoff as free analysis. I’m checking the diff and then I’ll run the available Xcode tests/build so the compiler gets the deciding vote.

### Assistant - 2026-05-06 12:53:05

Xcode sees the `VirtualTrainer` scheme and an iPhone 17 simulator, so I’ll start with the new calibration tests, then run the full suite. If the new code shakes out a compile issue, I’ll tighten it before the full pass.

### Assistant - 2026-05-06 12:54:05

The focused calibration suite passed, including persistence, skipped/failed states, no history pollution, and the free-analysis context invariant. I’m moving to the full workspace test run now, since this touches shared session plumbing.

### Assistant - 2026-05-06 13:00:07

The full test run is in the simulator phase now. Build completed far enough to install and launch tests, so any remaining signal should be behavioral test failures rather than basic compile/link trouble.

### Assistant - 2026-05-06 13:00:15

Full tests passed cleanly. I’m doing one explicit simulator build as a final compile sanity check, then I’ll audit the changed files for integration mismatches and any unintended history/camera side effects.

### Assistant - 2026-05-06 13:00:31

The explicit simulator build passed too. I’m doing the slow, boring audit pass now: file status, changed-line review, and checking that calibration did not get accidentally folded into workout history or the planned/free session paths.

### Assistant - 2026-05-06 13:01:24

One audit tweak: I made the live calibration HUD say “3 air squats • Camera check” so the session itself reflects the calibration target, not just the intro. I’m re-running the quick simulator build after that text/UI change.

### Assistant - 2026-05-06 13:01:39

The post-audit build is green. Since the final tweak was tiny but still touched a compiled SwiftUI file, I’m going to rerun the full test suite once more so the final report is clean and current.

### Assistant - 2026-05-06 13:02:18

The final test rerun has installed the app and is executing tests. This is the last verification loop unless it finds something real.

### Assistant - 2026-05-06 13:03:44

Implemented Bridge 10.5D calibration foundation.

**What changed**
- Added calibration domain + persistence:
  - [CalibrationRecord.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/CalibrationRecord.swift)
  - [CalibrationStore.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/CalibrationStore.swift)
- Added `SessionMode.calibration` and default 3-rep squat context in [LiveSessionContext.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/LiveSessionContext.swift).
- Added post-onboarding calibration gate and intro/session UI in [VirtualTrainerApp.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/VirtualTrainerApp.swift) and [CalibrationViews.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/CalibrationViews.swift).
- Reused the existing readiness and live session path through [CameraTabView.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/CameraTabView.swift) and [TrainerSessionView.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/TrainerSessionView.swift).
- Added focused coverage in [CalibrationStoreTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/CalibrationStoreTests.swift).

**Key Decisions**
- I used `SessionMode.calibration` instead of smuggling calibration through free analysis. It is cleaner for future trophy unlocks and keeps the live camera pipeline shared.
- Calibration does not save a `WorkoutSessionSummary`, so it does not pollute workout history or stats.
- I only added camera permission status to `CameraManager`; frame capture, MediaPipe, rep counting, readiness, and planned/free live flows remain intact.
- Persisted data is lightweight: status, exercise, target/completed reps, timestamps, visibility pass, average form score, optional notes. No raw frames, video, face images, raw pose streams, or biometric face data.

**Verification**
- `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:VirtualTrainerTests/CalibrationStoreTests` succeeded.
- Full `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'` succeeded.
- `xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'` succeeded.
- `git diff --check` is clean.

**Manual E2E Plan**
1. Fresh app state: complete onboarding, confirm Calibration intro appears before main tabs.
2. Tap Start Calibration, grant camera permission, pass readiness, start session, perform 3 air squats, confirm app enters main tabs and Profile shows Calibration: Completed.
3. Reset calibration from Profile, return to intro, tap Skip for now, relaunch app, confirm main tabs open and status is Skipped.
4. Reset calibration, deny camera permission, confirm graceful failed state with retry/skip path.
5. Camera tab free analysis: select any exercise, pass readiness, start, tap Done, confirm summary appears and optional history save still works.
6. Planned workout: start a planned session, complete a set, verify rest/next-set/summary flow still works.

**Follow-Ups**
- Wire `CalibrationStore.hasCompletedCalibration` or `CalibrationRecord.isSuccessfulCalibration` into `TrophyEngine` when trophy work begins.
- Later UI pass can polish calibration visuals; this intentionally kept the UI simple and functional.
