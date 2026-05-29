# P16C: Audit repo and app constraints

- Thread ID: 019e2581-504f-7fe3-9921-ce5ee6ac3bda
- Created: 2026-05-14 13:31:32 (Asia/Kolkata)
- Updated: 2026-05-14 13:53:30 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/14/rollout-2026-05-14T13-31-32-019e2581-504f-7fe3-9921-ce5ee6ac3bda.jsonl
- Git branch at thread start: main
- Git SHA at thread start: 62f12876a01d7eac38c734e119b50ea61341399b
- Exported visible messages: 20
- Extracted input images: 0

## Conversation

### User - 2026-05-14 13:31:50

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

### Assistant - 2026-05-14 13:31:57

I’ll first do the requested pre-flight and read-through: clean git status, branch, recent history, toolchain paths, then the repo docs and the relevant model/test files. After that I’ll make the Firebase translation layer in a tight slice and keep the live camera stack untouched.

### Assistant - 2026-05-14 13:32:13

Pre-flight looks good so far: `git status --short` returned clean, current branch is `main`, and both `clang` and `swiftc` resolve under XcodeDefault. I’m reading the docs and persisted model surfaces now so the DTOs match the existing app instead of imposing a new shape.

### Assistant - 2026-05-14 13:32:58

The Firestore docs make Option B explicit: compact workout documents plus `sets` subcollection, with derived evidence only. I’m now tracing the persisted Codable models and their default-decoding patterns so the mapper can round-trip old local JSON safely and keep Firestore types isolated.

### Assistant - 2026-05-14 13:36:59

I’ve got the shape now. I’m going to add this as an isolated Firebase translation layer: DTOs and mappers will live under `VirtualTrainer/Repositories/Firebase/`, the path builder will throw sanitized repository errors, and the encoding helper will be the only place that touches `FieldValue.serverTimestamp()` without introducing any Firestore write calls.

### Assistant - 2026-05-14 13:41:05

The five Firebase-layer files are in place. I kept workout sets split from the compact workout document and used raw strings for enum fields so Firestore payloads stay stable and app models stay free of Firestore-specific types.

### Assistant - 2026-05-14 13:41:41

First compile pass found issues in the mapper file, so I’m narrowing the diagnostics instead of plowing ahead. This is exactly the kind of phase boundary where keeping the app compiling after the slice matters.

### Assistant - 2026-05-14 13:43:15

I’m adding the test slice now, including the acceptance checks around profile set sorting, compact workout size, set evidence order, trophy server timestamps, insight-delivery merge semantics, path rejection, privacy rejection, and a positive validator pass for a populated workout DTO.

### Assistant - 2026-05-14 13:44:56

The initial app build is green again after one mapper type fix. I’ve added ten test methods for the new layer and updated the existing Firebase-upload audit so it allows the encoding helper’s Firestore import but still catches any write APIs outside the debug smoke verifier.

### Assistant - 2026-05-14 13:46:59

Focused Firestore translation tests are green: ten new test methods passed. I’m doing a quick static audit now for accidental write APIs and forbidden DTO fields before I run the required full build and suite.

### Assistant - 2026-05-14 13:47:13

The static scan shows no new write APIs: only the existing debug smoke verifier still calls `setData`, and the new helper only imports `FirebaseFirestore` for `FieldValue`. The secret-like strings in tests are dynamically assembled so the validator is exercised without committing real-looking credentials.

### Assistant - 2026-05-14 13:47:38

Required build passes on the requested workspace/scheme/destination with XcodeDefault. I’m starting the required full test run now, sequentially on the same DerivedData path, so there’s no build database contention.

### Assistant - 2026-05-14 13:48:18

The full suite has built and is now in the simulator test phase. The only warning surfaced so far is a pre-existing `RunLoop.main.run` async-context warning in an unrelated workout-detail test file.

### Assistant - 2026-05-14 13:48:54

Still waiting on the simulator run; no failures have appeared in the stream. I’ll let it finish and then pull the actual pass/fail counts from the result rather than guessing from the live log.

### Assistant - 2026-05-14 13:49:14

Full verification is green: the result bundle reports `358` passed, `0` failed, `0` skipped. I’m running the repo secret scan next with redaction enabled, then I’ll do whitespace/status checks and add a debug-log entry because this phase changes backend behavior boundaries.

### Assistant - 2026-05-14 13:50:24

`git diff --check` is clean, and the fallback secret scan over changed and new non-ignored files found no findings. Since this phase adds the Firestore translation/privacy boundary, I’m appending `DL-050` now with the verification details.

### Assistant - 2026-05-14 13:51:54

I’ve got the Phase 16C work in place from the prior stretch. I’m doing the last housekeeping now: appending the audit log entry, re-running whitespace/status checks, then I’ll give you the build/test and privacy-scan summary cleanly.

### Assistant - 2026-05-14 13:52:15

The debug log entry is already present as DL-050 and the header now points at DL-051, so I’m treating that as completed. I’m re-running the final lightweight audits over the current diff, including the newly appended log entry, to avoid signing off on stale checks.

### Assistant - 2026-05-14 13:52:38

The first fallback scan command tripped over zsh’s read-only `$status` variable before it scanned anything. I’m rerunning the same check with a neutral variable name; the actual audit hasn’t produced findings yet.

### Assistant - 2026-05-14 13:53:30

Phase 16C is in place on `main`. Pre-flight started clean, targeted `main`, and the Xcode toolchain resolves under `XcodeDefault.xctoolchain`.

**Changed Files**
- [FirestoreDTOs.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Repositories/Firebase/FirestoreDTOs.swift>)
- [FirestoreMapper.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Repositories/Firebase/FirestoreMapper.swift>)
- [FirestorePathBuilder.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Repositories/Firebase/FirestorePathBuilder.swift>)
- [FirestorePrivacyValidator.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Repositories/Firebase/FirestorePrivacyValidator.swift>)
- [FirestoreEncodingHelpers.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Repositories/Firebase/FirestoreEncodingHelpers.swift>)
- [FirestoreTranslationLayerTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/FirestoreTranslationLayerTests.swift>)
- [WorkoutSummarySizeAuditTests.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainerTests/WorkoutSummarySizeAuditTests.swift:115>)
- [DEBUG_LOG.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/DEBUG_LOG.md:1399>)

**PR Description**
Added the isolated Firestore translation layer: DTOs, symmetric mappers, path builder, privacy validator, and a single encoding helper that injects `FieldValue.serverTimestamp()` placeholders without adding repository writes. The workout shape follows the compact document plus `sets` subcollection model, with counts for partial-load detection.

Key decision: I kept Firestore concerns out of app models and did not wire any repositories yet. Before this, a future sync implementation would have needed to hand-build dictionaries and paths, which is where raw frame data or oversized workout evidence could accidentally sneak in. After this, a real workout like “3 squat sets with cue and rep-quality events” maps to one compact workout summary plus per-set documents, and the payload is privacy-validated before any future `setData`.

Firebase console/manual steps: none for Phase 16C. No Firestore reads/writes were added. Future phases still need rules/indexes/App Check/manual Firebase setup before live remote sync.

Migration behavior: no local JSON migration. Existing local Codable models remain the source of truth, with safe defaults on mapper decode and backwards-compatible local mode behavior preserved. `BackendMode.local` and no-plist builds remain unaffected.

Known follow-ups: wire repositories in Phase 16D+, add security rules/index validation, and run live Firebase smoke tests once the write layer exists.

**Verification**
- Build: PASS
- Tests: PASS, 358 passed / 0 failed / 0 skipped
- Focused new Firestore tests: 10 passed
- `git diff --check`: PASS
- `gitleaks`: not installed; fallback scan over changed/new non-ignored files found no secret-like values
- Static write scan: no new `.setData`, `.updateData`, or `.addDocument` calls beyond the existing debug smoke verifier

No protected live camera pipeline files were touched.
