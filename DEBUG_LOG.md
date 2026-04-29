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
