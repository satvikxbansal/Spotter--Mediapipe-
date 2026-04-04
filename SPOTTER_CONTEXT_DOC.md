# SPOTTER -- Virtual Trainer: Complete Project Context Document

> This document is a comprehensive knowledge transfer for the Spotter/Virtual Trainer iOS application. It contains everything needed to understand, discuss, extend, and contribute to this project without access to the codebase, past Cursor chat history, or prior Gemini conversations. Every threshold, every feedback string, every architectural decision is documented here.

---

## Table of Contents

1. [Project History & Founder Journey](#1-project-history--founder-journey)
2. [Tech Stack & Dependencies](#2-tech-stack--dependencies)
3. [Project Architecture & File Structure](#3-project-architecture--file-structure)
4. [Design System: "No-Fluff Noir"](#4-design-system-no-fluff-noir)
5. [Vision Pipeline](#5-vision-pipeline)
6. [Exercise Library (All 29 Exercises)](#6-exercise-library-all-29-exercises)
7. [Rep Counting System](#7-rep-counting-system)
8. [Coaching System](#8-coaching-system)
9. [Coach Personalities](#9-coach-personalities)
10. [UI Components: Camera Session View](#10-ui-components-camera-session-view)
11. [Home Dashboard & Navigation](#11-home-dashboard--navigation)
12. [Known Limitations & Future Work](#12-known-limitations--future-work)
13. [Key Architectural Decisions](#13-key-architectural-decisions)

---

## 1. Project History & Founder Journey

### The Idea

Spotter was born from a simple observation: millions of people want to work out at home but don't have the right resources or guidance to do it properly. Not everyone can afford a personal trainer. Not everyone wants to go to a gym. The idea was to build a virtual trainer -- an iOS app that doesn't just show you workout plans (every app does that), but actually *watches* you work out through the camera, counts your reps, corrects your posture in real-time, and motivates you when it can see you're struggling. A spotter. The kind of friend who stands behind you at the squat rack, except it lives in your phone.

The scope was deliberately narrow from the start: home workouts. Simple weights. Simple props. Bodyweight exercises. Dumbbells. No gym machines, no barbells, no complicated setups. The kind of workout you do in your living room with a yoga mat and a pair of 10-pound dumbbells. Squats, curls, push-ups, planks, lunges -- the fundamentals done right.

### The Starting Point: Zero

When this project started, I didn't know what Cursor was. I didn't know what an IDE is. I didn't know what Xcode even does. I had never written a line of Swift. I'm a product manager by trade, not an engineer. I had an idea, and I had the conviction that AI tools had gotten good enough that someone with zero coding experience could build something real.

My first instinct was to use Rork -- pay it $100 and have it spit out a working app. But I quickly learned about the incapabilities and inflexibility of no-code platforms. They can build a pretty shell, but the moment you need real-time computer vision processing camera frames at 30fps, they fall apart. You can't fake the physics of joint angle calculations. You can't "no-code" a state machine that tracks whether someone's knee has passed 90 degrees.

So I decided to get my hands dirty. I explored Cursor. Learned to navigate it. Learned what GitHub is and why it exists. Downloaded Xcode -- oh man, setting up Xcode was a TASK. The download alone took forever, and then the build issues started. Compiler errors that made no sense. Certificates and provisioning profiles that felt like bureaucratic gatekeeping. And I was doing all of this on a *company laptop*, which meant corporate restrictions at every turn.

### The Corporate Laptop Nightmare

Building an app on a corporate laptop is an exercise in creative problem-solving that nobody warns you about. The IT team had locked down everything. Proxies blocked half the internet. I had to bypass proxies just to install packages (don't tell admin). npm, CocoaPods, Ruby gems -- every dependency manager wanted to reach out to the internet, and the corporate proxy said "absolutely not."

Then came the phone testing disaster. I needed to test the camera functionality on a real device because -- as I painfully discovered -- **the camera does not work in the iOS Simulator**. You can simulate touch, simulate GPS, simulate network conditions, but you cannot simulate a camera feed. So I plugged in my iPhone... and nothing happened. I spent an embarrassingly long time trying to figure out what was wrong with my phone, or my head, or the AI-generated code, only to realize that **the IT team blocks USB ports for data transfer on company laptops**. That was a huge blocker. 

The workaround: I could use the Mac's built-in camera and test in the iPad-format simulator using the Mac camera as a stand-in. It's not ideal -- the Mac camera is stationary and the angle is wrong -- but it let me validate that the pose detection pipeline actually works.

### V1: Apple Vision Framework

Gemini was my software architect from day one. I described the app concept, and Gemini laid out a complete blueprint: use Apple's native Vision framework (`VNDetectHumanBodyPoseRequest`), SwiftUI for the UI, CoreHaptics for tactile feedback, and ElevenLabs for the virtual trainer's voice.

So we built it. An entire iOS app in Swift using Apple's Vision framework. The skeleton detection worked... sort of. But it had serious shortcomings:

- The skeletons were not accurate. Joints would jump around, especially in low light.
- Only 19 body points were detected -- no fingers, no toes, no detailed hand tracking.
- No gesture detection whatsoever. We needed thumbs up/down to control the workout flow.
- No 3D world coordinates. Everything was 2D normalized coordinates, which meant the angle calculations were camera-dependent. Turn slightly and the angles go haywire.
- No face blendshapes for fatigue/exertion detection.

For a basic demo it was fine. But we wanted something advanced enough to monetize. Something that could actually compete with having a real trainer.

### V2: QuickPose SDK

Searching for better pose estimation led us to QuickPose -- a commercial SDK specifically built for fitness apps. It promised accurate pose detection, exercise recognition, and rep counting out of the box. We were excited. We were ready to pay for it if we scaled past 100 users.

But then the compiler issues started. QuickPose's Swift package wouldn't compile in the latest version of Xcode. We downgraded Xcode. We downgraded Swift. We tried every combination of versions. Nothing worked. We reached out to the QuickPose team directly, and they told us this was "unsolvable right now" and they'd "probably upgrade their package soon."

Dead end. Roadblock. Weeks of work, and we were back to square one.

### The MediaPipe Discovery

Then something interesting happened. While digging into how QuickPose actually worked under the hood, we discovered that QuickPose is essentially a wrapper around **Google's MediaPipe**. MediaPipe is the backbone. And MediaPipe is open source. Apache 2.0 licensed. Free. And it's *far* more capable than what QuickPose exposed.

MediaPipe's Pose Landmarker gives you:
- 33 body landmarks (vs. Apple Vision's 19)
- Full 3D world coordinates in meters (camera-independent!)
- Hand landmarks (21 points per hand)
- Gesture recognition (thumbs up, thumbs down, open palm, fist, victory, pointing up)
- Face landmarks (478 points) with 52 ARKit-compatible blendshapes
- Segmentation masks
- All running on-device, no network calls, no API keys

This was the breakthrough moment.

### V3/V4: The MediaPipe Rewrite (Current Version)

We forked a reference repository and rewrote the entire brain of the app using MediaPipe. This is the current codebase -- version 3 or 4, depending on how you count the false starts.

It wasn't smooth. We faced Ruby installation issues (MediaPipe iOS uses CocoaPods, which requires Ruby). Conda environments clashed with system Ruby. CocoaPods versions fought with each other. The Xcode project had to be opened as a `.xcworkspace` (not `.xcodeproj`) or the MediaPipe frameworks wouldn't link. Script sandboxing had to be disabled. XCFramework copy phases were duplicated and had to be cleaned up manually.

But we got through it. And the architecture was built with extensibility in mind -- if MediaPipe adds new features (and they keep doing so), our abstraction layers (`JointName`, `AngleCalculator`, `ExerciseDefinition`) can accommodate them without rewriting the core.

### ElevenLabs Voice & CreateML

We also integrated ElevenLabs for Voice AI -- the idea being that the virtual trainer would actually *speak* to you with a realistic, emotive voice. Not Apple's robotic `AVSpeechSynthesizer`, but a voice that sounds like an actual coach. The `ElevenLabsService.swift` is written and functional, with API key and everything. But we couldn't test it because of the corporate proxies blocking the ElevenLabs API endpoints. So we decided to put voice on hold until we pay the $99 Apple Developer Program fee and can deploy via TestFlight to test on a real device on a non-corporate network.

We also trained our first ML model in CreateML! The `WorkoutClassifier.mlproj` in the repo is a CreateML project that classifies workout movements. It's not integrated into the app yet, but the fact that we went from "what is an IDE" to training a machine learning model is... something.

### The Emotional Truth

This project has been a rollercoaster. There were moments of genuine frustration -- spending hours debugging a USB connection only to find out it's a corporate policy, not a code bug. There were moments of pure elation -- seeing the skeleton overlay track my body for the first time, watching the rep counter increment as I did actual squats in front of my laptop camera. There was the particular flavor of madness that comes from getting a compiler error that says "Module 'MediaPipeTasksVision' not found" when the framework is literally sitting right there in the Pods directory.

I went from being someone who thought "coding an AI app" was something only engineers could do, to someone who can navigate Xcode build settings, read Swift compiler errors, understand what a `CMSampleBuffer` is, and have an intelligent conversation about the trade-offs between 2D and 3D joint angle calculations. Product management gave me the instinct for what to build; AI tools gave me the ability to build it. Neither would have worked alone.

The app isn't finished. It's not on the App Store. But it works. The camera sees you. The AI understands your body. It counts your reps. It corrects your form. It motivates you when you're slowing down. And it does it with personality -- either as a warm, encouraging Coach Bennett or a brutal, trash-talking Coach Fletcher.

That's Spotter.

---

## 2. Tech Stack & Dependencies

### Platform & Language

| Property | Value |
|---|---|
| Platform | iOS |
| Minimum iOS (Podfile) | 16.0 |
| Project deployment target | 26.2+ |
| Language | Swift 5 |
| Concurrency model | Strict (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| UI framework | SwiftUI |
| Dark mode | First-class (`.preferredColorScheme(.dark)`) |

### Core Dependencies

| Dependency | Version | Role |
|---|---|---|
| `MediaPipeTasksVision` | 0.10.33 | Pose/hand/face/gesture detection |
| `MediaPipeTasksCommon` | 0.10.33 | Shared MediaPipe infrastructure |
| CocoaPods | 1.16.2 | Dependency manager |

### Runtime ML Models

These are downloaded via `download_models.sh` into `VirtualTrainer/Models/` and are gitignored (not committed to the repository):

| Model File | Capability |
|---|---|
| `pose_landmarker_full.task` | 33 body landmarks (2D normalized + 3D world coordinates in meters) |
| `hand_landmarker.task` | 21 hand landmarks per hand, up to 2 hands simultaneously |
| `gesture_recognizer.task` | ML-based gesture classification (Thumb_Up, Thumb_Down, Open_Palm, Closed_Fist, Victory, Pointing_Up) -- optional, system falls back to `hand_landmarker.task` with heuristic analysis if absent |
| `face_landmarker.task` | 478 facial landmarks + 52 ARKit-compatible blendshapes -- optional, face features disabled if absent |

### Apple Frameworks Used

- `AVFoundation` -- Camera capture pipeline (`AVCaptureSession`, `AVCaptureVideoDataOutput`)
- `CoreHaptics` -- Authored haptic waveforms (repTick, warningPulse, successRipple)
- `UIKit` -- Fallback haptic generators (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`)
- `simd` -- 3D vector math for world-coordinate angle calculations
- `Combine` -- Reactive data flow (`@Published`, `ObservableObject`)
- `os` -- Structured logging (`Logger`)

### External Services

| Service | Status | Purpose |
|---|---|---|
| ElevenLabs TTS API | Written but untested (blocked by corporate proxy) | Realistic voice coaching |
| Apple Developer Program ($99/yr) | Not yet purchased | TestFlight deployment, real-device testing |

### Build System

- Workspace: `VirtualTrainer.xcworkspace` (MUST use this, not `.xcodeproj`, for CocoaPods linking)
- CocoaPods script phases: "Check Pods Manifest.lock", xcframework copy scripts
- User script sandboxing: DISABLED (`ENABLE_USER_SCRIPT_SANDBOXING = NO`) -- required for CocoaPods
- Model download: `./download_models.sh` must be run before first build

### Other Projects in Repository

| Project | Purpose |
|---|---|
| `FitCount-main/` | Reference app using QuickPose SDK (V2 remnant, kept for reference) |
| `WorkoutClassifier.mlproj` | CreateML project for workout movement classification (trained, not integrated) |

---

## 3. Project Architecture & File Structure

### Directory Tree

```
VirtualTrainer - mediapipe/
├── .gitignore
├── Podfile
├── Podfile.lock
├── download_models.sh
├── SPOTTER_CONTEXT_DOC.md          (this document)
├── VirtualTrainer.xcodeproj/
├── VirtualTrainer.xcworkspace/     (open THIS for builds)
├── Pods/                           (CocoaPods vendor directory)
├── VirtualTrainer/                 (main app source)
│   ├── VirtualTrainerApp.swift     (app entry point)
│   ├── ContentView.swift           (root navigation)
│   ├── .cursorrules                (AI coding guidelines)
│   ├── Assets.xcassets/            (colors, app icon, coach images)
│   ├── VirtualTrainer.entitlements
│   │
│   ├── Camera/
│   │   ├── CameraManager.swift         AVCaptureSession wrapper, frame delivery
│   │   └── CameraPreviewView.swift     UIViewRepresentable for live preview
│   │
│   ├── Vision/
│   │   ├── PoseEstimator.swift         MediaPipe PoseLandmarker, 2D+3D joints
│   │   ├── AngleCalculator.swift       2D/3D angle math, positional checks
│   │   ├── BodyVisibilityChecker.swift Per-exercise joint validation
│   │   ├── HandGestureDetector.swift   GestureRecognizer + fallback
│   │   ├── FaceLandmarkerService.swift 478 landmarks + blendshapes
│   │   └── JointName.swift            33 MediaPipe landmarks + 2 synthetic
│   │
│   ├── Models/
│   │   ├── ExerciseLibrary.swift       All 29 exercise definitions (1807 lines)
│   │   └── WorkoutData.swift           Types, plans, coach personality, cues
│   │
│   ├── RepCounting/
│   │   ├── RepCounterProtocol.swift    Protocol + RepPhase + FormScore
│   │   ├── UniversalRepCounter.swift   Data-driven counter for any exercise
│   │   └── SquatRepCounter.swift       Legacy squat-specific counter
│   │
│   ├── Coaching/
│   │   ├── FormFeedbackEngine.swift    Real-time biomechanical form analyzer
│   │   ├── MotivationEngine.swift      Tempo-decay fatigue detection + phrases
│   │   ├── ExertionAnalyzer.swift      Face blendshape effort scoring
│   │   ├── VoiceCoachManager.swift     Placeholder for ElevenLabs TTS
│   │   ├── HapticsEngine.swift         CoreHaptics waveform library
│   │   └── WorkoutReadyCoordinator.swift Pre-exercise ready-check flow
│   │
│   ├── UI/
│   │   ├── TrainerSessionView.swift    Full workout camera screen (903 lines)
│   │   ├── TrainerOverlayView.swift    Skeleton + angle arcs + violated joints
│   │   ├── HomeDashboardView.swift     Exercise selection, categories, plans
│   │   ├── BodyVisibilityBannerView.swift Visibility warning banner
│   │   └── DesignGalleryView.swift     Design system preview/testing screen
│   │
│   ├── DesignSystem/
│   │   ├── Theme.swift                 Colors, typography, spacing, motion, buttons
│   │   └── LiquidGlass.swift           Glass-morphism effect components
│   │
│   └── Services/
│       └── ElevenLabsService.swift     TTS API client (contains API key!)
│
├── FitCount-main/                  (reference QuickPose project)
└── WorkoutClassifier.mlproj/       (CreateML training project)
```

### Module Responsibilities

| Module | Responsibility |
|---|---|
| **Camera** | Manages `AVCaptureSession`, delivers `CMSampleBuffer` frames to Vision modules, provides `UIViewRepresentable` for SwiftUI live preview |
| **Vision** | Wraps all MediaPipe tasks behind framework-agnostic abstractions (`JointName`, `AngleCalculator`). No other module imports MediaPipe directly. |
| **Models** | Pure data definitions. `ExerciseLibrary` is the central registry of all 29 exercises with their complete biomechanical specifications. `WorkoutData` defines types for workouts, sets, coach personalities, and coach cues. |
| **RepCounting** | State machines that consume angle dictionaries and produce rep counts, phase info, and form scores. The `UniversalRepCounter` is data-driven from `ExerciseDefinition`. |
| **Coaching** | The "intelligence" layer. `FormFeedbackEngine` checks biomechanical rules. `MotivationEngine` detects fatigue from tempo decay. `ExertionAnalyzer` scores facial effort. `WorkoutReadyCoordinator` orchestrates the pre-exercise flow. |
| **UI** | SwiftUI views. `TrainerSessionView` is the main workout screen (camera + skeleton + HUD). `HomeDashboardView` is the exercise selector. |
| **DesignSystem** | Every visual token: colors, fonts, spacing, corner radii, animations, button styles. Nothing is hardcoded in views. |
| **Services** | External API clients (currently only ElevenLabs). |

---

## 4. Design System: "No-Fluff Noir"

The design language is called **"No-Fluff Noir"** -- a brutalist dark palette with a single warm accent color. The aesthetic draws from premium fitness gear: stark, functional, no-nonsense. Everything visible from arm's length during a workout.

### Color Palette

| Token | Value | Description |
|---|---|---|
| `background` | `Color(white: 0.05)` | Near-black. Not pure black -- the 5% white gives OLED screens a hint of materiality so UI elements don't float in a void. |
| `surface` | `Color(white: 0.12)` | Card/sheet surface. Separated from background by ~7% brightness. |
| `surfaceRaised` | `Color(white: 0.17)` | Nested surface (inputs sitting on a card). |
| `textPrimary` | `Color(white: 0.95)` | Bone white. Warm enough to avoid clinical feel, cool enough to avoid yellowing. |
| `textSecondary` | `Color(white: 0.52)` | Muted label text. Quiet but WCAG-legible against surface. |
| `textTertiary` | `Color(white: 0.32)` | Footnotes, timestamps, disabled states. |
| `accent` | `Color(red: 1.0, green: 0.69, blue: 0.0)` | **Warm Amber** -- the only chromatic color in the palette. Trophy gold, forge glow, earned warmth. Not "health app green." |
| `accentMuted` | accent at 20% opacity | Subtle borders, selection highlights, glows. |
| `danger` | `Color(red: 1.0, green: 0.30, blue: 0.26)` | Destructive/error/form-correction red. Used for Coach Fletcher's accent. |
| `positive` | `Color(red: 0.20, green: 0.84, blue: 0.48)` | Positive confirmation green. Used for Coach Bennett's accent. Used sparingly. |
| `divider` | `Color(white: 0.18)` | Hairline dividers between list rows. |
| `scrim` | `Color.black` at 65% opacity | Full-screen overlay tint behind sheets/modals. |

### Typography

All typography uses Apple's San Francisco system font. No custom fonts.

| Style | Font | Weight | Size | Extra |
|---|---|---|---|---|
| `RepCounterStyle` | SF Rounded | `.black` | 80pt (configurable) | `.monospacedDigit()` for tabular layout, `.numericText()` content transition for smooth digit-roll animation |
| `HeaderStyle` | SF Pro | `.heavy` | 28pt (configurable) | `.tracking(-0.6)` negative kerning, `.textCase(.uppercase)` |
| `SubheaderStyle` | SF Pro | `.bold` | 17pt | Sentence case, `textSecondary` color |
| `BodyStyle` | SF Pro | `.medium` | 16pt | `textPrimary` color |
| `CaptionStyle` | SF Pro | `.semibold` | 12pt | `textTertiary` color |

### Button Styles

| Style | Height | Fill | Label | Behavior |
|---|---|---|---|---|
| `PrimaryCTAStyle` | 56pt, full-width | Accent (or danger if `destructive`) | 16pt bold, uppercase, 0.4 tracking, `background` color text | Pressed: 78% opacity, 97% scale, snappy animation |
| `SecondaryCTAStyle` | 50pt, full-width | Transparent | 15pt bold, uppercase, 0.3 tracking, accent color text | 1.5pt accent stroke, pressed: 55% opacity, 97% scale |

### Spacing (8pt Grid)

| Token | Value |
|---|---|
| `xxxs` | 2pt |
| `xxs` | 4pt |
| `xs` | 8pt |
| `sm` | 12pt |
| `md` | 16pt |
| `lg` | 24pt |
| `xl` | 32pt |
| `xxl` | 48pt |
| `xxxl` | 64pt |

### Corner Radii

| Token | Value |
|---|---|
| `xs` | 4pt |
| `sm` | 8pt |
| `md` | 14pt |
| `lg` | 20pt |
| `pill` | 999pt |

### Motion Curves

| Token | Animation | Description |
|---|---|---|
| `snappy` | `.snappy(duration: 0.22)` | Button taps, micro-interactions |
| `smooth` | `.easeInOut(duration: 0.35)` | State transitions, overlays |
| `spring` | `.interpolatingSpring(stiffness: 280, damping: 20)` | Bouncy entrances |
| `bounce` | `.spring(response: 0.4, dampingFraction: 0.6)` | Motivation text pop-in |

### Haptic Waveforms

Four authored haptic patterns using CoreHaptics (with UIFeedbackGenerator fallback for older devices):

**`repTick()`** -- Completed rep. Sharp, authoritative, percussive.
- Single transient event: intensity 1.0, sharpness 0.95
- The tightest "click" the Taptic Engine can produce

**`buttonTap()`** -- Standard button press. Light, crisp, barely there.
- Single transient event: intensity 0.45, sharpness 0.35

**`warningPulse()`** -- Form deviation or camera tracking lost.
- Two rapid transient pulses 120ms apart
- Pulse 1: intensity 0.75, sharpness 0.30
- Pulse 2: intensity 0.90, sharpness 0.40
- Feels like a muffled double-knock -- urgent but not aggressive

**`successRipple()`** -- Set/workout complete. Rising three-beat crescendo.
- Beat 1 (t=0ms): intensity 0.45, sharpness 0.40
- Beat 2 (t=140ms): intensity 0.72, sharpness 0.60
- Beat 3 (t=340ms): intensity 1.0, sharpness 0.90
- Sustained rumble underneath: intensity 0.30, sharpness 0.10, duration 420ms
- The physical equivalent of a finish-line horn

---

## 5. Vision Pipeline

### Overview

The vision system processes live camera frames through four parallel MediaPipe pipelines:

```
CMSampleBuffer (from AVCaptureSession)
    │
    ├──> PoseEstimator ──> bodyJoints (2D) + worldJoints (3D)
    │                         │
    │                         ├──> AngleCalculator ──> angle dictionaries
    │                         ├──> BodyVisibilityChecker ──> ready/not ready
    │                         └──> RepCounter + FormFeedbackEngine
    │
    ├──> HandGestureDetector ──> HandGesture enum (thumbsUp, thumbsDown, etc.)
    │                              │
    │                              └──> WorkoutReadyCoordinator
    │
    └──> FaceLandmarkerService ──> blendshapes dictionary
                                     │
                                     └──> ExertionAnalyzer ──> effortScore
```

All three pipelines receive every camera frame simultaneously. They run in live-stream mode with async callbacks on MediaPipe's internal queues, publishing results to `@Published` properties on the main thread.

### PoseEstimator

Wraps MediaPipe's `PoseLandmarker` task. Configured for live-stream mode with a single pose.

**Output:**
- `bodyJoints: [JointName: CGPoint]` -- 2D normalized coordinates (0...1, top-left origin)
- `worldJoints: [JointName: SIMD3<Float>]` -- 3D world coordinates in meters with hip-center origin (camera-independent)

The 3D world coordinates are the preferred data source for angle calculations because they are not affected by camera angle or perspective distortion. The system falls back to 2D coordinates when 3D data is unavailable for a given joint triple.

### JointName Enum

Framework-agnostic body landmark identifiers. Maps 1:1 with MediaPipe's 33 output indices plus two synthetic joints:

**MediaPipe Indices 0-32:**
- 0: nose
- 1-3: leftEyeInner, leftEye, leftEyeOuter
- 4-6: rightEyeInner, rightEye, rightEyeOuter
- 7-8: leftEar, rightEar
- 9-10: mouthLeft, mouthRight
- 11-12: leftShoulder, rightShoulder
- 13-14: leftElbow, rightElbow
- 15-16: leftWrist, rightWrist
- 17-18: leftPinky, rightPinky
- 19-20: leftIndex, rightIndex
- 21-22: leftThumb, rightThumb
- 23-24: leftHip, rightHip
- 25-26: leftKnee, rightKnee
- 27-28: leftAnkle, rightAnkle
- 29-30: leftHeel, rightHeel
- 31-32: leftFootIndex, rightFootIndex

**Synthetic Joints:**
- 100: neck (midpoint of left/right shoulder)
- 101: root (midpoint of left/right hip)

**Skeleton Bone Pairs** (used for overlay rendering):
- Torso: leftShoulder-rightShoulder, leftShoulder-leftHip, rightShoulder-rightHip, leftHip-rightHip
- Left arm: leftShoulder-leftElbow, leftElbow-leftWrist
- Right arm: rightShoulder-rightElbow, rightElbow-rightWrist
- Left leg: leftHip-leftKnee, leftKnee-leftAnkle, leftAnkle-leftHeel, leftAnkle-leftFootIndex
- Right leg: rightHip-rightKnee, rightKnee-rightAnkle, rightAnkle-rightHeel, rightAnkle-rightFootIndex
- Head: neck-leftShoulder, neck-rightShoulder, neck-nose

### AngleCalculator

Stateless utility that computes all joint angles defined by an `ExerciseDefinition`.

**2D Angle Calculation:**
```
angle = |atan2(v1.dy, v1.dx) - atan2(v2.dy, v2.dx)| * (180/pi)
if angle > 180: angle = 360 - angle
```
Where v1 = start-mid vector, v2 = end-mid vector. Returns degrees 0-180.

**3D Angle Calculation (preferred):**
```
cosAngle = dot(v1, v2) / (length(v1) * length(v2))
angle = acos(clamp(cosAngle, -1, 1)) * (180/pi)
```
Uses SIMD3 vectors for camera-independent accuracy.

**Side Resolution:**
Each `AngleDefinition` specifies a `MeasurementSide`:
- `.left` -- use left-side joints only
- `.right` -- use right-side joints only
- `.both` -- average left and right measurements
- `.bestAvailable` -- prefer right, fall back to left

**Joint Name Resolution:**
Abstract joint names in exercise definitions (e.g., "shoulder", "knee", "hip") are resolved to concrete `JointName` values with side affinity. Special names: "hip_center" resolves to left/right hip based on side, "shoulder_center" similarly.

**Bilateral Angle Pairs:**
For `.both` or `.bestAvailable` definitions, separate left/right measurements are computed and returned as `BilateralAngle` structs with a `delta` property for asymmetry detection.

**Positional Checks:**
Beyond 3-point angle comparisons, the calculator evaluates spatial relationships:

| Check Type | What It Detects | How |
|---|---|---|
| `kneeValgus` | Knee collapsing inward past ankle in frontal plane | `abs(knee.x - ankle.x) / hipWidth > threshold` (default 0.15) |
| `heelRise` | User coming up on toes | `toe.y - heel.y > threshold` (default 0.02) |
| `jointAboveJoint` | One joint higher than another | `jointB.y - jointA.y > threshold` |
| `jointAlignedX` | Two joints horizontally aligned | `abs(jointA.x - jointB.x) > threshold` |
| `shoulderLevel` | Shoulders at same height | `abs(leftShoulder.y - rightShoulder.y) > threshold` (default 0.03) |

### HandGestureDetector

Detects hand gestures from live video frames. Has two modes:

**Primary: GestureRecognizer (ML-based)**
- Uses `gesture_recognizer.task` model
- Directly classifies: Thumb_Up, Thumb_Down, Open_Palm, Closed_Fist, Victory, Pointing_Up
- Configured for up to 2 hands, live-stream mode
- Min detection/presence/tracking confidence: 0.5

**Fallback: HandLandmarker (heuristic)**
- Uses `hand_landmarker.task` model if gesture_recognizer.task is absent
- Manual classification from 21-point hand landmarks:
  - Thumbs up: thumb tip above all finger tips, significant vertical delta from wrist
  - Thumbs down: thumb tip below all finger tips
  - Fist: all four fingers curled (tip close to MCP joint, threshold 0.12)
  - Open palm: no fingers curled

**Evidence Accumulation:**
A gesture must be detected for `confirmationFrames` (3) consecutive frames before being promoted to confirmed. Thumbs up/down require full 3 frames; other gestures require 2 frames.

**Published State:**
- `currentGesture: HandGesture` -- confirmed gesture (.thumbsUp, .thumbsDown, .openPalm, .fist, .victory, .pointingUp, .none)
- `handDetected: Bool`
- `handConfidence: Float`
- `allHandLandmarks: [[Int: CGPoint]]` -- array of per-hand 21-point landmark dictionaries (supports rendering skeletons for multiple hands)

**Hand Skeleton Topology (21-point, 23 bone pairs):**
Wrist (0) connects to: thumb CMC (1), index MCP (5), middle MCP (9), ring MCP (13), pinky MCP (17). Each finger chain: MCP -> PIP -> DIP -> Tip. Cross-palm connections: 5-9, 9-13, 13-17.

### FaceLandmarkerService

Processes live frames through MediaPipe's Face Landmarker for blendshape extraction.

**Configuration:**
- Single face, live-stream mode
- Min detection/presence/tracking confidence: 0.5
- `outputFaceBlendshapes = true`

**Output:**
- `blendshapes: [String: Float]` -- 52 ARKit-compatible blendshape coefficients (0.0-1.0)
- `faceDetected: Bool`

**Key blendshapes consumed by ExertionAnalyzer:**
- `browDownLeft`, `browDownRight` -- brow furrow (effort indicator)
- `eyeSquintLeft`, `eyeSquintRight` -- squinting under strain
- `jawOpen` -- mouth opening (breathing proxy, inverted for clench detection)
- `mouthFunnel`, `mouthPucker` -- mouth tension/bracing
- `eyeBlinkLeft`, `eyeBlinkRight` -- blink tracking for fatigue
- `mouthSmileLeft`, `mouthSmileRight` -- positive engagement

### BodyVisibilityChecker

Stateless evaluator that checks whether the camera can see enough of the user's body for a given exercise.

**Input:** Current joint dictionary + exercise type
**Output:** `Result` struct with:
- `isReady: Bool` -- all required joints visible
- `visibility: Double` -- 0.0 to 1.0 ratio of visible vs. required joints
- `message: String?` -- user-facing instruction if not ready
- `missingJoints: [JointName]` -- which joints are missing

Messages:
- No joints at all: "Step into the frame so the camera can see you"
- Some joints missing: "Move back so your [visibility hint] are visible"

---

## 6. Exercise Library (All 29 Exercises)

The `ExerciseLibrary` is the central registry. Every exercise is defined as an `ExerciseDefinition` struct containing complete biomechanical specifications. The system is fully data-driven -- adding a new exercise means adding a new definition; no code changes to the rep counter or form engine.

### Data Model

Each `ExerciseDefinition` contains:
- **id**: Matches `ExerciseType` rawValue
- **displayName**: Human-readable name
- **category**: upperBody / lowerBody / fullBody / yoga
- **movementType**: repetition (counts reps) / isometric (times hold duration)
- **cameraPosition**: front (face camera) / side (stand sideways)
- **setupInstruction**: Shown before exercise starts
- **requiredJoints**: Which `JointName`s must be visible
- **visibilityHint**: Shown in visibility banner
- **angles**: Array of `AngleDefinition` (which joints, which side)
- **primaryAngleKey**: The angle used for rep counting
- **downThreshold / upThreshold**: `PhaseThreshold` for state machine transitions
- **qualityTarget**: Target angle for a quality rep
- **qualityTargetIsMinimum**: Whether quality target is a floor or ceiling
- **formRules**: Array of `FormRule` with per-personality feedback
- **positionalChecks**: Array of `PositionalCheck` for spatial validation
- **targetMuscles**: Muscles worked
- **minRepDuration**: Minimum seconds between reps (noise filter)
- **idealAngles**: Target angles for form score ROM calculation
- **tempoRange**: Acceptable rep duration range in seconds

### LOWER BODY (10 Exercises)

#### 1. Squats
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera with feet shoulder-width apart"
- **Required Joints**: leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, leftShoulder, rightShoulder
- **Angles**: kneeAngle (hip-knee-ankle, both sides averaged), hipAngle (shoulder-hip-knee, bestAvailable)
- **Primary Angle**: kneeAngle
- **Down Threshold**: kneeAngle < 100 | **Up Threshold**: kneeAngle > 160
- **Quality Target**: 90 (maximum -- must go below this for quality)
- **Min Rep Duration**: 0.8s | **Tempo Range**: 1.5-4.0s
- **Ideal Angles**: kneeAngle=90, hipAngle=80
- **Target Muscles**: Quadriceps, Glutes, Hamstrings, Core
- **Form Rules**:
  - `squat_depth`: kneeAngle > 90 during down phase. Good: "Try to go a bit deeper -- aim for thighs parallel!" Drill: "That's a half rep at best. Get your ass DOWN!" Severity: warning, cooldown: 8s
  - `squat_back_straight`: hipAngle < 65 during down phase. Good: "Keep your chest up and back straight!" Drill: "Stop hunching over like a shrimp! Chest UP!" Severity: warning, cooldown: 10s
- **Positional Checks**:
  - `squat_valgus`: Knee valgus threshold 0.15, down phase. Good: "Push your knees out over your toes -- don't let them cave in!" Drill: "Knees OUT! They're caving in like a cheap tent!" Severity: warning, cooldown: 10s
  - `squat_heel`: Heel rise threshold 0.02, down phase. Good: "Keep your heels flat on the ground!" Drill: "Heels DOWN! You're not doing calf raises!" Severity: warning, cooldown: 10s

#### 2. Sumo Squats
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing camera with feet wider than shoulder-width, toes pointed out"
- **Required Joints**: leftHip, rightHip, leftKnee, rightKnee, leftShoulder, rightShoulder, leftAnkle, rightAnkle
- **Angles**: kneeAngle (hip-knee-ankle, both), hipAngle (shoulder-hip-knee, bestAvailable)
- **Primary Angle**: kneeAngle
- **Down**: kneeAngle < 95 | **Up**: kneeAngle > 160
- **Quality Target**: 85 (maximum) | **Min Rep**: 0.8s | **Tempo**: 1.5-4.0s
- **Ideal Angles**: kneeAngle=85, hipAngle=75
- **Target Muscles**: Inner Thighs, Glutes, Quadriceps, Core
- **Form Rules**:
  - `sumo_depth`: kneeAngle > 85 during down. Good: "Go wider and deeper -- feel that inner thigh stretch!" Drill: "My grandmother squats deeper than that. LOWER!" Warning, 8s
  - `sumo_upright`: hipAngle < 70 during down. Good: "Keep your torso upright -- don't lean forward!" Drill: "Stand up straight! You're not picking up pennies!" Warning, 10s
- **Positional Checks**:
  - `sumo_valgus`: Knee valgus threshold 0.12, down phase. Good: "Push knees out toward your toes!" Drill: "Knees are collapsing! Push them OUT!" Warning, 10s

#### 3. Lunges
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Stand sideways to the camera -- step forward to begin"
- **Required Joints**: leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, leftShoulder, rightShoulder
- **Angles**: frontKneeAngle (hip-knee-ankle, bestAvailable), hipAngle (shoulder-hip-knee, bestAvailable)
- **Primary Angle**: frontKneeAngle
- **Down**: frontKneeAngle < 100 | **Up**: frontKneeAngle > 155
- **Quality Target**: 90 (maximum) | **Min Rep**: 1.0s | **Tempo**: 1.5-4.0s
- **Ideal Angles**: frontKneeAngle=90, hipAngle=85
- **Target Muscles**: Quadriceps, Glutes, Hamstrings, Calves
- **Form Rules**:
  - `lunge_depth`: frontKneeAngle > 90 during down. Good: "Drop that back knee a little lower!" Drill: "That's barely a curtsy. Get DOWN there!" Warning, 8s
  - `lunge_torso`: hipAngle < 75 during down. Good: "Keep your torso upright -- eyes forward!" Drill: "Stop leaning! You look like the Tower of Pisa!" Warning, 10s

#### 4. Side Lunges
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera with feet together"
- **Angles**: kneeAngle (hip-knee-ankle, bestAvailable), trailingKneeAngle (hip-knee-ankle, both)
- **Primary Angle**: kneeAngle
- **Down**: kneeAngle < 105 | **Up**: kneeAngle > 155
- **Quality Target**: 90 (maximum) | **Min Rep**: 1.0s | **Tempo**: 1.5-4.0s
- **Ideal Angles**: kneeAngle=90
- **Target Muscles**: Inner Thighs, Quadriceps, Glutes, Hip Flexors
- **Form Rules**:
  - `sidelunge_depth`: kneeAngle > 90 during down. Good: "Sink a bit deeper into the lunge!" Drill: "That was pathetic. Sit INTO it!" Warning, 8s
  - `sidelunge_trailing`: trailingKneeAngle < 160 during down. Good: "Keep your trailing leg straight -- don't bend it!" Drill: "Straight leg on the other side! Only ONE knee bends!" Info, 10s
- **Positional Checks**:
  - `sidelunge_shoulders`: Shoulder level threshold 0.04, down phase. Good: "Keep your shoulders level -- don't lean to one side!" Drill: "You're tilting! Keep those shoulders LEVEL!" Info, 10s

#### 5. Glute Bridge
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Lie on your back sideways to the camera, knees bent"
- **Angles**: hipAngle (shoulder-hip-knee, bestAvailable), kneeAngle (hip-knee-ankle, bestAvailable)
- **Primary Angle**: hipAngle
- **Down**: hipAngle > 160 (note: down = entering from above) | **Up**: hipAngle < 130
- **Quality Target**: 170 (minimum -- must go ABOVE this)
- **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: hipAngle=170, kneeAngle=90
- **Target Muscles**: Glutes, Hamstrings, Core, Lower Back
- **Form Rules**:
  - `bridge_height`: hipAngle < 170 during down. Good: "Squeeze your glutes and push those hips higher!" Drill: "Higher! Your hips are barely off the ground!" Warning, 8s
  - `bridge_kneeangle`: kneeAngle outside 75-105 during down. Good: "Keep your knees at roughly 90 degrees!" Drill: "Fix your knee angle -- not too wide, not too narrow!" Info, 12s

#### 6. Hip Abduction Standing
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera -- lift one leg out to the side"
- **Angles**: legAbductionAngle (ankle_left-hip_center-ankle_right, both)
- **Primary Angle**: legAbductionAngle
- **Down**: legAbductionAngle > 25 | **Up**: legAbductionAngle < 12
- **Quality Target**: 35 (minimum) | **Min Rep**: 0.6s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: legAbductionAngle=40
- **Target Muscles**: Hip Abductors, Glutes, Outer Thighs
- **Form Rules**:
  - `hipab_range`: legAbductionAngle < 35 during down. Good: "Lift that leg a bit higher -- feel the burn!" Drill: "Higher! You're barely moving that leg!" Warning, 8s
- **Positional Checks**:
  - `hipab_shoulders`: Shoulder level threshold 0.04, down phase. Good: "Keep your torso upright -- don't lean sideways!" Drill: "Stop leaning! Stand up STRAIGHT!" Info, 10s

#### 7. Leg Raises
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Lie on your back sideways to the camera, legs straight"
- **Angles**: hipFlexionAngle (shoulder-hip-ankle, bestAvailable), kneeAngle (hip-knee-ankle, bestAvailable)
- **Primary Angle**: hipFlexionAngle
- **Down**: hipFlexionAngle < 110 | **Up**: hipFlexionAngle > 160
- **Quality Target**: 95 (maximum) | **Min Rep**: 1.0s | **Tempo**: 1.5-4.0s
- **Ideal Angles**: hipFlexionAngle=90, kneeAngle=170
- **Target Muscles**: Lower Abs, Hip Flexors, Core
- **Form Rules**:
  - `legr_straight`: kneeAngle < 165 during down+up. Good: "Keep your legs straight -- don't bend the knees!" Drill: "Straight legs! Not banana legs!" Warning, 10s
  - `legr_height`: hipFlexionAngle > 95 during down. Good: "Lift those legs a bit higher!" Drill: "Higher! Your legs should be pointing at the ceiling!" Warning, 8s
  - `legr_momentum`: hipFlexionAngle < 80 during down. Good: "Control the movement -- don't use momentum to swing!" Drill: "Stop SWINGING! Slow and controlled -- feel every inch!" Info, 10s

#### 8. Wall Sit (Isometric)
- **Camera**: Side | **Type**: Isometric
- **Setup**: "Stand sideways to the camera and slide down the wall until thighs are parallel"
- **Angles**: kneeAngle (hip-knee-ankle, bestAvailable), hipAngle (shoulder-hip-knee, bestAvailable)
- **Primary Angle**: kneeAngle
- **Down (hold position)**: kneeAngle < 100 | **Up (exit)**: kneeAngle > 150
- **Quality Target**: 90 (maximum)
- **Ideal Angles**: kneeAngle=90, hipAngle=90
- **Target Muscles**: Quadriceps, Glutes, Calves, Core
- **Form Rules**:
  - `wallsit_depth`: kneeAngle > 90, always active. Good: "Lower down a bit more -- aim for 90 degrees at the knee!" Drill: "That's not sitting, that's leaning! Get DOWN to 90!" Warning, 10s
  - `wallsit_back`: hipAngle < 80, always active. Good: "Keep your back flat against the wall -- stay upright!" Drill: "Back FLAT against the wall! You're slouching!" Warning, 10s

#### 9. Deadlift
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Stand sideways to the camera, feet hip-width apart"
- **Angles**: hipAngle (shoulder-hip-knee, bestAvailable), kneeAngle (hip-knee-ankle, bestAvailable)
- **Primary Angle**: hipAngle
- **Down**: hipAngle < 100 | **Up**: hipAngle > 165
- **Quality Target**: 90 (maximum) | **Min Rep**: 1.0s | **Tempo**: 2.0-5.0s
- **Ideal Angles**: hipAngle=90
- **Target Muscles**: Hamstrings, Glutes, Lower Back, Traps, Core
- **Form Rules**:
  - `deadlift_back`: hipAngle < 70 during down. Good: "Keep your back flat -- don't let it round over!" Drill: "Your back is rounding like a scared cat! FLAT back!" **Critical**, 8s
  - `deadlift_lockout`: hipAngle < 170 during up. Good: "Stand all the way up -- squeeze your glutes at the top!" Drill: "Lock it OUT! Stand up straight and squeeze!" Warning, 8s
  - `deadlift_knees`: kneeAngle < 140 during down. Good: "Keep your knees soft but fairly straight -- this isn't a squat!" Drill: "Straighten those knees! You're squatting, not hinging!" Info, 10s

#### 10. Calf Raises
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Stand sideways to the camera, feet hip-width apart"
- **Angles**: kneeAngle (hip-knee-ankle, bestAvailable)
- **Primary Angle**: kneeAngle
- **Down**: kneeAngle < 165 | **Up**: kneeAngle > 170
- **Quality Target**: 155 (maximum) | **Min Rep**: 0.5s | **Tempo**: 0.8-2.5s
- **Ideal Angles**: kneeAngle=170
- **Target Muscles**: Calves, Soleus
- **Form Rules**:
  - `calfraise_straight`: kneeAngle < 160 during down+up. Good: "Keep your legs straight -- don't bend the knees!" Drill: "Straight legs! This is calves, not squats!" Warning, 8s
- **Positional Checks**:
  - `calfraise_balance`: Shoulder level threshold 0.04, always. Good: "Stay balanced -- keep your weight centered!" Drill: "Stop wobbling! Center your weight!" Info, 10s

### UPPER BODY (10 Exercises)

#### 11. Bicep Curls
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, arms at your sides"
- **Required Joints**: leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip
- **Angles**: elbowAngle (shoulder-elbow-wrist, both), shoulderAngle (hip-shoulder-elbow, both)
- **Primary Angle**: elbowAngle
- **Down**: elbowAngle < 55 | **Up**: elbowAngle > 150
- **Quality Target**: 40 (maximum) | **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: elbowAngle=35
- **Target Muscles**: Biceps, Forearms
- **Form Rules**:
  - `curl_fullrange`: elbowAngle > 40 during down. Good: "Squeeze harder at the top -- full contraction!" Drill: "That's a half curl. Bring it ALL the way up!" Warning, 8s
  - `curl_swing`: shoulderAngle > 30 during down+up. Good: "Keep your elbows pinned to your sides -- don't swing!" Drill: "Stop swinging! You're not on a playground!" Warning, 10s
  - `curl_fullextend`: elbowAngle < 150 during up. Good: "Fully extend your arms at the bottom!" Drill: "All the way down! Full range of motion!" Info, 12s

#### 12. Push Ups
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Get into plank position facing the camera (side view for more accuracy)"
- **Required Joints**: shoulders, elbows, wrists, hips, ankles (both sides)
- **Angles**: elbowAngle (shoulder-elbow-wrist, bestAvailable), shoulderAngle (hip-shoulder-elbow, bestAvailable), bodyLineAngle (shoulder-hip-ankle, bestAvailable)
- **Primary Angle**: elbowAngle
- **Down**: elbowAngle < 100 | **Up**: elbowAngle > 155
- **Quality Target**: 85 (maximum) | **Min Rep**: 1.0s | **Tempo**: 1.5-4.0s
- **Ideal Angles**: elbowAngle=80, bodyLineAngle=170
- **Target Muscles**: Chest, Triceps, Shoulders, Core
- **Form Rules**:
  - `pushup_depth`: elbowAngle > 85 during down. Good: "Go a bit deeper -- chest towards the floor!" Drill: "That's not a push-up, that's a head nod. LOWER!" Warning, 8s
  - `pushup_bodyline`: bodyLineAngle outside 160-180 during all phases. Good: "Keep your body in a straight line -- don't sag or pike!" Drill: "Your body line is off! Tighten that core NOW!" Warning, 12s
  - `pushup_hips_sag`: bodyLineAngle < 155 during down+up. Good: "Your hips are sagging -- squeeze your glutes and tighten your core!" Drill: "Hips are DROPPING! Tighten everything -- you're a PLANK, not a hammock!" **Critical**, 10s
  - `pushup_hips_pike`: bodyLineAngle > 185 during down+up. Good: "Your hips are too high -- flatten your body line!" Drill: "Stop piking! This is push-ups, not downward dog!" Warning, 10s

#### 13. Lateral Raises
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, arms at your sides"
- **Angles**: shoulderAbductionAngle (hip-shoulder-wrist, both), elbowAngle (shoulder-elbow-wrist, both)
- **Primary Angle**: shoulderAbductionAngle
- **Down**: shoulderAbductionAngle > 75 | **Up**: shoulderAbductionAngle < 30
- **Quality Target**: 85 (minimum) | **Min Rep**: 0.6s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: shoulderAbductionAngle=90
- **Target Muscles**: Lateral Deltoids, Traps
- **Form Rules**:
  - `latrise_height`: shoulderAbductionAngle < 85 during down. Good: "Raise your arms to shoulder height!" Drill: "Higher! Your arms should be parallel to the floor!" Warning, 8s
  - `latrise_straight`: elbowAngle < 155 during down+up. Good: "Keep a slight bend but don't collapse the arms!" Drill: "Straighten those noodle arms!" Info, 12s
  - `latrise_toohigh`: shoulderAbductionAngle > 100 during down. Good: "Don't raise past shoulder height -- control at the top!" Drill: "TOO HIGH! Shoulder height is the ceiling -- stop overshooting!" Info, 10s
- **Positional Checks**:
  - `latrise_shrug`: Shoulder level threshold 0.05, down phase. Good: "Relax your traps -- don't shrug your shoulders up!" Drill: "Drop those shoulders! You're not earring shopping!" Info, 12s

#### 14. Front Raises
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Stand sideways to the camera, arms at your sides"
- **Angles**: shoulderFlexionAngle (hip-shoulder-wrist, bestAvailable), elbowAngle (shoulder-elbow-wrist, bestAvailable), hipAngle (knee-hip-shoulder, bestAvailable)
- **Primary Angle**: shoulderFlexionAngle
- **Down**: shoulderFlexionAngle > 75 | **Up**: shoulderFlexionAngle < 30
- **Quality Target**: 85 (minimum) | **Min Rep**: 0.6s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: shoulderFlexionAngle=90
- **Target Muscles**: Anterior Deltoids, Upper Chest
- **Form Rules**:
  - `frontrise_height`: shoulderFlexionAngle < 85 during down. Good: "Lift to shoulder height -- nice and controlled!" Drill: "Higher! I said shoulder height, not belly button height!" Warning, 8s
  - `frontrise_elbow`: elbowAngle < 155 during down+up. Good: "Keep your arms straight!" Drill: "Lock those elbows! This isn't bicep curls!" Info, 12s
  - `frontrise_sway`: hipAngle < 165 during down+up. Good: "Stay upright -- don't sway backwards!" Drill: "Stop leaning back! Control the weight!" Info, 12s

#### 15. Overhead Dumbbell Press
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, weights at shoulder height"
- **Angles**: elbowAngle (shoulder-elbow-wrist, both), shoulderAbductionAngle (hip-shoulder-elbow, both)
- **Primary Angle**: elbowAngle
- **Down**: elbowAngle > 155 | **Up**: elbowAngle < 95
- **Quality Target**: 170 (minimum) | **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: elbowAngle=175
- **Target Muscles**: Shoulders, Triceps, Upper Chest, Traps
- **Form Rules**:
  - `ohp_lockout`: elbowAngle < 170 during down. Good: "Press all the way up -- full extension!" Drill: "Lock it out! Halfway doesn't count!" Warning, 8s
  - `ohp_elbow_position`: shoulderAbductionAngle < 60 during down+up. Good: "Keep elbows at about 45 degrees from your body!" Drill: "Elbows out! Don't tuck them in so tight!" Info, 12s

#### 16. Cobra Wings
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing camera, arms bent at 90 degrees in front of chest"
- **Angles**: elbowAngle (shoulder-elbow-wrist, both), shoulderAngle (hip-shoulder-elbow, both)
- **Primary Angle**: shoulderAngle
- **Down**: shoulderAngle > 80 | **Up**: shoulderAngle < 40
- **Quality Target**: 90 (minimum) | **Min Rep**: 0.6s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: shoulderAngle=95, elbowAngle=90
- **Target Muscles**: Rear Deltoids, Rhomboids, Traps, Rotator Cuff
- **Form Rules**:
  - `cobra_squeeze`: shoulderAngle < 90 during down. Good: "Squeeze those shoulder blades together!" Drill: "Squeeze harder! Pretend there's a pencil between your shoulder blades!" Warning, 8s
  - `cobra_elbow`: elbowAngle outside 80-110 during down+up. Good: "Maintain that 90-degree elbow bend!" Drill: "Keep those elbows locked at 90! This isn't a flap!" Info, 12s

#### 17. Overarm Reach Bilateral
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, arms at your sides"
- **Angles**: shoulderFlexionAngle (hip-shoulder-wrist, both), elbowAngle (shoulder-elbow-wrist, both)
- **Primary Angle**: shoulderFlexionAngle
- **Down**: shoulderFlexionAngle > 150 | **Up**: shoulderFlexionAngle < 40
- **Quality Target**: 165 (minimum) | **Min Rep**: 0.6s | **Tempo**: 1.0-3.5s
- **Ideal Angles**: shoulderFlexionAngle=170, elbowAngle=170
- **Target Muscles**: Shoulders, Lats, Core, Upper Back
- **Form Rules**:
  - `overarm_full`: shoulderFlexionAngle < 165 during down. Good: "Reach all the way overhead -- full stretch!" Drill: "ALL the way up! Touch the ceiling!" Warning, 8s
  - `overarm_straight`: elbowAngle < 160 during down+up. Good: "Keep your arms straight as you reach!" Drill: "Straight arms! You're not doing bicep curls!" Info, 12s

#### 18. Hammer Curls
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, arms at your sides with palms facing in"
- **Angles**: elbowAngle (shoulder-elbow-wrist, both), shoulderAngle (hip-shoulder-elbow, both)
- **Primary Angle**: elbowAngle
- **Down**: elbowAngle < 50 | **Up**: elbowAngle > 155
- **Quality Target**: 40 (maximum) | **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: elbowAngle=35
- **Target Muscles**: Biceps, Brachialis, Brachioradialis, Forearms
- **Form Rules**:
  - `hammer_squeeze`: elbowAngle > 40 during down. Good: "Great squeeze! Hold briefly at the top for max contraction!" Drill: "Squeeze HARDER at the top! Don't just swing through!" Warning, 8s
  - `hammer_fullextend`: elbowAngle < 155 during up. Good: "Extend fully between reps -- full range of motion!" Drill: "ALL the way down! Partial reps are worthless!" Info, 10s
  - `hammer_swing`: shoulderAngle > 30 during down+up. Good: "Keep your elbows pinned -- don't let the shoulders drift!" Drill: "Elbows LOCKED to your sides! Stop using momentum!" Warning, 10s

#### 19. Shoulder Press
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, weights at shoulder height"
- **Angles**: shoulderAngle (hip-shoulder-elbow, both), elbowAngle (shoulder-elbow-wrist, both)
- **Primary Angle**: shoulderAngle
- **Down**: shoulderAngle > 160 | **Up**: shoulderAngle < 90
- **Quality Target**: 170 (minimum) | **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: shoulderAngle=175
- **Target Muscles**: Shoulders, Triceps, Upper Chest, Traps
- **Form Rules**:
  - `shoulderpress_lockout`: shoulderAngle < 170 during down. Good: "Press all the way up -- lock those arms out!" Drill: "LOCK IT OUT! Halfway reps don't build shoulders!" Warning, 8s
  - `shoulderpress_depth`: shoulderAngle > 85 during up. Good: "Bring the weights all the way down to shoulder height!" Drill: "Lower! All the way to your shoulders -- full range!" Info, 10s
- **Positional Checks**:
  - `shoulderpress_uneven`: Shoulder level threshold 0.05, down phase. Good: "Press both arms evenly -- don't favor one side!" Drill: "Even it out! One arm is leading -- press TOGETHER!" Warning, 10s

#### 20. Tricep Dips
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Position sideways to the camera, hands on a bench behind you"
- **Required Joints**: leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
- **Angles**: elbowAngle (shoulder-elbow-wrist, bestAvailable)
- **Primary Angle**: elbowAngle
- **Down**: elbowAngle < 90 | **Up**: elbowAngle > 160
- **Quality Target**: 85 (maximum) | **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: elbowAngle=85
- **Target Muscles**: Triceps, Chest, Anterior Deltoids
- **Form Rules**:
  - `tricdip_depth`: elbowAngle > 90 during down. Good: "Go deeper -- aim for a 90-degree bend at the elbow!" Drill: "That's not a dip, that's a nod! Get to 90 degrees!" Warning, 8s
  - `tricdip_lockout`: elbowAngle < 160 during up. Good: "Extend fully at the top -- lock those triceps!" Drill: "All the way UP! Lock out those arms!" Info, 10s

### FULL BODY (7 Exercises)

#### 21. Jumping Jacks
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera, arms at your sides, feet together"
- **Angles**: armRaiseAngle (hip-shoulder-wrist, both), legSpreadAngle (ankle_left-hip_center-ankle_right, both)
- **Primary Angle**: armRaiseAngle
- **Down**: armRaiseAngle > 140 | **Up**: armRaiseAngle < 40
- **Quality Target**: 160 (minimum) | **Min Rep**: 0.3s | **Tempo**: 0.5-2.0s
- **Ideal Angles**: armRaiseAngle=165
- **Target Muscles**: Full Body, Shoulders, Calves, Core
- **Form Rules**:
  - `jj_arms`: armRaiseAngle < 160 during down. Good: "Get those arms all the way overhead!" Drill: "Arms UP! Not halfway -- ALL THE WAY!" Warning, 6s
  - `jj_legs`: legSpreadAngle < 35 during down. Good: "Spread your feet wider -- open up those legs!" Drill: "Wider! Those legs should be JUMPING apart!" Info, 8s

#### 22. Knee Raises Bilateral
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera -- alternate lifting each knee"
- **Angles**: hipFlexionAngle (shoulder-hip-knee, bestAvailable), trunkAngle (knee-hip-shoulder, bestAvailable)
- **Primary Angle**: hipFlexionAngle
- **Down**: hipFlexionAngle < 100 | **Up**: hipFlexionAngle > 150
- **Quality Target**: 80 (maximum) | **Min Rep**: 0.4s | **Tempo**: 0.5-2.0s
- **Ideal Angles**: hipFlexionAngle=75
- **Target Muscles**: Hip Flexors, Core, Quads
- **Form Rules**:
  - `kneer_height`: hipFlexionAngle > 80 during down. Good: "Drive that knee up to hip height!" Drill: "HIGHER! Your knee should hit your chest!" Warning, 6s

#### 23. Sit Ups
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Lie on your back sideways to the camera, knees bent"
- **Angles**: torsoAngle (shoulder-hip-knee, bestAvailable)
- **Primary Angle**: torsoAngle
- **Down**: torsoAngle < 90 | **Up**: torsoAngle > 140
- **Quality Target**: 70 (maximum) | **Min Rep**: 0.8s | **Tempo**: 1.0-3.0s
- **Ideal Angles**: torsoAngle=65
- **Target Muscles**: Abs, Hip Flexors, Core
- **Form Rules**:
  - `situp_full`: torsoAngle > 70 during down. Good: "Come all the way up -- don't stop halfway!" Drill: "ALL the way up! That was a crunch, not a sit-up!" Warning, 8s

#### 24. V-Ups
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Lie flat on your back sideways to the camera"
- **Angles**: torsoAngle (wrist-shoulder-hip, bestAvailable), hipFlexionAngle (shoulder-hip-ankle, bestAvailable), kneeAngle (hip-knee-ankle, bestAvailable)
- **Primary Angle**: hipFlexionAngle
- **Down**: hipFlexionAngle < 100 | **Up**: hipFlexionAngle > 155
- **Quality Target**: 70 (maximum) | **Min Rep**: 1.0s | **Tempo**: 1.5-4.0s
- **Ideal Angles**: hipFlexionAngle=60, kneeAngle=170
- **Target Muscles**: Upper Abs, Lower Abs, Hip Flexors, Core
- **Form Rules**:
  - `vup_touch`: hipFlexionAngle > 70 during down. Good: "Reach for your toes -- hands and feet should meet!" Drill: "Touch your toes! Not your knees -- your TOES!" Warning, 8s
  - `vup_legs_straight`: kneeAngle < 160 during down+up. Good: "Keep those legs straight throughout the movement!" Drill: "Straight legs! Don't cheat by bending your knees!" Warning, 10s

#### 25. Plank (Isometric)
- **Camera**: Side | **Type**: Isometric
- **Setup**: "Get into plank position sideways to the camera"
- **Angles**: bodyLineAngle (shoulder-hip-ankle, bestAvailable), elbowAngle (shoulder-elbow-wrist, bestAvailable)
- **Primary Angle**: bodyLineAngle
- **Down (hold)**: bodyLineAngle > 160 | **Up (exit)**: bodyLineAngle < 145
- **Quality Target**: 175 (minimum)
- **Target Muscles**: Core, Shoulders, Glutes, Back
- **Form Rules**:
  - `plank_sag`: bodyLineAngle < 165, always. Good: "Keep your hips up -- straight line from head to heels!" Drill: "Your hips are dropping! Tighten that core NOW!" **Critical**, 8s
  - `plank_pike`: bodyLineAngle > 180, always. Good: "Don't pike your hips -- bring them down a touch!" Drill: "You're not doing downward dog! Flatten out!" Warning, 8s

#### 26. High Knees
- **Camera**: Front | **Type**: Repetition
- **Setup**: "Stand facing the camera -- drive each knee up as high as you can"
- **Angles**: hipFlexionAngle (shoulder-hip-knee, bestAvailable)
- **Primary Angle**: hipFlexionAngle
- **Down**: hipFlexionAngle < 100 | **Up**: hipFlexionAngle > 150
- **Quality Target**: 90 (maximum) | **Min Rep**: 0.2s | **Tempo**: 0.3-1.5s
- **Ideal Angles**: hipFlexionAngle=80
- **Target Muscles**: Hip Flexors, Core, Quads, Calves
- **Form Rules**:
  - `highknee_height`: hipFlexionAngle > 100 during down. Good: "Drive that knee higher -- aim for hip level!" Drill: "HIGHER! Your knee should be at hip height minimum!" Warning, 5s
- **Positional Checks**:
  - `highknee_posture`: Shoulder level threshold 0.05, always. Good: "Stay upright -- don't lean to one side!" Drill: "Stand STRAIGHT! You're wobbling all over!" Info, 8s

#### 27. Mountain Climbers
- **Camera**: Side | **Type**: Repetition
- **Setup**: "Get into plank position sideways to the camera"
- **Angles**: hipFlexionAngle (shoulder-hip-knee, bestAvailable), bodyLineAngle (shoulder-hip-ankle, bestAvailable)
- **Primary Angle**: hipFlexionAngle
- **Down**: hipFlexionAngle < 90 | **Up**: hipFlexionAngle > 160
- **Quality Target**: 80 (maximum) | **Min Rep**: 0.2s | **Tempo**: 0.3-1.5s
- **Ideal Angles**: hipFlexionAngle=80
- **Target Muscles**: Core, Hip Flexors, Shoulders, Quads, Chest
- **Form Rules**:
  - `mtnclimb_hips`: bodyLineAngle < 155, always. Good: "Keep your hips level -- don't let them pike up!" Drill: "Hips DOWN! You're not doing downward dog!" Warning, 8s

### YOGA (2 Exercises)

#### 28. Downward Dog (Isometric)
- **Camera**: Side | **Type**: Isometric
- **Setup**: "Start on all fours sideways to the camera, then lift hips up"
- **Angles**: hipAngle (shoulder-hip-ankle, bestAvailable), shoulderAngle (hip-shoulder-wrist, bestAvailable), kneeAngle (hip-knee-ankle, bestAvailable)
- **Primary Angle**: hipAngle
- **Down (hold)**: hipAngle < 100 | **Up (exit)**: hipAngle > 140
- **Quality Target**: 70 (maximum)
- **Target Muscles**: Hamstrings, Calves, Shoulders, Back, Core
- **Form Rules**:
  - `dd_hips`: hipAngle > 90, always. Good: "Push your hips higher -- create that inverted V!" Drill: "Hips UP! You look like a table, not a dog!" Warning, 10s
  - `dd_legs`: kneeAngle < 165, always. Good: "Try to straighten your legs -- press heels down!" Drill: "Straight legs! Bend those knees on your own time!" Info, 12s
  - `dd_arms`: shoulderAngle < 165, always. Good: "Extend your arms fully -- push the floor away!" Drill: "Lock those arms! Push the ground AWAY from you!" Info, 12s

#### 29. Warrior II (Isometric)
- **Camera**: Front | **Type**: Isometric
- **Setup**: "Stand facing the camera, step wide and extend arms to the sides"
- **Angles**: frontKneeAngle (hip-knee-ankle, bestAvailable), armLineAngle (wrist_left-shoulder_center-wrist_right, both), shoulderAbductionAngle (hip-shoulder-wrist, both)
- **Primary Angle**: frontKneeAngle
- **Down (hold)**: frontKneeAngle < 110 | **Up (exit)**: frontKneeAngle > 150
- **Quality Target**: 95 (maximum)
- **Target Muscles**: Quads, Glutes, Shoulders, Core, Hip Flexors
- **Form Rules**:
  - `warrior_knee`: frontKneeAngle > 95, always. Good: "Bend your front knee deeper -- aim for 90 degrees!" Drill: "Deeper! A warrior doesn't stand straight!" Warning, 10s
  - `warrior_arms`: shoulderAbductionAngle < 80, always. Good: "Keep your arms parallel to the ground!" Drill: "Arms UP and OUT! Like you're reaching for two walls!" Warning, 10s
- **Positional Checks**:
  - `warrior_shoulders`: Shoulder level threshold 0.04, always. Good: "Keep your shoulders level -- don't tilt!" Drill: "LEVEL shoulders! You're a warrior, not a seesaw!" Info, 12s

---

## 7. Rep Counting System

### RepCounter Protocol

Every exercise-specific counter implements the `RepCounter` protocol:

```swift
protocol RepCounter: AnyObject {
    var exerciseType: ExerciseType { get }
    var repCount: Int { get }
    var currentPhase: RepPhase { get }
    func process(angles: [String: Double]) -> RepCounterOutput
    func reset()
}
```

### RepPhase State Machine

Every exercise follows the same abstract loop:

```
idle  ──(angle crosses down threshold)──>  down
down  ──(angle crosses up threshold)──>    up  [rep counted here]
up    ──(immediate)──>                     idle
```

- `idle`: Standing/resting -- waiting for movement
- `down`: Eccentric portion -- user is lowering into the rep
- `up`: Concentric portion -- user is driving back up. Rep counted at down->up transition.

### RepCounterOutput

Every `process()` call returns:

| Field | Type | Description |
|---|---|---|
| `repCount` | Int | Total reps completed in this set |
| `phase` | RepPhase | Current movement phase |
| `cues` | [CoachCue] | Form-check warnings for this frame (empty = clean form) |
| `holdDuration` | TimeInterval | Seconds held in isometric position (0 for rep-based) |
| `isHolding` | Bool | Currently in held position |
| `formScore` | FormScore? | Per-rep quality score (nil if no rep just completed) |

### UniversalRepCounter (Primary)

The `UniversalRepCounter` is the main counter used for all exercises. It is fully data-driven from `ExerciseDefinition` -- no exercise-specific logic is hardcoded.

**Key Configuration (from ExerciseDefinition):**
- Phase thresholds: `downThreshold.enterBelow/enterAbove`, `upThreshold.enterBelow/enterAbove`
- Quality target for depth cues
- Min rep duration (default 0.5s)
- Ideal angles for form score ROM calculation
- Tempo range for form score tempo calculation

**Noise Reduction:**
- **EMA Smoothing**: Exponential Moving Average with alpha=0.4 applied to all angle values before processing. Reduces frame-to-frame jitter from 3D world landmarks.
- **Hysteresis**: Phase transitions require 2 consecutive frames in the new phase before the transition is committed. Prevents single-frame noise from triggering false phase changes.
- **Min Rep Duration**: Minimum time between rep counts (per exercise, default 0.5s). Prevents bouncing at the bottom of a movement from being counted as multiple reps.

**Form Score Calculation:**

Each completed rep receives a 0-100 composite score:

```
score = 100 - ROM_penalty - tempo_penalty - feedback_penalty
```

| Component | Calculation | Cap |
|---|---|---|
| ROM Penalty | For each tracked angle: `abs(extreme - ideal) / 10 * 5`, averaged across all angles | 40 points |
| Tempo Penalty | Too fast: `(idealMin - duration) / 0.5 * 15`. Too slow: `(duration - idealMax) * 10` | 30 points |
| Feedback Penalty | Number of form feedback cues fired during the rep * 10 | 30 points |

**Letter Grades:**
- A: 90-100
- B: 80-89
- C: 70-79
- D: 60-69
- F: 0-59

**Isometric Mode:**

For `movementType == .isometric` exercises (plank, wall sit, yoga), the counter tracks hold duration instead of reps:
- Entering the "down" phase starts a hold timer
- Leaving the "down" phase pauses the timer and accumulates the duration
- `repCount` is set to `Int(totalHoldDuration)` for display purposes

### SquatRepCounter (Legacy)

A hardcoded squat-specific counter that predates the `UniversalRepCounter`. Still present in the codebase. Uses different thresholds than the library definition:

| Threshold | Value |
|---|---|
| upThreshold | 150 degrees |
| downThreshold | 120 degrees |
| depthTarget | 110 degrees |
| depthCueCooldown | 8 seconds |

Supports both 2D and 3D angle resolution. Has its own `calculateAngle()` method and joint-resolution helpers. Generates a "Go a bit deeper" cue when depth target is not reached.

---

## 8. Coaching System

### FormFeedbackEngine

Real-time biomechanical form analyzer. Checks are evaluated every frame in a strict priority hierarchy -- the engine returns the first category that has violations and stops:

1. **Body Position** (highest priority): Is the user in frame at all?
   - No joints: "Step into the frame so the camera can see you" (critical)
   - Fewer than 4 joints: "Move further from the camera -- show more of your body" (warning)

2. **Joint Visibility**: Are all required joints for this exercise visible?
   - Lists missing joints by display name: "Move your [joint list] into view" (warning)

3. **Form Rules**: Per-exercise biomechanical constraints from `ExerciseDefinition.formRules`
   - Checks angle values against min/max thresholds
   - Respects `activeDuringPhases` -- only checks rules relevant to current movement phase
   - Per-rule cooldown prevents spam
   - Global cooldown of 3 seconds between any two feedbacks
   - Feedback text selected by coach personality (good vs drill)
   - Only one rule fires per evaluation cycle (first violated rule wins)

4. **Positional Checks**: Spatial/landmark-relative checks from `ExerciseDefinition.positionalChecks`
   - Evaluated by `AngleCalculator.evaluatePositionalChecks()` using both 2D and 3D joints
   - Same cooldown and single-fire logic as form rules

5. **Bilateral Asymmetry** (lowest priority): Left/right imbalance detection
   - Triggers when delta between left and right angle exceeds 15 degrees
   - Per-angle cooldown of 8 seconds
   - Good: "Your [side] [joint] is off by [delta] degrees -- try to keep both sides even!"
   - Drill: "[delta] degree imbalance on your [side] [joint]! Even it out NOW!"

### MotivationEngine

Detects fatigue from rep tempo decay and fires motivational messages.

**Detection Model:**
```
Baseline = average of gap between rep 1->2 and rep 2->3
Latest gap = time between last two reps
Decay ratio = (latestGap - baseline) / baseline

If decayRatio > threshold (40%, or 24% when face effort > 0.6):
    Fire motivational push
```

The face effort score from `ExertionAnalyzer` modulates the threshold: if the user is visibly straining (effortScore > 0.6), the tempo decay threshold is reduced by 40%, meaning motivation fires sooner even with smaller tempo drops.

**Rate Limiting:** Maximum one motivational push every 15 seconds.

**Display:** Message appears as large overlay text for 3.5 seconds with spring pop-in animation, then auto-dismisses.

**Phrase Pools:**

*Good Coach (12 phrases):*
1. "Stay tight! Push through it!"
2. "Breathe! You got this!"
3. "One more -- make it count!"
4. "That bar isn't gonna lift itself!"
5. "Dig deep, champion!"
6. "Pain is just weakness leaving!"
7. "You didn't come this far to quit!"
8. "Lock in -- this is your set!"
9. "Strong legs, strong mind!"
10. "Eyes up, chest proud -- finish it!"
11. "Your future self is watching!"
12. "This is where champions are made!"

*Drill Sergeant (16 phrases):*
1. "Get moving you lazy sack of shit!"
2. "My grandma squats heavier than that!"
3. "Someone else is out-working you right now!"
4. "You call that a rep? Pathetic!"
5. "Stop resting, your ex is watching!"
6. "That was embarrassing. Do it again!"
7. "You're softer than a marshmallow. PUSH!"
8. "Quit whining and finish the damn set!"
9. "Is that all you've got? Weak!"
10. "Pain? That's just your excuses crying!"
11. "Move it! Nobody cares about your feelings!"
12. "You paid for this gym, now USE it!"
13. "While you rest someone's hitting on your girl. MOVE!"
14. "You want a body or a participation trophy?"
15. "Get your ass down lower!"
16. "Absolutely disgusting effort. Again!"

Phrases cycle sequentially after a random starting index to avoid repetition.

**Integration:** Each motivational push triggers `warningPulse()` haptic and speaks the text via `VoiceCoachManager` (currently a stub).

### ExertionAnalyzer

Derives a real-time effort/exertion score from facial blendshapes.

**Scoring Model:**

Weighted composite of facial signals:

| Blendshape | Weight | Interpretation |
|---|---|---|
| `browDownLeft` | 0.20 | Brow furrow -- people frown harder under load |
| `browDownRight` | 0.20 | |
| `eyeSquintLeft` | 0.15 | Involuntary squinting during strain |
| `eyeSquintRight` | 0.15 | |
| `jawOpen` (inverted) | 0.12 | Jaw clenching during maximal effort (1 - jawOpen*3) |
| `mouthFunnel` | 0.10 | Bracing/tension |
| `mouthPucker` | 0.08 | Bracing/tension |

The weighted composite is normalized by total weight, then scaled by 2.5x and clamped to 1.0.

**Smoothing:** EMA with alpha=0.25. When no face is detected, raw effort decays at 0.95 per frame.

**Output:**
- `effortScore: Double` -- 0.0 (resting) to 1.0 (maximum strain)
- `fatigueLevel: Double` -- 0.0 (fresh) to 1.0 (exhausted)

**Fatigue Model:**
- Accumulates at 0.002 per update when effortScore > 0.4
- Recovers at 0.001 per update when effortScore <= 0.4
- Blink rate above 0.5 blinks/second (measured over 30-second window) adds 0.001 per update

### WorkoutReadyCoordinator

Orchestrates the pre-exercise ready-check flow:

```
positioning
    | (body visible)
    v
askingReady <-----------+
    |                   |
    +-- thumbs up       |
    |     |             |
    |     v             |
    |  countdown(3)     |
    |  countdown(2)     |
    |  countdown(1)     |
    |     |             |
    |     v             |
    |  exerciseActive   |
    |                   |
    +-- thumbs down     |
          |             |
          v             |
      waitingToRetry(3) |
      waitingToRetry(2) |
      waitingToRetry(1) |
          +-------------+
```

**State Messages:**
- `positioning`: "Get into position" / "Make sure the camera can see your full body"
- `askingReady`: "Are you ready? Thumbs up to start" / gesture indicator with thumbs up/down icons
- `countdown(n)`: Large countdown number / "Get set!"
- `waitingToRetry(n)`: "No worries! Asking again in [n]..." / "Take your time"
- `exerciseActive`: (no overlay, HUD active)

**Personality-Specific Messages:**

*Ready messages (Good):*
- "Alright! Are you ready to crush this? Give me a thumbs up!"
- "Let's do this! Thumbs up when you're set!"
- "Looking good! Ready to go? Show me a thumbs up!"
- "Time to work! Thumbs up when you're ready, champ!"

*Ready messages (Drill):*
- "Are you ready or are you just standing there? THUMBS UP!"
- "I don't have all day. Thumbs up. NOW."
- "You better be ready. Thumbs up or get out."
- "Stop wasting time. Thumbs up if you've got the guts."

*Countdown messages (Good):*
- "Here we go!" / "Let's get it!" / "You've got this!"

*Countdown messages (Drill):*
- "No backing out now!" / "Pain is coming!" / "Time to suffer!"

*Decline messages (Good):*
- "No rush! Take your time." / "All good -- get comfortable first!" / "Whenever you're ready, no pressure!"

*Decline messages (Drill):*
- "Scared already? Fine, take a moment." / "Even my grandmother would be ready by now." / "You're stalling. I'll ask again."

*Retry messages (Good):*
- "Okay, let's try this again! Thumbs up?" / "Ready now? Show me that thumbs up!" / "Take two! Are you ready this time?"

*Retry messages (Drill):*
- "Back again. Thumbs up or I'm leaving." / "Last chance. Are you READY?" / "I SAID thumbs up. Do it."

**Haptic Integration:** Each countdown tick triggers `repTick()`. Transition to `exerciseActive` triggers `successRipple()`.

### VoiceCoachManager

Currently a **placeholder/stub**. Singleton with three async methods that are no-ops:

- `prefetchRepCounts(upTo:personality:)` -- future: pre-cache TTS audio for rep count numbers
- `playRep(count:)` -- future: speak rep count aloud
- `playMotivation(text:personality:)` -- future: speak motivational message

Designed for eventual ElevenLabs integration. Has a `@Published voiceError: String?` for displaying connection/API errors.

---

## 9. Coach Personalities

Two coach personalities are available, selectable by the user and persisted via `@AppStorage`:

### Coach Bennett ("The Good Coach")

- **Tagline**: "Believes in you more than you believe in yourself"
- **Accent Color**: `Theme.Colors.positive` (green: RGB 0.20/0.84/0.48)
- **Image Asset**: `CoachBennet` (references `Good_coach_Bennet.jpg`)
- **Communication Style**: Warm, supportive, encouraging. Uses positive reinforcement. Acknowledges struggle without judgment. Phrasing is specific and constructive.
- **Example Form Feedback**: "Try to go a bit deeper -- aim for thighs parallel!"
- **Example Motivation**: "Stay tight! Push through it!"

### Coach Fletcher ("The Drill Sergeant")

- **Tagline**: "Not quite my tempo. Were you rushing or dragging?"
- **Accent Color**: `Theme.Colors.danger` (red: RGB 1.0/0.30/0.26)
- **Image Asset**: `CoachFletcher` (references `Drill_Sargeant_Coach_Fletcher.jpg`)
- **Communication Style**: Brutal, condescending, aggressive. Uses shame and humor as motivation. Colorful language. Insults that are funny enough to be motivating rather than genuinely hurtful.
- **Example Form Feedback**: "That's a half rep at best. Get your ass DOWN!"
- **Example Motivation**: "Get moving you lazy sack of shit!"

### Where Personality Affects Behavior

| System | How Personality Changes It |
|---|---|
| Form feedback text | Each `FormRule` and `PositionalCheck` has `feedbackGood` and `feedbackDrill` strings |
| Motivation phrases | Separate phrase pools (12 good, 16 drill) |
| Ready-check messages | Different messages for every state transition |
| Motivation overlay tint | Good uses accent (amber), Drill uses danger (red) |
| Exertion threshold | Face effort > 0.6 lowers motivation threshold by 40% |

---

## 10. UI Components: Camera Session View

`TrainerSessionView` is the primary workout screen. It is a full-screen SwiftUI view with multiple layered components.

### Layer Stack (bottom to top)

**1. Camera Feed** (`cameraLayer`)
- `CameraPreviewView` displaying live `AVCaptureSession` preview
- Edge-to-edge, ignores safe area

**2. Skeleton Overlay** (`skeletonLayer`)
- `TrainerOverlayView` renders:
  - Body joint dots at 2D landmark positions
  - Bone connections between joint pairs (using `JointName.bonePairs`)
  - Angle arc overlays showing current degrees at each tracked joint vertex
  - Violated joints highlighted in red/amber when form rules fire
  - Hand skeleton(s) using 21-point landmarks and 23 bone pairs (supports 2 hands)

**3. Active-Session Glow Border** (`glowBorder`)
- `RoundedRectangle` stroke in Warm Amber with pulsing shadow
- 3pt border width, shadow radius oscillates between 8 and 18
- Pulses continuously using `.easeInOut(duration: 1.6).repeatForever(autoreverses: true)`
- Only visible when camera is running

**4. HUD Overlay** (`hudOverlay`)
- **Top-left**: Workout title (uppercase, 14pt heavy, 1.5 tracking, accent color). Shows "SIDE VIEW" banner if exercise requires side camera.
- **Top-right**: Rep counter or hold timer
  - **Rep Counter**: 96pt heavy rounded digit, monospacedDigit, with `.numericText()` content transition (smooth digit roll). Phase label below (IDLE/DOWN/UP) in 11pt heavy tracking.
  - **Isometric Hold Timer**: 100x100pt progress ring with timer digits (36pt heavy rounded) inside. Shows minutes:seconds format. Ring progress = holdDuration / targetSeconds. "HOLDING" / "PAUSED" / "GET SET" label.
- **Mid-screen**: Body visibility banner when `visibilityResult.isReady == false` during active exercise
- **Bottom**: Coach cue banner (capsule, 14pt bold white text, severity-colored fill), debug angle badge, form score badge, effort badge, bottom bar

**5. Ready-Check Overlay** (`readyCheckOverlay`)
- Semi-transparent black backdrop (0.4 opacity)
- Content varies by `WorkoutReadyCoordinator.state`:
  - `positioning`: Setup instruction text, side-view camera position guide (if applicable), visibility progress bar
  - `askingReady`: Gesture indicator (thumbs up = green + "Start", thumbs down = red + "Not yet"), state message (28pt heavy), subtitle, coach message bubble (capsule in personality accent color)
  - `countdown`: Large number (72pt heavy rounded) with `.numericText()` transition, "Get set!" subtitle
  - `waitingToRetry`: "No worries!" message with seconds remaining
- Transitions with `.opacity` animation

**6. Motivation Overlay** (`motivationOverlay`)
- Large text (32pt black rounded, -0.5 tracking) in personality tint color
- Triple shadow glow effect: `opacity(0.9) radius(20)`, `opacity(0.5) radius(40)`, `opacity(0.25) radius(60)`
- Spring pop-in animation: scales from 0.3 to 1.0 with `response: 0.4, dampingFraction: 0.5`
- Auto-dismisses after 3.5 seconds
- Hit-testing disabled (doesn't block touch events)

**7. Voice Error Banner** (`voiceErrorBanner`)
- Shows at top of screen if `VoiceCoachManager.voiceError` is non-nil
- 11pt bold monospaced white text on danger-colored background
- Transitions with move+opacity

### Data Flow in TrainerSessionView

On every frame:
1. `CameraManager.onFrame` delivers `CMSampleBuffer` to all three detectors
2. `PoseEstimator` updates `bodyJoints` and `worldJoints`
3. `HandGestureDetector` updates `currentGesture`
4. `FaceLandmarkerService` updates `blendshapes`

On `bodyJoints` change:
1. `BodyVisibilityChecker.evaluate()` determines if user is positioned correctly
2. Feeds visibility into `WorkoutReadyCoordinator` (bodyIsVisible/bodyLost)
3. If exercise is active: `UniversalRepCounter.processJoints()` produces rep count, phase, angles
4. `FormFeedbackEngine.evaluate()` checks biomechanical rules
5. If rep count increased: `MotivationEngine.evaluateEffort()` + voice rep count
6. Angle overlays and violated joints are rebuilt for skeleton rendering

On gesture change:
- Thumbs up -> `readyCoordinator.thumbsUpDetected()`
- Thumbs down -> `readyCoordinator.thumbsDownDetected()`

On blendshapes change:
- `ExertionAnalyzer.update(blendshapes:)` updates effort score

---

## 11. Home Dashboard & Navigation

### Body Categories

Four categories, each with its own icon and exercise list:

| Category | Icon | Subtitle | Exercise Count |
|---|---|---|---|
| Upper Body | `figure.arms.open` | "Chest, arms & shoulders" | 10 |
| Lower Body | `figure.strengthtraining.traditional` | "Quads, glutes & calves" | 10 |
| Full Body | `figure.run` | "Hit everything at once" | 7 |
| Yoga | `figure.yoga` | "Flexibility & balance" | 2 |

### Exercise Selection

Each category presents a list of `ExerciseOption` items. All 29 exercises are marked `available: true`. Selecting an exercise navigates to `TrainerSessionView` with the chosen exercise wrapped in a `WorkoutPlan`.

### Mock Workout Plans

Three pre-built workout plans for previews and first-launch content:

**Leg Day Essentials** (15 min)
- 3 sets of squats: 12, 12, 10 reps

**Upper Body Pump** (20 min)
- Bicep curls: 12 reps
- Push-ups: 15 reps
- Bicep curls: 10 reps
- Push-ups: 12 reps

**Full Body Quickie** (18 min)
- Squats: 10, Push-ups: 12, Bicep curls: 10 (x2 rounds)

### User Profile

Currently hardcoded: `UserProfile.firstName = "Satvik"`. No auth or profile management yet.

---

## 12. Known Limitations & Future Work

### Current Limitations

| Area | Limitation |
|---|---|
| **Voice Coaching** | `VoiceCoachManager` is a stub. ElevenLabs service is written but untested (corporate proxy blocks API). |
| **Authentication** | No login/signup. User profile is hardcoded. |
| **Persistence** | No workout history saved. No CoreData/CloudKit/Firebase. |
| **Demo Videos** | No exercise demonstration videos. Setup instructions are text-only. |
| **Camera Switching** | Camera defaults to front. Some exercises define `cameraPosition: .side` but the camera doesn't automatically switch orientation. User sees a "SIDE VIEW REQUIRED" banner instead. |
| **Push-ups on Front Camera** | Push-ups are kept on front camera as a pragmatic compromise even though side view would be more accurate for body line tracking. |
| **Onboarding** | No first-launch calibration or tutorial flow. |
| **ML Model Integration** | `WorkoutClassifier.mlproj` is trained but not integrated into the app. |
| **Device Testing** | Never tested on a real iPhone (USB data transfer blocked by corporate IT). Only tested via Mac camera in iPad simulator format. |
| **TestFlight** | Not yet deployed. Requires $99 Apple Developer Program enrollment. |
| **ElevenLabs API Key** | Hardcoded in `ElevenLabsService.swift` (security concern -- should be moved to Keychain or environment config). |

### Future Work Roadmap

1. **Voice coaching**: Unblock ElevenLabs on a non-corporate network, test TTS pipeline, implement audio queuing so voice doesn't overlap with music
2. **Authentication**: Sign in with Apple (mandatory for App Store if social login is included)
3. **Workout history**: Persist completed workouts with CoreData or CloudKit
4. **Exercise demo videos**: Generate or film short demonstration clips for each exercise
5. **Automatic camera guidance**: Use `cameraPosition` from exercise definition to prompt camera rotation
6. **Rest intervals**: "Great job. 60 seconds rest." with countdown chime
7. **Workout plans V2**: Personalized plans based on user profile, history, and preferences
8. **Pain safety override**: If user taps "Pain", stop the set and suggest alternatives
9. **RPE check**: Post-set "How hard was that?" (1-10) for intelligent training load management
10. **Onboarding calibration**: "Stand in frame, arms relaxed, 2 seconds" for body scale estimation

---

## 13. Key Architectural Decisions

### MediaPipe over Apple Vision

Apple's Vision framework (`VNDetectHumanBodyPoseRequest`) was used in V1 but abandoned because:
- Only 19 body points (MediaPipe gives 33)
- No 3D world coordinates (MediaPipe provides camera-independent 3D)
- No hand/gesture detection (MediaPipe has dedicated hand/gesture models)
- No face blendshapes (MediaPipe provides 52 ARKit-compatible coefficients)
- Less accurate landmark tracking, especially in low light

MediaPipe was chosen over QuickPose because:
- QuickPose is built on MediaPipe but adds a proprietary wrapper
- QuickPose had compiler issues with latest Xcode (confirmed by vendor as "unsolvable")
- MediaPipe is Apache 2.0 licensed (free, no usage limits)
- Direct access to all capabilities without SDK abstraction layers

### Data-Driven Exercise Definitions

Rather than writing a custom `RepCounter` class for each exercise (like `SquatRepCounter`), the architecture evolved to a single `UniversalRepCounter` that reads thresholds, form rules, and positional checks from `ExerciseDefinition`. This means:
- Adding a new exercise = adding one static definition to `ExerciseLibrary`
- No code changes to the rep counter, form engine, or overlay
- All biomechanical parameters are centralized and auditable
- Form rules carry personality-specific feedback text

### 3D World Landmarks Preferred, 2D Fallback

3D world coordinates (in meters, hip-center origin) are used for angle calculations whenever available because they are camera-independent. If the user turns slightly, 2D angles change but 3D angles remain accurate. The system falls back to 2D normalized coordinates when 3D data is missing for a given joint triple.

### "Effort" Heuristics over "Emotion Detection"

Early plans called for "sadness" or "tiredness" detection via facial expressions. This was abandoned because:
- At workout distance (6+ feet from camera), the face is too small for reliable emotion inference
- Classifying emotions is ethically problematic and medically meaningless
- Instead, the system uses "effort heuristics": brow furrow, eye squint, jaw clench, blink rate -- physical signals that correlate with exertion without requiring emotion labels
- Rep tempo decay is a more reliable fatigue signal than facial analysis

### EMA Smoothing + Hysteresis

Two layers of noise reduction prevent false rep counts:
- **EMA (alpha=0.4)**: Smooths raw angle values frame-to-frame
- **Hysteresis (2 frames)**: Phase transitions require 2 consecutive frames in the new phase
- **Min rep duration**: Exercises define minimum time between counts (0.2s for high knees to 1.0s for deadlifts)

### Single Accent Color (Warm Amber)

The design system uses exactly one chromatic accent color. The Gemini conversation explored options including "Cyberpunk Neon Green" and "Electric Cyan." The final choice was **Warm Amber** (RGB 1.0/0.69/0.0) because:
- Trophy gold / forge glow associations
- Not "health app green" (differentiator)
- High contrast against near-black backgrounds
- Warm enough to feel earned (not clinical)

### CocoaPods over SPM

MediaPipe Tasks Vision is distributed as CocoaPods pods, not Swift Package Manager packages. This necessitated:
- Ruby/CocoaPods installation (Conda vs system Ruby conflicts)
- Opening `.xcworkspace` instead of `.xcodeproj`
- Disabling user script sandboxing
- Manual xcframework copy phase management

### Framework Abstraction via JointName

No module outside `Vision/` imports MediaPipe directly. The `JointName` enum provides a framework-agnostic abstraction. If MediaPipe were ever replaced (e.g., with a future Apple Vision update), only the files in `Vision/` would need to change. The rest of the app (rep counters, form engines, overlays) consume `[JointName: CGPoint]` dictionaries and know nothing about MediaPipe.

---

## Appendix: File Checksums and Lines of Code

| File | Lines | Role |
|---|---|---|
| `ExerciseLibrary.swift` | 1807 | Exercise definitions (largest file) |
| `TrainerSessionView.swift` | 903 | Main workout screen |
| `UniversalRepCounter.swift` | 444 | Data-driven rep counter |
| `WorkoutData.swift` | 405 | Type definitions |
| `AngleCalculator.swift` | ~400 | Angle math + positional checks |
| `FormFeedbackEngine.swift` | 349 | Biomechanical form analyzer |
| `HandGestureDetector.swift` | ~350 | Hand/gesture detection |
| `WorkoutReadyCoordinator.swift` | 323 | Pre-exercise flow |
| `Theme.swift` | 238 | Design system |
| `SquatRepCounter.swift` | 235 | Legacy squat counter |
| `HapticsEngine.swift` | 230 | Haptic waveforms |
| `MotivationEngine.swift` | 200 | Fatigue/motivation |
| `RepCounterProtocol.swift` | 163 | Protocol + types |
| `ExertionAnalyzer.swift` | 147 | Face-based effort scoring |
| `FaceLandmarkerService.swift` | ~130 | Face landmark pipeline |
| `JointName.swift` | ~120 | Joint enum + bone pairs |
| `BodyVisibilityChecker.swift` | ~50 | Visibility validation |
| `VoiceCoachManager.swift` | 30 | Placeholder stub |

---

*This document was generated from the Spotter codebase at commit HEAD on the `main` branch of the `VirtualTrainer - mediapipe` repository. It reflects the complete state of the application as of April 2026.*
