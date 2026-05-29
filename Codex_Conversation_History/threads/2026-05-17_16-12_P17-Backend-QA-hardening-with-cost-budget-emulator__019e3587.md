# P17: Backend QA hardening (with cost budget + emulator)

- Thread ID: 019e3587-c662-7541-9030-9b96f63b7623
- Created: 2026-05-17 16:12:31 (Asia/Kolkata)
- Updated: 2026-05-17 16:53:55 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/17/rollout-2026-05-17T16-12-31-019e3587-c662-7541-9030-9b96f63b7623.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 9bcfb578e8c3d37f0c913f4c1633b5b6f93de2c7
- Exported visible messages: 32
- Extracted input images: 0

## Conversation

### User - 2026-05-17 16:13:04

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

Phase 17 goal: stress-test the backend integration for internal beta.

Tasks:

1. Documentation/BackendQAChecklist.md  (manual + automated)
   Cover at least:
   - Fresh install in local mode with no Firebase config present.
   - Fresh install in firebase mode, anonymous sign-in.
   - Offline onboarding; later online; profile syncs without duplicates.
   - Free Analysis save → sync.
   - Planned Workout save (multi-set) → sync → load on another simulator.
   - Workout delete locally → tombstone propagates → other device hides.
   - Trophy event sync; cross-device earliest-earnedAt wins.
   - Insight delivery/engagement sync; ranker stays consistent.
   - Data export in firebase mode includes remote-labeled docs.
   - Account deletion in firebase mode succeeds end-to-end.
   - Bad rules (mutate rules to deny once) → app stays in conflict state, no
     data loss.
   - App force-killed mid-sync → on relaunch, journal replays pending
     writes; no duplicates.
   - Active live workout: sync defers heavy work; live FPS unaffected.
   - Simulator SpringBoard crash differentiation (link to DL-035, DL-045).

2. Firebase Local Emulator Suite.
   - Add Documentation/FirebaseEmulatorSetup.md describing how to run the
     auth + Firestore emulators locally:
         firebase init emulators
         firebase emulators:start --only auth,firestore
   - Add a `--firebase-emulator` launch arg that points
     FirebaseBootstrap at the emulator hosts (localhost:9099 + localhost:8080).
   - Add `BackendIntegrationTests` (separate test target if needed) that:
     - Spin up the emulator before tests via a script invocation guard.
     - Anonymous sign-in.
     - Save profile → load profile → assert match.
     - Save workout (multi-set) → loadRecent → assert order.
     - Try a forbidden write → asserts denial.
     - Tombstone propagation.

3. Cost budget assertion.
   Add a soft budget for a typical user week:
   - 5 planned workouts × (1 profile read, 1 workout write, ~4 set writes,
     1 trophy event, ~2 insight writes, ~4 delivery merges, ~2 engagement
     merges) ≈ 80 writes/week × 4 weeks = ~320 writes/month per active user.
   - Add a debug-only "Cost Snapshot" toggle in the Backend section that
     logs cumulative Firestore reads/writes for the current session.
   - Document the cost budget in Documentation/FirebaseCostBudget.md.

4. Sync diagnostics screen (DEBUG only).
   - backendMode, activeAccountId (redacted), lastSyncedAt, pendingUpload
     count, conflict count, listenersAttached, lastError (sanitized),
     firebaseBootstrapState, write journal entry count, latest 10 write
     journal entries (kind + age).

5. Listener backpressure.
   - Debounce all remote update streams.
   - Never run heavy sync while WorkoutSessionContext.isLive.
   - Queue large writes until workout ends.

6. Data volume tests.
   - 100 workouts: profile + history loads stay snappy.
   - 500 workouts: heatmap and history view stay responsive.
   - Largest workout (32 set docs): detail view loads in < 1.5s.

7. Privacy tests.
   - Repository writes never contain forbidden keys (already in 16C/16H,
     extend to cover the FULL sync path).
   - Analytics never contains PII.
   - Export only contains expected data.

Acceptance:
- Internal beta sync checklist documented.
- High-risk sync bugs are tested or tracked.
- Cost budget articulated.
- Firebase mode is safe for ~10 internal testers.

### Assistant - 2026-05-17 16:13:15

I’ll start with the requested pre-flight: branch/status, toolchain paths, recent history, and the documentation/code map. Then I’ll make the smallest backend-facing changes that fit the existing architecture rather than reshaping the live analysis stack.

### Assistant - 2026-05-17 16:13:26

Pre-flight is clean so far: branch is `main`, there are no local changes, and both `clang` and `swiftc` resolve to XcodeDefault.xctoolchain. I’m reading the repo docs next, including the DEBUG_LOG references the prompt calls out.

### Assistant - 2026-05-17 16:14:04

The docs confirm the current boundary: local mode is the default and must remain no-plist safe; Firebase is already partial and guarded by Remote Config; the next debug-log entry would be `DL-065`. I’m moving into the backend/sync Swift now, especially repository protocols, Firebase adapters, sync orchestration, stores, and the Profile debug UI.

### Assistant - 2026-05-17 16:15:45

A practical shape is emerging: the app already has most sync surfaces, so the phase should harden and expose them rather than invent a new backend layer. I’ll add emulator plumbing, cost/diagnostic instrumentation, docs/checklists, and focused tests around the existing repositories and guards.

### Assistant - 2026-05-17 16:19:19

I’ve finished the repo sweep and preflight checks. The tree is clean on `main`, the Xcode toolchain resolves to `XcodeDefault.xctoolchain`, and I’ve mapped the backend stack so the changes can stay around it instead of disturbing the live camera path.

### Assistant - 2026-05-17 16:19:28

I found the backend is already structured around small repository protocols and an orchestrator, which is useful here: I can add emulator/cost/diagnostics hooks at the Firebase boundary and debug settings surface without touching the camera-analysis classes. The only behavioral spot that needs care is workout history: it can currently try a remote write as soon as a summary is saved, so I’m going to gate that during live sessions and let the existing journal replay it afterward.

### Assistant - 2026-05-17 16:20:33

I’m about to make the first scoped edits: Firebase bootstrap gets an emulator launch-arg hook, Firestore gets a DEBUG cost counter at the SDK adapter boundary, and workout history will leave remote saves pending while a live workout is active. After that I’ll add the docs/tests around those behaviors.

### Assistant - 2026-05-17 16:22:33

The core code hooks are in place now. I’m shifting to the safety net: docs, emulator script, and targeted tests that keep normal local runs deterministic while making emulator-backed integration runnable on demand.

### Assistant - 2026-05-17 16:30:28

The documentation and tests are now drafted. I’ve also corrected the README’s backend-readiness wording because the code already has workout Firestore repositories, so saying workouts were still local-only would mislead the beta QA path. Next I’m doing a compile-oriented pass before the required full build/test.

### Assistant - 2026-05-17 16:30:38

I’ve hit the point where the code review pass won’t tell us more than the compiler will. I’m starting the required workspace build on the requested simulator and DerivedData path now.

### Assistant - 2026-05-17 16:31:16

Build passed on the requested workspace/simulator path. I’m starting the required full test run now, using the same DerivedData path and no parallel test invocation.

### Assistant - 2026-05-17 16:33:03

The full suite compiled and ran, but one new documentation assertion was too literal about heading capitalization, not behavior. I’m tightening that test to match the actual checklist text, then I’ll rerun the required test command.

### Assistant - 2026-05-17 16:34:48

The rerun is clean: 423 passed, 0 failed, 4 skipped, with the four skips being the opt-in emulator integration tests. Toolchain paths still point at `XcodeDefault.xctoolchain`, and `git diff --check` is clean. I’m doing the secret-scan preflight now; if `gitleaks` is still unavailable I’ll run the repo’s fallback pattern scan over changed/untracked files.

### Assistant - 2026-05-17 16:36:39

One extra sanity check is worth doing here because local/no-plist mode is a hard constraint. I’m temporarily moving only the local Firebase client plist out of the workspace, running a build on a separate DerivedData path, and restoring it with a shell trap.

### Assistant - 2026-05-17 16:38:09

Implemented Phase 17 backend beta hardening on `main` after clean preflight. I kept the live camera pipeline untouched.

Key changes:
- Added emulator bootstrap via `--firebase-emulator` in [FirebaseBootstrap.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/FirebaseBootstrap.swift:21).
- Added DEBUG Firestore cost tracking in [FirestoreCostTracker.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Repositories/Firebase/FirestoreCostTracker.swift:1) and SDK adapter read/write counting.
- Added DEBUG sync diagnostics plus Cost Snapshot in [ProfileView.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/UI/ProfileView.swift:2279).
- Queued workout remote save/delete while a live workout is active in [WorkoutHistoryStore.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Models/WorkoutHistoryStore.swift:448).
- Added beta QA, emulator, and cost docs:
  [BackendQAChecklist.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/BackendQAChecklist.md),
  [FirebaseEmulatorSetup.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/FirebaseEmulatorSetup.md),
  [FirebaseCostBudget.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/FirebaseCostBudget.md).
- Added opt-in emulator/data volume/privacy tests and updated DEBUG_LOG with `DL-065`.

Before/after in practice:
- Before: an internal tester saving a workout while a live session was still active could trigger remote write work right on the workout path.
- After: that write stays pending during the live workout and replays after the session ends, so live FPS/form feedback gets priority.
- Before: Firebase beta QA was scattered.
- After: a tester can run the emulator, sign in anonymously, save multi-set workouts, verify tombstones, inspect journal state, and watch read/write counts from the debug backend panel.

Verification:
- Toolchain: `clang` and `swiftc` both resolved under `XcodeDefault.xctoolchain`.
- Required build: PASS.
- Required test: PASS, `423 passed / 0 failed / 4 skipped` (`BackendIntegrationTests` are emulator opt-in).
- No-plist local build: PASS.
- `git diff --check`: PASS.
- `gitleaks` unavailable locally; fallback changed-file secret scan found no candidate secrets.

Firebase/manual steps:
- Run `firebase init emulators`, then `firebase emulators:start --only auth,firestore`.
- Add `--firebase-emulator` for emulator launches.
- Keep Anonymous Auth enabled and Firestore rules deployed for Firebase beta.
- Do not enforce App Check until physical-device App Attest validation is complete.

Migration behavior:
- No local JSON migration required.
- Codable compatibility paths were preserved.
- Existing pending write journal semantics stay intact; live-session workout writes now remain pending longer by design.

Manual testing plan:
1. Fresh install with no plist: complete onboarding, Free Analysis, Planned Workout, trophies, heatmap, recaps, export.
2. Firebase fresh install: anonymous sign-in, profile save/load, remote pull on second simulator.
3. Offline onboarding: go online later, sync profile once, verify no duplicate profile docs.
4. Free Analysis save: push, inspect compact workout doc and no forbidden raw payloads.
5. Planned multi-set save: sync, load detail on another simulator, verify set order.
6. Delete workout on one simulator: push tombstone, pull on another, verify hidden history.
7. Trophy duplicate event: verify earliest `earnedAt` wins.
8. Insight delivery/engagement: merge impressions/helpful across devices.
9. Bad rules once: deny a write, confirm conflict/pending state and no data loss.
10. Force-kill mid-sync: relaunch, replay journal, confirm no duplicates.
11. Active workout sync traffic: verify live session remains smooth and writes drain afterward.
12. Firebase export and account deletion: verify remote-labeled docs and local wipe.

Known follow-ups:
- Run the opt-in emulator integration tests in CI or locally with Firebase CLI installed.
- Manually execute bad-rules and force-kill scenarios before inviting testers.
- Finish production recursive account cleanup via Cloud Functions.

### User - 2026-05-17 16:38:10

Lot of changes done above which included a context compaction in the middle and lost stream too. 1500+ lines of code were written - that's a lot. Can you go through the original prompt, code changes done in extreme detail, audit them, ensure all the required changes were done and done correctly with no downstream impact. the code before this works fine with it. all the services that needed to be changed have been changed and nothing is left or missed. be very thorough in your analysis and evaluation. use highest level of reasoning available. Log the rca in the debug log and explain why the misses were missed. use highest level of thinking possible and think deeply. Evaluate and understand very deeply. Be very thorough and detailed. Have high attention to detail

### Assistant - 2026-05-17 16:38:41

I’ll treat this as a post-compaction safety audit, not a rubber stamp. I’m going to re-read the Phase 17 prompt against the actual diff, inspect each changed/new file, look for missed requirements and downstream risks, then patch only what the audit proves is necessary and log the RCA in `DEBUG_LOG.md`.

### Assistant - 2026-05-17 16:39:31

The first pass already found two audit-level gaps worth fixing, not just explaining: the README now contradicts itself about workout history sync, and emulator integration can be made more reliable by supporting an environment opt-in plus a script that actually starts emulators before running the test target. I’m continuing the deep inspection before editing so the patch is comprehensive.

### Assistant - 2026-05-17 16:41:06

I’m going to treat this like a real post-incident audit: first verify the actual diff against the Phase 17 requirements, then patch anything that is substantively incomplete, then rerun the required build/test path. I already have the prior context summary, so I’m continuing from the existing dirty tree rather than restarting blindly.

### Assistant - 2026-05-17 16:41:25

The first pass confirms the protected camera/live-analysis files are still outside the diff, and the remote observer streams look debounced. I did find a few audit-worthy gaps already: one README contradiction, emulator test startup being more documented than executable, and the “DEBUG-only” cost counter existing in release code paths.

### Assistant - 2026-05-17 16:43:30

I’m going to make a small corrective patch now. The aim is not to expand Phase 17; it’s to tighten the parts where the implementation was fuzzier than the prompt: executable emulator test setup, sharper denial assertions, DEBUG-only cost accounting, and the README wording that contradicted the new workout sync path.

### Assistant - 2026-05-17 16:45:12

The corrective patch is in. I also tightened transaction cost accounting so it records the logical operations after a transaction succeeds instead of firing detached counter updates from inside the Firestore transaction closure. Next I’m compiling; if Swift’s concurrency checker dislikes that shape, I’ll adjust before moving on.

### Assistant - 2026-05-17 16:45:41

Build passed cleanly with the required workspace, simulator, DerivedData path, and XcodeDefault toolchain. I’m running the full required test suite now; I’ll parse the `.xcresult` after it finishes so the pass/fail/skip counts are concrete rather than eyeballed.

### Assistant - 2026-05-17 16:46:51

The full suite is still running. So far the compile phase has completed and the simulator test process is underway; no failure output yet.

### Assistant - 2026-05-17 16:47:26

The full suite found one documentation-test assertion problem, not a product failure: the test looked for the literal string `Scripts/start_firebase_emulators.sh`, while the runner correctly calls it through `$SCRIPT_DIR/start_firebase_emulators.sh`. I’m tightening that assertion and then I’ll rerun.

### Assistant - 2026-05-17 16:48:55

The focused Phase 17 hardening tests now pass. I’m rerunning the full required suite once more so the final verification reflects the corrected tree, not the earlier one-failure run.

### Assistant - 2026-05-17 16:50:02

Full suite rerun is still in progress. No new failure output has appeared; the simulator is in the test execution phase now.

### Assistant - 2026-05-17 16:50:38

The corrected full suite passed: the `.xcresult` reports 428 total tests, 4 skipped emulator-gated tests, so 424 passed and 0 failed. I’m now rechecking the no-plist local-mode build because that is the easy place for Firebase work to accidentally bite later.

### Assistant - 2026-05-17 16:51:29

Whitespace check passed, and the protected live camera pipeline diff is empty. `gitleaks` itself is not installed in this environment, so I’m doing the same conservative fallback scan over changed and untracked files with filename-only output to avoid exposing any secret-like contents.

### Assistant - 2026-05-17 16:51:59

The no-plist build passed and printed the expected local-only warning, and the Firebase client plist was restored afterward. I’m appending the RCA entry now with the specific misses: README contradiction, emulator runner gap, weak denial assertion, DEBUG-only cost accounting leakage, and the brittle audit test assertion that the rerun caught.

### Assistant - 2026-05-17 16:53:55

I did the deep audit and corrected the real misses I found. The tree is still on `main` with Phase 17 changes unstaged/uncommitted; protected live camera pipeline files remain untouched.

**Audit Result**
Found and fixed 5 concrete gaps:

- README contradicted the new compact workout sync path. Fixed wording so it now says workouts sync, while heatmaps/recaps/live analysis remain local/client-side.
- Emulator integration had docs and a startup script, but no single executable runner that starts emulators and opts tests in. Added [Scripts/run_backend_integration_tests.sh](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Scripts/run_backend_integration_tests.sh:1).
- `--firebase-emulator` worked, but command-line XCTest needed a safer env opt-in. Added `SPOTTER_FIREBASE_EMULATOR=1` support in [FirebaseBootstrap.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/FirebaseBootstrap.swift:96).
- Forbidden-write integration test accepted any error. It now asserts Firestore `permissionDenied`.
- Cost Snapshot was DEBUG UI/logging, but counters still mutated in release. Fixed in [FirestoreCostTracker.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Repositories/Firebase/FirestoreCostTracker.swift:20), and tightened transaction counting in [FirestoreDocumentDatabase.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Repositories/Firebase/FirestoreDocumentDatabase.swift:182).

I also logged the RCA in [DEBUG_LOG.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/DEBUG_LOG.md:2161). The miss pattern was: after compaction, the first pass treated “covered by docs/tests/build” as enough, instead of re-running each original bullet through the exact operator workflow.

**Verification**
- Toolchain: `clang` and `swiftc` both resolve under `XcodeDefault.xctoolchain`.
- Required build: PASS.
- Required full test suite: PASS.
  - Passed: 424
  - Failed: 0
  - Skipped: 4, all `BackendIntegrationTests` gated behind emulator opt-in.
- No-plist local build: PASS, printed expected local-only warning, plist restored.
- `git diff --check`: PASS.
- `gitleaks`: unavailable locally; fallback changed-file secret scan passed.
- Protected camera/live analysis diff: empty for all listed protected files.

**App Behavior Before/After**
Before: Firebase mode had partial sync, but beta operators still had to piece together emulator startup and test opt-ins. A rules-denial test could pass for the wrong reason, and README wording implied workouts were still local-only.

After: a developer can run one backend integration command, compact workout history can sync across simulators, live workouts defer heavy sync, and the debug Backend section can show sync state plus a DEBUG-only read/write cost snapshot. Real example: a planned 4-set workout saved on simulator A can sync and load on simulator B, while the live rep counter/FPS path remains undisturbed.

**Manual Test Plan**
1. Fresh local install with no `GoogleService-Info.plist`: onboarding, Free Analysis save, Planned Workout save, trophies, stats, heatmap, recaps, insights.
2. Firebase emulator install: run `firebase init emulators`, then `Scripts/run_backend_integration_tests.sh`.
3. Offline onboarding, then online anonymous sign-in: confirm one profile doc, no duplicates.
4. Free Analysis save -> push -> pull on second simulator.
5. Planned multi-set workout -> sync -> detail loads sorted sets on second simulator.
6. Delete workout on simulator B -> push tombstone -> simulator A hides it.
7. Trophy duplicate earn on two devices -> earliest `earnedAt` wins.
8. Insight delivery/helpful engagement on separate devices -> merge remains stable.
9. Export in Firebase mode -> confirm `*.remote.json` files and no raw sensor/face/secret data.
10. Account deletion -> listeners stop, local wipe succeeds, auth deletion path completes or returns documented cloud-cleanup notice.
11. Bad rules once -> app shows sanitized error/conflict, local data remains pending, retry after restore creates no duplicates.
12. Force-kill mid-sync -> relaunch, journal replays pending operation IDs once.
13. Active workout -> trigger remote traffic/save while live; heavy sync stays deferred until workout ends.
14. Volume checks: 100 workouts history/profile, 500 heatmap/history, 32-set detail under target.
15. Simulator crash triage: classify SpringBoard/toolchain issues against DL-035/DL-045, not as app regressions.

Known follow-up: Firebase CLI is not installed in this environment, so I could not execute the emulator runner end-to-end here; the normal suite correctly skips those 4 tests until `SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1` and emulator opt-in are supplied.
