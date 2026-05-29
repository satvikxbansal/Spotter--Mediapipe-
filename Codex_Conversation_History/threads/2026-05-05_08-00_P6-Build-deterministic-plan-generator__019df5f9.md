# P6: Build deterministic plan generator

- Thread ID: 019df5f9-3f75-7623-a4ad-8837d3b45513
- Created: 2026-05-05 08:00:45 (Asia/Kolkata)
- Updated: 2026-05-05 08:44:36 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/05/rollout-2026-05-05T08-00-45-019df5f9-3f75-7623-a4ad-8837d3b45513.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 0992d7e4a9fd2f26108bfa827e75f1f5d59a00c6
- Exported visible messages: 14
- Extracted input images: 0

## Conversation

### User - 2026-05-05 08:01:01

# Files mentioned by the user:

## Convo with Chatgpt Pro 5.5 model.md: /Users/satvik.bansal/Downloads/Convo with Chatgpt Pro 5.5 model.md

## My request for Codex:
Use the universal Spotter instruction block and read debug log. Understand the complete code and read the DEBUG logs. then go through the below in extreme detail. Read all the existing files, cursor rules. Ensure you are not changing anything else apart from the below. After doing the change share a detailed note on what was done and how can we verify if new changes were implemented correctly and old ones are not broken. For more context, attached is a markdown doc with all the phases defined in the conversation with the 5.5 pro model. WE ARE WORKING ON PHASE 6 ONLY NOW.  

Use the universal Spotter instruction block.

Phase 6 goal:
Build deterministic local workout plan generation.

Create:
1. PlanGenerator
2. PlanService
3. PlanGenerationInput
4. PlanGenerationRules
5. PlanSwapService if scope allows

Inputs:
- UserProfile
- FitnessGoal
- FitnessLevel
- AgeBracket
- EquipmentOption set
- sessionLength: 7, 15, 25, 35
- preferredCoach
- recent workout history placeholder
- optional excluded exercises

Outputs:
- WorkoutPlanV2

Rules:
Goal mapping:
- strength: build muscle, control, progressive reps
- performance: stamina, athleticism, pace, circuits
- longevity: mobility, balance, joint-friendly consistency

Age behavior:
- under 18: conservative, bodyweight-first
- 18–34: baseline
- 35–49: slightly more warmup/rest for beginners
- 50–64: lower-impact bias, longer rest
- 65+: conservative intensity, balance/mobility bias

Equipment:
- Never include dumbbell exercises unless user selected dumbbells.
- Kettlebell/bands may be selected, but if no supported exercise metadata exists, do not force them.

Difficulty:
- Beginner gets beginner-friendly exercises.
- Intermediate can receive beginner + intermediate.
- Avoid advanced unless explicitly supported later.

Session length:
- 7 min: max 4 exercises
- 15 min: max 5 exercises
- 25 min: max 6–7 exercises
- 35 min: max 7–8 exercises

Camera switching:
- 7 min: one camera orientation preferred
- 15 min: max one switch
- 25/35 min: max two switches

Plan templates:
- Strength: warmup, lower/push/hinge/core
- Performance: warmup, cardio/circuit, core finisher
- Longevity: mobility, balance, stability, cooldown

Add:
- generateSmartStart(profile)
- generateDailyPlan(profile)
- swapExercise(in plan, exerciseId, reason)

Tests:
1. Beginner strength bodyweight plan has no dumbbell exercises.
2. Beginner performance age 50+ avoids high-impact when alternatives exist.
3. Longevity plan includes mobility/balance/isometric work.
4. Intermediate dumbbell strength includes at least one dumbbell exercise when available.
5. 7-minute plan has max 4 exercises.
6. Camera switch limit is respected.
7. All planned targets are not .open.
8. Generated plan Codable roundtrip works.

### Assistant - 2026-05-05 08:01:08

I’ll first map the repo and the linked phase document so the Phase 6 implementation lands inside the existing architecture instead of drifting into a parallel design. I’ll also check the debug logs and rules before touching files.

### Assistant - 2026-05-05 08:01:21

I found a compact Swift/iOS project with the main app under `VirtualTrainer/`, tests under `VirtualTrainerTests/`, plus the explicit `DEBUG_LOG.md` and Cursor debugging rule. Next I’m reading the phase doc and the core model/service files to anchor the new generator to the current `WorkoutPlanV2` shape.

### Assistant - 2026-05-05 08:01:51

The universal block confirms this phase should stay below the live MediaPipe stack: add local planning services/models, preserve the free-analysis path, keep UI raw, and test the rules. The debug log’s relevant prevention rules are around strict concurrency, Codable only where needed, target membership for new Swift files, and not touching exercise definitions unless necessary.

### Assistant - 2026-05-05 08:05:15

I’ve got the current model shape now: Phase 4 metadata exists for all exercises, Phase 5 `WorkoutPlanV2` already supports reps/holds/timed/AMRAP/open, and the project uses synchronized Xcode groups, so new Swift files under `VirtualTrainer/` and `VirtualTrainerTests/` are picked up automatically. I’m going to add pure `nonisolated` planner code under services/models and keep the camera, rep counter, form feedback, and UI untouched.

### Assistant - 2026-05-05 08:05:53

The planner shape is clear now. I’m adding the smallest Phase 6 surface: typed generation input/rules, a deterministic generator, a service facade with Smart Start/Daily Plan, and a scoped swap service that reuses the metadata catalog instead of touching `ExerciseLibrary` or the live session stack.

### Assistant - 2026-05-05 08:09:29

The core planner is in place now. I’m adding tests that exercise the actual promises in the Phase 6 prompt: equipment safety, age/high-impact behavior, longevity content, dumbbell inclusion when available, exercise-count caps, camera-switch caps, non-open targets, and Codable roundtrip.

### Assistant - 2026-05-05 08:10:25

Tests are written against the generator output rather than implementation details, which is good here: they flatten the generated `WorkoutPlanV2` and verify safety/cap invariants. I’m going to run the Xcode test target now through the workspace, since CocoaPods/MediaPipe wiring matters in this repo.

### Assistant - 2026-05-05 08:10:45

The test run has started on the `iPhone 17` simulator because this machine doesn’t have an `iPhone 16` runtime installed. I also confirmed only the new Phase 6 files are untracked/changed so far; no existing Swift files have been modified.

### Assistant - 2026-05-05 08:11:12

The compiler surfaced strict-concurrency warnings from helper methods placed in extensions, not from the generation logic itself. I’m tightening those helpers to be explicitly `nonisolated` so the planner stays pure and warning-free under the project’s default actor isolation.

### Assistant - 2026-05-05 08:11:58

The first build is still finishing its simulator test phase, but it was launched before the `nonisolated` helper cleanup landed, so I’ll rerun it after it exits. The only warnings that appeared outside the new planner are existing `AngleCalculator` strict-concurrency warnings, which I’m leaving alone because they are outside Phase 6.

### Assistant - 2026-05-05 08:12:59

Two new tests found useful planner behavior gaps rather than app regressions: a 50+ performance plan could still backfill a high-impact slot when a low-impact slot ran out, and longevity stability could choose a non-isometric strength move before an isometric option. I’m tightening those selection rules now.

### Assistant - 2026-05-05 08:13:54

The focused Phase 6 suite is green now: all eight new planner tests pass. I’m running the full `VirtualTrainerTests` target one more time so we verify the existing angle, rep counter, metadata, onboarding, and plan V2 tests still hold.

### Assistant - 2026-05-05 08:15:30

Implemented Phase 6 as a pure local planning layer, without touching the MediaPipe/camera/rep-counting/coaching/UI stack.

Added:
- [PlanGenerationInput.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/PlanGenerationInput.swift:3>): session length enum, recent history placeholder, profile-derived planner input.
- [PlanGenerationRules.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/PlanGenerationRules.swift:3>): age, difficulty, equipment, rest, intensity, and camera-switch rules.
- [PlanGenerator.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanGenerator.swift:3>): deterministic `WorkoutPlanV2` generation from profile + metadata.
- [PlanService.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanService.swift:3>): `generateSmartStart(profile:)`, `generateDailyPlan(profile:)`, and swap facade.
- [PlanSwapService.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanSwapService.swift:3>): scoped deterministic swap support.
- [PlanGeneratorTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/PlanGeneratorTests.swift:4>): all 8 requested Phase 6 tests.

Key behavior:
- No dumbbell-required/tagged exercises unless dumbbells are selected.
- Beginner plans only use beginner-friendly exercises.
- 50+ performance plans avoid high-impact work.
- Longevity plans include mobility, balance, and isometric work.
- 7/15/25/35 minute exercise caps and camera-switch caps are enforced.
- Generated targets are never `.open`.
- Generated `WorkoutPlanV2` Codable roundtrip passes.

Verification run:
```sh
xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'
```

Result: `TEST SUCCEEDED`. The focused Phase 6 tests passed, and the existing angle, rep counter, metadata, onboarding, form feedback, and WorkoutPlanV2 tests also passed. I used `iPhone 17` because this machine does not have an `iPhone 16` simulator installed.

No existing source files were modified; only new Phase 6 files were added. For manual verification later, Phase 7 can call `PlanService().generateSmartStart(profile:)` or `generateDailyPlan(profile:)` from the dashboard and inspect the produced `WorkoutPlanV2`.
