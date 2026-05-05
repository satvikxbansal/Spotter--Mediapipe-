# Spotter

Spotter is an iOS fitness coach that watches your movement through the camera and gives live form feedback while you train.

The big idea is simple: the app should feel like a smart training partner, not a rep counter with a nicer coat of paint. It should see your body position, count the work, catch form breakdowns, adjust future plans, and explain what changed in plain English.

This repo is the SwiftUI + MediaPipe build of Spotter. The raw product foundation is now built through **Phase 5** of the roadmap.

## What Spotter Does Today

Spotter already has the hard technical core in place:

- Live camera training with MediaPipe pose detection.
- Skeleton overlay aligned to the camera preview.
- Rep counting across a 47-exercise library.
- Form feedback from biomechanical rules.
- Exercise-specific camera visibility checks.
- Hand gesture support for readiness and session control.
- Face/exertion analysis when the optional face model is bundled.
- Voice, haptics, motivation, and coach personality hooks.
- Local onboarding for profile, goal, equipment, coach, and theme.
- A Camera tab for open-ended free analysis with no plan or target.
- Planning metadata for every supported exercise.
- Workout plan V2 models for reps, holds, timed work, AMRAP, and open mode.

The current UI is intentionally raw in several places. That is by design. We are building the product brain first, then the full design-system revamp comes later.

## The Product Shape

Spotter is being built around two training flows that share the same live analysis engine.

### 1. Free Analysis

This is the Camera tab flow.

The user picks one exercise, gets camera-ready, and trains freely. Spotter counts reps, shows form quality, gives cues, reads effort, listens for gestures, and lets the user stop whenever they want.

There is no workout plan, no set target, no rest screen, and no fake plan wrapped around it.

### 2. Planned Workouts

This is the next big flow.

The app will generate a plan from the user's goal, level, age bracket, equipment, and recent workout history. The user can preview it, pick a coach, swap exercises, start the session, move through sets and rest screens, and finish with a useful summary.

The important rule: planned workouts should reuse the existing camera-analysis engine. We should not build a second rep-counting or form-feedback pipeline.

## Built Through Phase 5

### Phase 1 and 2: Onboarding and Profile Basics

The app now starts with onboarding instead of dropping straight into the dashboard.

It stores:

- Display name
- Gender identity
- Age and age bracket
- Height and weight units
- Primary goal: Strength, Performance, or Longevity
- Fitness level
- Available equipment
- Preferred coach
- Selected theme

The profile is stored locally for now. Gender is saved for the profile, but it does not decide exercise selection in V1.

### Phase 3: Camera Tab Free Analysis

The Camera tab is now a first-class path.

Users can choose any supported exercise, pass a readiness screen, and start a free analysis session. The live session keeps the existing Spotter magic: camera feed, skeleton, reps, cues, form score, haptics, voice, motivation, hand gestures, and effort tracking.

### Phase 4: Exercise Planning Metadata

Spotter now has a planning metadata catalog separate from the biomechanics library.

`ExerciseLibrary` remains the source of truth for how exercises are tracked. `ExerciseMetadataCatalog` adds product data for planning:

- Difficulty
- Required and optional equipment
- Movement pattern
- Body region
- Plan tags
- Safety tags
- Default rest
- Beginner and intermediate targets
- Free-analysis and planned-workout support

This keeps planning decisions out of the rep-counting engine.

### Phase 5: Workout Plan V2

The old plan model only understood rep targets. The new plan model supports the kinds of workouts Spotter needs next:

- Reps
- Holds
- Timed work
- AMRAP
- Open/free mode

It also adds structured blocks, planned exercises, set targets, coach, source, plan reason, and conversion helpers from the older plan format.

## What Comes Next

The next phases turn the foundation into a full training product.

| Phase | What We Build | Why It Matters |
| --- | --- | --- |
| 6 | PlanGenerator and PlanService | Generate safe local plans from profile + metadata. |
| 7 | Raw Dashboard / Quick Start | Show Smart Start, daily plan, form check, trophies, and coming-soon running analysis. |
| 8 | Workout Preview | Let users inspect a plan, pick a coach, and swap exercises before starting. |
| 9A | Planned Workout Coordinator | Sequence planned sets through the live camera engine. |
| 9B | Rest Screen + Full Lifecycle | Add rest, next-set flow, completion, and a basic summary. |
| 10 | Workout History | Save summaries locally and open workout detail sheets. |
| 11 | Trophy Engine | Reward real progress from workout summaries. |
| 12 | Profile, Stats, Theme Selector | Add XP, streaks, goal changes, coach settings, and theme selection. |
| 13 | AI Coach Insight Engine | Create evidence-backed insights without external AI first. |
| 14 | Day-over-Day Trends | Add calendar snapshots, streaks, and trend insights. |
| 15 | Backend Abstraction | Add repository protocols while staying local-first. |
| 16 | Firebase Integration | Add auth and sync behind a feature flag. |
| 17 | Supabase Alternative | Optional path if we choose Supabase instead of Firebase. |
| 18 | Design System Revamp | Apply the HTML design direction and runtime themes. |
| 19 | Hardening | Privacy, safety, camera lifecycle, error states, and beta readiness. |

The best build order is still local-first. Firebase or Supabase should wait until the app has plans, summaries, trophies, profile, insights, and themes working locally.

## AI Coach Insights

The insight system should not be generic motivation text.

Good Spotter insights should be specific, evidence-backed, and useful. Examples:

- "Your squat depth improved after set 1 and stayed stable through set 3."
- "Push-up form dropped after rep 8, so next time we should start with incline push-ups."
- "Your form score is up over the last three sessions, but upper-body rest extensions are increasing."

The first version should be deterministic and local. It should use workout summaries, form scores, cue frequency, skipped sets, rest extensions, completion percentage, effort trend, and streak data. A language model can rewrite those facts later, but it should not invent them.

## Project Structure

```text
VirtualTrainer/
  Camera/          Camera setup and preview
  Coaching/        Form feedback, voice, haptics, effort, readiness
  DesignSystem/    Current theme and shared UI helpers
  Models/          Exercise library, onboarding, planning, sessions
  RepCounting/     Universal rep counter and rep protocols
  Services/        External/service layers
  UI/              Dashboard, onboarding, camera, trainer session
  Vision/          MediaPipe pose, hand, face, angles, visibility

VirtualTrainerTests/
  Unit tests for angle math, rep counting, metadata, onboarding, plans

NEW_DESIGN/
  HTML and screenshots for the future design-system revamp

FitCount-main/
  Legacy QuickPose sample project kept for reference
```

## Running The App

You need Xcode, CocoaPods, and a real iPhone for full camera testing.

1. Install pods:

   ```sh
   pod install
   ```

2. Download the MediaPipe pose and hand models:

   ```sh
   ./download_models.sh
   ```

3. Open the workspace, not the project:

   ```sh
   open VirtualTrainer.xcworkspace
   ```

4. Select the `VirtualTrainer` scheme.

5. Run on a physical device.

The pose model is required for the core trainer. The hand model powers gesture fallback. If `face_landmarker.task` is not bundled, effort features gracefully disable themselves.

## Running Tests

From Xcode, run the `VirtualTrainerTests` target.

From the command line, use an installed simulator destination, for example:

```sh
xcodebuild test \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The live camera experience still needs a physical device.

## Design Direction

The design reference lives in `NEW_DESIGN/`.

The product direction is dark, sharp, fitness-native, and a little loud in the right places. The main themes are:

- Hyper
- Hot Girl
- Warm
- Spicy

For now, the app stores the selected theme. Phase 18 will turn those choices into a real runtime design system.

## Privacy Notes

Spotter should store summaries, not raw camera data.

Good data to keep:

- Workout summaries
- Rep counts
- Hold seconds
- Form scores
- Cue categories
- Trophy progress
- Insight evidence
- User preferences

Data to avoid uploading by default:

- Raw video
- Camera frames
- Face images
- Raw pose streams
- Raw biometric face data

Any third-party API keys must stay out of client source before shipping. Use local placeholders during development and move real secrets behind backend functions later.

## Current North Star

Build the app in this order:

```text
See movement clearly.
Coach the current rep well.
Generate a useful next workout.
Remember what happened.
Explain progress honestly.
Make the product beautiful after the product works.
```

That is Spotter: a coach that watches carefully, speaks plainly, and gets smarter every session.
