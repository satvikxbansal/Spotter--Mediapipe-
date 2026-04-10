---
name: Comprehensive Testing Plan
overview: A complete manual testing plan covering all 29 exercises, their angle thresholds, rep counting, form feedback, scoring, coaching, UI overlays, and end-to-end user flows in the Spotter iOS app.
todos:
  - id: setup
    content: "Pre-test setup: build to device, download models, prepare test environment"
    status: pending
  - id: home-nav
    content: Test home dashboard, splash screen, exercise selection, coach selection flow
    status: pending
  - id: ready-flow
    content: Test positioning, gesture detection, countdown, and thumbs up/down flow
    status: pending
  - id: lower-body
    content: Test all 10 lower body exercises (squats, lunges, bridges, etc.) - reps, angles, feedback
    status: pending
  - id: upper-body
    content: Test all 10 upper body exercises (curls, presses, raises, etc.) - reps, angles, feedback
    status: pending
  - id: full-body
    content: Test all 7 full body exercises (jumping jacks, planks, sit ups, etc.) - reps, angles, feedback
    status: pending
  - id: yoga
    content: Test both yoga exercises (Downward Dog, Warrior II) - isometric holds and form feedback
    status: pending
  - id: form-score
    content: "Test form score calculation: ROM, tempo, feedback penalties, and A-F grading"
    status: pending
  - id: coaching
    content: Test motivation engine (fatigue detection), exertion analyzer, both coach personalities
    status: pending
  - id: overlays
    content: Test skeleton overlay, angle arcs, visibility banner, HUD elements, glow border
    status: pending
  - id: edge-cases
    content: "Test edge cases: camera occlusion, rapid movement, isometric holds, side resolution fallback"
    status: pending
  - id: haptics
    content: "Test all 4 haptic patterns: buttonTap, repTick, successRipple, warningPulse"
    status: pending
isProject: false
---

# Comprehensive Testing Plan for Spotter (VirtualTrainer)

This plan covers all functionality introduced across the recent commits, focusing on the biomechanics optimization (`f80ec74`), new exercises + form scoring (`a630e22`), and all supporting systems. The app must be tested on a **physical iOS device** with a camera.

---

## 1. Pre-Test Setup

- Open `VirtualTrainer.xcworkspace` in Xcode, build to a physical device (iOS 16+)
- Run `./download_models.sh` to ensure `pose_landmarker_full.task` and `hand_landmarker.task` exist in `VirtualTrainer/Models/`
- Ensure good lighting and enough room to perform exercises (at least 6-8 feet from device)
- Use a tripod or stable surface for the phone camera
- Test with both front-facing and rear cameras as exercises require

---

## 2. Home Dashboard and Navigation Flow

### 2.1 Splash Screen

- App opens with "Welcome to" fade-in, then "Spotter" brand name scale animation
- Animation lasts ~2 seconds, then transitions to dashboard
- No visual glitches during the animation sequence

### 2.2 Dashboard

- Time-based greeting displays correctly (Morning/Afternoon/Evening/Late Night)
- "Hey, Satvik" greeting shown
- "SPOTTER" header renders correctly
- All 4 body category cards visible: Upper Body, Lower Body, Full Body, Yoga
- Cards have staggered entrance animation
- Each card shows correct icon, title, and subtitle
- `buttonTap()` haptic fires on card tap

### 2.3 Exercise Selection Sheet

- Tapping each category opens the bottom sheet with correct exercises:
  - **Upper Body** (10): Bicep Curl, Push Up, Lateral Raise, Front Raise, Overhead Press, Cobra Wings, Overarm Reach, Hammer Curl, Shoulder Press, Tricep Dip
  - **Lower Body** (10): Squat, Sumo Squat, Lunge, Side Lunge, Glute Bridge, Hip Abduction, Leg Raise, Wall Sit, Deadlift, Calf Raise
  - **Full Body** (7): Jumping Jack, Knee Raise, Sit Up, V-Up, Plank, High Knees, Mountain Climber
  - **Yoga** (2): Downward Dog, Warrior II
- Radio-button selection works (only one exercise at a time)
- "Lock in & pick your coach" button enabled after selection

### 2.4 Coach Selection Sheet

- Two coach cards appear: Coach Bennett ("The Good Coach") and Coach Fletcher ("The Drill Sergeant")
- Each shows correct image, name, tagline, and accent color (green vs red)
- "Let's go" button navigates to `TrainerSessionView`
- Haptic feedback on each button tap

---

## 3. Workout Ready Flow (Pre-Exercise)

### 3.1 Positioning Phase

- "Get into position" instruction displayed
- Exercise-specific setup instruction shown
- For **side-view exercises** (Lunge, Glute Bridge, Leg Raise, Wall Sit, Deadlift, Calf Raise, Front Raise, Tricep Dip, Sit Up, V-Up, Plank, Mountain Climber, Downward Dog): "Side View" badge appears
- Body visibility progress bar (0-100%) updates in real-time
- Missing joints listed by name if not all visible

### 3.2 Ready Check (Gesture Detection)

- Once body is visible, "Are you ready?" prompt appears
- Thumbs up/down gesture indicators shown
- **Coach Bennett** message: "Alright! Are you ready to crush this? Give me a thumbs up!"
- **Coach Fletcher** message: "Are you ready or are you just standing there? THUMBS UP!"
- **Thumbs up** detected -> advances to countdown
- **Thumbs down** detected -> personality-adapted "no rush" message -> 3s wait -> re-asks

### 3.3 Countdown

- 3-2-1 numbers displayed in large 72pt font
- `repTick()` haptic fires on each count
- Coach personality message shown ("Here we go!" / "No backing out now!")
- `successRipple()` haptic fires when exercise becomes active (ascending 3-beat crescendo)

---

## 4. Exercise-by-Exercise Testing

For **every exercise**, verify the following checklist. I have grouped exercises by their unique characteristics.

### Key for Each Exercise Test

- **Rep detection**: Perform 5+ reps at varying speeds. Verify rep counter increments correctly.
- **Good rep**: Perform with correct form (hit quality target angle). Form score should be A/B.
- **Bad rep**: Deliberately use poor form. Form feedback should fire with correct message.
- **Angles overlay**: Verify angle arcs appear at correct joints with degree readout.
- **Camera position**: Verify the app requests the correct camera orientation.
- **Skeleton overlay**: Body skeleton drawn with white bones and joints.

---

### 4.1 LOWER BODY EXERCISES

#### Squats (front camera)

- **Rep counted** when knee goes below 100 deg (down) then back above 160 deg (up)
- **Good rep**: Knee reaches 90 deg or below -> form score A
- **Bad rep - shallow depth**: Keep knee above 90 deg during down -> cue: *"Try to go a bit deeper"* (Bennett) / *"Get your ass DOWN!"* (Fletcher)
- **Bad rep - rounded back**: Hip angle below 65 deg -> cue: *"Keep your chest up"* (Bennett) / *"Stop hunching like a shrimp!"* (Fletcher)
- **Knee valgus**: Let knees cave inward (ratio > 0.15) -> cue: *"Push your knees out"* / *"Knees caving in like a cheap tent!"*
- **Heel rise**: Come up on toes -> cue: *"Keep heels flat"* / *"You're not doing calf raises!"*
- **Tempo check**: Rep faster than 1.5s or slower than 4.0s -> tempo penalty on form score
- **Min rep duration**: Reps faster than 0.8s should not count
- Both knee angles tracked (`.both` side resolution)

#### Sumo Squats (front camera)

- Down threshold: knee < 95 deg, Up threshold: knee > 160 deg
- **Good rep**: Knee reaches 85 deg or below
- **Shallow depth**: Knee > 85 deg during down -> *"Go wider and deeper"*
- **Upright torso**: Hip < 70 deg -> *"Keep torso upright"*
- **Knee valgus**: Stricter threshold (0.12) compared to regular squat
- Tempo: 1.5-4.0s

#### Lunges (side camera)

- Uses `.bestAvailable` side resolution for front knee
- Down: frontKnee < 100 deg, Up: frontKnee > 155 deg
- **Good rep**: frontKnee reaches 90 deg
- **Depth feedback**: frontKnee > 90 deg during down -> *"Try to go deeper"*
- **Torso feedback**: hip < 75 deg during down -> *"Keep torso upright"*
- Min rep duration: 1.0s (longer than default 0.5s)
- Tempo: 1.5-4.0s

#### Side Lunges (front camera)

- Primary: kneeAngle (`.bestAvailable`), Secondary: trailingKneeAngle (`.both`)
- Down: knee < 105 deg, Up: knee > 155 deg
- **Good rep**: Knee reaches 90 deg
- **Trailing leg**: trailingKnee < 160 deg -> *"Keep trailing leg straight"*
- **Shoulder level**: Positional check with threshold 0.04

#### Glute Bridge (side camera) -- INVERTED PHASES

- **Phase logic is inverted**: "down" = hips UP (hip > 160 deg), "up" = hips down (hip < 130 deg)
- **Good rep**: Hip reaches 170 deg or above (`qualityTargetIsMinimum: true`)
- **Bridge height**: hip < 170 deg during down -> *"Push those hips higher!"*
- **Knee angle**: knee outside 75-105 deg range -> *"Keep knees at 90 degrees"*
- Tempo: 1.0-3.0s

#### Hip Abduction Standing (front camera)

- Primary: legAbductionAngle (ankle_left -> hip_center -> ankle_right, `.both`)
- Down: legAbduction > 25 deg, Up: legAbduction < 12 deg
- **Good rep**: legAbduction reaches 35 deg or above
- **Range feedback**: legAbduction < 35 deg during down -> *"Lift leg higher!"*
- Shoulder level positional check (threshold 0.04)

#### Leg Raises (side camera)

- Down: hipFlexion < 110 deg, Up: hipFlexion > 160 deg
- **Good rep**: hipFlexion reaches 95 deg or below
- **Bent legs**: knee < 165 deg -> *"Keep legs straight"*
- **Height**: hipFlexion > 95 deg during down -> *"Raise legs higher!"*
- **Momentum**: hipFlexion < 80 deg -> *"Control the movement"*

#### Wall Sit (side camera) -- ISOMETRIC

- Hold timer displayed (not rep counter)
- Down: knee < 100 deg, Up: knee > 150 deg
- **Quality**: Knee should be at 90 deg
- **Depth feedback**: knee > 90 deg always -> *"Sit lower!"*
- **Back feedback**: hip < 80 deg always -> *"Press back flat against wall"*
- `holdDuration` accumulates while in position; `repCount = Int(holdDuration)`

#### Deadlift (side camera)

- Down: hip < 100 deg, Up: hip > 165 deg
- **Good rep**: hip reaches 90 deg
- **Back rounding** (CRITICAL severity): hip < 70 deg -> *"Keep that back straight!"* / *"Back rounding like a scared cat!"*
- **Lockout**: hip < 170 deg during up phase -> *"Lock out your hips at the top!"*
- **Knee bend**: knee < 140 deg during down -> *"Bend at the hips, not the knees"* / *"This isn't a squat"*
- Tempo: 2.0-5.0s (slowest exercise)

#### Calf Raises (side camera)

- Very narrow threshold band: Down < 165 deg, Up > 170 deg (only 5 deg difference)
- **Good rep**: knee reaches 155 deg
- Verify the narrow band doesn't cause false positive/negative reps
- Tempo: 0.8-2.5s

---

### 4.2 UPPER BODY EXERCISES

#### Bicep Curls (front camera)

- Down: elbow < 55 deg, Up: elbow > 150 deg
- **Good rep**: elbow reaches 40 deg or below
- **Partial range**: elbow > 40 deg during down -> *"Squeeze at the top!"*
- **Swinging**: shoulder > 30 deg -> *"Keep elbows pinned!"* / *"Stop swinging!"*
- **Not extending**: elbow < 150 deg during up -> *"Fully extend your arms"*
- Both arms tracked (`.both`)
- Tempo: 1.0-3.0s

#### Push Ups (front camera)

- Down: elbow < 100 deg, Up: elbow > 155 deg
- **Good rep**: elbow reaches 85 deg
- **Shallow depth**: elbow > 85 deg during down -> *"Go lower!"*
- **Body line**: bodyLine angle (shoulder->hip->ankle) outside 160-180 deg -> *"Keep body in a straight line"*
- **Hip sag** (CRITICAL): bodyLine < 155 deg -> *"Hips are dropping!"* / *"Sagging like a wet noodle!"*
- **Hip pike**: bodyLine > 185 deg -> *"Don't pike your hips!"*
- Tempo: 1.5-4.0s

#### Lateral Raises (front camera)

- Down: shoulderAbduction > 75 deg, Up: shoulderAbduction < 30 deg
- **Good rep**: shoulderAbduction reaches 85 deg or above
- **Height**: shoulderAbduction < 85 deg during down -> *"Raise to shoulder height"*
- **Bent arms**: elbow < 155 deg -> *"Keep arms straight"*
- **Too high**: shoulderAbduction > 100 deg -> *"Don't raise past shoulder height"*
- Both arms tracked

#### Front Raises (side camera)

- Down: shoulderFlexion > 75 deg, Up: shoulderFlexion < 30 deg
- **Good rep**: shoulderFlexion reaches 85 deg
- **Height feedback**: shoulderFlexion < 85 deg during down -> *"Raise to shoulder height!"*
- **Bent elbow**: elbow < 155 deg -> *"Keep arms straight"*
- **Body sway**: hip < 165 deg -> *"Don't sway backwards"*

#### Overhead Dumbbell Press (front camera)

- Down: elbow > 155 deg, Up: elbow < 95 deg
- **Good rep**: elbow reaches 170 deg or above
- **Lockout**: elbow < 170 deg during down -> *"Lock out at the top!"*
- **Elbow position**: shoulderAbduction < 60 deg -> *"Keep elbows out to the side"*
- Both arms tracked

#### Cobra Wings (front camera)

- Down: shoulder > 80 deg, Up: shoulder < 40 deg
- **Good rep**: shoulder reaches 90 deg or above
- Ideal: shoulder 95 deg, elbow 90 deg

#### Overarm Reach Bilateral (front camera)

- Down: shoulderFlexion > 150 deg, Up: shoulderFlexion < 40 deg
- **Good rep**: shoulderFlexion reaches 165 deg or above
- Ideal: 170 deg shoulder, 170 deg elbow (arms straight overhead)

#### Hammer Curls (front camera)

- Down: elbow < 50 deg (tighter than bicep curl's 55), Up: elbow > 155 deg
- **Good rep**: elbow reaches 40 deg
- Same form rules as bicep curls (swinging, full extension, squeeze)

#### Shoulder Press (front camera)

- Down: shoulder > 160 deg, Up: shoulder < 90 deg
- **Good rep**: shoulder reaches 170 deg or above

#### Tricep Dips (side camera)

- Down: elbow < 90 deg, Up: elbow > 160 deg
- **Good rep**: elbow reaches 85 deg
- Uses `.bestAvailable` side resolution

---

### 4.3 FULL BODY EXERCISES

#### Jumping Jacks (front camera) -- FASTEST EXERCISE

- Down: armRaise > 140 deg, Up: armRaise < 40 deg
- **Good rep**: armRaise reaches 160 deg or above
- Secondary: legSpreadAngle tracked but not primary
- **Min rep duration**: 0.3s (very fast)
- Tempo: 0.5-2.0s
- Verify rapid reps are counted accurately at high speed

#### Knee Raises (front camera)

- Down: hipFlexion < 100 deg, Up: hipFlexion > 150 deg
- **Good rep**: hipFlexion reaches 80 deg
- Tempo: 0.5-2.0s

#### Sit Ups (side camera)

- Down: torso < 90 deg, Up: torso > 140 deg
- **Good rep**: torso reaches 70 deg
- Ideal: 65 deg

#### V-Ups (side camera)

- Down: hipFlexion < 100 deg, Up: hipFlexion > 155 deg
- **Good rep**: hipFlexion reaches 70 deg
- Knee straightness check: knee > 160 deg

#### Plank (side camera) -- ISOMETRIC

- Hold timer displayed
- Down: bodyLine > 160 deg, Up: bodyLine < 145 deg
- **Quality**: bodyLine should reach 175 deg
- **Hip sag** (CRITICAL): bodyLine < 165 deg -> *"Lift your hips!"* / *"Hips dropping!"*
- **Pike**: bodyLine > 180 deg -> *"Flatten your back!"* / *"Not doing downward dog!"*
- Form rules active during ALL phases (always checking)

#### High Knees (front camera)

- Min rep duration: 0.2s (very fast)
- Tempo: 0.3-1.5s
- Quality target: 90 deg

#### Mountain Climbers (side camera)

- Min rep duration: 0.2s
- Tempo: 0.3-1.5s
- Quality target: 80 deg

---

### 4.4 YOGA -- ISOMETRIC

#### Downward Dog (side camera)

- Down: hip < 100 deg, Up: hip > 140 deg
- Quality target: 70 deg (must go below)
- **Hip height**: hip > 90 deg always -> *"Push hips higher!"*
- **Leg straightness**: knee < 165 deg always -> *"Straighten your legs"*
- **Arm extension**: shoulder < 165 deg always -> *"Extend arms fully"*
- Hold timer accumulates

#### Warrior II (front camera)

- Down: frontKnee < 110 deg, Up: frontKnee > 150 deg
- Quality target: 95 deg
- Hold timer displayed

---

## 5. Form Score System

### 5.1 Score Calculation

- Score starts at 100 for each rep
- **ROM penalty** (max 40): Verify deduction increases as angle deviates from ideal
- **Tempo penalty** (max 30): Too fast (rep < lower tempo bound) gets `((bound - duration) / 0.5) * 15` penalty; too slow gets `(duration - upperBound) * 10`
- **Feedback penalty** (max 30): Each form violation during a rep costs 10 points
- Score cannot go below 0

### 5.2 Grade Display

- **A** (90-100): Green badge -- perform a textbook rep
- **B** (80-89): Accent color badge -- slightly off ideal
- **C** (70-79): Accent color badge
- **D** (60-69): Warning color badge -- multiple issues
- **F** (0-59): Red/danger badge -- severe form breakdown
- Letter grade displayed in HUD after each rep

### 5.3 Reproducible Score Tests

- **Perfect squat** (knee to 90 deg, 2.5s tempo, no form violations) -> expect A
- **Shallow fast squat** (knee to 110 deg, 1.0s tempo) -> expect D or F (ROM + tempo penalties)
- **Good form slow squat** (knee to 90 deg, 5.0s tempo) -> expect B or C (tempo penalty only)
- **Good depth with swinging** (correct angles but form violation) -> expect B (feedback penalty)

---

## 6. Rep Counting Engine (UniversalRepCounter)

### 6.1 State Machine

- Phase cycle: `idle` -> `down` -> `up` -> idle (rep counted at down->up transition)
- Phase label displayed correctly in HUD
- EMA smoothing (alpha 0.4) prevents jittery angle readings from causing false transitions
- Hysteresis: 2 consecutive frames required before phase change

### 6.2 Direction Detection

- Exercises where `downIsDecreasing` = true (squats, curls, etc.): angle decreases to enter "down"
- Exercises where `downIsDecreasing` = false (glute bridge, lateral raises): angle increases to enter "down"
- Verify each exercise uses the correct direction

### 6.3 Isometric Mode

- Plank, Wall Sit, Downward Dog, Warrior II all display hold timer (not rep count)
- Timer shows circular progress ring with seconds
- `holdDuration` accumulates only while angle is within threshold
- Timer pauses/resets if user breaks position

### 6.4 Quality Cue Cooldown

- Quality cues have 8.0s cooldown -- trigger a cue, verify it doesn't repeat for 8 seconds

---

## 7. FormFeedbackEngine

### 7.1 Evaluation Priority (verify short-circuit)

- **Body position** fires first: Hold camera too close (< 4 joints visible) -> "Move further from camera"
- **Joint visibility** fires second: Cover one required joint -> names specific missing joint
- **Form rules** fire third: Only ONE rule per frame (first match wins via `break`)
- **Positional checks** fire fourth: Only if no form rule fired
- **Bilateral asymmetry** fires last: Only if nothing else fired

### 7.2 Cooldowns

- Global cooldown: 3.0s between any two feedback messages
- Asymmetry cooldown: 8.0s
- Individual rule cooldowns vary (8s, 10s, 12s) -- verify each

### 7.3 Bilateral Asymmetry

- For `.both` exercises (curls, squats): Create > 15 deg difference between left and right side
- Should trigger asymmetry feedback after 8s cooldown
- Should NOT trigger if another feedback fired first

### 7.4 Personality Switching

- Every form cue has two variants. Verify:
  - Coach Bennett shows supportive messages (e.g., *"Try to go a bit deeper"*)
  - Coach Fletcher shows aggressive messages (e.g., *"Get your ass DOWN!"*)
- Test at least 3 exercises with each coach to confirm personality routing

---

## 8. Coaching Systems

### 8.1 Motivation Engine (Fatigue Detection)

- After 4+ reps, deliberately slow down (40%+ slower than first 3 reps) -> motivation message should appear
- Message displays as large 32pt glowing text with spring animation
- `warningPulse()` haptic fires with motivation
- 15-second cooldown between motivational messages
- Message auto-dismisses after 3.5 seconds
- With high facial exertion (visibly straining), threshold drops to 24% -- motivation triggers sooner

### 8.2 Exertion Analyzer

- Effort badge visible in HUD: "Effort: XX%"
- Color coding: Green (< 40%), Amber (40-70%), Red (> 70%)
- Furrowing brows, squinting, clenching jaw should increase score
- Relaxed face should show low score
- Fatigue level accumulates over time when effort > 0.4

### 8.3 Voice Coach (Placeholder)

- VoiceCoachManager methods are called but are currently no-ops
- Verify no crashes when voice methods are invoked

---

## 9. Visual Overlay System

### 9.1 Skeleton Overlay

- White bones (5pt) connecting correct joint pairs
- White dot joints (5pt radius)
- Hand skeleton with thinner bones (2.5pt), smaller joints (3pt), larger fingertips (4pt) with glow

### 9.2 Angle Arcs

- Angle arcs drawn at vertex of each tracked angle
- Degree readout label visible at each arc
- Normal angles: amber/warning color
- Violated angles (form rule triggered): red color
- Violated joints enlarged (7pt) with red glow

### 9.3 Body Visibility Banner

- Slides in when required joints not visible
- Pulsing walk icon
- "ADJUST POSITION" header
- Dynamic message naming missing joints
- Circular progress ring with visibility percentage

### 9.4 HUD Elements

- Top-left: Workout title (uppercase, accent color) + "Side View" badge if applicable
- Top-right: Rep counter (96pt number with phase label) OR hold timer (circular ring)
- Bottom: Coach cue banner (capsule pill), form score badge, effort badge
- Glow border pulsing amber around screen edges

---

## 10. Edge Cases and Stress Tests

### 10.1 Camera and Visibility

- Walk partially out of frame -> body visibility banner appears with correct missing joints
- Walk completely out -> "Move further from camera" when < 4 joints
- Re-enter frame -> tracking resumes, rep count preserved
- Poor lighting -> verify graceful degradation (no crashes)

### 10.2 Rapid Movement

- Perform jumping jacks at max speed (0.3s/rep) -> verify counter handles rapid reps
- Perform high knees at max speed (0.2s min duration) -> no double-counting
- Quick direction changes shouldn't trigger false reps

### 10.3 Isometric Hold Edge Cases

- Hold plank, briefly break form, re-enter -> timer should pause and resume
- Hold wall sit with drifting angle at threshold boundary -> verify no rapid start/stop

### 10.4 Transition Tests

- Start squat (front cam), exit, select lunge (side cam) -> camera position guidance correct
- Switch from rep-based exercise to isometric -> HUD correctly swaps from rep counter to timer
- Select new exercise -> rep counter resets to 0

### 10.5 Side Resolution

- `.both` exercises: Partially occlude one side -> verify other side still tracks
- `.bestAvailable` exercises: Block right side -> verify fallback to left
- `.left` / `.right` only exercises: Verify only that side tracked

---

## 11. Haptic Feedback Verification


| Trigger                         | Expected Haptic                                | How to Test                 |
| ------------------------------- | ---------------------------------------------- | --------------------------- |
| Tap any button on home/sheets   | Soft `buttonTap()` (barely noticeable)         | Navigate through all sheets |
| Each countdown number (3, 2, 1) | Sharp `repTick()` (crisp click)                | Start any exercise          |
| Exercise becomes active         | `successRipple()` (3-beat ascending crescendo) | Complete countdown          |
| Motivation message fires        | `warningPulse()` (double-knock)                | Slow down after 4+ reps     |


---

## 12. Coach Personality End-to-End

### 12.1 Coach Bennett (Good Coach) Path

- Select any exercise -> pick Coach Bennett
- Ready prompt: supportive tone
- Countdown: "Here we go!"
- Form feedback: encouraging corrections
- Motivation (if fatigue): uplifting phrases from 12-phrase pool

### 12.2 Coach Fletcher (Drill Sergeant) Path

- Select same exercise -> pick Coach Fletcher
- Ready prompt: aggressive tone
- Countdown: "No backing out now!"
- Form feedback: harsh/funny corrections (e.g., *"Get your ass DOWN!"*, *"Sagging like a wet noodle!"*)
- Motivation (if fatigue): aggressive phrases from 16-phrase pool

### 12.3 Thumbs Down Flow (Both Coaches)

- At ready check, give thumbs down
- Bennett: "No rush! Take your time." -> 3s -> re-asks
- Fletcher: "Scared already? Fine, take a moment." -> 3s -> re-asks with retry message

