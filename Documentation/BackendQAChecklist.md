# Backend QA Checklist

Phase 17 goal: prove the Firebase backend is safe enough for a small internal beta while preserving local-only use.

## Preconditions

- Build and test with `VirtualTrainer.xcworkspace`.
- Confirm `xcrun --find clang` and `xcrun --find swiftc` resolve under `XcodeDefault.xctoolchain`.
- Keep `BackendMode.local` runnable with `GoogleService-Info.plist` absent.
- Do not use production Firebase while emulator tests are running.
- Do not attach raw video, camera frames, face images, raw pose streams, raw pose timelines, raw biometric face data, raw face blendshape streams, plist contents, App Check debug tokens, or third-party secrets to logs, fixtures, exports, or Firestore payloads.

## Manual Beta Checklist

### 1. Fresh Install, Local Mode, No Firebase Config

Steps:
1. Remove or exclude `GoogleService-Info.plist` from the app bundle.
2. Delete the app from the simulator.
3. Launch Spotter with default settings.
4. Complete onboarding, generate a deterministic local plan, run Free Analysis, save the session, unlock at least one trophy, view stats, trends, weekly recap, heatmap, and AI insights.

Expected:
- App launches in local mode.
- No Firebase sign-in prompt is required.
- Free Analysis and Planned Workouts continue to use the shared live analysis stack.
- Saved workouts, trophies, stats, trends, recaps, weekly recaps, heatmaps, and AI insights persist locally.
- No Firebase config missing state blocks the app.

### 2. Fresh Install, Firebase Mode, Anonymous Sign-In

Steps:
1. Install a DEBUG build with a valid Firebase client plist or emulator bootstrap.
2. Set desired backend to `firebase`.
3. Relaunch if the debug UI requests it.
4. Tap "Sign in anonymously (Firebase)".

Expected:
- `Active` backend is `firebase`.
- Firebase UID is shown only in redacted form.
- Profile/debug sync actions become available.
- App remains usable if sign-in fails, with sanitized error text.

### 3. Offline Onboarding, Later Online Profile Sync

Steps:
1. Launch with Firebase mode desired, then disconnect network before onboarding.
2. Complete onboarding offline.
3. Reconnect network and sign in anonymously.
4. Run a full sync.
5. Repeat on another simulator signed into the same emulator/prod test account.

Expected:
- Local profile is claimed under the Firebase account once.
- Remote profile loads on the second simulator.
- No duplicate profile documents are created.
- Existing local JSON remains backwards compatible.

### 4. Free Analysis Save -> Sync

Steps:
1. Open Camera tab.
2. Run Free Analysis and save a summary.
3. Run "Push Pending Writes" or wait for normal sync.
4. Inspect Firestore or emulator UI.

Expected:
- One compact workout doc is written with set subdocuments when set evidence exists.
- No raw frames, raw pose streams, face data, or secret-like values are present.
- Session appears in history after pulling on another simulator.

### 5. Planned Workout Save, Multi-Set, Cross-Device Load

Steps:
1. Generate or select a Planned Workout from Dashboard.
2. Complete at least 4 sets.
3. Save the workout in Firebase mode.
4. Launch a second simulator on the same account and pull remote history.
5. Open the workout detail.

Expected:
- Recent history loads the compact workout quickly.
- Detail view loads set subdocuments when needed.
- Set order is stable by `setIndex`.
- Completion percent, total reps, form score, recaps, and insight inputs match the first device.

### 6. Delete Locally -> Tombstone Propagation

Steps:
1. Save a workout on simulator A.
2. Pull it on simulator B.
3. Delete it from B.
4. Push pending writes from B.
5. Pull remote on A.

Expected:
- Firestore workout doc gets `deletedAt`.
- A hides the workout from active history.
- Tombstone remains available for conflict/audit handling.
- Replaying the delete operation is idempotent.

### 7. Trophy Event Sync, Earliest Earned Wins

Steps:
1. Create the same trophy unlock on two simulators with different `earnedAt` values.
2. Push both devices.
3. Pull trophy progress on both devices.

Expected:
- Duplicate trophy progress collapses to a single earned trophy.
- Earliest `earnedAt` wins.
- Later events do not move the earned date forward.

### 8. Insight Delivery And Engagement Sync

Steps:
1. Trigger an insight on device A.
2. View it on Dashboard and Workout Summary.
3. Mark it helpful on device B.
4. Push and pull both devices.

Expected:
- Delivery records merge earliest first presentation, latest last presentation, max presentation count, and per-surface latest presentation.
- Engagement records merge counts and latest dates.
- Ranker output remains consistent after sync.

### 9. Data Export In Firebase Mode

Steps:
1. In Firebase mode, save a profile, workouts, trophies, calibration, and insights.
2. Pull remote data.
3. Export account data.

Expected:
- Export includes expected local data and remote-labeled sync metadata.
- Export does not include raw video, frames, pose streams, face images, raw face blendshapes, or secrets.

### 10. Account Deletion End To End

Steps:
1. Sign in anonymously in Firebase mode.
2. Save representative profile/workout/trophy/insight data.
3. Use the account deletion flow.
4. Verify local app state and remote user docs.

Expected:
- Listeners stop before deletion.
- Pending writes are handled or abandoned without crashing.
- Local data is wiped.
- Auth account is deleted.
- Remote cleanup follows the current client/console implementation plan.

### 11. Bad Rules Deny Once

Steps:
1. In emulator, temporarily change rules to deny one write category.
2. Attempt a profile or workout write.
3. Restore rules and retry sync.

Expected:
- App stays in a conflict/failed sync state with sanitized error text.
- Local data is not lost.
- Pending journal entries can replay after rules are restored.
- No duplicate writes are created after retry.

### 12. Force Kill Mid-Sync

Steps:
1. Save several pending records.
2. Start sync.
3. Force-kill the app from SpringBoard while writes are in flight.
4. Relaunch and run sync again.

Expected:
- `LocalWriteJournal.json` replays pending operation IDs.
- Remote saves are idempotent by operation ID.
- No duplicate workouts, trophies, deliveries, or engagements appear.

### 13. Active Live Workout Backpressure

Steps:
1. Start a live Free Analysis or Planned Workout.
2. Trigger remote listener traffic from another simulator or emulator UI.
3. Save a workout while the live session is still active.
4. End the workout and run sync.

Expected:
- Heavy pull/push/listener work defers while `WorkoutSessionContext.isLive`.
- Store-level workout remote saves remain queued until the workout ends.
- Live FPS and rep feedback remain unaffected.
- Pending writes clear after the workout ends and sync resumes.

### 14. Simulator SpringBoard Crash Differentiation

Steps:
1. If the simulator crashes, collect the build/test log and simulator crash report.
2. Compare symptoms against `DEBUG_LOG.md` entries DL-035 and DL-045.
3. Re-run toolchain checks and avoid the bare xcodeproj.

Expected:
- SpringBoard or simulator infrastructure crashes are classified separately from app crashes.
- XcodeDefault toolchain is used for both clang and swiftc.
- Reproduction notes include exact destination, DerivedData path, and whether the app process crashed.

## Automated Coverage Map

- `FirebaseBootstrapTests`
  - No-plist local fallback remains safe.
  - `--firebase-emulator` only configures emulators after Firebase app configure succeeds.
  - Bootstrap errors redact plist paths and API-key-like values.

- `SyncOrchestratorTests`
  - Local noop sync.
  - Pending push.
  - Conflict surfacing.
  - Tombstone push/pull.
  - Live workout deferral.
  - Store-level workout remote save queues during live workout.
  - Insight delivery replay does not duplicate.

- `FirestoreRepositoryTests`
  - Profile, workout, trophy, insight, calibration, and plan repository behavior.
  - Listener debounce/backpressure support.
  - Privacy validator rejects forbidden payload keys.

- `BackendDataVolumeTests`
  - 100 workouts: profile + history load stays snappy.
  - 500 workouts: history and heatmap calculation stay responsive.
  - 32-set workout: detail load completes under 1.5 seconds.

- `Phase17BackendHardeningTests`
  - Phase 17 docs and cost budget are present.
  - Cost Snapshot counter records session reads/writes.
  - Representative full-sync payloads reject forbidden raw and secret fields.
  - Analytics privacy guard rejects PII key variants.

- `BackendIntegrationTests`
  - Skipped by default.
  - Runs against Firebase Auth + Firestore emulators through `Scripts/run_backend_integration_tests.sh`, which starts the emulators and supplies `SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1` plus `SPOTTER_FIREBASE_EMULATOR=1`.
  - Covers anonymous sign-in, profile round trip, multi-set workout order, forbidden write denial, and tombstone propagation.

## Tracked Manual Gaps Before Wider Beta

- Validate App Check debug provider and release App Attest on physical devices before enforcement.
- Validate account deletion against the final production cleanup path when Cloud Functions are introduced.
- Run bad-rules and force-kill scenarios in emulator on at least two simulators before inviting testers.
