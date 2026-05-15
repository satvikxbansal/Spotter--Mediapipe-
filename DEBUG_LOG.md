# Debug log (Spotter / VirtualTrainer)

Structured incident log for build failures, crashes, and bug fixes. **Format and categories:** `.cursor/rules/debugging.mdc` (section A).

- Append only — do not delete or rewrite past entries.
- Next entry ID: **DL-052** (after each append, the next agent reads the latest `### [DL-XXX]` and increments).

---

<!-- Entries: append new blocks below this line (newest at bottom). -->

---

### [DL-001] Disable Missing Swift Profile Runtime Linkage
**Date:** 2026-04-29  
**Severity:** build-breaking  
**Category:** xcode-config  
**File(s):** `VirtualTrainer.xcodeproj/project.pbxproj`

**Error:**
`Library '/Users/satvik.bansal/Library/Developer/Toolchains/swift-6.2-RELEASE.xctoolchain/usr/lib/clang/17/lib/darwin/libclang_rt.profile_ios.a' not found` and `Linker command failed with exit code 1`.

**Root Cause:**
The app/test build initially had coverage-style instrumentation enabled. After disabling project coverage, the **global Swift 6.2 release toolchain override** still injected `-fprofile-instr-generate` for the `My Mac (Designed for iPad)` / device-style build. That Swift 6.2 toolchain is missing the iOS profiling runtime archive, while Xcode's default toolchain does include it.

**Fix Applied:**
Disabled code coverage and GCC-style coverage instrumentation in the app and test target build settings by setting `CLANG_ENABLE_CODE_COVERAGE = NO`, `ENABLE_CODE_COVERAGE = NO`, `GCC_GENERATE_TEST_COVERAGE_FILES = NO`, and `GCC_INSTRUMENT_PROGRAM_FLOW_ARCS = NO`. Also added a target-level linker resource directory override so Swift 6.2's clang can resolve compiler runtimes from Xcode's complete default Clang runtime directory: `-resource-dir /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/17`.

**Prevention Rule:**
When using a custom Swift toolchain, verify both effective coverage settings and the actual linker invocation for each destination. If the toolchain lacks platform compiler runtimes, add a target-level `-resource-dir` override to Xcode's default Clang runtime directory or use the Xcode default toolchain for device builds.

**Pattern Tags:** #xcode-config #toolchain #linker #coverage

---

### [DL-002] Fix XCFramework MediaPipe Link Flags
**Date:** 2026-04-29  
**Severity:** build-breaking  
**Category:** cocoapods-build  
**File(s):** `Podfile`, `Pods/Target Support Files/Pods-VirtualTrainer/Pods-VirtualTrainer.debug.xcconfig`, `Pods/Target Support Files/Pods-VirtualTrainer/Pods-VirtualTrainer.release.xcconfig`, `VirtualTrainer.xcodeproj/project.pbxproj`

**Error:**
`ld: library 'MediaPipeTasksCommon' not found` and earlier `no such module 'MediaPipeTasksVision'`.

**Root Cause:**
CocoaPods generated aggregate linker flags using `-l"MediaPipeTasksCommon" -l"MediaPipeTasksVision"` while the MediaPipe pods are vendored XCFramework frameworks copied under `XCFrameworkIntermediates`. Xcode 26 / Swift 6.2 resolved the framework headers after search-path fixes, but the linker still searched for static libraries named `libMediaPipeTasksCommon` and `libMediaPipeTasksVision`.

**Fix Applied:**
Updated the `Podfile` post-install hook to rewrite the generated `Pods-VirtualTrainer` xcconfigs so MediaPipe is linked with `-framework "MediaPipeTasksCommon" -framework "MediaPipeTasksVision"` and the XCFramework intermediate framework paths are included in `FRAMEWORK_SEARCH_PATHS`. Re-ran `pod install` to regenerate the configs.

**Prevention Rule:**
For vendored XCFramework pods, verify that generated CocoaPods linker flags use `-framework` and include `$(PODS_XCFRAMEWORKS_BUILD_DIR)` framework search paths before debugging Swift imports.

**Pattern Tags:** #cocoapods-build #mediapipe-integration #xcframework #linker

---

### [DL-003] Resolve Strict Concurrency Warnings From Pure Counter Isolation
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** concurrency  
**File(s):** `VirtualTrainer/RepCounting/UniversalRepCounter.swift`, `VirtualTrainer/RepCounting/RepCounterProtocol.swift`, `VirtualTrainer/Models/ExerciseLibrary.swift`, `VirtualTrainer/Models/WorkoutData.swift`, `VirtualTrainer/Vision/AngleCalculator.swift`, `VirtualTrainer/Vision/JointName.swift`, `VirtualTrainer/Vision/BodyVisibilityChecker.swift`, `VirtualTrainer/Vision/FramePositionAnalyzer.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`

**Error:**
Warnings such as `Call to main actor-isolated static method 'definition(for:)' in a synchronous nonisolated context`, `Main actor-isolated static property 'squats' can not be referenced from a nonisolated context`, and `Call to main actor-isolated initializer 'init(repCount:phase:cues:holdDuration:isHolding:formScore:)' in a synchronous nonisolated context`.

**Root Cause:**
`UniversalRepCounter` was made `nonisolated` to avoid a Swift 6.2 simulator deallocation crash in pure unit tests, but the value models and stateless helpers it depends on were still implicitly `MainActor` because the project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The counter also still owned a UI haptic side effect.

**Fix Applied:**
Marked pure value/model/math types as `nonisolated`, including exercise definitions, workout models, `RepCounterOutput`, `FormScore`, `AngleCalculator`, `JointName`, visibility/framing helpers, and the rep protocol. Moved the rep haptic side effect from `UniversalRepCounter` to the already-main-actor `TrainerSessionView` rep increment path.

**Prevention Rule:**
If a pure logic class is marked `nonisolated`, all value models and stateless helpers it synchronously calls must also be nonisolated, and UI side effects must remain in main-actor UI/coordinator layers.

**Pattern Tags:** #concurrency #mainactor #rep-counter #strict-concurrency

---

### [DL-004] Clean Hand Gesture Strict Swift Warnings
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** swift-types  
**File(s):** `VirtualTrainer/Vision/HandGestureDetector.swift`

**Error:**
`Assuming you mean 'Optional<HandGesture>.none'; did you mean 'HandGesture.none' instead?` and `Initialization of immutable value 'thumbCMC' was never used`.

**Root Cause:**
Inside an optional-chained comparison, `.none` was ambiguous between `Optional.none` and the `HandGesture.none` enum case. The fallback hand pose analyzer also retained an unused `thumbCMC` local.

**Fix Applied:**
Changed the comparison/assignment to explicitly use `HandGesture.none` and removed the unused `thumbCMC` local.

**Prevention Rule:**
When an enum has a `.none` case and the expression is optional-chained, always spell the enum case explicitly as `EnumName.none`.

**Pattern Tags:** #swift-types #warnings #hand-gesture

---

### [DL-005] Align Skeleton Overlay With Aspect-Fill Camera Preview
**Date:** 2026-04-29  
**Severity:** critical  
**Category:** ui-layout  
**File(s):** `VirtualTrainer/Vision/PoseEstimator.swift`, `VirtualTrainer/UI/TrainerOverlayView.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`

**Error:**
Skeleton overlay looked rough and drifted from the body because `CameraPreviewView` uses `.resizeAspectFill`, while `TrainerOverlayView.screenPoint(_:)` mapped normalized MediaPipe coordinates directly with `x * width` and `y * height`.

**Root Cause:**
MediaPipe landmarks are normalized in the camera image coordinate space, but `.resizeAspectFill` scales that image to cover the SwiftUI view and crops whichever dimension exceeds the view. The overlay did not apply the same aspect-fill transform, so body and hand points drifted farther from the preview image as they moved away from center. The earlier smoothing change also fed smoothed joints into both overlay and rep counting, which risked adding lag to biomechanics.

**Fix Applied:**
Published the camera image aspect ratio from `PoseEstimator`, passed it into `TrainerOverlayView`, and mapped body joints, hand joints, and angle arcs through an aspect-fill rect matching the preview. Split pose outputs so `bodyJoints` remains raw for rep counting/form feedback while `overlayBodyJoints` is smoothed for visual rendering only.

**Prevention Rule:**
Whenever camera preview uses `.resizeAspectFill`, overlay coordinates must be mapped through the same aspect-fill displayed image rect; never map normalized camera coordinates directly to the full SwiftUI view bounds.

**Pattern Tags:** #ui-layout #camera-pipeline #overlay #coordinate-mapping

---

### [DL-006] Choose Best-Available Side By Landmark Visibility
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** angle-math  
**File(s):** `VirtualTrainer/Vision/PoseEstimator.swift`, `VirtualTrainer/Vision/AngleCalculator.swift`, `VirtualTrainer/RepCounting/UniversalRepCounter.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`, `VirtualTrainerTests/AngleCalculatorTests.swift`

**Error:**
`.bestAvailable` angle resolution preferred the right side whenever both left and right triples existed, even if the left-side landmarks had higher MediaPipe visibility.

**Root Cause:**
`AngleCalculator` had no access to per-joint visibility scores, so `.bestAvailable` could only choose based on whether a side's joint triple existed. When both existed it used a fixed right-side fallback, which could prefer a noisier side.

**Fix Applied:**
Published `jointVisibility` from `PoseEstimator`, passed it through `UniversalRepCounter` and `TrainerSessionView`, and updated `AngleCalculator` to choose the visible side with the stronger landmark triple score. Overlay side selection now uses the same visibility-aware logic. Added a unit test covering left-higher-visibility selection.

**Prevention Rule:**
Any side-selection strategy named “best available” must consider landmark confidence or visibility when both sides are geometrically available.

**Pattern Tags:** #angle-math #mediapipe-integration #visibility #side-selection

---

### [DL-007] Add 3D Biomechanics Paths For Valgus And Body Line
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** angle-math  
**File(s):** `VirtualTrainer/Vision/AngleCalculator.swift`, `VirtualTrainerTests/AngleCalculatorTests.swift`

**Error:**
Knee valgus and signed body-line checks were 2D-only even when MediaPipe world landmarks were available.

**Root Cause:**
`evaluateKneeValgus` ignored `joints3D`, and `computeAngles3D` forced `bodyLineAngle` through the 2D signed body-line path. This made frontal and sag/pike cues more sensitive to camera tilt and viewpoint than necessary.

**Fix Applied:**
Added a 3D knee-valgus approximation using hip-width-normalized lateral knee displacement along the user's hip axis, with the existing 2D FPPA-style check as fallback. Added 3D signed body-line measurement using hip displacement from the shoulder-to-ankle line, again preserving 2D fallback. Added tests for both 3D paths.

**Prevention Rule:**
If a form metric uses body geometry and `worldJoints` are available, implement the 3D path first and keep the 2D version only as a fallback.

**Pattern Tags:** #angle-math #biomechanics #3d-landmarks #form-feedback

---

### [DL-008] Remove Extra Segmentation Mask Pass
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** camera-pipeline  
**File(s):** `VirtualTrainer/Vision/FramePositionAnalyzer.swift`

**Error:**
`FramePositionAnalyzer.analyze(_:)` iterated all mask pixels once to compute body count and weighted sums, then iterated the mask again with `reduce` to compute `totalWeight`.

**Root Cause:**
The total weight was calculated after the main pixel loop even though each foreground mask value was already being read and converted in that loop.

**Fix Applied:**
Accumulated `totalWeight` inside the existing foreground-pixel loop and removed the second full-mask reduce pass. Existing frame-position output and tests remain unchanged.

**Prevention Rule:**
When scanning camera masks or frame buffers, compute all per-pixel aggregate values in the same pass unless there is a correctness reason to do otherwise.

**Pattern Tags:** #camera-pipeline #performance #segmentation-mask

---

### [DL-009] Cap Tempo Penalty Component
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** state-management  
**File(s):** `VirtualTrainer/RepCounting/UniversalRepCounter.swift`

**Error:**
Very slow reps could produce an unbounded tempo penalty component before the final form score cap was applied, making per-component debugging misleading.

**Root Cause:**
`calculateTempoPenalty()` multiplied slow-rep excess duration by `10.0` and returned the raw integer. Although the final score capped tempo penalty at 30, the component function itself could return much larger values.

**Fix Applied:**
Capped both fast and slow tempo penalty components at 30 inside `calculateTempoPenalty()` so the returned component matches the public scoring budget.

**Prevention Rule:**
Score component functions should return values within their documented component budget, not rely on downstream callers to cap them.

**Pattern Tags:** #state-management #rep-counter #form-score #tempo

---

### [DL-010] Prioritize Highest Severity Form Rule
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** state-management  
**File(s):** `VirtualTrainer/Coaching/FormFeedbackEngine.swift`, `VirtualTrainerTests/FormFeedbackEngineTests.swift`

**Error:**
`FormFeedbackEngine.checkFormRules` stopped at the first violated form rule, so a lower-severity rule listed earlier could mask a later critical rule in the same evaluation frame.

**Root Cause:**
The form-rule loop used `break` immediately after appending the first violation. Rule order was acting as implicit priority, which is fragile as compound exercise rules grow.

**Fix Applied:**
Changed form-rule evaluation to scan all eligible violated form rules and keep the highest-severity feedback. Ties preserve first-listed order. Added regression tests for critical-over-warning priority and equal-severity first-rule tie behavior. Marked `FormFeedbackEngine` and nested feedback value types as nonisolated to avoid Swift 6.2 simulator deallocation crashes in pure logic tests.

**Prevention Rule:**
When multiple coaching rules can trigger in one frame, choose by explicit priority/severity rather than by array ordering unless the ordering is intentionally documented and tested.

**Pattern Tags:** #state-management #form-feedback #severity #tests

---

### [DL-011] Add Russian Twist Metrics And Exercise Definition
**Date:** 2026-04-29  
**Severity:** warning  
**Category:** exercise-definitions  
**File(s):** `VirtualTrainer/Vision/AngleCalculator.swift`, `VirtualTrainer/Models/ExerciseLibrary.swift`, `VirtualTrainer/Models/WorkoutData.swift`, `VirtualTrainer/Coaching/FormFeedbackEngine.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`, `VirtualTrainerTests/AngleCalculatorTests.swift`, `VirtualTrainerTests/UniversalRepCounterTests.swift`

**Error:**
Russian Twist was requested as a new exercise with 3D transverse-plane trunk rotation, lean-back form rules, hip-rotation stability, asymmetry feedback, and rep counting via twist magnitude.

**Root Cause:**
The existing engine did not have trunk-rotation metrics or a hip-rotation positional check. It also needed the new positional check case wired into violated-joint highlighting to keep `TrainerSessionView` exhaustive.

**Fix Applied:**
Added `signedTrunkTwistAngle`, `trunkTwistMagnitude`, and `leanBackAngle` metrics to `AngleCalculator`, plus `hipRotationStability` positional checks. Registered `.russianTwist` in `ExerciseType`, added it to the full-body/core exercise list, and added a data-driven `ExerciseDefinition` with twist, lean-back, hip stability, tempo, and coach feedback rules. Added Russian Twist math and rep-count tests.

**Prevention Rule:**
When adding a new `PositionalCheck.CheckType`, update every switch over `checkType`, including UI highlighting helpers, in the same change.

**Pattern Tags:** #exercise-definitions #angle-math #form-feedback #tests

---

### [DL-012] Remove Unneeded Codable From Live Session Context
**Date:** 2026-05-04  
**Severity:** build-breaking  
**Category:** swift-types  
**File(s):** `VirtualTrainer/Models/LiveSessionContext.swift`

**Error:**
`Type 'LiveSessionContext' does not conform to protocol 'Decodable'` and `Type 'LiveSessionContext' does not conform to protocol 'Encodable'` because `CoachPersonality` did not conform to `Codable`.

**Root Cause:**
`LiveSessionContext` was introduced as transient runtime state for planned and free-analysis sessions, but it was marked `Codable`. Automatic Codable synthesis failed because the stored `coach: CoachPersonality` property was not Codable, and the context did not need persistence.

**Fix Applied:**
Removed `Codable` conformance from `SessionMode`, `SessionTarget`, and `LiveSessionContext`, keeping them as runtime-only `Equatable` values. Persisted onboarding/profile data remains in the dedicated Codable `UserProfile` model.

**Prevention Rule:**
Only mark new state models as `Codable` when they are actually persisted or serialized, and verify every stored property already conforms before relying on synthesized Codable.

**Pattern Tags:** #swift-types #state-management #session-context #tests

---

### [DL-013] Show Current Exercise In Live Session HUD
**Date:** 2026-05-05
**Severity:** cosmetic
**Category:** ui-layout
**File(s):** `VirtualTrainer/UI/TrainerSessionView.swift`

**Error:**
Planned workout sessions showed the plan title in the camera HUD, but not the current exercise name, making it hard to remember which movement to perform after tapping Start Session.

**Root Cause:**
`TrainerSessionView.workoutTitleLabel` rendered `context.title` as the primary HUD label. For planned sessions, `LiveSessionContext` sets `context.title` to the plan title, while the active exercise is stored separately in `context.exerciseType`.

**Fix Applied:**
Updated `TrainerSessionView.workoutTitleLabel` so the smaller eyebrow shows the plan/mode label, the prominent HUD line shows `exerciseType.displayName`, and the secondary detail line shows free-practice status or planned set/target information.

**Prevention Rule:**
When live-session context contains both a plan title and an active exercise, always render the active exercise as the most prominent camera HUD label.

**Pattern Tags:** #ui-layout #planned-workout #session-context #hud

---

### [DL-014] Harden Camera Startup And Readiness Lifecycle
**Date:** 2026-05-05
**Severity:** crash-risk
**Category:** camera-pipeline
**File(s):** `VirtualTrainer/Camera/CameraManager.swift`, `VirtualTrainer/Coaching/WorkoutReadyCoordinator.swift`, `VirtualTrainer/UI/CameraTabView.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`, `VirtualTrainerTests/WorkoutReadyCoordinatorTests.swift`

**Error:**
Repeated session starts or readiness-state drift could leave the app in a risky state: duplicate/partial camera configuration, a free-analysis start button bypassing the intended readiness state, or a countdown continuing after the body left frame.

**Root Cause:**
`CameraManager.configureSession()` only handled the happy path and did not clean up partially configured sessions. The free-analysis entry UI still exposed a debug-style bypass. `WorkoutReadyCoordinator.bodyLost()` only reset from `askingReady`, not from countdown/retry states.

**Fix Applied:**
Made camera configuration idempotent, cleaned partial session inputs/outputs before retrying, and made `startConfiguredSession()` report actual `session.isRunning`. Removed the free-analysis debug bypass, wired thumbs-up active state to auto-start while preserving manual start once the body is ready, and made body loss cancel countdown/retry before activation. Added regression tests for countdown and retry cancellation. Also moved free-analysis timer/peak effort reset to the actual exercise-active transition instead of view appearance.

**Prevention Rule:**
Treat camera and readiness transitions as state machines: repeated starts, partial setup, and body-loss transitions must be explicit and covered by tests.

**Pattern Tags:** #camera-pipeline #readiness #state-management #tests

---

### [DL-015] Fix Exertion Analyzer Sparse Blendshape False Positives
**Date:** 2026-05-05
**Severity:** warning
**Category:** emotion-detection
**File(s):** `VirtualTrainer/Coaching/ExertionAnalyzer.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`, `VirtualTrainerTests/ExertionAnalyzerTests.swift`

**Error:**
Sparse face-landmarker blendshape dictionaries could inflate effort by treating missing `jawOpen` as a clenched jaw. The first regression test for this also exposed a Swift 6.2 simulator teardown crash for short-lived actor-isolated classes.

**Root Cause:**
The exertion composite always included the inverse-jaw contribution even when `jawOpen` was absent, so missing data became effort. The analyzer was also more UI-observable than needed; effort state is only consumed by `TrainerSessionView`, not observed independently elsewhere.

**Fix Applied:**
Only include each facial signal when that blendshape is present, decay effort when no usable signal exists, and made `ExertionAnalyzer` a nonisolated pure logic object. `TrainerSessionView` now copies the latest effort into SwiftUI state after each face update, preserving HUD/motivation refresh without depending on analyzer observation. Added tests for sparse blendshape behavior and available-signal normalization.

**Prevention Rule:**
Never interpret missing model output as a strong positive signal. Normalize only over signals actually present in that frame.

**Pattern Tags:** #emotion-detection #mediapipe #state-management #tests

---

### [DL-016] Keep Highest-Severity Positional Feedback
**Date:** 2026-05-05
**Severity:** warning
**Category:** form-feedback
**File(s):** `VirtualTrainer/Coaching/FormFeedbackEngine.swift`, `VirtualTrainerTests/FormFeedbackEngineTests.swift`

**Error:**
Positional form checks could still stop at the first violation, allowing a lower-severity positional cue listed earlier to mask a more important later cue.

**Root Cause:**
The earlier severity-priority fix covered angle/form rules, but positional checks retained the old first-hit behavior.

**Fix Applied:**
Changed positional checks to collect eligible violations and return the highest-severity feedback, preserving first-listed order only for equal severity. Added a regression test mirroring the angle/form priority tests.

**Prevention Rule:**
All coaching feedback categories should use the same explicit severity ordering so rule-array order cannot accidentally suppress critical safety cues.

**Pattern Tags:** #form-feedback #biomechanics #severity #tests

---

### [DL-017] Stabilize Gesture, Voice, Model, And Legacy Counter Wiring
**Date:** 2026-05-05
**Severity:** warning
**Category:** integration
**File(s):** `VirtualTrainer/Vision/HandGestureDetector.swift`, `VirtualTrainer/Coaching/VoiceCoachManager.swift`, `VirtualTrainer/Services/ElevenLabsService.swift`, `VirtualTrainer/RepCounting/UniversalRepCounter.swift`, `VirtualTrainer/RepCounting/RepCounterProtocol.swift`, `download_models.sh`, `README.md`

**Error:**
Several integration edges could cause confusing behavior or stale maintenance paths: low-confidence gestures could influence readiness, rep-count fallback voice lines could ignore the selected coach personality after 20 reps, the model downloader omitted gesture/face models, a placeholder ElevenLabs API key remained in source, and the removed `SquatRepCounter` path still appeared in documentation/comments.

**Root Cause:**
Recent feature work centralized runtime counting in `UniversalRepCounter` and added face/gesture features, but some supporting scripts, docs, and fallback paths were not updated together.

**Fix Applied:**
Added confidence gates for gesture recognition, preserved coach personality for rep-count fallback speech, made ElevenLabs require an `ELEVENLABS_API_KEY` Info.plist value instead of a source placeholder, added gesture and face model downloads, and removed stale `SquatRepCounter` references/file. Verified all four MediaPipe task files are present locally and the workspace/pod test path builds through `VirtualTrainer.xcworkspace`.

**Prevention Rule:**
When adding or retiring a live pipeline component, update runtime code, scripts, docs, tests, and fallback behavior in the same pass.

**Pattern Tags:** #gesture-detection #voice-coach #mediapipe #rep-counter #dependencies

---

### [DL-018] Recheck Gesture Ordering And Face Effort Staleness
**Date:** 2026-05-05
**Severity:** warning
**Category:** state-management
**File(s):** `VirtualTrainer/Coaching/WorkoutReadyCoordinator.swift`, `VirtualTrainer/UI/CameraTabView.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`, `VirtualTrainerTests/WorkoutReadyCoordinatorTests.swift`

**Error:**
If a user held thumbs up before the readiness coordinator entered `askingReady`, the app could miss the gesture because the views only reacted to gesture value changes. Separately, if face detection disappeared after a high-effort frame, the current effort state could remain stale until blendshapes changed again.

**Root Cause:**
The readiness flow depended on event ordering between body visibility and gesture detection. The face-effort UI copied analyzer output into SwiftUI state, but only reset on blendshape updates, not on the explicit face-lost signal.

**Fix Applied:**
Centralized readiness gesture handling in `WorkoutReadyCoordinator.handleGesture(_:)`, passed the current gesture when the body first becomes visible, and rechecks the current gesture when the `askingReady` prompt appears. Reset the live effort score when `FaceLandmarkerService.faceDetected` becomes false. Added regression tests for held thumbs up/down as the body becomes visible.

**Prevention Rule:**
For live camera state machines, validate both value changes and ordering changes. A correct current value can still be missed if no new change event fires.

**Pattern Tags:** #gesture-detection #emotion-detection #readiness #state-management #tests

---

### [DL-019] Stabilize Planned Workout Coordinator Tests
**Date:** 2026-05-05
**Severity:** build-breaking
**Category:** state-management
**File(s):** `VirtualTrainer/Coaching/PlannedWorkoutCoordinator.swift`, `VirtualTrainer/UI/PlannedWorkoutSessionView.swift`, `VirtualTrainerTests/PlannedWorkoutCoordinatorTests.swift`

**Error:**
The first Phase 9A coordinator test run crashed with `malloc: *** error for object ... pointer being freed was not allocated` and `Test crashed with signal abrt`. After converting the coordinator to value semantics, the tests then failed to compile because mutating methods were called on `let` constants.

**Root Cause:**
`PlannedWorkoutCoordinator` was originally more observable than necessary for pure set sequencing state. Under the project-wide MainActor defaults, the short-lived `ObservableObject` test instances hit the same simulator teardown family already seen with other lightweight observable logic classes. Once the coordinator became a value type, the tests still treated it like a reference object.

**Fix Applied:**
Converted `PlannedWorkoutCoordinator` to a `nonisolated struct`, stored it in `PlannedWorkoutSessionView` with `@State`, and updated coordinator tests to use mutable `var` instances where set completion/advance methods mutate state.

**Prevention Rule:**
Keep pure workout/session sequencing logic value-based unless reference identity or independent observation is required. When changing a coordinator from reference semantics to value semantics, update tests and callers to make state mutation explicit.

**Pattern Tags:** #planned-workout #state-management #tests #concurrency

---

### [DL-020] Import Combine For Rest Timer Publisher
**Date:** 2026-05-05
**Severity:** build-breaking
**Category:** swiftui-views
**File(s):** `VirtualTrainer/UI/RestScreenView.swift`

**Error:**
`Instance method 'autoconnect()' is not available due to missing import of defining module 'Combine'`.

**Root Cause:**
`RestScreenView` used `Timer.publish(every:on:in:).autoconnect()` for the rest countdown while only importing SwiftUI. The `autoconnect()` publisher helper is defined by Combine, so the new view failed to compile during the planned-workout test build.

**Fix Applied:**
Added `import Combine` to `VirtualTrainer/UI/RestScreenView.swift` so the timer publisher chain resolves correctly.

**Prevention Rule:**
When a SwiftUI view uses `Timer.publish(...).autoconnect()` or other publisher operators directly, import `Combine` in that file instead of relying on transitive imports.

**Pattern Tags:** #swiftui-views #combine #build

---

### [DL-021] Strictly Validate Planned Set Completion Summaries
**Date:** 2026-05-05
**Severity:** warning
**Category:** state-management
**File(s):** `VirtualTrainer/Coaching/PlannedWorkoutCoordinator.swift`, `VirtualTrainerTests/PlannedWorkoutCoordinatorTests.swift`

**Error:**
Planned workout set completion accepted any summary with the matching plan id, exercise index, and set index, leaving target, exercise type, total set count, and total exercise count unchecked.

**Root Cause:**
`PlannedWorkoutCoordinator.completeCurrentSet(with:)` validated only positional identifiers. A stale or mismatched `PlannedWorkoutSetSummary` could advance the coordinator into rest or completion while carrying the wrong active exercise or target metadata.

**Fix Applied:**
Tightened `completeCurrentSet(with:)` so the summary must match the active exercise type, active target, current global exercise index, current set index, total sets for the active exercise, and total exercises in the plan. Added regression coverage that rejects mismatched exercise and target summaries while preserving valid rest advancement.

**Prevention Rule:**
When a coordinator consumes a child-view completion summary, validate both identity and payload metadata before mutating lifecycle state.

**Pattern Tags:** #planned-workout #state-management #tests

---

### [DL-022] Stop Live Camera Pipeline Before Planned Exit Paths
**Date:** 2026-05-05
**Severity:** warning
**Category:** camera-pipeline
**File(s):** `VirtualTrainer/UI/TrainerSessionView.swift`

**Error:**
Planned workout cancel and free-analysis Done relied on SwiftUI disappearance to stop camera capture, while planned set completion had its own inline camera stop logic.

**Root Cause:**
Camera cleanup was split across multiple call sites. Exit paths that dismissed immediately still cleaned up on `onDisappear`, but the frame handler was not cleared through one shared lifecycle method before every explicit end/cancel/complete action.

**Fix Applied:**
Added `stopLivePipelines()` in `TrainerSessionView` to clear `cameraManager.onFrame` and stop the `AVCaptureSession`, then reused it for view disappearance, free-analysis Done, planned session cancel, and planned set completion.

**Prevention Rule:**
All live camera session exit paths should call one shared cleanup helper before dismissing or advancing lifecycle state.

**Pattern Tags:** #camera-pipeline #planned-workout #lifecycle

---

### [DL-023] Model Rest Timer Completion Explicitly
**Date:** 2026-05-05
**Severity:** warning
**Category:** swiftui-views
**File(s):** `VirtualTrainer/UI/RestScreenView.swift`, `VirtualTrainer/UI/PlannedWorkoutSessionView.swift`, `VirtualTrainerTests/PlannedWorkoutCoordinatorTests.swift`

**Error:**
When a planned workout rest timer reached zero, the rest screen still presented the countdown as `0 Seconds Left` and the parent continuation path duplicated the child button haptic.

**Root Cause:**
The rest screen treated zero as a numeric countdown value rather than a distinct completion state. The start action also triggered feedback in both the child rest view and the parent planned workout view.

**Fix Applied:**
Added a one-shot rest-complete signal, changed the zero-second label to `Rest Complete`, changed the header action to `Start Now`, reset the completion signal when `+15 sec` is added after zero, and removed the duplicate parent haptic. Added target-variant lifecycle assertions so rest durations are checked after hold, timed, and AMRAP-style sets.

**Prevention Rule:**
Countdown flows should represent zero as an explicit state, and nested SwiftUI action closures should keep haptic/audio feedback owned by one layer.

**Pattern Tags:** #planned-workout #rest-screen #swiftui-views #state-management #tests

---

### [DL-024] Clear Readiness Camera Frame Handler Before Workout Handoff
**Date:** 2026-05-05
**Severity:** warning
**Category:** camera-pipeline
**File(s):** `VirtualTrainer/UI/CameraTabView.swift`

**Error:**
The readiness camera stopped capture before entering free analysis, but its `onFrame` callback was not cleared through a shared helper before the trainer session camera took ownership.

**Root Cause:**
Readiness cleanup and workout startup each stopped the `CameraManager` directly. That left the frame callback lifecycle less explicit during full-screen handoff to `TrainerSessionView`.

**Fix Applied:**
Added `stopReadinessCamera()` to clear `cameraManager.onFrame` and stop capture together, then used it on readiness disappearance and immediately before presenting the free-analysis trainer session.

**Prevention Rule:**
Every camera owner handoff should clear frame callbacks before presenting or starting the next camera owner.

**Pattern Tags:** #camera-pipeline #readiness #lifecycle

---

### [DL-025] Align iOS Deployment Target And Clear Invalid Camera Entitlement
**Date:** 2026-05-05
**Severity:** warning
**Category:** xcode-config
**File(s):** `Podfile`, `Podfile.lock`, `VirtualTrainer.xcodeproj/project.pbxproj`, `VirtualTrainer/VirtualTrainer.entitlements`

**Error:**
The app and test project targets were configured with `IPHONEOS_DEPLOYMENT_TARGET = 26.2`, while the product and project rules target iOS 17+. The iOS entitlements file also contained the macOS sandbox camera entitlement `com.apple.security.device.camera`.

**Root Cause:**
The Xcode project carried a current-SDK deployment target instead of the intended app minimum, and the entitlement file retained a macOS camera sandbox key. On iOS, camera access is controlled by the `NSCameraUsageDescription` privacy string rather than that macOS entitlement.

**Fix Applied:**
Set the app, test, and Pods deployment target to iOS 17.0, ran `pod install` so CocoaPods generated settings and the lockfile checksum stayed aligned, and removed the invalid camera entitlement while preserving the entitlements file reference. Verified the built simulator app now reports `MinimumOSVersion = 17.0` and an empty entitlement dictionary.

**Prevention Rule:**
Keep app targets, test targets, Podfile settings, generated Pods settings, and platform privacy/entitlement models aligned with the real supported OS floor before declaring device readiness.

**Pattern Tags:** #xcode-config #cocoapods #deployment-target #entitlements

---

### [DL-026] Preserve Target Style During Exercise Swaps
**Date:** 2026-05-05
**Severity:** warning
**Category:** state-management
**File(s):** `VirtualTrainer/Services/PlanSwapService.swift`, `VirtualTrainerTests/WorkoutPreviewTests.swift`

**Error:**
Exercise swapping could replace an isometric hold exercise with a rep-based exercise that shared the same movement pattern, while retaining the original hold target.

**Root Cause:**
Swap candidate filtering matched movement pattern, equipment, difficulty, unilateral status, bodyweight constraints, and camera capability, but did not require the replacement exercise to preserve the same target style as the original exercise.

**Fix Applied:**
Added an isometric target-style parity check to the swap candidate filter and covered it with a regression test using a wall-sit hold plan. Hold/isometric exercises now only swap with compatible hold/isometric exercises.

**Prevention Rule:**
Planned workout substitutions must preserve target semantics as well as movement and equipment constraints so the session lifecycle receives coherent rep, hold, timed, or AMRAP targets.

**Pattern Tags:** #planned-workout #plan-swaps #targets #tests

---

### [DL-027] Avoid Main-Actor Store Deinit Crash In History Tests
**Date:** 2026-05-05
**Severity:** warning
**Category:** concurrency
**File(s):** `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainerTests/WorkoutHistoryStoreTests.swift`

**Error:**
Phase 10 history-store unit tests compiled but crashed with `Test crashed with signal abrt` during `WorkoutHistoryStore.__deallocating_deinit` on the iPhone 17 simulator.

**Root Cause:**
`WorkoutHistoryStore` is a short-lived `@MainActor ObservableObject` in the new unit tests. Under the current Swift 6.2 simulator/back-deploy runtime, tearing down that main-actor isolated observable store at test method exit routed through the actor deinit path and aborted before assertions could complete.

**Fix Applied:**
Added an explicit `nonisolated deinit {}` to `WorkoutHistoryStore` and reran the focused Phase 10 tests plus the full workspace test suite. The new history persistence tests now pass without teardown crashes.

**Prevention Rule:**
When adding a test-created main-actor observable store, give teardown an explicit nonisolated deinit or separate the persistence core from the observable wrapper so unit-test lifetime cleanup does not depend on main-actor deinit back-deploy behavior.

**Pattern Tags:** #concurrency #observableobject #tests #history

---

### [DL-028] Roll Back In-Memory History On Persistence Failure
**Date:** 2026-05-05
**Severity:** warning
**Category:** persistence
**File(s):** `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainerTests/WorkoutHistoryStoreTests.swift`

**Error:**
If `WorkoutHistoryStore.addSummary(_:)` failed to write the JSON file, the failed summary could still remain visible in the store's in-memory `summaries` list for the current app run.

**Root Cause:**
The store appended or replaced the summary before calling `persist()`, then returned the persistence result directly. A failed write set `persistenceError`, but it did not restore the previous in-memory array.

**Fix Applied:**
Preserved the previous summary list before mutation and restored it when persistence fails. Added a regression test that uses an unwritable history path and verifies failed saves do not appear in fetch-by-id or recent-history results.

**Prevention Rule:**
Local persistence APIs should keep memory and disk semantics aligned: if a user-facing save returns failure, rollback observable state or make the partial in-memory state explicit.

**Pattern Tags:** #history #persistence #tests

---

### [DL-029] Keep Isometric Hold Time Separate From Rep Counts
**Date:** 2026-05-06
**Severity:** critical
**Category:** rep-counter
**File(s):** `VirtualTrainer/RepCounting/UniversalRepCounter.swift`, `VirtualTrainerTests/UniversalRepCounterTests.swift`

**Error:**
Plank, wall-sit, yoga pose, and other isometric exercises could report elapsed hold seconds through `repCount` because `processIsometric` returned `repCount: Int(liveHold)`. That made hold seconds look like reps to downstream session summaries, rep-quality evidence, haptics/voice rep-count paths, and any rep-based dashboard aggregation.

**Root Cause:**
The isometric state machine measured hold time correctly in `holdDuration`, but it also overloaded the generic `repCount` output with that same live hold duration. A missing primary-angle frame during an active isometric hold also returned the generic fallback output, which did not preserve/pause hold semantics cleanly.

**Fix Applied:**
Changed isometric counter output to return the real internal `repCount` while exposing hold progress only through `holdDuration` and `isHolding`. Added a shared live-hold-duration helper, and when primary-angle data is missing during an isometric hold, the counter now banks elapsed hold time, pauses the hold, and returns the preserved duration without continuing to accrue time while posture evidence is absent. Added regression tests for hold duration not polluting rep count and for missing-angle pause behavior.

**Prevention Rule:**
Never use `repCount` as a transport for timed/isometric progress. Timed progress must flow through `holdDuration` or elapsed session time, and missing pose evidence during a hold should pause timing rather than silently crediting unobserved seconds.

**Pattern Tags:** #rep-counter #isometric #hold-timer #planned-workout #tests

---

### [DL-030] Reset Live Session Engines At Session Start
**Date:** 2026-05-06
**Severity:** warning
**Category:** state-management
**File(s):** `VirtualTrainer/UI/TrainerSessionView.swift`

**Error:**
Re-entering a trainer session could briefly carry stale live UI/session state such as rep count, phase, hold duration, form score, angle overlays, cue history, rep-quality events, motivation scale, exertion smoothing, or form-feedback cooldowns from a previous view lifetime.

**Root Cause:**
`TrainerSessionView` owns several `@State` values and long-lived helper engines. SwiftUI can reuse view state across appearances, while only some camera/gesture/coordinator resources were reset on disappear. The visible form-score reset was not enough to reset the underlying form, exertion, and motivation engines.

**Fix Applied:**
Expanded `.onAppear` initialization to reset scalar live state, cue/evidence buffers, overlays, hold state, form score, motivation scale, and the exertion/motivation/form engines before creating the fresh `UniversalRepCounter` and starting camera, pose, hand, and face pipelines.

**Prevention Rule:**
For camera-driven workout screens, reset both displayed state and the helper engines that produce it at session start. Do not rely only on disappear-time cleanup, because SwiftUI view identity and navigation timing can keep old state alive.

**Pattern Tags:** #state-management #trainer-session #form-feedback #effort #rep-evidence

---

### [DL-031] Guard Empty Voice Rep Prefetch Range
**Date:** 2026-05-06
**Severity:** warning
**Category:** crash-prevention
**File(s):** `VirtualTrainer/Coaching/VoiceCoachManager.swift`

**Error:**
Calling `prefetchRepCounts(upTo: 0, personality:)` or passing a negative count could build the invalid range `1...count`, which traps in Swift before a workout starts.

**Root Cause:**
The voice coach assumed all callers would prefetch at least one rep phrase. Hold/timed/open-ended sessions and future target plumbing can reasonably produce zero rep targets.

**Fix Applied:**
Added an early guard for `count > 0`, clearing `repPhrases` and returning before constructing the closed range.

**Prevention Rule:**
Any range built from user, plan, or target counts must guard the lower/upper bounds before constructing a closed range. Prefer empty collections for zero-work cases.

**Pattern Tags:** #crash-prevention #voice-coach #range #planned-workout

---

### [DL-032] Bridge 10.5E Foundation Audit
**Date:** 2026-05-06
**Severity:** warning
**Category:** audit
**File(s):** `README.md`, `VirtualTrainer/Camera/CameraManager.swift`, `VirtualTrainer/Services/ElevenLabsService.swift`, `VirtualTrainer.xcodeproj/project.pbxproj`

**Error:**
The docs still described Phase 9 coordinator/rest/history work as upcoming, the camera privacy copy did not explicitly state the no-storage/no-upload boundary, and the camera frame handler could be cleared from SwiftUI lifecycle code while the capture queue was still delivering late frames.

**Root Cause:**
Phase 9/10/10.5 implementation moved faster than the README, and the camera manager exposed its frame callback as a plain mutable closure shared between the main lifecycle path and the video-output queue.

**Fix Applied:**
Updated the README to reflect planned sessions, rest, summaries/history, calibration, Quick Start deck cycling, deferred plan-detail swapping, current Phase 11/13/14 direction, and the local privacy/storage boundary. Hardened the generated camera permission string, added a backend-secrets note to the dormant ElevenLabs client, and made `CameraManager` frame-handler access lock-protected. Re-ran secret/privacy scans, `xcodebuild test`, and `xcodebuild build` on the iPhone 17 simulator.

**Prevention Rule:**
After each bridge, docs should be checked against the actual current user flow, and camera lifecycle state shared across capture queues should be synchronized before adding more planned-workout or insight surfaces.

**Pattern Tags:** #audit #privacy #docs #camera #crash-prevention

---

### [DL-033] Harden AI Coach Derived Signal Accuracy
**Date:** 2026-05-06
**Severity:** warning
**Category:** insight-accuracy
**File(s):** `VirtualTrainer/Services/SignalExtractor.swift`, `VirtualTrainer/Services/InsightCandidateBuilder.swift`, `VirtualTrainer/Services/InsightNarrativeBuilder.swift`, `VirtualTrainerTests/InsightEngineTests.swift`

**Error:**
The new derived AI Coach signals had a few accuracy risks: string status parsing could read `not ready to progress` as ready, rest-response logic could call already-clean post-rest sets a failed recovery, cue-cluster evidence could pull in camera-framing cues, and rest skipped early was being treated like skipped work.

**Root Cause:**
The insight layer was inferring coaching status from broad text matching and reused existing `skipped` naming without accounting for the current planned-workout rest model, where that field means an early rest skip. Some derived signals also accepted too little scored quality evidence for progression/PR-style claims.

**Fix Applied:**
Made status mapping type-aware, required reliable scored quality samples for positive target/progression/quality-PR claims, tightened rest-response thresholds, required cue clusters to span multiple sessions with distinct non-camera cues, and changed early-rest-skip copy/actions away from skipped-work language. Added regression tests for blocked progression routing, rest-response false positives, and early rest skips not becoming target-aggressive signals.

**Prevention Rule:**
Deterministic coach insights should prefer explicit typed status over parsing prose, require enough scored evidence before positive progression claims, and preserve the exact semantics of workout summary fields before turning them into coaching recommendations.

**Pattern Tags:** #insight-accuracy #ai-coach #training-signals #rest-timing #tests

---

### [DL-034] Add Local Tombstones For Workout Deletes
**Date:** 2026-05-07
**Severity:** warning
**Category:** persistence
**File(s):** `VirtualTrainer/Models/WorkoutSessionSummary.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/AIInsightModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/UI/WorkoutDetailSheetView.swift`, `VirtualTrainer/UI/ProfileView.swift`

**Error:**
Workout history had no user-facing delete path, and any future hard local delete could be resurrected by another device once offline-first sync is added.

**Root Cause:**
`WorkoutHistoryStore` used its published visible summaries as the persisted source of truth. Removing an item from that array would also remove all local evidence that a delete happened.

**Fix Applied:**
Added backwards-compatible `deletedAt` fields and tombstone helpers to syncable local models, split workout history into an all-record source of truth plus a non-deleted SwiftUI projection, persisted tombstones in `WorkoutHistory.json`, added local delete/restore/purge and sync/debug queries, and invalidated AI insights that reference a deleted workout while preserving delivery and engagement records. Trophy recompute keeps already-earned trophy state; C6 remains responsible for canonical trophy unlock/retraction events.

**Prevention Rule:**
User-facing deletes for future syncable local records should write tombstones first, keep default UI queries on non-deleted projections, and preserve dependent behavior signals unless the product explicitly defines a separate deletion lifecycle.

**Pattern Tags:** #persistence #soft-delete #sync-prep #insights #history

---

### [DL-035] Recover Simulator SpringBoard Crash Loop After Successful Build
**Date:** 2026-05-08
**Severity:** warning
**Category:** xcode-simulator
**File(s):** `DEBUG_LOG.md`

**Error:**
Xcode build succeeded, then Run failed with `Simulator device failed to launch satvik.VirtualTrainer`, `NSPOSIXErrorDomain Code=64`, `BSErrorCodeDescription = host down`, and `The system shell probably crashed`. The simulator also showed `SpringBoard quit unexpectedly`.

**Root Cause:**
The failing iPhone 17 Pro simulator device (`0442BD6F-881D-451A-B764-815DCAD3F78A`) had SpringBoard in a crash loop, not an app launch crash. Fresh crash reports were `SpringBoard-2026-05-08-1711xx.ips` / `SpringBoard-2026-05-08-1713xx.ips`; no matching fresh `VirtualTrainer` crash report existed. The SpringBoard stack crashed in Apple simulator/system-shell code: `FBSDisplayMonitor -> FBDisplayManager -> FBSystemShellInitialize -> SBSystemAppMain`, with `EXC_BREAKPOINT / SIGTRAP`. `launchctl print` reported `successive crashes = 15`, and `simctl launch` failed outside Xcode with the same system-shell message, confirming Xcode was talking to a broken simulator shell rather than hitting app code.

**Fix Applied:**
Verified the current built `VirtualTrainer.app` could install and launch on a freshly created iPhone 17 Pro simulator, returning a real process id. Then recovered the original simulator non-destructively with `xcrun simctl shutdown 0442BD6F-881D-451A-B764-815DCAD3F78A`, `xcrun simctl boot 0442BD6F-881D-451A-B764-815DCAD3F78A`, `xcrun simctl bootstatus ... -b`, and `xcrun simctl launch ... satvik.VirtualTrainer`, which launched successfully with pid `11985`. Cleaned up the temporary smoke-test simulator afterwards.

**Prevention Rule:**
When build succeeds but Run fails with `NSPOSIXErrorDomain Code=64` / `host down`, first inspect `~/Library/Logs/DiagnosticReports/SpringBoard-*.ips` and `~/Library/Logs/CoreSimulator/CoreSimulator.log` before rolling back app code. Use `simctl launch` and, if needed, a fresh simulator to distinguish app crashes from SpringBoard/runtime crashes. Recovery order: shutdown/boot the affected simulator, then erase/recreate only if SpringBoard continues crashing. If `simctl launch` works but Xcode Run still fails, temporarily disable View Debugging insertion for the scheme.

**Pattern Tags:** #xcode-simulator #springboard #crash-loop #launch-failure #rca

---

### [DL-036] Preserve Canonical Backend-Readiness Fields In Recaps And Calibration
**Date:** 2026-05-08
**Severity:** warning
**Category:** persistence
**File(s):** `VirtualTrainer/Services/WeeklyRecapBuilder.swift`, `VirtualTrainer/Models/CalibrationRecord.swift`, `VirtualTrainerTests/WeeklyRecapBuilderTests.swift`, `VirtualTrainerTests/CalibrationStoreTests.swift`

**Error:**
Weekly recaps still read trophy top moments from `newlyEarnedEvents`, which is now transient UI feedback after canonical trophy unlock logs were added. Separately, `CalibrationRecord.copy(...)` did not pass through `serverCompletedAt`, so account-claim, tombstone, or restore helpers could silently discard the future server completion timestamp.

**Root Cause:**
C6 made `TrophyUnlockEvent` canonical, but `WeeklyRecapBuilder` was not updated to consume `unlockEventLog`. The calibration copy helper was added before `serverCompletedAt` preservation was covered by regression tests.

**Fix Applied:**
Updated weekly recap top-moment selection to read non-retracted canonical unlock events, falling back to `newlyEarnedEvents` only for legacy snapshots that do not have an event log. Updated calibration copy semantics to preserve `serverCompletedAt`. Added regression tests for both behaviors and verified focused tests, the full workspace test suite, simulator build, bundled MediaPipe task resources, and a simulator launch smoke.

**Prevention Rule:**
Derived UI surfaces should read canonical event logs once a model has one, not transient presentation arrays. Copy helpers for backend-ready models must pass through server timestamps and metadata fields, with explicit tests for account-claim and tombstone paths.

**Pattern Tags:** #persistence #sync-prep #weekly-recap #calibration #tests

---

### [DL-037] Move Local JSON Writes Behind Persistence Actor
**Date:** 2026-05-09
**Severity:** warning
**Category:** persistence
**File(s):** `VirtualTrainer/Models/PersistenceActor.swift`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/Models/ThemeStore.swift`, `VirtualTrainer/Models/LocalWriteJournal.swift`

**Error:**
Local JSON encode/write work still lived on the same main-actor store paths that publish SwiftUI state. That was acceptable with low-frequency local saves, but it would risk visible UI stalls once repository retries and backend listeners start increasing write frequency.

**Root Cause:**
The stores had grown backend-ready metadata, tombstones, operation IDs, trophy events, and insight delivery records while still writing each file directly from store methods. One rollback path in `OnboardingStore.save(...)` also returned success after an async persist failure, which hid a write failure from callers.

**Fix Applied:**
Added `PersistenceActor` for file reads, atomic writes, removes, directory creation, JSON encoding, and coalesced same-file writes with last-write-wins behavior. Refactored onboarding, workout history, trophies, insights, calibration, theme, and the local write journal to route encode/write work through actor persistence while preserving main-actor published state and rollback behavior. Kept camera analysis, planned workouts, deterministic plan generation, stats, trends, trophies, recaps, and local AI insights intact. Added persistence actor tests and migrated store tests to await async save/selection paths.

**Prevention Rule:**
Backend-scale local stores should keep `@Published` state main-actor isolated, but encode/write/remove work should flow through the persistence actor. Failed writes must return failure and preserve the previous published state; rapid repeated writes should coalesce instead of flooding the file system.

**Pattern Tags:** #persistence #concurrency #sync-prep #mainactor #tests

---

### [DL-038] Preserve Store Mutation Composition During Coalesced Async Writes
**Date:** 2026-05-10
**Severity:** warning
**Category:** persistence
**File(s):** `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/Models/ThemeStore.swift`, `VirtualTrainer/Models/LocalWriteJournal.swift`

**Error:**
The first async persistence pass moved some stores to apply state only after actor writes completed. In bursty paths, two quick mutations could both build from the same pre-mutation state before the first write resumed, so a coalesced final write could drop one local change.

**Root Cause:**
`await writeJournal.contains(...)` introduced a suspension point before the local mutation was visible in memory. The old synchronous stores applied local state before writing and rolled back on failure; the async refactor needed to preserve that composition behavior while still moving encode/write work off the main actor.

**Why It Was Missed In The First Pass:**
The first pass validated compile safety, actor-backed file writes, atomic behavior, rollback paths, and existing sequential store tests, but it did not add enough concurrent same-store mutation coverage. Most existing tests used `await` between calls, which means each mutation finished before the next one started. That hid the real app pattern where two UI or future repository-triggered writes can be launched back-to-back before the first async write resumes.

The review also focused on whether JSON encode/write work left the `MainActor`, but the deeper semantic requirement was that store mutations must still compose exactly like the old synchronous code. Context compaction made that easier to miss because the old ordering rule was implicit in the pre-refactor stores rather than written as a test: mutate local state first, then persist, then rollback if persistence fails.

**Fix Applied:**
Restored optimistic local mutation before persistence for profile, history, theme, calibration, trophy, and insight write paths, with duplicate-operation rollback and persisted-baseline rollback on write failure where needed. Updated `LocalWriteJournal` to load once per actor instance and keep in-memory pending entries so concurrent records compose before the final coalesced write. Added rapid-write regression tests for workout history, onboarding profile updates, and the local write journal.

**Prevention Rule:**
When adding `await` to a previously synchronous store mutation, make sure the in-memory mutation either happens before the first suspension point or is protected by an explicit serial mutation model. Coalescing file writes is safe only if later writes are built from the latest local state. Every async store refactor for append, merge, or update behavior should include a rapid concurrent mutation regression test, not only sequential awaited tests.

**Pattern Tags:** #persistence #concurrency #mainactor #rollback #tests

---

### [DL-039] Harden Local Compliance Export And Delete Against Queued Writes
**Date:** 2026-05-10
**Severity:** warning
**Category:** audit
**File(s):** `VirtualTrainer/Models/PersistenceActor.swift`, `VirtualTrainer/Services/AccountDeletionService.swift`, `VirtualTrainer/Services/DataExportService.swift`, `VirtualTrainerTests/ComplianceServicesTests.swift`, `VirtualTrainerTests/PersistenceActorTests.swift`

**Error:**
The first local-mode compliance pass added Profile export/delete, a PII registry, and tests, but the audit found two coverage gaps. Export read local JSON directly without first waiting for coalesced `PersistenceActor` writes to settle, and deletion removed files without explicitly waiting for queued actor writes that could recreate a file after the wipe in a tight async race. The PII registry test also checked the registry's manually maintained profile-field list against registry entries, but did not compare the registry to an actually encoded `UserProfile`.

**Root Cause:**
The compliance services were added as storage-bound scaffolding around existing local JSON files, but the previous persistence phase had changed the storage contract from direct synchronous writes to actor-coalesced async writes. That means file-level export/delete services must coordinate with the persistence actor, not only with `FileManager`. The PII test treated `PIIRegistry.currentProfileFieldIDs` as the source of truth instead of using encoded profile keys as an independent check.

**Why It Was Missed In The First Pass:**
The first pass verified the steady-state product behavior: files existed, export contained the expected archive entries, JSON decoded, deletion removed expected files, deletion was idempotent, and reloaded stores returned to onboarding. That missed the narrower race where a queued write can still be in the persistence actor when export/delete begins. Context compaction also made the relationship between the new compliance services and the immediately prior actor-persistence work easier to underweight, because the compliance prompt focused on account-readiness surfaces while the hidden coupling lived in the persistence implementation.

The PII coverage miss happened for a similar reason: the test proved the written registry was internally complete, but not that it stayed complete against the real encoded profile model. The safer test needed an independent encoded-profile key set.

**Fix Applied:**
Added `PersistenceActor.waitForWrites(to:)` and `removeAfterQueuedWrites(at:)`. `DataExportService` now waits for queued writes on profile, workouts, trophies, insights, calibration, and theme before reading files. `AccountDeletionService` now waits for queued writes before removing each local file/cache path and yields around write-journal deletion so late write-journal records created by just-finished store writes are also cleared. Strengthened compliance tests so a fully populated encoded `UserProfile` must match the PII registry profile-field list, and added persistence actor coverage for the queued-write-aware remove helper. Re-ran focused compliance and persistence tests after the patch.

**Prevention Rule:**
Any new file-level export, delete, migration, or audit service must be reviewed against the active persistence mechanism. If stores use a write actor, the service must flush or wait for that actor before reading or deleting local files. Registry tests should compare against the encoded model shape or another independent source of truth, not only against manually maintained registry constants.

**Verification Note:**
An initial attempt to run two `xcodebuild test` commands in parallel hit Xcode's shared DerivedData `build.db` lock. That was a test-run orchestration mistake, not an app failure. The affected focused tests were rerun sequentially.

**Pattern Tags:** #audit #persistence #compliance #privacy #tests

---

### [DL-040] Audit Secret-Readiness Wiring And Historical Token Redaction
**Date:** 2026-05-10
**Severity:** warning
**Category:** audit
**File(s):** `Documentation/SECRETS.md`, `.gitleaks.toml`, `Configurations/Debug.xcconfig`, `Configurations/Beta.xcconfig`, `Configurations/Release.xcconfig`, `.gitignore`, `README.md`, `SPOTTER_REVIEW.md`, `Spotter_Pre_Backend_Readiness.md`, `VirtualTrainer.xcodeproj/project.pbxproj`

**Error:**
The first secret-readiness pass had two audit misses while adding documentation and environment config. First, the initial masked scan covered common OpenAI/GitHub/Google/AWS token shapes but did not catch an underscore-style `sk_...` token-shaped value preserved in an old review document. Second, the pass briefly treated Xcode build-setting visibility as enough evidence that custom `INFOPLIST_KEY_*` values would materialize in the generated app bundle. A direct built-app `Info.plist` check showed those custom keys were absent, so relying on that path would have created a misleading configuration story.

**Root Cause:**
The work was intentionally documentation/config scoped, but the scan and verification strategy initially mixed two different guarantees: repository hygiene and runtime configuration availability. The first scan overfit to currently common provider prefixes and did not include Stripe-style or ElevenLabs-looking underscore key shapes. The Xcode verification checked `xcodebuild -showBuildSettings` before checking the final generated `Info.plist`, even though this project generates its Info.plist and also has target-level CocoaPods base configs.

**Why It Was Missed In The First Pass:**
Context compaction happened during the broader implementation, which made it easier to focus on satisfying the requested file additions and README updates rather than revalidating every assumption from the built artifact outward. The first scan also treated false positives from prose as the main noise problem, so the pattern set was too narrow around hyphenated `sk-...` provider keys and did not include `sk_...` examples. For Xcode config, seeing `SPOTTER_ENVIRONMENT` and `GOOGLE_SERVICE_INFO_PLIST` in effective build settings looked like successful wiring, but that did not prove anything about `Bundle.main` visibility or Firebase plist copy behavior.

**Fix Applied:**
Redacted the historical token-shaped example in `SPOTTER_REVIEW.md` without printing the value again, and softened a service-account example in `Spotter_Pre_Backend_Readiness.md` so it no longer resembles private-key material. Added `.gitleaks.toml` rules for provider tokens, service-account JSON, private keys, URL credentials, generic assignments, and `sk_...` secret-key shapes. Kept Debug and Release xcconfigs wired at the project level so the app target inherits environment build settings while preserving CocoaPods target xcconfigs and MediaPipe linker behavior. Removed the misleading generated-Info.plist mapping attempt and documented that Firebase phase work must add an explicit plist target-membership/copy/load step. Verified Debug resolves to dev/`GoogleService-Info-Dev.plist`, Release resolves to prod/`GoogleService-Info-Prod.plist`, `ElevenLabsService` remains a `Bundle.main` lookup only, and Debug tests plus a Release simulator build pass.

**Prevention Rule:**
Secret-readiness work must verify both layers separately: scan the full repository with broad provider and generic patterns, and verify runtime configuration by inspecting the built product when a `Bundle.main` or plist behavior is claimed. Build-setting presence alone is not proof of bundle availability. Historical audit docs should be included in secret scans because old examples can still leak real-looking values even after source code has been corrected.

**Pattern Tags:** #audit #secrets #xcconfig #firebase-readiness #docs #tests

---

### [DL-041] Add Local Repository Abstraction Before Backend SDKs
**Date:** 2026-05-10
**Severity:** warning
**Category:** backend-readiness
**File(s):** `VirtualTrainer/Repositories/BackendMode.swift`, `VirtualTrainer/Repositories/RepositoryError.swift`, `VirtualTrainer/Repositories/RepositoryProtocols.swift`, `VirtualTrainer/Repositories/LocalAuthRepository.swift`, `VirtualTrainer/Repositories/LocalStoreRepositories.swift`, `VirtualTrainer/Repositories/LocalPlanRepository.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Repositories/SyncOrchestrator.swift`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `README.md`

**Error:**
The app had backend-ready model fields, tombstones, write operations, event logs, and local compliance scaffolding, but it still lacked the repository contract layer that future Firebase or Supabase code must implement. Adding a backend SDK directly at this point would have mixed remote concerns into stores that also drive live camera, planned workouts, trophies, stats, trends, recaps, and insights.

**Root Cause:**
The pre-backend phases prepared the data shape first, but the product was still wired around concrete local stores. Without protocols and local repository implementations, there was no safe way to prove that backend-shaped reads and writes could preserve existing local JSON behavior before adding cloud dependencies.

**Fix Applied:**
Added `BackendMode`, typed `RepositoryError`, repository protocols for auth, profile, workouts, trophies, insights, theme, calibration, and plans, plus local implementations backed by the existing stores and local JSON files. Added a stable local anonymous account repository, `AppDependencies.local()`, and a `SyncOrchestrator` scaffold whose local-mode sync methods succeed as no-ops. Exposed narrow store save helpers where needed instead of rewriting the live product stores. Kept Firebase and Supabase SDKs out of the repo and left raw video, camera frames, face images, raw pose streams, raw biometric face data, and raw pose timelines outside all repository contracts.

**Prevention Rule:**
Backend phases should implement the repository protocols instead of reaching directly into SwiftUI stores or camera services. Local JSON decoding must remain backwards-compatible, write operations should continue to be idempotent, and theme sync should treat `UserProfile.selectedTheme` as the future remote source of truth while `Theme.json` remains a local cache.

**Pattern Tags:** #backend-readiness #repositories #local-first #sync-prep #privacy #tests

---

### [DL-042] Audit Phase 15 Repository Edge Cases After Context Compaction
**Date:** 2026-05-11
**Severity:** warning
**Category:** audit
**File(s):** `VirtualTrainer/Repositories/RepositoryProtocols.swift`, `VirtualTrainer/Repositories/LocalStoreRepositories.swift`, `VirtualTrainer/Repositories/LocalPlanRepository.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `README.md`

**Error:**
The Phase 15 repository layer compiled and passed its first happy-path tests, but the follow-up audit found several contract-edge misses. The observe methods existed but were not all declared `async throws` even though the phase required every repository method to use that shape. Retrying a workout delete or insight invalidation with the same completed operation ID could be reported as missing because the store checked for a currently visible record before accepting the write journal's idempotency record. The local plan repository's first draft also mixed file reload/write work with suspension points in a way that could lose rapid plan saves under MainActor reentrancy. Finally, `LocalInsightRepository.loadRecentInsights` exposed invalidated insight tombstones through a normal product-facing read.

**Root Cause:**
The implementation intentionally wrapped existing local stores instead of rewriting the product model, which was the right architectural choice for Phase 15. The miss was assuming that stores with tombstones and a write journal were automatically repository-idempotent at every boundary. A few older store methods were written from the UI projection point of view: if the record was no longer visible, they returned "not found" before checking whether the operation had already succeeded. The insight store also keeps deleted insight tombstones in its internal ranking/suppression state, but the repository read contract needed to return active recent insights, not internal tombstone records.

**Why It Was Missed In The First Pass:**
Context compaction happened in the middle of the broader backend-readiness work, so the first verification over-weighted file presence, compile safety, and sequential round-trip behavior. The initial tests proved that each repository could save and load the main record type once, but they did not retry tombstoning operations after the record disappeared from visible state, did not stress rapid plan saves, and did not assert that product-facing reads hide invalidated insight tombstones. The protocol-shape miss came from adding observer methods last and treating them like stream factories instead of applying the "all methods are async throws" rule uniformly.

**Fix Applied:**
Made all repository observer methods `async throws`, made local profile/workout/trophy observer streams emit again after repository-owned local writes, rewrote the local plan repository around an in-memory snapshot that mutates before the first suspension point, made retried workout deletes and insight invalidations honor completed operation IDs after tombstoning, and filtered deleted insights out of `LocalInsightRepository.loadRecentInsights`. Added regression tests for local auth Apple-link unsupported behavior and sign-out data preservation, observer updates after local writes, retried workout deletes, retried insight invalidation, rapid concurrent plan saves, and duplicate plan operation IDs. The README now states that normal repository reads hide deleted workouts and invalidated insights while local tombstones remain available for future sync.

**Prevention Rule:**
Repository audits must test the contract, not only the wrapped store's happy path. Every tombstone-producing write needs a same-operation retry test after the record has disappeared from normal reads, every async local repository that appends or replaces records needs a rapid-save test, and every product-facing repository load should explicitly decide whether it returns active records or tombstones. After context compaction, re-run the acceptance checklist against signatures, semantics, and tests instead of trusting memory of the pre-compaction pass.

**Pattern Tags:** #audit #repositories #idempotency #tombstones #concurrency #tests

---

### [DL-043] Stabilize Persistence Actor Rapid-Write Verification
**Date:** 2026-05-11
**Severity:** warning
**Category:** tests
**File(s):** `VirtualTrainerTests/PersistenceActorTests.swift`

**Error:**
The full verification run exposed a flaky persistence actor test. `testRapidWritesResolveSafelyWithLastPayload` used two `async let` writes and assumed the second source-code line would always be the actor's last enqueued write. Under a different scheduler interleaving, the first payload could be the write that actually completed last, causing the test to fail even though the actor still wrote one complete payload and reported valid `.written` / `.superseded` outcomes.

**Root Cause:**
`async let` starts child work concurrently, so lexical order is not a reliable proxy for actor enqueue order. The test was validating a stronger ordering guarantee than the production actor promises for two simultaneously-started writes.

**Why It Was Missed In The First Pass:**
The test usually passed because the scheduler often started the first `async let` before the second, making the second payload the final file content. The broader repository work made us rerun the full suite enough times to hit the opposite interleaving.

**Fix Applied:**
Updated the test to assert the actual contract: the final file content must match a payload whose write outcome was `.written`, at least one write must be `.written`, and every rapid-write outcome must be `.written` or `.superseded`. This keeps the safety check without depending on scheduler order.

**Prevention Rule:**
Concurrency tests should not infer actor enqueue order from source-code order when work is deliberately launched concurrently. If a test needs strict last-write semantics, it must create a deterministic ordering; otherwise it should assert the contract that is guaranteed across valid interleavings.

**Pattern Tags:** #tests #concurrency #persistence #flaky-test

---

### [DL-044] Re-Audit Phase 15 Repository Integration After Compaction
**Date:** 2026-05-11
**Severity:** note
**Category:** audit
**File(s):** `VirtualTrainer/Repositories/*`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `VirtualTrainerTests/PersistenceActorTests.swift`, `README.md`, `DEBUG_LOG.md`

**Error:**
A second audit was requested because the repository phase had gone through a context compaction and earlier review already found subtle misses. The risk was that a file could exist without fully satisfying the contract, a local repository could expose tombstones through normal reads, a retry path could regress idempotency, a protected camera/live-analysis service could have been touched accidentally, or verification could have passed before the final test adjustment.

**Root Cause:**
The earlier misses were caused by validating the first repository pass too much from file presence and simple save/load round trips. The compacted context made it easier to lose the original acceptance checklist details, especially the uniform `async throws` method shape, same-operation retry behavior after tombstoning, and the difference between internal tombstone state and product-facing repository reads.

**Why It Was Missed In The First Pass:**
The first pass proved that local repositories could compile and perform happy-path writes, but it did not initially stress all contract edges. Observer methods were added late and reviewed like stream factories instead of normal repository methods. Delete/invalidation retry behavior inherited UI-store assumptions where invisible records look missing. The plan repository initially had suspension points around file persistence that needed a separate concurrency stress test. The persistence actor test also assumed concurrent `async let` lexical order matched actor enqueue order, which only failed under a less common scheduler interleaving.

**Fix Applied:**
Re-ran the full Phase 15 audit from the current filesystem state. Confirmed all repository protocol functions are `async throws`, local implementations exist for Auth/Profile/Workout/Trophy/Insight/Theme/Calibration/Plan, local auth keeps a stable anonymous ID, Apple linking is intentionally unsupported in local mode, sign-out does not erase local data, local sync no-ops succeed, normal workout and insight reads hide tombstoned records, and theme remains documented as `UserProfile.selectedTheme` for future remote source of truth with `Theme.json` as local cache. Confirmed the diff does not touch `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, `FormFeedbackEngine`, `HandGestureDetector`, `ExertionAnalyzer`, MediaPipe setup, or the live camera pipeline. Confirmed no Firebase or Supabase imports/dependencies and no repository upload/storage path for raw video, camera frames, face images, raw pose streams, raw biometric face data, or raw pose timelines.

**Verification:**
`git diff --check` passed. Static scans found no Firebase/Supabase imports or dependency references, no protected live-pipeline file changes, and no raw camera/pose/face upload path in repositories. `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed with 335 tests, 0 failures, and 0 skipped. `xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'` passed. Simulator smoke installed and launched `satvik.VirtualTrainer`; the process stayed alive after startup.

**Prevention Rule:**
After any future context compaction, re-run the acceptance checklist from the actual tree: inspect changed and untracked files, verify protocol signatures, verify idempotent tombstone retries, verify product-facing reads versus internal tombstone state, run the full test suite after the last edit, and record the audit result in the debug log.

**Pattern Tags:** #audit #repositories #context-compaction #verification #local-first #tests

---

### [DL-045] Fix Firebase/gRPC IDE Build Crash From Custom Swift Toolchain
**Date:** 2026-05-14
**Severity:** build-breaking
**Category:** xcode-config
**File(s):** Xcode IDE toolchain selection, `VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `VirtualTrainer.xcodeproj/project.pbxproj`

**Error:**
After Firebase was added through Swift Package Manager, Xcode's Issue Navigator showed seven clang errors under the `VirtualTrainer` scheme:

`clang frontend command failed with exit code 134 (use -v to see invocation)`

`unable to execute command: Abort trap: 6`

Several follow-on errors reported missing temporary object files such as:

`no such file or directory: '/private/var/folders/75/nndfzddd11b8kv28kpwdjlh40000gp/T/swbuild.tmp.<random>/Data.noindex/arm64-apple.o'`

Changing the selected simulator device to `iPhone 17 Pro` did not change the failure.

**What Made This Tricky:**
The first command-line build with an explicit DerivedData path succeeded:

`xcodebuild -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/VirtualTrainerDerivedData build`

The normal command-line DerivedData build also succeeded:

`xcodebuild -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

But pressing Build inside the Xcode UI still failed. This proved the Firebase package graph and project sources were buildable, and the remaining difference was Xcode IDE state, not simulator selection or Swift source.

**Root Cause:**
The Xcode UI was using the custom **Swift 6.2 Release** toolchain:

`/Users/satvik.bansal/Library/Developer/Toolchains/swift-6.2-RELEASE.xctoolchain`

The terminal `xcodebuild` path used Xcode's default toolchain:

`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`

Firebase `12.13.0` brought in binary Swift Package artifacts, including `grpc-binary` and `openssl_grpc.framework`. During the app build, Xcode copies some codeless binary frameworks into the app bundle and injects a stub binary. In the failing IDE build log, the stub injection step invoked the custom toolchain clang:

`/Users/satvik.bansal/Library/Developer/Toolchains/swift-6.2-RELEASE.xctoolchain/usr/bin/clang -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -x c -c /dev/null -target arm64-apple-ios100.0-simulator -o /private/var/folders/.../swbuild.tmp.../Data.noindex/arm64-apple.o`

That custom clang crashed on the generated `ios100.0-simulator` target with:

`Assertion failed: (OsVersion < VersionTuple(100) && "Invalid version!"), function getDarwinDefines, file OSTargets.cpp, line 92.`

Once clang aborted, Xcode tried to link/lipo the stub file that was never produced, causing the misleading missing-file cascade:

`lipo: can't open input file: .../Data.noindex/arm64-apple (No such file or directory)`

The visible `Data.noindex/arm64-apple.o` messages were therefore symptoms. The actual issue was the selected custom Swift toolchain's clang crashing during Firebase/gRPC binary-framework stub injection.

**Why The Simulator Change Did Not Help:**
The failure happened before app launch and before simulator-specific runtime behavior. Xcode was constructing framework stubs for the simulator build product. Any iOS simulator destination using the same IDE-selected Swift 6.2 toolchain could hit the same `ios100.0-simulator` clang assertion, so switching to `iPhone 17 Pro` only changed the destination name, not the bad compiler path.

**Fix Applied:**
Opened Xcode's Toolchains selector from the toolbar and changed the active toolchain from **Swift 6.2 Release** back to **Xcode 26.3**.

After switching, Xcode's UI build used:

`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang`

The Xcode UI build then succeeded at `2026-05-14 10:21 IST`, and the Issue Navigator cleared.

No source files, project files, pod files, package pins, or build settings were changed for this fix. `git status --short` was clean before this debug-log entry was added.

**Diagnostic Steps That Found It:**
1. Confirmed the workspace contains CocoaPods for MediaPipe and Swift Package Manager for Firebase.
2. Confirmed Firebase package resolution is valid: `firebase-ios-sdk` `12.13.0`, plus `grpc-binary`, `GoogleUtilities`, `GoogleAppMeasurement`, `leveldb`, `nanopb`, and related dependencies.
3. Confirmed available destinations include `iPhone 17 Pro`, so the device itself was not missing or misconfigured.
4. Built from the terminal with an explicit clean DerivedData path; build succeeded.
5. Built from the terminal using normal Xcode DerivedData; build succeeded.
6. Triggered a build from the Xcode UI; build failed again with fresh `swbuild.tmp` paths.
7. Decompressed the latest `.xcactivitylog` from:
   `~/Library/Developer/Xcode/DerivedData/VirtualTrainer-ezszqygydeoqrdhconliqskhqxfl/Logs/Build/`
8. Found the failing IDE log contained `swift-6.2-RELEASE.xctoolchain`, `target arm64-apple-ios100.0-simulator`, and the `OsVersion < VersionTuple(100)` clang assertion.
9. Switched Xcode's active toolchain to Xcode 26.3.
10. Rebuilt in Xcode UI; build succeeded and errors disappeared.

**Verification:**
Terminal clean build passed:

`xcodebuild -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath /tmp/VirtualTrainerDerivedData build`

Terminal normal DerivedData build passed:

`xcodebuild -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`

Xcode UI build passed after selecting **Xcode 26.3** in the Toolchains window. The successful Xcode activity log no longer contained `swift-6.2-RELEASE`, `clang frontend command failed`, or `error:`.

`xcrun --find clang` after the fix resolved to:

`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang`

**Prevention Rule:**
When Firebase, gRPC, or another binary Swift Package starts failing in Xcode with `clang frontend command failed`, `Abort trap: 6`, and missing `swbuild.tmp/.../Data.noindex/*.o` files, check Xcode's active toolchain before editing code. In Xcode, open the Toolchains selector and prefer the bundled **Xcode** toolchain for app builds unless a custom Swift toolchain is explicitly required.

If terminal `xcodebuild` succeeds but the Xcode UI fails, compare the compiler paths in the `.xcactivitylog`. A mismatch between `XcodeDefault.xctoolchain` and `~/Library/Developer/Toolchains/swift-*.xctoolchain` is a high-signal clue.

Do not treat the random `swbuild.tmp` object-file paths as the root cause. They are temporary outputs that disappear because the earlier compiler command crashed.

**Pattern Tags:** #xcode-config #toolchain #firebase #swiftpm #grpc #clang #ide-only #deriveddata

---

### [DL-046] Add Firebase Bootstrap And DEBUG Smoke Verification; Block Phase 16 On Firestore TLS
**Date:** 2026-05-14
**Severity:** integration-blocking
**Category:** firebase-integration
**File(s):** `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/Services/FirebaseBootstrap.swift`, `VirtualTrainer/Services/FirebaseSmokeVerifier.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`, simulator trust/network state

**Context:**
Firebase packages were installed in the Xcode workspace:

- `FirebaseAuth`
- `FirebaseCore`
- `FirebaseFirestore`
- existing CocoaPods app framework linkage through `Pods_VirtualTrainer.framework`

Firebase Console has anonymous authentication enabled. There is no login UI yet, so the correct integration proof at this phase is a gated debug-only anonymous sign-in plus a Firestore write/read smoke check, not a product-facing auth screen.

**Errors / Findings:**
1. Firebase packages were present, but the app had no explicit Firebase runtime bootstrap path yet. Installing packages alone does not configure Firebase; the app must call `FirebaseApp.configure(...)` with the bundled `GoogleService-Info.plist`.
2. After adding the smoke verifier, the first compile attempt failed because `FirebaseSmokeVerifier.swift` referenced `FirebaseApp` without importing `FirebaseCore`.
3. The Phase 15 audit test correctly failed after Firebase write code appeared, because the test was intentionally guarding against accidental production Firestore uploads before Phase 16. The test needed a narrow allowlist for bootstrap and DEBUG-only smoke verification, not a broad disable.
4. The initial smoke verifier used a structured task-group timeout. Firestore/gRPC can keep retrying while the callback never returns under this network failure mode, so the task-group implementation could fail to write a deterministic smoke-result file.
5. Live Firebase Auth initially failed in the simulator with network/trust errors. After adding the local corporate simulator certificates, anonymous Auth progressed and returned an anonymous user.
6. Firestore live write still failed on the simulator. Simulator logs repeatedly showed Firebase Firestore gRPC handshake failures:

`WriteStream ... Stream error: 'Unavailable: failed to connect to all addresses; last error: UNKNOWN: ... Ssl handshake failed (TSI_PROTOCOL_FAILURE): SSL_ERROR_SSL: error:1000007d:SSL routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED: self signed certificate in certificate chain'`

7. Network comparison showed host macOS curl can reach Google APIs, while simulator curl cannot verify the same HTTPS endpoint:

Host:

`curl -I --max-time 10 https://www.googleapis.com` returned HTTP/2 404, proving basic host reachability.

Simulator:

`xcrun simctl spawn 0442BD6F-881D-451A-B764-815DCAD3F78A /usr/bin/curl -I --max-time 10 https://www.googleapis.com` failed with:

`curl: (60) SSL certificate problem: self signed certificate in certificate chain`

**Root Cause:**
There were two separate issues:

1. **App integration gap:** Firebase SDK dependencies were added, but the app needed explicit runtime configuration and a safe verification path.
2. **Environment/network blocker:** The current simulator network is behind TLS inspection. Firebase Auth can now complete after simulator trust changes, but Firestore uses gRPC/BoringSSL and is still rejecting the intercepted certificate chain. This is not fixed by switching simulator devices and should not be bypassed in app code.

The current Firestore failure is environmental, not a missing package, missing plist, bundle-id mismatch, or Phase 16 repository implementation bug.

**Fix Applied:**
1. Added `FirebaseBootstrap.configureIfNeeded()` to configure Firebase once from the bundled `GoogleService-Info.plist`.
2. Called `FirebaseBootstrap.configureIfNeeded()` during `VirtualTrainerApp.init()`.
3. Added `FirebaseSmokeVerifier` behind `#if DEBUG`.
4. Gated the smoke verifier so it only runs with `--firebase-smoke-test` or `VIRTUALTRAINER_FIREBASE_SMOKE_TEST=1`; normal app launch does not sign in or write Firestore.
5. Smoke verifier now:
   - configures Firebase if needed,
   - signs in anonymously,
   - verifies the user is anonymous,
   - writes a debug Firestore document under `debugFirebaseSmoke/{uid}`,
   - reads the document back,
   - verifies a nonce round-trip,
   - writes `Library/Caches/FirebaseSmokeResult.json`,
   - redacts Google API keys from error output.
6. Replaced the smoke timeout helper with an unstructured continuation gate so blocked Auth/Firestore callbacks produce a deterministic failure result instead of hanging indefinitely.
7. Updated `WorkoutSummarySizeAuditTests.testNoProductionFirebaseUploadCodeExistsYet()` to allow only:
   - app bootstrap,
   - DEBUG smoke verifier imports and calls,
   - smoke-only Firestore `setData`.
   The audit still blocks accidental production Firestore writes before Phase 16.
8. Added simulator-local corporate certificates as a diagnostic step. This helped Auth progress, but did not clear Firestore gRPC. This is local simulator state, not a repo change.

**Verification:**
Build passed on the target simulator:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`

Full test suite passed after the last code change:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`

Latest test summary:

- Result: `Passed`
- Total tests: `335`
- Passed: `335`
- Failed: `0`
- Skipped: `0`
- Device: `iPhone 17 Pro`
- Simulator ID: `0442BD6F-881D-451A-B764-815DCAD3F78A`
- Result bundle: `~/Library/Developer/Xcode/DerivedData/VirtualTrainer-ezszqygydeoqrdhconliqskhqxfl/Logs/Test/Test-VirtualTrainer-2026.05.14_10-54-57-+0530.xcresult`

Bundled app config was verified:

- App bundle id: `satvik.VirtualTrainer`
- Firebase plist `BUNDLE_ID`: `satvik.VirtualTrainer`
- Firebase `PROJECT_ID`: `spotter-42ffe`
- Firebase `GOOGLE_APP_ID`: present and matching the app

Normal app launch passed the guard check:

`xcrun simctl launch 0442BD6F-881D-451A-B764-815DCAD3F78A satvik.VirtualTrainer`

No `FirebaseSmokeResult.json` was created during normal launch, proving the verifier does not accidentally run in product startup.

Explicit smoke launch:

`SIMCTL_CHILD_VIRTUALTRAINER_FIREBASE_SMOKE_TEST=1 xcrun simctl launch --terminate-running-process 0442BD6F-881D-451A-B764-815DCAD3F78A satvik.VirtualTrainer --firebase-smoke-test`

Smoke result:

```json
{
  "bundleID" : "satvik.VirtualTrainer",
  "googleAppID" : "1:75737325492:ios:a4298df0aac33c20425ce1",
  "isAnonymous" : true,
  "message" : "Firestore smoke write did not complete within 25 seconds.",
  "projectID" : "spotter-42ffe",
  "status" : "fail"
}
```

This proves Firebase Core configuration and anonymous Auth are working, but Firestore live write/read is not green on this simulator/network.

**Phase 16 Gate:**
Do not proceed to Phase 16 as fully green yet. Proceeding would hide an external Firestore connectivity problem behind new repository code.

Green:

- Xcode/Firebase package build
- Firebase plist bundled with matching bundle id
- Firebase Core configure path
- anonymous Auth smoke path
- full local test suite
- normal app launch without accidental Firestore writes

Red:

- Firestore live write/read from the iOS simulator on this network

**Prevention Rule:**
Before implementing Phase 16 production Firestore repositories, rerun the DEBUG smoke verifier on a network that does not intercept Firebase TLS traffic, or have IT/network policy bypass SSL inspection for Firebase/Google endpoints used by this app, including Firestore/gRPC traffic. Do not disable TLS verification or add app-level certificate bypasses.

Keep the audit test active. Any new production Firestore write path should be introduced deliberately in Phase 16 and should come with tests that prove the intended Firestore shape and local-first behavior.

**Pattern Tags:** #firebase #firebase-auth #firestore #grpc #tls #simulator #debug-smoke #phase-16-gate #anonymous-auth

---

### [DL-047] Harden Firebase Client Config Loading For Local-Only Builds
**Date:** 2026-05-14
**Severity:** warning
**Category:** firebase-integration
**File(s):** `VirtualTrainer.xcodeproj/project.pbxproj`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/Services/FirebaseBootstrap.swift`, `VirtualTrainer/Services/FirebaseSmokeVerifier.swift`, `VirtualTrainerTests/FirebaseBootstrapTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`, `GoogleService-Info.example.plist`, `Documentation/DEVELOPMENT_SETUP.md`

**Error:**
The app target had a direct `GoogleService-Info.plist` resource reference and `VirtualTrainerApp.init()` called Firebase bootstrap unconditionally. A fresh clone without a Firebase client plist could therefore fail resource handling or hit bootstrap assertions even though `BackendMode.local` should be fully functional.

**Root Cause:**
`GOOGLE_SERVICE_INFO_PLIST` was defined in the environment xcconfigs but not consumed by the Xcode resource pipeline. Firebase bootstrap also treated missing or invalid config as an assertion path instead of a normal local-only state.

**Fix Applied:**
Removed the direct plist file/resource reference from the app target and added an always-running build phase that copies the configured environment plist into the app bundle only when one is present. Replaced bootstrap's Bool/assertion API with `FirebaseBootstrapState` and `configureIfAvailable()`, returning `.missingConfig`, `.alreadyConfigured`, `.configured`, or sanitized `.failed` states without logging plist contents or secret-like values. Removed normal-launch Firebase bootstrap from `VirtualTrainerApp.init()` and kept the DEBUG smoke verifier behind its explicit launch gate plus successful Firebase configuration. Added a placeholder example plist, development setup documentation, and focused bootstrap tests.

**Verification:**
Toolchain paths resolve to XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Clean no-plist build passed after temporarily moving the ignored local client plist out of the repo and using a fresh DerivedData path:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData`

Required build passed with the local client plist present:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 339
- Failed: 0
- Skipped: 0

Targeted `FirebaseBootstrapTests` passed. Fallback secret scan over tracked and new, non-ignored files found no matching secret-like values.

**Prevention Rule:**
Firebase client config must be copied through the environment-aware build phase, not target-membered as a required resource. Local mode must not call Firebase bootstrap during normal app startup, and any bootstrap failure reason must stay sanitized and free of plist contents, API keys, app IDs, project IDs, and local plist paths.

**Pattern Tags:** #firebase #local-first #xcode-config #secrets #bootstrap #tests

---

### [DL-048] Add Runtime Backend Status Switch For Phase 16A
**Date:** 2026-05-14
**Severity:** warning
**Category:** backend-readiness
**File(s):** `VirtualTrainer.xcodeproj/project.pbxproj`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/Repositories/BackendConfiguration.swift`, `VirtualTrainer/Repositories/BackendStatusStore.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Services/FirebaseSmokeVerifier.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainer/UI/MainTabView.swift`, `VirtualTrainerTests/BackendConfigurationTests.swift`, `VirtualTrainerTests/BackendStatusStoreTests.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
Phase 16 needed Firebase to light up incrementally, but the app still had no published desired/active backend status. DEBUG builds also had no safe runtime switch for requesting Firebase, no visible fallback reason when Firebase config was absent, and the DEBUG smoke verifier was not tied to the active backend mode.

**Root Cause:**
Backend selection was still implicit startup behavior. Firebase readiness, dependency construction, and debug verification did not share one observable source of truth, so local-first behavior could regress as soon as later phases added partial Firebase repositories.

**Fix Applied:**
Added `BackendConfiguration` to resolve `SPOTTER_BACKEND_MODE` from generated Info.plist plus a DEBUG-only `UserDefaults` override, while non-DEBUG builds stay local until the production switch is promoted. Added `BackendStatusStore` to publish desired mode, active mode, Firebase bootstrap state, and a user-facing fallback message. `VirtualTrainerApp` now constructs and injects that store, builds dependencies through `AppDependencies.from(_:)`, and only checks the smoke-test launch gate when Firebase is active. Phase 16A deliberately keeps Firebase-mode repositories local and tags the dependency graph with `backendMode = .firebase` so Phase 16B can override Auth without rewriting the app shell. Added DEBUG Profile settings UI for desired/active mode, bootstrap state, redacted local account ID, restart warning, and an inline Firebase smoke-test button. The smoke verifier now returns an inline result and no longer prints UID or Firestore path values on success.

**Verification:**
Toolchain paths resolve under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 344
- Failed: 0

`SPOTTER_BACKEND_MODE=firebase` build passed with the ignored local Firebase client config present. `SPOTTER_BACKEND_MODE=firebase` also passed from a fresh DerivedData path while the ignored local client config was temporarily absent; the build phase reported local-only mode and the file was restored immediately afterward.

`git diff --check` passed. `gitleaks` was not installed, so the fallback scan used the repo `.gitleaks.toml` patterns over changed, non-ignored files and found no secret-like values.

**Prevention Rule:**
Future Firebase phases must route launch-time backend decisions through `BackendStatusStore` and must keep Firebase repository adoption partial and explicit. DEBUG mode switches require a restart rather than live Firebase reconfiguration, and local mode must continue to build, launch, and run tests with no Firebase client plist.

**Pattern Tags:** #backend-mode #firebase #local-first #debug-ui #xcode-config #secrets #tests

---

### [DL-049] Add Firebase Anonymous Auth And Local Account Claim Coordinator
**Date:** 2026-05-14
**Severity:** warning
**Category:** firebase-auth
**File(s):** `VirtualTrainer/Repositories/Firebase/FirebaseAuthRepository.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Services/AccountClaimCoordinator.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainerTests/AccountClaimCoordinatorTests.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
Firebase mode could configure Firebase Core, but it still used `LocalAuthRepository` and had no product path for anonymous Firebase Auth. A Firebase UID therefore could not become `AccountContext.currentAccountId`, and existing local-only profile, workout, trophy, insight, calibration, and theme records were not claimed before future remote listeners attach.

**Root Cause:**
Phase 16A intentionally stopped at backend-mode selection and bootstrap. The app had account-aware stores and `claimLocalDataForAccount(id:)`, but no coordinator tied auth state changes to those stores. The existing `LocalWriteJournal` also treats operation IDs as global idempotency keys, so passing one operation ID directly through all six store claim calls would make the first store record the operation and cause later stores to skip.

**Fix Applied:**
Added `FirebaseAuthRepository` behind `AuthRepository` for anonymous sign-in, sign-out, delete, and auth-state observation. Added `AppDependencies.firebaseAuthOnly()` so Firebase mode uses Firebase Auth while all data repositories remain local until Firestore phases ship. Added `AccountClaimCoordinator` and `AccountAwareStores`; the coordinator records one parent `.profile` claim operation and gives each store its own child operation ID to preserve the existing journal semantics. `VirtualTrainerApp` now observes Firebase auth changes only when Firebase is the active backend and routes each emitted UID through the coordinator. Profile DEBUG backend tools now support anonymous sign-in, sign-out, redacted UID display, and a manual force re-claim action. No Firestore repository writes were added.

**Verification:**
Toolchain paths resolve under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 348
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored local Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16B`

The no-plist app build installed and launched on the `iPhone 17 Pro` simulator with bundle id `satvik.VirtualTrainer`.

`git diff --check` passed. `GoogleService-Info.plist` was present locally and ignored by git; the build phase copied it into the app bundle without printing plist contents. `gitleaks` was not installed. The fallback scanner found one pre-existing documentation false positive in `Spotter_Phase16_Forward_Plan.md` where a future privacy-validator test mentions redacted private-key fixture text; the changed/unignored files scan found no secret-like values.

**Prevention Rule:**
Keep Firebase auth adoption separate from Firestore repository adoption. Do not attach future remote listeners until `AccountClaimCoordinator` has claimed local records for the emitted UID. Do not reuse the parent account-claim operation ID directly for all store writes unless `LocalWriteJournal` is redesigned to support multi-entity operation records.

**Pattern Tags:** #firebase-auth #anonymous-auth #account-claim #local-first #write-journal #debug-ui #tests

---

### [DL-050] Add Isolated Firestore Translation Layer For Phase 16C
**Date:** 2026-05-14
**Severity:** warning
**Category:** backend-readiness
**File(s):** `VirtualTrainer/Repositories/Firebase/FirestoreDTOs.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreMapper.swift`, `VirtualTrainer/Repositories/Firebase/FirestorePathBuilder.swift`, `VirtualTrainer/Repositories/Firebase/FirestorePrivacyValidator.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreEncodingHelpers.swift`, `VirtualTrainerTests/FirestoreTranslationLayerTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
Phase 16C needed the Firestore document translation boundary before any repository writes were wired. The app already had Firebase Auth scaffolding and local sync-ready models, but it did not yet have isolated DTOs, mappers, path construction, Firestore-safe encoding, or a privacy validator for rejecting raw camera/pose/face payloads and secret-like values.

**Root Cause:**
Previous phases stopped at local repositories, backend-mode selection, Firebase bootstrap, and anonymous auth. Without a separate translation layer, future Firestore repositories would have been tempted to encode app models directly, risk embedding oversized workout evidence, leak Firestore-specific timestamp behavior into product models, or miss the documented compact-workout-plus-sets shape from `Documentation/FirestoreShape.md`.

**Fix Applied:**
Added Firestore DTOs for profile, compact workouts, workout sets, trophy events, trophy progress cache, insights, insight delivery, insight engagement, calibration, and plans. Added symmetric mapper functions that normalize account IDs, keep UUID document fields as lowercase strings, store enum raw values, sort set-backed arrays such as profile limitations, and keep Firestore DTOs out of app models. Added path builders for the documented `users/{uid}/...` shape with empty/invalid path component rejection. Added a privacy validator for forbidden raw-media/pose/face/secret fields, large binary blobs, and secret-like strings. Added a single encoding helper that converts DTOs through `JSONEncoder` and `JSONSerialization`, lowercases UUID-shaped strings, injects `FieldValue.serverTimestamp()` for nil server timestamp placeholders, and validates the payload before it can be handed to a future `setData` call. No production Firestore writes were added.

**Verification:**
Toolchain paths resolved under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 358
- Failed: 0
- Skipped: 0

Focused `FirestoreTranslationLayerTests` passed with 10 new test methods. `WorkoutSummarySizeAuditTests.testNoProductionFirebaseUploadCodeExistsYet()` still allows only the debug smoke verifier to call Firestore write APIs. `git diff --check` passed. `gitleaks` was not installed, so the fallback `.gitleaks.toml` pattern scan over changed and new non-ignored files found no secret-like values. Static write scan found no new `.setData`, `.updateData`, or `.addDocument` calls outside the existing debug smoke verifier.

**Prevention Rule:**
Future Firestore repositories should consume these DTOs and helpers instead of encoding app models or constructing paths ad hoc. Any new Firestore write path must keep workout sets split from compact workout summaries, call the privacy validator before writing, avoid raw camera/video/pose/face payloads, and update the audit allowlist only for intentional write APIs with tests.

**Pattern Tags:** #firebase #firestore #backend-readiness #dto-mapping #privacy #local-first #tests

---

### [DL-051] Wire Lowest-Risk Firestore Repositories For Phase 16D
**Date:** 2026-05-14
**Severity:** warning
**Category:** firestore-sync
**File(s):** `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreProfileRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreThemeRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreCalibrationRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestorePlanRepository.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/ThemeStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainer/UI/HomeDashboardView.swift`, `VirtualTrainer/UI/WorkoutPreviewView.swift`, `Documentation/FirestoreShape.md`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `VirtualTrainerTests/FirestoreTranslationLayerTests.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
Phase 16D needed Firebase mode to sync profile, theme, calibration, and active-plan cache through Firestore, while keeping workouts, trophies, insights, and the live camera/session stack local and non-blocking. The app also still had to build, test, and run in `BackendMode.local` with no Firebase client plist.

**Root Cause:**
Phase 16C intentionally stopped at DTOs, mapping, path construction, and privacy validation. There was no Firestore document adapter, no transactional repository layer, and no reverse wiring from SwiftUI stores back to the remote repositories. Theme persistence also needed to avoid a competing remote document because `UserProfile.selectedTheme` is the documented future source of truth.

**Fix Applied:**
Added a small Firestore document database adapter plus repositories for `users/{uid}/profile/current`, profile-backed theme sync, `users/{uid}/calibration/status`, and `users/{uid}/plans/{planId}`. Added transaction conflict/idempotency handling, 250 ms debounced document observers, Firestore payload normalization, partial plan-cache writes that never gate camera/session flow, and `AppDependencies.firebasePartial()` so Firebase mode uses Firebase Auth plus these four Firestore repositories while workouts, trophies, and insights remain local. Wired `OnboardingStore`, `ThemeStore`, and `CalibrationStore` to load/observe/save remotely in Firebase mode, with local JSON kept only as a fast cache there. Added DEBUG Profile sync buttons for profile, calibration, and plan checks.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 364
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored local Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16D`

Focused Firestore repository tests covered profile conflict, idempotent retry, observer emission, and Firebase partial dependency composition. Mapper tests covered profile, calibration, and plan round trips. Local repository tests stayed green.

`git diff --check` passed. `gitleaks` was not installed. The fallback scanner initially found only intentional test fixtures for fake auth tokens and the privacy-validator fake private-key rejection payload; the changed/untracked non-ignored files scan passed after allowlisting those exact fixtures.

**Prevention Rule:**
Keep Firestore adoption explicit and partial by repository. Profile, theme, calibration, and plan cache may sync in Firebase mode, but workout summaries, trophies, insights, raw camera frames, raw pose streams, raw face data, and any secret-like values must not be uploaded by Phase 16D code. Remote plan cache must never be required to start or finish camera sessions.

**Pattern Tags:** #firebase #firestore #sync #local-first #privacy #debug-ui #tests

---

### [DL-052] Sync Workout Summaries With Firestore Option B Shape
**Date:** 2026-05-14
**Severity:** warning
**Category:** firestore-sync
**File(s):** `VirtualTrainer/Repositories/Firebase/FirestoreWorkoutRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainer/Repositories/Firebase/FirestorePathBuilder.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreMapper.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDTOs.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Repositories/SyncOrchestrator.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/WorkoutSessionSummary.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/UI/WorkoutDetailSheetView.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `VirtualTrainerTests/WorkoutHistoryStoreTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`

**Error:**
Phase 16E needed planned-workout and free-analysis summaries to sync to Firestore without embedding all set evidence in the parent workout document, without breaking local-only operation, and without storing raw camera, pose, face, or video data.

**Root Cause:**
Phase 16D intentionally left workouts local while lower-risk repositories moved to Firestore. Workout summaries carry compact rollups plus per-set evidence, so using a single embedded document would exceed the measured shape budget and make listener refreshes too heavy for cross-device history sync.

**Fix Applied:**
Added `FirestoreWorkoutRepository` for `users/{uid}/workouts/{workoutId}` plus deterministic `sets/{exerciseType}-set-{setIndex}` documents. Saves now validate `summary.accountId == uid`, encode the compact workout and set documents through the Firestore privacy validator, and commit a single write batch with the parent operation ID copied onto every set. Deletes are soft tombstones on the workout doc, reads filter `deletedAt == null`, detail loads fetch sets on demand, and recent listeners debounce compact emissions by 250 ms. Firebase-mode `WorkoutHistoryStore` now keeps local persistence first, then pushes workout saves/deletes remotely, merges observed compact remote summaries with local pending work, and lazy-loads detail in the detail sheet. Added a DEBUG-only serial `pushPendingWorkouts()` path in `SyncOrchestrator`.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 373
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Focused `FirestoreRepositoryTests` passed the compact write, deterministic set ID, same-operation retry, soft-delete, and compact-observer cases. Focused `WorkoutSummarySizeAuditTests` passed the documented compact estimate, max-set under 64 KB, and forbidden set payload rejection cases. Local-only no-plist build passed after temporarily moving the ignored local Firebase client plist out of the repo and restoring it immediately:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16E`

`git diff --check` passed. `gitleaks` was not installed, so the fallback `.gitleaks.toml` pattern scan over changed and new non-ignored files found no secret-like values. Existing Swift 6 concurrency warnings remain in Firestore observer debounce code and should be cleaned up in a follow-up before the toolchain flips those warnings to errors.

**Prevention Rule:**
Future Firestore workout changes must keep summaries split into one compact workout doc plus per-set evidence docs, validate all encoded payloads before writing, keep local persistence as the first commit point, preserve `BackendMode.local` and no-plist builds, and never serialize raw camera frames, raw pose streams, face data, video, or third-party secrets.

**Pattern Tags:** #firebase #firestore #workout-history #option-b #local-first #privacy #tests
