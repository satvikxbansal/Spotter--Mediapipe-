# Spotter

Spotter is an iPhone fitness coach that watches your movement, understands the exercise, counts the work, and gives form feedback while you train.

The app is being built around one promise:

```text
Do not just count reps. Understand the session.
```

That means Spotter should know what the user is trying to do, what the camera can see, whether the rep was clean, when form starts breaking down, what kind of workout makes sense next, and how to explain all of that in simple language.

This repository is the SwiftUI + MediaPipe version of Spotter. It has moved beyond the original camera demo and is now becoming a local-first training product with onboarding, free camera analysis, generated plans, a raw dashboard, and the foundations for planned workouts.

## Current Product State

The latest code includes:

- A SwiftUI iOS app shell with local onboarding.
- A 47-exercise tracking library.
- MediaPipe pose detection with 2D and 3D body landmarks.
- A live camera trainer with skeleton overlay, rep counting, form scoring, cues, haptics, voice, motivation, hand gestures, and optional face/exertion analysis.
- A first-class Camera tab for free exercise analysis.
- Exercise metadata for planning, equipment rules, movement patterns, safety tags, default rest, and targets.
- Workout Plan V2 models that support reps, holds, timed work, AMRAP, and open mode.
- A deterministic local plan generator.
- Smart Start and Daily Plan generation from the user's profile.
- Dashboard V0 with generated plan cards, quick actions, trophy teaser, and running-analysis placeholder.
- A raw workout preview screen that shows generated plan blocks, targets, camera orientation, coach, and plan reason.
- Unit tests for onboarding, exercise metadata, plan generation, dashboard content, workout plan V2, angle math, form feedback, and rep counting.

Some screens are intentionally raw. The goal right now is to make the product logic real before spending too much time polishing UI.

## What Makes Spotter Different

Most fitness apps ask the user to follow a video or manually log a workout.

Spotter is different because the camera is part of the workout loop.

It can:

- See whether the user's body is visible enough to track.
- Adapt the session to front-view or side-view exercises.
- Count reps from actual movement.
- Score form from exercise-specific biomechanical rules.
- Give cues when knees, hips, shoulders, spine, tempo, or range of motion drift.
- Use hand gestures during readiness and live sessions.
- Use facial blendshapes as an optional effort signal when the face model is present.
- Generate plans that respect goal, level, age, equipment, impact, and camera friction.

The long-term goal is not "AI as a chatbot." The goal is an app that observes training and turns that observation into better decisions.

## Main User Flows

### 1. Onboarding

The app starts with onboarding when no local profile exists.

The onboarding flow collects:

- Display name
- Gender identity
- Age
- Height and weight
- Metric or imperial units
- Primary goal
- Fitness level
- Available equipment
- Preferred coach
- Theme choice

The three goals are:

- Strength: muscle, control, and progressive reps.
- Performance: stamina, athleticism, pace, and circuit capacity.
- Longevity: mobility, balance, and joint-friendly consistency.

Gender is stored for the profile, but it does not drive exercise selection in the current version. Age is used through age-aware planning rules.

The profile is saved locally at app support storage under `Spotter/UserProfile.json`.

### 2. Dashboard

After onboarding, the user lands on the dashboard.

Dashboard V0 currently shows:

- Time-based greeting.
- Athlete name.
- Streak placeholder backed by recent workout-history input.
- Smart Start card.
- Daily Plan card.
- Quick actions.
- Trophy teaser.
- Recent workout card when history is available.

Smart Start is a 7-minute generated plan. Daily Plan is a 25-minute generated plan. Both are created locally through `PlanService` and `PlanGenerator`.

The quick actions are:

- Form Check: enabled and routes into free camera analysis.
- Running Analysis: visible but disabled as Coming Soon.
- Trophies: currently a teaser screen.

### 3. Free Analysis

The Camera tab is the open-ended training flow.

User flow:

```text
Camera tab
-> choose an exercise
-> pass camera readiness
-> start free analysis
-> train until Done
-> see a lightweight summary
```

This flow has no plan, target, rest screen, or set structure. It is for moments like:

- "Check my push-up form."
- "Count squats for a quick set."
- "Let me practice one exercise without starting a whole workout."

Free Analysis still uses the real trainer stack:

- Camera preview
- Pose estimator
- Skeleton overlay
- Hand landmarks
- Universal rep counter
- Form feedback engine
- Haptics
- Voice coach
- Motivation engine
- Body visibility banner
- Effort tracking when face landmarks are available

### 4. Generated Plans

Spotter now generates local plans from user profile data.

Inputs include:

- User profile
- Fitness goal
- Fitness level
- Age bracket
- Equipment
- Session length
- Preferred coach
- Recent workout history placeholder
- Excluded exercises

Supported session lengths:

- 7 minutes
- 15 minutes
- 25 minutes
- 35 minutes

The generator filters exercises first, then scores them.

It filters by:

- Planned-workout support
- Required equipment
- Difficulty
- Beginner friendliness
- Excluded exercises
- Dumbbell availability

It scores by:

- Goal match
- Preferred movement tags
- Impact level
- Age policy
- Bodyweight-first rules
- Balance and mobility bias
- Recent exercise repetition
- Dumbbell strength preference for intermediate users

It also limits camera switching:

- 7-minute plans: no camera switch
- 15-minute plans: up to one switch
- 25-minute plans: up to two switches
- 35-minute plans: up to two switches

This matters because a technically correct plan can still feel bad if the user has to keep moving the phone.

### 5. Workout Preview

Generated plans can be previewed from the dashboard.

The current preview shows:

- Plan title
- Subtitle
- Duration
- Difficulty
- Coach
- Why this plan was generated
- Blocks
- Exercises
- Coaching focus
- Sets and targets
- Camera orientation

This screen is still a raw preview. Full coach switching, exercise swaps from UI, start session, and planned workout coordination are upcoming.

## Built So Far By Phase

### Phase 1 and 2: App Shell, Onboarding, Profile

Built:

- Onboarding gate in `VirtualTrainerApp`.
- `OnboardingStore`.
- `UserProfile`.
- `OnboardingDraft`.
- Profile validation.
- Local JSON persistence.
- Main tab shell.
- Debug profile view with reset.

Important files:

- `VirtualTrainer/VirtualTrainerApp.swift`
- `VirtualTrainer/Models/UserProfile.swift`
- `VirtualTrainer/Models/OnboardingStore.swift`
- `VirtualTrainer/UI/OnboardingViews.swift`
- `VirtualTrainer/UI/MainTabView.swift`

### Phase 3: Camera Tab Free Analysis

Built:

- `CameraTabView`.
- Exercise selection by category.
- Searchable form-check list.
- Camera readiness screen.
- `LiveSessionContext`.
- Free-analysis mode in `TrainerSessionView`.
- Lightweight free-analysis summary sheet.

Important files:

- `VirtualTrainer/UI/CameraTabView.swift`
- `VirtualTrainer/Models/LiveSessionContext.swift`
- `VirtualTrainer/UI/TrainerSessionView.swift`
- `VirtualTrainer/Coaching/WorkoutReadyCoordinator.swift`

### Phase 4: Exercise Planning Metadata

Built:

- `ExercisePlanMetadata`.
- `ExerciseMetadataCatalog`.
- Planning metadata for every supported exercise.
- Coverage tests that every `ExerciseType` has metadata and maps back to `ExerciseLibrary`.

Important files:

- `VirtualTrainer/Models/ExercisePlanMetadata.swift`
- `VirtualTrainer/Models/ExerciseMetadataCatalog.swift`
- `VirtualTrainerTests/ExerciseMetadataCatalogTests.swift`

### Phase 5: Workout Plan V2

Built:

- `WorkoutTarget`
- `WorkoutPlanV2`
- `WorkoutBlock`
- `PlannedExercise`
- `PlannedSet`
- `PlanSource`
- Legacy plan conversion helpers
- Target formatting
- Codable roundtrip tests

The old `WorkoutPlan` and `WorkoutSet` still exist for compatibility while the planned workout flow is being migrated.

Important files:

- `VirtualTrainer/Models/WorkoutData.swift`
- `VirtualTrainerTests/WorkoutPlanV2Tests.swift`

### Phase 6: Local Plan Generation

Built:

- `PlanGenerationInput`
- `PlanSessionLength`
- `PlanGenerationRules`
- `PlanGenerator`
- `PlanService`
- `PlanSwapService`
- Deterministic templates for Strength, Performance, and Longevity
- Age-aware intensity/rest rules
- Equipment-safe filtering
- Camera-switch limits
- Deterministic swap logic foundation
- Plan generation tests

Important files:

- `VirtualTrainer/Models/PlanGenerationInput.swift`
- `VirtualTrainer/Models/PlanGenerationRules.swift`
- `VirtualTrainer/Services/PlanGenerator.swift`
- `VirtualTrainer/Services/PlanService.swift`
- `VirtualTrainer/Services/PlanSwapService.swift`
- `VirtualTrainerTests/PlanGeneratorTests.swift`

### Phase 7: Dashboard V0

Built:

- `DashboardContentFactory`
- Smart Start plan card
- Daily Plan card
- Quick actions
- Running Analysis coming-soon placeholder
- Trophy teaser
- Recent workout placeholder
- Raw `WorkoutPreviewView`
- Dashboard tests

Important files:

- `VirtualTrainer/Models/DashboardData.swift`
- `VirtualTrainer/UI/HomeDashboardView.swift`
- `VirtualTrainer/UI/WorkoutPreviewView.swift`
- `VirtualTrainerTests/DashboardContentTests.swift`

## Exercise Library

Spotter currently supports 47 exercises across four groups.

### Upper Body

- Bicep Curl
- Push Up
- Lateral Raise
- Front Raise
- Overhead Press
- Cobra Wings
- Overarm Reach
- Hammer Curl
- Shoulder Press
- Tricep Dip
- Incline Push Up

### Lower Body

- Squat
- Sumo Squat
- Lunge
- Side Lunge
- Glute Bridge
- Hip Abduction
- Leg Raise
- Wall Sit
- Deadlift
- Calf Raise
- Romanian Deadlift
- Chair Sit-to-Stand
- Hip Thrust
- Reverse Lunge
- Step Up
- Donkey Kick

### Full Body and Core

- Jumping Jack
- Knee Raise
- Sit Up
- V-Up
- Plank
- High Knees
- Mountain Climber
- Reverse Crunch
- Russian Twist
- Bird Dog
- Side Plank

### Yoga and Mobility

- Downward Dog
- Warrior
- Chair Pose
- Tree Pose
- Triangle Pose
- Warrior I
- Warrior III
- Cobra Pose
- Mountain Pose

`ExerciseLibrary` is the biomechanics source of truth. It defines setup instructions, camera position, required joints, phases, angles, thresholds, form rules, and feedback cues.

`ExerciseMetadataCatalog` is the planning source of truth. It defines difficulty, equipment, movement pattern, body region, plan tags, contraindication tags, rest, targets, and whether the exercise works for free analysis or planned workouts.

Keep those responsibilities separate.

## Architecture

The important split is:

```text
ExerciseLibrary
  -> how an exercise is tracked

ExerciseMetadataCatalog
  -> how an exercise is selected for a plan

TrainerSessionView + live analysis stack
  -> how the camera session runs

PlanGenerator + PlanService
  -> how today's workout is chosen

DashboardContentFactory
  -> how generated plans become dashboard content
```

The camera stack should stay shared between free analysis and planned workouts.

Do not create a second pose pipeline for plans.
Do not duplicate rep counting for plans.
Do not put planning rules inside `TrainerSessionView`.

## Project Structure

```text
VirtualTrainer/
  Camera/
    CameraManager.swift
    CameraPreviewView.swift

  Coaching/
    ExertionAnalyzer.swift
    FormFeedbackEngine.swift
    HapticsEngine.swift
    MotivationEngine.swift
    VoiceCoachManager.swift
    WorkoutReadyCoordinator.swift

  DesignSystem/
    Theme.swift
    LiquidGlass.swift

  Models/
    DashboardData.swift
    ExerciseLibrary.swift
    ExerciseMetadataCatalog.swift
    ExercisePlanMetadata.swift
    LiveSessionContext.swift
    OnboardingStore.swift
    PlanGenerationInput.swift
    PlanGenerationRules.swift
    UserProfile.swift
    WorkoutData.swift

  RepCounting/
    RepCounterProtocol.swift
    SquatRepCounter.swift
    UniversalRepCounter.swift

  Services/
    ElevenLabsService.swift
    PlanGenerator.swift
    PlanService.swift
    PlanSwapService.swift

  UI/
    CameraTabView.swift
    HomeDashboardView.swift
    MainTabView.swift
    OnboardingViews.swift
    TrainerOverlayView.swift
    TrainerSessionView.swift
    WorkoutPreviewView.swift

  Vision/
    AngleCalculator.swift
    BodyVisibilityChecker.swift
    FaceLandmarkerService.swift
    FramePositionAnalyzer.swift
    HandGestureDetector.swift
    JointName.swift
    OneEuroFilter.swift
    PoseEstimator.swift

VirtualTrainerTests/
  Unit tests for planning, dashboard content, onboarding, metadata,
  angle math, form feedback, visibility, and rep counting.

NEW_DESIGN/
  HTML and screenshots for the future visual design system.

FitCount-main/
  Legacy QuickPose sample kept only for reference.
```

## Design Direction

The current app uses a dark "No-Fluff Noir" theme:

- Near-black background
- Bone-white text
- Warm amber accent
- Heavy uppercase headers
- Compact cards
- Haptic, camera-first feel

The future design-system revamp will use the HTML reference in `NEW_DESIGN/`.

Theme options already exist in profile data:

- Hyper
- Hot Girl
- Warm
- Spicy

They are stored today. Full runtime theming is still upcoming.

## Roadmap From Here

### Next: Phase 8

Workout Preview should become interactive.

Planned work:

- Start Session button.
- Coach selector.
- Exercise swap UI.
- Save-as-default coach option if useful.
- Plan-specific insight placeholder.
- Safer preview state handling.

### Then: Phase 9A

Build the planned workout coordinator.

Planned work:

- Own current block, exercise, and set.
- Feed each planned set into the existing live trainer.
- Show planned target in the live HUD.
- Advance after target completion or manual Complete Set.
- Keep free analysis untouched.

### Then: Phase 9B

Add the real workout lifecycle.

Planned work:

- Rest screen.
- Skip rest.
- Add 15 seconds.
- Up-next exercise state.
- Workout completion state.
- Basic summary view.
- Camera cleanup between sets.

### Later Phases

After the planned workout loop works:

- Workout history and detail sheets.
- Trophy engine.
- Profile stats, XP, streaks, and calendar.
- Deterministic AI Coach Insight Engine.
- Day-over-day trend analysis.
- Backend abstraction.
- Firebase or Supabase sync.
- Full design-system revamp.
- Privacy, safety, performance, and beta hardening.

## AI Coach Insight Strategy

The insight engine should be built locally and deterministically first.

Bad insight:

```text
Great job today. Keep going.
```

Good insight:

```text
Your push-up form dropped after rep 8, so the next upper-body plan should start with incline push-ups and only progress if form stays above target.
```

Great Spotter insights should be:

- Specific
- Evidence-backed
- Short
- Actionable
- Non-shaming
- Connected to the next plan

The first version should use:

- Rep count
- Hold seconds
- Form score
- Cue frequency
- Cue timing
- Skipped sets
- Rest extensions
- Completion percentage
- Effort trend
- Streak
- Recent exercise history

A language model can rewrite structured insight facts later. It should not invent the facts.

## Backend Strategy

Stay local-first for now.

The app should have these working locally before backend integration:

- Profile
- Generated plans
- Planned workout summaries
- Free-analysis summaries
- Workout history
- Trophies
- Stats
- Insights
- Theme selection

Only after that should the app add repository protocols and then Firebase or Supabase behind a feature flag.

Recommended storage boundary:

Good to store:

- Profile and preferences
- Plans
- Workout summaries
- Per-set summaries
- Rep counts
- Hold seconds
- Form scores
- Cue categories
- Trophy progress
- Insight evidence

Avoid uploading by default:

- Raw video
- Camera frames
- Face images
- Raw pose streams
- Raw biometric face data

## Running The App

You need:

- Xcode
- CocoaPods
- A physical iPhone for the real camera experience

Install pods:

```sh
pod install
```

Download the MediaPipe pose and hand models:

```sh
./download_models.sh
```

Open the workspace:

```sh
open VirtualTrainer.xcworkspace
```

Then select the `VirtualTrainer` scheme and run on a device.

Do not open only `VirtualTrainer.xcodeproj` for normal development. Use the workspace so CocoaPods and MediaPipe are wired correctly.

## MediaPipe Models

`download_models.sh` downloads:

- `pose_landmarker_full.task`
- `hand_landmarker.task`

The code can also use these optional models if they are bundled:

- `gesture_recognizer.task`
- `face_landmarker.task`

If the gesture recognizer is missing, hand gestures fall back to hand-landmark heuristics. If the face model is missing, face/exertion features disable gracefully.

## Running Tests

Run tests from Xcode with the `VirtualTrainerTests` target.

Command-line example:

```sh
xcodebuild test \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The live camera path still needs a physical device.

## Development Notes

Use these rules when extending the app:

- Keep camera analysis shared between free analysis and planned workouts.
- Keep business logic out of SwiftUI views.
- Keep `ExerciseLibrary` focused on tracking and biomechanics.
- Keep `ExerciseMetadataCatalog` focused on planning.
- Prefer deterministic local logic before adding external AI.
- Do not upload raw camera data by default.
- Do not ship real API keys in source.
- Keep the app compiling after each phase.

## Current North Star

Spotter should become the training app that can say:

```text
I saw the rep.
I understood the form.
I know what changed.
I know what we should do next.
```

That is the product: a coach that watches carefully, speaks plainly, and gets smarter every session.
