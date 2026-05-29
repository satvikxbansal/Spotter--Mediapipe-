# P16.0: Inspect iOS repo before changes

- Thread ID: 019e2512-57e8-7a91-9d2b-a7dcccc82ced
- Created: 2026-05-14 11:30:19 (Asia/Kolkata)
- Updated: 2026-05-14 11:47:38 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/14/rollout-2026-05-14T11-30-19-019e2512-57e8-7a91-9d2b-a7dcccc82ced.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 7fe115b21e4e52a737258e0ed110319e9670ae02
- Exported visible messages: 13
- Extracted input images: 0

## Conversation

### User - 2026-05-14 11:31:03

You are working in the Spotter iOS Swift repository.

Before changing code:
1. Inspect the current tree end-to-end. Read README.md, DEBUG_LOG.md, every file in
   Documentation/, the relevant Swift files in VirtualTrainer/, and the most recent
   git history (`git log --oneline -20`).
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
17. Git pre-flight: confirm `git status` is clean before starting. Confirm the
    branch you intend to target. After commits, run `git diff --check` to catch
    whitespace errors.
18. Secret pre-flight: run any available secret scan (the repo ships
    .gitleaks.toml). Fail the phase if real secrets would be committed. 
19. Mention the change the code brings to the application - the before and after with real life practical examples if possible. 



Phase 16.0 goal: harden Firebase resource handling so the app builds and runs
without GoogleService-Info.plist present, and so environment-scoped plist files
are honored.

Do NOT in this phase: change FirebaseApp.configure semantics beyond a guarded
return; add Firestore writes; add AppCheck; add Analytics; add Crashlytics;
add Remote Config; change any product UI; touch the live camera pipeline.

Inspect first:
- VirtualTrainer.xcodeproj/project.pbxproj — find every reference to
  GoogleService-Info.plist
- VirtualTrainer/VirtualTrainerApp.swift — note the unconditional
  FirebaseBootstrap.configureIfNeeded() call in init()
- VirtualTrainer/Services/FirebaseBootstrap.swift — note the assertionFailure
  on missing plist
- VirtualTrainer/Services/FirebaseSmokeVerifier.swift — this is fine, keep it
- Configurations/Debug.xcconfig, Beta.xcconfig, Release.xcconfig — note
  GOOGLE_SERVICE_INFO_PLIST is defined but not consumed by Xcode
- .gitignore — confirm GoogleService-Info*.plist is ignored
- Documentation/SECRETS.md
- DEBUG_LOG.md entry DL-045

Tasks:

1. Project resource refactor.
   Remove the direct PBXBuildFile / PBXFileReference for GoogleService-Info.plist
   from the app target's Resources phase. Replace with a Run Script build phase
   named "Copy Firebase Client Config If Present" placed BEFORE the "Copy Bundle
   Resources" phase. The script body:

       set -e
       PLIST_NAME="${GOOGLE_SERVICE_INFO_PLIST:-GoogleService-Info.plist}"
       CANDIDATES=(
           "${SRCROOT}/${PLIST_NAME}"
           "${SRCROOT}/${PLIST_NAME%.plist}-Dev.plist"
           "${SRCROOT}/GoogleService-Info.plist"
       )
       FOUND_PATH=""
       for path in "${CANDIDATES[@]}"; do
           if [ -f "$path" ]; then
               FOUND_PATH="$path"
               break
           fi
       done
       DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
       if [ -n "$FOUND_PATH" ]; then
           install -m 0644 "$FOUND_PATH" "$DEST"
           echo "warning: Copied Firebase client config from $FOUND_PATH"
       else
           echo "warning: No Firebase client config found; building in local-only mode."
       fi

   The script must NOT fail the build when the plist is missing. Mark the phase
   "Based on dependency analysis" off so it always runs.

2. Make FirebaseBootstrap safe-by-default.
   Replace `assertionFailure(...)` in FirebaseBootstrap with a graceful return
   path. The function should never crash on missing config. Expand the return
   type from Bool to:

       enum FirebaseBootstrapState: Equatable {
           case notAttempted
           case configured
           case missingConfig
           case alreadyConfigured
           case failed(reason: String)   // reason must be sanitized — no plist
                                          // contents, no API keys
       }
       static func configureIfAvailable() -> FirebaseBootstrapState

   Behavior:
   - If FirebaseApp.app() != nil → .alreadyConfigured.
   - If Bundle.main has no GoogleService-Info.plist → .missingConfig.
   - Else attempt FirebaseApp.configure(options:) inside a do/catch; on success
     check FirebaseApp.app() != nil and return .configured; on any thrown error
     return .failed(reason: sanitized).
   - Sanitize: the reason string must not contain the plist path or any value
     that looks like an API key, GoogleAppID, or project ID.
   - The function is idempotent (safe to call multiple times).

3. Remove the unconditional call from VirtualTrainerApp.init().
   Keep the @main intact. Move the bootstrap call to a new code path that is
   only invoked when the desired BackendMode == .firebase, which we add in
   Phase 16A. In this phase, simply make init() a no-op for Firebase bootstrap.
   FirebaseSmokeVerifier.runIfRequested() can remain only inside #if DEBUG, but
   move it after the bootstrap call when 16A wires the mode switch. For this
   phase, gate it: only run the smoke verifier when the launch arg is present
   AND FirebaseBootstrap.configureIfAvailable() returns .configured or
   .alreadyConfigured.

4. .gitignore audit.
   Verify these entries exist (they do today; do not duplicate):
       GoogleService-Info*.plist
       !GoogleService-Info.example.plist
       Configurations/LocalSecrets.xcconfig
       *.local.xcconfig
       *ServiceAccount*.json
       *service-account*.json
       *.p8
       *.pem
       *.key
   Add a committed `GoogleService-Info.example.plist` template (with placeholder
   values like `YOUR_GOOGLE_APP_ID`) so a fresh contributor knows the shape.

5. Documentation/DEVELOPMENT_SETUP.md
   Create this file. Content must cover:
   - Bundled Xcode toolchain is required; standalone Swift 6.2 crashes inside
     gRPC binary stub injection (cite DEBUG_LOG entry DL-045).
   - Use VirtualTrainer.xcworkspace, not the bare xcodeproj.
   - First-clone setup:
       pod install
       ./download_models.sh
       (optional) Copy your dev GoogleService-Info-Dev.plist to repo root.
   - How to switch backend mode in Debug (forward reference to Phase 16A).
   - The clang/grpc toolchain trap symptoms and fix (link to DL-045).
   - DerivedData hygiene: do not run parallel xcodebuild test commands against
     the same DerivedData path.

6. Tests.
   Add `FirebaseBootstrapTests.swift`:
   - `configureIfAvailable` returns .missingConfig when no plist is in test
     bundle.
   - .alreadyConfigured is returned on the second call.
   - The returned reason in .failed never contains the test environment plist
     path even when one is faked in.
   - No secret-like value (regex: AIza[0-9A-Za-z\-_]{35}) appears in any
     returned reason string.

Acceptance criteria:
- Repo can be cloned to a fresh machine; `xcodebuild build` succeeds with NO
  GoogleService-Info.plist present.
- With the plist present at repo root, build also succeeds and the plist is
  copied into the app bundle.
- VirtualTrainerApp.init() no longer crashes on missing plist.
- All existing tests pass (≥335).
- DEBUG_LOG.md has a new DL-### entry summarizing the change.

### Assistant - 2026-05-14 11:31:10

I’ll start with the pre-flight checks and a broad read of the repo before touching anything: git state, branch, toolchain paths, docs, project plist references, and the Firebase-related Swift. Then I’ll make the narrow resource/bootstrap changes and keep the camera stack undisturbed.

### Assistant - 2026-05-14 11:31:30

Pre-flight looks clean: branch is `main`, and both `clang` and `swiftc` resolve through XcodeDefault.xctoolchain. I’m going through the docs and Firebase/project wiring now, paying special attention to where the plist is referenced and how tests are organized.

### Assistant - 2026-05-14 11:32:19

The current state matches the phase prompt: the plist is directly in the app Resources phase, the xcconfig mapping exists but Xcode is not consuming it, and `VirtualTrainerApp.init()` still configures Firebase on every launch. I also found the existing DEBUG smoke path is gated by launch arg/env var, so I’ll keep that behavior and only let it proceed after a successful/previous Firebase configuration.

### Assistant - 2026-05-14 11:35:09

I’ve got the shape now. I’m going to make the edits in a tight set: remove the direct plist resource from the project, add the always-running copy script, make Firebase bootstrap return a safe state enum, gate the debug smoke path, add the example plist and setup doc, then add focused bootstrap tests.

### Assistant - 2026-05-14 11:38:25

The code edits are in place and I’m running a targeted bootstrap test now before the full build/test pass. One side note: Xcode touched a user scheme ordering plist while the tools were running; I’ll keep that metadata out of the final diff so the actual change stays clean.

### Assistant - 2026-05-14 11:40:08

The targeted test build succeeded far enough to execute the new run script: it copied the local Firebase client config when present, and Xcode also confirmed the script is set to run every build. The simulator test runner is still spinning; I’m letting that finish before touching the final build/test sequence.

### Assistant - 2026-05-14 11:40:27

The four new `FirebaseBootstrapTests` pass. I’m doing one extra acceptance check now with the ignored local plist temporarily moved out of the repo and a separate clean DerivedData path, so we prove a fresh clone with no Firebase client config still builds.

### Assistant - 2026-05-14 11:43:04

The no-plist build is still running because it had to populate a fresh Swift Package checkout in a clean DerivedData path. Nothing has failed so far; this is the slow “first clone” shape we actually want to exercise.

### Assistant - 2026-05-14 11:43:36

The no-plist clean build passed and the ignored local plist is back where it was. I also cleaned up the Xcode scheme ordering noise, so the remaining diff is just the intended project/bootstrap/docs/tests work. Next I’m running the required exact build, then the full test suite on the same DerivedData path, sequentially.

### Assistant - 2026-05-14 11:43:59

The required build passed with the local plist present and the new copy phase active. I’m starting the required full test suite now on `/tmp/VirtualTrainerDerivedData`; this is sequential after the build, matching the phase constraint.

### Assistant - 2026-05-14 11:45:57

Full test is green: `339` passed, `0` failed, `0` skipped. I’m adding the required DL-047 entry now with the build/test and no-plist verification, then I’ll do the final whitespace and diff checks.

### Assistant - 2026-05-14 11:47:37

Implemented Phase 16.0 on `main`.

**Changed**
- Replaced the required plist resource with an always-running Xcode script phase in [project.pbxproj](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer.xcodeproj/project.pbxproj:226).
- Made Firebase bootstrap safe and stateful in [FirebaseBootstrap.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/FirebaseBootstrap.swift:4).
- Removed normal-launch Firebase bootstrap from [VirtualTrainerApp.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/VirtualTrainerApp.swift:21).
- Gated DEBUG smoke verification on explicit launch request plus successful Firebase config in [FirebaseSmokeVerifier.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainer/Services/FirebaseSmokeVerifier.swift:21).
- Added [FirebaseBootstrapTests.swift](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/VirtualTrainerTests/FirebaseBootstrapTests.swift:1), [GoogleService-Info.example.plist](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/GoogleService-Info.example.plist:1), and [DEVELOPMENT_SETUP.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/Documentation/DEVELOPMENT_SETUP.md:1).
- Appended DL-047 in [DEBUG_LOG.md](/Users/satvik.bansal/Desktop/VirtualTrainer%20-%20mediapipe/DEBUG_LOG.md:1261).

**Behavior**
Before: a fresh clone without `GoogleService-Info.plist` could trip Firebase resource/bootstrap assumptions.  
After: Spotter launches and builds in local-only mode without Firebase config, so Free Analysis, Planned Workouts, local planning, trophies, stats, trends, recaps, heatmaps, and insights stay usable. If a developer drops an ignored dev plist at repo root, the build copies it into the app bundle for Firebase-only debug paths.

**Verification**
- Toolchain confirmed under `XcodeDefault.xctoolchain`.
- No-plist clean build: PASS.
- Required build with local ignored plist present: PASS.
- Required full test suite: `339 passed`, `0 failed`, `0 skipped`.
- `git diff --check`: PASS.
- `gitleaks` was not installed, so I ran a redacted fallback scan over tracked/new non-ignored files: no findings.

**PR Notes**
No Firebase Console changes are required for local mode. Firebase developers should add ignored environment plist files locally, for example `GoogleService-Info-Dev.plist`; no service accounts or private keys belong in this repo. No migration is needed; Codable local JSON and BackendMode.local behavior are unchanged. Known follow-up: Phase 16A should wire the backend-mode switch so Firebase bootstrap is invoked only for `.firebase`.
