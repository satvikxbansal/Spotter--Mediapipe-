# Spotter

Spotter is an iPhone fitness coach that watches you train, counts your work, checks your form, and uses that evidence to decide what should happen next.

The promise of the app is simple:

```text
Do not just count reps. Understand the session.
```

That means Spotter should know what exercise you are doing, what the camera can see, whether the rep was clean, where form started to break, how hard the session felt, what you have done recently, and what workout makes sense next.

This repo is the SwiftUI and MediaPipe version of Spotter. It has grown from a camera demo into a local-first training product with onboarding, calibration, live form analysis, generated plans, editable workout previews, planned workout sessions, rest flow, workout summaries, history, trophies, profile stats, trends, and evidence-backed coach insights.

## The Short Version

Spotter can currently:

- Run a SwiftUI iOS app with onboarding, calibration, dashboard, camera, trophies, and profile tabs.
- Track 47 home-friendly exercises across upper body, lower body, full body, core, yoga, and mobility.
- Use MediaPipe Pose Landmarker for 2D and 3D body landmarks.
- Use MediaPipe hand and gesture models for simple workout gestures.
- Use MediaPipe face landmarks as an optional effort signal when the face model is available.
- Count reps and holds with a universal, data-driven rep counter.
- Score form using exercise-specific rules.
- Give real-time cues, haptics, local voice coaching, and motivation.
- Generate local workout plans from profile, goal, level, age, equipment, limitations, history, and session length.
- Offer a 7-minute Quick Start deck with several safe variants that can be cycled from the dashboard.
- Offer Daily Plans using the user's preferred session length.
- Let the user preview a plan, choose a coach, adjust sets and targets, and start a planned session.
- Run planned workouts through the same live camera engine used by free analysis.
- Save workout summaries with rep-level and set-level evidence.
- Compute trophies, XP, streaks, profile stats, trend snapshots, training signals, and coach insights locally.
- Keep raw camera frames, raw video, raw face images, and raw pose streams out of persistent storage.

The product is still not finished. The next big work is backend abstraction, optional Firebase sync, the final design-system revamp, beta hardening, and a careful Running Analysis research phase.

## Why Spotter Exists

Most fitness apps ask you to follow a video or log a workout by hand.

Spotter is different because the camera is part of the coaching loop.

It should be able to say:

```text
I saw the rep.
I understood the form.
I know what changed.
I know what we should do next.
```

That is the heart of the app. The "AI" is not meant to be a random chatbot sitting beside a workout app. The goal is a coach that observes training and turns observation into better feedback, better plans, and better progress.

## Current Product State

The app now has two first-class training flows.

### 1. Free Analysis

Free Analysis is the open camera mode.

Use it when the user wants to quickly check one movement:

- "Check my squat form."
- "Count a set of curls."
- "Let me practice push-ups without starting a full plan."

Flow:

```text
Camera tab
-> choose an exercise
-> pass camera readiness
-> train
-> tap Done
-> see and save a lightweight summary
```

Free Analysis uses the full live trainer stack:

- Camera preview
- Pose detection
- Skeleton overlay
- Hand landmarks
- Gesture recognition
- Universal rep counter
- Form feedback engine
- Haptics
- Local voice coaching
- Motivation engine
- Body visibility checks
- Optional face/exertion analysis
- Rep-quality evidence
- Summary save into local history

### 2. Planned Workouts

Planned Workouts are generated from the user's profile and training history.

Flow:

```text
Dashboard
-> Quick Start or Daily Plan
-> Workout Preview
-> adjust coach, sets, or targets
-> Start Session
-> live camera set
-> rest screen
-> next set
-> workout summary
-> local history, trophies, stats, trends, and insights update
```

The important engineering choice is that planned workouts do not have a second pose engine. They reuse the same live camera analysis stack as Free Analysis.

## Main App Screens

### Onboarding

Onboarding creates a local profile.

It collects:

- Name
- Gender identity
- Age
- Height and weight
- Metric or imperial units
- Primary goal
- Fitness level
- Available equipment
- Physical limitations
- Preferred session length
- Workout days per week
- Reminder preference
- Preferred coach
- Theme choice

The three goals are:

- Strength: build muscle, control, and progressive reps.
- Performance: build stamina, athleticism, and circuit capacity.
- Longevity: build mobility, balance, joint-friendly strength, and consistency.

Profile data is stored locally under app support storage in the `Spotter` folder. Existing profile JSON is decoded with defaults so older local users do not lose their profile when new fields are added.

### Calibration

After onboarding, Spotter can show a lightweight calibration gate.

The default calibration asks the user to complete 3 squats. This verifies that the camera can see the body and that the basic tracking loop works in the user's space.

Calibration can be completed, skipped, failed, and reset in debug tools. The result is stored locally and can unlock the Calibrated trophy.

### Dashboard

The dashboard is the training home.

It shows:

- Time-based greeting
- Athlete name
- Current streak from real local workout history
- Quick Start plan deck
- Daily Plan
- Coach Insight card when evidence exists
- Quick actions
- Trophy teaser
- Recent workout card

Quick actions:

- Form Check: opens Free Analysis exercise selection.
- Running Analysis: visible as Coming Soon.
- Trophies: opens the trophy area.

### Quick Start

Quick Start is a 7-minute plan deck.

The deck can contain up to 5 variants. It is generated locally and seeded by profile, goal, day, and deck version. This makes it feel fresh while keeping tests stable.

Quick Start respects:

- Equipment
- Age rules
- Physical limitations
- Fitness level
- Camera-switch limits
- Recent workout history

The dashboard can cycle through the deck. This gives the app energy without exposing exercise-level swapping inside plan details too early.

### Daily Plan

Daily Plan uses the user's preferred session length:

- 15 minutes
- 25 minutes
- 35 minutes

The plan generator can also make 7-minute plans for Quick Start.

The generator filters exercises first, then scores them. It avoids unsafe or unavailable choices before it tries to make the workout interesting.

It considers:

- Goal
- Fitness level
- Age bracket
- Equipment
- Physical limitations
- Session length
- Preferred coach
- Recent workout history
- Excluded exercises
- Camera setup friction

It also limits camera switching:

- 7-minute plans: 0 switches
- 15-minute plans: up to 1 switch
- 25-minute plans: up to 2 switches
- 35-minute plans: up to 2 switches

This matters because a plan can be correct on paper and still feel bad if the user has to move the phone every two minutes.

### Workout Preview

Workout Preview is the bridge between "the app generated a plan" and "the user is ready to train."

It shows:

- Plan title
- Goal
- Duration
- Difficulty
- Coach
- Exercise count
- Plan insight
- Camera setup sequence
- Blocks
- Exercises
- Sets and targets
- Rest timing
- Coaching focus

The user can:

- Pick Coach Bennett or Coach Fletcher for this plan.
- Save the selected coach as the profile default.
- Adjust set count.
- Adjust rep targets.
- Adjust hold or timed targets when supported.
- Reset an exercise back to the generated plan.
- Start the planned session.

Exercise swapping is intentionally hidden for now. `PlanSwapService` still exists as a foundation, but the current product keeps plan details focused on volume editing.

### Live Trainer

The live trainer owns the camera workout experience.

It uses:

- `CameraManager` for `AVCaptureSession`
- `PoseEstimator` for MediaPipe pose landmarks
- `HandGestureDetector` for gestures
- `FaceLandmarkerService` for optional face blendshapes
- `BodyVisibilityChecker` for required joints
- `FramePositionAnalyzer` for body framing from segmentation masks
- `AngleCalculator` for 2D and 3D biomechanics
- `UniversalRepCounter` for reps and holds
- `FormFeedbackEngine` for cues
- `ExertionAnalyzer` for effort proxy
- `MotivationEngine` for coach copy
- `VoiceCoachManager` for local spoken rep counts and cues
- `HapticsEngine` for touch feedback
- `WorkoutReadyCoordinator` for readiness and countdown

Recent camera and biomechanics fixes include:

- One-frame-at-a-time processing guards for pose, hand, and face work.
- Frame timeout cleanup so stale results do not freeze the session.
- MediaPipe sample timestamps from `CMSampleBuffer` presentation time.
- Smoothed overlay landmarks separate from raw landmarks used for rep counting.
- Aspect-fill coordinate mapping so the skeleton lines up with the camera preview.
- Visibility-aware side selection for `.bestAvailable` angles.
- 3D paths for knee-valgus approximation and signed body-line checks, with 2D fallback.
- Lock-protected camera frame handler access.

### Rest Screen

Planned workouts move through rest between sets.

The rest screen supports:

- Countdown
- Skip rest
- Add time
- Up-next exercise state
- Rest outcome capture

Rest behavior is saved into the workout summary and can later power fatigue, plan-fit, and insight logic.

### Workout Summary And History

When a workout ends, Spotter builds a local summary.

Summaries store derived evidence such as:

- Workout mode
- Plan title
- Started and ended time
- Duration
- Total reps
- Total hold seconds
- Average form score
- Completion percent
- Set summaries
- Cue events
- Rep-quality events
- Good-form reps
- Excellent-form reps
- High-severity cue count
- Rest extensions
- Skipped sets
- Structured effort summary
- Workout outcome

Spotter does not store raw camera frames, raw video, raw face images, raw pose streams, or raw biometric face data by default.

### Trophies

The trophy system is deterministic and local.

It includes:

- Trophy definitions
- Trophy progress
- Trophy unlock events
- Trophy store
- Trophy engine
- Trophy collection screen
- Dashboard trophy teaser
- Workout-summary trophy feedback

Trophy categories include:

- Starter
- Consistency
- Form
- Volume
- Muscle group
- Goal
- Calibration
- Time of day
- Elite
- Coming Soon

The system is honest about unavailable metrics. For example, trophies that require real heart-rate data, external load, or unsupported exercises can be marked Coming Soon instead of faking progress from weak signals.

### Profile

The profile tab is now a real product hub, not just a debug screen.

It shows:

- User identity
- Level and XP
- Trophy strip
- Theme selector
- Goal selector
- Coach selector
- Preferred session length
- Stats cards
- Calendar snapshot
- Coach insights
- Recent workout history
- Workout detail sheet
- Debug reset tools in a lower-priority section

Stats are built from real local history and trophy progress.

Current stats include:

- Total workouts
- Planned workouts
- Free Analysis sessions
- Total reps
- Total hold seconds
- Good-form reps
- Excellent-form reps
- Current streak
- Longest streak
- Average form score
- Total duration
- Workouts this week
- XP
- Level
- Trophies earned
- Last workout date

### Trends And Signals

Spotter now has a trend and signal layer.

This is important because the insight engine should not rummage through raw history every time it needs something to say. It should consume structured facts.

The trend engine can build:

- Current streak
- Longest streak
- Workouts this week
- Weekly consistency status
- Daily workout counts
- Daily reps
- Daily hold seconds
- Daily average form
- Daily duration
- Month calendar snapshot
- Exercise trend summaries
- Strongest exercise
- Improving exercise
- Struggling exercise
- Most repeated cue
- Trophy near misses
- Camera friction count

The signal extractor can produce signals for:

- Consistency
- Form improvement
- Form drop-off
- Volume increase or drop
- Completion
- Fatigue
- Rest behavior
- Skipped exercises
- Repeated cues
- Exercise mastery
- Exercise struggles
- Plan fit
- Trophy proximity
- Camera friction
- Progression readiness
- Target fit
- Session fit
- Quality PRs

### Coach Insights

The AI Coach Insight Engine is local and deterministic right now.

It does not call OpenAI, ChatGPT, Firebase, Supabase, or any external LLM. That is intentional.

The engine creates evidence-backed insights for:

- Dashboard
- Workout Preview
- Workout Summary
- Profile
- Trophy screen

Good insights should feel specific and useful:

```text
Push-up form dropped after rep 8, so the next upper-body block should use an easier target before increasing volume.
```

Bad insights are generic:

```text
Great job today. Keep going.
```

The insight system uses:

- `TrendEngine`
- `SignalExtractor`
- `InsightCandidateBuilder`
- `InsightRanker`
- `InsightNarrativeBuilder`
- `InsightEngine`
- `InsightStore`

`InsightStore` persists recent insights, dedupes by key, expires stale insights, and avoids repeating the same idea too often.

## Exercise Library

Spotter currently supports 47 exercises.

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

### Full Body And Core

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

### Yoga And Mobility

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

`ExerciseMetadataCatalog` is the planning source of truth. It defines difficulty, equipment, movement pattern, body region, planning tags, contraindication tags, rest, targets, and whether an exercise works in Free Analysis or Planned Workouts.

Keep those two responsibilities separate.

## Architecture

The most important split is:

```text
ExerciseLibrary
  -> how an exercise is tracked

ExerciseMetadataCatalog
  -> how an exercise is selected for a plan

TrainerSessionView and the live analysis stack
  -> how camera training runs

PlanGenerator and PlanService
  -> how workouts are generated

DashboardContentFactory
  -> how generated workouts become dashboard content

WorkoutPreviewState and PlanTargetEditService
  -> how a generated workout is adjusted before launch

PlannedWorkoutCoordinator
  -> how planned sets, rest, and completion move forward

WorkoutHistoryStore
  -> how local summaries and evidence are saved

TrophyEngine and TrophyStore
  -> how milestones are computed and persisted

TrendEngine and SignalExtractor
  -> how history becomes structured training facts

InsightEngine and InsightStore
  -> how structured facts become useful coach insights
```

Rules that should stay true:

- Keep camera analysis shared between Free Analysis and Planned Workouts.
- Do not create a second pose pipeline for plans.
- Keep business logic out of SwiftUI views when practical.
- Keep `ExerciseLibrary` focused on tracking.
- Keep `ExerciseMetadataCatalog` focused on planning.
- Use deterministic local logic before adding external AI.
- Do not store or upload raw camera data by default.
- Do not ship real API keys or service-role secrets in the iOS client.

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
    PlannedWorkoutCoordinator.swift
    VoiceCoachManager.swift
    WorkoutReadyCoordinator.swift

  DesignSystem/
    LiquidGlass.swift
    Theme.swift

  Models/
    AIInsightModels.swift
    CalibrationRecord.swift
    CalibrationStore.swift
    DashboardData.swift
    ExerciseLibrary.swift
    ExerciseMetadataCatalog.swift
    ExercisePlanMetadata.swift
    InsightStore.swift
    LiveSessionContext.swift
    OnboardingStore.swift
    PlanGenerationInput.swift
    PlanGenerationRules.swift
    StatsEngine.swift
    ThemeStore.swift
    TrainingTrendModels.swift
    TrophyModels.swift
    UserProfile.swift
    WorkoutData.swift
    WorkoutEvidenceModels.swift
    WorkoutHistoryStore.swift
    WorkoutPreviewState.swift
    WorkoutSessionContext.swift
    WorkoutSessionSummary.swift
    WorkoutSummaryBuilder.swift

  RepCounting/
    RepCounterProtocol.swift
    UniversalRepCounter.swift

  Services/
    ElevenLabsService.swift
    InsightCandidateBuilder.swift
    InsightEngine.swift
    InsightNarrativeBuilder.swift
    InsightRanker.swift
    PlanGenerator.swift
    PlanService.swift
    PlanSwapService.swift
    PlanTargetEditService.swift
    QuickStartPlanDeckService.swift
    SignalExtractor.swift
    TrendEngine.swift

  UI/
    BodyVisibilityBannerView.swift
    CalendarSnapshotView.swift
    CalibrationViews.swift
    CameraTabView.swift
    HomeDashboardView.swift
    MainTabView.swift
    OnboardingViews.swift
    PlannedWorkoutSessionView.swift
    ProfileView.swift
    RestScreenView.swift
    TargetVolumeEditSheetView.swift
    TrainerOverlayView.swift
    TrainerSessionView.swift
    TrophiesView.swift
    WorkoutDetailSheetView.swift
    WorkoutPreviewView.swift
    WorkoutSummaryView.swift

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
  Unit tests for onboarding, calibration, planning, dashboard content,
  workout preview, target editing, planned coordination, history,
  evidence, trophies, stats, trends, insights, angle math, form feedback,
  visibility, exertion, and rep counting.

NEW_DESIGN/
  HTML exports and screenshots for the future visual design system.

WorkoutClassifier.mlproj/
  CreateML workout-classifier experiment. It is not integrated into the app yet.
```

## Tech Stack

- Platform: iOS
- Minimum iOS: 17.0
- Language: Swift 5
- UI: SwiftUI
- Camera: AVFoundation
- Pose, hand, gesture, and face models: MediaPipe Tasks Vision
- Dependency manager: CocoaPods
- Haptics: CoreHaptics and UIKit haptic fallbacks
- Local voice: `AVSpeechSynthesizer`
- Optional remote TTS client: ElevenLabs service shell, configured through `ELEVENLABS_API_KEY` if used later
- Persistence: local JSON files in app support storage
- Tests: XCTest

The app uses CocoaPods for MediaPipe. Open the workspace, not just the project file.

```text
Use:  VirtualTrainer.xcworkspace
Avoid: VirtualTrainer.xcodeproj for normal development
```

## MediaPipe Models

Run this before the first build:

```sh
./download_models.sh
```

It downloads these files into `VirtualTrainer/Models/`:

- `pose_landmarker_full.task`
- `hand_landmarker.task`
- `gesture_recognizer.task`
- `face_landmarker.task`

These model files are runtime assets and should not be treated like app source code.

If the gesture recognizer is missing, hand features can fall back to hand-landmark logic. If the face model is missing, face and effort features disable gracefully.

## Running The App

Install pods:

```sh
pod install
```

Download MediaPipe models:

```sh
./download_models.sh
```

Open the workspace:

```sh
open VirtualTrainer.xcworkspace
```

Then select the `VirtualTrainer` scheme and run.

A physical iPhone is best for real camera testing. The simulator can run much of the app, but it is not a complete substitute for the live camera workout experience.

## Running Tests

Run tests from Xcode with the `VirtualTrainerTests` target.

Command-line example:

```sh
xcodebuild test \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Privacy Boundary

Spotter is local-first right now.

Good to store locally:

- Profile and preferences
- Calibration status
- Generated plans
- Edited plan targets
- Workout summaries
- Set summaries
- Rep-quality events
- Cue events
- Rest behavior
- Derived effort summaries
- Trophy progress
- Stats
- Trend snapshots and signals
- Insight history and delivery records
- Theme selection

Do not store or upload by default:

- Raw video
- Camera frames
- Face images
- Raw pose streams
- Raw biometric face data

Third-party secrets must not ship in the iOS client. That includes OpenAI keys, ElevenLabs keys, Firebase private keys, Supabase service-role keys, and similar credentials. Future services that need secrets should live behind backend functions.

## Current Roadmap

The attached product plan and the recent codebase now line up like this:

Done or mostly done:

- Bridge 10.5A2: richer workout evidence
- Bridge 10.5B1: target editing instead of visible plan-detail swaps
- Bridge 10.5B2: Quick Start deck cycling
- Bridge 10.5C: expanded profile preferences
- Bridge 10.5D: calibration foundation
- Bridge 10.5E: foundation audit fixes
- Phase 11: trophy engine
- Phase 12: real profile hub, stats, themes, history, and trophy showcase
- Phase 13: trend and signal engine
- Phase 14: deterministic local coach insight engine

Next work:

### Phase 15: Backend Abstraction

Add repository protocols and local implementations before integrating any backend SDK.

Planned repositories:

- Auth
- Profile
- Plans
- Workouts
- Trophies
- Insights
- Themes
- Calibration

The app should still work fully offline in local mode.

### Phase 16: Firebase Behind A Feature Flag

Add Firebase only after the repository layer exists.

Start with:

- `BackendMode.local`
- `BackendMode.firebase`
- Anonymous auth for internal testing
- Firestore repositories
- Graceful behavior when Firebase config is missing

Store summaries and aggregates. Do not upload raw camera/video/pose/face data.

### Phase 17: Supabase Alternative

Use this only if the product decision changes away from Firebase.

Do not build Firebase and Supabase at the same time.

### Phase 18: Design System Revamp

The app already has functional themes, but the full visual polish is still ahead.

The design revamp should use `NEW_DESIGN/` as the reference and create a real runtime theme system for:

- Hyper
- Hot Girl
- Warm
- Spicy

The revamp should preserve all existing product logic. It should not rewrite the camera pipeline.

### Phase 19: Beta Hardening

This is the stability pass before real testers.

Focus areas:

- Camera lifecycle
- Permission-denied states
- Missing model states
- Duplicate save prevention
- Trophy event dedupe
- Insight repeat prevention
- Performance
- Privacy copy
- Secret scanning
- Build and test health

### Phase 20: Running Analysis Research

Running Analysis should stay Coming Soon for now.

It is a different product problem from home workout rep counting. It needs separate research around phone placement, gait capture, cadence, stride asymmetry, impact approximation, validation, and safety copy.

Do not ship injury-risk claims from unvalidated gait signals.

## Development Notes

Use these rules when extending Spotter:

- Read the existing model and service first.
- Prefer small, testable changes.
- Keep the live camera pipeline shared.
- Keep plan generation deterministic.
- Keep insights evidence-backed.
- Keep trophies honest about unavailable data.
- Keep local JSON backward compatible.
- Keep secrets out of source.
- Add tests when behavior changes.
- Update this README when the product phase changes.

## North Star

Spotter should become the home training app that watches carefully, speaks plainly, and gets smarter every session.

Not louder. Not more complicated. Smarter.

The app should earn trust by showing its work:

```text
Because I saw this, I recommend that.
```

That is the product.
