---
name: Spotter Context Document
overview: Create an exhaustive context document for the Spotter/Virtual Trainer app that covers the complete project history (with verbatim emotions), the full tech stack, design system, all 29 exercises with biomechanics, coaching personalities, form feedback rules, vision pipeline, and every architectural decision -- designed to give Claude on web full context without access to the codebase.
todos:
  - id: history-section
    content: "Write Section 1: Project History & Founder Journey with emotional verbatim voice"
    status: completed
  - id: tech-stack
    content: "Write Section 2: Tech Stack & Dependencies with exact versions"
    status: completed
  - id: architecture
    content: "Write Section 3: Project Architecture & File Structure"
    status: completed
  - id: design-system
    content: "Write Section 4: Design System 'No-Fluff Noir' with all tokens"
    status: completed
  - id: vision-pipeline
    content: "Write Section 5: Vision Pipeline technical depth"
    status: completed
  - id: exercise-library
    content: "Write Section 6: All 29 exercises with complete biomechanics, thresholds, form rules, and feedback text"
    status: completed
  - id: rep-counting
    content: "Write Section 7: Rep Counting System"
    status: completed
  - id: coaching-system
    content: "Write Section 8: Coaching System (form feedback, motivation, exertion, ready coordinator)"
    status: completed
  - id: coach-personalities
    content: "Write Section 9: Coach Personalities with all phrase pools"
    status: completed
  - id: ui-components
    content: "Write Section 10-11: UI Components and Home Dashboard"
    status: completed
  - id: limitations-decisions
    content: "Write Sections 12-13: Known Limitations & Architectural Decisions"
    status: completed
isProject: false
---

# Spotter / Virtual Trainer -- Comprehensive Context Document

## What This Plan Produces

A single, extremely detailed markdown document (likely 2000+ lines) that serves as a **complete knowledge transfer** for Claude on the web. It will contain everything needed to understand, discuss, and extend this project without access to the codebase or past conversations.

The document will be created at: `SPOTTER_CONTEXT_DOC.md` in the project root.

## Document Structure (Sections)

### 1. Project History & Founder Journey (Emotional, Verbatim)

The raw, unfiltered story of building Spotter -- written in the founder's voice. Covers:

- The original idea: home workouts without guidance, the gap in the market
- Initial ignorance: "didn't know what Cursor was, what an IDE is, what Xcode even does"
- Considered Rork ($100), learned it's inflexible, decided to get hands dirty
- Learning Cursor, understanding GitHub, downloading Xcode ("setting up Xcode was a task man!")
- Corporate laptop struggles: proxies, admin restrictions
- **V1: Apple Vision framework** -- built entire Swift/SwiftUI app, realized limitations (inaccurate skeletons, joints not detected, no gesture support)
- **V2: QuickPose SDK** -- tried integrating, paid intent, compiler failures, downgraded Xcode + Swift, contacted QuickPose team, got told "unsolvable right now"
- Discovery: QuickPose is built on **MediaPipe** -- the "aha" moment
- **V3/V4 (current): Google MediaPipe** -- forked repo, rewrote entire brain, Ruby install issues, moved away from Xcode-only compilation
- Phone testing blocked: USB data transfer blocked by IT, discovered camera doesn't work in simulator, workaround with Mac camera in iPad format
- ElevenLabs voice integration: coded but blocked by corporate proxies, deferred to TestFlight
- **Trained first ML model in CreateML** (WorkoutClassifier)
- Apple Developer Program $99 fee pending for TestFlight deployment
- Gemini as software architect: the full Gemini conversation guided architecture decisions

### 2. Tech Stack & Dependencies

- **Platform**: iOS (Podfile minimum iOS 16, project targets iOS 26.2+)
- **Language**: Swift 5 with strict concurrency (`@MainActor` isolation)
- **UI Framework**: SwiftUI (dark-mode-first, `ENABLE_PREVIEWS`)
- **Vision/AI**: Google MediaPipe Tasks Vision 0.10.33 via CocoaPods
  - `MediaPipeTasksVision` XCFramework
  - `MediaPipeTasksCommon` XCFramework
- **Runtime ML Models** (downloaded via `download_models.sh`, gitignored):
  - `pose_landmarker_full.task` -- 33 body landmarks + 3D world coords
  - `hand_landmarker.task` -- 21 hand landmarks per hand
  - `gesture_recognizer.task` (optional) -- ML-based gesture classification
  - `face_landmarker.task` (optional) -- 478 face landmarks + 52 blendshapes
- **Voice (future)**: ElevenLabs TTS API (service written, API key present, blocked by proxy)
- **Haptics**: CoreHaptics with UIFeedbackGenerator fallback
- **Build System**: CocoaPods 1.16.2, Xcode workspace
- **ML Training**: CreateML project (`WorkoutClassifier.mlproj`)
- **Reference project**: FitCount-main (QuickPose-based, kept for reference)

### 3. Project Architecture & File Structure

Complete directory tree with every Swift file's role, organized by module:

- `Camera/` -- AVFoundation capture pipeline
- `Vision/` -- MediaPipe wrappers (Pose, Hand, Face, Angle math)
- `Models/` -- Exercise library, workout data, coach personalities
- `RepCounting/` -- Protocol + universal + squat-specific counters
- `Coaching/` -- Form feedback, motivation, exertion, haptics, voice, ready flow
- `UI/` -- Session view, overlay, dashboard, design gallery, visibility banner
- `DesignSystem/` -- Theme colors, typography, button styles, liquid glass
- `Services/` -- ElevenLabs integration

### 4. Design System: "No-Fluff Noir"

Every design token verbatim from `Theme.swift`:

- Color palette: background (5% white), surface (12%), surfaceRaised (17%), textPrimary (95% bone white), textSecondary (52%), textTertiary (32%), accent (Warm Amber RGB 1.0/0.69/0.0), danger, positive, divider, scrim
- Typography: RepCounterStyle (SF Rounded .black + tabular), HeaderStyle (heavy, -0.6 tracking, uppercase), SubheaderStyle, BodyStyle, CaptionStyle
- Button styles: PrimaryCTA (full-width 56pt, accent fill), SecondaryCTA (ghost/outline)
- Spacing: 8pt grid (xxxs=2 through xxxl=64)
- Corner radii: xs=4 through pill=999
- Motion: snappy (0.22s), smooth (0.35s easeInOut), spring (stiffness 280), bounce (response 0.4)
- Haptic waveforms: repTick, buttonTap, warningPulse (double-knock), successRipple (ascending 3-beat crescendo with rumble)

### 5. Vision Pipeline (Complete Technical Depth)

- **PoseEstimator**: MediaPipe PoseLandmarker, live stream mode, processes CMSampleBuffer, publishes `bodyJoints` (2D) + `worldJoints` (3D SIMD3), 33 landmarks
- **JointName enum**: All 33 MediaPipe indices + 2 synthetic (neck=100, root=101), bone pair definitions for skeleton rendering
- **AngleCalculator**: 2D (`atan2` vectors) and 3D (`simd_dot` / `acos`) angle computation, exercise-driven angle definitions, bilateral angle pairs, positional checks (knee valgus, heel rise, joint-above-joint, joint-aligned-X, shoulder level)
- **HandGestureDetector**: GestureRecognizer (ML-based) with HandLandmarker fallback, evidence accumulation (3 consecutive frames), 21-point hand skeleton, bone pair topology, supports 2 hands simultaneously
- **FaceLandmarkerService**: 478 facial landmarks, 52 ARKit-compatible blendshapes, feeds ExertionAnalyzer
- **BodyVisibilityChecker**: Per-exercise required joint validation

### 6. Exercise Library (All 29 Exercises, Complete Biomechanics)

For each exercise, the document will include:

- Display name, category, movement type (repetition vs isometric)
- Camera position (front vs side) with setup instruction
- Required joints for visibility
- All angle definitions (which joints, measurement side)
- Primary angle key for rep counting
- Down/up phase thresholds (exact degree values)
- Quality target and whether it's a minimum or maximum
- Every form rule with: id, angle key, min/max angle thresholds, active phases, Good Coach feedback text, Drill Sergeant feedback text, severity, cooldown
- Every positional check (knee valgus thresholds, heel rise, shoulder level, etc.)
- Target muscles
- Min rep duration, ideal angles, tempo range

**Exercises by category:**

- **Lower Body (10)**: Squats, Sumo Squats, Lunges, Side Lunges, Glute Bridge, Hip Abduction Standing, Leg Raises, Wall Sit, Deadlift, Calf Raises
- **Upper Body (10)**: Bicep Curls, Push Ups, Lateral Raises, Front Raises, Overhead Dumbbell Press, Cobra Wings, Overarm Reach Bilateral, Hammer Curls, Shoulder Press, Tricep Dips
- **Full Body (7)**: Jumping Jacks, Knee Raises Bilateral, Sit Ups, V-Ups, Plank, High Knees, Mountain Climbers
- **Yoga (2)**: Downward Dog, Warrior II

### 7. Rep Counting System

- **RepCounter protocol**: `process(angles:)` -> `RepCounterOutput` (repCount, phase, cues, holdDuration, isHolding, formScore)
- **RepPhase state machine**: idle -> down -> up -> idle
- **UniversalRepCounter**: Data-driven from ExerciseDefinition, EMA smoothing (alpha=0.4), hysteresis (2 consecutive frames), min rep duration, tempo tracking, form score calculation (ROM penalty up to 40, tempo penalty up to 30, feedback penalty 10/cue capped at 30)
- **SquatRepCounter**: Legacy hardcoded version (up=150, down=120, depth=110)
- **FormScore**: 0-100 composite, letter grades A-F, component breakdowns (ROM, tempo, feedback)
- **Isometric mode**: Hold duration tracking with progress ring UI

### 8. Coaching System

- **FormFeedbackEngine**: Hierarchical checks (body position -> joint visibility -> form rules -> positional checks -> bilateral asymmetry), per-rule cooldowns, global 3s cooldown, asymmetry threshold 15 degrees
- **MotivationEngine**: Rep tempo decay detection (baseline from first 3 reps, 40% decay threshold, adjusted by face effort), 12 good phrases + 16 drill phrases, 15s cooldown, 3.5s display, integrates voice + haptics
- **ExertionAnalyzer**: Blendshape-based effort scoring (brow furrow 20%, eye squint 15%, jaw clench 12%, mouth tension 10%/8%), EMA smoothed (alpha=0.25), fatigue model (accumulation when effort>0.4, blink rate tracking)
- **WorkoutReadyCoordinator**: State machine (positioning -> askingReady -> countdown/waitingToRetry -> exerciseActive), thumbs up/down gesture triggers, personality-specific messages for every state transition
- **VoiceCoachManager**: Currently a placeholder/stub, designed for future ElevenLabs integration
- **HapticsEngine**: CoreHaptics with authored waveforms, 4 patterns (repTick, buttonTap, warningPulse, successRipple)

### 9. Coach Personalities

- **Coach Bennett ("The Good Coach")**: warm, supportive, encouraging. Accent color: positive green. Example: "Try to go a bit deeper -- aim for thighs parallel!"
- **Coach Fletcher ("The Drill Sergeant")**: brutal, condescending, aggressive. Accent color: danger red. Example: "That's a half rep at best. Get your ass DOWN!"
- Stored via `@AppStorage`, affects: form feedback text, motivation phrases, ready-check messages, accent colors, coach images

### 10. UI Components (Camera Session View)

Complete breakdown of the `TrainerSessionView` layers:

1. Camera feed (edge-to-edge)
2. Skeleton overlay (joints + bones + angle arcs + violated joints in red)
3. Active-session glow border (Warm Amber, pulsing)
4. HUD overlay: workout title, rep counter badge (with digit-roll animation), phase label
5. Isometric hold timer with progress ring
6. Ready-check overlay (positioning guide, gesture indicator, visibility progress bar, coach message bubbles)
7. Motivation overlay (large bold text with triple shadow glow, spring animation)
8. Coach cue banner (capsule, severity-colored)
9. Debug angle badge, form score badge, effort badge
10. Voice error banner
11. Side-view camera position guide

### 11. Home Dashboard

Body category selection (Upper Body, Lower Body, Full Body, Yoga), exercise picker bottom sheet, workout plans (mock data: Leg Day, Upper Body Pump, Full Body Quickie), coach personality selector

### 12. Known Limitations & Future Work

- Voice coaching is stub-only (ElevenLabs blocked by proxy)
- No auth/login system yet (UserProfile is hardcoded)
- No workout history persistence
- No demo videos for exercises
- Camera defaults to front (some exercises recommend side view)
- Push-ups kept on front camera as pragmatic compromise
- No onboarding/calibration flow
- CreateML model trained but not integrated
- TestFlight deployment pending $99 Apple Developer fee

### 13. Key Architectural Decisions (from Gemini + Development)

- MediaPipe over Apple Vision (accuracy, 3D landmarks, gesture recognition)
- Data-driven exercise definitions over per-exercise hardcoded counters
- 3D world landmarks preferred with 2D fallback
- "Effort" heuristics over "emotion detection" (face too small at workout distance)
- EMA smoothing + hysteresis for noise reduction
- Single accent color (Warm Amber) over multi-color palette
- CocoaPods over SPM (MediaPipe not available on SPM)

## Implementation Approach

The document will be written as a single comprehensive markdown file. It will be structured for maximum utility as a context input to Claude on web -- with clear section headers, code snippets where critical (e.g., exact threshold values), and the founder's story written with preserved emotional authenticity.