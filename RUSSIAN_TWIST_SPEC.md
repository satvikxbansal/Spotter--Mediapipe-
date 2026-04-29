# Russian Twist — Biomechanics & Implementation Spec

For VirtualTrainer (iOS, MediaPipe Pose Landmarker, BlazePose world landmarks).

---

## Feasibility

Yes — implementable today with no new model, no new sensors, no UI changes beyond adding the exercise card.

The signal is **rotation of the shoulder line around the vertical (Y) axis**. MediaPipe's 3D world landmarks (`worldJoints: [JointName: SIMD3<Float>]`, already published by `PoseEstimator`) give you `x`, `y`, `z` in meters with the pelvis as origin. That's exactly the data needed for transverse-plane angle measurement. The 2D landmarks alone are not enough — they foreshorten as the user rotates, which would make the angle non-monotonic. The 3D path is correct.

Front-facing camera works. Side-facing camera does not (shoulder vector collapses to a point on rotation). Add a hint: "Face the camera directly."

---

## Biomechanics

**Setup**: seated on the floor, knees bent ~90°, feet flat or elevated, trunk leaned back ~45° from vertical (hip angle ~135°), arms held in front of the chest (clasped or holding weight).

**Movement**: rotate the trunk side-to-side around the vertical axis. The shoulders sweep through an arc while the hips stay relatively stationary. End range is roughly **30–45°** of rotation per side, measured at the shoulder line relative to the hip line.

**Counting convention**: each excursion past threshold counts as one rep. So 20 reps = roughly 10 left + 10 right, alternating. This matches how every fitness app and most coaches count it.

**Primary movers**: obliques (internal + external), rectus abdominis (isometric for the lean-back), hip flexors (isometric).

**Common form errors** (these become your `formRules` and `positionalChecks`):

1. **Not leaning back enough** — user sits upright, so the obliques don't load. Hip angle should be ~120–150°, not 170° (sitting straight up).
2. **Not rotating enough** — shoulders barely move past center. End-range rotation should be ≥25°.
3. **Hips rotating with shoulders** — whole-body twist instead of isolated trunk twist. Measured as hip-vector rotation matching shoulder-vector rotation.
4. **Bilateral asymmetry** — significantly bigger rotation to one side than the other (suggests core imbalance or compensating for an injury).
5. **Speed** — too fast = loss of control, momentum-driven. Tempo target ~1.5–2.5s per side.

---

## Angle definition (math)

You need two new quantities. Both go into `AngleCalculator.swift`.

### 1. `signedTrunkTwistAngle` (3D world landmarks required)

The signed rotation of the shoulder vector relative to the hip vector, projected onto the horizontal plane.

```
let shoulderVec = world[.rightShoulder] - world[.leftShoulder]   // SIMD3<Float>
let hipVec      = world[.rightHip]      - world[.leftHip]

// Project onto horizontal (XZ) plane — zero out the Y (vertical) component.
let s = SIMD3<Float>(shoulderVec.x, 0, shoulderVec.z)
let h = SIMD3<Float>(hipVec.x,      0, hipVec.z)

let sN = simd_normalize(s)
let hN = simd_normalize(h)

let dot = simd_clamp(simd_dot(sN, hN), -1.0, 1.0)
let unsigned = acos(dot)                    // 0 to π

// Sign via cross product Y component: positive Y = counter-clockwise
// when viewed from above (rotating to the user's left).
let cross = simd_cross(hN, sN)
let signed = cross.y >= 0 ? unsigned : -unsigned

let degrees = signed * 180.0 / .pi          // -90…+90, typically -45…+45
```

Returns degrees. **Negative = rotated to user's right, positive = rotated to user's left** (consistent with right-hand rule around the vertical axis). At neutral (shoulders aligned with hips) it's 0.

### 2. `trunkTwistMagnitude`

`abs(signedTrunkTwistAngle)`. This is what the rep counter consumes — the existing state machine works on monotonic 1D signals, and absolute value gives you exactly that (one "rep" = excursion to either side past threshold).

### 3. Lean-back angle (re-uses existing math)

Hip flexion angle = `angle(shoulder, hip, knee)`. For Russian twist, target range **120°–150°**. Below 120° = leaned back too far (uncontrolled). Above 150° = sitting too upright (no oblique load).

---

## Rep counter wiring

The exercise fits the existing `UniversalRepCounter` state machine cleanly **if** you feed it `trunkTwistMagnitude` (always positive) instead of the signed angle:

- **down phase** (= "rotated"): magnitude > 25°
- **up phase** (= "centered"): magnitude < 10°
- One full cycle (center → side → center) = 1 rep
- Hysteresis 2 frames as everywhere else
- `minRepDuration` = 0.4s (slightly faster than the default 0.5s — twists are quicker than squats)

This counts each side as a rep without enforcing alternation. To enforce alternation, track the sign of the most recent side and flag a `warning` cue if the same side fires twice in a row (this is good as a v2).

---

## Exercise definition

Add a new case `.russianTwist` to `ExerciseType`, list it under `BodyCategory.core` (or wherever your obliques live), and add a definition to `ExerciseLibrary.swift`. Pattern matching your existing entries:

```swift
.russianTwist: ExerciseDefinition(
    type: .russianTwist,
    displayName: "Russian Twist",
    bodyCategory: .core,
    isometric: false,
    requiredJoints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee],
    visibilityHint: "shoulders, hips, and knees",
    primaryAngle: .trunkTwistMagnitude,                   // NEW metric
    angleSource: .trunkTwistMagnitude,
    repThresholds: RepThresholds(
        downEnterAbove: 25,                               // rotated to a side
        downExitBelow:  20,
        upEnterBelow:   10,                               // back near center
        upExitAbove:    15
    ),
    tempo: TempoTarget(min: 1.0, max: 2.5),               // per side
    formRules: [
        FormRule(
            id: "leanBack",
            metric: .leanBackAngle,                       // NEW: hip flexion
            range: 120...150,
            severity: .warning,
            activeDuringPhases: [.up, .down],
            messages: [
                .good:  "Lean back a bit more — keep tension on your core",
                .drill: "LEAN BACK! You're sitting straight up!"
            ],
            failsBelowMessages: [
                .good:  "Lean back a bit more — keep tension on your core",
                .drill: "LEAN BACK! You're sitting straight up!"
            ],
            failsAboveMessages: [
                .good:  "Don't lean back so far — control the movement",
                .drill: "Sit UP a touch — you're losing control!"
            ]
        ),
        FormRule(
            id: "rotationDepth",
            metric: .trunkTwistMagnitude,
            range: 25...60,
            severity: .info,
            activeDuringPhases: [.down],
            failsBelowMessages: [
                .good:  "Rotate further — get your shoulders past your hips",
                .drill: "TWIST! Get those shoulders around!"
            ],
            failsAboveMessages: nil
        )
    ],
    positionalChecks: [
        // Hip stability — hips shouldn't rotate as much as shoulders
        PositionalCheck(
            id: "hipStability",
            kind: .hipRotationStability(maxHipRotation: 15),  // NEW check
            severity: .warning,
            persistFrames: 5,
            messages: [
                .good:  "Keep your hips steady — twist from the waist, not the legs",
                .drill: "STOP rotating your hips! Twist from the WAIST!"
            ]
        )
    ],
    bilateralAsymmetry: BilateralAsymmetryRule(
        metric: .trunkTwistByDirection,                   // NEW: returns max abs left, max abs right
        deltaThreshold: 12,                               // 12° matters more here than 15°
        cooldownSeconds: 10,
        messages: [
            .good:  "You're rotating further to one side — try to match both",
            .drill: "EVEN it out! You're favoring one side!"
        ]
    )
)
```

The three new things you're adding to `AngleCalculator`:

1. `trunkTwistMagnitude` — `abs(signedTrunkTwistAngle)`, primary rep signal.
2. `leanBackAngle` — same as existing `hipFlexion` measured as `angle(shoulder, hip, knee)`, but you may want a distinct name so the user-facing message is right.
3. `hipRotationStability` (positional check) — track the absolute angle of the hip vector itself relative to the camera frame's Z axis over the last N frames, flag if hip rotation exceeds `maxHipRotation`.

`trunkTwistByDirection` is a small extension to your asymmetry rule: track max signed twist per side over the set, compare absolute values.

---

## Cursor prompt (paste into Cursor)

```
Add the Russian Twist exercise to the VirtualTrainer iOS app. Follow the existing patterns
in the codebase exactly — don't introduce new abstractions unless required.

CONTEXT

The app uses MediaPipe Pose Landmarker (Full task) and publishes both 2D image-space joints
and 3D world joints (BlazePose, hip-center origin, meters) from VirtualTrainer/Vision/
PoseEstimator.swift. AngleCalculator.swift owns all metric math. UniversalRepCounter.swift
runs an idle → down → up → idle state machine on a single primary angle with hysteresis.
ExerciseLibrary.swift holds per-exercise definitions; new exercises are added by appending
a case to ExerciseType (in WorkoutData.swift) plus a definition entry, and listing the
exercise under the appropriate BodyCategory.

Russian twist is a transverse-plane rotation: the trunk rotates around the vertical (Y)
axis, sweeping the shoulders side-to-side while the hips stay roughly stationary. The user
sits leaned back ~45° with knees bent. End range is ~30–45° rotation per side. Each
excursion past threshold counts as one rep.

REQUIREMENTS

1. Add `.russianTwist` to the `ExerciseType` enum in VirtualTrainer/Models/WorkoutData.swift.
   Add it to the core (obliques) entry of `BodyCategory.exercises`. Set `available: true`.

2. Add three new metrics to VirtualTrainer/Vision/AngleCalculator.swift:

   a. `signedTrunkTwistAngle(world: [JointName: SIMD3<Float>]) -> Double?` — returns the
      signed rotation in degrees of the shoulder vector relative to the hip vector,
      projected onto the horizontal (XZ) plane. Use simd_cross to determine sign:
      positive cross.y means counter-clockwise rotation (user's left). Returns nil if
      any of leftShoulder, rightShoulder, leftHip, rightHip is missing from world joints.
      Range typically -90…+90, real-world Russian twist range is -45…+45.

   b. `trunkTwistMagnitude(world: …) -> Double?` — abs(signedTrunkTwistAngle). This is
      the primary rep-counter signal.

   c. `leanBackAngle(joints2D: …, world: …) -> Double?` — hip flexion measured as
      angle(shoulder, hip, knee). Prefer 3D when available, fall back to 2D. Use the
      existing `pickSideValue3D` / `pickSideValue` for side selection (this exercise
      should resolve to the side facing the camera most directly — use
      `.bestAvailable`, but be aware of the existing right-bias in `.bestAvailable`).

   Wire each new metric into `MetricKind` (or whatever the existing metric enum is named)
   and into the `computeAngles` / `computeAngles3D` switch statements so they're available
   to the rep counter and form rules.

3. Add a new `PositionalCheck` kind: `hipRotationStability(maxHipRotation: Double)`. The
   evaluator computes the angle of the hip vector (rightHip − leftHip projected onto XZ)
   relative to the camera's Z axis, tracks the rolling max over the last 5 frames, and
   fails when that max exceeds `maxHipRotation` degrees. Wire it into FormFeedbackEngine
   the same way `kneeValgus` and `heelRise` are wired (3-frame persistence).

4. Add the exercise definition to VirtualTrainer/Models/ExerciseLibrary.swift using the
   skeleton in this spec (see RUSSIAN_TWIST_SPEC.md, "Exercise definition"). Match the
   formatting and field order of the surrounding entries (e.g., the existing core
   exercises like sitUp / reverseCrunch).

5. Rep thresholds: downEnterAbove 25°, downExitBelow 20°, upEnterBelow 10°, upExitAbove
   15°. Tempo target 1.0–2.5s per rep. minRepDuration 0.4s (override the default 0.5s).

6. Form rules:
   - leanBackAngle in 120°…150°, severity warning. Below = "Lean back more"; above =
     "Don't lean back so far". Active in both up and down phases.
   - trunkTwistMagnitude in 25°…60°, severity info, active during down phase. Below =
     "Rotate further". (No "above" message.)

7. Bilateral asymmetry: track max signed twist per side across the set, compare absolute
   values, flag at 12° delta with 10s cooldown. (Tighter than the default 15° because
   asymmetry matters more here.)

8. Visibility hint: "shoulders, hips, and knees". `requiredJoints` includes
   leftShoulder, rightShoulder, leftHip, rightHip, leftKnee, rightKnee.

9. Add a one-line camera-orientation hint in the readiness coordinator's positioning
   message for this exercise: "Face the camera directly so it can see your shoulders
   rotate." Side-facing won't work because the shoulder vector collapses to a point.

VOICE COACHING

Add coach lines for both personalities (good / drill) using the same vocabulary patterns
as the existing core exercises. Example:

   leanBack — good: "Lean back a bit more — keep tension on your core"
              drill: "LEAN BACK! You're sitting straight up!"
   rotation — good: "Rotate further — get your shoulders past your hips"
              drill: "TWIST! Get those shoulders around!"
   hips     — good: "Keep your hips steady — twist from the waist, not the legs"
              drill: "STOP rotating your hips! Twist from the WAIST!"
   asymmetry — good: "You're rotating further to one side — try to match both"
               drill: "EVEN it out! You're favoring one side!"

TESTS

Add unit tests in the existing AngleCalculator test target:

   - signedTrunkTwistAngle returns 0 (±2°) when shoulder and hip vectors are parallel.
   - signedTrunkTwistAngle returns +30° (±2°) for a synthetic pose rotated 30° to the
     user's left around the Y axis, and -30° when rotated to the right.
   - trunkTwistMagnitude is always non-negative.
   - leanBackAngle returns ~135° for a synthetic seated pose with the trunk leaned back
     45° from vertical.

For the rep counter, add a test that runs a sequence of synthetic frames sweeping
trunkTwistMagnitude through 0 → 30 → 0 → 30 → 0 and asserts 2 reps counted.

NON-GOALS

Don't enforce strict alternation in v1 — most users alternate naturally and the
asymmetry rule already catches gross imbalance. Don't add weighted-twist detection
(arms-extended vs. weight-held) — out of scope. Don't add foot-elevated detection
— treat any seated configuration the same.
```

---

## Notes for the implementer

- The right-bias in `.bestAvailable` is a known issue (called out in `SPOTTER_REVIEW.md`). For Russian twist specifically, side selection for `leanBackAngle` should prefer whichever side has both shoulder and knee non-nil; if both do, the right bias is harmless because the lean is symmetric.

- The `hipRotationStability` check assumes the user is roughly facing the camera at the start of the set (so the hip vector starts close to perpendicular to the camera Z axis). If they slowly drift their seated orientation across a set, the check will false-positive. Mitigation: capture the hip-vector orientation at rep #1 as the baseline, then measure deviation from that baseline rather than from the camera Z axis. Same idea as how a head-tracking IMU calibrates "forward."

- A subtle issue: BlazePose's world landmark Y axis points _down_ in the standard convention (pelvis origin, Y down, Z forward). Double-check the sign in your project — if Y is flipped, the cross-product sign for the twist direction also flips. The unit test for "rotated 30° to user's left = +30°" will catch this.

- If you want a v2 that enforces alternation: track `lastTwistSign` on the rep counter (only set when a rep completes), and on the next rep emit a `warning` cue if the new sign matches `lastTwistSign`. Reset `lastTwistSign` after every set.

- Russian twist's primary rep signal — magnitude rather than signed angle — is the only place in your codebase where the rep counter consumes a "always positive" angle. Worth a comment in `ExerciseLibrary.swift` so the next maintainer doesn't try to "fix" it.
