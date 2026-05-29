# C7: Add server clock fields

- Thread ID: 019e076c-7cae-7ac3-8500-2bf7b8fc96a8
- Created: 2026-05-08 17:20:10 (Asia/Kolkata)
- Updated: 2026-05-08 17:31:31 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/08/rollout-2026-05-08T17-20-10-019e076c-7cae-7ac3-8500-2bf7b8fc96a8.jsonl
- Git branch at thread start: main
- Git SHA at thread start: b7ee5b09ac035751d98b4831dd346bc5b3f38bff
- Exported visible messages: 17
- Extracted input images: 0

## Conversation

### User - 2026-05-08 17:20:28

You are working in the Spotter iOS Swift repository.

Before changing code:
1. Deeply inspect the current repository.
2. Read the current README and DEBUG_LOG.md.
3. Read relevant files before editing.
4. Treat this prompt as implementation guidance, not a blind spec. If the current code reveals a safer approach, choose it and explain why.
5. Do not rewrite MediaPipe, CameraManager, PoseEstimator, UniversalRepCounter, FormFeedbackEngine, HandGestureDetector, ExertionAnalyzer, or the live camera pipeline.
6. Preserve both live flows:
   - Camera tab free analysis
   - Planned workout sessions
7. Preserve deterministic local plan generation, trophies, stats, trends, recaps, and AI insights.
8. Keep backend work local-first until the Firebase phase explicitly begins.
9. Do not store or upload raw video, camera frames, face images, raw pose streams, raw biometric face data, or raw pose timelines.
10. Do not print or expose secret values.
11. Maintain backwards-compatible Codable decoding for existing local JSON.
12. Keep the app compiling after this phase.
13. Run available tests/build commands and summarize results.
14. Summarize changed files, key decisions, migration behavior, and known follow-ups.
15. Mention the change the code brings to the application - the before and after with real life practical examples if possible. 
Goal:
Prepare trophies, streaks, workouts, and future PRs for server-authoritative time.

Create:
- AppClock.swift

protocol AppClock {
    func now() -> Date
    func estimatedServerNow() -> Date
}

struct LocalClock: AppClock {
    func now() -> Date { Date() }
    func estimatedServerNow() -> Date { Date() }
}

Add fields:
- WorkoutSessionSummary.serverEndedAt: Date?
- TrophyUnlockEvent.serverEarnedAt: Date?
- CalibrationRecord.serverCompletedAt: Date?
- AIInsight.serverCreatedAt: Date? if useful

Rules:
- Local mode sets server fields to nil or local estimate consistently.
- Streak logic should prefer serverEndedAt when available, then endedAt.
- Firebase repository later overwrites server fields with Firestore server timestamp after write acknowledgement.
- Do not claim true server time in local mode.

Update:
- StatsEngine streak calculations
- TrendEngine date windows
- TrophyEngine unlock event creation
- WorkoutHistoryStore summary creation path if needed

Tests:
- old summaries without serverEndedAt decode
- StatsEngine prefers serverEndedAt
- streak tests remain stable with LocalClock
- TrophyUnlockEvent can carry serverEarnedAt

Acceptance:
- Time-sensitive logic can later shift to server timestamps without model redesign.

### Assistant - 2026-05-08 17:20:31

I’ll inspect the repo first and read the README plus debug log before touching anything. I’m going to trace where summaries, streaks, trends, trophies, calibration records, and insights are defined so the clock change lands in the existing shape rather than fighting it.

### Assistant - 2026-05-08 17:20:42

I’ve got the file map. Next I’m reading the repository notes and the engines/models that own dates; the important bit here is to add server-time readiness without disturbing the live pose/camera path or local-first behavior.

### Assistant - 2026-05-08 17:20:59

The repo notes confirm the target constraints: local deterministic coaching, two live flows sharing one camera stack, and no raw camera/pose persistence. I’m narrowing the edit to model timestamps plus date consumers, with tests around decoding and server-date preference.

### Assistant - 2026-05-08 17:23:05

I’ve got enough of the shape now. I’m going to make the server timestamp fields optional and nil in local mode, add a tiny clock abstraction, then route date-sensitive engines through `serverEndedAt ?? endedAt`; that gives Firebase a landing place later without pretending local time is server time today.

### Assistant - 2026-05-08 17:23:08

First edit pass is model-only: new clock file, optional server fields, and copy/Codable plumbing. I’m keeping local constructors on nil server timestamps so the app is honest until a backend write acknowledgement supplies a real server value.

### Assistant - 2026-05-08 17:24:05

Now I’m moving the date consumers. This is deliberately a fallback, not a rewrite: if a summary has `serverEndedAt`, streaks/windows use it; older and local-only summaries keep behaving exactly as before via `endedAt`.

### Assistant - 2026-05-08 17:26:00

Test edits next. I’m adding assertions for legacy JSON, a targeted server-date streak case, and a trophy event roundtrip so the optional fields are proven to be additive rather than migration-breaking.

### Assistant - 2026-05-08 17:27:22

The main wiring is in place. I’m doing a quick self-review now for accidental `endedAt` leftovers in the date-window paths and for Codable/copy omissions, then I’ll run focused tests before the broader build/test command.

### Assistant - 2026-05-08 17:27:34

The diff looks scoped: no camera, pose, rep counter, form engine, or live-session pipeline changes. I’m starting with the focused model/engine tests that cover these timestamp paths, then I’ll run the broader command if the simulator cooperates.

### Assistant - 2026-05-08 17:27:50

The focused run reached compile and found one model plumbing miss in `CalibrationRecord`: I copied the new field through a static factory without giving that factory a parameter. I’ll patch that now and rerun.

### Assistant - 2026-05-08 17:29:02

The focused suite is past compilation now and into simulator test execution. I’m waiting it out; if it passes, I’ll use the same workspace/simulator path for the broader verification.

### Assistant - 2026-05-08 17:29:30

Focused verification passed. I’m running the full workspace test command now; after that I’ll run a plain simulator build so we have both test and compile evidence for this phase.

### Assistant - 2026-05-08 17:30:13

The full test run has built the app and is in the test phase. No new compile issues have surfaced; I’m letting the simulator finish the suite.

### Assistant - 2026-05-08 17:30:31

Full tests passed. One more plain `xcodebuild build` now, mostly to prove the app target compiles outside the test harness too.

### Assistant - 2026-05-08 17:30:48

Both verification passes succeeded: full tests and a plain app build. I’m doing the final review pass now: status, changed files, and the exact migration behavior to report back cleanly.

### Assistant - 2026-05-08 17:31:31

Implemented the server-time readiness pass. I kept it local-first: local mode leaves new server timestamp fields as `nil`, so the app does not pretend it has true server time before Firebase exists.

Changed files:
- Added [AppClock.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/AppClock.swift:1)
- Updated timestamp models in [WorkoutSessionSummary.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/WorkoutSessionSummary.swift:218), [TrophyModels.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/TrophyModels.swift:287), [CalibrationRecord.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/CalibrationRecord.swift:34), and [AIInsightModels.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/AIInsightModels.swift:148)
- Updated server-time fallback logic in [StatsEngine.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/StatsEngine.swift:57), [TrendEngine.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/TrendEngine.swift:78), [TrendWindowPolicy.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/TrendWindowPolicy.swift:18), and [WorkoutHistoryStore.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/WorkoutHistoryStore.swift:215)
- Added/updated tests in `StatsEngineTests`, `TrendEngineTests`, `TrophyEngineTests`, `WorkoutHistoryStoreTests`, and `SyncMetadataTests`

Key behavior:
- `WorkoutSessionSummary.serverEndedAt`, `TrophyUnlockEvent.serverEarnedAt`, `CalibrationRecord.serverCompletedAt`, and `AIInsight.serverCreatedAt` are optional and backward-compatible.
- Streaks, trend windows, history sorting/stats, and trophy workout-day logic now prefer `serverEndedAt`, falling back to `endedAt`.
- Trophy unlock events are created with `serverEarnedAt: nil` in local mode.
- Old JSON without the new fields decodes cleanly with nil server timestamps.

Practical before/after:
Before, if a user’s phone clock was wrong or offline data later synced, streaks and trends were locked to the device’s `endedAt`. After this, the same workout can later receive `serverEndedAt` from Firestore; for example, a workout that the phone thought ended yesterday can count toward today’s streak once the backend confirms the real server completion time. Offline/local workouts still behave exactly as they do today.

Verification passed:
- Focused timestamp/model tests passed.
- Full `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `git diff --check` passed.

Known follow-ups: when Firebase begins, repositories should overwrite these server fields after Firestore server timestamp acknowledgement. If time-of-day trophies need true server-authoritative start time later, add a separate `serverStartedAt` rather than overloading `endedAt`.
