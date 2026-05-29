# Replicate Spotter UI design

- Thread ID: 019df375-98ec-7d81-8de1-9c8f8b4461ca
- Created: 2026-05-04 20:17:43 (Asia/Kolkata)
- Updated: 2026-05-04 20:31:59 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/04/rollout-2026-05-04T20-17-43-019df375-98ec-7d81-8de1-9c8f8b4461ca.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 2f2f960b2a11d4aa68c31d00f48ef5e6f30add27
- Exported visible messages: 12
- Extracted input images: 0

## Conversation

### User - 2026-05-04 20:17:46

# Files mentioned by the user:

## DesignRefHTML2 2.zip: /Users/satvik.bansal/Downloads/DesignRefHTML2 2.zip

## Convo with Chatgpt Pro 5.5 model.md: /Users/satvik.bansal/Downloads/Convo with Chatgpt Pro 5.5 model.md

## My request for Codex:
[CONTEXT]
okay so we are building SPOTTER. World-class home workout AI coach for beginner and intermediate users. Spotter should not compete as a content library. It should compete as the first home workout app that makes
beginners feel watched, corrected, and progressed without needing a human trainer. The wedge is credible real-time form correction, not the number of workouts. The PMF promise: "Put your phone down. Spotter sees your form, counts your reps, fixes one thing at a time, gives real time coaching in familiar coach voices , useful insights post your workout, useful insights into your performance and updates tomorrow's plan." The product opportunity is strong because Spotter has a credible wedge: not another workout library, but an ondevice AI coach that sees the user, corrects the user, and adapts the next set. The current codebase already has a
real pose-estimation and rep-counting spine: MediaPipe Pose Landmarker in live stream mode, a data-driven
ExerciseDefinition schema, a universal rep counter, form-rule feedback, segmentation-based framing, hand gesture
readiness, haptics, local voice, and a 47-exercise library.

[EXISTING CODE]
the code of spotter has been updated. the updated code is in the project opened here (VirtualTrainer - mediapipe)

[DESIGN]
Updated design with new elements - zip file named (DesignRefHTML 2 2.zip) is attached - all the html code and a folder for screenshots of each screen too for good reference. keep in mind that we have a theme selector too here. we want to ensure that we are replicating the UI and interactions exactly as in the designs. 

[EXISTING DETAILED PLAN FROM PRO 5.5 MODEL]
A copy of the conversation i have had with the Pro model of GPT 5.5 (Extended thinking) is also attached as .md file  here. refer to it to understand my context and where i am coming from. this is extremely well thought (>70 mins think time). Only contraint here being that it did not have a detailed review odf the code due to some contraints in github cloning which should not be a problem here since the code is all available in the project we are working in. give it a read, understand it carefully, evaluate it and then create your detailed plan that we can start building.

[PROMPT AND IMP DETAILS]
Can you once again deeply analyse the updated spotter code as well as the design ref html in complete depth and understand it. You might need to unzip thew folder. Post that can you create prompts for me to get started with the building of the onboarding, dashboard, profile page, workout plans (important), AI coach insights (plan specific, workout specific, DoD trend specific - we want these to be very insightful - have a detailed section on your thoughts on this and then the prompt too to build it out). The AI Coach insights is the most important aspect of the project. I want to build the raw functionalties first and then do a design system revamp so we dont get lost in the UI bits. I believe the above is going to be a very heavy build if one-shotted. we will also test after each phase. Ensure that codex also does a deep review of the complete code before doing any changes and it is informed to use the prompt as reference ervem though it is very detailed but intelligently make any chamges if required after it understands the code to address any misses, etc. 

I want the plan you share to be very thorough - each and every finctioanlity you see in the Design ref is accounted for in some phase or the other - you define phases such that they are testable, implementatble and do not clash. For stuff like integration of third party (firebase/supabase) for backend and auth login - explain the steps i need to do to make this possible too. but lets build as much before this as possible so it is easy to work with existing info and resources. 

No bar on credits being used so use highest level of reasoning possible. think like a senior staff software engineer turned product manager and do the above. If you cannot access any files or resource, call it out. think deeply and understand the context of what we are building and the capabilities/limitations of the current system. Note that we are building a Swift app. 

Also note that in the Camera tab we also have an exercise-specific CTA where user can select an exercise and perform it while spotter analyses, counts, give s feedback - everything that spotter does rn but only for that exercise - no plan, no target - pure rep counting and feedback and motivation and skeleton overlay and effort and hand gesture recognition and form quality - everything! So ensure this is accounted too in addition the plans. would recommend having a separate plans service and keeping the existing exercise service as is? just a sugestion with my limited knowledge - evaluate and do the needful here that works best.  
Hope you understand the user flow we want to achieve from the screenshots and HTML Design ref.  

Generate the detailed plan so we can start building immediately! do not do any changes yet! store the plan as an md file in the project.

### Assistant - 2026-05-04 20:18:03

I’ll ground this in the actual repo and the two reference files first, using read-only inspection. I’ll avoid code changes while we’re in planning mode; for the design zip I’ll inspect contents directly rather than unpacking it into the project.

### Assistant - 2026-05-04 20:18:23

The repo already contains a `NEW_DESIGN` export, but the zip you attached has additional/refined screens such as `form-check-selection.html`, `workout-detail-sheet.html`, and `workout-preview-(copy).html`. I’m going to compare design intent from the attached zip against the current Swift structure, not assume the in-repo export is enough.

### Assistant - 2026-05-04 20:18:34

The Pro-model plan is strong on product sequencing, but it had a real limitation that we don’t have here: it did not build or inspect the local Xcode project. The local project has a `VirtualTrainer` scheme and tests target, so the implementation plan can include concrete build/test gates.

### Assistant - 2026-05-04 20:20:05

The code confirms the architecture risk: `TrainerSessionView` currently owns almost the entire live analysis pipeline directly, and `HomeDashboardView` still fakes “workouts” by wrapping a chosen exercise into three sets. The next plan should split session orchestration from the analysis spine without rewriting MediaPipe or rep/form logic.

### Assistant - 2026-05-04 20:21:37

The HTML design is product-complete enough to drive architecture: onboarding collects identity/vitals/objective/equipment; dashboard has Smart Start plus exercise-specific Form Check; profile owns theme, trophies, calendar, history, and insights; planned workouts need preview, coach choice, live sets, rest, summary, and detail sheets. I’m going to verify build/test health next so the phase prompts have realistic gates.

### Assistant - 2026-05-04 20:21:43

A simulator is available (`iPhone 17 Pro`, iOS 26.2), and the workspace exposes the `VirtualTrainer` scheme plus tests. I’m running the current test target once; this may take a bit, but it gives us a clean baseline before the plan starts adding phases.

### Assistant - 2026-05-04 20:25:01

<proposed_plan>
# Spotter Build Plan + Codex Prompt Pack

## Summary
- Baseline reviewed: SwiftUI + MediaPipe app, 47 exercise definitions, live pose/hand/face/exertion pipeline, universal rep counter, form rules, haptics, local voice, and passing tests via `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`.
- Core decision: keep [ExerciseLibrary.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/ExerciseLibrary.swift:1>) as the biomechanical source of truth; add planning/profile/history/insight layers around it.
- Core refactor: turn [TrainerSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/TrainerSessionView.swift:1>) into a shared live-analysis surface used by two modes: free exercise analysis and planned workout sets.
- Raw functionality comes first; design-system fidelity and theme polish come after the product flows work.

## Key Interfaces To Add
- `SpotterAppState`, `SpotterRoute`, `MainTab`: onboarding gate, dashboard, camera/form-check, profile, workout preview/session/summary routing.
- `UserProfile`: name, gender, age, height/weight + units, goal, level, equipment, preferred coach, selected theme, onboarding timestamps.
- `ExercisePlanningMetadataCatalog`: planning-only metadata keyed by `ExerciseType`, separate from form/rep definitions.
- `WorkoutPlanV2`, `PlannedExercise`, `PlannedSet`, `PlanTarget`: support reps, reps-per-side, seconds, AMRAP, open/free, rest seconds, camera position, swaps, plan reason.
- `LiveWorkoutSessionContext`: `mode: freeAnalysis | plannedWorkout`, exercise, set target, coach, plan id, callbacks for rep/hold/form/effort/cues/completion.
- `WorkoutSummary`, `SetSummary`, `ExerciseSummary`, `WorkoutHistoryRepository`, `Trophy`, `CoachInsight`, `InsightEvidence`.

## Phase Prompts
Use this preamble for every phase: “Deeply inspect the current Swift code before editing. Preserve MediaPipe pose, hand gesture readiness, rep counting, form feedback, haptics, voice, skeleton overlay, and tests. Treat this prompt as reference, but adapt if the code reveals a safer path. Build raw functionality first; do not chase pixel-perfect design yet.”

1. Phase 0 — Save Plan + Audit  
Prompt: “Create `SPOTTER_BUILD_PLAN.md` with this plan, then audit routing, models, camera/session ownership, tests, and the hardcoded ElevenLabs key. Do not change product behavior. Re-run the existing test command and record baseline risks.”

2. Phase 1 — App Shell + Local State  
Prompt: “Add app state, onboarding gate, tab shell, route enum, and local persistence scaffolding. Replace direct `HomeDashboardView()` launch with the app router. Keep current dashboard reachable as a temporary dashboard tab.”

3. Phase 2 — Raw Onboarding  
Prompt: “Implement the DesignRef onboarding fields from `welcome`, identity, vitals, objective/equipment. Persist `UserProfile`. Include validation, back/continue, reset onboarding debug action, and simple native UI.”

4. Phase 3 — Session Context Refactor  
Prompt: “Introduce `LiveWorkoutSessionContext` and make `TrainerSessionView` consume it while preserving current live-analysis behavior. Add callbacks for rep count, hold time, form score, effort, cue, ready state, and stop/cancel.”

5. Phase 4 — Camera Tab Free Analysis  
Prompt: “Build the Form Check flow from `form-check-selection`: searchable/filterable exercise picker, camera readiness, then live free analysis for exactly one selected exercise. No fake three-set plan, no target, no rest screen.”

6. Phase 5 — Plan Models + Metadata  
Prompt: “Add Plan V2 models and planning metadata without rewriting `ExerciseLibrary`. Include goal tags, difficulty, equipment, movement pattern, camera position, beginner safety, default targets, and test coverage for metadata completeness.”

7. Phase 6 — Plan Generator + Dashboard  
Prompt: “Build deterministic local `PlanService`: filter by profile/equipment/level, score by goal, minimize camera switches, generate Smart Start/day plans, and expose refresh. Build raw dashboard matching `quick-start` IA: Smart Start, Form Check, disabled Running Analysis, bottom tabs.”

8. Phase 7 — Workout Preview + Coach Choice  
Prompt: “Implement workout preview from both preview HTML files: plan hero, duration/difficulty/coach, exercise list, target display, swap one/swap all, coach picker, plan-specific insight placeholder, and Start Session route.”

9. Phase 8 — Planned Workout Lifecycle  
Prompt: “Add `PlannedWorkoutCoordinator` to sequence planned set → live analysis → set completion → rest → next set → summary. Support reps, reps-per-side, seconds, AMRAP. Make `CameraManager` lifecycle idempotent across set/rest transitions.”

10. Phase 9 — Summary, History, Detail Sheet  
Prompt: “Persist local workout summaries for free and planned sessions. Build workout summary and historical detail sheet from DesignRef. Capture duration, completion, targets, reps/hold seconds, average form, cues, effort, skipped sets, rest changes.”

11. Phase 10 — Trophy Engine  
Prompt: “Implement deterministic trophies from real summaries: Spark, Calibrated, Form Architect, Squat King, 7-Day Inferno, 1K Club, Elite Form, movement-category trophies, and locked Apex Spotter. Build trophy home/collection raw UI.”

12. Phase 11 — AI Coach Insight Engine  
Prompt: “Build deterministic insight generation before any LLM. Generate plan-specific, workout-specific, and day-over-day insights, each with mandatory evidence and a concrete next action. Integrate into preview, summary, profile, calendar/detail.”

13. Phase 12 — Profile + Theme Selector  
Prompt: “Build profile raw functionality: identity, XP/level, trophies, theme selector, goal edit, coach style edit, workout calendar, insight cards, history list, reset/debug. Persist selected theme but keep design polish minimal.”

14. Phase 13 — Backend Abstraction  
Prompt: “Create repository protocols and local implementations for profile, plans, workouts, trophies, insights, theme. Do not add Firebase/Supabase yet. Ensure models are Codable and backend-ready.”

15. Phase 14 — Firebase Or Supabase  
Prompt: “Add backend behind a feature flag. Prefer Firebase for MVP auth/offline sync unless SQL/admin reporting is the priority. Never upload raw camera frames/video. Keep local mode working without config.”

16. Phase 15 — Design System Revamp  
Prompt: “After flows work, implement Spotter theme tokens and reusable components matching DesignRef: Hyper, Hot Girl, Warm, Spicy; onboarding, dashboard, form check, preview, live, rest, summary, trophies, profile.”

## AI Coach Insights Spec
- Plan-specific insights explain why today’s plan exists: goal, level, equipment, history, recent form, skipped/rest behavior, camera friction, and progression choice.
- Workout-specific insights explain what happened: where form degraded, best/worst set, rep index failure point, cue pattern, target completion, effort trend, and next adjustment.
- Day-over-day insights compare rolling 3/7/14-day windows: form quality, volume, consistency, movement balance, rest dependence, readiness failures, and progression readiness.
- Required model shape: `InsightType`, `InsightPriority`, `surface`, `title`, `shortMessage`, `detail`, `recommendedAction`, `evidence[]`, `createdAt`, optional `planId/workoutId/exerciseType`.
- Quality bar: no generic praise unless tied to evidence; every insight must name a signal and suggest one useful next step.
- LLM later: only rewrite deterministic evidence into nicer copy; never let an LLM invent workout facts.

## Backend/Auth Steps
- Firebase recommended: create Firebase project, add iOS bundle id, download `GoogleService-Info.plist`, add SDK, configure `FirebaseApp`, add Sign in with Apple, Firestore persistence, user-owned security rules, feature flag.
- Firestore shape: `users/{uid}`, `plans/{planId}`, `workouts/{workoutId}`, `workouts/{workoutId}/sets/{setId}`, `trophies/{trophyId}`, `insights/{insightId}`.
- Supabase alternative: create project, tables for profiles/plans/workouts/sets/trophies/insights/themes, enable RLS by `auth.uid()`, configure Apple OAuth, add Swift SDK, keep anon key in config.
- Security default: rotate/remove the hardcoded ElevenLabs key before external testing; use licensed/original coach voices, not shipped secrets.

## DesignRef Coverage
- `welcome`, `onboarding-identity`, `onboarding-stats-v2`, `onboarding`: Phase 2.
- `calibration`, `camera-readiness`, `form-check-selection`: Phases 3-4.
- `quick-start`, theme dashboard preview: Phase 6 and Phase 15.
- `workout-preview`, `workout-preview-(copy)`: Phase 7.
- `live-workout`, `rest-screen`: Phase 8.
- `workout-summary`, `workout-detail-sheet`: Phase 9.
- `trophies`, `trophies-(copy)`, `trophy-collection`: Phase 10.
- `profile`, theme previews: Phase 12 and Phase 15.
- Running Analysis remains a disabled “Exclusive” CTA until a future gait-analysis scope.

## Test Plan
- Run the existing `xcodebuild test` command after every phase.
- Add unit tests for profile persistence, plan generation filters, camera-switch limits, swaps, session coordinator progression, summary aggregation, trophies, and insights.
- Manual device smoke tests for camera permission, readiness, thumbs-up/down, free analysis, planned workout set/rest transitions, skeleton overlay, form cues, voice, haptics, and camera cleanup.
- Acceptance: every phase is shippable, testable, and does not regress the existing live exercise analysis.

## Assumptions
- No repo files were changed during this planning pass; the markdown file should be created as Phase 0 when execution mode begins.
- Build local-first through Phase 13; backend comes after data shapes stabilize.
- Keep `ExerciseLibrary` biomechanical and add planning metadata separately.
- Firebase is the default backend recommendation unless you choose SQL-heavy Supabase workflows.
</proposed_plan>

### User - 2026-05-04 20:28:22

PLEASE IMPLEMENT THIS PLAN:
# Spotter Build Plan + Codex Prompt Pack

## Summary
- Baseline reviewed: SwiftUI + MediaPipe app, 47 exercise definitions, live pose/hand/face/exertion pipeline, universal rep counter, form rules, haptics, local voice, and passing tests via `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`.
- Core decision: keep [ExerciseLibrary.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/ExerciseLibrary.swift:1>) as the biomechanical source of truth; add planning/profile/history/insight layers around it.
- Core refactor: turn [TrainerSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/TrainerSessionView.swift:1>) into a shared live-analysis surface used by two modes: free exercise analysis and planned workout sets.
- Raw functionality comes first; design-system fidelity and theme polish come after the product flows work.

## Key Interfaces To Add
- `SpotterAppState`, `SpotterRoute`, `MainTab`: onboarding gate, dashboard, camera/form-check, profile, workout preview/session/summary routing.
- `UserProfile`: name, gender, age, height/weight + units, goal, level, equipment, preferred coach, selected theme, onboarding timestamps.
- `ExercisePlanningMetadataCatalog`: planning-only metadata keyed by `ExerciseType`, separate from form/rep definitions.
- `WorkoutPlanV2`, `PlannedExercise`, `PlannedSet`, `PlanTarget`: support reps, reps-per-side, seconds, AMRAP, open/free, rest seconds, camera position, swaps, plan reason.
- `LiveWorkoutSessionContext`: `mode: freeAnalysis | plannedWorkout`, exercise, set target, coach, plan id, callbacks for rep/hold/form/effort/cues/completion.
- `WorkoutSummary`, `SetSummary`, `ExerciseSummary`, `WorkoutHistoryRepository`, `Trophy`, `CoachInsight`, `InsightEvidence`.

## Phase Prompts
Use this preamble for every phase: “Deeply inspect the current Swift code before editing. Preserve MediaPipe pose, hand gesture readiness, rep counting, form feedback, haptics, voice, skeleton overlay, and tests. Treat this prompt as reference, but adapt if the code reveals a safer path. Build raw functionality first; do not chase pixel-perfect design yet.”

1. Phase 0 — Save Plan + Audit  
Prompt: “Create `SPOTTER_BUILD_PLAN.md` with this plan, then audit routing, models, camera/session ownership, tests, and the hardcoded ElevenLabs key. Do not change product behavior. Re-run the existing test command and record baseline risks.”

2. Phase 1 — App Shell + Local State  
Prompt: “Add app state, onboarding gate, tab shell, route enum, and local persistence scaffolding. Replace direct `HomeDashboardView()` launch with the app router. Keep current dashboard reachable as a temporary dashboard tab.”

3. Phase 2 — Raw Onboarding  
Prompt: “Implement the DesignRef onboarding fields from `welcome`, identity, vitals, objective/equipment. Persist `UserProfile`. Include validation, back/continue, reset onboarding debug action, and simple native UI.”

4. Phase 3 — Session Context Refactor  
Prompt: “Introduce `LiveWorkoutSessionContext` and make `TrainerSessionView` consume it while preserving current live-analysis behavior. Add callbacks for rep count, hold time, form score, effort, cue, ready state, and stop/cancel.”

5. Phase 4 — Camera Tab Free Analysis  
Prompt: “Build the Form Check flow from `form-check-selection`: searchable/filterable exercise picker, camera readiness, then live free analysis for exactly one selected exercise. No fake three-set plan, no target, no rest screen.”

6. Phase 5 — Plan Models + Metadata  
Prompt: “Add Plan V2 models and planning metadata without rewriting `ExerciseLibrary`. Include goal tags, difficulty, equipment, movement pattern, camera position, beginner safety, default targets, and test coverage for metadata completeness.”

7. Phase 6 — Plan Generator + Dashboard  
Prompt: “Build deterministic local `PlanService`: filter by profile/equipment/level, score by goal, minimize camera switches, generate Smart Start/day plans, and expose refresh. Build raw dashboard matching `quick-start` IA: Smart Start, Form Check, disabled Running Analysis, bottom tabs.”

8. Phase 7 — Workout Preview + Coach Choice  
Prompt: “Implement workout preview from both preview HTML files: plan hero, duration/difficulty/coach, exercise list, target display, swap one/swap all, coach picker, plan-specific insight placeholder, and Start Session route.”

9. Phase 8 — Planned Workout Lifecycle  
Prompt: “Add `PlannedWorkoutCoordinator` to sequence planned set → live analysis → set completion → rest → next set → summary. Support reps, reps-per-side, seconds, AMRAP. Make `CameraManager` lifecycle idempotent across set/rest transitions.”

10. Phase 9 — Summary, History, Detail Sheet  
Prompt: “Persist local workout summaries for free and planned sessions. Build workout summary and historical detail sheet from DesignRef. Capture duration, completion, targets, reps/hold seconds, average form, cues, effort, skipped sets, rest changes.”

11. Phase 10 — Trophy Engine  
Prompt: “Implement deterministic trophies from real summaries: Spark, Calibrated, Form Architect, Squat King, 7-Day Inferno, 1K Club, Elite Form, movement-category trophies, and locked Apex Spotter. Build trophy home/collection raw UI.”

12. Phase 11 — AI Coach Insight Engine  
Prompt: “Build deterministic insight generation before any LLM. Generate plan-specific, workout-specific, and day-over-day insights, each with mandatory evidence and a concrete next action. Integrate into preview, summary, profile, calendar/detail.”

13. Phase 12 — Profile + Theme Selector  
Prompt: “Build profile raw functionality: identity, XP/level, trophies, theme selector, goal edit, coach style edit, workout calendar, insight cards, history list, reset/debug. Persist selected theme but keep design polish minimal.”

14. Phase 13 — Backend Abstraction  
Prompt: “Create repository protocols and local implementations for profile, plans, workouts, trophies, insights, theme. Do not add Firebase/Supabase yet. Ensure models are Codable and backend-ready.”

15. Phase 14 — Firebase Or Supabase  
Prompt: “Add backend behind a feature flag. Prefer Firebase for MVP auth/offline sync unless SQL/admin reporting is the priority. Never upload raw camera frames/video. Keep local mode working without config.”

16. Phase 15 — Design System Revamp  
Prompt: “After flows work, implement Spotter theme tokens and reusable components matching DesignRef: Hyper, Hot Girl, Warm, Spicy; onboarding, dashboard, form check, preview, live, rest, summary, trophies, profile.”

## AI Coach Insights Spec
- Plan-specific insights explain why today’s plan exists: goal, level, equipment, history, recent form, skipped/rest behavior, camera friction, and progression choice.
- Workout-specific insights explain what happened: where form degraded, best/worst set, rep index failure point, cue pattern, target completion, effort trend, and next adjustment.
- Day-over-day insights compare rolling 3/7/14-day windows: form quality, volume, consistency, movement balance, rest dependence, readiness failures, and progression readiness.
- Required model shape: `InsightType`, `InsightPriority`, `surface`, `title`, `shortMessage`, `detail`, `recommendedAction`, `evidence[]`, `createdAt`, optional `planId/workoutId/exerciseType`.
- Quality bar: no generic praise unless tied to evidence; every insight must name a signal and suggest one useful next step.
- LLM later: only rewrite deterministic evidence into nicer copy; never let an LLM invent workout facts.

## Backend/Auth Steps
- Firebase recommended: create Firebase project, add iOS bundle id, download `GoogleService-Info.plist`, add SDK, configure `FirebaseApp`, add Sign in with Apple, Firestore persistence, user-owned security rules, feature flag.
- Firestore shape: `users/{uid}`, `plans/{planId}`, `workouts/{workoutId}`, `workouts/{workoutId}/sets/{setId}`, `trophies/{trophyId}`, `insights/{insightId}`.
- Supabase alternative: create project, tables for profiles/plans/workouts/sets/trophies/insights/themes, enable RLS by `auth.uid()`, configure Apple OAuth, add Swift SDK, keep anon key in config.
- Security default: rotate/remove the hardcoded ElevenLabs key before external testing; use licensed/original coach voices, not shipped secrets.

## DesignRef Coverage
- `welcome`, `onboarding-identity`, `onboarding-stats-v2`, `onboarding`: Phase 2.
- `calibration`, `camera-readiness`, `form-check-selection`: Phases 3-4.
- `quick-start`, theme dashboard preview: Phase 6 and Phase 15.
- `workout-preview`, `workout-preview-(copy)`: Phase 7.
- `live-workout`, `rest-screen`: Phase 8.
- `workout-summary`, `workout-detail-sheet`: Phase 9.
- `trophies`, `trophies-(copy)`, `trophy-collection`: Phase 10.
- `profile`, theme previews: Phase 12 and Phase 15.
- Running Analysis remains a disabled “Exclusive” CTA until a future gait-analysis scope.

## Test Plan
- Run the existing `xcodebuild test` command after every phase.
- Add unit tests for profile persistence, plan generation filters, camera-switch limits, swaps, session coordinator progression, summary aggregation, trophies, and insights.
- Manual device smoke tests for camera permission, readiness, thumbs-up/down, free analysis, planned workout set/rest transitions, skeleton overlay, form cues, voice, haptics, and camera cleanup.
- Acceptance: every phase is shippable, testable, and does not regress the existing live exercise analysis.

## Assumptions
- No repo files were changed during this planning pass; the markdown file should be created as Phase 0 when execution mode begins.
- Build local-first through Phase 13; backend comes after data shapes stabilize.
- Keep `ExerciseLibrary` biomechanical and add planning metadata separately.
- Firebase is the default backend recommendation unless you choose SQL-heavy Supabase workflows.

### Assistant - 2026-05-04 20:28:36

I’ll start turning the plan into code now, beginning with the local-first product spine: persisted profile/app state, plan models/services, session context, free-analysis, planned workouts, history, trophies, insights, and raw UI. I’ll keep the existing MediaPipe path intact and run the Xcode tests at the end.

### Assistant - 2026-05-04 20:30:29

The project uses Xcode’s filesystem-synchronized groups, so new Swift files under `VirtualTrainer/` and `VirtualTrainerTests/` should be picked up without hand-editing the pbxproj. I’m going to add the product spine as new files, then do small targeted patches to the existing app launch, workout model conflict, trainer session, camera lifecycle, and ElevenLabs secret.

### User - 2026-05-04 20:31:59

<turn_aborted>
The user interrupted the previous turn on purpose. Any running unified exec processes may still be running in the background. If any tools/commands were aborted, they may have partially executed.
</turn_aborted>
