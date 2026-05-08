# Debug log (Spotter / VirtualTrainer)

Structured incident log for build failures, crashes, and bug fixes. **Format and categories:** `.cursor/rules/debugging.mdc` (section A).

- Append only — do not delete or rewrite past entries.
- Next entry ID: **DL-001** (after each append, the next agent reads the latest `### [DL-XXX]` and increments).

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
