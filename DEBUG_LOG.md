# Debug log (Spotter / VirtualTrainer)

Structured incident log for build failures, crashes, and bug fixes. **Format and categories:** `.cursor/rules/debugging.mdc` (section A).

- Append only — do not delete or rewrite past entries.
- Next entry ID: **DL-063** (after each append, the next agent reads the latest `### [DL-XXX]` and increments).

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

---

### [DL-053] Sync Trophy And Insight Memory Through Firestore
**Date:** 2026-05-15
**Severity:** warning
**Category:** firestore-sync
**File(s):** `VirtualTrainer/Repositories/Firebase/FirestoreTrophyRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreInsightRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainer/Repositories/Firebase/FirestorePathBuilder.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Repositories/LocalStoreRepositories.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `README.md`, `Documentation/FirestoreShape.md`, `Documentation/SyncConflictResolution.md`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
Phase 16F needed Firebase mode to sync trophy unlock events, derived trophy progress, insight documents, insight delivery aggregates, and insight engagement aggregates while preserving local mode, the live camera stack, planned workouts, deterministic local analytics, privacy boundaries, and no-plist builds.

**Root Cause:**
Phase 16D intentionally kept trophies and insights local while Firestore support proved the lower-risk profile/theme/calibration/plan paths first. The memory layer still lacked collection listeners, Firestore trophy/insight repositories, store-to-repository wiring after account claim, and aggregate merge behavior. One important mapper edge also surfaced during testing: generic nil `server*` timestamp injection is useful for remote sync metadata, but trophy progress must preserve the user's actual `earnedAt` moment and not let sync-write time become the displayed earned date.

**Fix Applied:**
Added Firestore repositories for `users/{uid}/trophyEvents/{eventId}`, optional `trophyProgress/current`, `users/{uid}/insights/{dedupeKey}`, `insightDelivery/{dedupeKey}`, and `insightEngagement/{dedupeKey}`. Trophy events use deterministic operation IDs, transactional duplicate checks, append-only active loads, derived earliest-earned progress, and debounced collection observation. Insights merge by `dedupeKey`, preserve newer `sourcePolicyVersion`, tombstone invalidated docs, and merge delivery/engagement aggregates with the documented earliest/latest/max/sum rules. Wired `TrophyStore` and `InsightStore` to observe and push remote changes in Firebase mode while keeping local mode unchanged, and kept all outgoing DTO payloads behind `FirestorePrivacyValidator`. Updated docs to describe the current partial Firebase boundary.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite was restarted on request and passed:

- Passed: 370
- Failed: 0
- Skipped: 0

The restarted required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored local Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16F`

Focused tests covered Firestore trophy event round-trip and idempotent duplicate write, earliest-earned trophy progress, coming-soon trophy suppression, insight policy-version replacement, delivery aggregate merge, engagement aggregate merge, insight invalidation hiding, and privacy-validator rejection of forbidden raw-pose payload keys.

`gitleaks` was not installed. The fallback scanner over changed and new non-ignored files found no secret-like values.

**Prevention Rule:**
When adding a Firestore repository for derived memory, decide whether server timestamps are metadata or user-facing chronology before using generic timestamp injection. Trophy and insight sync must upload only compact derived records, never raw video, frames, face data, pose streams, pose timelines, third-party secrets, or workout raw payloads. Local mode must remain the durable source of truth whenever Firebase config is absent.

**Pattern Tags:** #firebase #firestore #sync #trophies #insights #local-first #privacy #tests

---

### [DL-054] Audit Phase 16F Memory Sync After Interrupted Context
**Date:** 2026-05-15
**Severity:** warning
**Category:** firestore-sync
**File(s):** `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreInsightRepository.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `VirtualTrainerTests/InsightStoreTests.swift`, `VirtualTrainerTests/TrophyEngineTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
The restarted audit after a context compaction and lost stream found several Phase 16F edge-case misses: remote insight engagement aggregates could be counted again when listener snapshots echoed the same aggregate; a local engagement after a remote aggregate could push the whole aggregate back as a new delta; invalidating a missing remote insight document threw `notFound` instead of writing a tombstone; policy-version insight updates could refresh `serverCreatedAt` even though the write used merge semantics; coming-soon trophy suppression lacked a direct legacy-progress regression; and the Firebase write safety test still used Phase 16C wording that implied no production Firestore writes existed.

**Root Cause:**
The first implementation covered the main repository happy paths, but it blurred two distinct shapes: event deltas produced by the current device and aggregate snapshots returned by Firestore listeners. That let sum-based engagement merging be correct for incoming write deltas but unsafe for repeated remote snapshots. Generic Firestore helper behavior also made nil server timestamp injection look safe in all contexts, even when an existing server-owned creation timestamp needed to be preserved. The interrupted stream and context compaction fragmented the acceptance checklist, so the initial tests did not replay identical listener snapshots, spy on the exact payload sent after local engagement, invalidate a never-created insight doc, assert server-owned timestamp preservation, or exercise legacy earned coming-soon trophies.

**Fix Applied:**
Separated aggregate snapshot merging from delta merging in `InsightStore`, using max-per-kind engagement counts for remote snapshots and sum-only semantics in the Firestore repository transaction. Changed local engagement uploads to send a single-event delta while retaining the full local aggregate in memory. Updated missing-doc invalidation to merge a minimal tombstone at `users/{uid}/insights/{dedupeKey}`. Preserved existing `serverCreatedAt` on insight policy bumps. Added focused regression tests for listener idempotency, local-after-remote engagement payloads, missing insight tombstones, server-created timestamp preservation, coming-soon trophy event suppression, and the updated approved Firebase repository allowlist.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 374
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored local Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseAuditDerivedData16F`

Focused audit tests passed for `InsightStoreTests`, `FirestoreRepositoryTests`, and `TrophyEngineTests`. Protected live camera source files were not modified. `gitleaks` was not installed, and the fallback changed-file secret scan found no secret-like values.

**Prevention Rule:**
For sync aggregates, write tests that replay the same listener snapshot twice and separately assert the outbound write payload after a local mutation follows a remote merge. Treat operation deltas and persisted aggregate snapshots as different contracts. Firestore merge writes must explicitly preserve server-owned fields, and checklist-driven phases should be re-audited from the live tree after any context interruption before final verification.

**Pattern Tags:** #audit #firebase #firestore #insights #trophies #idempotency #listeners #privacy #tests

---

### [DL-055] Coordinate Manual Push Pull And Listener Sync
**Date:** 2026-05-15
**Severity:** warning
**Category:** firestore-sync
**File(s):** `VirtualTrainer/Repositories/SyncOrchestrator.swift`, `VirtualTrainer/Models/SyncConflictsStore.swift`, `VirtualTrainer/Models/SyncMetadata.swift`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Models/ThemeStore.swift`, `VirtualTrainer/Models/WorkoutSessionContext.swift`, `VirtualTrainer/Repositories/RepositoryProtocols.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreWorkoutRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreTrophyRepository.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainer/UI/TrainerSessionView.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainerTests/SyncOrchestratorTests.swift`

**Error:**
Phase 16G needed `SyncOrchestrator` to become a real manually triggered push, pull, and listener coordinator while preserving local mode, no-plist builds, both training flows, live camera safety, deterministic local planning, trophies, stats, trends, recaps, heatmaps, AI insights, and the privacy boundary around raw camera, pose, face, and secret data.

**Root Cause:**
The prior orchestrator was a scaffold, while store-owned Firebase listeners made it hard to reason about a single sync lifecycle. Conflict handling also had nowhere durable to surface failed records. The current `LocalWriteJournal` is an idempotency ledger for completed operation IDs rather than a pending payload queue, so replaying journal entries directly would have required inventing a second serialization contract and risked breaking existing local JSON. Recent workout pulls also loaded visible records only, which meant a remote tombstone could be missed by another local cache.

**Fix Applied:**
Implemented manual `pullRemote`, `pushPendingLocal`, `startListeners`, `stopListeners`, and `performFullSync` phases with local-mode no-op behavior. The orchestrator now owns listener attachment for profile, recent workouts, trophy events, and insights, uses debounced repository emissions, defers heavy sync while `WorkoutSessionContext.isLive` is true, and resumes deferred work when the workout ends. Store updates gained `applyRemote*` paths that mark incoming records synced, deduplicate identical sync metadata, and update published state on the main actor without replay loops. Pending push replay reads records already marked `.pendingUpload`, conflicts mark records `.conflict`, and conflict summaries persist through the new capped `SyncConflictsStore`. Added a tombstone-aware workout repository hook so delete propagation can hide records on another device without changing the visible recent-workout query contract. Profile debug UI now exposes run full sync, push pending writes, pull remote, start listeners, stop listeners, status, last sync time, pending upload count, conflict count, listener state, and sanitized last error.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 389
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Focused `SyncOrchestratorTests` passed local-mode no-op, pending upload replay, conflict surfacing and skip behavior, listener deduplication, tombstone propagation, and live-workout deferral. Local-only no-plist build passed after temporarily moving the ignored Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16G`

`gitleaks` was not installed, and the fallback changed-file secret scan found no secret-like values. `git diff --check` passed.

**Prevention Rule:**
Keep sync manually triggered until Phase 17 wires automatic background scheduling. Any heavy push or pull must check the live workout guard before starting, and listener-driven updates must stay tombstone-aware and metadata-deduped. New sync code must preserve `BackendMode.local`, no-plist builds, backward-compatible local Codable decoding, and the rule that raw video, camera frames, face images, raw pose streams, raw pose timelines, biometric face data, blendshape streams, and third-party secrets are never stored or uploaded.

**Pattern Tags:** #sync #firebase #firestore #local-first #listeners #conflicts #privacy #workout-safety #tests

---

### [DL-056] Audit Phase 16G Sync After Context Compaction
**Date:** 2026-05-15
**Severity:** warning
**Category:** firestore-sync
**File(s):** `VirtualTrainer/Repositories/SyncOrchestrator.swift`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainerTests/SyncOrchestratorTests.swift`, `VirtualTrainerTests/InsightStoreTests.swift`

**Error:**
The post-compaction audit found that Phase 16G's manual sync implementation still had edge cases around full-sync ordering and aggregate listener merges. `performFullSync` intentionally pulls before pushing, but profile, calibration, and insight apply paths could accept stale remote data over a local `.pendingUpload` record before that record was replayed. Insight delivery and engagement save acknowledgements could also leave aggregate records marked `.pendingUpload`, causing repeated uploads. The first full-suite rerun after hardening then exposed a second-order regression: remote insight delivery tombstones and remote engagement aggregates were skipped whenever a local pending auxiliary record already existed.

**Root Cause:**
The original implementation focused on making the no-op orchestrator real and verified the central workout/listener/tombstone paths first. That covered the visible two-device acceptance flow but did not prove the pull-before-push invariant against every account-aware store, especially singleton stores and insight auxiliary aggregates. The `LocalWriteJournal` wording in the phase contract also invited a journal-drain mental model, while the actual codebase journal only stores operation IDs and entity kinds, not replayable payloads. After context compaction and a lost stream, the checklist was resumed from summarized state, so tests were added for orchestrator behavior but not enough store-level cross-checks for stale singleton pulls, aggregate ack clearing, and existing insight tombstone semantics. The audit fix briefly over-corrected by skipping pending insight auxiliary records entirely, which preserved pending writes but blocked legitimate remote aggregate and tombstone merges.

**Fix Applied:**
Added `allowReplacingPending` apply paths for profile, calibration, insights, insight delivery, and insight engagement. Normal pull/listener emissions now mark incoming records as synced and dedupe identical metadata while preserving local pending or conflict ownership where overwriting would lose a still-unpushed mutation. Orchestrator save acknowledgements use `allowReplacingPending: true` so successful repository saves clear pending metadata and stop repeat uploads. Insight delivery and engagement now merge remote aggregate contents even when a local pending record exists, keep pending metadata for unsent local deltas, and let remote tombstones win so deleted auxiliary records no longer suppress future selection. Added regression tests for full sync not clobbering pending profile/calibration, insight delivery ack clearing and no replay, and kept the existing insight tombstone/aggregate tests passing.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed after the audit fixes:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed after the audit fixes:

- Passed: 392
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Focused `SyncOrchestratorTests` passed 9/9, including local-mode no-op, pending upload replay, conflict surfacing, listener dedupe, tombstone propagation, live-workout deferral, and the new pull-before-push singleton regressions. Focused `InsightStoreTests` passed after correcting the auxiliary aggregate merge regression. Local-only no-plist build passed after temporarily moving the ignored Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseAuditDerivedData16G`

Protected live camera pipeline files were not modified.

**Prevention Rule:**
For every future sync phase, prove pull-before-push with a local pending record plus a stale remote version for each store shape: singleton, list, aggregate, and tombstone. Ack paths must have explicit tests showing pending metadata clears and repeated push becomes a no-op. Listener merge tests must include both repeated identical snapshots and remote tombstones arriving while a local pending auxiliary record exists. Do not treat `LocalWriteJournal` as a replay payload queue unless its schema is deliberately migrated to store replayable record references or payloads.

**Pattern Tags:** #audit #sync #firebase #firestore #local-first #listeners #conflicts #pending-upload #tombstones #privacy #tests

---

### [DL-057] Lock Down Firestore Rules And App Check Prep
**Date:** 2026-05-15
**Severity:** warning
**Category:** firebase-security
**File(s):** `Documentation/firestore.rules`, `Documentation/FirebaseConsoleChecklist.md`, `Documentation/AppCheckRollout.md`, `VirtualTrainer.xcodeproj/project.pbxproj`, `VirtualTrainer/Services/FirebaseBootstrap.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`

**Error:**
Phase 16H needed the Firebase server boundary to catch up with the repository layer before wider backend testing. Without owner-only Firestore rules, App Check rollout notes, and repository-level payload assertions, a Firebase-mode development build could compile while the manual console setup or a future repository write drifted outside the intended account and privacy boundary.

**Root Cause:**
Earlier Phase 16 work deliberately added Firebase repositories behind a feature flag before publishing production-ready rules or App Check enforcement. The existing DTO privacy tests verified representative encodable models, but they did not inspect every repository write payload produced by realistic save, update, tombstone, and aggregate paths. Firebase App Check was already available through the Firebase package graph, but the app target did not link the App Check product or install a DEBUG-only provider before `FirebaseApp.configure()`.

**Fix Applied:**
Added the v1 owner-only Firestore rules document with default deny, user ownership checks, delete-by-tombstone behavior for durable sync records, user-cleared plan deletion, raw-sensor and secret-like field-name denial, and a Phase 16J TODO for schema-level required-field and type validation. Added Firebase Console and App Check rollout documentation covering anonymous auth only, Firestore rule publishing, no initial composite indexes, debug App Check registration without enforcement, disabled Storage/RTDB, no Functions deployment, and manual cross-uid denial smoke testing. Linked `FirebaseAppCheck` into the app target and installed `AppCheckDebugProviderFactory` only in DEBUG before Firebase configures. Added repository privacy assertion coverage that captures realistic in-memory Firestore writes for profile, theme, calibration, plans, workouts, workout sets, workout tombstones, trophies, insights, insight delivery, and insight engagement, then verifies each payload stays within the published DTO key set and avoids forbidden raw data or secret-like keys.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 392
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Focused repository privacy assertion test passed. Local-only no-plist build passed after temporarily moving the ignored Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData-local-no-plist SPOTTER_BACKEND_MODE=local`

Firebase-mode build-setting override passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData-firebase-mode SPOTTER_BACKEND_MODE=firebase`

Protected live camera pipeline files were not modified. No raw video, camera frame, face image, raw pose stream, raw pose timeline, biometric face data, face blendshape stream, or third-party secret field is introduced by the new repository payload test fixtures.

**Prevention Rule:**
Every new Firestore write path must have a repository-level payload assertion that captures the actual encoded write and compares it with the DTO's published key set plus the raw-data and secret-field denylist. Keep App Check enforcement off until debug-token onboarding, owner-only rule smoke tests, and Phase 17 emulator automation prove the dev workflow and denial paths. Firestore rule changes must stay documented with console steps and must preserve `BackendMode.local` no-plist builds.

**Pattern Tags:** #firebase #firestore-rules #app-check #privacy #repository-tests #local-first #backend-mode #security

---

### [DL-058] Audit Phase 16H Repository Payload Coverage After Compaction
**Date:** 2026-05-15
**Severity:** warning
**Category:** test-coverage
**File(s):** `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `DEBUG_LOG.md`

**Error:**
The post-compaction Phase 16H audit found that the newly added repository privacy test did not fully prove its own acceptance claim. It captured and validated every write that happened during the fixture run, but it only asserted a minimum write count. Because the in-memory Firestore test double compared JSON-encoded boolean fields by `String(describing:)`, `NSNumber(true)` did not match the Swift `true` filter value. That caused the second active-plan save fixture to miss the prior active plan and skip the inactive-plan update payload, while the test still passed under the loose `>= 14` write-count assertion.

**Root Cause:**
The production Firestore repository path was reviewed correctly, but the audit surface shifted into test fidelity: `FirestorePlanRepository.saveActivePlan` relies on an `active == true` query before deactivating older active plans. Real Firestore handles boolean filters natively; the in-memory test double approximated filters with string comparison, which is not type-faithful after `JSONSerialization` turns booleans into `NSNumber`. The miss survived the first pass because the test validated payload privacy after capture rather than proving each intended repository write category had been captured. The context compaction and lost stream also encouraged resuming from a checklist summary and green full-suite result instead of replaying the exact write trace category by category. The early shell mistakes during verification (`status` as a zsh read-only variable and a misquoted fallback secret-scan regex) were process noise, not product defects, but they are the same class of risk: after interruption, every assertion and command should be re-derived from live output instead of trusted from memory.

**Fix Applied:**
Hardened the repository privacy test with exact write-category assertions for full profile save, profile-backed theme patch, calibration save, two active plan saves, inactive-plan update, workout summary, two workout set documents, workout tombstone, trophy event append, full insight save, insight tombstone, insight delivery, and insight engagement. Added a key-only write summary to the count failure message so future misses can be diagnosed without logging secret values. Fixed the in-memory Firestore filter matcher to treat `NSNumber` and `Bool` values equivalently for boolean filters while preserving the existing `NSNull` and string fallback behavior. This makes the test double exercise the same active-plan deactivation path the live Firestore query would exercise.

**Verification:**
Focused repository privacy test passed after the audit fix:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData -only-testing:VirtualTrainerTests/FirestoreRepositoryTests/testRepositoryWritePayloadsMatchPublishedDTOKeysAndPrivacyBoundary`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 392
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored Firebase client plist out of the repo and restoring it immediately afterward:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData-local-no-plist SPOTTER_BACKEND_MODE=local`

Firebase-mode build-setting override passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData-firebase-mode SPOTTER_BACKEND_MODE=firebase`

Protected live camera pipeline files were not modified.

**Prevention Rule:**
Repository privacy tests must prove both payload shape and path coverage. Do not accept aggregate write counts as coverage for multi-repository fixtures; assert the expected path/kind/category for every intended write. In-memory Firestore doubles must compare filtered values by Firestore semantics, not only string descriptions, especially for `Bool`, `NSNull`, server timestamp stand-ins, and future typed query values. After a context compaction, lost stream, or command failure, re-run the exact focused assertion that would fail if the missed path were absent before trusting a full-suite green result.

**Pattern Tags:** #audit #test-coverage #firestore #repository-tests #privacy #plans #local-first #compaction #verification

---

### [DL-059] Add Firebase-Mode Account Deletion And Remote Export
**Date:** 2026-05-16
**Severity:** warning
**Category:** privacy-compliance
**File(s):** `VirtualTrainer/Services/AccountDeletionService.swift`, `VirtualTrainer/Services/DataExportService.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainerTests/ComplianceServicesTests.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `Documentation/FirebaseFunctionsPlan.md`, `Documentation/FirebaseConsoleChecklist.md`, `README.md`, `DEBUG_LOG.md`

**Error:**
Phase 16I needed the in-app Apple account deletion path to work in Firebase mode, including automatically created anonymous accounts. Before this phase, the visible Profile account controls were effectively local-file compliance tools: they wiped the device and exported local JSON, but they did not coordinate Firebase auth deletion, sync listener shutdown, bounded client-side Firestore cleanup, or remote export labeling.

**Root Cause:**
The backend mode layer had already been introduced for repositories and sync, but the compliance services still treated account deletion and export as device-only operations. Firestore rules intentionally allow the iOS client to hard-delete only limited user-owned plan documents; durable profile, workout, trophy, insight, theme, and calibration cleanup needs an Auth-triggered Cloud Function using Admin SDK privileges. The local plan cache also lived outside the original export/delete file list, so a device wipe could leave `WorkoutPlans.json` behind even though planned workouts are now a core persisted flow.

**Fix Applied:**
Made `AccountDeletionService.deleteAccountAndData` mode-aware. Local and current Supabase placeholder modes keep the local wipe path, while Firebase mode stops sync listeners, waits for all local store writes including plans, attempts `Auth.auth().currentUser.delete()` through `FirebaseAuthRepository.deleteAccount()`, performs a bounded client-allowed Firestore delete of `users/{uid}/plans`, wipes local files, clears `AccountContext`, and returns a non-blocking cloud-delay notice if any cloud step partially fails. Made deletion idempotent so a second run after account clear still wipes local state and clears context.

Extended `DataExportService` so local exports include plans and Firebase exports add server-side snapshots as clearly labeled `*.remote.json` files for profile, workouts with sets, trophy events, insights with delivery and engagement, calibration, theme, and plans. Per-category remote failures now leave the archive successful with a README note instead of blocking the user. Updated Profile Account UI to always expose Export and Delete, require typing `DELETE` for destructive deletion, show local vs Firebase subtitles, and route back to onboarding after deletion. Added `Documentation/FirebaseFunctionsPlan.md` documenting the future `spotter-functions` repo plan for `onAuthUserDelete`, nightly tombstone vacuum, optional operation-id dedupe, and future LLM rewrite proxy, with an explicit rule that service account keys never ship in the iOS repo.

**Verification:**
Toolchain paths resolve under XcodeDefault:

`xcrun --find clang`

`xcrun --find swiftc`

Focused compliance and Firestore cleaner tests passed before the full run:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData -only-testing:VirtualTrainerTests/ComplianceServicesTests -only-testing:VirtualTrainerTests/FirestoreRepositoryTests/testAccountDeletionCleanerDeletesOnlyClientAllowedPlansWithinBound`

Required build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed:

- Passed: 399
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored Firebase client plist out of the repo and restoring it immediately afterward:

`SPOTTER_BACKEND_MODE=local xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16I`

`gitleaks` was not installed locally, so a redacted fallback scan over changed and new files checked common Firebase, OpenAI, GitHub, Slack, password, and private-key credential formats and found no secret-like patterns. Protected live camera pipeline files were not modified.

**Prevention Rule:**
Future compliance changes must branch by `BackendMode` explicitly and preserve the local no-plist path before adding cloud behavior. Client-side Firestore deletion must stay bounded to rule-allowed data and must never pretend to replace the Auth-triggered server-side fan-out. Every persisted local store added to a training flow must be included in both account deletion and data export, with backwards-compatible empty exports for missing legacy files. Remote export failures should be reported in the archive README, not turned into a user-blocking export failure.

**Pattern Tags:** #privacy-compliance #account-deletion #firebase #firestore #data-export #cloud-functions #local-first #backend-mode #apple-compliance #no-plist

---

### [DL-060] Audit Phase 16I After Compaction And Lost Stream
**Date:** 2026-05-16
**Severity:** warning
**Category:** audit
**File(s):** `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainer/Services/DataExportService.swift`, `Documentation/FirebaseFunctionsPlan.md`, `DEBUG_LOG.md`

**Error:**
The post-implementation audit found that Phase 16I's core service behavior was present and passing tests, but one user-facing requirement was not actually robust in the live UI: when Firebase deletion had a partial cloud failure, `AccountDeletionService` returned the required "Some cloud data may take up to 7 days to delete" notice, and `ProfileView` assigned it to `accountStatusMessage`, but the same success path immediately reset onboarding. That routes the user away from Profile, so the notice could disappear before being seen. The audit also found two documentation/privacy-consistency nits: the export `schemaVersions.json` privacy boundary did not mention raw face blendshape streams even though the README text did, and the Functions plan described service account handling a little more broadly than the prompt's explicit Firebase project secret requirement.

**Root Cause:**
The implementation resumed after a context compaction and lost stream with a green focused-test result and a summary of the intended work. That made it too easy to validate service-level return values and command-level success while under-checking the UI lifetime of those values. The existing tests asserted that the notice was produced by the service, not that the notice survived the Profile-to-onboarding route transition. The docs nit happened because the privacy boundary text exists in multiple places (`README.txt`, `schemaVersions.json`, Firestore docs, and Functions docs), and the first pass updated the user-readable README path but did not compare every repeated privacy phrase byte-for-byte. The service account wording was safe, but it was not as literal as the user's requested Functions plan language.

**Fix Applied:**
Added a post-deletion completion alert in `ProfileView` for partial cloud-deletion notices. The app now dismisses the destructive confirmation sheet, shows the cloud-delay message in an alert, and only routes back to onboarding after the user taps Continue. Successful no-warning deletion still routes immediately. Updated the export schema privacy boundary to include raw face blendshape streams, matching README wording. Tightened `Documentation/FirebaseFunctionsPlan.md` to state that any dedicated service account material belongs only in Firebase project secrets and never in the iOS repository.

**Verification:**
Required build passed after the audit patch:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required test suite passed after the audit patch:

- Passed: 399
- Failed: 0
- Skipped: 0

The required test command was:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Local-only no-plist build passed after temporarily moving the ignored Firebase client plist out of the repo and restoring it immediately afterward:

`SPOTTER_BACKEND_MODE=local xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoFirebaseDerivedData16I`

`git diff --check` passed. `gitleaks` was not installed locally, so a redacted fallback scan over changed and new files checked common Firebase, OpenAI, GitHub, Slack, service-account JSON, password, and private-key credential formats and found no secret-like patterns. Protected live camera pipeline files were not modified.

**Prevention Rule:**
After any context compaction, lost stream, or large generated patch, re-audit every user-facing requirement at the presentation boundary, not only at the service/API boundary. If a requirement says "surface" or "route", prove the value is still visible after state changes and navigation. Repeated privacy and secrets-policy phrases must be searched globally and updated consistently across export metadata, README text, docs, and tests. Green tests are not enough when no test observes the UI lifetime of a returned service result.

**Pattern Tags:** #audit #compaction #lost-stream #account-deletion #firebase #ui-routing #privacy-boundary #documentation #verification

---

### [DL-061] Re-Audit Firebase Deletion Order, Config Fallbacks, And Observer Concurrency
**Date:** 2026-05-16
**Severity:** crash-prevention
**Category:** firebase, compliance, concurrency, xcode-config
**File(s):** `VirtualTrainer/Services/AccountDeletionService.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreRepositorySupport.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreCalibrationRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreInsightRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreProfileRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreThemeRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreTrophyRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreWorkoutRepository.swift`, `VirtualTrainer/Models/CalibrationStore.swift`, `VirtualTrainer/Models/InsightStore.swift`, `VirtualTrainer/Models/OnboardingStore.swift`, `VirtualTrainer/Models/ThemeStore.swift`, `VirtualTrainer/Models/TrophyModels.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer.xcodeproj/project.pbxproj`, `VirtualTrainerTests/ComplianceServicesTests.swift`, `Documentation/DEVELOPMENT_SETUP.md`, `Documentation/FirebaseFunctionsPlan.md`, `README.md`

**Error:**
The deep Phase 15/16 audit found Firebase wiring present, but several high-confidence failure edges remained: Firebase-mode account deletion attempted Auth deletion before the bounded client-allowed Firestore cleanup, Firestore query/listener wrappers could pass a non-positive limit to the Firebase SDK, Release/Beta builds could silently fall back to a generic local debug `GoogleService-Info.plist`, and Firebase observer streams used mutable captured `debounceTask` locals that Xcode warned would become Swift 6 language-mode errors. Release also surfaced redundant `await` warnings in store observation error handlers.

**Root Cause:**
Account deletion ordering treated Firebase Auth deletion as an early step even though owner-only Firestore rules require the user to still be authenticated for the small client-side plan cleanup. Repository callers already normalized invalid limits to zero, but the Firebase adapter forwarded zero into Firestore query construction instead of returning an empty result/listener. The Firebase config copy phase had an over-broad generic fallback and a malformed dev-candidate derivation (`${PLIST_NAME%.plist}-Dev.plist`), so non-debug builds could bundle a local ignored debug plist when the environment plist was absent. The observer debounce implementation stored a mutable task variable inside escaping listener closures that may be invoked concurrently by the SDK. The redundant `await`s were leftover from earlier actor-isolation churn: the tasks already execute in the inherited main-actor context, and the error setters are synchronous.

**Fix Applied:**
Reordered Firebase account deletion to stop listeners, wait for local writes, perform bounded Firestore cleanup while auth is still alive, then delete the Auth account, wipe local data, and clear account context. Added a regression test that proves the remote cleaner still sees the current Firebase account during cleanup. Made Firebase Firestore query/listener calls return empty results and no-op listeners for non-positive limits instead of touching `limit(to:)`. Tightened the Firebase config copy script so generic `GoogleService-Info.plist` is a Debug-only fallback; Release/Beta now use only their configured environment plist names and otherwise build local-only. Replaced the per-observer captured mutable debounce task with a small locked `FirestoreObserverDebouncer`, then removed redundant `await`s from synchronous observation error setters. Updated setup and Firebase Functions docs to match the corrected deletion and config behavior.

**Verification:**
Full final test suite passed on iPhone 17 Pro simulator:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerAuditFullDerivedDataFinal`

- Passed: 400
- Failed: 0
- Skipped: 0

Focused Firebase/compliance/backend tests also passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerAuditDerivedData -only-testing:VirtualTrainerTests/FirestoreRepositoryTests -only-testing:VirtualTrainerTests/ComplianceServicesTests -only-testing:VirtualTrainerTests/BackendRepositoryTests`

Release simulator build passed and proved the non-debug config fallback is closed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerAuditReleaseDerivedData`

The Release log only showed the intentional Firebase config message, `No Firebase client config found; building in local-only mode.`, and no longer showed the captured-var or redundant-await warning families. `git diff --check` passed. `gitleaks` is not installed locally, so a redacted fallback scan over changed tracked files checked common Firebase, OpenAI, GitHub, Slack, password/token/API-key, authorization, and private-key patterns and found no matches. Static crash-surface search found only a planned Firestore-rules TODO and the existing programmer-error `preconditionFailure` for an invalid static privacy regex; neither is a live user crash path. Live Firebase smoke against a remote project was not run because this audit did not use live project credentials.

**Prevention Rule:**
For account deletion, keep client-allowed Firestore cleanup before Auth deletion whenever security rules depend on `request.auth.uid`; leave recursive cleanup to Cloud Functions. Treat zero or negative repository limits as empty results before calling SDK query builders. Non-debug builds must never fall back to generic local debug Firebase plist names. Firebase listener state must live behind an explicit synchronization boundary, not a mutable captured local. When Release introduces Swift concurrency warnings, clear high-confidence ones immediately because they often represent future build failures.

**Pattern Tags:** #firebase #account-deletion #firestore #config #concurrency #crash-prevention #rca

---

### [DL-062] Post-Compaction Re-Audit Of Firebase Edge Cases
**Date:** 2026-05-16
**Severity:** crash-prevention
**Category:** audit, firebase, concurrency, account-deletion
**File(s):** `VirtualTrainer/Repositories/Firebase/FirestoreRepositorySupport.swift`, `VirtualTrainer/Services/AccountDeletionService.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreInsightRepository.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `VirtualTrainerTests/ComplianceServicesTests.swift`, `DEBUG_LOG.md`

**Error:**
The follow-up audit after context compaction found two additional high-confidence edges that could affect Firebase downstream behavior. The shared Firestore observer debouncer canceled the previous task, but a task that had already awakened could still win a rapid-listener-update race and yield a stale event. Firebase account deletion also trusted the UI/account-context account ID first; if the context was stale or nil while Firebase Auth still had a current user, client-allowed Firestore cleanup and Auth deletion could be skipped. The focused build also surfaced an unused Firestore transaction return-value warning.

**Root Cause:**
The first pass correctly removed mutable captured debounce-task locals, but cancellation alone was not a complete generation check for listener interleavings. The deletion flow correctly moved Firestore cleanup before Auth deletion, but it still treated `AccountContext` as the source of truth even though owner-scoped Firestore rules and Auth deletion depend on Firebase Auth's live current user. The transaction warning was a leftover from an intentionally ignored SDK result.

**Fix Applied:**
Made `FirestoreObserverDebouncer` generation-aware under its lock, so only the most recent scheduled listener operation can yield and cancellation invalidates all pending generations. Changed Firebase deletion to prefer the live Auth repository account ID and fall back to the context account ID only when Auth has no current account. Marked the intentionally unused transaction result with `_ =`. Added regression coverage for latest-only debouncing, cancel-dropping pending debounced operations, and stale account-context deletion using the live Auth UID.

**Verification:**
Focused compliance and Firestore repository tests passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerCompactionAuditDerivedData -only-testing:VirtualTrainerTests/ComplianceServicesTests -only-testing:VirtualTrainerTests/FirestoreRepositoryTests`

Release simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerCompactionReleaseDerivedData`

Full final test suite passed on iPhone 17 Pro simulator:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerCompactionFullDerivedData`

- Passed: 403
- Failed: 0
- Skipped: 0

`git diff --check` passed. `gitleaks` is not installed locally, so a redacted fallback scan over changed tracked files checked common Firebase, OpenAI, GitHub, Slack, password/token/API-key, authorization, and private-key patterns and found no matches. Live Firebase smoke against a remote project was not run because this audit did not use live project credentials.

**Prevention Rule:**
After context compaction, re-audit timing and state-source boundaries in addition to the visible patch diff. Listener debouncers should use a generation token, not cancellation alone, when callbacks can arrive rapidly. Cloud cleanup and Auth deletion should prefer the live Auth identity whenever Firestore rules or SDK operations depend on the authenticated user.

**Pattern Tags:** #audit #compaction #firebase #firestore #account-deletion #concurrency #crash-prevention #rca

---

### [DL-063] Phase 16J Remote Config, Analytics, Crashlytics, And App Check Readiness
**Date:** 2026-05-16
**Severity:** feature-readiness
**Category:** firebase, remote-config, analytics, crashlytics, app-check, privacy
**File(s):** `VirtualTrainer/Services/FeatureFlags.swift`, `VirtualTrainer/Services/RemoteFeatureFlagService.swift`, `VirtualTrainer/Services/AnalyticsService.swift`, `VirtualTrainer/Services/CrashReportingService.swift`, `VirtualTrainer/Services/AppRuntime.swift`, `VirtualTrainer/Services/FirebaseBootstrap.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/Repositories/BackendStatusStore.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/Models/DashboardData.swift`, `VirtualTrainer/Services/PlanService.swift`, `VirtualTrainer/Services/QuickStartPlanDeckService.swift`, `VirtualTrainer/UI/CameraTabView.swift`, `VirtualTrainer/UI/HomeDashboardView.swift`, `VirtualTrainer/UI/OnboardingViews.swift`, `VirtualTrainer/UI/CalibrationViews.swift`, `VirtualTrainer/UI/WorkoutPreviewView.swift`, `VirtualTrainer/UI/PlannedWorkoutSessionView.swift`, `VirtualTrainer/UI/WorkoutSummaryView.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainer/UI/TrainingHeatmapView.swift`, `VirtualTrainerTests/Phase16JServicesTests.swift`, `VirtualTrainerTests/BackendRepositoryTests.swift`, `Documentation/AppCheckRollout.md`, `Documentation/FirebaseConsoleChecklist.md`, `VirtualTrainer.xcodeproj/project.pbxproj`

**Error:**
Phase 16J required Firebase Remote Config, Analytics, Crashlytics, and App Check enforcement readiness after the core Auth/Firestore sync path was stable. The app still needed to keep `BackendMode.local` fully usable without `GoogleService-Info.plist`, avoid Firebase calls in unit tests/local mode, preserve deterministic local planning defaults, and avoid collecting raw camera, pose, face, or PII payloads.

**Root Cause:**
The Phase 16A-G Firebase work intentionally focused on Auth/Firestore sync first. Feature flags were static local Codable values, telemetry had no privacy-bounded service abstraction, Crashlytics launch context was not centralized, and App Check had only the DEBUG debug-provider path. Unit tests also needed a hard guard around Firebase bootstrap because SDK initialization can emit diagnostics and reach runtime code that is outside the deterministic local test boundary.

**Fix Applied:**
Added `RemoteFeatureFlagService` with bundled `FeatureFlags.default` defaults and Firebase Remote Config overrides that apply only after a successful fetch. Added backwards-compatible Codable defaults for new flags: `backendSyncEnabled`, `coachInsightLLMRewrite`, `quickStartDeckVersion`, `trophyCatalogVersion`, `runningAnalysisEnabled`, and `designSystemV2Enabled`. Added privacy-bounded `AnalyticsService` implementations for Firebase and local/test no-op mode, with a fixed no-PII event taxonomy for app open, onboarding, calibration, workout saves, trophies, insights, share-card rendering, and sync errors. Added `CrashReportingService` with Firebase and no-op implementations, launch custom keys for backend mode/schema versions, and SHA-256 account-id prefixing instead of display-name identifiers. Updated Firebase bootstrap to keep DEBUG App Check debug provider support and use App Attest on iOS 14.5+ release devices, with DeviceCheck fallback, while leaving enforcement to the Firebase Console. Added documentation for staged App Check rollout and Firebase console setup. Preserved the live camera analysis stack by only wiring analytics at flow boundaries and leaving the protected pipeline files unchanged.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Required simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required full test suite passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 408
- Failed: 0
- Skipped: 0

Focused Phase 16J service tests passed before the full run. `git diff --check` passed. `gitleaks` is not installed locally, so a redacted fallback scan over changed and untracked files checked common Firebase, OpenAI, GitHub, Slack, password/token/API-key, authorization, and private-key patterns and found no matches. Static diff search confirmed no changes to the protected live camera pipeline files listed in the Phase 16J prompt.

**Prevention Rule:**
Firebase observability features must sit behind local/test-safe protocols before UI flows call them. Remote Config must never be required for app launch or deterministic local planning; failed fetches keep bundled defaults. Analytics payloads must be enumerated and privacy-guarded, never raw rep streams, raw pose timelines, raw camera frames, raw face data, display names, age, gender, or secret-like values. App Check enforcement remains a console rollout step after physical-device App Attest validation.

**Pattern Tags:** #phase16j #remote-config #analytics #crashlytics #app-check #privacy #local-mode #firebase

---

### [DL-064] Post-Compaction Phase 16J Safety Audit And Kill-Switch Hardening
**Date:** 2026-05-16
**Severity:** crash-prevention
**Category:** audit, remote-config, firebase, privacy, launch-sequencing
**File(s):** `VirtualTrainer/Services/FeatureFlags.swift`, `VirtualTrainer/Services/RemoteFeatureFlagService.swift`, `VirtualTrainer/Services/AnalyticsService.swift`, `VirtualTrainer/Repositories/AppDependencies.swift`, `VirtualTrainer/VirtualTrainerApp.swift`, `VirtualTrainer/UI/HomeDashboardView.swift`, `VirtualTrainer/UI/WorkoutPreviewView.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainerTests/Phase16JServicesTests.swift`, `DEBUG_LOG.md`

**Error:**
The post-compaction audit found that Phase 16J's `backendSyncEnabled` Remote Config kill switch stopped full sync/listeners, but store-level remote save paths and direct active-plan cache writes could still reach Firebase repositories after the flag changed. There was also a startup edge where Firebase sync could begin before the first Remote Config attempt completed, a backwards-compatibility gap for older `FeatureFlags` JSON files that still used the legacy `enabledFlags` shape, an analytics privacy guard that matched only exact forbidden key spellings, and two new synchronous unit tests that crashed during teardown when XCTest deallocated main-actor repository-backed `AppDependencies`.

**Root Cause:**
The first Phase 16J pass treated the kill switch mostly as a sync-orchestrator concern, but the app also has local stores configured with remote repositories and direct plan-cache writes from dashboard/preview flows. Remote Config defaults were correctly local-first, but there was no explicit "initial Remote Config attempt completed" state to prevent early Firebase writes before a fetched kill-switch value could apply. The new `FeatureFlags` `Codable` implementation replaced synthesized decoding without preserving the old private `enabledFlags` storage key. The analytics privacy guard compared raw parameter keys, so separator/case variants such as `display_name` were not normalized. The XCTest crash was a test-harness lifetime issue caused by creating and dropping `@MainActor` dependency graphs inside synchronous test methods.

**Fix Applied:**
Made `RemoteFeatureFlagService` publish `hasCompletedInitialRefresh` and expose `allowsBackendSync`, which requires both an initial Remote Config attempt and `backendSyncEnabled=true`. Launch now refreshes feature flags before configuring store remote repositories or observing Firebase auth changes, and store remote sync is configured as local when `allowsBackendSync` is false. Dashboard, workout preview, and debug sync tools now use the same guard before direct Firebase plan/sync actions. Restored legacy `FeatureFlags` decoding from `enabledFlags` while keeping explicit new keys authoritative. Normalized analytics privacy key checks by stripping non-alphanumerics and lowercasing before comparison. Kept Firebase Analytics and Crashlytics no-op in unit tests even when a test forces Firebase mode, and converted the affected dependency-wiring tests to async XCTest methods to match the repo's existing main-actor dependency test pattern.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Focused Phase 16J tests passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerPhase16JAuditFocusedDerivedData -only-testing:VirtualTrainerTests/Phase16JServicesTests`

Required simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required full test suite passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 413
- Failed: 0
- Skipped: 0

No-plist local fallback build passed after temporarily moving local ignored Firebase client plist files out of the workspace and restoring them with a shell trap:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoPlistDerivedData`

The build printed the expected local-only warning and did not require `GoogleService-Info.plist`.

`git diff --check` passed. `gitleaks` is not installed locally, so a redacted `.gitleaks.toml`-aligned fallback scan over changed and untracked files checked common Firebase, OpenAI, GitHub, Slack, password/token/API-key, authorization, private-key, and App Check debug-token-context patterns and found no candidate secrets. A static diff search confirmed no changes to the protected live camera pipeline files listed in the Phase 16J prompt. Firebase SDK entrypoint search confirmed Remote Config, Analytics, Crashlytics, and App Check SDK calls remain inside service/bootstrap wrappers instead of UI or live camera pipeline files.

**Prevention Rule:**
Remote kill switches must gate every write path, not only orchestrator-level listeners. For Firebase startup, wait for the first Remote Config attempt before enabling backend writes so remote-off values can win before sync begins; failed fetches may then fall back to bundled defaults. When replacing synthesized `Codable` on persisted local types, explicitly decode the previous storage shape. Privacy guards should normalize keys before denylist checks, and unit tests should exercise main-actor dependency graphs through async XCTest methods.

**Pattern Tags:** #phase16j #post-compaction-audit #remote-config #kill-switch #firebase #privacy #codable #xctest #local-mode

---

### [DL-065] Phase 17 Backend Beta QA, Emulator, Cost, And Backpressure Hardening
**Date:** 2026-05-17
**Severity:** feature-readiness
**Category:** backend, firebase, emulator, diagnostics, privacy, testing
**File(s):** `README.md`, `Documentation/BackendQAChecklist.md`, `Documentation/FirebaseEmulatorSetup.md`, `Documentation/FirebaseCostBudget.md`, `Scripts/start_firebase_emulators.sh`, `VirtualTrainer/Services/FirebaseBootstrap.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreCostTracker.swift`, `VirtualTrainer/Models/WorkoutHistoryStore.swift`, `VirtualTrainer/UI/ProfileView.swift`, `VirtualTrainerTests/BackendIntegrationTests.swift`, `VirtualTrainerTests/BackendDataVolumeTests.swift`, `VirtualTrainerTests/Phase17BackendHardeningTests.swift`, `VirtualTrainerTests/FirebaseBootstrapTests.swift`, `VirtualTrainerTests/SyncOrchestratorTests.swift`, `VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift`

**Error:**
Phase 17 needed the Firebase backend path stress-tested for internal beta without weakening local mode, without touching the live camera analysis stack, and without storing or logging raw sensor/face data or secret-like values. The app also lacked an emulator launch path, a beta QA checklist, a visible session cost counter, a DEBUG sync diagnostics surface, and tests for volume/backpressure/privacy risks.

**Root Cause:**
Previous Firebase phases established Auth/Firestore repositories and local-first sync contracts, but they intentionally left internal beta operations mostly manual. Emulator setup was documentation-only, Firestore adapter calls did not expose a cheap read/write counter, Profile's backend debug section did not show journal/listener/conflict diagnostics in one place, and store-level workout saves could still attempt a remote write during an active live session even though orchestrator-level heavy sync was already deferred.

**Fix Applied:**
Added `--firebase-emulator` bootstrap support for Auth `localhost:9099` and Firestore `localhost:8080` after Firebase app configuration succeeds. Added guarded emulator startup docs and script. Added DEBUG `FirestoreCostTracker` adapter counters and a Profile backend "Sync Diagnostics" section showing backend mode, redacted account ID, last sync, pending uploads, conflicts, listener state, sanitized last error, bootstrap state, write journal count, latest journal entry kinds/ages, and the Cost Snapshot toggle. Added a live-session guard to leave workout remote saves/deletes queued until `WorkoutSessionContext.isLive` ends. Added Phase 17 QA, emulator, and cost-budget docs plus unit/integration/data-volume/privacy tests.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Required simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required full test suite passed after tightening one documentation assertion:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 423
- Failed: 0
- Skipped: 4 (`BackendIntegrationTests`, emulator opt-in)

`git diff --check` passed. `gitleaks` is not installed locally, so a redacted fallback scan over changed and untracked files checked common Firebase, OpenAI, GitHub, Slack, password/token/API-key, authorization, private-key, service-account, bearer-token, and App Check debug-token-style patterns and found no candidate secrets. Static diff search confirmed no changes to `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, `FormFeedbackEngine`, `HandGestureDetector`, `ExertionAnalyzer`, `WorkoutReadyCoordinator`, `FaceLandmarkerService`, or `FramePositionAnalyzer`.

**Prevention Rule:**
Internal beta backend work must ship with emulator instructions, local-mode/no-plist checks, opt-in integration tests, data-volume checks, privacy payload coverage, and a documented manual QA path before expanding tester count. Heavy sync and large workout writes must remain deferred while live camera training is active; diagnostics may log aggregate counters and sanitized states only, never payloads, account IDs, plist contents, App Check debug tokens, raw frames, raw pose streams, face data, or secret-like values.

**Pattern Tags:** #phase17 #firebase #emulator #backend-qa #cost-budget #sync-diagnostics #backpressure #privacy #local-mode

---

### [DL-066] Phase 17 Post-Compaction Audit Corrections
**Date:** 2026-05-17
**Severity:** audit-correction
**Category:** backend, firebase, emulator, diagnostics, documentation, testing
**File(s):** `README.md`, `Documentation/BackendQAChecklist.md`, `Documentation/FirebaseEmulatorSetup.md`, `Documentation/FirebaseCostBudget.md`, `Scripts/run_backend_integration_tests.sh`, `VirtualTrainer/Services/FirebaseBootstrap.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreCostTracker.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift`, `VirtualTrainerTests/BackendIntegrationTests.swift`, `VirtualTrainerTests/FirebaseBootstrapTests.swift`, `VirtualTrainerTests/Phase17BackendHardeningTests.swift`

**Error:**
The Phase 17 implementation was broad and partially completed across a context compaction and lost stream, which left several audit misses after the first passing build/test run. The README still contained an older line saying workout history remained local even though compact workout sync had been added. Emulator integration tests had a guarded test target and startup script, but there was no single runner that actually started the emulators and supplied the required opt-in environment before invoking the test target. The forbidden-write emulator test accepted any error instead of asserting Firestore permission-denied. The Cost Snapshot tracker was documented as DEBUG-only, but its in-memory counters still mutated in release builds even though only logging/UI were DEBUG-gated. Transaction cost counting also recorded from inside the transaction closure via detached main-actor tasks, making the count more timing-sensitive than necessary. One hardening test was too brittle and looked for a literal runner path that differed from the script's robust `$SCRIPT_DIR` invocation.

**Root Cause:**
The misses came from treating several Phase 17 bullets as covered once docs, tests, and buildability existed, instead of round-tripping each bullet through the exact operator workflow. Context compaction made the first pass lean on the accumulated summary rather than re-reading every changed artifact for contradictions. "Spin up the emulator before tests via a script invocation guard" was interpreted as "document the startup script and skip tests unless opted in," which was weaker than the requested executable path. The Cost Snapshot feature was reviewed from the UI/logging perspective but not from the compiled release code path. The denied-rules test validated that a failure occurred but did not validate the important downstream distinction between a real rules denial and another emulator/network/configuration failure.

**Fix Applied:**
Updated the README to describe the real before/after: Firebase mode can now sync compact workout history to another simulator, while heatmaps, recaps, FPS-sensitive live analysis, and rep feedback remain local/client-side derived. Added `Scripts/run_backend_integration_tests.sh`, which starts the Auth/Firestore emulators and runs only `VirtualTrainerTests/BackendIntegrationTests` with `SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1` and `SPOTTER_FIREBASE_EMULATOR=1`. Added environment-based emulator opt-in to `FirebaseEmulatorBootstrap` while preserving `--firebase-emulator`. Strengthened the forbidden-write test to assert `FirestoreErrorDomain` and `FirestoreErrorCode.permissionDenied`. DEBUG-gated `FirestoreCostTracker` mutation as well as logging, and moved transaction cost recording to successful transaction completion using adapter read/write counts. Updated the emulator, QA, and cost docs plus hardening tests to reflect the runner and DEBUG-only counter behavior.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Required simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Focused Phase 17 hardening tests passed after fixing the runner-path assertion:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData -only-testing:VirtualTrainerTests/Phase17BackendHardeningTests`

Required full test suite passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 424
- Failed: 0
- Skipped: 4 (`BackendIntegrationTests`, emulator opt-in)

No-plist local fallback build passed after temporarily moving the ignored local Firebase client plist out of the workspace and restoring it with a shell trap:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoPlistDerivedData`

The build printed the expected local-only warning and did not require `GoogleService-Info.plist`. `git diff --check` passed. `gitleaks` is not installed locally, so a redacted filename-only fallback scan over changed and untracked files checked common Firebase, OpenAI, GitHub, Slack, password/token/API-key, authorization, private-key, service-account, bearer-token, and App Check debug-token-style patterns and found no candidate secrets. Static diff search confirmed no changes to `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, `FormFeedbackEngine`, `HandGestureDetector`, `ExertionAnalyzer`, `WorkoutReadyCoordinator`, `FaceLandmarkerService`, or `FramePositionAnalyzer`.

**Prevention Rule:**
After any context compaction or interrupted long-running phase, audit against the original prompt with an explicit requirement matrix before declaring the phase complete. For testability requirements, prefer a single executable command or script over prose-only instructions. For DEBUG-only diagnostics, gate state mutation, not only UI and logging. For negative backend tests, assert the specific failure class that protects user data. Documentation changes must be re-read for old/new contradictions before final verification.

**Pattern Tags:** #phase17 #post-compaction-audit #firebase #emulator #cost-budget #debug-only #rules-denial #documentation #privacy #local-mode

### [DL-067] Phase 17.5 Backend Hardening
**Date:** 2026-05-17
**Severity:** hardening
**Category:** backend, firebase, firestore-rules, privacy, sync, testing
**File(s):** `Documentation/firestore.rules`, `Documentation/FirestoreRulesEmulatorTests.md`, `Documentation/BackendQAChecklist.md`, `Documentation/FirebaseEmulatorSetup.md`, `README.md`, `.gitignore`, `Scripts/test-firestore-rules.sh`, `Scripts/firestore-rules-tests/index.test.js`, `Scripts/pre-commit-firestore-rules.sample.sh`, `VirtualTrainer/Repositories/Firebase/FirestoreWorkoutRepository.swift`, `VirtualTrainer/Repositories/Firebase/FirestoreDTOs.swift`, `VirtualTrainer/Repositories/Firebase/FirestorePrivacyValidator.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`, `VirtualTrainerTests/FirestoreTranslationLayerTests.swift`

**Error:**
Phase 17 still had four backend gaps before the design revamp. The root `users/{uid}` document was owner-writable without a reserved schema, so future app code could accidentally put profile or product fields there. Workout deletion used `updateData`, which fails when a local workout is created and deleted before its first remote upload, preventing the intended remote tombstone from being created. The privacy validator allowed arbitrary `Data` values up to 4 KB even though there are no approved binary Firestore fields today. Finally, the published Firestore rules had documentation and XCTest coverage, but no standalone emulator-backed rules suite that could be run locally before publishing rules.

**Root Cause:**
The backend path had been hardened around compact derived documents and local-first sync, but a few implicit assumptions remained untested: root user docs were treated like another owner-scoped document, delete tombstones assumed a remote document already existed, the binary payload guard was size-based instead of allowlist-based, and rules behavior was validated indirectly rather than through the Firestore emulator. These gaps were small individually, but together they left room for privacy drift and sync edge cases as Firebase usage expands.

**Fix Applied:**
Restricted `users/{uid}` root writes in `Documentation/firestore.rules` to owner-readable, non-deletable metadata with only `accountId`, `schemaVersion`, `createdAt`, `updatedAt`, and optional `lastSeenAt`. Changed workout deletion to `setData(..., merge: true)` with a minimal tombstone payload containing `accountId`, `schemaVersion`, normalized `workoutId`, `deletedAt`, deterministic `operationId`, and pending `syncMetadata`; repeated deletes with the same operation ID now short-circuit. Added backwards-compatible decoding defaults so minimal remote tombstones remain readable without weakening full workout DTO writes. Changed `FirestorePrivacyValidator` to reject every `Data` value by default unless a future privacy-reviewed call explicitly allowlists the field. Added Node/@firebase emulator rules tests plus a local runner and pre-commit stub, and updated README/QA/emulator docs to make the tightened rules workflow explicit.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Firestore rules emulator tests passed after using a temporary JDK because no system Java runtime was installed:

`Scripts/test-firestore-rules.sh`

- Passed: 9
- Failed: 0

Required simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required full test suite passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 428
- Failed: 0
- Skipped: 4 (`BackendIntegrationTests`, emulator opt-in)

No-plist local fallback build passed after temporarily moving the ignored local Firebase client plist out of the workspace and restoring it with a shell trap:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoPlistDerivedData`

The build printed the expected local-only warning and did not require `GoogleService-Info.plist`. `Scripts/test-firestore-rules.sh` also left no committed emulator artifacts; the generated `firestore-debug.log` is ignored. `git diff --check` passed before this entry and is rerun after appending. `gitleaks` is not installed locally, so a filename-only fallback scan over changed and untracked text files checked the repo's Firebase, service-account, private-key, OpenAI, GitHub, Slack, Stripe, JWT, bearer/authorization, URL credential, Supabase, and generic secret assignment patterns and found no candidate secrets. Static diff search confirmed no changes to `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, `FormFeedbackEngine`, `HandGestureDetector`, `ExertionAnalyzer`, `WorkoutReadyCoordinator`, `FaceLandmarkerService`, or `FramePositionAnalyzer`.

**Prevention Rule:**
Treat Firestore schema and local sync behavior as a paired contract: every privacy or deletion rule change needs repository tests and emulator rules tests before publication. Root user docs stay reserved metadata unless a migration explicitly changes the schema. Binary Firestore fields require an explicit allowlist and privacy review before any upload path can accept them. Delete paths must be idempotent for existing, missing, and retried documents.

**Pattern Tags:** #phase17-5 #firebase #firestore-rules #sync #tombstones #privacy #rules-emulator #local-mode #tests

---

### [DL-068] Phase 17.5 Post-Compaction Audit Correction
**Date:** 2026-05-17
**Severity:** audit-correction
**Category:** backend, firebase, firestore, tombstones, codable, privacy, testing
**File(s):** `DEBUG_LOG.md`, `VirtualTrainer/Repositories/Firebase/FirestoreDTOs.swift`, `VirtualTrainerTests/FirestoreTranslationLayerTests.swift`

**Error:**
The post-compaction Phase 17.5 audit found one downstream-risk miss in the tombstone decoding patch. The first implementation made `FirestoreWorkoutDocument` tolerant of missing full-workout fields so newly-created minimal tombstone documents could be read back from Firestore. That tolerance was not scoped tightly enough: an active remote workout document with no `deletedAt` and missing required fields could also decode with defaults such as `"Deleted workout"`, zero duration, zero reps, and empty analytics instead of failing as it did before. That would not corrupt local camera analysis, but it could hide malformed active Firestore data and make a bad remote document look like a valid empty workout.

**Root Cause:**
The miss came from optimizing the first pass around the positive tombstone requirement: delete-before-upload must create a minimal remote tombstone and `loadRecentWorkoutTombstones` must read it. Context compaction compressed that requirement into "minimal tombstones must decode," and the initial tests covered the positive tombstone path plus fully-populated DTO payloads, but not the negative path where an active, non-deleted workout is malformed. Because the change lived in a Codable initializer rather than a visibly separate repository branch, it looked backwards-compatible while actually widening active-read behavior. The audit also caught that the no-plist build helper can temporarily disturb tracked `*.codex-tmp` Firebase config filenames if local ignored plist files are present, so filename restoration must be verified without printing plist contents.

**Fix Applied:**
Restricted missing-field defaults in `FirestoreWorkoutDocument.init(from:)` to documents that actually contain `deletedAt`. Active documents now retain the previous strict decoding contract for required fields, while deleted tombstones can still decode from the minimal payload written by `setData(..., merge: true)`. Added `testWorkoutDocumentDecoderDefaultsOnlyDeletedTombstones` to prove both sides of the contract: a minimal deleted tombstone decodes, and a minimal active workout still throws. Restored the tracked Firebase `*.codex-tmp` filenames after the no-plist verification by comparing hashes only and without printing any plist values.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Focused Firestore repository and DTO/privacy tests passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerAuditDerivedData -only-testing:VirtualTrainerTests/FirestoreTranslationLayerTests -only-testing:VirtualTrainerTests/FirestoreRepositoryTests`

- Passed: 39
- Failed: 0

Firestore rules emulator tests passed with the temporary JDK used for DL-067:

`Scripts/test-firestore-rules.sh`

- Passed: 9
- Failed: 0

Required full test suite passed after the audit correction:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 431
- Failed: 0
- Skipped: 4 (`BackendIntegrationTests`, emulator opt-in)

No-plist local fallback build passed again after temporarily moving local Firebase client plists out of the workspace and restoring them with a shell trap:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoPlistAuditDerivedData`

The build printed the expected local-only warning and did not require `GoogleService-Info.plist`. `git diff --check` passed after this entry was appended. Static diff search confirmed no changes to `CameraManager`, `PoseEstimator`, `UniversalRepCounter`, `FormFeedbackEngine`, `HandGestureDetector`, `ExertionAnalyzer`, `WorkoutReadyCoordinator`, `FaceLandmarkerService`, or `FramePositionAnalyzer`. A subsequent commit-range secret scan found a separate tracked Firebase plist filename issue; see DL-069.

**Prevention Rule:**
When adding tolerant Codable decoding for migrations, tombstones, or offline sync recovery, add paired negative tests proving the normal non-migration path remains strict. After any context compaction, audit the complete prompt against the complete diff, including untracked files and generated scripts, before declaring the phase complete. For local-no-plist checks, verify file restoration by filename and hash only; never print plist contents or secret-like values.

**Pattern Tags:** #phase17-5 #post-compaction-audit #firestore #tombstones #codable #privacy #tests #local-mode

---

### [DL-069] Phase 17.5 Secret Pre-Flight Audit Correction
**Date:** 2026-05-17
**Severity:** critical
**Category:** backend, firebase, secrets, repository-hygiene, local-mode
**File(s):** `.gitignore`, `DEBUG_LOG.md`, `GoogleService-Info.example.plist`, `GoogleService-Info.example.plist.codex-tmp`, `GoogleService-Info.plist.codex-tmp`

**Error:**
The post-compaction audit found that the P17.5 commit included tracked Firebase plist temp filenames: `GoogleService-Info.example.plist.codex-tmp` and `GoogleService-Info.plist.codex-tmp`. Pattern-only checks confirmed Firebase config keys were present in those tracked files without printing their values. That violates the phase privacy and secret-handling requirement because the app must build without Firebase config, the real local `GoogleService-Info.plist` must remain ignored, and no third-party secret-like value should be committed, logged, or added to fixtures.

**Root Cause:**
The miss came from the no-plist verification workflow colliding with local ignored plist files. The helper temporarily moved `GoogleService-Info*.plist` to `*.codex-tmp` so Xcode could prove local-only mode, but the temp suffix was not ignored and not excluded from the commit review. Context compaction also made the final status check focus on source/docs/scripts, while the secret scan was run over the visible changed text paths rather than the full commit range. Because the filenames looked like build-check residue, they were not treated as release-blocking tracked artifacts soon enough.

**Fix Applied:**
Removed the tracked `*.codex-tmp` Firebase plist files from the working tree, restored `GoogleService-Info.example.plist` as a sanitized placeholder file with non-secret example values, and added `GoogleService-Info*.plist.*` to `.gitignore` so temporary plist backup filenames stay ignored. Left the real local `GoogleService-Info.plist` ignored and unprinted. The current diff now makes the intended repository contract explicit: example config may be committed, local Firebase client config may not, and no temporary no-plist verification filename should be tracked.

**Verification:**
`gitleaks` is not installed locally, so a fallback scan was run over the current working-tree diff, the latest P17.5 commit file list, and untracked text files using Firebase API-key, service-account, private-key, OpenAI, GitHub, Slack, Stripe, JWT, bearer/authorization, URL credential, Supabase, App Check debug-token, and generic secret-assignment patterns. The scan reported only the historical tracked `*.codex-tmp` plist paths that this correction removes from the current diff; the sanitized example plist contains placeholders only. `git diff --check` passed after the plist cleanup and this entry. Static diff search again confirmed no changes to the protected live camera pipeline files.

**Prevention Rule:**
Secret pre-flight must scan the commit range as well as the unstaged working tree, and it must include tracked files with temporary suffixes. No-plist build helpers must move Firebase config into an ignored temporary directory or use a suffix covered by `.gitignore`, then verify restoration by filename and hash only. Any Firebase plist-like file that is not the sanitized example must be treated as a release blocker until removed from Git history and the underlying keys are rotated if the commit has been pushed.

**Pattern Tags:** #phase17-5 #secrets #firebase-plist #post-compaction-audit #local-mode #repository-hygiene

---

### [DL-070] Phase 17.5 Acceptance Matrix and Swift Isolation Audit Correction
**Date:** 2026-05-17
**Severity:** audit-correction
**Category:** backend, firebase, firestore, tombstones, codable, testing, toolchain
**File(s):** `DEBUG_LOG.md`, `VirtualTrainer/Repositories/Firebase/FirestoreDTOs.swift`, `VirtualTrainerTests/FirestoreRepositoryTests.swift`

**Error:**
The final requirement-by-requirement audit found two smaller misses after DL-068 and DL-069. First, the code correctly used `setData(..., merge: true)` for all workout deletes, but the XCTest matrix did not explicitly prove the normal delete-after-upload path merged `deletedAt`; it only covered delete-before-upload, retry idempotency, and tombstone visibility. Second, the no-plist build surfaced a Swift concurrency warning on the custom `FirestoreWorkoutDocument.init(from:)`: the initializer was treated as main actor-isolated and therefore could not cleanly satisfy the nonisolated `Decodable` requirement in future Swift language modes.

**Root Cause:**
The delete tests were written around the new failure mode, which was missing remote documents after offline-create-then-delete, so the already-working uploaded-document path was treated as indirectly covered by repository behavior. The concurrency warning was missed because the first full test run passed, and the audit initially focused on failures and requirement coverage rather than compiler warnings emitted only during a clean no-plist rebuild of the affected file. Context compaction made the checklist broader but easier to satisfy at a coarse level, so the final pass needed a line-by-line acceptance matrix rather than "all relevant tests are green."

**Fix Applied:**
Added `testWorkoutRepositoryDeleteAfterUploadMergesDeletedAt`, which saves a normal uploaded workout, deletes it, asserts the delete write is `setData(merge: true)`, confirms `deletedAt` and the deterministic delete `operationId`, and confirms existing fields such as `title` remain after the merge. Marked `FirestoreWorkoutDocument.init(from:)` as `nonisolated` so the custom decoder preserves the nonisolated Codable contract of the DTO.

**Verification:**
Focused Firestore repository and DTO/privacy tests passed after the new test and nonisolated initializer fix:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerAuditDerivedData -only-testing:VirtualTrainerTests/FirestoreTranslationLayerTests -only-testing:VirtualTrainerTests/FirestoreRepositoryTests`

- Passed: 39
- Failed: 0
- Skipped: 0

Required full XCTest passed after the source fix:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 431
- Failed: 0
- Skipped: 4 (`BackendIntegrationTests`, emulator opt-in)

No-plist local fallback build passed again after the fix using a temp directory that moved only real local Firebase config filenames:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerNoPlistAuditDerivedData2`

The build printed the expected local-only warning, succeeded, restored the ignored local plist, and no longer emitted the `FirestoreWorkoutDocument` Decodable isolation warning. Firestore rules emulator tests remained green at 9 passed, 0 failed.

**Prevention Rule:**
Every acceptance bullet needs a direct positive or negative test, even when the behavior appears to be covered by a neighboring edge-case test. Clean builds must be scanned for warnings after adding custom Codable implementations on actor-isolated or nonisolated DTOs. A passing XCTest suite is not sufficient if the compiler is already warning about a future language-mode error.

**Pattern Tags:** #phase17-5 #acceptance-matrix #firestore #tombstones #swift-concurrency #codable #tests #local-mode

---

### [DL-071] Design System V2 D0 Inventory
**Date:** 2026-05-17
**Severity:** documentation
**Category:** design-system, inventory, v2, accessibility, swiftui-planning
**File(s):** `DEBUG_LOG.md`, `Documentation/DesignSystemV2Inventory.md`, `Documentation/PhosphorToSFSymbolMap.md`

**Error:**
No runtime defect was fixed in this phase. The V2 design exports existed as 29 HTML files and 29 screenshots, but the repo did not yet have a single implementation inventory that mapped each visual reference to current SwiftUI screens, code-supported behavior, design-only deferrals, code-only surfaces that must remain available, tokens, image decisions, and icon replacements. That gap would make later V2 phases risky because design-only items such as login, AI swaps, BPM trophies, KG volume, calories, burpees, and active Running Analysis could accidentally become fake product behavior.

**Root Cause:**
The design files were exported from a web/Tailwind/Iconify prototype, while the iOS app uses SwiftUI, SF Symbols, system fonts, local-first stores, shared live camera analysis, and optional Firebase mode. Without a D0 inventory, later implementation prompts would need to rediscover the same deltas screen by screen and could miss the product truth encoded in README, the backend docs, DL-045 toolchain notes, `Theme.swift`, `LiquidGlass.swift`, feature flags, and the current UI files.

**Fix Applied:**
Added `Documentation/DesignSystemV2Inventory.md` with an exhaustive 29-screen inventory grouped by D2-D6 feature area, exact HTML-to-screenshot pairs, current SwiftUI equivalents, stable hero strings, key component notes, design-only deferrals, code-only features to preserve and style, design token extraction, per-theme accent confirmation against `SpotterThemeOption`, and imagery decisions. Added `Documentation/PhosphorToSFSymbolMap.md` with all 99 unique `iconify-icon` Phosphor references found across the HTML exports, including usage counts, HTML refs, SF Symbol replacements, and weak/custom follow-up notes.

No UI code, backend repository behavior, Firestore rules, sync behavior, or live camera pipeline files were changed. Existing dirty worktree changes outside these D0 docs were left untouched.

**Verification:**
Toolchain paths resolved under `XcodeDefault.xctoolchain`:

`xcrun --find clang`

`xcrun --find swiftc`

Both returned paths under:

`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`

Design artifact extraction confirmed:

- 29 HTML files in `NEW_DESIGN/export-html/`
- 29 matching PNG screenshots in `NEW_DESIGN/screenshots/`
- 1 shared `:root` token block variant across all 29 HTML files
- 99 unique Phosphor icon references mapped to SF Symbols or a documented closest replacement plan

Required simulator build passed:

`xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

Required full test suite passed:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/VirtualTrainerDerivedData`

- Passed: 431
- Failed: 0
- Skipped: 4 (`BackendIntegrationTests`, emulator opt-in)

The xcresult reported 435 total tests, 4 skipped, and succeeded. One metadata warning was present from AppIntents metadata extraction being skipped because no AppIntents dependency is present. The build also copied the local ignored Firebase client config for this developer machine without printing plist contents.

Static status review confirmed this D0 work touched documentation only: `Documentation/DesignSystemV2Inventory.md`, `Documentation/PhosphorToSFSymbolMap.md`, and this `DEBUG_LOG.md` append.

**Prevention Rule:**
Before implementing any V2 screen, start from the D0 inventory rather than the HTML alone. If design shows unsupported product behavior, mark it coming soon or omit it; do not build fake behavior. If code has a real surface the design omits, keep it and style it with V2 language. Treat remote images, external fonts, Tailwind, Iconify, and Phosphor as reference-only until a later asset/font licensing phase explicitly adds app-owned resources.

**Pattern Tags:** #design-system-v2 #d0 #inventory #tailwind-to-swiftui #sf-symbols #feature-deltas #documentation-only #tests
