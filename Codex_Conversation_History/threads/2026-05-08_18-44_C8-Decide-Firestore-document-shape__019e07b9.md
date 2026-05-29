# C8: Decide Firestore document shape

- Thread ID: 019e07b9-cc5f-78e1-8e16-1741402c7aa1
- Created: 2026-05-08 18:44:37 (Asia/Kolkata)
- Updated: 2026-05-08 18:57:04 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/08/rollout-2026-05-08T18-44-37-019e07b9-cc5f-78e1-8e16-1741402c7aa1.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 8fdea66ab18123c49bec609b8db5840479b65e3d
- Exported visible messages: 19
- Extracted input images: 0

## Conversation

### User - 2026-05-08 18:44:40

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
Decide Firestore document shape before Firebase code.

Tasks:
1. Add WorkoutSummarySizeAuditTests.swift.

Synthetic worst case:
- 8 exercises
- 4 sets per exercise
- 25 rep-quality events per set
- 5–10 cue events per set
- all optional evidence filled

Then decide embed vs subcollection. Firestore’s 1 MiB document size limit makes this audit mandatory, not optional

Measure:
- JSON encoded byte size using the same date encoding style.
- Add rough Firestore overhead allowance.
- Assert below a conservative threshold such as 256 KB if planning to embed.

2. Create:
Documentation/FirestoreShape.md

Document:
- Firestore has strict document size limits.
- Chosen shape:
  Option A: embed set summaries inside workout document.
  Option B: workout doc + sets subcollection.
  Option C: workout doc + sets subcollection + rep events subcollection.
- Current measured synthetic size.
- Decision and rationale.
- Migration plan if shape changes later.

Recommended likely shape:
- Store a compact `WorkoutSessionSummary` doc at users/{uid}/workouts/{workoutId}
- Store set summaries at users/{uid}/workouts/{workoutId}/sets/{setId}
- Store detailed repQualityEvents either embedded per set if small or compressed/limited if needed.
- Keep raw camera/pose data out entirely.

Tests:
- size audit passes or fails loudly
- FirestoreShape.md exists
- no code uploads data yet

Acceptance:
- Firebase repository has a documented target data shape before implementation.

### Assistant - 2026-05-08 18:44:43

I’ll start by mapping the repo and reading the existing docs/logs, then I’ll inspect the model/test structure before touching anything. I’ll keep this phase scoped to documentation and size-audit tests, with no Firebase upload code.

### Assistant - 2026-05-08 18:45:03

The repo is an iOS Swift project with an existing local-first model layer and tests. I’m reading the README and debug log now, then I’ll trace the existing workout summary/evidence Codable models so the audit uses the app’s real encoding shape.

### Assistant - 2026-05-08 18:45:20

The docs reinforce the boundary pretty strongly: summaries and derived evidence are okay, raw camera/video/pose/face data are not, and backend work is supposed to stay behind a repository/Firebase phase. I’m now reading the summary schema, evidence models, store encoding, and existing test patterns so the new test lands in the right target without disturbing live flows.

### Assistant - 2026-05-08 18:46:29

The current local encoder for workout history is `prettyPrinted`, `sortedKeys`, and `iso8601`, so the audit should use that exact style instead of a compact JSON shortcut. I also found the project uses file-system-synchronized Xcode groups, so adding a test file under `VirtualTrainerTests/` should be picked up without hand-editing the project file.

### Assistant - 2026-05-08 18:48:35

I’ve got the model boundaries now. I’m going to add a focused audit test that builds the worst-case local summary from the real Codable models, estimates Firestore overhead, and locks the chosen shape to compact workout docs plus set subcollection docs.

### Assistant - 2026-05-08 18:50:01

The test file is in place. I’m going to run just the size-audit method first so I can capture the actual byte counts before writing `Documentation/FirestoreShape.md`; the doc-existence test will wait until the doc has those exact values.

### Assistant - 2026-05-08 18:50:20

The first focused run hit a Swift type-checker timeout in the new synthetic cue fixture, not an app/runtime failure. I’m simplifying that fixture into explicit locals and loops so the compiler has less inference work to chew through.

### Assistant - 2026-05-08 18:51:28

The focused build is past compilation now and waiting on the simulator test run. Once it returns, I’ll use the printed audit numbers to write the Firestore shape doc and then run the full new audit test class.

### Assistant - 2026-05-08 18:52:02

The size test passed, but Xcode suppressed the `print` payload in the normal console output. I’m going to briefly surface the computed values through a temporary failing assertion, capture them, then remove that assertion before continuing.

### Assistant - 2026-05-08 18:52:54

The temporary capture run is also waiting on the simulator. It should fail intentionally with the audit struct in the failure text, then I’ll immediately remove that failure and put the values into the documentation.

### Assistant - 2026-05-08 18:53:32

The measured worst-case full embedded summary is about 661 KB as JSON and about 893 KB with the audit’s Firestore allowance. That is under Firestore’s hard 1 MiB limit, but far above the 256 KB comfort threshold, so I’m documenting the safer subcollection shape now.

### Assistant - 2026-05-08 18:54:12

The Firestore shape doc is now written with the exact audit values and the decision: compact workout doc plus set subcollection, with rep/cue events embedded per set for now. I’m running the full new audit test class next, including the doc and no-Firebase-upload guards.

### Assistant - 2026-05-08 18:54:55

The audit class has built cleanly and is in the simulator run again. The new tests are intentionally small: one size audit, one doc-content guard, one guard that Firebase upload calls have not been introduced in app source.

### Assistant - 2026-05-08 18:55:13

The new audit test class passed. I’m going to run the full workspace test suite now, then a simulator build, because this touched the test target and docs but should not affect live camera or workout flows.

### Assistant - 2026-05-08 18:55:58

The full suite is now in the quiet simulator-running phase. Nothing has failed so far; I’m just waiting for XCTest to flush the results.

### Assistant - 2026-05-08 18:56:16

Full `xcodebuild test` succeeded on the iPhone 17 simulator. I’m doing a plain simulator build now as the last verification pass.

### Assistant - 2026-05-08 18:56:30

The full test suite and the app build both succeeded. I’m doing a quick final diff/readback now so I can give you the exact changed files, line references, and the migration/shape decision without hand-waving.

### Assistant - 2026-05-08 18:57:04

Implemented the Firestore shape decision phase.

Added [WorkoutSummarySizeAuditTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift:17), which builds the synthetic worst case from the real Codable workout/evidence models:

- 8 exercises
- 4 sets each
- 25 rep-quality events per set
- 10 cue events per set
- optional evidence/sync/tombstone fields filled
- same `prettyPrinted`, `sortedKeys`, `iso8601` encoding style as `WorkoutHistoryStore`
- Firestore allowance: `JSON * 1.35 + 1024`

Measured result:

```text
fullEmbeddedJSONBytes: 660999
fullEmbeddedEstimatedFirestoreBytes: 893373
compactWorkoutDocumentEstimatedFirestoreBytes: 3715
maxSetDocumentEstimatedFirestoreBytes: 28101
```

Added [Documentation/FirestoreShape.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/FirestoreShape.md:1). Decision is [Option B](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/FirestoreShape.md:122): compact workout doc at `users/{uid}/workouts/{workoutId}`, set summaries at `users/{uid}/workouts/{workoutId}/sets/{setId}`, with rep/cue events embedded per set for now.

Why: full embedding is under Firestore’s 1 MiB hard limit, but about 893 KB with allowance, which is too close for a shape that will likely grow. Per-set docs are only about 28 KB worst-case, so Option B keeps list/profile queries tiny and loads detail evidence only when the user opens a workout.

No production app code or live pipeline code was changed. No Firebase upload code was added; the new test also guards that app source still has no Firebase import or Firestore write calls.

Verification passed:

- `xcodebuild test ... -only-testing:VirtualTrainerTests/WorkoutSummarySizeAuditTests`
- Full `xcodebuild test ...` passed: 306 tests
- `xcodebuild build ...` passed

Practical before/after: before, a heavy planned session could have become one giant workout document containing every set, cue, and rep event. After this, the workout list can fetch a compact “Friday strength, 800 reps, avg form score” record, while the detailed rep sparkline/cue evidence loads from set docs only when the user opens that workout.
