# P14_E: Unify cue normalization

- Thread ID: 019e0124-f441-76b3-9d35-189133b358f1
- Created: 2026-05-07 12:04:19 (Asia/Kolkata)
- Updated: 2026-05-07 12:20:17 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T12-04-19-019e0124-f441-76b3-9d35-189133b358f1.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a8305d617f2abab60b3b8df7bd7426bfdc252375
- Exported visible messages: 14
- Extracted input images: 0

## Conversation

### User - 2026-05-07 12:04:24

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
15. Post building, Review the implementation and suggest ways to expand and deepen this coaching engine. Implement the highest leverage ones ensuring the code is stable and does not break existing functionalities. 

TASK
Cue normalization is forked across SignalExtractor, InsightCandidateBuilder, and
TrendEngine. TrendEngine.cueCounts is case-sensitive. This makes mostRepeatedCue,
repeatedCue signals, and cueCluster signals undercount real repetition.

GOAL
1. Create `Services/CueNormalizer.swift` with one canonical normalizer:
     static func normalize(_ cue: String) -> String
   Steps: trim, lowercase, collapse internal whitespace, strip trailing punctuation,
   strip leading "the/a/an/your/keep/lock/drive". Return the canonical key.

2. Create `Services/CueClusterTaxonomy.swift` with a single source of truth for cue
   families. Replace InsightCandidateBuilder + SignalExtractor inline cluster maps with:
     enum CueCluster: String, CaseIterable {
        case kneeTracking, hipHinge, trunkBrace, shoulderStack, elbowAlign,
             wristNeutral, depthRange, tempoControl, balanceStability,
             headNeck, footPlacement, breathing, other
     }
     static func cluster(for normalized: String) -> CueCluster

   Differentiate `shoulder/elbow/wrist` (currently merged into "upper-stack").
   Differentiate `depth` (squat depth) from `range of motion` from `lower` (verb).
   Add `breathing`, `head/neck`, `foot placement` clusters since the exercise library
   includes those cues.

3. Refactor TrendEngine.cueCounts, SignalExtractor.cueCounts and cueCluster, and
   InsightCandidateBuilder.normalizedCue and grouped-cue logic to use CueNormalizer
   and CueClusterTaxonomy.

CONSTRAINTS
- Behavior: cues that already produced the same `mostRepeatedCue` must still group;
  cues that previously failed to group due to case/whitespace must now group.
- No test should regress. Update existing tests to assert the new normalization.

ACCEPTANCE
- New CueNormalizerTests: 20+ pairs of input → normalized key, including
  punctuation/casing.
- New CueClusterTaxonomyTests: 20+ inputs → cluster, including the wrist/elbow/shoulder
  separation.
- Existing TrendEngineTests, SignalExtractorTests, InsightEngineTests pass.

### Assistant - 2026-05-07 12:04:32

I’ll inspect the repo first and trace the existing cue logic before touching anything. I’ll keep the live camera pieces out of scope and focus on the services/tests around cue normalization, clustering, and insight trends.

### Assistant - 2026-05-07 12:04:44

I found a regular Xcode project with service-heavy app code and a dirty worktree already in place. Some existing modified files overlap the insight area, so I’ll read them carefully and make the cue changes without reverting or trampling those edits.

### Assistant - 2026-05-07 12:05:16

The cue logic is indeed split three ways: `TrendEngine` trims only, `SignalExtractor` has an inline cluster map and lightweight lowercase grouping, and `InsightCandidateBuilder` has its own whitespace-only normalizer. I’m going to add one service-level normalizer and taxonomy, then wire all three call sites through it.

### Assistant - 2026-05-07 12:07:58

I’m making the new services now. One deliberate choice: normalization will define the grouping key, while trend and insight outputs will keep a representative human-readable cue so existing coaching copy does not suddenly become clipped or lowercase.

### Assistant - 2026-05-07 12:11:19

The refactor is wired through the core services now. I’m adding focused tests next: direct normalizer coverage, direct taxonomy coverage, and a couple of regression checks through the trend/signal/insight paths so the app behavior is protected end to end.

### Assistant - 2026-05-07 12:13:20

Xcode sees a single `VirtualTrainer` scheme with synchronized folders, so the new Swift files should be picked up without project-file surgery. I’m going to run the test build next; first I’m checking available simulator destinations so I don’t waste a cycle on a device name this machine doesn’t have.

### Assistant - 2026-05-07 12:13:48

The project build failed before reaching our code because `MediaPipeTasksVision` was not found when building the raw `.xcodeproj`. That usually means the CocoaPods workspace needs to drive the build, so I’m switching to the workspace path next.

### Assistant - 2026-05-07 12:14:45

The workspace build is through compilation and codesigning; the simulator test runner is still working. No source compile errors surfaced in that pass, which is the key signal I wanted before letting the full suite run.

### Assistant - 2026-05-07 12:14:52

Targeted tests passed through the workspace: the new normalizer/taxonomy tests, `TrendEngineTests`, and `InsightEngineTests` are green. I’m running the full test suite now to catch any side effects outside the cue path.

### Assistant - 2026-05-07 12:16:25

Full workspace test suite passed. I’m doing a final implementation review now: looking for accidental scope creep, duplicated normalization paths, and any cue-family edge cases that are cheap to harden without disturbing the live camera pipeline.

### Assistant - 2026-05-07 12:17:11

One small hardening fell out of the review: cues like “raise to shoulder height” are range cues, not shoulder-stack cues, and “lock it out” loses “lock” by design during normalization. I tightened those taxonomy edges and added tests before the final verification pass.

### Assistant - 2026-05-07 12:18:13

The hardened taxonomy pass is green for the cue and insight/trend tests. I’m doing one last full-suite run after that small change so the final status is clean and current.

### Assistant - 2026-05-07 12:20:17

Implemented the cue normalization/taxonomy phase and kept it away from MediaPipe, camera, rep counting, and the live camera pipeline.

**What Changed**
- Added [CueNormalizer.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/CueNormalizer.swift:3>) with the canonical trim/lowercase/whitespace/punctuation/leading-token normalization.
- Added [CueClusterTaxonomy.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/CueClusterTaxonomy.swift:3>) as the single cue-family source of truth, including separate shoulder, elbow, wrist, breathing, head/neck, and foot placement clusters.
- Refactored [TrendEngine.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/TrendEngine.swift:727>) to count cues by normalized key while preserving a readable representative cue for UI/insight copy.
- Refactored [SignalExtractor.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/SignalExtractor.swift:1081>) so repeated-cue evidence and cue-cluster evidence match normalized variants.
- Refactored [InsightCandidateBuilder.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/InsightCandidateBuilder.swift:1072>) to use the canonical normalizer for dedupe/grouping.
- Also normalized the discovered set-level cue counter in [WorkoutEvidenceModels.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/WorkoutEvidenceModels.swift:119>), which was the highest-leverage extra hardening after review.

**Tests**
- Added [CueNormalizerTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/CueNormalizerTests.swift:4>) with 20+ normalization cases.
- Added [CueClusterTaxonomyTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/CueClusterTaxonomyTests.swift:4>) with 20+ taxonomy cases, including wrist/elbow/shoulder separation.
- Added regression coverage in [TrendEngineTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/TrendEngineTests.swift:156>) and [InsightEngineTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/InsightEngineTests.swift:91>).

Verification:
- Raw `.xcodeproj` test attempt failed because CocoaPods modules were not resolved (`MediaPipeTasksVision` missing).
- Correct workspace command passed:
  `xcodebuild test -scheme VirtualTrainer -workspace VirtualTrainer.xcworkspace -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`
- Final full test suite: `TEST SUCCEEDED`.

**Key Decisions**
- I kept `mostRepeatedCue` user-facing text readable instead of returning lowercase canonical keys. The normalized key drives grouping; the display cue remains the best representative original cue.
- I did not touch MediaPipe, `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, live camera flows, or raw camera/biometric data handling.
- I hardened taxonomy for coaching language like “shoulder height” and “lock it out,” which are range cues rather than shoulder-stack cues.

**Manual Test Plan**
1. Launch the app and run Camera tab free analysis for a movement that can trigger form cues, then save the workout summary.
2. Run a planned workout session from preview through completion, including at least one cue-producing set.
3. Complete a second session with a similar cue phrased differently by casing/punctuation/coach wording; verify dashboard/profile repeated-cue insights group it.
4. Trigger shoulder, elbow, and wrist cues separately in upper-body exercises and verify they do not collapse into one generic upper-body family.
5. Check workout history/local summaries only contain cue text and metrics, not raw frames, raw video, face images, raw pose streams, or biometric face data.

**Follow-Ups**
- Extract the display-preserving cue count helper if another cue counter appears.
- Add exercise-context-aware taxonomy scoring so “shoulder height” vs “shoulders stacked” can keep improving.
- Map cue clusters to specific corrective drills and progression gates, making the coaching engine deeper than “focus this cue.”
