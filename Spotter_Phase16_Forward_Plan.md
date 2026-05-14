# Spotter — Phase 16 Forward Plan

**Purpose:** Single-source plan for every step from "Firebase SDK installed locally" through "App Store beta-ready" and the design-system revamp. Replaces GPT 5.5 Pro's Phase 16.0–20 plan with a tighter version that matches what's actually in the repo.

**Author:** Founder-coach review.
**Inputs read:** README.md, DEBUG_LOG.md (entries DL-001 through DL-045), all of `Documentation/*.md`, every file in `VirtualTrainer/Repositories/*`, all account-aware stores, `FirebaseBootstrap.swift`, `FirebaseSmokeVerifier.swift`, `.gitignore`, `Configurations/*.xcconfig`, `VirtualTrainer.xcodeproj/project.pbxproj`, the uploaded GPT 5.5 Pro PDF in full, and the two prior evaluation docs in this repo.

---

## Part 1 — Where the code actually is right now

This is what I verified by reading the tree, not the README.

### 1.1 Pre-backend hardening: all eleven items from the last review are shipped

| Item from last review | Status | Evidence |
|---|---|---|
| C-1 `accountId` on ownership models | ✅ | Present on `UserProfile`, `WorkoutSessionSummary`, `TrophyProgress`, `TrophyUnlockEvent`, `AIInsight`, `InsightDeliveryRecord`, `InsightEngagementRecord`, `CalibrationRecord`, all account-aware stores. `AccountContext` + `AccountOwnership` helpers in place. |
| C-2 `SyncMetadata` | ✅ | `Models/SyncMetadata.swift` with `SyncState`, `markLocalMutation`, `preferredForMerge`. |
| C-3 Soft-delete + tombstones | ✅ | `deletedAt: Date?` on `WorkoutSessionSummary` and others. `WorkoutHistoryStore.delete...` with tombstone preservation. |
| C-4 Idempotency keys | ✅ | `Models/WriteOperation.swift` + `LocalWriteJournal` actor with `contains/record/vacuum`. |
| C-5 Off-main persistence | ✅ | `Models/PersistenceActor.swift` actor with `writeLatest`, `waitForWrites`, `removeAfterQueuedWrites`. Stores write through it. |
| C-6 Trophy event log canonical | ✅ | `TrophyUnlockEvent` is append-only; `TrophyEngine` preserves `earnedAt` from earliest event. |
| C-7 Server clock abstraction | ✅ | `Models/AppClock.swift` with `LocalClock`. `WorkoutSessionSummary.serverEndedAt`, `authoritativeEndedAt`. |
| C-8 Firestore shape audit | ✅ | `Documentation/FirestoreShape.md` with measured numbers (`660999` JSON bytes embedded, `28.1 KB` per max set doc). Decision: **Option B** (compact workout doc + sets subcollection). `WorkoutSummarySizeAuditTests.swift` enforces it. |
| C-9 Insight sync semantics | ✅ | `Documentation/SyncConflictResolution.md` defines merge rules for profile/workout/trophy/insight/delivery/engagement/calibration/theme. |
| C-10 PII / account deletion / data export | ✅ | `Services/PIIRegistry.swift`, `Services/AccountDeletionService.swift`, `Services/DataExportService.swift`. |
| C-11 Secret hygiene + xcconfig | ✅ | `.gitleaks.toml`, `Documentation/SECRETS.md`, `Configurations/{Debug,Beta,Release}.xcconfig` with `GOOGLE_SERVICE_INFO_PLIST` variable per env. |

### 1.2 Phase 15 (repository abstraction): shipped

| Item | Status | Notes |
|---|---|---|
| Repository protocols | ✅ | `RepositoryProtocols.swift`: Auth, Profile, Workout, Trophy, Insight, Theme, Calibration, Plan. All `@MainActor` and `async throws`. Observe methods return `AsyncStream`. |
| `BackendMode` enum | ✅ | `.local`, `.firebase`, `.supabase`. |
| `RepositoryError` | ✅ | `.notFound`, `.conflict(serverVersion, localVersion)`, `.unauthorized`, `.network`, `.invalidPayload`, `.accountMissing`, `.backendUnavailable`. |
| Local implementations | ✅ | `LocalAuthRepository`, `LocalStoreRepositories.swift` (Profile, Workout, Trophy, Insight, Theme, Calibration), `LocalPlanRepository`. |
| `AppDependencies` | ✅ | Container injecting concrete repos. `AppDependencies.local()` factory. Injected into `VirtualTrainerApp`. |
| `SyncOrchestrator` | ✅ scaffold | Currently a `.local` no-op. `performFullSync`, `observeRemote`, `enqueueDirtyWrites` all return after a yield. |
| 36 test files / ~335 passing tests | ✅ | Includes `BackendRepositoryTests`, `SyncMetadataTests`, `LocalWriteJournalTests`, `PersistenceActorTests`, `ComplianceServicesTests`, `AccountOwnershipTests`. |

### 1.3 Firebase integration: started, but in a fragile shape

What's already there:
- ✅ Firebase SDK installed via SPM: `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`. No `FirebaseAppCheck`, `FirebaseAnalytics`, `FirebaseCrashlytics`, `FirebaseRemoteConfig`.
- ✅ `Services/FirebaseBootstrap.swift` — calls `FirebaseApp.configure(options:)` using the bundled plist.
- ✅ `Services/FirebaseSmokeVerifier.swift` — full anonymous-auth + Firestore write/read round-trip behind a launch arg (`--firebase-smoke-test`) or env var.
- ✅ `GoogleService-Info.plist` downloaded locally (877 bytes, present at repo root).
- ✅ Firebase Console: project created, iOS app registered with bundle ID, plist downloaded, Anonymous Auth enabled, Firestore database created.

What's **broken or risky right now**:

1. **🔴 The Xcode project hard-references `GoogleService-Info.plist` as a required app resource.** I confirmed this in `VirtualTrainer.xcodeproj/project.pbxproj`:

   ```
   D602ED092FB1AE21001756A5 /* GoogleService-Info.plist */ = {...path = "GoogleService-Info.plist"...};
   D602ED0A2FB1AE21001756A5 /* GoogleService-Info.plist in Resources */ = ...
   ```

   Combined with `.gitignore` ignoring `GoogleService-Info*.plist`, this means **any fresh clone fails to build at the Resource Copy stage**. This was GPT 5.5 Pro's central observation and it's accurate. Codex or CI will face this on first run.

2. **🔴 `FirebaseBootstrap.configureIfNeeded()` is called unconditionally in `VirtualTrainerApp.init()`.** If the plist is ever missing (which it will be after fix #1), the existing `assertionFailure` will crash Debug builds before the app can fall back to local mode. There is no `BackendMode` gating around this call.

3. **🔴 `Configurations/*.xcconfig` defines `GOOGLE_SERVICE_INFO_PLIST = GoogleService-Info-Dev.plist` per environment, but the Xcode project does NOT consume that variable** — it hard-codes `GoogleService-Info.plist`. The environment scaffolding exists but isn't wired up.

4. **🟡 `BackendMode` defaults to `.local` everywhere, but there is no `BackendConfiguration` type, no UI toggle, no UserDefaults override.** You can't actually flip the app into Firebase mode at runtime even though all the plumbing for it exists.

5. **🟡 `FirebaseSmokeVerifier` is excellent infrastructure** (writes to `debugFirebaseSmoke/{uid}`, has timeouts, sanitizes output) but it's not wired into any in-app surface — only the launch argument path. After Phase 16A this should be exposed in a Debug Profile section.

6. **🟡 Toolchain trap (from DL-045):** the standalone Swift 6.2 toolchain crashes inside Firebase/gRPC binary stub injection. Bundled `XcodeDefault.xctoolchain` works. Anyone working on this branch needs to know that.

7. **🟢 `NEW_DESIGN/` has `export-html` + `screenshots` but no Swift bridging yet.** That's fine — Phase 18 territory.

### 1.4 What's deferred by your decision (post-backend)

| Item | Why deferred |
|---|---|
| Personal Records system (`2.C` from earlier review) | Backend-dependent for canonical timestamps |
| Trophy library expansion (`2.E`) | Wait until trophies sync, then add via Remote Config catalog |
| Coach-personality narratives (`1.G`) | Independent but lower-priority |
| Trophy unlock celebration (`2.B`) | Independent but lower-priority |
| Streak Freeze + Streak Milestones (`2.D`) | Backend-dependent for cross-device consistency |
| Workout edit/delete UI (`2.G`) | Backend cascade design needs to happen first |
| Named levels + XP curve (`2.H`) | Includes remote trophy catalog; needs Remote Config |
| Trophy / recap share cards (`2.A` rest) | Independent; can ship anytime |

---

## Part 2 — Firebase Console: what to do right now

> **The question you asked:** *"When I added the Spotter app and bundle ID, it showed me to download the GoogleService-Info.plist, which I added into Xcode. Post that there were a few more steps, which I don't see now."*

Short answer: **you don't need to continue the wizard.** Firebase's setup wizard is a one-shot UI; once you complete the "add SDKs" and "initialize" steps the wizard collapses and won't re-show. The remaining work is in code, not in the console.

### 2.1 What you've already done in the console (verified)

- ✅ Project created
- ✅ iOS app registered with the matching bundle ID
- ✅ `GoogleService-Info.plist` downloaded
- ✅ SDKs installed (verified in the SPM package graph: `firebase-ios-sdk 12.13.0` + `grpc-binary` + `GoogleUtilities` + `GoogleAppMeasurement` + `leveldb` + `nanopb`)
- ✅ Anonymous Auth enabled
- ✅ Firestore database created

### 2.2 What to do in the Firebase Console before Phase 16.0 code work

These are five short tasks. None of them touch Spotter code.

1. **Publish owner-only Firestore rules.** Go to `Firestore Database → Rules` and paste the starter rules below, then click **Publish**. This is the rules version you'll harden in Phase 16H.

   ```js
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       function signedIn() { return request.auth != null; }
       function owns(uid) { return signedIn() && request.auth.uid == uid; }

       match /users/{uid} {
         allow read, write: if owns(uid);
         match /{document=**} {
           allow read, write: if owns(uid);
         }
       }

       match /{document=**} {
         allow read, write: if false;
       }
     }
   }
   ```

2. **Confirm Anonymous Auth is still on** in `Authentication → Sign-in method`. Don't enable Sign in with Apple yet — that comes in Phase 16I/19.

3. **Do NOT enable App Check enforcement.** Leave App Check unregistered. Phase 16H will register it in debug mode; Phase 19 will enable enforcement once we've validated debug + device tokens.

4. **Do NOT add Analytics, Crashlytics, Remote Config yet.** Keep the Firebase footprint minimal — just Core/Auth/Firestore — until Phase 16J explicitly opens those.

5. **(Optional, recommended)** Create a second Firebase project named e.g. `spotter-prod` and add the same iOS app to it, then download its `GoogleService-Info.plist` as `GoogleService-Info-Prod.plist`. Don't add it to Xcode yet. This lets you point `Configurations/Release.xcconfig` at it later without scrambling. If you skip this, you'll do it in Phase 19.

### 2.3 How to re-download the plist if you need it

If you ever need it again (e.g., new dev machine, lost the file), go to `Project settings (gear icon) → General → Your apps → iOS app → "GoogleService-Info.plist"`. Firebase requires the filename to be **exactly** `GoogleService-Info.plist` — no `(2)` suffix, no rename. Drop it where Configurations/*.xcconfig points to:

```
Debug   -> GoogleService-Info-Dev.plist  (this is the file you have today)
Beta    -> GoogleService-Info-Dev.plist
Release -> GoogleService-Info-Prod.plist (only when you create the prod project)
```

> Phase 16.0 will refactor the project to copy the env-scoped file into the bundle as `GoogleService-Info.plist` at build time.

---

## Part 3 — How my plan differs from GPT 5.5 Pro's

GPT's plan is **structurally correct** and well-broken-down (16.0 → 16A–J → 17 → 18 → 19 → 20). I'd ship it. But it misses a few things that matter given the exact code state:

| Gap in GPT's plan | What I'd add |
|---|---|
| GPT says "create FirebaseBootstrapper.swift" in 16A | We already have `Services/FirebaseBootstrap.swift`. The prompt should be **refactor**, not create, and explicitly target the `assertionFailure` line that will crash Debug builds when the plist is absent. |
| GPT misses the existing `FirebaseSmokeVerifier` | This is a major asset. Phase 16A and 16B should reference it as the end-to-end verification tool. Phase 16C-G can use it to validate each repository's first write. |
| Phase 16A "BackendConfiguration via UserDefaults" doesn't say where the toggle lives | I add an explicit Debug-only Profile Settings section spec, plus a non-debug "Firebase unavailable" banner spec. |
| Phase 16B "claim local data on sign-in" is vague | I add the explicit ordering: claim must happen BEFORE first remote read AND BEFORE any sync orchestrator listener starts, otherwise listeners will overwrite local-only records. Also: collision handling when both local and remote have data for the same `accountId`. |
| Phase 16E doesn't address who's authoritative — store or repository — once Firestore is live | I add: stores subscribe to repo `AsyncStream`s; repos are the source of truth in `.firebase` mode; stores stay as the SwiftUI projection layer. |
| Phase 16G "listener debounce" | I add concrete debounce + reentrance rules (no listener-triggered Firestore writes during live workout sessions). |
| Phase 16H rules are described but not drafted | I draft the actual rules content in the prompt body. |
| Pre-flight checks before each phase | I add a shared preflight that includes the DL-045 toolchain check and a `git status` clean assertion. |
| GPT misses: Sign in with Apple's revocation handling (Apple requires REVOKE_TOKEN endpoint behavior) | I add it to Phase 19. |
| GPT misses: Firebase Functions emulator + local rules emulator for tests | I add it to Phase 17. |
| Phase 17 misses cost-per-session budget assertion | I add it: log Firestore read/write counts during a typical onboarding + workout + summary flow, and target an explicit number. |

The rest of GPT's plan I keep, in the same order. The corrected, single-source plan is below.

---

## Part 4 — Execution order

```
Phase 16.0  ──  Firebase resource hardening + config audit
Phase 16A   ──  BackendConfiguration + BackendStatusStore + refactor FirebaseBootstrap
Phase 16B   ──  FirebaseAuthRepository + anonymous sign-in + local data claim
Phase 16C   ──  Firestore DTOs + Mapper + PathBuilder + PrivacyValidator
Phase 16D   ──  Firestore Profile / Theme / Calibration / Plans repos
Phase 16E   ──  Firestore Workout repo (Option B: compact doc + sets subcollection)
Phase 16F   ──  Firestore Trophy + Insight repos (events + delivery + engagement)
Phase 16G   ──  SyncOrchestrator activation (push / pull / listeners / orchestration)
Phase 16H   ──  Firestore rules + App Check debug provider + privacy-assertion tests
Phase 16I   ──  Account deletion + data export wired through Firebase + Cloud Functions plan
Phase 16J   ──  Optional Firebase products: Remote Config, Analytics, Crashlytics, App Check enforcement
Phase 17    ──  Backend QA hardening + cost budget + sync diagnostics
Phase 18    ──  Design-system revamp from NEW_DESIGN
Phase 19    ──  Beta / TestFlight / App Store readiness
Phase 20    ──  Running Analysis research stub
```

Estimated calendar time with Codex assist + one developer:

- 16.0 → 16J: **2.5–3.5 weeks** (most phases are 0.5–1.5 days each; 16E and 16G are the heaviest)
- 17: **3–5 days**
- 18: **2–3 weeks**
- 19: **1 week**
- 20: **1–2 days**

---

## Part 5 — Universal preflight (paste at top of every Codex prompt)

```
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
```

---

## Part 6 — Phase prompts (Codex-ready, ordered)

---

### Phase 16.0 — Firebase resource hardening + config audit

**Why this phase exists.** The Xcode project hard-references `GoogleService-Info.plist` as a required resource, but `.gitignore` ignores it. Fresh clones / CI / Codex environments cannot build. Also, `FirebaseBootstrap.configureIfNeeded()` runs unconditionally on launch and calls `assertionFailure` when the plist is missing, which crashes Debug builds. Fix both before adding any new Firebase code.

**Codex prompt:**

```
Use the Spotter universal preflight block.

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
```

---

### Phase 16A — `BackendConfiguration` + `BackendStatusStore` + mode-aware bootstrap

**Codex prompt:**

```
Use the Spotter universal preflight block.

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
```

---

### Phase 16B — `FirebaseAuthRepository` + anonymous sign-in + local-data claim

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16B goal: implement FirebaseAuthRepository for anonymous sign-in and
connect it to AccountContext. Trigger claimLocalDataForAccount on every store
before any remote read happens. Do NOT write Firestore documents in this phase.

Pre-flight verification:
- Confirm GoogleService-Info.plist is in the bundle for Firebase mode tests.
- Confirm AccountContext, AccountOwnership, and claimLocalDataForAccount(id:)
  exist on:
    OnboardingStore, WorkoutHistoryStore, TrophyStore, InsightStore,
    CalibrationStore, ThemeStore.

Tasks:

1. Create VirtualTrainer/Repositories/Firebase/FirebaseAuthRepository.swift.
   imports: FirebaseAuth, FirebaseCore.

   @MainActor
   final class FirebaseAuthRepository: AuthRepository {
       var currentAccountId: String? { Auth.auth().currentUser?.uid }

       func signInAnonymously() async throws -> String {
           if let user = Auth.auth().currentUser { return user.uid }
           let result = try await Auth.auth().signInAnonymously()
           return result.user.uid
       }

       func linkAnonymousAccountWithApple(idToken: String,
                                          nonce: String) async throws -> String {
           // Scaffolding only — full flow ships in Phase 16I/19.
           throw RepositoryError.backendUnavailable
       }

       func signOut() async throws {
           try Auth.auth().signOut()
           // Do NOT delete local data on sign-out.
       }

       func deleteAccount() async throws {
           guard let user = Auth.auth().currentUser else {
               throw RepositoryError.accountMissing
           }
           // Server-side fan-out lives in Phase 16I via Cloud Functions.
           try await user.delete()
       }

       func observeAuthChanges() async throws -> AsyncStream<String?> {
           AsyncStream { continuation in
               let handle = Auth.auth().addStateDidChangeListener { _, user in
                   continuation.yield(user?.uid)
               }
               continuation.onTermination = { _ in
                   Task { @MainActor in
                       Auth.auth().removeStateDidChangeListener(handle)
                   }
               }
           }
       }
   }

2. AppDependencies.firebaseAuthOnly() factory.
   Same as .local() except auth = FirebaseAuthRepository().
   This is the staging factory until Phase 16D ships first Firestore repos.

3. Account claim coordinator.
   Add VirtualTrainer/Services/AccountClaimCoordinator.swift.

   @MainActor
   final class AccountClaimCoordinator {
       let accountContext: AccountContext
       let stores: AccountAwareStores
       let writeJournal: LocalWriteJournal

       func handleAuthChange(_ newUid: String?) async {
           accountContext.setAccount(newUid)
           guard let newUid else { return }
           // Order matters. Claim local data BEFORE any sync orchestrator
           // listener attaches in Phase 16G. Today we just claim and persist.
           let opId = UUID()
           _ = await stores.claimAll(forAccountId: newUid, operationId: opId)
           await writeJournal.record(operationId: opId, entityKind: .profile)
       }
   }

   AccountAwareStores is a struct that bundles the six account-aware stores
   already in the app and exposes `claimAll(forAccountId:operationId:)` which
   loops through each store calling its claimLocalDataForAccount.

4. Wire it.
   In VirtualTrainerApp, when backendStatusStore.activeBackendMode == .firebase
   and the configured auth repository emits a non-nil uid via
   observeAuthChanges, route through AccountClaimCoordinator.
   In .local mode the existing LocalAuthRepository's stable id continues to be
   the account, no Firebase listener attached.

5. Debug UI.
   ProfileView debug Backend section gets:
   - "Sign in anonymously (Firebase)" button — only enabled when active mode
     is firebase. Shows uid (redacted).
   - "Sign out" button.
   - "Force Re-Claim Local Data Under Current UID" debug button (rare; used
     when testing the claim path manually).

6. Tests.
   - Mock auth: signing in triggers AccountContext.setAccount with the new uid
     and stores' claim methods are invoked exactly once.
   - Mock auth: signing out does NOT delete any local file.
   - Existing LocalAuthRepository tests still pass.
   - Test that linkAnonymousAccountWithApple throws .backendUnavailable in
     both local and firebase modes for this phase.
   - Test that an account claim is recorded in LocalWriteJournal with kind
     .profile and that re-running the claim with the same operationId is a
     no-op.

7. Manual verification.
   - Set BackendMode override = .firebase in Debug.
   - Launch app, complete onboarding.
   - Tap "Sign in anonymously".
   - Firebase Console > Authentication shows an anonymous user.
   - Firestore stays empty (no repository writes yet).
   - Firestore Console > debugFirebaseSmoke remains empty unless smoke test
     was explicitly run.

Acceptance:
- Anonymous Firebase Auth works behind the protocol.
- AccountContext.currentAccountId becomes the Firebase UID in firebase mode.
- All six account-aware stores claim local-only records to the Firebase UID
  exactly once on first sign-in.
- No Firestore documents are created.
- Local mode untouched.
```

---

### Phase 16C — Firestore DTOs + Mapper + PathBuilder + PrivacyValidator

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16C goal: build the Firestore translation layer in isolation — DTOs,
mappers, paths, encoding helpers, and a privacy validator — before any
repository is wired. Zero Firestore writes in this phase.

Inspect:
- Documentation/FirestoreShape.md (compact workout doc + sets subcollection)
- Documentation/SyncConflictResolution.md (merge rules per type)
- All persisted models with accountId, syncMetadata, deletedAt
- WorkoutSummarySizeAuditTests for the size constants

Create files under VirtualTrainer/Repositories/Firebase/:

1. FirestoreDTOs.swift
   Define one Codable struct per Firestore document shape:

   - FirestoreProfileDocument
   - FirestoreWorkoutDocument             (compact summary, no embedded sets)
   - FirestoreWorkoutSetDocument
   - FirestoreTrophyEventDocument
   - FirestoreTrophyProgressCacheDocument (optional cache; canonical source is
                                           the events log)
   - FirestoreInsightDocument
   - FirestoreInsightDeliveryDocument
   - FirestoreInsightEngagementDocument
   - FirestoreCalibrationDocument
   - FirestorePlanDocument

   Every DTO must include:
   - schemaVersion: Int
   - accountId: String
   - deletedAt: Date?
   - syncMetadata fields where the corresponding model has them
   - serverTimestamp placeholder field name (e.g. serverEndedAt: Date?,
     serverEarnedAt: Date?) — Firestore writes will set these via
     FieldValue.serverTimestamp() in Phase 16D+ but the DTO model carries
     them as Date?
   - operationId: UUID  for write-idempotency
   - For workout: counts (setCount, repQualityEventCount, cueEventCount) so
     readers can detect partial loads.

   DTOs MUST NOT contain:
   - rawVideo, videoFrame, cameraFrame, faceImage, rawPoseStream,
     rawPoseTimeline, rawLandmarks, rawFaceBlendshapeStream, biometricFaceData,
     imageData, pixelBuffer, Data fields, apiKey, privateKey, serviceAccount,
     bearerToken.

2. FirestoreMapper.swift
   func mapToProfileDocument(_ profile: UserProfile) -> FirestoreProfileDocument
   func mapFromProfileDocument(_ doc: FirestoreProfileDocument) -> UserProfile
   ... and the symmetric pair for every DTO.

   Rules:
   - Firestore-specific types do NOT leak into app models.
   - UUIDs round-trip as lowercase string.
   - Enums use rawValue.
   - Sets become sorted arrays for stable round-trip.
   - On decode, default missing fields to safe values; never throw on a single
     missing optional.
   - On encode, normalize accountId via AccountOwnership.normalizedAccountId.

3. FirestorePathBuilder.swift
   Static methods:
       users(_:)
       profileDocument(uid:)             -> users/{uid}/profile/current
       workoutDocument(uid:workoutId:)   -> users/{uid}/workouts/{workoutId}
       setDocument(uid:workoutId:setId:) -> users/{uid}/workouts/{workoutId}/sets/{setId}
       trophyEvent(uid:eventId:)         -> users/{uid}/trophyEvents/{eventId}
       trophyProgressCache(uid:)         -> users/{uid}/trophyProgress/current
       insight(uid:dedupeKey:)           -> users/{uid}/insights/{dedupeKey}
       insightDelivery(uid:dedupeKey:)   -> users/{uid}/insightDelivery/{dedupeKey}
       insightEngagement(uid:dedupeKey:) -> users/{uid}/insightEngagement/{dedupeKey}
       calibration(uid:)                 -> users/{uid}/calibration/status
       plan(uid:planId:)                 -> users/{uid}/plans/{planId}
   All paths reject empty/whitespace uids and dedupeKeys.

4. FirestorePrivacyValidator.swift
   func validate(_ payload: [String: Any]) throws
   Throws RepositoryError.invalidPayload with sanitized reason when any of:
   - forbidden key names (see DTO MUST NOT list)
   - Any Data value with > 4 KB byte length (raw blob heuristic)
   - Any String matching the secret regex set from .gitleaks.toml
     (AIza..., -----BEGIN..., service-account JSON shape, etc.)
   Allowed:
   - workout summaries, set summaries, cueEvents, repQualityEvents,
     structuredEffortSummary, formScore, effort proxy numeric fields,
     identifiers, schema/syncMetadata, operationIds.

5. FirestoreEncodingHelpers.swift
   Single helper path that converts a DTO into [String: Any] suitable for
   setData. Reads through FirestoreMapper, then encodes the DTO via
   JSONEncoder + JSONSerialization for type coverage. Replaces special markers
   with FieldValue.serverTimestamp() where the DTO has a server-* Date?
   property and the existing value is nil. Do NOT pull in
   FirebaseFirestoreSwift; we stay on the @objc Firestore API for now.

6. Tests (Phase 16C must add at least 8 tests):
   - Profile DTO round-trip with Set<PhysicalLimitation> → sorted array → Set.
   - Workout compact DTO size stays within
     compactWorkoutDocumentEstimatedFirestoreBytes from FirestoreShape.md.
   - Set DTO round-trip preserves repQualityEvents order and formScore values.
   - Trophy event DTO round-trip preserves earnedAt and earnedAtServer.
   - Insight delivery DTO merges produce expected counts (per
     SyncConflictResolution.md).
   - PathBuilder rejects empty uid and empty dedupeKey.
   - PrivacyValidator rejects { "cameraFrame": Data }, { "apiKey": "AIza..." },
     { "private_key": "-----BEGIN ..." }.
   - PrivacyValidator allows a fully-populated workout DTO.

Acceptance:
- All DTOs / mapper / path / validator / encoding helpers exist with tests.
- No Firestore writes anywhere yet.
- Test count grows by at least 8.
```

---

### Phase 16D — Firestore Profile / Theme / Calibration / Plans

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16D goal: ship the four lowest-risk Firestore repositories. Workout,
trophy, and insight repos come later.

Pre-flight:
- Phase 16C complete; DTOs/mapper/validator/path builder exist.
- FirebaseAuthRepository from 16B exists.
- AccountClaimCoordinator wires the auth-change → claim flow.

Tasks:

1. FirestoreProfileRepository.swift
   Path: users/{uid}/profile/current

   func loadProfile(accountId:) async throws -> UserProfile?
       - getDocument; if !exists, return nil. Map DTO -> UserProfile.

   func saveProfile(_:operationId:) async throws -> UserProfile
       - Require profile.accountId == uid (else throw .accountMissing).
       - Run privacy validator on encoded payload.
       - Use a Firestore transaction:
           - Read current doc.
           - If server doc's syncMetadata.localUpdatedAt > local's AND
             pendingOperationId != operationId → throw .conflict with both
             versions. Repository sets profile.syncMetadata.syncState =
             .conflict and returns the conflicted profile to caller; UI shows
             a non-blocking notice (Phase 17 wires the UI).
           - Else write with serverVersion = doc.metadata.updateTime
             (round-tripped to a string) and operationId.
       - Return the profile with updated SyncMetadata (lastSyncedAt = now,
         syncState = .synced, serverVersion = new updateTime).

   func observeProfile(accountId:) async throws -> AsyncStream<UserProfile?>
       - Snapshot listener; debounce 250ms (use AsyncStream + Task.sleep
         pattern, not Combine, to keep stack small).

2. FirestoreThemeRepository.swift
   Decision (per SyncConflictResolution.md): UserProfile.selectedTheme is the
   future remote source of truth. Theme.json is the local fast-cache.
   Implementation:
       loadTheme(accountId:) reads the profile doc and returns
       profileDoc.selectedTheme.
       saveTheme(_:accountId:operationId:) reads-modify-writes the profile
       doc's selectedTheme only (transactional partial update).
   This avoids creating a competing remote source of truth.

3. FirestoreCalibrationRepository.swift
   Path: users/{uid}/calibration/status
   - Save completed/skipped/failed.
   - Conflict policy from docs: completed beats skipped/failed if completed
     is the latest valid record. If neither side is completed and times tie,
     keep the latest localUpdatedAt.

4. FirestorePlanRepository.swift
   Path: users/{uid}/plans/{planId}
   - Plans are still locally generated. Remote storage is a cache for the
     "active plan" and a thin history.
   - loadActivePlan: read users/{uid}/plans where active == true, order by
     savedAt desc, limit 1.
   - saveActivePlan: mark previous active plan as active=false, then write
     new doc with active=true. In a transaction.
   - Remote plan must NEVER be required for camera/session flow.

5. AppDependencies.firebasePartial() factory.
   - auth: FirebaseAuthRepository
   - profile, theme, calibration, plans: Firestore repositories
   - workouts, trophies, insights: still local until 16E/16F.

6. Reverse-wiring the SwiftUI stores.
   OnboardingStore, ThemeStore, CalibrationStore in firebase mode should:
   - On accountId change, kick off a `Task { ... }` that calls the matching
     repository's load + observe stream and updates @Published state via the
     existing setters.
   - On user save (existing code path), additionally call the repository's
     save. Reuse the LocalWriteJournal to dedupe.
   - Do not double-persist. Either local or remote owns the durable copy in
     a given mode; in firebase mode the local JSON file is just a fast-cache.
     Decide and document.

7. Debug UI.
   ProfileView debug Backend section:
   - "Test profile sync" button: signs in if needed, mutates and saves, reads
     back, shows result.
   - "Test calibration sync" same shape.
   - "Test plan sync" same shape.

8. Tests.
   - Mapper round-trips for Profile, Calibration, Plan (Theme is via Profile).
   - Conflict simulation for ProfileRepository using a stub Firestore.
   - Idempotency: same operationId on retry produces no duplicate write.
   - Observer emits initial state then a follow-up after a remote change.
   - Local mode unaffected.

Acceptance:
- Profile, theme (via profile), calibration, plan sync to Firestore in
  firebase mode.
- Two-device test (simulator A and B) confirms profile updates flow across.
- No workout / trophy / insight data uploaded yet.
- BackendMode.local fully intact.
```

---

### Phase 16E — Firestore Workout Repository (Option B)

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16E goal: implement FirestoreWorkoutRepository using the measured
Option B shape from Documentation/FirestoreShape.md.

Paths (re-stated):
- users/{uid}/workouts/{workoutId}                    compact workout doc
- users/{uid}/workouts/{workoutId}/sets/{setId}       per-set evidence

Tasks:

1. Save behavior.
   Require summary.accountId == uid; else throw .accountMissing.
   Run FirestorePrivacyValidator on every encoded payload.
   Use a Firestore WriteBatch:
   - One write for the compact workout doc, including:
       schemaVersion, accountId, mode, planId, planTitle, title, goal, coach,
       startedAt, endedAt, serverEndedAt (FieldValue.serverTimestamp() if nil),
       durationSeconds, totalReps, totalHoldSeconds, averageFormScore,
       completionPercent, topCueSummary, effortSummary,
       structuredEffortSummary, workoutOutcome, totalGoodFormReps,
       totalExcellentFormReps, totalHighSeverityCues, setCount,
       repQualityEventCount, cueEventCount, createdAt, deletedAt,
       operationId, syncMetadata.
   - One write per ExerciseSetSummary into the sets subcollection, keyed by a
     deterministic setId derived from (exerciseType.rawValue, setIndex ?? 0).
   The batch commits as a single logical save. Idempotency: each set doc's
   operationId equals the parent workout's operationId so reruns of the same
   save do not create duplicates.

2. Delete behavior.
   Soft-delete only. Set deletedAt = serverTimestamp() on the workout doc.
   Set docs inherit by inference (workout doc's deletedAt). Default reads
   filter `deletedAt == null`. A separate scheduled tombstone vacuum function
   (Cloud Function plan in 16I) hard-deletes after 30 days.

3. Load behavior.
   loadRecentWorkouts(accountId:limit:since:):
     - Query users/{uid}/workouts where deletedAt == null,
       order by serverEndedAt desc (fall back to endedAt if serverEndedAt
       missing), limit `limit`.
     - For each compact doc, instantiate a WorkoutSessionSummary with empty
       exerciseSummaries. Caller fetches sets on demand via loadWorkout.
   loadWorkout(accountId:id:):
     - getDocument workout, then collection.getDocuments on sets, ordered by
       setIndex.
     - Map both to a full WorkoutSessionSummary.

4. Observe behavior.
   observeRecentWorkouts(accountId:limit:):
     - Snapshot listener on the workouts query, debounce 250ms.
     - On each emission, do NOT eagerly fetch sets. Surfaces that need detail
       call loadWorkout.
     - Listener handle is removed on AsyncStream termination.

5. SyncOrchestrator integration (push-only for now).
   Extend SyncOrchestrator with a Debug-only `pushPendingWorkouts()` method:
   - Find local summaries with syncState == .pendingUpload.
   - Call repository.saveWorkoutSummary in serial.
   - Update local syncState to .synced on ack.

6. WorkoutHistoryStore wiring in firebase mode.
   - On account claim, subscribe to repo.observeRecentWorkouts(limit: 80) and
     populate `summaries` from the merged result of local + remote. Local
     items not yet on the server stay; remote items not yet in local cache
     are added.
   - Save path: in firebase mode call repo.saveWorkoutSummary AFTER the local
     persist completes. If remote save fails, leave syncState =
     .pendingUpload; next orchestrator push retries.
   - Delete path: same.

7. Privacy + size tests.
   - Synthetic 8-exercise × 4-set × 25-repEvent workout encodes to a compact
     doc whose Firestore-estimated bytes match
     compactWorkoutDocumentEstimatedFirestoreBytes from FirestoreShape.md
     within 5%.
   - Largest set doc stays under 64 KB.
   - Privacy validator rejects an attempt to write `cameraFrame: Data(...)`
     or any forbidden key inside a set doc.

8. Idempotency + tombstone tests.
   - Saving the same summary twice with the same operationId produces the
     same Firestore state (no duplicate set docs).
   - Deleting a workout sets workout.deletedAt; subsequent loadRecentWorkouts
     omits it; subsequent loadWorkout returns nil for the deleted id.

Acceptance:
- Planned and Free Analysis summaries sync to Firestore as one compact doc
  plus N set docs.
- Soft delete is honored.
- Listener-driven WorkoutHistoryStore stays in sync across two simulators.
- No raw camera / pose / face / video data ever serialized.
- BackendMode.local unaffected.
```

---

### Phase 16F — Firestore Trophy + Insight repositories

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16F goal: sync the memory layer — trophy unlock events, insight
documents, delivery and engagement aggregates.

Paths:
- users/{uid}/trophyEvents/{eventId}                  append-only
- users/{uid}/trophyProgress/current                  optional cache
- users/{uid}/insights/{dedupeKey}                    insight body
- users/{uid}/insightDelivery/{dedupeKey}             cooldown aggregate
- users/{uid}/insightEngagement/{dedupeKey}           engagement aggregate

Tasks:

1. FirestoreTrophyRepository.
   - loadTrophyDefinitions: returns the bundled catalog. Remote catalog
     hydration via Remote Config arrives in Phase 16J / 2.H.
   - saveTrophyEvent(_:operationId:): append-only doc; the deterministic
     eventId is operationId.uuidString.lowercased(). On duplicate writes,
     transaction reads first; if the doc already exists with the same
     accountId+trophyId+earnedAt, return existing.
   - loadTrophyEvents(accountId:since:): query trophyEvents where deletedAt
     == null, order by earnedAt asc.
   - loadTrophyProgress: derive from events (preserve earliest earnedAt
     per trophyId) unless a cache doc is present and not stale.
   - observeTrophyEvents: listener with 500ms debounce.
   - Coming-soon trophies emit no events (the TrophyEngine already enforces
     this — confirm in tests).

2. FirestoreInsightRepository.
   - saveInsights(_:operationId:): one doc per AIInsight keyed by dedupeKey.
     setData(merge: true) to preserve server-only fields. Honor sourcePolicyVersion: later wins.
   - loadRecentInsights(accountId:limit:): query where deletedAt == null AND
     expiresAt > now (or expiresAt == null), order by createdAt desc.
   - saveDeliveryRecord: read-modify-write merge:
       earliest firstPresentedAt, latest lastPresentedAt, max
       presentationCount, per-surface max last-presented date.
   - saveEngagementRecord: read-modify-write merge:
       sum engagementCounts, max lastEngagementDates per kind.
   - invalidateInsight(accountId:dedupeKey:operationId:): set deletedAt =
     serverTimestamp(). Subsequent loads exclude it.

3. Wiring InsightStore in firebase mode.
   On account claim, subscribe to:
     - repo.observeRecentInsights with debounce
     - repo.observeDeliveryRecords (optional listener; cheap docs)
     - repo.observeEngagementRecords
   Merge remote into local @Published state.
   On local save (recordImpression, recordEngagement, ingest), also push to
   the repository. Idempotency via LocalWriteJournal.

4. Privacy.
   Run FirestorePrivacyValidator on every outgoing payload.
   Delivery and engagement records must NOT carry workout raw payloads,
   evidence refs that include camera data, or PII beyond dedupeKey.

5. Tests.
   - Trophy event round-trip with earliest-earnedAt-wins on duplicate.
   - Coming-soon trophies → no events emitted.
   - Insight round-trip by dedupeKey with sourcePolicyVersion bump.
   - Delivery merge: earliest first, latest last, max count.
   - Engagement merge: sum counts, max dates per kind.
   - Invalidated insight hidden from loadRecentInsights.
   - PrivacyValidator rejects forbidden keys in insight docs.

Acceptance:
- Trophy unlock events fan out to remote consistently.
- Cross-device duplicate trophy unlock unifies on earliest earnedAt.
- Insight engagement persists across devices.
- BackendMode.local fully unchanged.
```

---

### Phase 16G — SyncOrchestrator activation

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16G goal: turn SyncOrchestrator from a no-op scaffold into a real
push/pull/listener coordinator. Keep it manually triggerable; do NOT enable
fully-automatic background sync yet (Phase 17 will).

Implementation contract:

1. Sync phases (all async throws):
   - pullRemote(accountId:): single pull pass for all repository types in a
     defined order: profile -> calibration -> active plan -> recent workouts
     (compact) -> trophy events -> recent insights -> delivery -> engagement.
   - pushPendingLocal(accountId:): drain LocalWriteJournal pending entries by
     replaying the matching repository save call.
   - startListeners(accountId:): attach observe* listeners for the live
     surfaces (profile, recent workouts, trophy events, insights).
   - stopListeners()
   - performFullSync(): stopListeners → pullRemote → pushPendingLocal →
     startListeners.

2. Camera/product safety.
   - SyncOrchestrator MUST check WorkoutSessionContext.isLive before scheduling
     heavy syncs. If live, defer to onWorkoutEnded.
   - SyncOrchestrator MUST NOT start the camera, request microphone, or run
     pose work.
   - Listeners debounce remote updates: 250ms for workouts/profile, 500ms for
     insights, 1000ms for trophy events.

3. Conflict surfacing.
   - When a repo throws RepositoryError.conflict, mark the local record's
     syncState = .conflict and write a SyncConflict event to a new
     `SyncConflictsStore` (in-memory + persisted, capped at 50). Phase 17
     wires UI for review/dismiss.

4. Listener-driven store updates.
   Each account-aware store gains an `applyRemote*` method that takes a
   repository emission and merges with local state without forming an
   infinite loop:
   - mark incoming as already-synced
   - skip local replay if syncMetadata equals the incoming version
   - update @Published state on main actor
   - existing tests for store mutation should still pass

5. Debug UI.
   ProfileView Backend section adds:
   - "Run Full Sync"
   - "Push Pending Writes"
   - "Pull Remote"
   - "Start Listeners" / "Stop Listeners"
   - Show: status, lastSyncedAt, pendingUploadCount, conflictCount,
     listenersAttached, lastError (sanitized).

6. Tests.
   - Local-mode no-op succeeds.
   - Pending upload pushes correctly with a fake repository.
   - Conflict surfaces correctly and stops further writes for that record.
   - Listener emissions are deduplicated when the local record was already
     synced.
   - Tombstone propagation: deleting locally then pushing produces a remote
     deletedAt; pulling on another device hides the tombstoned record.
   - Live-workout guard: pushPendingLocal while WorkoutSessionContext.isLive
     queues to onWorkoutEnded.

Acceptance:
- Two-simulator workflow demonstrates: save on A → appears on B within 5s
  (debounce included), delete on B → disappears on A within 5s.
- Local mode untouched.
- No automatic background sync yet — every operation is debug-triggered or
  triggered by an explicit auth/account-claim event.
```

---

### Phase 16H — Firestore rules + App Check debug provider + privacy assertion tests

**Codex prompt:**

```
Use the Spotter universal preflight block.

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
```

---

### Phase 16I — Account deletion + data export wired through Firebase + Cloud Functions plan

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16I goal: extend the existing AccountDeletionService and DataExportService
to handle backend mode, and document the Cloud Functions plan that will fan out
account deletion server-side.

Apple Account Deletion requirement: any iOS app that creates an account —
including automatically-created anonymous accounts — must allow users to
initiate deletion in-app. We meet this in firebase mode in this phase.

Tasks:

1. Extend AccountDeletionService.deleteAccountAndData with mode awareness:
   - .local: today's behavior.
   - .firebase:
     a) Stop all sync listeners (call SyncOrchestrator.stopListeners()).
     b) Await PersistenceActor.waitForWrites for every store URL.
     c) If currentAccountId != nil, attempt
        FirebaseAuthRepository.deleteAccount() which calls
        Auth.auth().currentUser.delete().
     d) Client-side, perform a bounded Firestore tree delete of users/{uid}
        (limited to the documents the rules allow the client to delete; for
        rules above, only plans). The rest is the Cloud Function's job.
     e) Wipe local files (existing local path).
     f) Clear AccountContext, route the user back to onboarding.
     g) On any partial failure, surface a "Some cloud data may take up to 7
        days to delete" notice and continue local wipe. Do NOT block the user.

2. Extend DataExportService:
   - .local: today's behavior.
   - .firebase: in addition to local files, fetch the latest server-side
     copies (profile, recent workouts with sets, trophy events, insights with
     delivery + engagement, calibration, plans) into the same archive, each
     labeled `*.remote.json` so the user can distinguish.
   - README.txt inside the archive explains local vs remote, the date
     generated, and the schema versions in play.

3. Documentation/FirebaseFunctionsPlan.md
   - onAuthUserDelete: triggered on auth.user().onDelete(); deletes
     users/{uid}/** recursively. Use the Functions Firestore admin SDK.
   - scheduledTombstoneVacuum: nightly job hard-deletes documents whose
     deletedAt < now - 30 days.
   - operationIdDedupe: optional; the rules + client idempotency already
     cover most cases.
   - insightRewriteProxy: future. The iOS client must not call third-party
     LLMs directly. A function can accept InsightLLMContext, call OpenAI/etc,
     and return RewriteResult.
   - Document explicitly: service account keys NEVER ship in the iOS repo.
     Functions live in a separate repo `spotter-functions` and use a
     service account stored in Firebase project secrets.
   - The functions are NOT shipped in this phase; this is a documentation +
     scaffolding phase.

4. UI.
   ProfileView Account section (visible always, not just DEBUG):
   - "Export My Data" — calls DataExportService.exportLocalData or
     exportLocalAndRemoteData depending on mode.
   - "Delete My Account and Data" — destructive confirmation, requires typing
     the word DELETE.
   - Subtitle clearly states:
     - "Local mode: clears all data on this device."
     - "Firebase mode: deletes this device AND your synced cloud data.
       Some cloud data may take up to 7 days to fully delete."

5. Tests.
   - Local-mode deletion unchanged (existing tests).
   - Firebase-mode deletion calls in order: stopListeners → wait → auth.delete
     → local wipe → AccountContext clear.
   - Export in firebase mode writes both *.json and *.remote.json files when
     possible; if remote fetch fails, the export still succeeds with a
     note in README.txt.
   - Re-running delete is idempotent.

Acceptance:
- Apple Account Deletion compliance is verifiable end-to-end in firebase mode.
- Documentation for Cloud Functions exists; no functions are deployed.
- Export honors local + remote labeling.
- App routes back to onboarding after deletion in both modes.
```

---

### Phase 16J — Optional Firebase products (Remote Config / Analytics / Crashlytics / App Check enforcement)

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 16J goal: add Remote Config, Analytics, Crashlytics, and App Check
enforcement readiness AFTER core Auth/Firestore sync is stable. Do not run if
any of 16A-G are unstable.

Pre-flight:
- 16A-G shipped and Phase 17 hardening complete or in flight.
- Anonymous sign-in and basic sync verified on two simulators.

Tasks:

1. Remote Config (FirebaseRemoteConfig).
   - Add RemoteFeatureFlagService that wraps the existing static FeatureFlags
     and overlays remote values for:
       - backendSyncEnabled (kill switch)
       - coachInsightLLMRewrite
       - quickStartDeckVersion
       - trophyCatalogVersion
       - runningAnalysisEnabled
       - designSystemV2Enabled
   - Defaults come from bundled FeatureFlags.default; remote overrides apply
     after the first successful fetch. Fetch fails → stick with defaults.
   - Add tests that prove defaults are honored when no network.

2. Analytics (FirebaseAnalytics).
   - Add AnalyticsService protocol + FirebaseAnalyticsService impl +
     NoopAnalyticsService for tests and local mode.
   - Event taxonomy (no PII, no raw rep events):
       appOpen
       onboardingCompleted
       calibrationCompleted(outcome)
       workoutSaved(mode)                  // .freeAnalysis or .plannedWorkout
       trophyUnlocked(id, rarity)
       insightImpression(type, surface)
       insightHelpful(type)
       insightNotHelpful(type)
       shareCardRendered(kind)             // .heatmap | .trophy | .recap
       syncError(domain)
   - Add a test that introspects every event call and asserts no PII keys
     (displayName, age, gender, etc).

3. Crashlytics (FirebaseCrashlytics).
   - Wire on launch in firebase mode.
   - Set custom keys: backendMode, schemaVersions.
   - Do NOT set user identifier to displayName; use accountId hashed (SHA-256
     prefix 8 chars) as the key, or skip entirely.

4. App Check enforcement readiness.
   - Today: AppCheckDebugProvider installed in DEBUG (from 16H).
   - Add AppAttestProvider for iOS 14.5+ devices in release.
   - Add Documentation/AppCheckRollout.md describing the staged enforcement:
       Stage 1: Monitoring mode (Firebase Console → App Check → Firestore →
                Unenforced; collect metrics for 7 days)
       Stage 2: Enforce. Set in Firebase Console.
   - Do NOT enable enforcement in this phase. Phase 19 will, after physical
     device validation.

5. Tests.
   - Remote Config defaults without network.
   - Noop analytics in local mode emits zero Firebase calls.
   - Analytics privacy assertions.
   - Crashlytics no-op in unit tests.

Acceptance:
- Remote Config bound to a few real flags.
- Analytics events flowing; privacy preserved.
- Crashlytics initialized in firebase mode.
- App Check installed but unenforced.
- BackendMode.local fully unchanged.
```

---

### Phase 17 — Backend QA hardening (with cost budget + emulator)

**Codex prompt:**

```
Use the Spotter universal preflight block.

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
```

---

### Phase 18 — Design-system revamp from NEW_DESIGN

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 18 goal: align Spotter's SwiftUI surface with NEW_DESIGN/export-html and
NEW_DESIGN/screenshots WITHOUT changing any backend behavior or product logic.

Pre-flight:
- Phase 17 complete; backend is stable and observed in dev.
- Inspect NEW_DESIGN/export-html and NEW_DESIGN/screenshots end-to-end.
- Inspect DesignSystem/Theme.swift, DesignSystem/LiquidGlass.swift,
  ThemeStore, SpotterThemeOption.

Build SpotterThemeV2 — semantic color/typography/spacing tokens:

1. Semantic colors:
   background, foreground, primary, secondary, accent, muted, card,
   cardElevated, border, destructive, success, warning, chartPrimary,
   chartSecondary, overlayOnLive (camera HUD)

   Plus spacing scale, radius scale, border widths, shadow elevations,
   safe-area rules, motion tokens.

2. Runtime palettes (one per SpotterThemeOption):
   - Hyper       (neon / electric)
   - Hot Girl    (pink / magenta)
   - Warm        (terracotta / amber)
   - Spicy       (red / saffron)

   Each palette overrides every semantic color and a few motion tokens.

3. Typography:
   display, largeTitle, title, headline, body, caption, monospacedMetric.
   System font fallbacks unless a bundled font is shipped with the design.

4. Reusable components:
   SpotterButton (primary/secondary/destructive/ghost), SpotterCard,
   MetricPill, GoalCard, ExerciseRow, CoachCard, TrophyCard, ThemeOptionCard,
   BottomNav, ProgressRing, InsightCard, WorkoutHistoryRow,
   TargetVolumeEditSheet, RestTimerView, SummaryMetricCard, HeatmapDayCell,
   SharePosterPreview, BackendStatusBanner (firebase mode), ConflictRowBadge.

5. Apply screen-by-screen:
   Welcome / onboarding (5 steps), Calibration intro + run, Dashboard / Quick
   Start, Camera tab exercise selection + readiness, Free Analysis summary,
   Workout Preview, Target Volume Edit sheet, Live Workout HUD shell, Rest
   screen, Workout Summary, Workout Detail sheet, Trophies, Trophy
   Collection, Profile, Heatmap day drill-in, Account / Export / Delete,
   Backend debug / status, Sync diagnostics (DEBUG).

Hard rules:
- NO raw hex colors in feature screens.
- NO repeated one-off card/button styles.
- All chrome goes through tokens.
- Theme switch updates accent immediately; persists via existing ThemeStore.
- Camera overlay text must remain readable over live feed (use overlayOnLive).
- Support iPhone SE (small) through Pro Max.
- Support Dynamic Type at least Large.
- Preserve accessibility contrast.
- Do NOT change any product logic.
- Do NOT touch backend repository code or live camera pipeline.

Testing:
- Build green.
- All core unit tests pass.
- Snapshot tests for at least 8 representative screens × 4 themes × 2 device
  sizes.
- Manual: switch every theme, complete onboarding, complete calibration,
  start Free Analysis, start a planned workout, finish summary, delete a
  workout, export data.

Acceptance:
- App visually matches NEW_DESIGN direction.
- Runtime themes work.
- Functional flows remain intact.
```

---

### Phase 19 — Beta / TestFlight / App Store readiness

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 19 goal: prepare Spotter for a real internal/TestFlight beta.

Tasks:

1. Privacy copy.
   - Camera usage description (Info.plist NSCameraUsageDescription).
   - On-device form analysis explanation.
   - "No raw video upload by default" copy.
   - Derived evidence explanation (what we save).
   - Account export/delete explanation.
   - Firebase sync explanation when enabled.
   - AI insight explanation (deterministic, evidence-backed, no medical
     diagnosis).

2. Permissions and graceful-failure copy.
   - Camera denied → guidance to Settings.
   - Model unavailable → "Download models" button or instruction.
   - Network unavailable → no blocker; sync deferred banner.
   - Firebase unavailable → local-mode banner.
   - No microphone permission requested unless an explicit feature needs it.

3. Account requirements (Apple App Store Guideline 5.1.1(v)).
   - If anonymous Firebase account is auto-created, explain that on the
     "Account" Profile section.
   - Account deletion must be production-ready (it is, via 16I).
   - Sign in with Apple: only if you choose to surface a "Sign in with Apple"
     button. If you do, you MUST handle Apple's REVOKE_TOKEN webhook (Sign in
     with Apple JS REST API + server endpoint) and propagate revocation to
     Firebase Auth via a Cloud Function. Document or defer in
     Documentation/SignInWithAppleRollout.md.

4. Stability.
   - No orphan camera sessions (camera lifecycle is solid; verify
     once more under PlannedWorkoutSessionView + RestScreenView edge cases).
   - No double frame processing.
   - Sync does not run heavy work during live workout (Phase 16G + 17 gate).
   - App survives force-quit during pending sync (LocalWriteJournal replays).
   - Simulator SpringBoard issues documented per DL-035 and DL-045.

5. Performance.
   - Live camera FPS stable across iPhone SE → 17 Pro Max.
   - Workout save < 250ms.
   - Large workout detail loads < 1.5s.
   - Profile heatmap loads < 500ms.
   - No main-actor JSON write stalls (already handled via PersistenceActor).

6. Observability.
   - Crashlytics if enabled.
   - Analytics if enabled with privacy taxonomy from 16J.
   - Debug sync diagnostics gated to #if DEBUG or hidden in release builds.

7. TestFlight checklist (Documentation/TestFlightChecklist.md):
   - Build number strategy (auto-increment via CI or manual).
   - Firebase dev/prod project selection per build configuration.
   - GoogleService-Info-Prod.plist mapped to Release.xcconfig.
   - Firestore rules published in prod project.
   - App Check stage 1 (monitoring only) in prod for 7 days; stage 2
     (enforcement) only after metrics look clean.
   - Internal tester instructions (Sign in flow, known limitations, how to
     report bugs).

8. App Store metadata prep.
   - App Privacy labels:
     - Data Used to Track You: None.
     - Data Linked to You: Contact Info (none unless email login added),
       Identifiers (account uid), Usage Data (analytics events), Diagnostics
       (Crashlytics).
     - Data Not Linked to You: Workout history (linked via account uid →
       "Linked").
   - Support URL.
   - Account deletion instructions (in-app path + URL).
   - Safety disclaimer (no medical diagnosis).

Acceptance:
- Internal beta checklist exists and is followed.
- No privacy/security blocker.
- App can be installed, signed-in-with, and used end-to-end by a non-
  developer.
```

---

### Phase 20 — Running Analysis research stub

**Codex prompt:**

```
Use the Spotter universal preflight block.

Phase 20 goal: prepare Running Analysis as a documented research/coming-soon
feature without unsafe injury claims.

Tasks:

1. RunningAnalysisFeatureFlag (default false; remote-controllable via
   RemoteFeatureFlagService when 16J shipped).

2. RunningAnalysisPlaceholderView shown on Dashboard's quick action.
   - Coming-soon copy.
   - Explains gait/form research direction.
   - Does NOT start the camera.
   - No injury risk claims.

3. Documentation/RunningAnalysisResearch.md.
   - Camera setup assumptions (phone placement, distance).
   - Indoor vs outdoor constraints.
   - Full-body visibility limitations.
   - What MediaPipe pose can infer with reasonable confidence.
   - What it cannot infer (foot strike pattern, ground reaction force, joint
     loading).
   - No injury diagnosis under any circumstance.
   - Validation plan (treadmill ground-truth comparisons, IRB-style consent
     for any test data collection).
   - Candidate metrics, gated by validation:
       cadence proxy, stride symmetry proxy, trunk lean, knee tracking,
       foot strike (only after validation, conservative confidence band).
   - Privacy boundary identical to the camera pipeline today.

4. Dashboard.
   - Running Analysis card opens the placeholder.
   - Clearly marked Coming Soon.

5. Tests.
   - Feature flag default = false.
   - Placeholder view does not instantiate CameraManager.
   - No backend writes happen from this surface.

Acceptance:
- Running Analysis is accounted for; the rest of the product is unaffected.
```

---

## Part 7 — Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Firebase package adds binary stub injection that crashes under custom Swift toolchain | High | DL-045 captured the fix; DEVELOPMENT_SETUP.md added in 16.0; preflight check on every phase |
| Conflict on multi-device write floods stores with stale records | High | SyncOrchestrator gates listener updates by syncMetadata; `applyRemote*` methods skip already-synced records (16G) |
| App Check rejects legitimate clients in production | Medium | Monitoring stage (Phase 19) before enforcement |
| Cost overrun in Firestore | Medium | Cost budget assertion in Phase 17; remote config kill switch in 16J |
| Apple App Store rejects for account-deletion non-compliance | High | Phase 16I + Phase 19 prerequisite |
| Sign in with Apple revocation not handled | High if SIWA shipped | Documented in Phase 19; defer SIWA until revocation server endpoint exists |
| Insights LLM rewrite leaks PII | High | Default off; sanitizer rejects; future rewriteProxy lives behind a Cloud Function (Phase 16I plan) |
| Live workout disrupted by sync | High | Phase 16G live-workout guard; debounce; PersistenceActor.waitForWrites |
| Onboarding profile race with first remote read | Medium | AccountClaimCoordinator runs BEFORE listeners attach (Phase 16B + 16G) |
| Schema change breaks decoders | Medium | All Codable decoders already use `decodeIfPresent`; schemaVersion bumps tracked in PIIRegistry / SyncMetadata |

---

## Part 8 — Immediate next actions (do these now)

1. **Open Firebase Console → Firestore → Rules** and paste the owner-only rules from Part 2.2.1. Click **Publish**. Do this before any backend code work to ensure the rules are in place when 16D first writes to Firestore.

2. **Open the project in Xcode** and confirm the active toolchain is **Xcode 26.3** (Xcode menu → Toolchains). If it shows "Swift 6.2", switch back. See DL-045.

3. **Run the pre-flight in a terminal:**

   ```sh
   cd "/Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe"
   git status                          # should be clean
   xcode-select -p                     # should be /Applications/Xcode.app/Contents/Developer
   xcrun --find clang                  # should resolve under XcodeDefault.xctoolchain
   rm -rf /tmp/VirtualTrainerDerivedData
   xcodebuild build \
     -workspace VirtualTrainer.xcworkspace \
     -scheme VirtualTrainer \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -derivedDataPath /tmp/VirtualTrainerDerivedData
   xcodebuild test \
     -workspace VirtualTrainer.xcworkspace \
     -scheme VirtualTrainer \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -derivedDataPath /tmp/VirtualTrainerDerivedData
   ```

   Expect: 335+ tests pass. If anything fails, stop and triage before Phase 16.0.

4. **Run Phase 16.0** in Codex. It's the smallest phase. Verify with a fresh clone: rename your local `GoogleService-Info.plist` to `GoogleService-Info.plist.bak` and rebuild — the build must still succeed and the app must launch in local mode.

5. **After 16.0 lands, run 16A then 16B.** These two phases are also small. After 16B you should be able to:
   - Toggle backend mode in the Debug Profile screen to `.firebase`.
   - Sign in anonymously.
   - See an anonymous user appear in Firebase Console → Authentication.
   - Firestore still empty (correct — no writes yet).

6. **Then proceed through 16C → 16J sequentially.** Do NOT skip 16C — the DTO/mapper/privacy layer makes 16D-G dramatically faster and safer.

7. **Defer 16J's App Check enforcement until Phase 19.** Same for Sign in with Apple. They unlock late.

---

## Part 9 — What I disagree with in GPT 5.5 Pro's plan (and what I kept)

**I kept** the overall phase structure (16.0 → 16J → 17 → 18 → 19 → 20). It's correct.

**I disagree with / amended:**

1. GPT prescribes a brand-new `FirebaseBootstrapper.swift`. We already have `FirebaseBootstrap.swift` doing roughly the right thing. Refactor it. **Edited Phase 16.0 + 16A accordingly.**

2. GPT did not catch the existing `FirebaseSmokeVerifier.swift`. It's a great asset and should be the manual verification tool for each subsequent phase. **Added references in 16A, 16B, 16D, 16E.**

3. GPT's 16B doesn't specify the AccountClaimCoordinator ordering relative to sync listeners. That order matters — claim must precede listeners or you'll overwrite local-only records with empty remote state. **Added `AccountClaimCoordinator` spec in 16B and ordering in 16G.**

4. GPT's 16E doesn't say who's authoritative — the store or the repository — once remote is live. **Added the rule:** stores subscribe to repos in firebase mode; repos are the durable copy; stores remain the SwiftUI projection layer.

5. GPT's 16G mentions debouncing but no concrete window. **Specified: 250ms workouts/profile, 500ms insights, 1000ms trophy events.**

6. GPT's 16H rules are described, not written. **Wrote them out in full, including the `noRawData()` rule function.**

7. GPT's 16J adds App Check + Crashlytics but doesn't gate them to "after 16A-G are stable". **Added the explicit pre-flight gate.**

8. GPT's Phase 19 doesn't mention Sign in with Apple's REVOKE_TOKEN endpoint. Apple has enforced this since iOS 16 and apps without it can be rejected. **Added in Phase 19.**

9. GPT's Phase 17 misses an emulator path. Firebase Emulator Suite is free, fast, and lets you run integration tests deterministically without touching live Firebase. **Added Firebase Emulator setup in Phase 17.**

10. GPT's Phase 17 misses cost budgets. **Added a soft per-user-week budget.**

11. GPT's universal preflight is good. **I added git status, secret scan, and the explicit toolchain check to mine.**

The rest of GPT's plan I would ship without edits.

---

## Closing

You are in unusually good shape going into the Firebase work. The pre-backend hardening is comprehensive, the repository abstraction is in, the live camera pipeline is protected, and the Firebase SDK is already integrated cleanly. The remaining work is dominantly **plumbing** — DTOs, repository implementations, listeners, rules — not architectural decisions.

If you only do three things this week:

1. **Publish the owner-only Firestore rules in the console NOW.** Five minutes. Removes the chance that you write to a wide-open database during 16D testing.
2. **Run Phase 16.0** so a clone-and-build sequence works without the local plist. Avoids the future "why won't this build for Codex" surprise.
3. **Run 16A + 16B back-to-back** so you can toggle into Firebase mode in the Debug Profile screen and see an anonymous UID appear in the Firebase Console. That visible feedback is energizing and validates the whole stack end-to-end.

After that, the rest of 16C-J is mostly mechanical given the foundation you've laid.

Ship a small Phase, verify in Console + smoke test, commit, repeat. Don't batch.
