# P10.5B_2: Add Quick Start plan deck

- Thread ID: 019dfbd8-4eb2-7070-940f-3415abeaadff
- Created: 2026-05-06 11:22:30 (Asia/Kolkata)
- Updated: 2026-05-06 11:43:54 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/06/rollout-2026-05-06T11-22-30-019dfbd8-4eb2-7070-940f-3415abeaadff.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 210f4e4dd7e39d8384463d8afbd53ce7d6ff6bac
- Exported visible messages: 23
- Extracted input images: 0

## Conversation

### User - 2026-05-06 11:22:32

Bridge 10.5B2 — Quick Start plan deck and cycle-swap
Why this is added

You want excitement in the Train Now / Quick Start surface, but not complexity in the plan detail page. So the right split is:

Plan details = edit volume only
Quick Start = shuffle between quick plan options

This keeps the serious workout preview clean while making the dashboard feel alive.

Prompt
Use the common Spotter Codex preflight block.

Bridge 10.5B2 goal:
Add a Quick Start plan deck to the Train Now / dashboard Smart Start card. The user can cycle-swap between up to 5 quick plans.

Important files to inspect:
- VirtualTrainer/UI/HomeDashboardView.swift
- VirtualTrainer/Models/DashboardData.swift
- VirtualTrainer/Services/PlanService.swift
- VirtualTrainer/Services/PlanGenerator.swift
- VirtualTrainer/Models/PlanGenerationInput.swift
- VirtualTrainer/Models/UserProfile.swift
- VirtualTrainer/Models/WorkoutHistoryStore.swift
- VirtualTrainerTests/DashboardContentTests.swift
- VirtualTrainerTests/PlanGeneratorTests.swift

Product decision:
- This is not exercise-level smart swapping.
- This swaps the entire Smart Start / Quick Start plan.
- Generate up to 5 quick plans:
  - 2 beginner-intensity quick plans
  - 3 intermediate-intensity quick plans
- User taps “Swap Plan” or “Shuffle” to cycle through them.
- Cycle should feel random/exciting, but be deterministic enough for tests.

Tasks:

1. Add QuickStartPlanDeckService.

Create:
- QuickStartPlanDeckService
- QuickStartPlanVariant
- QuickStartDeck

QuickStartPlanVariant fields:
- id
- title
- subtitle
- intensityLabel: beginner / intermediate
- plan: WorkoutPlanV2
- reason
- deckIndex

2. Generation rules.

Generate 5 variants:
- all should be 7-minute plans
- all must respect equipment
- all must respect age-safety rules
- all must respect camera-switch limits
- all must use current profile goal as anchor, but may vary focus:
  - core
  - lower body
  - upper body
  - mobility reset
  - athletic circuit
- 2 variants should be beginner-intensity
- 3 variants should be intermediate-intensity

Safety interpretation:
- If the user profile is beginner, senior, or safety-limited, intermediate-intensity variants must not violate safety rules.
- If true intermediate variants cannot be safely generated, downgrade them to “Challenge Lite” and explain in the reason.
- Never include unavailable equipment.

3. Deterministic randomness.

Use a deterministic seed so tests are stable:
- profile id
- current day
- goal
- deck generation version

The order should feel shuffled but stable for that day/profile.

4. Dashboard integration.

Update DashboardContent:
- smartStartDeck: QuickStartDeck
- selectedSmartStartIndex or currentSmartStart
- keep current smartStart summary for simple UI compatibility if needed

Update HomeDashboardView:
- SmartStartCard shows current quick plan
- Add secondary CTA:
  - “Swap Plan”
  - or “Shuffle”
- On tap:
  - cycle to next plan in the deck
  - use haptics
  - update displayed plan
- “Go Now” / “Start” opens preview for the currently selected quick plan

5. PlanService API.

Add:
- generateQuickStartDeck(profile:recentWorkoutHistory:now:)
- generateSmartStart(profile:variantSeed:) if useful

Do not break existing generateSmartStart(profile:) callers.

6. Tests.

Add/update tests:
- deck has max 5 plans
- deck has 2 beginner-intensity and 3 intermediate-intensity variants when safely possible
- every deck plan is 7 minutes
- every deck plan respects equipment
- every deck plan respects camera-switch limit
- cycle advances through plans and wraps around
- same profile/day produces stable deck
- different day or seed changes deck order or composition
- starting Smart Start uses selected deck plan

Acceptance criteria:
- Train Now / Smart Start card can cycle between quick plans.
- Plan details still does not expose exercise-level swapping.
- Quick Start remains safe and simple.

### Assistant - 2026-05-06 11:22:35

I’ll trace the dashboard data flow and plan generation pieces first, then I’ll patch the smallest set of models/services/views/tests so the deck behaves like a first-class Smart Start source. After that I’ll run the focused test suite and tighten anything the compiler calls out.

### Assistant - 2026-05-06 11:22:51

I didn’t find a literal “preflight block” string in the repo, so I’m treating it as the repo-first safety pass: check worktree, read the dashboard and plan-generation path, then make scoped changes without disturbing unrelated edits. Next I’m reading the models/services/tests that define the current Smart Start contract.

### Assistant - 2026-05-06 11:23:27

The existing generator already enforces age policy, equipment, difficulty, and camera-switch limits. I’m going to build the deck on top of those rules instead of creating a parallel planner, then add a deterministic deck-order layer and a tiny dashboard index state for cycling.

### Assistant - 2026-05-06 11:26:42

The Xcode project is using synchronized file groups, so adding a new Swift file under `VirtualTrainer/Services` should be picked up without hand-editing the project file. I’m about to add the deck service, extend `PlanGenerationInput` with safe variation knobs, and then wire the dashboard to read from the selected deck item.

### Assistant - 2026-05-06 11:29:09

The model/service layer is now mostly in place: the deck service produces five 7-minute variants, uses a stable profile/day/version seed, and preserves the old `generateSmartStart(profile:)` API. I’m wiring the UI now so the card’s “Start” button follows the currently selected variant rather than the old single Smart Start plan.

### Assistant - 2026-05-06 11:30:37

The dashboard tests now cover the selected-deck behavior, and the generator-side tests cover deck size, intensity counts, equipment, camera limits, same-day stability, day changes, seed changes, and Challenge Lite downgrades. I’m going to run the focused XCTest target now; the first pass will probably reveal any Swift visibility or initializer nits.

### Assistant - 2026-05-06 11:30:55

That first test command used the `.xcodeproj`, and the build stopped before hitting our code because the CocoaPods MediaPipe module was not loaded from the project-only build. I’m switching to the workspace-backed test command so the pod frameworks are available.

### Assistant - 2026-05-06 11:31:39

The workspace build has made it past compilation and signing; it’s now in the simulator test phase. No app-code compiler errors surfaced in that pass, so I’m waiting on the actual XCTest results.

### Assistant - 2026-05-06 11:31:57

The focused dashboard and plan-generator tests are green. I’m doing one full test sweep now because the `PlanGenerationInput` initializer grew new defaulted fields, and that kind of change can touch more call sites than the feature itself.

### Assistant - 2026-05-06 11:32:35

The full suite is still running in the simulator. So far it rebuilt cleanly from the workspace and hasn’t emitted failures; I’m letting it finish rather than cutting the verification short.

### Assistant - 2026-05-06 11:33:34

Implemented Bridge 10.5B2.

Added a deterministic Quick Start deck in [QuickStartPlanDeckService.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/QuickStartPlanDeckService.swift:37>) with:
- `QuickStartPlanVariant`
- `QuickStartDeck`
- 5 seeded 7-minute variants: 2 beginner, 3 intermediate
- profile/day/goal/version deterministic ordering
- equipment, age-safety, and camera-switch limits preserved through the existing generator
- Challenge Lite downgrade for beginner or age-limited profiles

Wired it through:
- [PlanService.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanService.swift:31>) with `generateQuickStartDeck(...)` and seeded Smart Start generation
- [DashboardData.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/DashboardData.swift:58>) with selected deck state and cycling
- [HomeDashboardView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/HomeDashboardView.swift:72>) with the Smart Start card showing the selected variant, a `Shuffle` CTA, haptics, and selected-plan preview start

Also extended tests in [PlanGeneratorTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/PlanGeneratorTests.swift:196>) and [DashboardContentTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/DashboardContentTests.swift:134>) for deck shape, safety, stability, cycling, wrapping, seed/day changes, and selected-plan start behavior.

Verification:
- Focused dashboard/plan tests: passed
- Full suite: `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed

Small note: the project-only test command fails because Pods are not loaded there; the workspace command is the correct one for this repo.

### User - 2026-05-06 11:33:35

Do another in-depth deep audit of the entire codebase and check if there are any unwired code or dependencies or app crashes [ app crashes prevention are important] or bugs - evaluate and resolve them. ALso look for possible incomplete codes, logics, and ways to improve / strengthen existing - evaluate them deeply and only implement the highest confidence and priority ones. review the recent code changes (phases 9A + 9B+ 10+ 10.5B1 + current 10.5B2 changes)and the older code deeply and check for errors, crashes or new bugs. 

Post the above, share an end to end manual testing plan for the features in this chat. think deeply and use highest level of reasoning. be very detailed and in depth and evaluate the code with the highest possible technical lens for bugs, etc - code quality can be skipped, we will improve that later. looking for funtiomnal bugs, crashes, suspicious screens - for parts that are sus and might require a round of manual review - call them out and mention in the end to end testing plan so i can verify those too. Post this we will proceed to phase 11.

### Assistant - 2026-05-06 11:33:50

I’ll do this as a crash-and-functionality audit rather than a style pass: first map the riskiest surfaces, then run static crash searches and tests, then patch only high-confidence issues. I’ll keep an eye on the recent Smart Start deck path plus the older preview/session/history/onboarding flows that it touches.

### Assistant - 2026-05-06 11:34:16

The first broad scan found one direct app-crash smell in the current Smart Start path: `DashboardContent.currentSmartStart` uses `preconditionFailure` if a deck is ever empty. The generator should usually prevent that, but crash-prevention means the UI model should degrade gracefully anyway, so I’m marking that for a high-confidence fix while I continue checking the session and camera paths.

### Assistant - 2026-05-06 11:35:02

I’m seeing a second high-confidence hardening opportunity outside the new deck: camera session configuration can leave a partially configured session if input succeeds but output fails. That is rare, but it affects a core crash-prone dependency surface, so I’m going to make it fail closed and publish `isRunning = false` instead of leaving stale state.

### Assistant - 2026-05-06 11:35:59

I’ve finished the first pass through the camera, readiness, planned-session, history, onboarding, and recent deck code. I’m going to patch three narrowly scoped hardening items now: remove a reachable `preconditionFailure` from dashboard data, make camera configuration cleanly roll back on failure, and remove a force unwrap from form-feedback copy construction.

### Assistant - 2026-05-06 11:38:34

I’ve finished the static audit pass and patched the small set of crash-risk items that had strong evidence. I’m moving into verification now: focused dashboard tests first, then the full simulator test suite so we can separate “the fix works” from “the app still hangs together.”

### Assistant - 2026-05-06 11:39:12

The focused dashboard test build is still running cleanly, with no compile errors surfacing so far. Once that exits, I’ll run the full suite and then do one last diff pass so the final audit notes are anchored to exactly what changed.

### Assistant - 2026-05-06 11:40:10

Focused dashboard coverage passed, including the empty-deck crash fallback and selected-plan start behavior. The full suite is running now; after that I’ll do one more audit sweep for force unwraps and unimplemented-looking strings, then I’ll package the test plan with the “please manually eyeball this” spots.

### Assistant - 2026-05-06 11:40:23

The full XCTest suite passed, which is a good sign for the new deck, preview/session, history, pose, and onboarding invariants. I’m doing one final static analyzer pass now; if Xcode’s analyzer has anything useful to say, I’ll fold that into the audit before I stop.

### Assistant - 2026-05-06 11:41:35

The analyzer completed successfully too. I’m doing a last manual risk pass over the things tests often miss: raw array indexing, camera/model startup paths, and product surfaces that look wired but might still feel suspicious in a real build.

### Assistant - 2026-05-06 11:43:54

**Audit Result**
I did the deep crash/functionality pass and implemented only the highest-confidence fixes I found.

Fixed:
- Added an empty-deck fallback so Smart Start cannot crash if the deck ever generates zero variants: [DashboardData.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/DashboardData.swift:64>).
- Hardened camera session setup so failed output wiring rolls back partial AVCapture inputs/outputs instead of leaving a half-configured session: [CameraManager.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Camera/CameraManager.swift:87>).
- Removed the remaining app-side force unwrap in form feedback missing-joint copy: [FormFeedbackEngine.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Coaching/FormFeedbackEngine.swift:241>).
- Added regression coverage for empty Smart Start deck fallback, selected deck plan behavior, and cycle wrap: [DashboardContentTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/DashboardContentTests.swift:134>).

Verified:
- `xcodebuild test ... -only-testing:VirtualTrainerTests/DashboardContentTests` passed.
- Full `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed.
- `xcodebuild analyze ...` passed.
- No remaining `fatalError`, `preconditionFailure`, `assertionFailure`, `try!`, `as!`, `.first!`, or `.last!` in app Swift files.
- MediaPipe model files are present, camera usage description is wired, Pods are present, and the new Quick Start service compiles into the target.

**Manual Review Callouts**
These are not fixes I’d confidently change in this pass, but they deserve human review:
- Profile tab is currently `ProfileDebugView`, with “Debug reset” production-facing copy.
- Workout camera/session UI still shows debug angle and gesture labels.
- `WorkoutSummaryBuilder.placeholderInsight` is still product-placeholder logic, not a crash.
- Running Analysis dashboard action is intentionally disabled as “Coming Soon.”
- Quick Start focus titles may not perfectly match exercise composition when equipment/safety constraints force safe fallbacks.
- Camera permission denied UX should be manually checked on-device.
- Voice coach drill copy should get product/content review before shipping.
- `ContentView` is unused Hello World; harmless, but stale.

**End-To-End Manual Test Plan**
1. Fresh install: complete onboarding for beginner, intermediate, senior, and limited-equipment profiles. Relaunch and verify profile persists.

2. Dashboard Smart Start: confirm up to 5 Quick Start variants appear through Shuffle, Shuffle cycles and wraps, haptics fire, and Start opens the currently visible plan.

3. Deck safety: test bodyweight-only, mat-only, wall/no-wall, dumbbells/no-dumbbells. Verify no unavailable equipment appears, all Quick Start plans are 7 minutes, and beginner/senior intermediate labels explain Challenge Lite safety.

4. Stability: relaunch same day/profile and confirm deck order is stable. Change simulator date to next day and confirm order or variants change.

5. Plan preview: verify no exercise-level swap UI appears. Only target/set volume editing should be exposed. Edit reps, hold, timed, and set count; reset; start session; confirm edits carry into session.

6. Planned session: test readiness flow, thumbs up/down, countdown, rep sets, hold/timed sets, AMRAP/open targets, manual complete, rest screen, skip/add rest, finish, summary save, and no duplicate history saves.

7. Camera Free Analysis: grant camera, deny camera, test body visibility, hand gesture start, selected exercise tracking, Done, summary save, and history detail.

8. History/Profile: verify streaks, recent workout, aggregate stats, reset onboarding, coach default changes, and relaunch persistence.

9. Suspicious UI pass: specifically inspect Profile tab debug copy, session debug overlays, placeholder insights, Running Analysis disabled state, and Quick Start title-vs-exercise fit under limited equipment.

We’re in a much cleaner place for Phase 11.
