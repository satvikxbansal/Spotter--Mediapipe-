# P9b: Add workout rest screen

- Thread ID: 019df79d-c4b7-75b0-8931-7c0cb162d15e
- Created: 2026-05-05 15:40:05 (Asia/Kolkata)
- Updated: 2026-05-05 16:28:18 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/05/rollout-2026-05-05T15-40-05-019df79d-c4b7-75b0-8931-7c0cb162d15e.jsonl
- Git branch at thread start: main
- Git SHA at thread start: d75218231e50152c688e4e010cfed270723f2e45
- Exported visible messages: 45
- Extracted input images: 0

## Conversation

### User - 2026-05-05 15:41:33

# Files mentioned by the user:

## Convo with Chatgpt Pro 5.5 model.md: /Users/satvik.bansal/Downloads/Convo with Chatgpt Pro 5.5 model.md

## My request for Codex:
Use the universal Spotter instruction block and read debug log. Understand the complete code and read the DEBUG logs. then go through the below in extreme detail. Read all the existing files, cursor rules. Ensure you are not changing anything else apart from the below. After doing the change share a detailed note on what was done and how can we verify if new changes were implemented correctly and old ones are not broken. For more context, attached is a markdown doc with all the phases defined in the conversation with the 5.5 pro model. WE ARE WORKING ON PHASE 9B ONLY NOW. 

Use the universal Spotter instruction block.

Phase 9B goal:
Add rest screen and complete planned workout lifecycle.

DesignRef screens:
- rest-screen.html
- live-workout screens
- workout-summary.html foundation

Create:
1. RestScreenView
   - last set result
   - last form score
   - best/worst cue
   - countdown
   - +15 seconds
   - skip rest
   - start next set/exercise
   - up next exercise/set details

2. WorkoutSummaryBuilder
   - builds summary from coordinator completed sets

3. WorkoutSessionState enum:
   - ready
   - activeSet
   - rest
   - completed
   - cancelled

4. PlannedWorkoutSessionView updates:
   - active set -> rest -> next set/exercise -> summary
   - if final set completed, route to WorkoutSummaryView

5. Basic WorkoutSummaryView:
   - duration
   - exercises completed
   - total reps
   - total hold seconds
   - average form score
   - completion %
   - coach insight placeholder
   - Done button

Requirements:
- Rest screen must not appear in free-analysis mode.
- Planned workout mode should support rep, hold, timed, and AMRAP targets as gracefully as possible.
- If automatic completion is not reliable for holds/timed targets yet, support manual Complete Set.
- Preserve camera cleanup between sets so no orphan camera session remains.

Tests:
- Complete a 2-exercise generated plan.
- Verify rest appears between sets.
- Verify +15s and skip rest work.
- Verify final summary appears.
- Verify camera stops on exit/cancel.

Acceptance criteria: 
- Full planned workout flow exists.
- Rest screen exists.
- Summary appears.
- Camera lifecycle remains stable.

### Assistant - 2026-05-05 15:41:36

I’ll trace the project first: rules, logs, design refs, and the Phase 9B context file. Then I’ll make the smallest scoped changes for the workout lifecycle and verify the flow with the existing build/tests where possible.

### Assistant - 2026-05-05 15:41:56

The repo already has some Phase 9B-looking files (`RestScreenView`, `WorkoutSummaryBuilder`, `WorkoutSummaryView`) in place, so I’m checking whether they are stubs, partial prior work, or already wired incorrectly. I’m also pulling the instruction block and debug log before touching code.

### Assistant - 2026-05-05 15:42:28

I found the universal block and the active debug protocol. The debug log has entries up through `DL-020`, including a recent rest timer import fix, so I’m treating the current Phase 9B code as potentially partially implemented and validating every lifecycle edge rather than assuming it is finished.

### Assistant - 2026-05-05 15:43:29

The Phase 9B surface is present, but I’m seeing a few likely lifecycle gaps to prove or fix: rest duration source, final set summary timing, progress over multiple planned sets, and whether planned rest can ever leak into free-analysis. I’m reading the surrounding model/service layers now so the patch stays narrow.

### Assistant - 2026-05-05 15:43:56

The camera lifecycle is intentionally still owned by `TrainerSessionView`, and planned mode wraps it instead of creating a second pipeline. That is the right shape for this phase; now I’m going to run the existing planned-workout tests/build path to see whether the partial implementation is healthy before I patch anything.

### Assistant - 2026-05-05 15:46:45

I’m going to make two small implementation changes: tighten coordinator acceptance so a completed-set summary must match the exact active exercise/target, and centralize camera shutdown so Done, Complete Set, cancel, and disappearance all clear the frame handler immediately. Then I’ll add tests around rest/summary lifecycle for hold, timed, AMRAP, and rejection of mismatched set completions.

### Assistant - 2026-05-05 15:48:57

The patch is in. It is deliberately not touching MediaPipe, rep counting, form feedback, plan generation, or the design system. I’m running the planned-workout tests again now, including the new mixed-target lifecycle coverage.

### Assistant - 2026-05-05 15:49:52

Targeted Phase 9B tests pass. I’m going to run the broader workspace test suite now because this change touches shared session/camera surfaces and I want to catch any older flow regression before calling it done.

### Assistant - 2026-05-05 15:50:48

The broad test suite passed too. Because the patch fixes lifecycle/camera cleanup risks, I’m appending the required debug-log entries now before I wrap up.

### Assistant - 2026-05-05 15:51:53

Implemented Phase 9B hardening without touching the core MediaPipe/rep/form/camera pipeline.

**What Changed**
- Tightened planned set completion validation in [PlannedWorkoutCoordinator.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Coaching/PlannedWorkoutCoordinator.swift:80).
  The coordinator now only advances to rest/summary when the completed-set payload matches the active exercise, target, set index, total sets, and total exercises.

- Centralized live camera cleanup in [TrainerSessionView.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/TrainerSessionView.swift:1128).
  `stopLivePipelines()` now clears `cameraManager.onFrame` and stops capture for:
  - planned set completion
  - planned workout cancel
  - free-analysis Done
  - view disappearance

- Added Phase 9B lifecycle coverage in [PlannedWorkoutCoordinatorTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/PlannedWorkoutCoordinatorTests.swift:158).
  New tests cover:
  - rejecting mismatched completion summaries
  - hold targets
  - timed targets
  - AMRAP with timer
  - open/manual AMRAP
  - rest transitions
  - final summary aggregation

- Appended required debug-log entries:
  - `DL-021` for strict planned-set summary validation
  - `DL-022` for shared camera cleanup

**Verified**
- Targeted Phase 9B tests passed:
  `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VirtualTrainerTests/PlannedWorkoutCoordinatorTests`

- Full workspace test suite passed:
  `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'`

**Manual QA Path**
1. Open `VirtualTrainer.xcworkspace`.
2. Start a generated planned workout from Dashboard → Preview → Start Session.
3. Complete first set manually or by target.
4. Verify rest screen appears, `+15s` changes countdown, Skip Rest/Start Set advances.
5. Complete at least two exercises.
6. Verify final summary shows duration, exercises, reps/hold time, form, completion, insight placeholder.
7. Start free-analysis mode and end it; rest screen should not appear.
8. Cancel during a planned set and confirm camera stops immediately, with no lingering camera indicator/session.

### User - 2026-05-05 15:55:22

Can you once again go through the entire code in depth and check for any issues, crashes, dependecies, etc. everyting is wired up correctly. Is 15 seconds rest standard for all exerrcises or is that customisable basis plan  or beginner/intermediate status? what happens after the rest timer stops? 
Ensure timer comes up correctly after every set. ensure sets are configured correctly and their timings too. DO A THOROUGH AUDIT OF THE CODE BASE, NEW CODE CHANGES AND THE FUNCTIONALITY WE ARE BUILDING. IF THERE ARE ANY SCOPE FOR IMPROVEMENT, PLEASE CALL THAT OUT DO THAT TOO. IN THE END SHARE A DETAIELD LIST OF WHAT CHANGES WERE DONE, THEIR IMPACT AND HOW THEY MAKE THE APP BETTER. BE EXTREMELY THOROIGH, CAREFUL AND USE HIGHEST LEVEL OF REASONING.

### Assistant - 2026-05-05 15:55:36

I’ll do this as an audit plus fixes where the code clearly wants tightening. I’ll re-read the session/rest/plan generator path end to end, then run tests again after any scoped improvements.

### Assistant - 2026-05-05 15:55:59

I’ve confirmed rest is not a global hardcoded 15 seconds. The `+15` button is just a user extension; planned rest comes from exercise metadata plus plan rules. I’m checking the generator/rules now because that is where beginner/intermediate and age should influence both targets and rest.

### Assistant - 2026-05-05 15:57:05

A concrete issue surfaced in the free-analysis readiness path: `CameraReadinessView` starts its own camera session, then presents `TrainerSessionView`, which starts another one. Depending on SwiftUI presentation behavior, the readiness camera may not always stop before the full-screen trainer appears. That’s exactly the kind of orphan-session risk we want to kill, so I’m going to patch it alongside rest-screen clarity.

### Assistant - 2026-05-05 15:58:01

I also found a small UX bug while auditing the rest action path: tapping “Start next” caused two button haptics, one in `RestScreenView` and one again in the parent continuation handler. I’m removing the parent duplicate so the tactile feedback stays crisp instead of feeling like a double tap.

### Assistant - 2026-05-05 16:03:23

The cleanup scan now shows both live camera entry points clear `onFrame` before stopping, so frame callbacks will not keep processing after exit or handoff. I’m running the targeted test groups for plan/rest/session next.

### Assistant - 2026-05-05 16:04:59

I’m picking up from the audit where the session compacted: the Phase 9B lifecycle patch is in place, and I’m waiting on the targeted tests that were already running before I do the full-suite pass and final verification.

### Assistant - 2026-05-05 16:05:08

The focused lifecycle and plan-generation tests passed, including the new rest-duration checks for rep, hold, timed, and AMRAP-style targets. I’m doing one more diff/read pass now, then I’ll append the audit notes to the debug log and run the full workspace test suite.

### Assistant - 2026-05-05 16:05:36

The code now answers one of the big behavioral questions cleanly: rest does not auto-launch the next camera session when the countdown hits zero; it marks the rest complete and waits for a user tap. That keeps the camera handoff deliberate, which matters on a phone where the user may still be resetting position.

### Assistant - 2026-05-05 16:05:51

I found two audit-level cleanup gaps and tightened them: the rest screen now has an explicit completed state at zero, and the readiness camera handoff now clears its frame callback before the workout camera is presented. I’m recording those in `DEBUG_LOG.md` before the full test sweep.

### Assistant - 2026-05-05 16:06:07

The debug log now has two new entries for the rest-completion UI/state fix and readiness camera handoff cleanup. I’m running the complete workspace tests now, which is the slow but useful “did we disturb anything outside Phase 9B?” check.

### Assistant - 2026-05-05 16:07:01

Full workspace tests passed on the iPhone 17 simulator. I’m doing the final hygiene checks now: whitespace, changed-file review, and a final status snapshot so the wrap-up can separate verified behavior from the bits that still need a real device camera pass.

### Assistant - 2026-05-05 16:07:09

The code is clean, but the markdown hygiene check caught trailing spaces in the new debug-log entries. I’m cleaning only those log lines, then I’ll rerun the whitespace check.

### Assistant - 2026-05-05 16:07:58

Implemented the Phase 9B audit fixes and re-verified the app. The planned workout flow is now tighter around rest, summary, targets, and camera cleanup.

**Direct Answers**
Rest is **not a universal 15 seconds**. The `+15 sec` button only extends the current rest. Planned rest comes from the plan’s `PlannedExercise.restSeconds`, generated as:

`max(15, exerciseMetadata.defaultRestSeconds + age/level rest policy + block bonus)`

So it is customizable by the plan and affected by exercise metadata, age policy, and some block type logic. Exercise metadata currently uses rest defaults like 30, 45, 60, and 75 seconds.

When the rest timer reaches zero, it now shows **Rest Complete**, fires one success haptic, changes the header action to **Start Now**, and waits for the user to start the next set/exercise. It does **not** auto-start the camera session, which is safer because the user may still be repositioning.

**What Changed**
Tightened planned set completion validation in [PlannedWorkoutCoordinator.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Coaching/PlannedWorkoutCoordinator.swift:80>). A completed set now has to match plan id, exercise type, target, exercise index, set index, total sets, and total exercises before the coordinator can advance to rest or summary.

Improved rest timer completion in [RestScreenView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/RestScreenView.swift:38>). The zero state is explicit now: `Rest Complete`, `Start Now`, one-shot haptic, and `+15 sec` correctly re-arms the completion signal.

Centralized live camera cleanup in [TrainerSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/TrainerSessionView.swift:1128>). Planned set complete, planned cancel, free-analysis Done, and view disappearance all clear `cameraManager.onFrame` and stop capture through the same helper.

Cleaned readiness camera handoff in [CameraTabView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/CameraTabView.swift:294>). The readiness camera now clears its frame handler before free-analysis camera ownership starts.

Removed duplicate start haptic from [PlannedWorkoutSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/PlannedWorkoutSessionView.swift:72>), so tapping start/skip rest does not double-fire feedback.

Expanded tests in [PlannedWorkoutCoordinatorTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/PlannedWorkoutCoordinatorTests.swift:155>) and [PlanGeneratorTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/PlanGeneratorTests.swift:164>) to cover mismatched summary rejection, hold/timed/AMRAP lifecycle, per-set rest transitions, summary aggregation, and generated rest policy.

Added debug-log entries `DL-021` through `DL-024` in [DEBUG_LOG.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/DEBUG_LOG.md:455>).

**Audit Result**
The lifecycle is now:

`activeSet -> rest -> activeSet -> ... -> completed -> WorkoutSummaryView`

Final set completion routes to summary. Free-analysis mode does not enter the rest screen. Manual **Complete Set** remains available for planned mode, which covers hold/timed/AMRAP cases where automatic completion is not reliable or open-ended.

**Verification**
Passed targeted Phase 9B tests:

`PlannedWorkoutCoordinatorTests`, `PlanGeneratorTests`, `WorkoutPreviewTests`, `OnboardingModelTests`

Passed full workspace suite:

`xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'`

Passed hygiene:

`git diff --check`

Manual device QA still matters for real camera hardware: complete a generated 2-exercise plan, confirm rest appears after every non-final set, tap `+15 sec`, tap `Skip Rest`/`Start Now`, finish final set, verify summary, then cancel/exit and confirm the camera indicator turns off cleanly.

### User - 2026-05-05 16:11:18

Good. Do another in depth audit of the entire codebase and check if there are any unwired code or dependencies or crashes or bugs - evaluate and resolve them. 

Post the above, share an end to end manual testing plan for the features in this chat including the rest screen. think deeply and use highest level of reasoning. be very detailed and in depth and evaluate the code with the highest possible technical lens for bugs, etc - code quality can be skipped, we will improve that later. looking for funtiomnal bugs, crashes, suspicious screens - for parts that are sus and might require a round of manual review - call them out and mention in the end to end testing plan so i can verify those too. Post this we will proceed to phase 10.

### User - 2026-05-05 16:11:23

<turn_aborted>
The user interrupted the previous turn on purpose. Any running unified exec processes may still be running in the background. If any tools/commands were aborted, they may have partially executed.
</turn_aborted>

### User - 2026-05-05 16:11:42

Good. Do another in depth audit of the entire codebase and check if there are any unwired code or dependencies or crashes or bugs - evaluate and resolve them. 

Post the above, share an end to end manual testing plan for the features in this chat including the rest screen. think deeply and use highest level of reasoning. be very detailed and in depth and evaluate the code with the highest possible technical lens for bugs, etc - code quality can be skipped, we will improve that later. looking for funtiomnal bugs, crashes, suspicious screens - for parts that are sus and might require a round of manual review - call them out and mention in the end to end testing plan so i can verify those too. Post this we will proceed to phase 10.

### Assistant - 2026-05-05 16:16:45

I’ll do this as a bug audit rather than a style pass: first I’m checking wiring, targets, dependencies, crash-prone patterns, and Phase 9B paths; then I’ll patch anything concrete and rerun the full tests.

### Assistant - 2026-05-05 16:16:57

There’s no stray `xcodebuild` from the aborted turn, but there is a simulator app process still alive. I’m leaving it alone for now and focusing on source-level/runtime-path issues so I don’t disturb your running simulator state.

### Assistant - 2026-05-05 16:17:33

The first substantive audit finding is deployment-target drift: CocoaPods is set to iOS 16, the repo rules say iOS 16/17+, but the app target is currently iOS 26.2. That would make the app uninstallable on normal iOS 17/18/19 devices, so I’m checking API usage before deciding the safest target value.

### Assistant - 2026-05-05 16:20:14

The second real functional risk is in plan swaps: a hold/isometric move could be swapped with a rep-based move sharing the same movement pattern, while keeping the old target. That can produce suspicious sessions like “Squat: hold 30s” or “Tree Pose: 12 reps,” so I’m tightening swap eligibility to preserve target style.

### Assistant - 2026-05-05 16:21:02

I found two concrete things worth fixing now, not just noting: target/config drift that could block real-device installs, and swap logic that could create mismatched targets. I’m patching only those functional risks, then I’ll rebuild/test and inspect the built app bundle for MediaPipe model resources.

### Assistant - 2026-05-05 16:21:44

The patches are in. I’m refreshing CocoaPods metadata after the platform change so `Podfile.lock` and the generated pod configs don’t drift from the app target.

### Assistant - 2026-05-05 16:21:59

CocoaPods regenerated cleanly, and the MediaPipe xcconfig rewrite is still present. I’m running focused tests for the changed plan-swap and Phase 9B lifecycle surfaces before I widen to the full suite.

### Assistant - 2026-05-05 16:23:08

The focused tests passed, including the new guard against hold/rep swap mismatches. I’m checking the built app bundle next: that tells us whether model files and signing entitlements are actually landing the way the source suggests.

### Assistant - 2026-05-05 16:23:21

The built simulator app confirms the important runtime wiring: all four MediaPipe `.task` models are in the app bundle, the app now reports MinimumOSVersion 17.0, and the generated entitlements are empty. I’m also doing a generic iOS build without signing to catch device-slice/linking issues that simulator tests can miss.

### Assistant - 2026-05-05 16:24:53

I’m going back through the last mile now: adding the required debug-log entries for the two audit fixes, then I’ll run the full test/build checks one more time so the final report is grounded in actual verification rather than “looks right.”

### Assistant - 2026-05-05 16:25:02

The existing log already captures the earlier Phase 9B fixes through DL-024. I’m appending the two new audit findings now: the iOS deployment/entitlement mismatch and the plan-swap target-style mismatch.

### Assistant - 2026-05-05 16:25:18

With the log updated, I’m starting the full simulator test suite. This is the broadest automated check available here for wiring, compile-time dependency issues, and the planned-workout state changes.

### Assistant - 2026-05-05 16:25:33

While that full suite runs, I’m doing a separate static sweep for crash-prone patterns and stale wiring markers. I’m keeping this focused on functional risk: force casts, forced tries, fatal errors, dangling deployment settings, and known placeholder paths.

### Assistant - 2026-05-05 16:25:39

The static sweep surfaced one in-target forced unwrap in form feedback and a few older `FitCount-main` files outside the current app target. I’m checking the in-target unwrap now; if it can ever be empty, I’ll harden it rather than leaving a latent crash.

### Assistant - 2026-05-05 16:26:14

The full simulator suite passed. I’m doing the remaining hygiene checks now: whitespace/diff validity, build settings/resource presence, and one unsigned generic iOS device build to make sure this is not only simulator-clean.

### Assistant - 2026-05-05 16:27:13

The generic iOS device build succeeded, and the remaining config checks are clean: iOS target is 17.0, camera privacy string is present, the entitlements plist is empty, and all four MediaPipe task resources are still present. I’m doing a final diff read now for accidental scope creep before I write the handoff.

### Assistant - 2026-05-05 16:28:18

**Audit Result**

I did another deep pass using the universal Spotter instructions, cursor rules, and `DEBUG_LOG.md`. I found and fixed two additional functional risks:

1. The project was effectively targeting iOS `26.2`, despite the app being iOS 17+. This could block installs on normal iOS 17+ devices.
2. Exercise swap could replace an isometric hold exercise with a non-isometric movement while keeping the hold target, which could create broken planned sets.

Rest is **not a flat 15 seconds for all exercises**. Generated rest comes from exercise metadata plus age/fitness policy and slot adjustment in [PlanGenerator.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanGenerator.swift:244>). The `+15 sec` button is only the manual rest extension, and `15` is also the minimum generated rest floor.

When the rest timer reaches zero, it does **not auto-start** the next set. The rest screen changes to `Rest Complete`, the header action becomes `Start Now`, and the user taps to start the next set/exercise.

**Changes Made**

- Set app/test/Pods deployment target to iOS `17.0` in [Podfile](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/Podfile:1>) and the Xcode project.
- Removed invalid macOS camera entitlement from [VirtualTrainer.entitlements](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/VirtualTrainer.entitlements:1>).
- Preserved isometric target style during exercise swaps in [PlanSwapService.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/PlanSwapService.swift:46>).
- Added regression coverage for isometric swap safety.
- Added debug log entries `DL-025` and `DL-026`.
- Reverified Phase 9B lifecycle wiring: `ready -> activeSet -> rest -> activeSet -> completed/cancelled` in [WorkoutSessionContext.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/WorkoutSessionContext.swift:3>) and [PlannedWorkoutSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/PlannedWorkoutSessionView.swift:23>).
- Reverified camera cleanup on set completion, cancel, free-analysis Done, and disappearance in [TrainerSessionView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/TrainerSessionView.swift:1128>).

**Verification Run**

- `pod install` passed.
- Full simulator tests passed: `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Generic iOS device build passed: `xcodebuild build ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
- `git diff --check` passed.
- Build settings confirmed `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.
- Camera privacy string exists.
- Entitlements plist is empty.
- All MediaPipe `.task` resources are present.

**Manual Testing Plan**

1. Fresh install and onboarding:
   - Launch from a clean install.
   - Complete onboarding with beginner profile, age 65+, bodyweight/mat equipment.
   - Relaunch app and confirm profile persists.
   - Use debug reset from Profile tab and verify onboarding restarts.

2. Dashboard and plan preview:
   - Open dashboard after onboarding.
   - Start a generated workout.
   - Confirm preview shows exercises, sets, targets, rest chips, coach, and start button.
   - Try swap on bodyweight-only profile. Confirm no dumbbell exercises appear.
   - For hold/isometric exercises, confirm swaps do not turn them into normal rep movements.

3. Free analysis:
   - Go to camera/free-analysis mode.
   - Start readiness flow.
   - Confirm camera opens, body visibility updates, thumbs-up/manual start works.
   - Complete a few reps and tap Done.
   - Confirm summary appears.
   - Confirm rest screen never appears in free-analysis mode.
   - Confirm camera indicator turns off after Done.

4. Planned workout happy path:
   - Start a generated workout with at least two exercises.
   - Complete set 1 manually or by hitting target.
   - Confirm camera stops and rest screen appears.
   - Confirm rest screen shows last set result, form score, best/worst cue, countdown, and up-next details.
   - Tap `+15 sec` and confirm timer increases.
   - Tap `Skip Rest` and confirm next set/exercise starts with readiness/camera again.
   - Complete all sets.
   - Confirm final set goes directly to workout summary, not rest.

5. Rest timer behavior:
   - Let rest timer reach zero.
   - Confirm label changes to `Rest Complete`.
   - Confirm action changes to `Start Now`.
   - Confirm no automatic camera restart happens at zero.
   - Tap `Start Now` and confirm next set begins.

6. Target variants:
   - Verify rep targets auto-complete when reps are reached.
   - Verify hold/timed targets can be manually completed if auto-completion feels unreliable.
   - Verify AMRAP with duration ends at duration.
   - Verify open-ended AMRAP requires manual `Complete Set`.

7. Camera lifecycle stress:
   - Start planned set, cancel with `x`, confirm camera stops.
   - Complete set, wait on rest screen, confirm camera stays off.
   - Start next set, confirm camera restarts cleanly.
   - Background app during active set, rest screen, and summary.
   - Return and verify no crash or orphan camera session.

**Suspicious Areas To Manually Review**

- Live workout still shows debug-style angle and gesture labels. Functional, but worth deciding if they should remain visible.
- Profile tab is still `ProfileDebugView`.
- Running Analysis and Trophies are intentional placeholder/teaser paths.
- Camera permission denied path should not crash, but UX may feel unfinished.
- Summary is in-memory only right now; workout history persistence is naturally Phase 10 territory.
