# P16A: Audit repo and build flow

- Thread ID: 019e2522-8089-7640-909a-ff5ec77eb1ae
- Created: 2026-05-14 11:47:58 (Asia/Kolkata)
- Updated: 2026-05-14 12:18:43 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/14/rollout-2026-05-14T11-47-58-019e2522-8089-7640-909a-ff5ec77eb1ae.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 7fe115b21e4e52a737258e0ed110319e9670ae02
- Exported visible messages: 29
- Extracted input images: 0

## Conversation

### User - 2026-05-14 11:48:08

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

Phase 16A goal: add a runtime backend mode switch and a published backend status
so the rest of Phase 16 can light up Firebase incrementally without breaking
local mode.

Do NOT: implement Firestore repositories; implement FirebaseAuthRepository;
write any Firestore documents.

Tasks:

1. Create VirtualTrainer/Repositories/BackendConfiguration.swift.

   nonisolated struct BackendConfiguration {
       static let userDefaultsKey = "spotter.backendMode"

       /// Reads the desired mode from build settings and DEBUG-only
       /// UserDefaults override. Release builds always return .local until
       /// Phase 19 promotes the production switch.
       static func desiredMode(
           bundle: Bundle = .main,
           userDefaults: UserDefaults = .standard
       ) -> BackendMode {
           #if DEBUG
           if let raw = userDefaults.string(forKey: userDefaultsKey),
              let mode = BackendMode(rawValue: raw) {
               return mode
           }
           #endif
           // Read SPOTTER_BACKEND_MODE from Info.plist (set via xcconfig).
           if let raw = bundle.object(forInfoDictionaryKey: "SPOTTER_BACKEND_MODE") as? String,
              let mode = BackendMode(rawValue: raw) {
               return mode
           }
           return .local
       }

       #if DEBUG
       static func setDesiredMode(_ mode: BackendMode,
                                  userDefaults: UserDefaults = .standard) {
           userDefaults.set(mode.rawValue, forKey: userDefaultsKey)
       }
       #endif
   }

   Wire SPOTTER_BACKEND_MODE through Info.plist via xcconfig:
   - Add SPOTTER_BACKEND_MODE = $(SPOTTER_BACKEND_MODE) to the build settings
     pulled into Info.plist by adding a key in Info.plist that resolves the
     build setting.
   - Keep Debug/Beta/Release defaulting to `local`.

2. Create VirtualTrainer/Repositories/BackendStatusStore.swift.

   @MainActor
   final class BackendStatusStore: ObservableObject {
       @Published private(set) var desiredBackendMode: BackendMode
       @Published private(set) var activeBackendMode: BackendMode
       @Published private(set) var firebaseBootstrapState: FirebaseBootstrapState
       @Published private(set) var userFacingMessage: String?

       init() {
           let desired = BackendConfiguration.desiredMode()
           desiredBackendMode = desired
           if desired == .firebase {
               firebaseBootstrapState = FirebaseBootstrap.configureIfAvailable()
           } else {
               firebaseBootstrapState = .notAttempted
           }
           activeBackendMode = (firebaseBootstrapState == .configured ||
                                firebaseBootstrapState == .alreadyConfigured)
                                ? desired : .local
           userFacingMessage = Self.message(for: firebaseBootstrapState,
                                            desired: desired,
                                            active: activeBackendMode)
       }

       #if DEBUG
       func setDesiredMode(_ mode: BackendMode) {
           BackendConfiguration.setDesiredMode(mode)
           // Re-evaluate; if mode changes require restart, surface that in
           // userFacingMessage rather than mutating Firebase live.
       }
       #endif

       private static func message(...) -> String? { ... }
   }

3. Update VirtualTrainerApp:
   - Replace the unconditional FirebaseBootstrap.configureIfNeeded() call from
     init() with construction of BackendStatusStore.
   - Inject BackendStatusStore into the environment.
   - Only run FirebaseSmokeVerifier.runIfRequested() if
     statusStore.activeBackendMode == .firebase.

4. Create AppDependencies.from(_ statusStore:) factory.
   - .local mode returns AppDependencies.local().
   - .firebase mode also returns AppDependencies.local() for now, with one
     exception: tag the dependencies with an internal `mode` field so Phase 16B
     can override Auth specifically. Or expose a builder for partial-firebase
     dependencies. Decide and document.

5. Debug UI.
   In ProfileView's SettingsDebugSection, add a new collapsible "Backend"
   section visible only when #if DEBUG:
   - Show desired mode (local/firebase)
   - Show active mode
   - Show firebaseBootstrapState
   - Show currentAccountId (redacted: first 6 chars + "…")
   - Picker to switch desired mode
   - "Restart required" warning if changing the mode mid-session needs a fresh
     launch (it does; do not try to re-init Firebase live)
   - Button: "Run Firebase Smoke Test (DEBUG)" — invokes
     FirebaseSmokeVerifier.run() and shows result inline.

6. Tests.
   - `BackendConfigurationTests`: default .local; reading from a stub Info.plist
     with SPOTTER_BACKEND_MODE=firebase returns .firebase; UserDefaults override
     wins in DEBUG.
   - `BackendStatusStoreTests`: starting with desired=.firebase but missing
     plist yields active=.local and a non-nil userFacingMessage.
   - Local-only build path still passes existing tests.

Acceptance criteria:
- Build succeeds with mode=local and no plist.
- Build succeeds with mode=firebase and plist present (it bootstraps).
- Build succeeds with mode=firebase and plist absent (it falls back to local
  with a banner string).
- Tests pass.
- A new DL entry summarizes the change.

### Assistant - 2026-05-14 11:48:32

I’ll start with the repository pre-flight and source survey you asked for, keeping plist contents and anything secret-like out of terminal output. Once I know the current branch, tree state, and existing architecture, I’ll make the smallest Phase 16A changes that fit the app’s current shape.

### Assistant - 2026-05-14 11:48:51

Pre-flight found the Xcode toolchain exactly where required, and the current branch is `main`. One important snag: `git status --short` is not clean, including uncommitted changes in Firebase/bootstrap-adjacent files that Phase 16A would touch, so I’m going to inspect those diffs before any edits and preserve them rather than assume they are mine.

### Assistant - 2026-05-14 11:49:11

The uncommitted diff is actually directly relevant: it already introduces safe Firebase bootstrap states and makes the plist optional. I’ll treat that as existing user work, keep it intact, and build Phase 16A on top of it only after the requested documentation/code survey is complete.

### Assistant - 2026-05-14 11:50:07

The docs confirm the important constraints for this phase: local-first remains the default, Firebase work is feature-gated, normal product reads should keep hiding tombstones, and the live camera stack stays shared between Free Analysis and Planned Workouts. I’m now tracing the actual dependency injection and debug UI wiring so the backend switch lands in the app shell rather than in the camera/session code.

### Assistant - 2026-05-14 11:52:01

The Xcode project is using file-system-synchronized groups, so new Swift files under `VirtualTrainer/` and `VirtualTrainerTests/` should be picked up without hand-adding PBX source entries. One thing I noticed from the app target settings: generated Info.plist keys are coming from `INFOPLIST_KEY_*`, so the backend mode belongs there in the app target build settings, fed by the existing xcconfigs.

### Assistant - 2026-05-14 11:52:27

I’ve also checked the protected live analysis pieces enough to confirm Phase 16A doesn’t need to touch them. Next I’m doing the secret-scan pre-flight, then I’ll edit only the app-shell/repository/debug-status surface.

### Assistant - 2026-05-14 11:52:49

`gitleaks` isn’t installed on this machine, so I’ll use the repo’s configured patterns as a fallback and report only file/line metadata with matched values redacted. That keeps the scan useful without splashing credentials into logs.

### Assistant - 2026-05-14 11:55:29

I’m going to add the backend status/configuration layer now. The key implementation choice is to use the existing `AppDependencies.backendMode` as the Phase 16A tag while keeping every repository implementation local until the auth-specific Firebase override arrives in the next phase.

### Assistant - 2026-05-14 11:59:13

The first slice is in place: configuration reads Debug overrides/build settings, launch status decides whether Firebase is active, and the app only honors the smoke-test launch gate when Firebase actually bootstrapped. I’m adding tests for those launch decisions now, including the missing-plist fallback.

### Assistant - 2026-05-14 12:00:42

The code and focused tests are now in place. I’m going into verification sequentially with the required workspace and DerivedData path, starting with build before the full test run.

### Assistant - 2026-05-14 12:01:17

Build caught a Swift initialization ordering bug in the new status store: I assigned `firebaseBootstrapState` and then read it before `activeBackendMode` had been initialized. I’m fixing that with locals so initialization stays clean, then I’ll rerun the build.

### Assistant - 2026-05-14 12:01:58

The required build now passes after the status-store initialization fix. It did find an ignored local Firebase client config and copied it into the simulator app bundle, but no plist contents or key values were printed. Next is the full test run, same workspace and DerivedData path, sequentially.

### Assistant - 2026-05-14 12:03:52

The full suite is still running, with no second `xcodebuild` started against that DerivedData path. I’m letting it finish rather than poking the build system sideways.

### Assistant - 2026-05-14 12:04:22

Two new tests failed; the rest of the suite kept moving cleanly. I’m narrowing those failures now rather than touching unrelated app code.

### Assistant - 2026-05-14 12:06:48

I’ve got the context from the prior work and I’m picking up at the test failure. First I’m going to collect the focused test output that was already running, then I’ll patch the narrow cause rather than disturbing the app pipeline.

### Assistant - 2026-05-14 12:06:58

The focused run confirms the same two failures, but the terse xcodebuild tail doesn’t include assertions. I’m going into the `.xcresult` now and also reading the two test files so the next edit is surgical.

### Assistant - 2026-05-14 12:08:37

The crash is happening at test teardown, not in the assertions: Swift is aborting while deallocating main-actor observable/local repository objects in synchronous XCTest methods. I’m going to make these two tests use the async XCTest path and isolate the status-store test from global Firebase state, which matches the intended behavior without touching production code.

### Assistant - 2026-05-14 12:08:44

That patch only changes the test harness shape and makes the missing-config scenario explicit. I’m rerunning just those two tests first so we can see whether the teardown crash is gone before spending another full suite run.

### Assistant - 2026-05-14 12:10:24

Focused tests are green now. I’m going back through the required verification sequence from the top: exact workspace build, then exact full test run, both serially against the same DerivedData path.

### Assistant - 2026-05-14 12:11:05

Build is green. I’m starting the full suite now; after that I’ll run the cleanup checks and write the debug-log entry with the real verification results.

### Assistant - 2026-05-14 12:11:43

The full test command is past build/signing and into the simulator run. No new failures yet; I’m letting it finish rather than starting any overlapping Xcode work.

### Assistant - 2026-05-14 12:12:35

Full suite passed. I’m collecting the exact pass/fail counts from the saved log now, then I’ll run whitespace and secret checks before touching `DEBUG_LOG.md`.

### Assistant - 2026-05-14 12:12:54

`git diff --check` is clean. Xcode did touch the per-user scheme-management plist during verification, which is not part of this phase; I’m checking that diff and will remove only that generated noise if it’s ours.

### Assistant - 2026-05-14 12:13:45

Secret scan passed using the repo’s `.gitleaks.toml` patterns over changed non-ignored files; `gitleaks` itself is still not installed here. I’m reading the current debug-log header/last entry, then I’ll add the Phase 16A entry in the existing format.

### Assistant - 2026-05-14 12:14:24

The required build/test is already green: build succeeded and the suite reports 344 passed, 0 failed. I’m also exercising the two backend-mode build variants now, serially: Firebase mode with the local ignored client config present, then Firebase mode with that config temporarily absent and restored by a shell trap.

### Assistant - 2026-05-14 12:15:45

The absent-plist build is using a fresh DerivedData path so there’s no stale bundled plist from the previous build. It’s a cold package build, so it’s noisier and slower, but the repo secret file is held outside the repo and will be restored automatically when this command exits.

### Assistant - 2026-05-14 12:17:40

The new DL-048 entry is appended and the header now points to DL-049. I’m doing the final whitespace and secret checks after that log edit, then I’ll collect the final changed-file summary.

### Assistant - 2026-05-14 12:18:43

Implemented Phase 16A.

Pre-flight note: `git status` was already dirty on `main` before I started, including prior Firebase bootstrap/doc work, so I preserved those changes and layered this phase on top.

**What changed**
- Added runtime backend selection in [BackendConfiguration.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Repositories/BackendConfiguration.swift:3) and published status in [BackendStatusStore.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Repositories/BackendStatusStore.swift:4).
- Wired `SPOTTER_BACKEND_MODE` into generated Info.plist build settings.
- Updated app launch to create/inject `BackendStatusStore`, and only check Firebase smoke-test gating when Firebase is active.
- Added `AppDependencies.from(_:)`; decision: Phase 16A keeps Firebase mode on local repositories but tags dependencies with `.firebase` so Phase 16B can override Auth cleanly.
- Added DEBUG Profile backend UI with desired/active modes, bootstrap state, redacted account ID, restart warning, and inline smoke-test result.
- Added backend config/status tests and updated audits. No live camera pipeline files were edited.

**Before / After**
Before: requesting Firebase mode with a missing plist had no shared app status, so later Firebase work could accidentally blur local and remote behavior.

After: a developer can switch desired mode to Firebase in DEBUG, restart, and see “desired=firebase / active=local / missing config” while Free Analysis and Planned Workouts still save locally. With a valid plist, active mode can become Firebase, but repositories still remain local for this phase.

**Verification**
- Toolchain verified under `XcodeDefault.xctoolchain` for `clang` and `swiftc`.
- Required build: PASS.
- Required test suite: PASS, 344 passed / 0 failed.
- Extra Firebase-mode build with plist present: PASS.
- Extra Firebase-mode build with plist absent on fresh DerivedData: PASS, local-only fallback.
- `git diff --check`: PASS.
- `gitleaks` not installed; fallback scan using `.gitleaks.toml` patterns over changed non-ignored files: PASS.

**PR Notes**
Firebase/manual steps: keep the real `GoogleService-Info.plist` ignored, set `SPOTTER_BACKEND_MODE=firebase` or use the DEBUG picker, restart, then run the DEBUG smoke test. No `FirebaseAuthRepository`, Firestore repositories, or Firestore writes were added.

Migration behavior: no local JSON schema changes, so existing local files remain backward compatible.

Known follow-ups: Phase 16B should introduce Auth override through the new dependency tag/factory; Firestore repositories remain later work. Existing simulator Firestore TLS issue from DL-046 remains an environment follow-up.
