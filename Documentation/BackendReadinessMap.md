# Spotter Backend Readiness Map

Generated from the current Swift repository before changing sync models.

This is a documentation-only map. It does not add Firebase, repositories, model fields, or product behavior. It treats the current code as the source of truth and flags backend needs separately from what exists today.

## Inspection Scope

Read before writing this map:

- `README.md`
- `DEBUG_LOG.md`
- `VirtualTrainer/Models/UserProfile.swift`
- `VirtualTrainer/Models/WorkoutSessionSummary.swift`
- `VirtualTrainer/Models/WorkoutHistoryStore.swift`
- `VirtualTrainer/Models/TrophyModels.swift`
- `VirtualTrainer/Models/AIInsightModels.swift`
- `VirtualTrainer/Models/InsightStore.swift`
- `VirtualTrainer/Models/CalibrationRecord.swift`
- `VirtualTrainer/Models/CalibrationStore.swift`
- `VirtualTrainer/Models/ThemeStore.swift`
- `VirtualTrainer/Models/OnboardingStore.swift`
- `VirtualTrainer/Sharing/ShareCardRenderer.swift`
- `VirtualTrainer/UI/ProfileView.swift`
- `VirtualTrainer/UI/WorkoutDetailSheetView.swift`
- `VirtualTrainer/UI/TrophiesView.swift`
- all files under `VirtualTrainerTests/`

Additional files inspected for persistence and sync boundaries:

- `VirtualTrainer/VirtualTrainerApp.swift`
- `VirtualTrainer/UI/CameraTabView.swift`
- `VirtualTrainer/UI/PlannedWorkoutSessionView.swift`
- `VirtualTrainer/UI/CalibrationViews.swift`
- `VirtualTrainer/UI/HomeDashboardView.swift`
- `VirtualTrainer/UI/WorkoutPreviewView.swift`
- `VirtualTrainer/UI/WorkoutSummaryView.swift`
- `VirtualTrainer/Models/WorkoutEvidenceModels.swift`
- `VirtualTrainer/Models/WorkoutSessionContext.swift`
- `VirtualTrainer/Models/WorkoutData.swift`
- `VirtualTrainer/Models/PlanGenerationInput.swift`
- `VirtualTrainer/Models/TrainingTrendModels.swift`
- `VirtualTrainer/Models/WorkoutDetailEvidenceModel.swift`
- `VirtualTrainer/Models/StatsEngine.swift`
- `VirtualTrainer/Services/FeatureFlags.swift`
- `VirtualTrainer/Services/InsightRewriter.swift`
- `VirtualTrainer/Services/WeeklyRecapBuilder.swift`
- `VirtualTrainer/Services/WorkoutRecapBuilder.swift`

## Current Local Persistence

All product persistence currently uses local JSON files. The default base is:

```text
FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
  ?? FileManager.default.temporaryDirectory
```

Every runtime default appends `Spotter/` under that base.

JSON encode/write/remove work for the file-backed stores now routes through `PersistenceActor`, which preserves atomic writes and coalesces rapid same-file writes with a last-write-wins policy. Published state stays on the main actor; high-frequency save work is no longer coupled to UI-bound code paths where practical.

| Store | Runtime file path | Persisted payload | Encoder details | Notes |
|---|---|---|---|---|
| `OnboardingStore` | `<Application Support>/Spotter/UserProfile.json` | `UserProfile` | pretty printed, sorted keys, ISO-8601 dates | Created by onboarding and updated by profile preferences. `resetOnboarding()` hard-deletes the file. |
| `ThemeStore` | `<Application Support>/Spotter/Theme.json` | `ThemeEnvelope { selectedTheme }` | pretty printed, sorted keys | Also decodes legacy raw `SpotterThemeOption`. Duplicates `UserProfile.selectedTheme` for runtime theme bootstrapping. |
| `CalibrationStore` | `<Application Support>/Spotter/CalibrationRecord.json` | `CalibrationRecord` | pretty printed, sorted keys, ISO-8601 dates | Stores only the latest calibration status/record. `resetForDebug()` hard-deletes the file. |
| `WorkoutHistoryStore` | `<Application Support>/Spotter/WorkoutHistory.json` | `[WorkoutSessionSummary]` | pretty printed, sorted keys, ISO-8601 dates | Free Analysis and Planned Workout saves both land here. `addSummary` upserts by `id`; delete/update/tombstone APIs keep default UI queries on active summaries. |
| `TrophyStore` | `<Application Support>/Spotter/TrophyProgress.json` | `TrophyProgressSnapshot` | pretty printed, sorted keys, ISO-8601 dates | Snapshot is derived from workout history and calibration. Persisted snapshot strips `newlyEarnedEvents`. |
| `InsightStore` | `<Application Support>/Spotter/CoachInsights.json` | `PersistedInsightStoreSnapshot` | pretty printed, sorted keys, ISO-8601 dates | Stores recent insights, delivery cooldowns, and engagement records. |
| `LocalWriteJournal` | `<Application Support>/Spotter/LocalWriteJournal.json` | `[LocalWriteJournalEntry]` | pretty printed, sorted keys, ISO-8601 dates | Tracks completed local operation IDs so future retry paths do not double-apply the same user action. |

Preview/test-only persistence uses temporary directories, for example `ProfilePreviewStores` in `ProfileView` and test fixtures. `ShareCardRenderer` renders a local `UIImage` from aggregate heatmap data and does not write an image file.

No current runtime persistence writes raw video, camera frames, face images, raw pose streams, raw biometric face data, or raw pose timelines.

## C3 Tombstone Preparation Implemented

C3 adds local-only soft-delete preparation without adding a backend SDK, repositories, `accountId`, `SyncMetadata`, or write-operation models.

- `UserProfile`, `WorkoutSessionSummary`, `AIInsight`, and `CalibrationRecord` now decode optional `deletedAt` safely when older JSON omits it.
- `WorkoutHistoryStore` keeps an internal all-record source of truth, publishes only non-deleted summaries to existing SwiftUI surfaces, persists tombstones in `WorkoutHistory.json`, and exposes sync/debug queries that include deleted records.
- Workout delete actions mark summaries deleted, hide them from default history/stats/dashboard/profile queries, and invalidate generated insights whose evidence references the deleted workout.
- `InsightDeliveryRecord` and `InsightEngagementRecord` are intentionally preserved when an insight is invalidated.
- Trophy progress can be recomputed from the visible workout projection, but already-earned trophy state is not retracted in this phase. Canonical unlock events and any admin/debug retraction semantics remain deferred to C6.
- `CalibrationStore.resetForDebug()` remains a debug hard reset. Tombstoned calibration records are not treated as completed if encountered in persisted local JSON.

## Current Schema Versions

| Area | Current version marker | Current value | Migration behavior |
|---|---:|---:|---|
| Onboarding schema | `UserProfile.currentOnboardingSchemaVersion` | `2` | Missing version decodes to current value. |
| Profile schema | `UserProfile.currentProfileSchemaVersion` | `2` | Missing version decodes to current value. |
| Workout summary schema | `WorkoutSessionSummary.currentSchemaVersion` | `2` | Missing `summarySchemaVersion` decodes as `1`. |
| Trophy catalog | `TrophyDefinitionCatalog.version` | `1` | Persisted snapshots carry `catalogVersion`; duplicate progress entries are merged during lookup. |
| Insight source policy | `AIInsight.currentSourcePolicyVersion` | `phase14.local.deterministic.v1` | Load filters out insights with old source policy or empty evidence. |
| Theme file | none | none | Decodes either `ThemeEnvelope` or legacy raw `SpotterThemeOption`. |
| Calibration record | none | none | No custom backwards-compatible decoder yet. |
| Insight snapshot schema | none | none | Missing `engagementRecords` decodes as an empty array. |

## Backwards-Compatible Decoding Already Present

- `UserProfile` defaults missing `limitations`, `preferredSessionLength`, `workoutDaysPerWeek`, `reminderPreference`, `timezoneIdentifier`, `avatarStyle`, and schema versions.
- `WorkoutSessionSummary` defaults missing `id`, `summarySchemaVersion`, `workoutOutcome`, `structuredEffortSummary`, evidence totals, and `createdAt`.
- `ExerciseSetSummary` defaults missing cue events, rest/skipped flags, rep-quality events, completion source, set duration, effort, best cue, and worst cue.
- `CueEvent` defaults missing `id`.
- `PersistedInsightStoreSnapshot` defaults missing `engagementRecords` to `[]`.
- `ThemeStore` supports both current envelope and legacy raw enum storage.
- `TrophyProgressSnapshot.progressByTrophyId` resolves duplicate persisted progress entries without crashing and preserves earned progress preferentially.

## Syncable Models

| Model | Current persistence | Sync readiness | Notes |
|---|---|---|---|
| `UserProfile` | `UserProfile.json` | Must sync | Contains PII and user preferences. Needs account ownership and conflict policy before backend. |
| `SpotterThemeOption` / `ThemeEnvelope` | `Theme.json` | Should sync or fold into profile | Current theme is also on `UserProfile.selectedTheme`; decide whether separate theme document remains necessary. |
| `CalibrationRecord` | `CalibrationRecord.json` | Should sync | Current app stores latest record only. A backend may prefer `calibration/current` plus optional attempts history. |
| `WorkoutSessionSummary` | `WorkoutHistory.json` | Must sync | Primary training record. Contains derived evidence only, not raw camera or pose streams. |
| `ExerciseSetSummary` | nested in workout summaries | Must sync with workout | Candidate for embedding unless Firestore document-size audit says to split. |
| `CueEvent` | nested in set summaries | Must sync with workout | Derived cue event, not raw landmarks. |
| `RepQualityEvent` | nested in set summaries | Must sync with workout | Derived per-rep quality evidence. |
| `SetQualitySummary` | nested in set summaries | Must sync or recompute | Small derived aggregate; useful to store for stable recaps/details. |
| `StructuredEffortSummary` | nested in workout summaries | Must sync with workout if present | Derived face-blendshape effort proxy. Do not sync raw blendshapes or face data. |
| `TrophyProgressSnapshot` | `TrophyProgress.json` | Sync decision needed | Current snapshot is derived locally. Backend should either merge snapshots or use trophy event log as canonical source. |
| `TrophyProgress` | nested in trophy snapshot | Sync decision needed | Derived per trophy. If synced directly, needs conflict rules. |
| `TrophyUnlockEvent` | transient in snapshot, not persisted after reload | Sync decision needed | Better as append-only event collection if server needs canonical `earnedAt`. |
| `AIInsight` | `CoachInsights.json` | Should sync if multi-device insight continuity matters | Already has `dedupeKey`, `createdAt`, `expiresAt`, `sourcePolicyVersion`, and evidence refs. |
| `InsightEvidence` | nested in `AIInsight` and recaps | Sync with insight/recap | Derived references back to saved workouts, exercises, sets, reps, or signals. |
| `InsightDeliveryRecord` | `CoachInsights.json` | Sync decision needed | Controls cooldowns per surface. Device-local is simpler; sync gives better cross-device UX. |
| `InsightEngagementRecord` | `CoachInsights.json` | Sync decision needed | Helpful/not-helpful/dismissed/opened signals affect ranking. |
| `WorkoutPlanV2` | Codable but not currently persisted | Future sync candidate | Generated and edited plans are currently in-memory. Do not add a plan backend until a product need exists. |
| `QuickStartDeck` / `QuickStartPlanVariant` | Codable but not currently persisted | Usually do not sync | Deterministic local generation can recreate decks from profile, date, and generation version. |
| `WeeklyRecap` | Codable but not currently persisted | Usually do not sync | Built deterministically from workouts/trophies/profile; dedupe currently uses `InsightStore` delivery records. |
| `UserTrainingTrendSnapshot`, `UserTrainingSignal`, `WorkoutCalendarSnapshot` | Codable but not currently persisted | Prefer recompute locally first | Derived caches can be added later if performance requires it. |
| `UserStats`, `WorkoutRecap` | Not Codable and not persisted | Do not sync as source of truth | Derived from saved summaries/trophies. |

## Backend Field Needs

These are needs for the future sync phase, not fields that exist today.

| Model/document | Needs `accountId` | Needs `deletedAt` | Needs `SyncMetadata` | Why |
|---|---:|---:|---:|---|
| `UserProfile` | Yes | Yes | Yes | Account-owned PII/preferences; reset/account deletion must not resurrect across devices. |
| Theme preference | Yes, if separate from profile | Usually no | Yes, if separate | Safer to fold into `UserProfile` unless the design system needs a separate preferences document. |
| `CalibrationRecord` | Yes | Yes or superseded-at | Yes | Reset/failed/completed status should sync; decide single current record versus attempts collection. |
| `WorkoutSessionSummary` | Yes | Yes | Yes | User-created history needs ownership, offline dirty state, and tombstones for delete/edit. |
| `ExerciseSetSummary` | Inherited from workout | Inherited from workout | Inherited from workout or per set if split | Only needs its own metadata if stored as a subcollection. |
| `CueEvent` | Inherited from workout | Inherited from workout | Usually no | Derived evidence; no independent lifecycle today. |
| `RepQualityEvent` | Inherited from workout | Inherited from workout | Usually no | Derived evidence; no independent lifecycle today. |
| `TrophyProgressSnapshot` | Yes, if synced | Usually no | Yes, if synced | Snapshot is derived; conflict resolution is more important than tombstones. |
| `TrophyProgress` | Inherited from trophy snapshot/account | Prefer no; use derived recompute or retraction event | Yes, if synced directly | Avoid blind soft-deletes on derived state; event log is safer. |
| `TrophyUnlockEvent` | Yes, if persisted remotely | Prefer `revokedAt`/`retractedAt` over `deletedAt` | Yes | Append-only event semantics are better for awards than mutable deletion. |
| `AIInsight` | Yes | Yes or `expiresAt`/invalidated-at | Yes | Existing `expiresAt` handles natural expiry; explicit invalidation still needs a tombstone-like field if synced. |
| `InsightDeliveryRecord` | Yes | Usually no, TTL instead | Yes | Dedupe/cooldown record keyed by insight `dedupeKey`; can expire by TTL. |
| `InsightEngagementRecord` | Yes | Usually no | Yes | Tiny mergeable counters/dates; no current deletion lifecycle. |
| `WorkoutPlanV2` | Yes, if persisted | Yes, if persisted | Yes, if persisted | Current app does not persist plans; add only with saved plan/session draft product scope. |

Recommended `SyncMetadata` shape to decide before Phase 15:

```swift
struct SyncMetadata: Codable, Equatable {
    var localUpdatedAt: Date
    var lastSyncedAt: Date?
    var serverVersion: String?
    var syncState: SyncState
    var pendingOperationId: UUID?
}
```

The exact names can change, but the repository layer needs local dirty state, server acknowledgement state, a conflict/version token, and an idempotency key.

## Writes That Need `operationId`

Every backend-mode write should carry an idempotency key. Current local methods do not accept one.

| Current write | Current method/path | Operation id needed before backend |
|---|---|---|
| Create profile | `OnboardingStore.completeOnboarding()` | Yes |
| Update training preferences | `OnboardingStore.updateTrainingPreferences(...)` | Yes |
| Update goal | `OnboardingStore.updatePrimaryGoal(_:)` | Yes |
| Update preferred coach | `OnboardingStore.updatePreferredCoach(_:)` | Yes |
| Update selected theme in profile | `OnboardingStore.updateSelectedTheme(_:)` | Yes |
| Update session length | `OnboardingStore.updatePreferredSessionLength(_:)` | Yes |
| Reset onboarding/account data | `OnboardingStore.resetOnboarding()` | Yes, but should become non-debug account deletion/reset flow |
| Update standalone theme file | `ThemeStore.updateSelectedTheme(_:)` / `sync(with:)` | Yes if separate theme doc remains |
| Save calibration completion | `CalibrationStore.saveCompleted(...)` | Yes |
| Save calibration skip | `CalibrationStore.saveSkipped(...)` | Yes |
| Save calibration failure | `CalibrationStore.saveFailed(...)` | Yes |
| Reset calibration | `CalibrationStore.resetForDebug()` | Yes if exposed outside debug; tombstone/supersede preferred |
| Save free-analysis summary | `WorkoutHistoryStore.addSummary(_:)` via `CameraTabView.saveSummary()` | Yes |
| Save planned-workout summary | `WorkoutHistoryStore.addSummary(_:)` via `PlannedWorkoutSessionView.saveHistorySummaryIfNeeded()` | Yes |
| Trophy recompute/persist | `TrophyStore.update(...)` / `updateAll(...)` | Yes if writing remote snapshot or events |
| Clear latest unlock events | `TrophyStore.clearLatestUnlockEvents()` | Local UI-only today; probably no remote operation |
| Ingest/select insights | `InsightStore.selectInsights(...)` / `selectGeneratedInsights(...)` | Yes if generated insights are synced |
| Record impression | `InsightStore.recordImpression(...)` | Yes if delivery records sync |
| Record presentation by key | `InsightStore.recordPresentation(...)` | Yes if delivery records sync |
| Record engagement | `InsightStore.recordEngagement(...)` | Yes if engagement records sync |
| Clear insights for debug | `InsightStore.clearForDebug()` | Debug-only; should not become a production remote write without explicit product flow |

## Current Store APIs And Missing APIs

### `OnboardingStore`

Current public methods:

- `canContinue(from:)`
- `updateHeightUnit(_:)`
- `updateWeightUnit(_:)`
- `toggleEquipment(_:)`
- `toggleLimitation(_:)`
- `completeOnboarding()`
- `updateTrainingPreferences(...)`
- `resetOnboarding()`
- `updatePrimaryGoal(_:)`
- `updatePreferredCoach(_:)`
- `updateSelectedTheme(_:)`
- `updatePreferredSessionLength(_:)`

Missing before backend:

- Account-scoped load/save.
- Explicit production account deletion path separate from debug reset.
- Export/import representation.
- Conflict resolver for profile/preferences.
- Operation-id-aware write API.

### `ThemeStore`

Current public methods:

- `updateSelectedTheme(_:)`
- `sync(with:)`
- `reload()`

Missing before backend:

- Decision whether this remains a separate sync document or folds into profile.
- Account-scoped write if separate.
- Operation-id-aware write if separate.

### `CalibrationStore`

Current public methods:

- `loadStatus()`
- `saveCompleted(_:)`
- `saveCompleted(...)`
- `saveSkipped(...)`
- `saveFailed(_:)`
- `saveFailed(...)`
- `resetForDebug()`

Missing before backend:

- Non-debug delete/reset/supersede semantics.
- Optional calibration attempts history.
- Account-scoped current record.
- Operation-id-aware write API.

### `WorkoutHistoryStore`

Current public methods:

- `addSummary(_:)`
- `fetchRecentSummaries(limit:)`
- `fetchSummary(id:)`
- `aggregateStats(now:)`
- `recentWorkoutHistoryItems(limit:)`
- `reload()`

Missing before backend:

- `updateSummary` for future edits.
- `deleteSummary` / `restoreSummary` soft-delete.
- Query including tombstones for sync.
- Query by `updatedAt`/dirty state.
- Bulk import/merge from remote.
- Account-scoped filtering.
- Operation-id-aware write API.
- Background persistence path for large histories.

### `TrophyStore` / `TrophyEngine`

Current public methods:

- `TrophyEngine.update(after:history:calibrationStatus:previousSnapshot:now:)`
- `TrophyEngine.updateAll(history:calibrationStatus:previousSnapshot:now:)`
- `TrophyStore.update(after:history:calibrationStatus:now:)`
- `TrophyStore.updateAll(history:calibrationStatus:now:)`
- `TrophyStore.clearLatestUnlockEvents()`
- `TrophyStore.reload()`

Missing before backend:

- Canonical trophy sync decision: derived snapshot merge versus append-only trophy events.
- Cross-device `earnedAt` merge policy.
- Retraction/recompute policy for deleted workouts.
- Account-scoped snapshot/events.
- Operation-id-aware remote write if trophies sync.

### `InsightStore`

Current public methods:

- `selectInsights(_:for:profile:limit:now:)`
- `selectGeneratedInsights(_:for:profile:limit:now:)`
- `insights(for:profile:limit:now:)`
- `deliveryRecord(for:)`
- `engagementRecord(for:)`
- `engagementRecordsSnapshot()`
- `canPresentOnce(dedupeKey:on:)`
- `recordImpression(_:on:now:)`
- `recordPresentation(dedupeKey:on:now:)`
- `recordEngagement(_:kind:now:)`
- `clearForDebug()`

Missing before backend:

- Deliberate sync-vs-device-local decision for delivery and engagement.
- Remote merge rules for delivery records and engagement counters.
- Explicit invalidation/TTL cleanup API.
- Account-scoped insight query.
- Operation-id-aware write API for impression/engagement writes.

### Plans

Current state:

- `PlanService`, `PlanGenerator`, and `QuickStartPlanDeckService` generate deterministic local plans.
- `WorkoutPreviewState` supports local plan edits before launch.
- There is no current `PlanStore` or persisted plan file.

Missing before backend only if product scope requires saved plans:

- Plan repository/local store.
- Save/delete/tombstone semantics.
- Draft-vs-started-session lifecycle.
- Conflict policy for edited plan targets.

## Privacy Boundary

Current code and README agree on the local-first privacy boundary:

- Good to store/sync later: profile/preferences, calibration status, generated/edited plan metadata if productized, workout summaries, set summaries, rep-quality events, cue events, rest behavior, derived effort summaries, trophies, stats/trends/signals, heatmap day aggregates, recaps, insight delivery/engagement records, and theme selection.
- Do not store or upload: raw video, camera frames, face images, raw pose streams, raw biometric face data, raw pose timelines.
- `WorkoutSessionSummary` stores derived evidence only. `StructuredEffortSummary` and `RepQualityEvent.effortAtRep` are derived effort proxies, not raw face data.
- `ShareCardRenderer` uses aggregate heatmap summaries and profile display name to render a local image. It does not persist or upload that image.
- Future LLM rewrite context from `AIInsight.toLLMContext()` is derived/codable and should stay behind the default-off feature flag unless a backend privacy review explicitly allows it.
- Secrets must not ship in the iOS client. README specifically calls out OpenAI, ElevenLabs, Firebase private keys, Supabase service-role keys, and similar credentials.

## Proposed Firestore Shape

Keep this local-first until the Firebase phase explicitly begins.

```text
users/{accountId}
  profile/current
  preferences/theme                # optional; may be folded into profile
  calibration/current              # or calibrationRecords/{recordId}
  workouts/{workoutId}
    sets/{setId}                   # only if document-size audit says not to embed
      repQualityEvents/{eventId}   # only if split is needed
      cueEvents/{eventId}          # only if split is needed
  trophyProgress/current           # if syncing snapshots
  trophyEvents/{eventId}           # preferred if trophies need canonical earnedAt history
  insights/{insightId}
  insightDelivery/{dedupeKey}
  insightEngagement/{dedupeKey}
  plans/{planId}                   # only if saved plans become product scope
  syncOperations/{operationId}      # idempotency / TTL write ledger
```

Recommended first pass:

- Put `UserProfile` either in `users/{accountId}/profile/current` or directly on `users/{accountId}` with a private profile map. Choose one and keep security rules simple.
- Embed workout set evidence inside `workouts/{workoutId}` until a measured worst-case summary approaches Firestore document-size limits.
- Prefer recomputing stats, trends, heatmap, workout recaps, and weekly recaps on-device from synced workouts/trophies/profile instead of syncing them as source-of-truth documents.
- Treat Quick Start decks as deterministic local outputs and do not sync them unless the product adds saved plan history.

## Open Decisions Before Firebase

1. Account identity: exact `accountId` naming, anonymous auth upgrade path, and whether local UUIDs remain entity ids only.
2. Repository phase: add protocols and local repositories before importing Firebase SDKs.
3. Sync metadata: choose `SyncMetadata` fields, conflict state naming, and dirty-record query behavior.
4. Tombstones: decide per model between `deletedAt`, TTL expiry, `supersededAt`, or event retraction.
5. Idempotency: define `operationId` creation, local retry behavior, and remote `syncOperations` TTL policy.
6. Workout delete/edit: add local APIs before remote sync so deletes cannot be resurrected.
7. Workout document shape: measure worst-case `WorkoutSessionSummary` size and choose embedded evidence versus subcollections.
8. Trophy sync: derived snapshot merge versus canonical append-only trophy events.
9. Insight sync: decide whether delivery cooldowns and engagement records are cross-device or device-local.
10. Theme sync: decide whether `Theme.json` remains separate or profile `selectedTheme` becomes the only remote source.
11. Calibration sync: decide latest-only record versus attempts collection.
12. Plans: decide whether generated/edited plans are persisted remotely or remain deterministic local runtime state.
13. Server timestamps: decide which fields become server-authoritative in backend mode, especially workout end times and trophy earned times.
14. Timezone: use `UserProfile.timezoneIdentifier` consistently for streak/weekly recap calculations across devices.
15. Repository I/O scaling: local JSON encode/write work is actor-isolated now; repository actors should still add pagination, listener backpressure, and remote-history batching before large backend histories.
16. PII/export/delete: create PII inventory, data export, and account deletion flows before shipping account creation.
17. Security rules/App Check: design Firestore rules around `accountId == request.auth.uid` and add App Check before broader testing.
18. Secrets/config: keep private keys out of source; decide dev/beta/prod Firebase config handling.
19. Release gating: debug reset/clear methods should not become production remote deletion controls by accident.

## Current Test Surface

The repository currently has 28 XCTest files with 252 `func test...` methods.

Relevant persistence/backwards-compatibility coverage already exists:

- `OnboardingModelTests`: legacy profile decoding, profile preference persistence, theme persistence, failed theme write rollback.
- `CalibrationStoreTests`: completed/skipped/failed calibration persistence, validation rejection, calibration not polluting workout history.
- `WorkoutHistoryStoreTests`: planned/free-analysis saves, sort order, Codable round trip, legacy summary decoding, evidence defaults, createdAt defaulting, rep-quality round trip, aggregate stats, duplicate planned-save upsert, failed-save rollback.
- `TrophyEngineTests`: deterministic trophy progress, one-time unlock events, persisted progress reload, duplicate persisted progress merging, coming-soon states.
- `InsightStoreTests`: selection does not consume cooldown, impression cooldown, important insight bypass, current generated insights over older stored insights, engagement persistence, legacy snapshot without engagement records.
- `WorkoutPlanV2Tests` and `PlanGeneratorTests`: generated and mixed-target plan Codable round trips.

No tests were added for this phase because this change only adds documentation and no documentation helper code.
