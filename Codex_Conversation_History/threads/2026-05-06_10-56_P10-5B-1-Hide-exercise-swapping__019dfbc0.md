# P10.5B_1: Hide exercise swapping

- Thread ID: 019dfbc0-37a6-7462-a54a-e6c5fdd7d3b1
- Created: 2026-05-06 10:56:11 (Asia/Kolkata)
- Updated: 2026-05-06 11:09:55 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/06/rollout-2026-05-06T10-56-11-019dfbc0-37a6-7462-a54a-e6c5fdd7d3b1.jsonl
- Git branch at thread start: main
- Git SHA at thread start: eeaf5c2ba510f98e5357645bb04bb1c26c1f0b6e
- Exported visible messages: 10
- Extracted input images: 0

## Conversation

### User - 2026-05-06 10:58:34

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
The earlier plan preview allowed smart swaps. Your current product decision is better for now: do not offer exercise swapping inside plan details yet. The attached screenshot shows a focused sheet for editing target volume only.

So this phase should:

Hide Swap All
Hide per-exercise swap buttons
Keep existing PlanSwapService code dormant
Add Adjust Movement sheet
Let user edit sets and reps/counts
Prompt
Use the common Spotter Codex preflight block.

Bridge 10.5B1 goal:
Update Workout Preview so plan-detail editing only supports set count and target count right now. Do not expose exercise swapping in the UI.

Important current files to inspect:
- VirtualTrainer/UI/WorkoutPreviewView.swift
- VirtualTrainer/Models/WorkoutPreviewState.swift
- VirtualTrainer/Services/PlanSwapService.swift
- VirtualTrainer/Services/PlanService.swift
- VirtualTrainer/Models/WorkoutData.swift
- VirtualTrainer/Models/PlanGenerationInput.swift
- VirtualTrainerTests/WorkoutPreviewTests.swift
- VirtualTrainerTests/WorkoutPlanV2Tests.swift

Product decision:
- No visible “Swap all”.
- No visible per-exercise swap button.
- Existing PlanSwapService and swap methods may remain for future use.
- Do not delete swap logic unless required for compilation.
- Add target-volume editing inspired by the attached Exercise Swap Sheet V1 design:
- Adjust Movement
- exercise name
- target volume
- Sets stepper
- Reps stepper for rep-based exercises
- Save Changes
- Reset to Original Plan

Tasks:

1. Hide swap UI from WorkoutPreviewView.
- Remove or hide the “Swap all” button.
- Remove or hide the per-exercise swap icon/button.
- Keep code paths dormant for later if safe.
- Update copy that currently says swaps are limited by camera rules.

2. Add plan target editing.

Create:
- PlanTargetEditService
- TargetVolumeDraft
- TargetVolumeValidation
- TargetVolumeEditSheetView

TargetVolumeDraft should include:
- exerciseId or stable planned-exercise identifier
- originalExerciseType
- draftSetCount
- draftTarget
- minSetCount
- maxSetCount
- minTargetValue
- maxTargetValue
- validationMessage optional

3. Support target types safely.

For .reps:
- edit set count
- edit rep count
- apply the same rep target to each set, or keep slight progression only if current plan already uses progression and implementation remains simple.

For .hold(seconds) and .timed(seconds):
- edit set count
- edit seconds using the same sheet pattern, but label it “Seconds” instead of “Reps”.

For .amrap(seconds: nil):
- edit set count only.
- show target as AMRAP.

For .amrap(seconds: value):
- edit set count
- edit seconds if simple, otherwise keep seconds fixed and document follow-up.

For .open:
- do not allow target editing inside planned workouts unless a safe rule exists.

4. Add safe bounds.

Use conservative defaults:
- set count min 1, max 5
- beginner rep target min 4, max 20
- intermediate rep target min 5, max 30
- hold/timed min 10 seconds, max 90 seconds
- if user age bracket is midlife/senior, keep max conservative
- do not allow zero or negative values

5. Preserve original plan.

WorkoutPreviewState should keep:
- originalPlan
- editedPlan
- hasUserEdits
- resetToOriginalPlan()
- resetExerciseToOriginal(exerciseId)

6. UI behavior.

WorkoutPreviewExerciseRow should have an “Adjust” affordance or row tap:
- opens TargetVolumeEditSheetView
- shows current sets and target
- Save Changes updates preview plan
- Reset to Original Plan resets that exercise or the whole plan, whichever is simpler and clearly labeled

7. Planned session should use edited plan.

When user starts the session:
- activePlan must be the edited plan
- edited sets/reps/seconds must show in live HUD
- rest/session coordinator must use edited targets

8. Tests.

Update tests:
- preview no longer exposes visible swap-all/per-row swap behavior if tested
- existing PlanSwapService tests can remain if they exist
- edit reps updates plan target
- edit set count updates number of PlannedSet values
- reset restores original target and set count
- invalid values are rejected or clamped
- planned session starts with edited target
- editing hold/timed target works or is safely disabled with documented behavior

Acceptance criteria:
- Plan preview has no user-facing smart swap UI.
- User can adjust set count and rep/seconds target.
- Existing swap service remains available for future phases.
- App compiles and tests pass.

### Assistant - 2026-05-06 10:58:37

I’ll start by mapping the repo and reading the named files plus recent debug/build clues before touching anything. After that I’ll make the smallest implementation that fits the existing model flow, then build/test and audit the diff carefully.

### Assistant - 2026-05-06 10:58:57

I found the Swift app, tests, and a `DEBUG_LOG.md` at the repo root. Next I’m reading the preview/state/service/test surfaces together so the implementation lands where the app already expects plan mutations to live.

### Assistant - 2026-05-06 11:00:36

The important shape is clear now: planned sessions already consume `WorkoutPlanV2` through `PlannedWorkoutCoordinator`, so editing the preview plan itself will naturally drive the HUD/rest/session coordinator without touching the live camera stack. I’m going to add a small target-edit service and keep swap services intact but unreferenced by the visible preview UI.

### Assistant - 2026-05-06 11:01:27

I’m going to edit three areas: a pure service/model file for target drafts and clamping, preview state to track original vs edited plans, and the preview UI to replace swap affordances with an Adjust sheet. Then I’ll add unit coverage around the service/state behavior.

### Assistant - 2026-05-06 11:05:40

The preview UI no longer has the swap entry points; the swap service and state methods remain available behind the scenes for a later phase. I’m at the compile/test loop now, which should also catch Swift pattern-matching or SwiftUI builder issues in the new service/sheet.

### Assistant - 2026-05-06 11:07:00

The app target has compiled and the test runner is still active. I haven’t touched the MediaPipe/camera/live pipeline classes; the edited plan is flowing through the existing coordinator path exactly as hoped.

### Assistant - 2026-05-06 11:07:47

The full `xcodebuild test` run succeeded on the iPhone 17 simulator. I’m doing the promised audit pass now: checking the diff for accidental swap UI exposure, target bounds behavior, no camera/MediaPipe changes, and no data/privacy regressions.

### Assistant - 2026-05-06 11:08:09

Audit caught one subtle edge: saving an untouched draft could have flattened a generated 8/9 progression into 8/8. I patched that so unchanged saves are true no-ops, and added a regression test before rerunning the suite.

### Assistant - 2026-05-06 11:09:55

Implemented Bridge 10.5B1.

**Changed Files**
- [PlanTargetEditService.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanTargetEditService.swift>)
- [TargetVolumeEditSheetView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/TargetVolumeEditSheetView.swift>)
- [WorkoutPreviewState.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/WorkoutPreviewState.swift>)
- [WorkoutPreviewView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/WorkoutPreviewView.swift>)
- [WorkoutPreviewTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/WorkoutPreviewTests.swift>)

**What Changed**
- Removed visible `Swap all` and per-exercise swap affordances from Workout Preview.
- Left `PlanSwapService` and existing swap state methods dormant for a later phase.
- Added an `Adjust Movement` sheet for planned exercise volume.
- Added set/reps/seconds editing with safe clamping.
- Preserved `originalPlan`, `editedPlan`, `hasUserEdits`, full-plan reset, and per-exercise reset paths in preview state.
- Planned sessions now launch from `previewState.displayPlan`, so edited targets flow into `PlannedWorkoutCoordinator`, live HUD target text, rest flow, and set completion validation through the existing pipeline.

**Key Decisions**
- Used a stable preview identifier of `blockIndex + exerciseIndex` instead of adding IDs to `PlannedExercise`, because that avoids a Codable/model migration ripple.
- Rep/seconds edits apply one uniform target to every rebuilt set, except an unchanged draft is a true no-op so existing generated progressions like `8, 9` are not accidentally flattened.
- `.hold`, `.timed`, and `.amrap(seconds:)` support seconds editing. `.amrap(nil)` supports set-count editing only. `.open` is safely disabled in planned preview editing.
- Midlife/senior caps are more conservative than default bounds.

**Verification**
- `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'` passed.
- `git diff --check` passed.
- Audit grep confirmed no visible swap UI strings/icons remain in `WorkoutPreviewView`.
- Audit grep confirmed these changes do not touch MediaPipe, raw camera frames, secret handling, or upload paths.

**Known Follow-Ups**
- Final visual design polish for the sheet can wait for the design-system revamp.
- Open target editing remains intentionally disabled until there is a clear product rule.
- Future swap work can reuse the dormant swap service without reintroducing UI now.

**Manual E2E Test Plan**
1. Launch app, complete onboarding if needed, open Dashboard.
2. Open Smart Start or Daily Plan preview.
3. Confirm there is no `Swap all` button and no per-row swap icon.
4. Tap `Adjust` on a rep-based movement, change sets and reps, save.
5. Confirm preview chips show the edited set count and target.
6. Reopen the same movement, tap `Reset to Original Plan`, confirm original chips return.
7. Adjust a hold/timed movement, confirm the sheet says `Seconds` and preview updates seconds.
8. Try an open-target plan fixture if available; confirm adjust is disabled or unavailable.
9. Tap `Start Session` after an edit.
10. Confirm the live HUD shows the edited target and total set count.
11. Complete the set and verify rest/up-next uses the edited plan values.
12. Return to Camera tab free analysis and confirm the free-analysis flow still launches independently.
