# C0: Create backend readiness map

- Thread ID: 019e028b-696c-72b2-8566-e65c5621f391
- Created: 2026-05-07 18:35:51 (Asia/Kolkata)
- Updated: 2026-05-07 18:44:09 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T18-35-51-019e028b-696c-72b2-8566-e65c5621f391.jsonl
- Git branch at thread start: main
- Git SHA at thread start: c32fc0cda34efde33218499124ae5c805e5b555c
- Exported visible messages: 11
- Extracted input images: 0

## Conversation

### User - 2026-05-07 18:36:15

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


Goal:
Create an exact backend-readiness map of the current Spotter codebase before changing sync models.

Tasks:
1. Inspect:
   - UserProfile.swift
   - WorkoutSessionSummary.swift
   - WorkoutHistoryStore.swift
   - TrophyModels.swift
   - TrophyStore / TrophyEngine if stored in TrophyModels.swift
   - AIInsightModels.swift
   - InsightStore.swift
   - CalibrationRecord.swift
   - CalibrationStore.swift
   - ThemeStore.swift
   - OnboardingStore.swift
   - ShareCardRenderer.swift
   - ProfileView.swift
   - WorkoutDetailSheetView.swift
   - TrophiesView.swift
   - README.md
   - DEBUG_LOG.md
   - all current tests

2. Produce a markdown file:
   Documentation/BackendReadinessMap.md

Include:
- all locally persisted files and their file paths
- all syncable models
- current schema versions
- which models need accountId
- which models need deletedAt
- which models need SyncMetadata
- which writes need operationId
- current store methods and missing methods
- privacy boundary summary
- proposed Firestore collections
- open decisions before Firebase

3. Do not add Firebase, repositories, or model fields in this prompt.
4. Add tests only if needed for current documentation helpers.

Acceptance criteria:
- Documentation/BackendReadinessMap.md exists.
- It reflects the current repo accurately.
- No product behavior changes.
- Existing tests still pass.

### Assistant - 2026-05-07 18:36:23

I’ll start by mapping the repo and reading the requested docs and model/store files before touching anything. This phase sounds documentation-only, so I’ll keep code behavior still and only add the readiness map unless the repo reveals a tiny helper/test need.

### Assistant - 2026-05-07 18:36:38

The tree is modest and there’s one pre-existing untracked file, `Spotter_Pre_Backend_Readiness.md`; I’ll leave that alone. Next I’m reading the requested model/store/view files and the two docs in parallel so the map reflects the code that is actually here.

### Assistant - 2026-05-07 18:37:04

A few important shape details are already visible: persisted JSON is local app-support based, profile and workout summaries carry explicit schema versions, and summary decoding still defaults newer evidence fields. I’m widening the search now for every actual persistence point so the map doesn’t miss local files outside the initial list.

### Assistant - 2026-05-07 18:38:37

The write paths are now clear: free analysis and planned sessions both append `WorkoutSessionSummary` into `WorkoutHistoryStore`, then trophies and insights are recomputed/persisted from derived evidence. I’m reading the test surface next, with extra attention on Codable/backward-compat persistence tests.

### Assistant - 2026-05-07 18:40:36

I’ve got the backend map shape now. I’m going to add a new documentation file only, keeping the implementation untouched; it will call out current behavior versus recommended Firebase-phase decisions so we don’t accidentally smuggle model changes into this phase.

### Assistant - 2026-05-07 18:42:30

The map is now in place under `Documentation/BackendReadinessMap.md`. I’m doing a quick review pass on the generated doc and then I’ll run the available Xcode test/build commands from the workspace.

### Assistant - 2026-05-07 18:42:41

Only the new `Documentation/` directory is my change; the pre-existing `Spotter_Pre_Backend_Readiness.md` remains untouched. I’m starting with the README’s workspace test command on the `VirtualTrainer` scheme and iPhone 17 simulator destination.

### Assistant - 2026-05-07 18:43:19

The test build has compiled and installed the test bundle; now it’s in the simulator execution phase. So far this is behaving like a normal full workspace run rather than a destination/configuration failure.

### Assistant - 2026-05-07 18:43:42

Full tests passed. I’m running the matching workspace build command now as a separate compile check, since the acceptance criteria asked for available tests/build commands.

### Assistant - 2026-05-07 18:44:09

Implemented the backend-readiness map as a documentation-only change:

[BackendReadinessMap.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/BackendReadinessMap.md)

It covers local persisted JSON paths, syncable models, schema versions, account/delete/sync metadata needs, operation-id write paths, current store APIs and gaps, privacy boundaries, proposed Firestore collections, migration behavior, and open Firebase decisions.

Key decision: I did not blindly recommend `deletedAt` everywhere. For derived trophy state and transient insight records, the map calls out safer backend choices like event logs, TTL, invalidation, or recompute policies.

Verification passed:

```sh
xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'
# TEST SUCCEEDED

xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'
# BUILD SUCCEEDED
```

No product behavior changes, no Firebase/repository/model fields added, and no tests were added because this phase only creates documentation. The pre-existing untracked `Spotter_Pre_Backend_Readiness.md` is still untouched.
