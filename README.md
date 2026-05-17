# Spotter

Spotter is an iPhone fitness coach that watches you train, counts your work, checks your form, and uses that evidence to decide what should happen next.

The promise of the app is simple:

```text
Do not just count reps. Understand the session.
```

That means Spotter should know what exercise you are doing, what the camera can see, whether the rep was clean, where form started to break, how hard the session felt, what you have done recently, and what workout makes sense next.

This repo is the SwiftUI and MediaPipe version of Spotter. It has grown from a camera demo into a local-first training product with onboarding, calibration, live form analysis, generated plans, editable workout previews, planned workout sessions, rest flow, workout summaries, history, trophies, profile stats, training heatmaps, trends, workout recaps, weekly recaps, evidence drill-downs, evidence-backed coach insights, a backend-ready local data foundation, a local repository abstraction layer, and an optional Firebase mode for account/profile/preferences/plans/trophy/insight memory sync.

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
- Compute trophies, XP, streaks, profile stats, trend snapshots, training signals, workout recaps, weekly recaps, and coach insights locally.
- Build useful coach feedback even for the first few saved sessions through bootstrap signals and per-workout recap logic.
- Normalize and cluster repeated form cues through one shared cue taxonomy.
- Apply recent-window policies so old cue and camera-friction history does not dominate current coaching.
- Track insight impressions and lightweight engagement separately, so cooldowns start when an insight is actually shown.
- Let users open evidence sheets from insight cards and workout detail cards.
- Show a 12-week profile heatmap with day drill-ins, workout detail links, and a local share poster.
- Let users export their data as a human-readable JSON folder and delete account data from Profile in both local mode and Firebase mode.
- Delete saved workouts safely by hiding them from normal history while keeping a tombstone for future sync.
- Keep local records ready for future accounts through account ownership, sync metadata, server-time placeholders, and idempotent write operation IDs.
- Preserve trophy unlocks as a canonical event log instead of only a recalculated progress snapshot.
- Keep insight delivery, cooldown, and helpful/not-helpful records ready for cross-device merge.
- Route backend-shaped reads and writes through repository contracts for auth, profile, plans, workouts, trophies, insights, theme, and calibration while preserving the existing local JSON stores.
- Provide Firebase-mode sync for auth, profile, profile-backed theme, calibration, active plan cache, trophy unlock events/progress, insight documents, insight delivery, and insight engagement without changing the live camera product flow.
- Provide Firebase-mode account export and account deletion initiation for Apple account-deletion compliance, with local wipe continuing even if cloud cleanup needs the server-side deletion function.
- Document the planned Firestore shape and sync conflict rules before adding Firebase.
- Document the secrets policy, add environment-scoped xcconfig placeholders, and add a secret-scan config before accepting Firebase client files.
- Keep a no-network LLM rewrite seam behind a default-off feature flag for future coach-copy experiments.
- Keep raw camera frames, raw video, raw face images, and raw pose streams out of persistent storage.

The product is still not finished. The local data foundation, repository layer, first Firebase sync surfaces, and backend-mode compliance scaffolding are now in place, but the next big work is Cloud Functions deployment, the final design-system revamp, beta hardening, and a careful Running Analysis research phase.

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
-> workout recap and optional coach insight
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
- Weekly recap card when the weekly window is eligible
- Coach Insight card when evidence exists
- Quick actions
- Trophy teaser
- Recent workout card

Quick actions:

- Form Check: opens Free Analysis exercise selection.
- Running Analysis: visible as Coming Soon.
- Trophies: opens the trophy area.

Dashboard insights are now presentation-aware. The dashboard can fetch and rank insight candidates without consuming the repeat cooldown; the cooldown is recorded only when the card appears. Users can open the Evidence sheet from the insight card, and the store records lightweight engagement such as opened, helpful, and not helpful.

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
- Open evidence behind a plan insight when one is available.
- Mark a plan insight as helpful or not helpful.

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

The summary screen now always renders a deterministic `WorkoutRecap`. That recap is built from the saved session itself, so the user no longer sees a placeholder when the broader insight engine has nothing eligible to say. It highlights the dominant exercise, form trajectory, useful set evidence, and one next step.

When a generated `AIInsight` is available, it appears below the recap rather than replacing it. The user can open the insight evidence sheet and mark whether the insight was helpful.

Saved workout details expose more of the evidence Spotter already computes:

- Per-set form sparkline from scored reps
- Average form, excellent reps, good reps, and scored-rep pills
- Drop-after-rep and improved-after-rep badges
- Top cue, best cue, and worst cue context
- Rest extended and rest skipped indicators
- Effort and top-cue evidence timelines

Saved workouts can also be deleted from workout detail and profile history. The delete is sync-safe: Spotter hides the workout from normal product surfaces, keeps a tombstone for future backend sync, invalidates coach insights that depended on that workout, and recalculates trophy progress from the remaining visible history.

### Trophies

The trophy system is deterministic and local.

It includes:

- Trophy definitions
- Trophy progress
- Trophy unlock events
- Canonical unlock event log
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

Unlocks are now preserved as canonical events with future server-time support. Progress can still be recomputed from local history, but the earned moment itself has a durable record for future multi-device sync.

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
- 12-week training heatmap
- Day drill-ins with session stats and workout detail links
- Share Heatmap poster rendered locally from aggregate workout summaries
- Collapsed This Month calendar snapshot
- Weekly recap when the weekly window is eligible
- Coach insights
- Recent workout history
- Workout detail sheet
- Local account data controls for Export My Data and Delete My Account and Data
- Debug reset tools in a lower-priority section

Stats are built from real local history and trophy progress.

Profile is also the deeper coaching surface. It can show multiple ranked insights, a weekly recap, a 12-week training heatmap, and evidence drill-downs that link insight evidence back to the relevant saved workout detail.

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
- Daily intensity summaries for the 12-week heatmap
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
- First session
- Setup quality
- Rep cleanliness intro
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
- Quality capacity
- Movement balance
- Cue clusters
- Rest response
- Progression readiness
- Target fit
- Session fit
- Exercise reacquisition
- Exercise preference
- Repeat exercise progress
- Personal baseline
- Quality PRs

New users no longer have to wait for six saved sessions before Spotter can say something specific. `SignalGenerationContext` enables bootstrap signals for the first 1-5 sessions, including first-session consistency, setup quality, rep cleanliness, repeat-exercise progress, and a personal baseline.

Cue-driven trends now use shared normalization and clustering:

- `CueNormalizer` trims, lowercases, collapses whitespace, strips trailing punctuation, and removes common leading words.
- `CueClusterTaxonomy` maps normalized cues into coaching families such as knee tracking, hip hinge, trunk brace, shoulder stack, elbow alignment, wrist position, depth/range, tempo, balance, head/neck, foot placement, and breathing.

The trend layer also has `TrendWindowPolicy` so repeated cues and camera-friction counts focus on recent sessions or recent days instead of all-time history. This keeps old problems from overpowering current training evidence after the user has fixed them.

### Coach Insights

The AI Coach Insight Engine is local and deterministic by default.

It does not call OpenAI, ChatGPT, Firebase, Supabase, or any external LLM in the default build. That is intentional.

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
- `InsightEvidenceSheetView`
- `InsightEngagementControls`
- `InsightRewriter`
- `FeatureFlags`

`InsightStore` persists recent insights, dedupes by key, expires stale insights, stores per-surface delivery records, and avoids repeating the same idea too often.

Important delivery behavior:

- `selectInsights` fetches candidates without marking them as presented.
- `recordImpression` records the actual card impression from UI `onAppear`.
- `recordEngagement` stores opened, dismissed, helpful, and not-helpful signals.
- Important safety-tier insights bypass the normal repeat cooldown.
- The ranker can boost previously helpful insights and penalize recently dismissed or not-helpful ones.
- Ranking is goal-aware, so strength, performance, and longevity users can receive different priorities from the same evidence.

Delivery and engagement records are now account-scoped and sync-ready. They include tombstone and merge behavior so a future backend can keep cooldowns and helpful/not-helpful learning consistent across devices without storing raw workout, camera, pose, or face data inside those records.

The app also has an LLM-ready seam:

- `AIInsight.toLLMContext()` creates a derived, Codable context package.
- `InsightRewriter` defines the rewrite protocol.
- `NoopInsightRewriter` is the default implementation.
- `FeatureFlag.coachInsightLLMRewrite` is off by default.
- `RewriteValidator` rejects rewrites that lose the exercise, action, or evidence anchor.

This means future copy experiments can be added behind a feature flag without changing the privacy boundary or weakening deterministic evidence rules.

### Weekly Recaps

`WeeklyRecapBuilder` creates one composite recap for the completed ISO week when the timing is right:

- Sunday evening after 6 PM in the user's timezone
- Monday morning before noon in the user's timezone

Weekly recaps can appear on Dashboard and Profile once per week per surface. They include:

- Week start and end
- Headline and narrative
- Sessions, average form, total reps, hold time, and trophies earned
- Top moment
- Biggest surprise
- Next-week focus
- Evidence refs
- A stable dedupe key

If the week had no saved sessions, the recap still returns an honest recovery-week story instead of pretending there was training data.

## Backend Readiness And Firebase Sync

Spotter is still local-first by default. `BackendMode.local` must build and run with no Firebase client plist, and local planning, trophies, stats, trends, recaps, weekly recaps, heatmaps, and deterministic coach insights continue to work from local data.

Firebase mode is optional and deliberately partial. It currently uses Firebase Auth plus Firestore repositories for profile, profile-backed theme, calibration, active plan cache, workout summaries and set subdocuments, trophy unlock events/progress, insight documents, insight delivery, and insight engagement. The live camera analysis stack is unchanged, and `Documentation/BackendQAChecklist.md` plus `Documentation/FirebaseEmulatorSetup.md` cover the internal beta stress path.

The recent backend-readiness work makes the local product safer to connect to a backend incrementally. In product terms, the app now has the boring but important foundations that prevent painful sync bugs after launch.

What has been prepared:

- Account ownership: local records can now tell whether they belong to local-only mode or a future signed-in account. Stores can switch visible data by account and can claim existing local data for a future account without changing the user's workout IDs.
- Sync status: profile, workouts, calibration, trophies, insights, insight delivery, insight engagement, and theme state carry metadata for local-only, pending upload, synced, or conflict states.
- Delete safety: deleting a workout writes a tombstone instead of simply removing the record. The workout disappears from normal history, stats, profile, and dashboard surfaces, dependent coach insights are invalidated, and future sync will not accidentally bring the workout back from another device.
- Idempotent writes: save, update, delete, trophy, insight, calibration, theme, and profile writes can carry operation IDs. A local write journal remembers completed operations so a future retry does not double-save the same user action.
- Server-time readiness: workouts, calibration, insights, and trophy unlocks have fields for server-confirmed timestamps where useful. Trophy progress preserves the user's actual `earnedAt` moment for duplicate resolution instead of using sync-write time as the earned date.
- Trophy history: trophy unlocks are now preserved as canonical events, not only as a recalculated progress snapshot. This gives the future backend a stable "this was earned then" record and supports retraction/correction without rewriting history.
- Insight continuity: insight impressions, cooldowns, helpful/not-helpful feedback, and engagement records are account-scoped and have merge rules. A future multi-device user should not lose feedback learning or keep seeing the same insight card on every device.
- Backend-scale local persistence: profile, workout history, trophies, insights, calibration, theme, and the write journal now encode and write JSON through a dedicated persistence actor instead of doing frequent save work on the UI path. Rapid repeated saves are coalesced with a last-write-wins policy, while atomic writes and rollback behavior stay intact.
- Repository layer: the app has backend-shaped protocols, local implementations, and selected Firestore implementations for Auth, Profile, Plans, Trophies, Insights, Theme, and Calibration. In plain terms, the app can keep behaving like an offline app today while Firebase mode plugs into the same product contract. Normal repository reads stay product-facing, so deleted workouts and invalidated insights stay hidden while their tombstones remain available for sync.
- Local account identity: local mode now has a stable anonymous account ID that can be reused across launches. Signing out clears the current local account context, but it does not erase local data unless the user uses the deletion flow.
- Sync orchestrator scaffold: `SyncOrchestrator` has the statuses and entry points needed for broader sync, but in local mode its full sync, remote observation, and dirty-write enqueue steps intentionally succeed as no-ops.
- Theme source-of-truth decision: local `Theme.json` remains a fast boot/cache path. In Firebase mode, the remote source of truth is `UserProfile.selectedTheme`, not a second competing remote theme document.
- Compliance controls: Profile now has Export My Data and Delete My Account and Data in both local mode and Firebase mode. Local export creates a readable temporary JSON folder with profile, workouts, trophies, trophy events, insights, insight delivery, insight engagement, calibration, theme, plans, schema versions, and a plain-English README. Firebase export adds matching `*.remote.json` files for the latest server-side copies where available. Delete clears the local profile, workouts, trophies, insights, calibration, theme, plan cache, write journal, generated export cache, and share-image cache, then returns the app to onboarding. In Firebase mode it also stops sync listeners, performs the small client-allowed plan cleanup while the user is still authenticated, attempts Firebase Auth deletion, and leaves full recursive cleanup to Cloud Functions.
- PII registry: the app now has a simple local registry that names profile fields and health-adjacent sensitivity fields in user-readable language, including limitations, age, height, weight, timezone, reminder preference, account ID, and derived effort summaries.
- Conflict policy: `Documentation/SyncConflictResolution.md` defines how each major record should merge when local and remote copies disagree, and when the app should mark a record as conflicted instead of guessing.
- Firestore shape: `Documentation/FirestoreShape.md` measures a synthetic worst-case workout and chooses a compact workout document plus per-set documents. This keeps history queries light while preserving detailed rep and cue evidence safely under Firestore document limits.
- Secrets and environment config: `Documentation/SECRETS.md` explains how Firebase client config differs from private keys, why service-role credentials do not belong in the iOS repo, and how Debug/Beta/Release builds map to environment-scoped config. `.gitleaks.toml` gives the repo a repeatable secret-scan baseline. `Configurations/Debug.xcconfig` and `Configurations/Release.xcconfig` are wired at the project level without touching the CocoaPods target configs; `Configurations/Beta.xcconfig` is ready for a future Beta build configuration.
- Privacy boundary: the future backend shape still allows only derived training evidence. Raw video, camera frames, face images, raw pose streams, raw biometric face data, raw pose timelines, and secrets stay out of the upload path.

What this means:

```text
Local mode remains fully offline.
Firebase mode now syncs selected account, preference, plan, compact workout history, trophy, and insight memory records.
Derived analytics and the live analysis stack still stay local/client-side: for example, a saved workout can sync to another simulator, while heatmaps, recaps, FPS-sensitive camera analysis, and rep feedback are still computed from local derived records.
```

Still remaining before a backend beta:

- Deploy and verify the account-deletion Cloud Function from the separate `spotter-functions` repo.
- Firestore security rules, App Check, and Firebase console indexes for the new collections.
- Repository-level pagination and listener backpressure for large remote histories.
- Backend-mode QA for account switching, tombstones, conflicts, retries, missing config, emulator coverage, and internal beta cost checks.

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
  -> how milestones, progress, and canonical unlock events are computed and persisted

TrendEngine and SignalExtractor
  -> how history becomes structured training facts

InsightEngine and InsightStore
  -> how structured facts become useful coach insights, impressions, and engagement signals

WorkoutRecapBuilder and WeeklyRecapBuilder
  -> how saved sessions become deterministic recap surfaces

CueNormalizer, CueClusterTaxonomy, and TrendWindowPolicy
  -> how repeated cue evidence stays canonical and recent

AccountContext and AccountOwnership
  -> how local data is scoped to local-only mode or a future signed-in account

PIIRegistry, DataExportService, and AccountDeletionService
  -> how users can understand, export, and initiate deletion for local and Firebase account data

SyncMetadata, WriteOperation, and LocalWriteJournal
  -> how local records become retry-safe and sync-ready without adding a backend SDK yet

InsightRewriter and FeatureFlags
  -> how future rewrite experiments stay behind a default-off seam
```

Rules that should stay true:

- Keep camera analysis shared between Free Analysis and Planned Workouts.
- Do not create a second pose pipeline for plans.
- Keep business logic out of SwiftUI views when practical.
- Keep `ExerciseLibrary` focused on tracking.
- Keep `ExerciseMetadataCatalog` focused on planning.
- Use deterministic local logic before adding external AI.
- Keep recaps and insights evidence-backed even when the user has little history.
- Record insight impressions separately from insight selection.
- Keep account ownership, tombstones, sync metadata, and operation IDs intact on future-syncable records.
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
    AccountContext.swift
    AIInsightModels.swift
    AppClock.swift
    CalibrationRecord.swift
    CalibrationStore.swift
    DashboardData.swift
    ExerciseLibrary.swift
    ExerciseMetadataCatalog.swift
    ExercisePlanMetadata.swift
    InsightStore.swift
    LiveSessionContext.swift
    LocalWriteJournal.swift
    OnboardingStore.swift
    PlanGenerationInput.swift
    PlanGenerationRules.swift
    StatsEngine.swift
    SyncMetadata.swift
    ThemeStore.swift
    TrainingTrendModels.swift
    TrendWindowPolicy.swift
    TrophyModels.swift
    UserProfile.swift
    WorkoutData.swift
    WorkoutDetailEvidenceModel.swift
    WorkoutEvidenceModels.swift
    WorkoutHistoryStore.swift
    WorkoutPreviewState.swift
    WorkoutSessionContext.swift
    WorkoutSessionSummary.swift
    WorkoutSummaryBuilder.swift
    WriteOperation.swift

  RepCounting/
    RepCounterProtocol.swift
    UniversalRepCounter.swift

  Services/
    AccountDeletionService.swift
    CueClusterTaxonomy.swift
    CueNormalizer.swift
    DataExportService.swift
    ElevenLabsService.swift
    FeatureFlags.swift
    InsightCandidateBuilder.swift
    InsightEngine.swift
    InsightNarrativeBuilder.swift
    InsightRanker.swift
    InsightRewriter.swift
    PIIRegistry.swift
    PlanGenerator.swift
    PlanService.swift
    PlanSwapService.swift
    PlanTargetEditService.swift
    QuickStartPlanDeckService.swift
    SignalExtractor.swift
    TrendEngine.swift
    WeeklyRecapBuilder.swift
    WorkoutRecapBuilder.swift

  Sharing/
    ShareCardRenderer.swift
    ShareCoordinator.swift

  UI/
    BodyVisibilityBannerView.swift
    CalendarSnapshotView.swift
    CalibrationViews.swift
    CameraTabView.swift
    HomeDashboardView.swift
    InsightEngagementControls.swift
    InsightEvidenceSheetView.swift
    MainTabView.swift
    OnboardingViews.swift
    PlannedWorkoutSessionView.swift
    ProfileView.swift
    RestScreenView.swift
    TargetVolumeEditSheetView.swift
    TrainingHeatmapView.swift
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
  32 XCTest files with 307 test methods covering onboarding, calibration, planning, dashboard content,
  workout preview, target editing, planned coordination, history,
  evidence, trophies, stats, trends, insights, angle math, form feedback,
  visibility, exertion, cue normalization, cue clustering, insight ranking,
  insight store delivery, workout recaps, weekly recaps, evidence sheets,
  account ownership, sync metadata, write journaling, Firestore size shape,
  and rep counting.

NEW_DESIGN/
  HTML exports and screenshots for the future visual design system.

WorkoutClassifier.mlproj/
  CreateML workout-classifier experiment. It is not integrated into the app yet.

Spotter_Phase1_2_Evaluation.md
  Founder-style evaluation and implementation prompt log for the recent
  trends, signals, insights, trophies, and workout-history hardening work.

Spotter_Pre_Backend_Readiness.md
  Founder-style audit of what needed to exist before repository and Firebase work.

Documentation/BackendReadinessMap.md
  Map of current persistence, syncable models, missing APIs, and backend field needs.

Documentation/SyncConflictResolution.md
  Product and engineering rules for resolving future local-vs-remote conflicts.

Documentation/FirestoreShape.md
  Measured Firestore document-shape decision for workout summaries and set evidence.

Documentation/SECRETS.md
  Secrets policy, Firebase client config mapping, local developer setup, and secret-scan workflow.

Documentation/FirebaseFunctionsPlan.md
  Plan for the separate `spotter-functions` repo to recursively delete user data, vacuum tombstones,
  optionally dedupe operations, and proxy future LLM rewrites without shipping server secrets in iOS.

Configurations/
  Debug, Beta, and Release xcconfig placeholders for environment-scoped client config.
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
- Persistence: local JSON files in app support storage, with sync-ready account ownership, tombstones, sync metadata, a local write journal, and actor-isolated JSON encode/write paths
- Secret hygiene: `Documentation/SECRETS.md`, `.gitleaks.toml`, and environment-scoped xcconfig placeholders
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

- Account ownership IDs for future signed-in accounts
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
- Heatmap day-intensity summaries
- User-initiated heatmap share images rendered from aggregate stats
- User-initiated local data export folders generated in temporary storage
- Workout recaps and weekly recap dedupe records
- Insight history, delivery records, and engagement counts
- Derived, non-raw LLM rewrite context if a future feature-flagged rewrite layer needs it
- Theme selection
- Sync metadata, tombstones, server-time placeholders, and local write-operation journal entries

Do not store or upload by default:

- Raw video
- Camera frames
- Face images
- Raw pose streams
- Raw pose timelines
- Raw biometric face data
- Raw face blendshape streams

The heatmap and share poster use saved workout summaries and derived daily aggregates only. They should not store raw camera frames, raw video, face images, raw pose streams, or raw biometric face data.

Third-party secrets must not ship in the iOS client. That includes OpenAI keys, ElevenLabs keys, Firebase private keys, Supabase service-role keys, and similar credentials. Future services that need secrets should live behind backend functions.

See `Documentation/SECRETS.md` for the repo policy. In short: Firebase `GoogleService-Info` client plists are not service-role private keys, but they must still be environment-scoped. Debug maps to `GoogleService-Info-Dev.plist`, Beta currently maps to Dev until a staging/prod beta decision is made, and Release maps to `GoogleService-Info-Prod.plist`. No real API keys were added to source in this phase.

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
- Phase 14 hardening: impression-based insight delivery, engagement tracking, goal-aware ranking, bootstrap signals, cue normalization, recent-window trend policy, workout recaps, weekly recaps, evidence drill-downs, and the default-off LLM rewrite seam
- Profile heatmap hardening: 12-week intensity view, day drill-ins, collapsed month snapshot, and local share poster
- Pre-backend readiness: account ownership, sync metadata, soft-delete tombstones, workout delete, insight invalidation, idempotent write journal, actor-isolated local persistence, server-time fields, canonical trophy unlock event log, sync-ready insight records, local data export, local account/data deletion, PII registry, conflict rules, measured Firestore shape, secrets policy, environment xcconfigs, and secret-scan config
- Phase 15: backend abstraction protocols, local repositories, local anonymous account identity, app dependency container, and a local-mode no-op sync orchestrator
- Phase 16I: backend-mode data export, Apple account-deletion initiation, local plan-cache compliance cleanup, and Cloud Functions deletion plan documentation

Next work:

### Phase 16: Firebase Behind A Feature Flag

Add Firebase only after the repository layer exists.

Start with:

- `BackendMode.local`
- `BackendMode.firebase`
- Anonymous auth for internal testing
- Firestore repositories
- Graceful behavior when Firebase config is missing
- Firebase client config loading that follows `Documentation/SECRETS.md` and the `Configurations/*.xcconfig` environment mapping
- Firestore shape from `Documentation/FirestoreShape.md`: compact workout documents plus per-set evidence documents
- Conflict behavior from `Documentation/SyncConflictResolution.md`

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
- Insight and recap edge cases
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
- Keep insight selection separate from impression recording.
- Use the shared cue normalizer and cluster taxonomy for cue-driven logic.
- Keep trophies honest about unavailable data.
- Keep local JSON backward compatible.
- Keep JSON persistence off the UI path where practical; use the shared persistence actor for local encode/write/remove work.
- Keep account ownership, sync metadata, tombstones, server-time fields, and operation IDs backward compatible.
- Update sync conflict and Firestore-shape docs when backend assumptions change.
- Keep secrets out of source.
- Run the secret scan before commits that touch config, docs, scripts, or service integrations.
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
