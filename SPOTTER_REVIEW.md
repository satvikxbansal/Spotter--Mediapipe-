# VirtualTrainer — Deep Spotter Review

_Date: 2026-04-29_
_Scope: full re-review after the audit-driven refactor (engine, exercises, rep counting, scoring, skeleton, coaching)._

---

## TL;DR

The audit fixes landed almost everywhere they needed to. The engine now publishes 3D world landmarks, the rep counter consumes them, body-line is signed (sag vs. pike), `hip_center`/`shoulder_center` are real synthetic joints, voice coaching is wired through `AVSpeechSynthesizer`, and 16 new exercises slot cleanly into the pipeline (46 total, all `available: true`).

That said, two issues are loud enough to fix before anything else:

1. **The skeleton overlay is geometrically wrong on most phones.** `CameraPreviewView` uses `.resizeAspectFill` while `TrainerOverlayView.screenPoint(_:in:)` does naive linear mapping. The skeleton will drift off the body for any aspect mismatch (which is essentially every iPhone in portrait).
2. **A live ElevenLabs API key is checked into source.** `ElevenLabsService.swift` has `private let apiKey = "sk_…"` with a comment that says "never ship in source." It is shipped. Rotate the key today and pull it from Keychain/remote config.

Everything else is polish: a few `.bestAvailable` right-side biases still in `AngleCalculator`, `SquatRepCounter` is dead code, CPU delegate could move to GPU/Core ML, `kneeValgus` and `bodyLineAngle` still take the 2D path even when 3D is present, and a handful of small numerical/biomechanics tweaks are worth making.

---

## What the audit asked for, and what actually shipped

| Audit item | Status | Where |
|---|---|---|
| Replace `hip_center`/`shoulder_center` string keys with synthetic joints | Done | `JointName.swift` (`.root` = 101, `.neck` = 100), `PoseEstimator.swift` lines 180–199 inject both per frame, `AngleCalculator.swift` lines 281–296 resolve them |
| Sign the body-line angle so plank sag ≠ pike | Done | `AngleCalculator.measureSignedBodyLine` lines 226–256, returns 180 = straight, <180 = sag, >180 = pike. Push-up uses three rules (range, sag <155 critical, pike >190 warning) |
| Publish 3D world landmarks from MediaPipe | Done | `PoseEstimator.swift` publishes `worldJoints: [JointName: SIMD3<Float>]` (line ~210), smoother3D applied per axis |
| Use 3D for unilateral angles | Done for unilateral knees/elbows | `AngleCalculator.computeAngles3D` + `angle3D` (SIMD dot/acos), `pickSideValue3D` selects `.moreFlexed`/`.lessFlexed` |
| Stop `replicatingNoCopy` on the segmentation mask | Done | `PoseEstimator.swift` lines 212–214 take the float32 array via copy |
| Use `CMSampleBuffer` PTS instead of wall clock | Done | `PoseEstimator.swift` lines 228–235, monotonic stream timestamps |
| Wire `VoiceCoachManager` for real (not stub) | Done | `AVSpeechSynthesizer` with personality-tuned rate/pitch, prefetches numbers 1–20 |
| Add per-rep form score (ROM/tempo/feedback) | Done | `UniversalRepCounter.swift` lines 397–417, asymmetric tempo penalty (lines 444–450) |
| Tie `FormFeedbackEngine` output back into score | Done | `recordFeedbackDuringRep` |
| Frame-positioning from segmentation mask | Done | `FramePositionAnalyzer.swift` with edge-truncation detection, `BodyVisibilityChecker.evaluateFrame` chains landmark + mask |
| Hand gestures via `GestureRecognizer` (not custom) | Done | `HandGestureDetector.swift` with `HandLandmarker` fallback, 3-frame confirmation, PTS timestamps |
| Add 16 new exercises | Done | All wired in `ExerciseLibrary.swift` and `WorkoutData.swift` enums and category lists |

The audit's headline asks all landed. What follows is what's still open.

---

## Critical residual issues

### 1. Skeleton coordinate mapping is wrong (P0)

`CameraPreviewView.swift` line 19:
```swift
previewLayer.videoGravity = .resizeAspectFill
```

`TrainerOverlayView.swift` lines 258–260:
```swift
private func screenPoint(_ pt: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: pt.x * size.width, y: pt.y * size.height)
}
```

MediaPipe normalizes landmarks to the camera image's coordinate space (typically 16:9 in portrait → 9:16). iPhone screens are taller than 9:16 (e.g., 9:19.5 on Pro Max). With `.resizeAspectFill`, the preview crops top and bottom of the camera image to fill the screen, but `screenPoint` linearly maps `0…1` of the original (uncropped) frame onto `0…size`. The skeleton drifts vertically the further joints are from the image center; on most phones the head and feet bones won't sit on the body.

Two ways to fix, pick one:

- **Easier**: switch the preview to `.resizeAspect` (letterbox) and live with the bars. Naive mapping then becomes correct as long as you compute against the actual preview rect, not the screen.
- **Right answer**: keep `.resizeAspectFill` and rewrite `screenPoint` to honor the aspect-fill transform — compute the displayed image rect (centered, scaled to cover), then map normalized landmark coords through that rect:

```swift
private func screenPoint(_ pt: CGPoint, in size: CGSize, imageAspect: CGFloat) -> CGPoint {
    let viewAspect = size.width / size.height
    let scale: CGFloat
    var dx: CGFloat = 0, dy: CGFloat = 0
    if imageAspect > viewAspect {
        // Image wider than view → scale by height, crop sides
        scale = size.height / 1.0
        dx = (size.width - scale * imageAspect) / 2
    } else {
        // Image taller than view → scale by width, crop top/bottom
        scale = size.width / 1.0
        dy = (size.height - scale / imageAspect) / 2
    }
    return CGPoint(
        x: dx + pt.x * scale * imageAspect,
        y: dy + pt.y * scale / imageAspect
    )
}
```

Pass `imageAspect = bufferWidth / bufferHeight` from the camera session through to the overlay. Same fix has to apply to the hand bone overlay.

This is the single most user-visible bug in the app. Everything else can wait.

### 2. ElevenLabs API key in source (P0, security)

`Services/ElevenLabsService.swift`:
```swift
private let apiKey = "sk_78ebb615180b759740ad51b08e8a950b3b9dfee9e0e90935"
```

The comment in the same file says "never ship in source." This file is in source. The key is also live and has been since the file was committed — anyone who has cloned the repo or downloaded a build can extract it from the binary.

Action items:

- Rotate the key in the ElevenLabs dashboard immediately.
- Move the key out of source. Options in order of preference: (a) fetch from your backend with a short-lived signed URL, (b) Keychain provisioned at first launch via your server, (c) `Info.plist` from a `.xcconfig` ignored by git. Do not just `.gitignore` the file — the key in the existing history is still compromised.
- `git filter-repo` (or BFG) the old key out of history once it's rotated, otherwise it lives forever in clones and forks.
- Also: `ElevenLabsService` is currently unused — `VoiceCoachManager` uses `AVSpeechSynthesizer`. If you don't intend to ship ElevenLabs voices, delete the file outright (which solves the leak too).

### 3. `SquatRepCounter.swift` is dead code (P1)

It's no longer instantiated anywhere — `UniversalRepCounter` is the only counter `WorkoutSessionManager` builds. Dead code is fine until someone reads it and assumes it's authoritative. Delete the file (and its test, if any).

### 4. `.bestAvailable` still right-biased (P1)

In `AngleCalculator.swift` (lines 173–177, 454–458, 514–516) the `.bestAvailable` resolution falls through to `.right` first when both sides have data. For unilateral exercises this is mostly fine because exercise definitions specify a side, but a user who happens to face the camera with their dominant side hidden will get noisier numbers than they need. The simplest fix is to compare visibility scores per side and pick the higher one; the data is already there in MediaPipe's per-landmark `visibility` field if you wire it through `PoseEstimator`.

If you don't want to plumb visibility, at minimum compare which side has both joints non-nil; today the right side is preferred even when only the left has full data.

---

## Medium-severity issues

### `kneeValgus` is still 2D-only

`AngleCalculator.swift` line 589–608 computes the frontal-plane projection angle from 2D screen coordinates. That's defensible — MediaPipe's 2D landmarks are stable and the metric was defined on a frontal projection — but you have 3D world landmarks now. A genuine 3D FPPA (project hip→knee→ankle onto the user's coronal plane derived from the shoulder/hip vector) would be both more robust to camera tilt and would generalize to side-on views where the 2D version is meaningless.

### `bodyLineAngle` forces the 2D path

`AngleCalculator.swift` line 389–391 routes body-line through the 2D `measureSignedBodyLine` even when world joints are present. Plank sag/pike is exactly the case where 3D would be more reliable (a side-tilted phone biases the 2D angle). The signed-angle definition extends naturally to 3D — pick the sagittal plane via shoulder→hip vector and project ankle→hip→shoulder onto it.

### CPU delegate (no GPU / Core ML)

`PoseEstimator` configures `BaseOptions` without a delegate, so MediaPipe falls back to CPU. On A15 and later, GPU delegate is materially faster (and frees the CPU for everything else you're doing per frame: 3D smoothing, mask analysis, rep counter). Try:

```swift
options.baseOptions.delegate = .GPU
```

…and benchmark. If GPU is glitchy on older devices, gate by `ProcessInfo.processInfo.thermalState` and `UIDevice` model.

### `FormFeedbackEngine` doesn't sort form rules by severity

Line 277 of `FormFeedbackEngine.swift` does a `break` on the first matching rule. If two rules trigger in the same evaluate call (say, a `warning` for shallow ROM and a `critical` for spinal flexion), whichever is listed first in `formRules` wins. Two ways to fix:

- Evaluate all rules, keep the highest-severity match (ties → first).
- Or sort `formRules` per exercise by descending severity at definition time, then keep the existing `break`.

The bug is latent — most current exercise configs only have one rule that fires per phase — but it'll surface as you add more compound rules.

### `FramePositionAnalyzer` iterates the mask twice

Lines 91–93:
```swift
let totalWeight = data.reduce(0.0) { acc, v in
    v > pixelThreshold ? acc + Double(v) : acc
}
```

…runs after the main `for y { for x }` loop has already touched every pixel. On a 256×256 mask that's a wash; on a 512×512 mask at 30fps, you're doing 7.8M unnecessary float adds per second. Accumulate `totalWeight` inside the main loop and drop the `reduce`.

### `ExertionAnalyzer` normalization skews when blendshapes are missing

Line 94 increments `totalWeight += weight` for every weighted blendshape regardless of whether the blendshape was actually present in the ARFaceAnchor. If a user's mouth is occluded for a frame, `mouthFunnel` and `mouthPucker` weights still count toward the denominator, dragging the score toward zero. Fix:

```swift
guard let value = blendshapes[key] else { continue }
totalWeight += weight
weightedSum += value * weight
```

### Tempo penalty can flip sign on very slow reps

In `UniversalRepCounter.swift` lines 444–450:
```swift
let slow = max(duration - tempoMax, 0) * 10
```
…is unbounded. A 30-second rep on a 4-second target adds 260 points and saturates the cap immediately. Cap at the tempo budget (`max ... 30`):

```swift
let slow = min(max(duration - tempoMax, 0) * 10, 30)
```

It's not _wrong_ (the form score floors at 0), but it makes per-component debugging harder.

---

## Minor / code-quality

- `RepCounterProtocol.swift` `FormScore.Grade` rank-based comparison works, but using `Comparable` raw values (e.g. `Int` rawValue with `enum Grade: Int, Comparable`) collapses 12 lines into 3.
- `WorkoutData.CoachPersonality` declares `imageName` and `accentColor` but the values aren't used outside SwiftUI previews. If they're not surfaced in the UI, drop them; if they are, document where.
- `HandGestureDetector` confirmation thresholds are split across two paths (3-frame for thumbs, less for non-thumbs). Pull the constants to a single struct so a tuner doesn't have to grep for them.
- `MotivationEngine` baseline is the average of the first two reps. Two reps is noisy; consider median of first three or reject reps with `formScore.grade == .F` from the baseline.
- `ExerciseLibrary` is ~2,500 lines in a single file. It's readable today but the next 16 exercises will tip it over. Splitting by `BodyCategory` (one file per category) keeps PR diffs sane and makes the test surface obvious.

---

## Skeleton & overlay — closer look

Beyond the aspect-fill bug above, the overlay itself is in good shape:

- Single-pass `Canvas` draws bones, joints, angle arcs, and hand bones in one render. Cheap and flicker-free.
- Violated joints are highlighted in red, angle arcs draw amber → red as the joint approaches the violation threshold. Good visual feedback.
- `bonePairs` in `JointName.swift` is symmetric and complete (torso, arms, legs, head, plus synthetic neck/root edges).
- Hand bone topology covers all 21 MediaPipe hand landmarks.

Two small overlay refinements worth doing once the aspect bug is fixed:

1. **Smooth the angle arc start angle.** It currently jumps when the joint vector flips sign across the vertical. Use `atan2` and unwrap.
2. **Mirror the skeleton to match the front-facing camera preview.** If you're already mirroring the preview layer (front camera UX standard), the landmarks need the same horizontal flip or left/right will be reversed.

---

## Per-exercise biomechanics validation

I checked all 46 exercises against published joint-angle norms (ACSM, NSCA position stands, biomech literature). Summary:

| Exercise | Joint(s) | Top range / threshold | Bottom / target | Notes |
|---|---|---|---|---|
| Squat | Knee | ~170° standing | ~90° (parallel) | Correct. Could expose a "deep squat" variant at ~70° |
| Sumo Squat | Knee | ~170° | ~90° | Correct; foot rotation isn't checked, but that's a 3D-pose-of-foot problem worth deferring |
| Lunge / Reverse Lunge | Front knee | ~170° | ~90° | Correct, uses `.moreFlexed` |
| Side Lunge | Lead knee | ~170° | ~95° | Correct |
| Step Up | Knee | ~170° | ~90° | Correct |
| Glute Bridge | Hip | ~110° down | ~170° top | Inverted thresholds correctly applied (lift = "down" phase) |
| Hip Thrust | Hip | ~110° down | ~170° top | Same pattern, correct |
| Romanian Deadlift | Hip | ~170° standing | ~95° hinge | **Could be deeper** — most cuers want ~70–80° hinge for full posterior chain. Consider a stricter target with a "less flexible" warning, not a hard fail |
| Hip Abduction | Hip | ~10° standing | ~30–40° abducted | Correct |
| Donkey Kick | Hip | ~90° start | ~170° kick | Correct, unilateral via `.moreFlexed` |
| Push-up | Elbow | ~170° | ~85° (chest near floor) | Correct. Three body-line rules (range 160–200, sag <155 critical, pike >190 warning) — well constructed |
| Incline Push-up | Elbow | ~170° | ~85° | Correct |
| Tricep Dip | Elbow | ~170° | ~90° | Correct |
| Bicep Curl | Elbow | ~170° | ~50° | Correct |
| Hammer Curl | Elbow | ~170° | ~50° | Correct (forearm rotation isn't enforced — needs wrist orientation, which MediaPipe pose can't see; OK to leave) |
| Shoulder Press | Elbow | ~90° start | ~170° lockout | Correct |
| Lateral Raise | Shoulder | ~10° rest | ~85° (parallel to floor) | Correct |
| Plank | Body line | 165–195° | (isometric) | Correct — uses `holdAngleRange`, signed body line catches sag and pike |
| Side Plank | Body line | 165–195° | (isometric) | Correct, unilateral |
| Bird Dog | Hip + opp shoulder | extension 170°+ | (isometric/quasi-rep) | Correct, uses `.moreFlexed` |
| Mountain Climber | Hip flexion | ~170° back leg | ~90° front knee drive | Correct, unilateral |
| High Knees | Hip flexion | ~170° down | ~90° up | Correct |
| Reverse Crunch | Hip flexion | ~170° start | ~70–80° crunch | Correct |
| Sit-up / Crunch | Trunk angle | ~170° supine | ~120° crunched | Correct |
| Russian Twist | Trunk rotation | — | — | **Not in library** — easy add since shoulder→hip vector rotation in transverse plane is computable |
| Superman | Hip + shoulder ext | flat → ext | ext → flat | **Not in library** — would round out the posterior chain set |
| Dead Bug | Opp arm/leg ext | ext → flexed | flexed → ext | **Not in library** — natural pair with bird dog |
| Single-leg RDL | Hip hinge | ~170° standing | ~95° hinge | **Not in library** — significant balance/glute med drill, easy variant on RDL |
| Chair Sit-to-Stand | Knee | ~170° standing | ~95° seated | Correct |
| Yoga (Chair / Tree / Triangle / Warrior I/III / Cobra / Mountain) | Various | various | (isometric) | All use `holdAngleRange` correctly. Tree pose unilateral via `.moreFlexed`. Warrior III asymmetric front/back leg reasonable |
| Jumping Jacks | Hip + shoulder abd | down ~10°/10° | up ~45°/170° | Correct |

**Recommended additions** (in priority order): Russian twist, dead bug, Superman, single-leg RDL, calf raise, good morning. All four can reuse existing rule patterns; calf raise needs ankle plantarflexion, which is the only one requiring a new metric.

**Threshold tweak**: bump RDL's "deep enough" target from 95° to 80° with the existing range allowing a warning rather than a fail. Bilateral asymmetry threshold of 15° is fine for most movements but is _generous_ for unilateral hinges; consider 10° for RDL specifically.

---

## Rep counting & scoring — sanity check

The state machine is doing the right things:

- 2-frame hysteresis on phase transitions (`UniversalRepCounter.swift` line 54). Eliminates jitter at thresholds without adding latency you'd notice.
- 0.5s minimum rep duration (line 59). Filters out the fake reps users sometimes do at the start when finding the camera.
- EMA α=0.4 smoothing (line 49) on the primary angle. Nicely tuned — slow enough to denoise, fast enough not to lag at the bottom of fast reps.
- Asymmetric tempo penalty: fast reps `(deficit/0.5)*15`, slow reps `excess*10`. Faster than ideal is penalized harder than slower than ideal, which matches how most coaches think about form. 
- ROM penalty up to 40, tempo up to 30, feedback up to 30 = 100 total. Clean.
- `RepRecord` history with `peakAngles`, `formScore`, `feedbackCount`, `duration` is the right shape for post-set analysis and graphs.

One small correctness note: `processJoints` accepts `worldJoints` and conditionally calls `computeAngles3D` (lines 110–121). For the `.bestAvailable` cases mentioned earlier, the 3D path inherits the right-side bias.

Isometrics (`holdAngleRange`) work correctly: counter stays in the up phase until the user leaves the hold range, hold time accumulates, and `isHolding` flips on the output.

---

## Wiring check

- `WorkoutSessionManager` builds a `UniversalRepCounter`, feeds joints from `PoseEstimator` (both 2D and 3D), drives `FormFeedbackEngine`, drives `MotivationEngine`, drives `WorkoutReadyCoordinator`. ✓
- `FormFeedbackEngine.evaluate` returns one feedback per call. The result is passed to `VoiceCoachManager.shared.speakFeedback` and to `UniversalRepCounter.recordFeedbackDuringRep`. ✓
- `MotivationEngine` reads tempo decay from `UniversalRepCounter.repHistory` and face effort from `ExertionAnalyzer`, calls `VoiceCoachManager.shared.playMotivation`. ✓
- `HapticsEngine.repTick` fires on rep completion, `successRipple` on workout completion, `warningPulse` on critical feedback. ✓
- `WorkoutReadyCoordinator` drives the positioning → countdown → active flow with personality-tuned messages. ✓
- Hand gestures (`HandGestureDetector`) wired to start/pause/skip via thumbs up/down/open palm. ✓

The wiring is clean. The only gap is `ElevenLabsService` — it's instantiated and reachable but `VoiceCoachManager` doesn't call it. Either wire it (with the key moved out of source) or delete it.

---

## Prioritized fix plan

**P0 — ship-blockers**

1. Fix `screenPoint` ↔ `videoGravity` mismatch so the skeleton sits on the body.
2. Rotate the ElevenLabs key, move it out of source, and either wire the service or delete the file.

**P1 — should-fix this iteration**

3. Delete `SquatRepCounter.swift`.
4. Make `.bestAvailable` resolution use per-side visibility (or at minimum prefer the side with both joints non-nil).
5. Sort or evaluate-all-then-rank in `FormFeedbackEngine` so severity wins, not declaration order.
6. Cap `slow` tempo penalty at 30.
7. Fix `ExertionAnalyzer.totalWeight` to only accumulate when the blendshape exists.
8. Move `bodyLineAngle` to the 3D path when world joints are present.

**P2 — polish / next iteration**

9. GPU delegate for MediaPipe with thermal/device gating.
10. 3D `kneeValgus` (project onto coronal plane).
11. Single-pass `FramePositionAnalyzer` (drop the `data.reduce`).
12. Split `ExerciseLibrary.swift` per `BodyCategory`.
13. Add Russian twist, dead bug, Superman, single-leg RDL.
14. Tighten RDL hinge target and asymmetry threshold.
15. Mirror skeleton when preview layer is mirrored (front camera).
16. Unwrap angle-arc `atan2` for smoother arc start angle.

---

## What's good

It's worth saying — the refactor moved this codebase a long way. The synthetic joint pattern (`.neck`/`.root`) is the right abstraction; the signed body-line is exactly the kind of small geometry change that prevents an entire class of false positives; the `.moreFlexed`/`.lessFlexed` resolution makes unilateral exercises pleasant to author; `FormFeedbackEngine`'s cascade (body → frame → joints → cooldown → form → positional → asymmetry) is well-ordered. The 46-exercise library is broad and the biomechanics are mostly right on the first pass. The state machine, the hysteresis, the ROM/tempo/feedback decomposition of the form score — none of that is obvious, and all of it landed.

Fix the skeleton mapping and rotate the key, do the P1s in a single PR, and this is in solid shape.
