# P8: Build WorkoutPreviewView

- Thread ID: 019df646-abb4-7bc3-9349-c9287b98903a
- Created: 2026-05-05 09:25:19 (Asia/Kolkata)
- Updated: 2026-05-05 09:49:52 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/05/rollout-2026-05-05T09-25-19-019df646-abb4-7bc3-9349-c9287b98903a.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 2f0742c19ff669e7214cf6b7538863c07cdb262a
- Exported visible messages: 14
- Extracted input images: 0

## Conversation

### User - 2026-05-05 09:27:11

# Files mentioned by the user:

## Convo with Chatgpt Pro 5.5 model.md: /Users/satvik.bansal/Downloads/Convo with Chatgpt Pro 5.5 model.md

## My request for Codex:
Use the universal Spotter instruction block and read debug log. Understand the complete code and read the DEBUG logs. then go through the below in extreme detail. Read all the existing files, cursor rules. Ensure you are not changing anything else apart from the below. After doing the change share a detailed note on what was done and how can we verify if new changes were implemented correctly and old ones are not broken. For more context, attached is a markdown doc with all the phases defined in the conversation with the 5.5 pro model. WE ARE WORKING ON PHASE 8 ONLY NOW.  

Use the universal Spotter instruction block.

Phase 8 goal:
Build raw WorkoutPreviewView from DesignRef workout-preview.html and workout-preview-(copy).html.

Features:
1. Show:
   - plan title
   - subtitle/objective
   - estimated duration
   - difficulty
   - coach
   - plan reason
   - exercise list
   - sets and targets
   - rest info
   - camera orientation notes
2. Start Session button.
3. Coach selector:
   - Coach Bennett
   - Coach Fletcher
   - save selection into plan/session
4. Swap exercise:
   - per-exercise swap if easy
   - Swap All if supported by PlanService
   - replacement must respect same movement pattern, equipment, difficulty, and camera constraints
5. Plan-specific insight placeholder:
   - generated later by InsightEngine
   - for now show plan.planReason

Requirements:
- Raw SwiftUI.
- Do not start camera until Start Session.
- Keep coach selection independent of global preference unless user chooses Save as default.
- Do not let swaps introduce unavailable equipment.
- Do not exceed camera-switch rule after swaps.

Tests:
- Preview renders a generated plan.
- Coach can be changed.
- Swapping exercise keeps equipment constraints.
- Start Session creates a planned workout session context.

Acceptance check
- User can preview plan.
- User can choose coach.
- User can start planned session.
- Swaps are safe and deterministic.

### Assistant - 2026-05-05 09:27:20

I’ll treat this as a Phase 8-only implementation pass. First I’m going to read the project rules, the referenced conversation doc, and the debug logs so the preview work lands in the existing architecture instead of wandering off in a shiny new direction.

### Assistant - 2026-05-05 09:27:37

I found an existing `WorkoutPreviewView.swift`, plan services/models, a debug log, and `.cursor/rules/debugging.mdc`. That means Phase 8 is likely an upgrade/integration rather than a brand-new island; I’m going to map the existing plan/session types before touching files.

### Assistant - 2026-05-05 09:29:25

The design reference only contains `workout-preview.html`; I don’t see `workout-preview-(copy).html` in `NEW_DESIGN/export-html`. I’ll still cover the copy’s intended functionality from the phase prompt: the coach selector and session-start controls.

### Assistant - 2026-05-05 09:31:54

I’ve got the main shape now: Phase 7 left a static preview, `PlanSwapService` already enforces most swap safety, and `LiveSessionContext` only knows legacy planned workouts. I’m going to add the missing preview state layer, V2 start-context creation, a safe Swap All API, and then wire the SwiftUI to those without touching the MediaPipe/camera pipeline.

### Assistant - 2026-05-05 09:35:54

The edit pass is in place. I’m at the verification stage now; first I’m checking compiler behavior because SwiftUI `Layout`, strict actor isolation, and the file-synchronized project format are the places this sort of change tends to complain.

### Assistant - 2026-05-05 09:37:15

Tests are green on the iPhone 17 simulator. I’m doing one more diff/status pass now to make sure the Phase 8 changes stayed bounded to preview/session/plan plumbing and didn’t drift into the camera or biomechanics layers.

### Assistant - 2026-05-05 09:37:51

Implemented Phase 8 only.

I built the raw interactive workout preview around the existing plan architecture:

- Added preview state logic in [WorkoutPreviewState.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/WorkoutPreviewState.swift:3)
- Rebuilt [WorkoutPreviewView.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/WorkoutPreviewView.swift:3) to show title, subtitle/objective, duration, difficulty, coach, plan reason, insight placeholder, exercises, sets, targets, rest, and camera notes
- Added coach selection for Coach Bennett / Coach Fletcher, with selection staying local to the plan unless “Save default” is tapped
- Added per-exercise Swap and Swap All, using the existing safe swap rules
- Added V2 planned-session context creation in [LiveSessionContext.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/LiveSessionContext.swift:93)
- Added `PlanService.swapAll(...)` in [PlanService.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/PlanService.swift:63)
- Wired dashboard previews to pass the profile into the preview so equipment constraints are respected
- Added focused Phase 8 tests in [WorkoutPreviewTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/WorkoutPreviewTests.swift:1)

I did not touch the MediaPipe pose pipeline, camera manager, rep counter, form feedback engine, hand gesture detector, exertion analyzer, or core biomechanics.

One note: the repo has `NEW_DESIGN/export-html/workout-preview.html`, but I could not find `workout-preview-(copy).html` on disk. I used the phase prompt’s coach-selector requirements to cover that missing reference.

Verification run:

```bash
xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

Result: `** TEST SUCCEEDED **`

How to verify manually:
1. Open Dashboard.
2. Tap Smart Start or Daily Plan.
3. Confirm preview shows plan details, coach, reason, insight placeholder, exercises, targets, rest, and camera setup.
4. Switch coach and confirm the selected coach updates only the preview.
5. Tap Save default and confirm Profile reflects the new coach.
6. Use Swap / Swap all and confirm no unavailable equipment appears and camera switch count stays within the displayed limit.
7. Tap Start Session and confirm the camera starts only after that tap.

### User - 2026-05-05 09:45:20

can you add exercise name on the camera view screen when i start a session? i am unable to remember what to do when i start session.

### Assistant - 2026-05-05 09:45:39

Absolutely, that’s a very real workout-brain problem. I’ll add the current exercise name directly into the live camera HUD for planned sessions, keeping it separate from the plan title so the camera still starts only after Start Session.

### Assistant - 2026-05-05 09:45:56

I found the cause: planned sessions were putting the plan title in the HUD (`25-Minute Strength`) but not the current exercise (`Squat`, `Push Up`, etc.). I’m making the exercise name the prominent live label and keeping the plan title as the smaller eyebrow above it.

### Assistant - 2026-05-05 09:46:21

The HUD now reads like: small plan/mode label, big current exercise name, then set/target info underneath. That should make “what am I doing right now?” visible without adding any new camera behavior.

### Assistant - 2026-05-05 09:48:48

The build side has passed compilation and Xcode is in the simulator test run now. It’s taking its usual MediaPipe/simulator minute, so I’m letting it finish rather than cutting off a useful verification run.

### Assistant - 2026-05-05 09:49:51

Done. I updated the live camera HUD in [TrainerSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/TrainerSessionView.swift:521>) so it now shows:

- small label: plan title or `Free analysis`
- big label: current exercise name, e.g. `SQUAT`
- detail label: `Set 1 of 2 • 8 reps` or `Open practice`

I did not change camera startup, MediaPipe, rep counting, or form feedback behavior.

Verification passed:

```bash
xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

Result: `TEST SUCCEEDED`

I also logged the UI fix in [DEBUG_LOG.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/DEBUG_LOG.md:278>).
