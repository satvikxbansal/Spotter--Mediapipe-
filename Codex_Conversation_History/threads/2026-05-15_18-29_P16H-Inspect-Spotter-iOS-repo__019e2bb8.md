# P16H: Inspect Spotter iOS repo

- Thread ID: 019e2bb8-c263-7021-8b5c-8fe744ff50f4
- Created: 2026-05-15 18:29:49 (Asia/Kolkata)
- Updated: 2026-05-15 19:05:18 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/15/rollout-2026-05-15T18-29-49-019e2bb8-c263-7021-8b5c-8fe744ff50f4.jsonl
- Git branch at thread start: main
- Git SHA at thread start: a4b84b8978c515b7aff1b4485695dab06cd676fd
- Exported visible messages: 37
- Extracted input images: 0

## Conversation

### User - 2026-05-15 18:30:27

You are working in the Spotter iOS Swift repository.

Before changing code:
1. Inspect the current tree end-to-end. Read README.md, DEBUG_LOG.md, every file in
   Documentation/, the relevant Swift files in VirtualTrainer/, and the most recent
   git history (git log --oneline -20).
2. Treat this prompt as guidance, not a blind spec. If the current code reveals a
   safer approach, take it and explain why in the summary.
3. Do NOT rewrite the live camera pipeline:
   - CameraManager
   - PoseEstimator
   - UniversalRepCounter
   - FormFeedbackEngine
   - HandGestureDetector
   - ExertionAnalyzer
   - WorkoutReadyCoordinator
   - FaceLandmarkerService
   - FramePositionAnalyzer
4. Preserve both training flows: Free Analysis from the Camera tab AND Planned
   Workouts from the Dashboard. They share the live analysis stack.
5. Preserve deterministic local planning, trophies, stats, trends, recaps, weekly
   recaps, heatmaps, and AI insights. The local pipeline must keep working with
   no Firebase config.
6. Keep BackendMode.local fully functional. The app MUST build and run with
   GoogleService-Info.plist absent.
7. Privacy: do NOT store or upload raw video, camera frames, face images, raw
   pose streams, raw pose timelines, raw biometric face data, raw face blendshape
   streams, or any third-party secret.
8. Do NOT print plist contents, Firebase API keys, App Check debug tokens, or
   any secret-like value to stdout, logs, or test fixtures.
9. Maintain backwards-compatible Codable decoding for existing local JSON files.
10. Toolchain: use the bundled Xcode toolchain (XcodeDefault.xctoolchain). Verify
    with:
        xcrun --find clang
        xcrun --find swiftc
    Both must resolve under
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain.
    See DEBUG_LOG.md entry DL-045 for why this matters.
11. Builds: always use VirtualTrainer.xcworkspace, never the bare xcodeproj.
12. Do NOT run multiple xcodebuild test commands against the same DerivedData
    path in parallel.
13. Keep the app compiling after every phase.
14. After the phase, run:
        xcodebuild build  -workspace VirtualTrainer.xcworkspace \
            -scheme VirtualTrainer \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -derivedDataPath /tmp/VirtualTrainerDerivedData
        xcodebuild test   -workspace VirtualTrainer.xcworkspace \
            -scheme VirtualTrainer \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
            -derivedDataPath /tmp/VirtualTrainerDerivedData
    and summarize PASS/FAIL counts.
15. If the phase changed behavior, append a DEBUG_LOG.md entry following the
    existing format (use the next DL-### number, real ISO date, error,
    root cause, fix applied, verification, prevention rule, pattern tags).
16. Summarize in the PR description: changed files, key decisions, Firebase
    console/manual steps required of the developer, migration behavior, and
    known follow-ups.
17. Git pre-flight: confirm git status is clean before starting. Confirm the
    branch you intend to target. After commits, run git diff --check to catch
    whitespace errors.
18. Secret pre-flight: run any available secret scan (the repo ships
    .gitleaks.toml). Fail the phase if real secrets would be committed. 
19. Mention the change the code brings to the application - the before and after with real life practical examples if possible. 
20. Share an indepth end to end manual testing plan of the changes done - be practical and ensure all aspects are tested well before we proceed.

Phase 16H goal: lock down server-side access and prepare for App Check without
enforcing yet.

Tasks:

1. Documentation/firestore.rules
   Use this content as the v1 (owner-only) version, then publish via
   Firebase Console:

   rules_version = '2';

   service cloud.firestore {
     match /databases/{database}/documents {

       function signedIn() {
         return request.auth != null;
       }
       function owns(uid) {
         return signedIn() && request.auth.uid == uid;
       }
       function isString(v) { return v is string; }
       function nonEmpty(v) { return isString(v) && v.size() > 0; }
       function hasAccountId(uid) {
         return request.resource.data.accountId == uid;
       }

       // Forbid raw-sensor field names anywhere in the user tree.
       function noRawData() {
         return !(
           "rawVideo" in request.resource.data ||
           "videoFrame" in request.resource.data ||
           "cameraFrame" in request.resource.data ||
           "faceImage" in request.resource.data ||
           "rawPoseStream" in request.resource.data ||
           "rawPoseTimeline" in request.resource.data ||
           "rawLandmarks" in request.resource.data ||
           "rawFaceBlendshapeStream" in request.resource.data ||
           "biometricFaceData" in request.resource.data ||
           "imageData" in request.resource.data ||
           "pixelBuffer" in request.resource.data ||
           "apiKey" in request.resource.data ||
           "privateKey" in request.resource.data ||
           "serviceAccount" in request.resource.data
         );
       }

       match /users/{uid} {
         allow read, write: if owns(uid);

         match /profile/{doc} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;  // delete-by-tombstone only
         }

         match /workouts/{workoutId} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;

           match /sets/{setId} {
             allow read: if owns(uid);
             allow create, update: if owns(uid) && noRawData();
             allow delete: if false;
           }
         }

         match /trophyEvents/{eventId} {
           allow read: if owns(uid);
           allow create: if owns(uid) && hasAccountId(uid) && noRawData();
           allow update: if false;  // append-only
           allow delete: if false;
         }
         match /trophyProgress/{doc} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;
         }

         match /insights/{dedupeKey} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;
         }
         match /insightDelivery/{dedupeKey} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;
         }
         match /insightEngagement/{dedupeKey} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;
         }

         match /calibration/{doc} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if false;
         }

         match /plans/{planId} {
           allow read: if owns(uid);
           allow create, update: if owns(uid) && hasAccountId(uid) && noRawData();
           allow delete: if owns(uid);  // plans may be cleared by user
         }
       }

       // Default deny
       match /{document=**} {
         allow read, write: if false;
       }
     }
   }

   Add a TODO comment in the file noting that Phase 16J will introduce
   schema-level field validation (required fields, types).

2. Documentation/FirebaseConsoleChecklist.md
   Bullet checklist of console steps including:
   - Auth: anonymous on, all others off until 19
   - Firestore Rules: paste from firestore.rules
   - Firestore Indexes: none initially; let Firebase auto-suggest at runtime
     and document the resulting indexes here as they appear
   - App Check: register iOS app for debug; do NOT enable enforcement
   - Storage / RTDB: disabled
   - Functions: not deployed yet

3. App Check debug provider.
   - Add FirebaseAppCheck SPM dependency.
   - In #if DEBUG before FirebaseApp.configure(), install
     AppCheckDebugProviderFactory.
   - Add Documentation/AppCheckRollout.md describing:
       - How to obtain a debug token in Console
       - Why we do not enforce yet
       - Production path: switch to AppAttestProvider on iOS 14.5+

4. Privacy assertion tests.
   Add tests that introspect every Firestore write payload produced by every
   repository under realistic call patterns; the assertion is the payload's
   key set is a subset of the DTO's published keys (no surprise fields), and
   contains none of the forbidden keys.

5. Cross-uid denial smoke.
   Add a manual checklist item: use Firebase Emulator Suite (or the live dev
   project) to attempt a write at users/SOME_OTHER_UID/profile/current with
   a different uid's auth token. Confirm denial. (This becomes automated in
   Phase 17 with the emulator.)

Acceptance:
- firestore.rules file exists and matches the published rules.
- Console checklist exists.
- App Check debug provider installed in DEBUG only.
- Privacy assertion tests cover every repository write path.
- BackendMode.local and BackendMode.firebase both build.

### Assistant - 2026-05-15 18:30:35

I’ll first do the required pre-flight and repo read-through before touching anything: tree, docs, relevant Swift, toolchain, git state/history, and available secret scanning config. Then I’ll make the smallest Phase 16H changes that fit the current architecture.

### Assistant - 2026-05-15 18:30:47

The pre-flight shows a clean `main` branch and the Xcode toolchain paths resolve exactly under `XcodeDefault.xctoolchain`, which matches the DL-045 constraint. I also see a real `GoogleService-Info.plist` present locally, so I’ll avoid printing or touching its contents and keep all checks secret-safe.

### Assistant - 2026-05-15 18:31:20

I’ve finished the README and current `Documentation/` pass. The important constraint is consistent across them: Firebase mode is optional and partial, theme remains profile-backed remotely, workouts use compact parent docs plus set subdocs, and raw sensor payloads must stay out of every persistence path.

### Assistant - 2026-05-15 18:31:32

The debug log confirms DL-045’s toolchain lesson and the current next incident number is effectively `DL-057` despite the stale header. I’m moving into the Swift/Firebase repository layer now, especially the payload boundary where the privacy tests need to hook in.

### Assistant - 2026-05-15 18:33:50

The current Firebase write boundary is cleanly isolated: every production write already flows through repository DTOs or patch helpers, then through `FirestorePrivacyValidator`. I’m going to keep that shape and add the App Check hook at bootstrap plus tests that exercise the repositories rather than touching the live camera/session stack.

### Assistant - 2026-05-15 18:34:41

I’ve got enough context to edit now. The implementation plan is intentionally narrow: add owner-only rules/docs, add `FirebaseAppCheck` as an explicit SPM product, install the debug provider inside `FirebaseBootstrap` before configuration, and extend the existing Firestore repository test harness so repository writes are checked by payload shape and privacy boundary.

### Assistant - 2026-05-15 18:38:56

The docs and App Check bootstrap patch are in. I also added the privacy test at the repository seam: it runs realistic writes for profile, theme, calibration, plans, workouts, trophies, insights, delivery, engagement, and tombstones, then checks the captured Firestore payload keys and forbidden raw-data fields.

### Assistant - 2026-05-15 18:39:55

The first focused run compiled far enough to prove the App Check product is resolving and linking, but the new test used two enum case names that don’t exist in this codebase. I’m tightening that fixture code to the local enum names and rerunning the focused check.

### Assistant - 2026-05-15 18:43:33

The fallback secret scan over changed and new non-ignored files passed with no findings. I’m moving into the required sequential build and test commands now, using the shared `/tmp/VirtualTrainerDerivedData` path only one `xcodebuild` at a time.

### Assistant - 2026-05-15 18:45:08

I’ve got the repo context and the Phase 16H changes in place. I’m picking up at verification now: full workspace build, full test pass, then I’ll add the DEBUG_LOG entry with the actual results and do the final scans.

### Assistant - 2026-05-15 18:45:15

The working tree has only the expected Phase 16H edits and we’re still on `main`. I’m running the required workspace build now with the shared DerivedData path, and I’ll keep the test run sequential after it finishes.

### Assistant - 2026-05-15 18:45:36

Full build passed. Next I’m running the full test suite with the same workspace/scheme and DerivedData path, still sequentially so the simulator build state stays boring in the best possible way.

### Assistant - 2026-05-15 18:46:14

The full test run is still active. No failure output has appeared yet; I’m letting xcodebuild finish rather than interrupting the simulator run.

### Assistant - 2026-05-15 18:47:01

The required full test run passed. I’m extracting the actual pass/fail counts from the test log now, then I’ll do the extra local/firebase build checks the acceptance text calls out.

### Assistant - 2026-05-15 18:47:25

The required build/test are green. I’m doing two extra acceptance checks now: first a local-mode build with the ignored Firebase plist temporarily moved aside, then a Firebase-mode build-setting override to make sure both backend modes still compile.

### Assistant - 2026-05-15 18:48:39

The no-plist local build is still running, which is normal on a fresh DerivedData path because it recompiles the package graph. The command has a trap to restore the ignored plist when it exits.

### Assistant - 2026-05-15 18:49:23

Local mode without a Firebase plist built successfully and the ignored plist was restored. The Firebase-mode build-setting override is now compiling on its own DerivedData path.

### Assistant - 2026-05-15 18:49:56

Both backend compile checks are green: local no-plist and Firebase mode. I’m checking the current DEBUG_LOG format and then I’ll append the Phase 16H entry with the real verification results.

### Assistant - 2026-05-15 18:51:00

The DEBUG_LOG entry is appended as DL-057. I’m doing the final hygiene pass now: toolchain re-check, whitespace check, and a changed-file secret scan that reports only filenames/pattern labels if anything trips.

### Assistant - 2026-05-15 18:51:32

Final hygiene is clean: XcodeDefault paths verified, `git diff --check` passed, and the fallback changed-file secret scan passed because `gitleaks` is not installed here. I’m doing one last review of the changed hunks so the summary can point to the exact places.

### Assistant - 2026-05-15 18:52:11

Implemented Phase 16H on `main`. Initial git status was clean; final tree has only the expected Phase 16H files changed.

**Changed**
- Added owner-only Firestore v1 rules with raw-data/secret-like field denial and Phase 16J schema-validation TODO: [Documentation/firestore.rules](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/firestore.rules:1)
- Added console rollout checklist, including anonymous auth only, rules publishing, no initial indexes, App Check debug registration without enforcement, disabled Storage/RTDB, no Functions, and cross-uid denial smoke: [Documentation/FirebaseConsoleChecklist.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/FirebaseConsoleChecklist.md:1)
- Added App Check rollout notes: [Documentation/AppCheckRollout.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/AppCheckRollout.md:1)
- Linked `FirebaseAppCheck` and installed `AppCheckDebugProviderFactory` in `#if DEBUG` before `FirebaseApp.configure()`: [FirebaseBootstrap.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/FirebaseBootstrap.swift:1)
- Added repository write payload privacy tests covering profile, theme, calibration, plans, workouts/sets/tombstones, trophies, insights, delivery, and engagement: [FirestoreRepositoryTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/FirestoreRepositoryTests.swift:274)
- Appended DEBUG_LOG entry `DL-057`: [DEBUG_LOG.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/DEBUG_LOG.md:1)

**App Behavior**
Before: Firebase mode could compile and write through repositories, but the server-side owner-only rule checklist, App Check debug setup, and every-write payload guardrail were not locked down together.

After: a developer can run Firebase mode for internal testing with DEBUG App Check tokens, publish owner-only rules, and verify repository payloads stay DTO-shaped and free of raw camera/pose/face/secret fields. Example: saving a workout still syncs derived summaries and set quality evidence, but a surprise field like `cameraFrame`, `rawPoseTimeline`, or `apiKey` would now fail the repository privacy test and be denied by the documented Firestore rules.

**Verification**
- Toolchain:
  - `clang` and `swiftc` both resolve under `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`
- Required build: PASS
- Required tests: PASS, `392` passed, `0` failed
- `BackendMode.local` no-plist build: PASS
- `BackendMode.firebase` build-setting override: PASS
- `git diff --check`: PASS
- `gitleaks` was not installed; fallback changed-file secret scan: PASS
- Protected live camera pipeline files were not modified.

**Firebase Manual Steps**
Publish `Documentation/firestore.rules` in Firebase Console, enable only anonymous auth, register App Check debug tokens, keep enforcement off, keep Storage/RTDB disabled, deploy no Functions, and document any Firebase-suggested indexes only after runtime errors surface them.

**Migration**
No local JSON schema changes and no Codable migrations required. `BackendMode.local` remains functional with `GoogleService-Info.plist` absent.

**Manual Testing Plan**
1. Local no-plist: remove real Firebase plists, launch local mode, complete onboarding, create a dashboard plan, run Free Analysis, run a Planned Workout, save history, verify trophies/stats/trends/recaps/weekly recaps/heatmaps/insights still update.
2. Firebase dev: restore dev plist, set Firebase mode, launch DEBUG, register the App Check debug token in Console, sign in anonymously, run profile/theme/calibration/plan/workout/trophy/insight smoke actions.
3. Rules smoke: authenticate as UID A, attempt write to `users/UID_B/profile/current`, confirm denied.
4. Privacy smoke: inspect Firestore documents after saves; confirm only derived DTO fields exist, no raw frames/images/pose streams/face blendshapes/secrets.
5. Regression pass: repeat Free Analysis and Planned Workout flows to confirm the shared live analysis stack is unchanged.

Known follow-ups: Phase 16J schema-level field validation, Phase 17 emulator automation for cross-uid denial/rules tests, production App Attest provider path before App Check enforcement.

### User - 2026-05-15 18:52:11

Lot of changes done above which included a context compaction in the middle and lost stream too. 700+ lines of code were written - that's a lot. Can you go through the original prompt, code changes done in extreme detail, audit them, ensure all the required changes were done and done correctly with no downstream impact. the code before this works fine with it. all the services that needed to be changed have been changed and nothing is left or missed. be very thorough in your analysis and evaluation. use highest level of reasoning available. Log the rca in the debug log and explain why the misses were missed. use highest level of thinking possible and think deeply. Evaluate and understand very deeply. Be very thorough and detailed. Have high attention to detail

### Assistant - 2026-05-15 18:52:24

I’m going back into audit mode and treating the prior work as suspect until proven otherwise. I’ll map each original requirement to the actual diff, inspect every repository write path against the new privacy test, run focused verification where useful, then append a new DEBUG_LOG RCA entry with any misses and why they slipped through.

### Assistant - 2026-05-15 18:52:45

I’ve started with the actual diff rather than trusting the earlier summary. One thing already worth checking carefully: the new privacy test says it covers every repository write path, so I’m now enumerating the repository protocols and concrete Firestore methods method-by-method against that test.

### Assistant - 2026-05-15 18:53:46

The write-path enumeration shows the app has fewer concrete Firestore write methods than the docs/rules collections imply: `trophyProgress` is currently read/cache-only in the repository layer, so there is no write path to test there yet. I did find one audit-quality weakness in the new test: it validated every captured payload, but only asserted a minimum write count rather than proving each intended write category occurred. I’m going to tighten that now so future drift cannot hide behind “enough writes happened.”

### Assistant - 2026-05-15 18:55:17

I tightened the repository privacy test so it now proves the exact write categories: full profile, theme patch, calibration, active-plan save plus inactive-plan update, workout doc plus sets plus tombstone, trophy append, insight full/tombstone, delivery, and engagement. I’m running that focused test immediately to catch any false assumptions.

### Assistant - 2026-05-15 18:56:30

The focused test is still running because xcodebuild rebuilt after the test patch. No failure has surfaced; I’m letting it finish cleanly.

### Assistant - 2026-05-15 18:56:52

The tightened assertion flushed out a real test-assumption problem: the focused test now fails, but xcodebuild’s tail didn’t include the assertion text. I’m pulling the failure details from the result bundle instead of guessing.

### Assistant - 2026-05-15 18:59:07

The failing tightened test found something useful, and it is in the test double rather than production Firestore code: the in-memory query filter compared `NSNumber(true)` from JSON serialization to Swift `true` by string, so active-plan queries missed existing active plans. That means the prior payload test accidentally skipped the inactive-plan update path. I’m fixing the test double so it behaves like Firestore for boolean filters, then the exact coverage assertion should pass.

### Assistant - 2026-05-15 19:00:48

The focused audit test now passes after fixing the in-memory Firestore boolean filter and making the write coverage exact. I’m moving to the full verification loop again: required workspace build, required full test suite, then the backend-mode compile checks and final scans before I write the RCA entry.

### Assistant - 2026-05-15 19:01:23

Required build passed after the audit patch. I’m running the full test suite now; this is the only xcodebuild test currently using `/tmp/VirtualTrainerDerivedData`.

### Assistant - 2026-05-15 19:02:35

The full suite is still running. The focused test already passed; I’m waiting on the full run to make sure the test-double fix didn’t disturb the older repository/sync tests.

### Assistant - 2026-05-15 19:02:51

Full tests passed: 392 passed, 0 failed. I’m re-running the two backend-mode compile checks as the final acceptance sweep: local with the ignored Firebase plist absent, then Firebase mode with the build setting override.

### Assistant - 2026-05-15 19:03:52

Both backend-mode build checks passed again. I’m appending a separate DL-058 audit RCA now: this will explicitly call out the missed inactive-plan update coverage, why the first pass didn’t catch it, and what guardrail now prevents a repeat.

### Assistant - 2026-05-15 19:04:33

The RCA is logged. I’m doing the final non-build hygiene now: toolchain path re-check, whitespace check, changed-file secret scan, and a protected-file diff check.

### Assistant - 2026-05-15 19:05:18

I audited the Phase 16H work end to end and found one real miss in the first implementation. It was not a production-path bug, but it was a test-coverage bug: the privacy test claimed to cover every repository write path, yet it only asserted a loose write count. Because the in-memory Firestore test double compared boolean filters by string, the active-plan deactivation update was skipped in the fixture while the test still passed.

I fixed that and logged the RCA as `DL-058` in [DEBUG_LOG.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/DEBUG_LOG.md:1791>).

**Audit Result**
- Firestore rules: present, owner-only, default-deny, raw-data/secret field denylist, Phase 16J TODO included: [firestore.rules](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/Documentation/firestore.rules:1>)
- Firebase checklist: present, including cross-uid denial smoke: [FirebaseConsoleChecklist.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/Documentation/FirebaseConsoleChecklist.md:27>)
- App Check rollout doc: present: [AppCheckRollout.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/Documentation/AppCheckRollout.md:5>)
- DEBUG-only App Check provider: installed before Firebase configure: [FirebaseBootstrap.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Services/FirebaseBootstrap.swift:42>)
- FirebaseAppCheck dependency: linked into the app target.
- Privacy tests: now assert exact write categories and payload shape, not just “some writes happened”: [FirestoreRepositoryTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/FirestoreRepositoryTests.swift:274>)
- Test double fix: boolean Firestore filters now behave type-faithfully for the active-plan path: [FirestoreRepositoryTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/FirestoreRepositoryTests.swift:1550>)
- Protected live camera pipeline files: untouched.

**Why The Miss Was Missed**
The first pass had a classic “green but not proven” weakness: it validated every captured payload, but did not prove every intended payload was captured. Context compaction and the lost stream made that easier to miss because the work resumed from a summary plus a green full-suite result instead of replaying the write trace category-by-category. The bad in-memory boolean comparison then quietly hid the inactive-plan update path.

**Verification**
- Required build: PASS
- Required test suite: PASS, `392` passed, `0` failed
- Focused repository privacy test: PASS
- `BackendMode.local` no-plist build: PASS
- `BackendMode.firebase` build-setting override: PASS
- `xcrun --find clang` and `xcrun --find swiftc`: both under XcodeDefault
- `git diff --check`: PASS
- `gitleaks`: unavailable here; fallback changed-file secret scan: PASS
- Protected pipeline diff check: PASS

No downstream app behavior was changed by the audit fix; it only strengthens tests and the in-memory Firestore test double. The app-facing Phase 16H behavior remains: Firebase mode is prepared for owner-only rules and DEBUG App Check testing, while local mode continues to build without a Firebase plist.
