# Spotter — Pre-Backend Readiness Review

**Author:** Founder coach review (Phase 15 / Phase 16 prep)
**Scope:**
1. Re-evaluate the updated code state (post-integration of the previous review's prompts).
2. Audit it against backend-integration readiness, end-to-end.
3. Read GPT-5.5-Pro's Phase 15 (backend abstraction) and Phase 16 (Firebase) prompts in full and tell you whether they're sufficient or where they need editing.
4. Produce the punch list and the rewritten Codex prompts.

---

## Part A — What actually shipped from the last evaluation

I read every file the README referenced. Here's the honest accounting against the 17 prompts in `Spotter_Phase1_2_Evaluation.md`:

| # | Prompt | Shipped? | Evidence |
|---|---|---|---|
| 1.A | Impression-based delivery + engagement + safety bypass | ✅ Done | `InsightStore.recordImpression`, `recordEngagement`, `wasRecentlyPresented` returns `false` for `severity == .important`; engagement weights live in `InsightRanker.engagementScore` |
| 1.B | Kill placeholder, ship `WorkoutRecap` | ✅ Done | `Services/WorkoutRecapBuilder.swift` exists with `WorkoutRecap` struct + tests |
| 1.C | Single `CueNormalizer` + `CueClusterTaxonomy` | ✅ Done | Both files exist; tests exist |
| 1.D | Bootstrap signals for sessions 1–5 | ✅ Done | `SignalGenerationContext`, signal types `firstSession`, `setupQuality`, `repCleanlinessIntro`, `repeatExerciseProgress`, `personalBaseline` (per README) |
| 1.E | `TrendWindowPolicy` time-decay | ✅ Done | `Models/TrendWindowPolicy.swift` exists |
| 1.F | Rich evidence in `WorkoutDetailSheetView` | ✅ Done | `WorkoutDetailEvidenceModel` exists, sparkline + badges per README + tests |
| 1.G | **Coach-personality-aware narratives** | ❌ **Not shipped.** `toLLMContext` accepts `coachPersonality`, but `InsightNarrativeBuilder` produces a single voice. No `CoachNarrative` / `CoachVoice` helper exists. |
| 1.H | Goal-aware ranking + evidence sheet + weekly recap | ✅ Done | `InsightRanker.goalAlignmentScore` + `goalSignalScore`, `InsightEvidenceSheetView`, `WeeklyRecapBuilder` |
| 1.I | LLM rewrite seam | ✅ Done | `InsightRewriter`, `NoopInsightRewriter`, `RewriteValidator`, `FeatureFlag.coachInsightLLMRewrite`, `AIInsight.toLLMContext()` |
| 2.A | Trophy / recap / collection share cards + share button enabled | ⚠️ **Partial.** Only the **training heatmap poster** ships in `ShareCardRenderer.swift`. Trophy unlock card, workout recap card, and trophy collection poster are not built; the "Share Collection" button in `TrophiesView` is still `.disabled(true).opacity(0.45)`. |
| 2.B | Trophy unlock celebration (confetti, haptic ladder, sound, replay) | ❌ **Not shipped** |
| 2.C | Personal Records system + "Best of you" tile | ❌ Deferred (you've explicitly chosen post-backend) |
| 2.D | Streak Freeze + Streak Milestones | ❌ **Not shipped** |
| 2.E | Trophy library expansion | ❌ Deferred (you've explicitly chosen post-backend) |
| 2.F | 12-week heatmap + day drill-in | ✅ Done |
| 2.G | **Workout edit/delete + filtering + redo** | ❌ **Not shipped.** No `removeSummary`, no `updateSummary`, no `deleteWorkout`. |
| 2.H | Named levels + better XP curve + remote trophy catalog | ❌ **Not shipped** |

**This matters for backend.** Of the seven items not shipped, three are **direct backend-integration blockers** (1.G nice-to-have aside): `2.G` (delete), `2.H` (remote-loadable catalog architecture), and `2.A` (share path that needs a stable identity). I'll flag them again in Part C.

---

## Part B — What I see in the updated code that's strong

Before the gaps, give yourself credit:

1. **`InsightStore` separation of concerns is clean.** `selectInsights` (data fetch) is fully decoupled from `recordImpression` / `recordEngagement` (UI side-effects). The `wasRecentlyPresented` short-circuit on `.important` severity is exactly right. `bestInsightsByDedupeKey` correctly invalidates older `sourcePolicyVersion` entries.
2. **`InsightRanker` is profile-aware now.** `goalAlignmentScore` returns +10 / +3 / 0 by goal-match, `goalSignalScore` adds per-goal signal weights, and `engagementScore` reads helpful/notHelpful/dismissed from `InsightEngagementRecord`. Good shape for a future server-rerank.
3. **`InsightEngine` async overloads are clean.** Every public surface has a sync deterministic path AND an async variant that runs `rewriteIfNeeded`. The `RewriteValidator.canAdopt` requires the rewrite to (a) actually change something, (b) cover the exercise, (c) cover the recommended action verb, (d) cover at least one evidence anchor. That's stricter than most LLM safety wrappers I've seen.
4. **`InsightLLMContext` includes `sanitizationBlocklist`.** Future server-side or local LLM caller can self-check.
5. **`PersistedInsightStoreSnapshot` decodes `engagementRecords` with `decodeIfPresent`.** Forward-compatible.
6. **Schema versioning hygiene is consistent.** `UserProfile.currentProfileSchemaVersion = 2`, `WorkoutSessionSummary.currentSchemaVersion = 2`, `AIInsight.currentSourcePolicyVersion = "phase14.local.deterministic.v1"`, `TrophyDefinitionCatalog.version = 1`. All four use `decodeIfPresent` defaults.
7. **All persistence uses `[.atomic]` writes** with `[.prettyPrinted, .sortedKeys]` and `iso8601` dates. JSON is diff-friendly and round-trip stable.
8. **Privacy boundary is explicit in code AND README.** No raw frames stored.
9. **`nonisolated`** is used consistently for all stateless engines, signals, builders, rankers, and rewriters — Swift 6 strict concurrency ready.
10. **Test surface is broad.** 28 test files. New stuff (`CueNormalizerTests`, `CueClusterTaxonomyTests`, `WorkoutRecapBuilderTests`, `WeeklyRecapBuilderTests`, `InsightStoreTests`, `InsightRankerTests`, `WorkoutDetailEvidenceModelTests`, `InsightEvidenceSheetSnapshotTests`) is all there.

This is a more disciplined codebase than 95% of what you'd see at this stage. The bones are right.

---

## Part C — Backend-readiness audit (the actual question)

I evaluated every Spotter store and model against what backend integration will actually need on day one. **There are eleven concrete items I would close before you write a single line of repository / Firebase code.** I've grouped them by severity.

> **C-prefix = Critical. H-prefix = High. M-prefix = Medium.** Each has a Codex-ready prompt at the end of this part.

### C-1 — Add an `accountId` on the ownership models, separate from local entity IDs

**The bug.** Every persisted entity in Spotter today (`UserProfile.id`, `WorkoutSessionSummary.id`, `TrophyProgress.trophyId`, `CalibrationRecord`, `AIInsight.id`) is identified by local UUIDs or stable string keys. None of them carry an `accountId` (or `userId`) that a backend can use as a partition key.

**Why it matters.** When you add Firebase auth (anonymous or Sign-in-with-Apple), the user gets a `uid`. Firestore's path is `users/{uid}/workouts/{workoutId}` — Firestore needs to know whose workout this is on the wire. If the model itself doesn't carry `accountId`, then:
- You can't multi-account on the same device (testing, family share later).
- You can't safely export/import data between accounts.
- You can't distinguish "anonymous local data" from "data already synced under uid X" on first sign-in.

**Fix.** Every persisted ownership-bearing model gains `accountId: String?` (nullable for local-only). Stores filter by `accountId` when one is set. The repository layer fills it in on save.

### C-2 — Add sync metadata to all syncable entities

**The bug.** No model has `lastSyncedAt`, `serverVersion` (ETag-style), `localUpdatedAt`, or `syncState`. When two devices race to update the same `UserProfile`, you have no way to detect or resolve the conflict.

**Why it matters.** This is the single hardest problem in offline-first sync. You either solve it correctly day one or you spend six months untangling cases like:
- User edits goal on iPhone (offline), opens iPad (which had stale goal), edits goal on iPad → which wins?
- Trophy snapshot on iPhone is recomputed locally and pushed to server; same on iPad. Server gets both. Which trophy `earnedAt` is canonical?
- Workout summary saves while offline, queue replays on reconnect, but the server already has it from a prior sync — must not double-write.

**Fix.** Add a `SyncMetadata` value type with:
```swift
struct SyncMetadata: Codable, Equatable {
    var localUpdatedAt: Date
    var lastSyncedAt: Date?      // server-confirmed write timestamp
    var serverVersion: String?   // ETag / Firestore doc updateTime
    var syncState: SyncState     // .localOnly, .pendingUpload, .synced, .conflict
    var pendingOperationId: UUID?  // idempotency key
}
```
Embed it on `UserProfile`, `WorkoutSessionSummary`, `TrophyProgressSnapshot`, `CalibrationRecord`, `AIInsight`, `OnboardingStore` payload, and the in-memory cooldown / engagement records. Repositories use `localUpdatedAt > lastSyncedAt` to detect dirty rows; conflicts go through a documented resolver per type (last-write-wins for profile/preferences; merge-on-derived for trophies/insights).

### C-3 — Tombstones and `deleteWorkout` (also blocks Phase 2.G feature)

**The bug.** `WorkoutHistoryStore` has no `removeSummary` or `updateSummary`. The Phase 15 prompt declares `WorkoutRepository.deleteWorkout` but the underlying store can't do it. Same in TrophyStore — there's no way to retract an erroneous trophy unlock event.

**Why it matters.** A delete that only removes from local but doesn't tombstone will be undone the next time another device syncs back. Soft-delete with tombstones (`deletedAt`, retained for N days, then hard-purged) is the only safe pattern for offline-first.

**Fix.** Add `deletedAt: Date?` to `WorkoutSessionSummary`, `UserProfile` (account-deletion path), `TrophyProgress`, `AIInsight`. Add `WorkoutHistoryStore.deleteSummary(id:)` that sets `deletedAt = Date()` and persists; `summaries` filter out `deletedAt != nil` for default queries; `repositoriesSeeAllForSync(includingTombstones: true)` is what the Firestore sync uses. After 30 days, a vacuum pass purges tombstones.

### C-4 — Idempotency keys for writes

**The bug.** No write currently carries an `operationId`. If a save fails mid-way (network drop), the retry might double-write.

**Why it matters.** Firestore writes are idempotent if you use `set` on the same docId, BUT for `add` semantics (e.g., "create a new workout") the docId is the key — and if you use `UUID()` regeneration on retry, you'll get duplicates. Also, your local ack flow (`addSummary` returns Bool) currently rolls back on failure — but doesn't dedupe a partial-success / partial-failure split between local file and server.

**Fix.** Every write through a repository carries an `operationId: UUID`. Local persistence treats `(entityId, operationId)` as the dedupe key. Server treats `operationId` as a unique-write token in a Firestore `_writes/{opId}` doc with TTL.

### C-5 — Off-main persistence

**The bug.** `WorkoutHistoryStore.persist`, `TrophyStore.persist`, `InsightStore.persist`, `OnboardingStore.save`, `CalibrationStore.persist` — all five run on `@MainActor`. With 200+ workout summaries (each with rep events), a save can stutter the UI for hundreds of milliseconds. Once you add Firestore, every write also fans out to network on the same actor.

**Why it matters.** UX degrades fast under real-world history sizes. Sync code must not block the main actor.

**Fix.** Two-step:
1. Refactor the sync-IO part of every store to a `nonisolated` helper that does the encode + write on a background queue, with an `await` on the main actor only to flip `@Published` state after a successful write.
2. Define a `RepositoryActor` (Swift `actor`) that owns I/O for each repository. The MainActor-bound store reads its `@Published` state from a publisher pipe out of the actor.

### C-6 — Append-only event log for trophies and PRs (decision needed before sync)

**The bug.** `TrophyEngine` is pure-derived: it recomputes everything from `[WorkoutSessionSummary]` on every change. `TrophyProgressSnapshot.merge()` preserves `earnedAt` from the previous snapshot but ONLY locally. Two devices computing the same snapshot independently will diverge on `earnedAt` (the device that triggered the unlock first wins on its own clock; the other device sees the unlock at a different timestamp).

**Why it matters.** You have a decision to make NOW, not after Firebase is wired:
- **Option A:** Snapshot is server-of-truth. Each device pushes its computed snapshot; server merges with `min(earnedAt)` per trophy. Trophy unlock event is non-canonical.
- **Option B:** Trophy unlock events are an append-only log under `users/{uid}/trophyEvents/{eventId}`. Snapshot is purely derived from the log. `earnedAt` is `serverTimestamp()` of the first matching event. This is more durable and gives you a real audit trail that could later power "On April 12, you unlocked 7-Day Inferno" stories.

I recommend Option B. Either way, document the decision in code BEFORE Phase 15.

### C-7 — Server-authoritative timestamps for ratchet metrics

**The bug.** `Date()` is used everywhere. A user can set their phone clock back to claim a streak day they didn't actually do.

**Why it matters.** Trophies, streaks, and PRs are exactly the surface where time-based cheating shows up. Clock skew also affects multi-device sync.

**Fix.** When backend mode is on, use `serverTimestamp()` for: `TrophyUnlockEvent.earnedAt`, `WorkoutSessionSummary.endedAt`, `PersonalRecord.achievedAt` (for the Phase-2 PR system you're deferring). Local-mode falls back to `Date()` but the local timestamp is always overwritten by the server timestamp on first successful sync. This is exactly Firestore's `FieldValue.serverTimestamp()` model.

### C-8 — Firestore document-size and shape audit

**The bug.** `WorkoutSessionSummary` embeds `[ExerciseSetSummary]` which embeds `[CueEvent]` and `[RepQualityEvent]`. A 30-minute high-tempo session can produce 60+ rep quality events and 20+ cue events per set. Firestore's max doc size is 1 MB. You're probably fine in absolute terms, but you should measure.

**Why it matters.** GPT's Phase 16 prompt suggests `users/{uid}/workouts/{workoutId}/sets/{setId}` paths — meaning sets become a subcollection. The current model embeds them. Decision needed.

**Fix.** Generate a synthetic worst-case workout (8 exercises × 4 sets × 25 reps × 4 cue events per rep), encode it with the current `JSONEncoder`, measure size. If it's under ~256 KB, embed sets. Above that, flatten sets into a subcollection (one Firestore doc per set) and rep events into a sub-subcollection (or denormalize to top-level rep_events). Either way, decide once, encode the decision in `FirestoreWorkoutRepository`, document it.

### C-9 — Engagement / impression / cooldown sync semantics

**The bug.** `InsightDeliveryRecord` (cooldowns) and `InsightEngagementRecord` (helpful/notHelpful) are private engagement signals. They're persisted in `CoachInsights.json`. Phase 15 prompt's `InsightRepository` only mentions `saveInsights` / `loadRecentInsights` / `loadInsightsByType` — nothing about delivery / engagement. But they directly affect ranking, so cross-device they need to sync (or be device-local by design).

**Why it matters.** If user marks an insight `notHelpful` on iPhone, then sees the same insight on iPad, the system has lost its learning. Or worse — the per-surface cooldown won't apply on the second device, so the user sees the same insight twice.

**Fix.** Make a deliberate decision and document it:
- **Option A:** Cooldowns and engagement are device-local; the cost is mild duplication on multi-device users. Lower data sensitivity, cheaper to implement.
- **Option B:** Sync via `users/{uid}/insightDelivery/{dedupeKey}` and `users/{uid}/insightEngagement/{dedupeKey}` with merge-on-write. Slightly more data, better UX.

Recommend Option B for the dedupeKey-keyed records (it's tiny — a few KB even for power users).

### C-10 — PII inventory + deletion + export scaffolding

**The bug.** `OnboardingStore` collects: name, gender identity, age, height, weight, equipment, limitations, timezone. Once that data is on a backend, GDPR Article 17 (right-to-erasure) and Article 20 (data portability) apply, plus CCPA, plus Apple's "Account Deletion" App Store requirement (which is **mandatory** for any iOS app that creates an account — your Phase 16 plan creates one).

**Why it matters.** Apple will reject the build if you have account creation but no in-app account-deletion flow. You also need an export.

**Fix.** Add three things, BEFORE Phase 16:
1. `Models/PIIRegistry.swift` listing which fields are PII (display name, age, gender, height, weight, etc) and which are not.
2. `AccountDeletionService` skeleton with a local-mode implementation that wipes all `Spotter/*.json` files. The Firebase mode (Phase 16) extends it to also delete the Firestore doc tree and Auth user.
3. `DataExportService` skeleton that produces a JSON archive of every store's contents.

Both are small, mostly UI plumbing, and they unblock App Store submission.

### C-11 — Secret hygiene + build configuration audit

**The bug.** The README says ElevenLabs is configured via `ELEVENLABS_API_KEY` and warns "Do not ship real API keys" — but I haven't seen a `.gitleaks.toml`, `xcconfig` separation, or build-time secret-injection scaffolding. Phase 15/16 prompts both say "do not ship secrets" but don't enforce it.

**Why it matters.** Once you add `GoogleService-Info.plist` (Phase 16 manual step #3), you have at least one real config file in the repo. Anonymous Firebase Auth doesn't need a secret, but if Sign-in-with-Apple is added later, the `Sign in with Apple` capability uses an Apple-issued service identifier, which is fine to ship — but you should still:
- Have a documented secrets-out-of-source policy.
- Have CI check (e.g., `gitleaks` or `trufflehog` in a pre-commit) that nothing slipped in.
- Use `.xcconfig` per environment (Debug, Beta, Release) so you can swap Firebase projects (dev / prod) without code change.

### Lower-priority observations

- **`OnboardingStore.profile` is the source of truth in-memory but `id: UUID()` is generated locally on every fresh install.** Once an account exists, a returning user installing on a new device needs the profile to be tied to `accountId`, not a fresh local UUID. (This is the same issue as C-1 from a different angle.)
- **`InsightStore.recentInsights` cap is 80** — fine locally, but on a backend that's the wrong abstraction. Server should keep an unbounded log; client decides display window. Document this.
- **Calendar/timezone reliance.** `WorkoutHistoryStore.calendar = Calendar.current` runs on the device's TZ. When syncing across devices in different TZs (unlikely but possible — a traveling user), streak calculations can disagree by a day. Either always compute streaks server-side, or always derive on the client from `profile.timezoneIdentifier` (you already store it).
- **`@Published` storms.** `OnboardingStore`, `WorkoutHistoryStore`, `TrophyStore`, `InsightStore` all emit `objectWillChange` on every save. Once you add real-time Firestore listeners, you'll get rapid-fire publishes. Plan for `Combine.removeDuplicates()` or `debounce` upstream of the views that subscribe.
- **No analytics surface.** Phase 16 mentions Crashlytics + Analytics in the strategy section but the Codex prompt itself doesn't include them. You'll want at least: app-open, onboarding-complete, workout-saved, trophy-unlocked, insight-impression, insight-helpful — and that data needs the same privacy-first treatment (no raw camera, no biomechanics events).
- **No App Check / DeviceCheck.** Anonymous auth on Firebase is open to anyone who can read your `GoogleService-Info.plist`. App Check is a one-line addition that prevents random clients from spamming your Firestore. Add it in Phase 16.
- **No remote feature-flag service.** `FeatureFlags` is a static type with one flag. Backend integration is the right time to either (a) integrate Firebase Remote Config or (b) build a thin wrapper that's swappable later.
- **Debug-only `clearForDebug`** on `InsightStore` and similar — fine but make sure these are gated by `#if DEBUG` for Release builds; right now they're public methods.

---

## Part D — Codex prompts for the eleven items

Each prompt is self-contained, written to be pasted directly. Order them as follows for execution: **C-3 → C-1 → C-2 → C-4 → C-7 → C-6 → C-9 → C-8 → C-5 → C-10 → C-11.** That order minimizes re-work because each item builds on the model changes of the previous.

---

### Prompt C-3 — Soft-delete + `deleteWorkout` + tombstones

```
TASK
Spotter currently has no way to delete a saved workout, edit a saved workout, retract
an erroneously-earned trophy, or invalidate a stale insight. Without soft-delete
semantics in the local model, backend sync (Phase 15/16) will silently resurrect
deleted records every time another device syncs.

GOAL
Add `deletedAt: Date?` to every persisted ownership-bearing model and add the local
delete/restore plumbing so a future sync layer can propagate tombstones.

SCOPE
1. Models that gain `deletedAt: Date?`:
   - WorkoutSessionSummary
   - UserProfile        (for account-deletion path)
   - TrophyProgress
   - TrophyUnlockEvent
   - AIInsight
   - CalibrationRecord
   For each, decode with `decodeIfPresent` defaulting to nil so existing JSON loads.

2. WorkoutHistoryStore additions:
   - func deleteSummary(id: UUID) -> Bool        // sets deletedAt = Date(), persists
   - func restoreSummary(id: UUID) -> Bool       // clears deletedAt
   - func purgeTombstones(olderThan: Date) -> Int  // hard delete deletedAt < cutoff
   The default `summaries` published property hides tombstones; expose
   `summariesIncludingTombstones` for the future sync layer.

3. TrophyStore additions:
   - func retractTrophy(id: String, reason: String) -> Bool
     Marks the matching TrophyProgress with deletedAt and clears earnedAt.
     Used for human-error correction (e.g. test data leaking into prod).

4. InsightStore additions:
   - func invalidateInsight(dedupeKey: String) -> Bool
     Sets deletedAt on the matching insight, removes from recentInsights for default
     queries. Engagement records persist (they still inform ranking).

5. UI surfaces (minimal):
   - WorkoutDetailSheetView: overflow menu with "Delete workout" (destructive
     confirmation). On delete, dismiss the sheet and recompute trophy progress
     (TrophyEngine already idempotent).
   - Profile workout history list: swipe-to-delete with the same confirmation.
   - On delete: invalidate any AIInsight whose evidence references the deleted
     workoutId via InsightStore.invalidateInsight.

6. Cascade rules:
   - Deleting a workout DOES revert PRs (when 2.C ships post-backend).
   - Deleting a workout DOES NOT revert already-earned trophies; this matches the
     existing `merge()` behavior in TrophyEngine that locks earnedAt once set.
   - Deleting a workout DOES expire any AIInsight whose evidence depends on it.

CONSTRAINTS
- Do not break decoding of existing local JSON files.
- Default queries everywhere must continue to hide tombstones.
- All new fields are nullable; never throw on a missing deletedAt.

ACCEPTANCE
- WorkoutHistoryStoreTests: delete, restore, purge with cutoff, tombstone-hidden.
- TrophyEngineTests: retract a trophy → progress updates; recompute idempotent.
- InsightStoreTests: invalidate by dedupeKey → no longer surfaces; engagement
  records preserved.
- Existing tests pass.
```

---

### Prompt C-1 — `accountId` on ownership models

```
TASK
Every persisted Spotter model is identified by a local UUID or stable string. None
of them carry an account/owner ID. Once Firebase auth is added, the backend will
need an explicit owner partition key on every write.

GOAL
Introduce `accountId: String?` (nullable, default nil for purely-local data) on every
ownership-bearing persisted model. Repositories fill it in on save when an account
exists. Stores filter by accountId when one is set; otherwise behave as today.

SCOPE
1. Add `accountId: String?` with `decodeIfPresent` to:
   - UserProfile
   - WorkoutSessionSummary
   - TrophyProgress + TrophyProgressSnapshot
   - TrophyUnlockEvent
   - AIInsight
   - CalibrationRecord
   - InsightDeliveryRecord and InsightEngagementRecord
   - OnboardingStore's persisted profile JSON

2. Add a single source of truth: `Models/AccountContext.swift`
     final class AccountContext: ObservableObject {
        @Published private(set) var currentAccountId: String?
        func setAccount(_ id: String?)
     }
   Wire it as an @StateObject in VirtualTrainerApp; environment-inject downstream.
   Default value is nil, meaning the app is in local-anonymous mode.

3. Stores read AccountContext on save and stamp accountId on writes:
   - OnboardingStore.save(profile) → fills profile.accountId from context
   - WorkoutHistoryStore.addSummary → fills summary.accountId
   - TrophyStore persists snapshot with accountId
   - InsightStore stamps accountId on each AIInsight as it ingests
   - CalibrationStore stamps on saved record

4. Stores filter on read:
   - When accountId is set in context, only return rows whose accountId matches
     OR whose accountId is nil (legacy local-only). Provide a one-shot
     `claimLocalDataForAccount(id:)` method that rewrites all nil-accountId rows
     to the current account on first sign-in (the "anonymous → real account"
     upgrade path).

CONSTRAINTS
- Local-only mode (accountId == nil) must continue to work unchanged.
- Backward-compatible JSON: missing accountId → treat as nil.
- Do not introduce any Firebase/Supabase imports yet; this is pure model + store work.

ACCEPTANCE
- New AccountContextTests: set/clear/claimLocal flows.
- Existing tests pass.
- Round-trip a UserProfile saved without accountId, then with accountId, then load.
```

---

### Prompt C-2 — `SyncMetadata` on every syncable entity

```
TASK
No model carries the metadata that an offline-first sync layer requires
(localUpdatedAt, lastSyncedAt, serverVersion, syncState, idempotency key). Add it
now so the Phase 15 repository protocols have the fields they need to use.

GOAL
Add a `SyncMetadata` value type and embed it on every syncable entity. Repositories
use it for write-tracking, conflict detection, and resolution.

SCOPE
1. Define Models/SyncMetadata.swift:
     enum SyncState: String, Codable { case localOnly, pendingUpload, synced, conflict }
     struct SyncMetadata: Codable, Equatable {
        var localUpdatedAt: Date
        var lastSyncedAt: Date?
        var serverVersion: String?
        var syncState: SyncState
        var pendingOperationId: UUID?

        static let initialLocalOnly: SyncMetadata
     }

2. Embed `var syncMetadata: SyncMetadata` (decodeIfPresent → initialLocalOnly) on:
   - UserProfile
   - WorkoutSessionSummary
   - TrophyProgress (per-trophy, not snapshot)
   - AIInsight
   - CalibrationRecord
   On every local mutation, bump localUpdatedAt and set syncState to .pendingUpload
   if it was .synced.

3. Document conflict resolution per type (in code comments + a new file
   `Documentation/SyncConflictResolution.md`):
   - UserProfile: last-write-wins by localUpdatedAt, but never overwrite
     onboardingCompletedAt or createdAt with later values.
   - WorkoutSessionSummary: writes are immutable after sync; local edits via
     deleteSummary + addNew (Phase 2.G UI) regenerate the doc with a new
     operationId. Direct edit of synced summaries is disallowed.
   - TrophyProgress: server-of-truth via append-only TrophyUnlockEvent log
     (see prompt C-6).
   - AIInsight: device-of-truth (see prompt C-9 for engagement/cooldown sync).
   - CalibrationRecord: most-recent wins.

CONSTRAINTS
- Only model + store metadata work. No Firebase/Supabase imports.
- Backward-compatible decoding: missing syncMetadata defaults to initialLocalOnly.

ACCEPTANCE
- SyncMetadataTests verify default state, transitions, and codable round-trip.
- Stores set syncState = .pendingUpload on mutation.
- Existing tests pass.
```

---

### Prompt C-4 — Idempotency keys for writes

```
TASK
Local saves currently have no operation token. Once a sync layer retries on flaky
networks, a partial write can double-create. We need idempotency keys before
Phase 15 protocols are written.

GOAL
Each write through a future repository will carry a `WriteOperation` envelope with a
deterministic operationId. Local stores recognize the same operationId and dedupe.

SCOPE
1. Define Models/WriteOperation.swift:
     struct WriteOperation<Payload: Codable & Equatable>: Codable {
        let operationId: UUID
        let entityKind: WriteEntityKind  // enum: profile, workout, trophy, insight, calibration
        let payload: Payload
        let createdAt: Date
     }

2. Add a thin LocalWriteJournal (Models/LocalWriteJournal.swift):
   - File-persisted append-only log of recent operationIds (last 30 days).
   - func record(_ operationId: UUID) and func contains(_ operationId: UUID) -> Bool
   - Vacuumed on app launch.

3. Each store's mutating method takes an optional operationId:
   - addSummary(_, operationId: UUID? = nil)
   - completeOnboarding(operationId: UUID? = nil)
   - update(after:, operationId: UUID? = nil) on TrophyStore
   - recordImpression / recordEngagement carry operationIds too
   When operationId is supplied AND already in the journal, the call is a no-op.
   When nil, the store generates a fresh UUID, writes the journal entry, then
   performs the mutation.

CONSTRAINTS
- Default behavior unchanged when operationId is nil (auto-generate).
- Journal file is small; budget < 200 KB for 30 days of activity.
- Pure local change; no networking yet.

ACCEPTANCE
- LocalWriteJournalTests: record, dedupe, vacuum.
- Calling addSummary twice with the same operationId only persists once.
```

---

### Prompt C-7 — Server-authoritative timestamps (clock skew defense)

```
TASK
Streaks, trophies, and personal records depend on Date(). A user can set their
phone clock back to backdate a workout. For backend integration we need a clock
that the server authoritatively trusts.

GOAL
Introduce a `Clock` abstraction that provides serverNow() in addition to Date().
In local mode it falls back to Date(); in backend mode (Phase 16) it returns
serverTimestamp() values for new writes and reconciles old writes on first sync.

SCOPE
1. Models/Clock.swift:
     protocol AppClock {
        func now() -> Date
        func serverTimestamp() -> Date  // best estimate; identical to now() in local mode
     }
     struct LocalClock: AppClock { ... uses Date() ... }
     // FirebaseServerClock will arrive in Phase 16 and override serverTimestamp()

2. Pass `AppClock` into every engine that mints a meaningful timestamp:
   - TrophyEngine: TrophyUnlockEvent.earnedAt uses clock.serverTimestamp()
   - WorkoutHistoryStore.addSummary: stamps a `serverEndedAt` on the summary
     equal to clock.serverTimestamp(); endedAt remains the device-clock value
     for display. Streak calculations prefer serverEndedAt when present.
   - StatsEngine: streak math reads serverEndedAt > endedAt > nil.

3. WorkoutSessionSummary gains `serverEndedAt: Date?` (nullable, decodeIfPresent).
   In local mode it equals endedAt. In backend mode the repository will overwrite
   it with the Firestore writeTime on successful sync.

4. The Clock is environment-injected from VirtualTrainerApp using a default
   LocalClock(); tests inject a stub clock.

CONSTRAINTS
- Streak / PR semantics must be byte-identical in local mode.
- Backward-compatible decoding.

ACCEPTANCE
- StatsEngineTests parameterized on a stub clock prove streak math reads
  serverEndedAt when present.
- Existing tests pass with the default LocalClock.
```

---

### Prompt C-6 — Trophy events: append-only log + canonical earnedAt

```
TASK
TrophyEngine recomputes a snapshot from history. Two devices computing the same
snapshot independently can disagree on earnedAt. For multi-device users, the
snapshot is not a sufficient source of truth.

GOAL
Move to an append-only TrophyUnlockEvent log as the source of truth for unlocks.
Snapshot becomes purely derived from events + recomputed metric values. earnedAt
is the timestamp of the first event.

SCOPE
1. Persist `[TrophyUnlockEvent]` in TrophyStore alongside the snapshot. Already
   in the model; just persist it.

2. TrophyEngine.updateAll changes:
   - Compute the metric value as today.
   - When a metric value first crosses target, emit an event with
     `earnedAt = clock.serverTimestamp()` AND append it to the persisted log.
   - When merging a recompute against existing log, look up earnedAt from the
     earliest matching event for that trophyId; never overwrite with a later
     value.
   - Snapshot.progress[i].earnedAt is filled from the log, not from the previous
     snapshot.

3. TrophyStore retains the events but trims to the last 1,000 to bound storage.

4. TrophyStore now exposes:
   - func unlockEvents(for trophyId: String) -> [TrophyUnlockEvent]
   - func unlockEvents(in dateRange: ClosedRange<Date>) -> [TrophyUnlockEvent]
   These are what the future Profile "achievements timeline" UI will use.

CONSTRAINTS
- Deterministic recompute: the same history + log produces the same snapshot.
- Event order preserved by earnedAt asc; tie-break by trophyId.

ACCEPTANCE
- New TrophyEngineTests: recompute against an existing log preserves earnedAt,
  even when current Date() is later than the original.
- Existing TrophyEngineTests pass.
```

---

### Prompt C-9 — Insight delivery + engagement sync semantics decision

```
TASK
InsightDeliveryRecord (cooldowns) and InsightEngagementRecord (helpful, etc.) are
private engagement signals that affect ranking. Decide and document whether they
sync across devices, then implement the chosen path.

GOAL
Adopt the "sync with last-write-wins per dedupeKey" approach. Cooldowns become
multi-device-aware so a user who saw an insight on iPhone doesn't see the same
one immediately on iPad.

SCOPE
1. Add the same SyncMetadata embed to InsightDeliveryRecord and
   InsightEngagementRecord (from prompt C-2).

2. Make the merge functions explicit and total:
   - InsightDeliveryRecord.merge(local, remote): later lastPresentedAt wins;
     presentationCount sums; per-surface dictionary takes max date per surface.
   - InsightEngagementRecord.merged(with:) already exists; verify behavior on
     same-day double-engagement (currently sums counts — keep that).

3. Add a stable dedupe key for storage (already keyed by AIInsight.dedupeKey).

4. Document the decision in a new comment block at the top of InsightStore.swift:
     // SYNC SEMANTICS:
     // Delivery records and engagement records are server-mirrored per accountId.
     // Conflicts merge by max(lastEvent timestamps) and sum(counts).
     // The local InsightStore is the cache; the server doc is canonical for
     // multi-device reads.

CONSTRAINTS
- No backend code yet; just the merge functions, the SyncMetadata, and the
  documented decision.
- Behavior in single-device local mode unchanged.

ACCEPTANCE
- InsightStoreTests: merge two delivery records with overlapping surfaces produces
  the union-with-max-date.
- Existing tests pass.
```

---

### Prompt C-8 — Workout document size + shape audit

```
TASK
Before deciding whether to embed sets or use a Firestore subcollection, measure.

GOAL
Produce a deterministic synthetic worst-case workout, encode it, log the size, and
document the decision.

SCOPE
1. Add a test target file `WorkoutSummarySizeAuditTests.swift`:
   - Build a synthetic WorkoutSessionSummary with:
     - 8 ExerciseSetSummary entries
     - Each with 25 RepQualityEvent entries, formScore present, cueMessageNearRep
       present (40-character cue)
     - Each with 5 CueEvent entries
     - Reasonable averageFormScore values
   - Encode using the same JSONEncoder as WorkoutHistoryStore
   - Print the byte count + assert under 256 KB; if over, fail loudly.

2. Based on the measured size, write a decision in
   Documentation/FirestoreShape.md:
   - If under 256 KB → embed sets in the workout doc.
     Path: users/{uid}/workouts/{workoutId}
   - If over 256 KB → flatten:
     users/{uid}/workouts/{workoutId}
     users/{uid}/workouts/{workoutId}/sets/{setId}
     users/{uid}/workouts/{workoutId}/sets/{setId}/repEvents/{repEventId}
   - Document chosen path and rationale.

3. If embedded path is chosen, document the maximum-set-count safeguard
   (refuse to save / split into two workout docs at hard limit).

CONSTRAINTS
- Pure measurement + documentation. No code-shape changes yet; that comes in
  Phase 16.

ACCEPTANCE
- The test runs and produces a measured size.
- A Documentation/FirestoreShape.md exists with the decision.
```

---

### Prompt C-5 — Off-main persistence

```
TASK
All five stores persist on @MainActor. Once Firestore listeners are added, every
write fans out to network on the same actor. UI stuttering will compound.

GOAL
Move file I/O off the main actor. Stores keep their @Published state on the main
actor for SwiftUI binding, but the encode + write happens on a background actor.

SCOPE
1. Define Models/PersistenceActor.swift:
     actor PersistenceActor {
        func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws
        func read(_ url: URL) throws -> Data
        func remove(_ url: URL) throws
     }
   Singleton instance; injected by default.

2. Refactor each store's persist():
   - Move encode() onto the calling thread (cheap; Codable JSONEncoder is fast).
   - The actual write goes through PersistenceActor.write inside a Task.
   - Store maintains an `inFlightWrite: Task?` so concurrent saves coalesce
     (last-write wins for the in-flight slot; the previous Task is cancelled
     before issuing the new one).

3. Stores affected:
   - OnboardingStore.save
   - WorkoutHistoryStore.persist
   - TrophyStore.persist
   - InsightStore.persist
   - CalibrationStore.persist

4. Loads stay on init for now (acceptable as one-time main-thread cost). A
   future task can move loads off-main too.

CONSTRAINTS
- @Published mutation must remain on the main actor.
- Atomic write semantics preserved (.atomic option).
- If a save fails, the previously-published state must remain consistent
  (existing rollback behavior preserved by reverting the @Published value
  inside the error catch).

ACCEPTANCE
- Existing store tests pass (they don't hit the I/O path beyond init).
- A new PersistenceActorTests verifies write/read/remove from background actor.
- Manual: run a "save 200 workout summaries" loop and observe no UI hitch.
```

---

### Prompt C-10 — PII inventory + account deletion + data export

```
TASK
Once Phase 16 enables account creation, App Store policy AND GDPR/CCPA require
account deletion in-app and data export on request. Build the scaffolding now,
local-mode only, so Phase 16 is purely about wiring it to Firestore.

GOAL
Three new components: PIIRegistry, AccountDeletionService, DataExportService.
All work today against local files; Phase 16 extends them to also affect server.

SCOPE
1. Models/PIIRegistry.swift:
     enum PIIField: String, CaseIterable {
        case displayName, age, gender, height, weight, timezone, equipment,
             limitations, reminderPreference, accountId
     }
     struct PIIRegistry {
        static let fields: [PIIField] = PIIField.allCases
        static func describe(_ field: PIIField) -> String  // for export labels
     }

2. Services/AccountDeletionService.swift:
     @MainActor
     final class AccountDeletionService {
        init(stores: AppStores) { ... }
        func deleteAccount() async throws -> AccountDeletionReceipt
     }
     // deletes UserProfile.json, WorkoutHistory.json, TrophyProgress.json,
     // CoachInsights.json, CalibrationRecord.json, LocalWriteJournal,
     // any cached share images.
     // Phase 16: also issues Firestore tree delete + Auth.user.delete.

3. Services/DataExportService.swift:
     @MainActor
     final class DataExportService {
        func generateExport() async throws -> URL
        // Produces a zipped JSON archive in the app's temp directory:
        //   profile.json, workouts.json, trophies.json, insights.json,
        //   calibration.json, schemaVersions.json, README.txt explaining each file.
        // Returns a file URL the caller can present in a UIActivityViewController.
     }

4. Profile UI: in the existing SettingsDebugSection (or a new Account section
   when sign-in is added in Phase 16), add two destructive options:
   - "Delete my account and data" → confirmation dialog → AccountDeletionService
   - "Export my data" → DataExportService → share sheet
   In local mode, "Delete" wipes local files; in backend mode it deletes server
   too. Both flows must work today.

CONSTRAINTS
- DataExportService output is human-readable and self-documenting.
- AccountDeletionService is irreversible by design; require typed confirmation
  ("DELETE") in the UI dialog.
- No Firestore code yet.

ACCEPTANCE
- AccountDeletionServiceTests: invoking deleteAccount removes all expected
  files; rerun is a no-op (no error).
- DataExportServiceTests: zipped archive contains all expected JSONs and a
  README; archive is decodable round-trip.
- Profile UI shows the two new buttons (visible in preview).
```

---

### Prompt C-11 — Secret hygiene + xcconfig environments

```
TASK
The repo will soon need to handle GoogleService-Info.plist (Phase 16) and may
already need ELEVENLABS_API_KEY safely. We need a documented secrets policy and
build-config separation now, before any real key lands in the repo.

GOAL
Three deliverables:
1. .gitleaks.toml allowlisting acceptable patterns and blocking the dangerous ones.
2. Three xcconfig files: Debug.xcconfig, Beta.xcconfig, Release.xcconfig — empty
   today but structured so Phase 16's GoogleService-Info-Dev.plist /
   GoogleService-Info-Prod.plist can swap by build configuration.
3. A Documentation/SECRETS.md describing what is allowed in source, what is not,
   how to add new secrets via Info.plist build settings (and not in .swift files),
   and how local developers obtain dev secrets.

SCOPE
1. Add .gitleaks.toml with rules for:
   - Generic API key patterns (32-char hex, AWS keys, Google API keys)
   - Firebase service-account JSON (block "private_key": "-----BEGIN")
   - Apple cert / .p12 / .p8 binary blobs
   - Allowlist for the legitimate strings (e.g. iOS bundle ID, model file names).

2. Add Configurations/{Debug,Beta,Release}.xcconfig — set them at the project
   level. Currently empty but with comments explaining the convention.

3. Documentation/SECRETS.md content:
   - What is allowed in source (no real secrets; the bundle ID is fine).
   - What is NOT allowed (any private key, any service-account JSON, any token).
   - How to add a real secret in Phase 16 (xcconfig + Info.plist key + Swift
     accessor that reads Bundle.main.object(forInfoDictionaryKey:)).
   - How a new developer obtains dev Firebase config (e.g., env var or 1Password
     vault — define the team-specific path).
   - Pre-commit hook recommendation that runs gitleaks.

CONSTRAINTS
- No actual secrets in the deliverable.
- All three xcconfig files are empty; they exist as scaffolding, not config.

ACCEPTANCE
- .gitleaks.toml lints clean against the current repo.
- Build still works after switching the project to use xcconfig-based config.
- Documentation/SECRETS.md exists and is referenced from README.md.
```

---

## Part E — GPT-5.5-Pro's Phase 15 and Phase 16 prompts: review and rewrite

Now to your direct question: **does GPT's plan cover everything?**

Short answer: **No.** The two prompts are well-structured skeletons but they're missing roughly 60% of the substantive day-1 backend work. They list the protocols and the Firestore paths, but they don't address sync semantics, conflict resolution, schema migration, identity transitions, off-main I/O, App Store account-deletion requirements, App Check / DeviceCheck, Remote Config, secret hygiene, or analytics. They also assume work that hasn't been done yet (the `WorkoutRepository.deleteWorkout` line presumes the underlying store can soft-delete — it can't, until prompt C-3 ships).

Read GPT's two prompts as **table of contents**, not as **build instructions**.

Below is what I'd actually paste into Codex once Part D is done.

---

### Replacement Prompt for Phase 15 (Backend Abstraction)

```
TASK (Phase 15 — Backend Abstraction)
You are working in the Spotter iOS Swift repository. The previous "pre-backend
hardening" work (prompts C-1 through C-11 in
Spotter_Pre_Backend_Readiness.md) is COMPLETE. Stores have accountId, sync
metadata, soft-delete, idempotency keys, server-clock abstraction, append-only
trophy events, off-main persistence, account deletion + export, and secret hygiene.

We are now adding the repository abstraction layer. Do NOT integrate Firebase or
Supabase in this task.

PRINCIPLES
1. Local-first. The default BackendMode is .local. Every test must pass with
   .local mode. The app must run end-to-end without any backend SDK installed.
2. Repository protocols are pure abstractions — no Firebase / Supabase types
   leak through them. Use Swift value types from the existing Models.
3. Stores depend on protocols, not concrete repositories. Refactor incrementally.
4. Concurrency: every repository protocol method is `async throws`.
5. Errors: each repository returns a typed Error. Define `RepositoryError` cases:
   .notFound, .conflict(serverVersion, localVersion), .unauthorized,
   .network(underlying), .invalidPayload, .accountMissing.

SCOPE — protocols (Repositories/*.swift)

  protocol AuthRepository {
      var currentAccountId: String? { get }
      func signInAnonymously() async throws -> String   // returns accountId
      func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String
      func signOut() async throws
      func deleteAccount() async throws  // calls AccountDeletionService server-side
      func observeAuthChanges() -> AsyncStream<String?>
  }

  protocol ProfileRepository {
      func loadProfile(accountId: String) async throws -> UserProfile?
      func saveProfile(_ profile: UserProfile, operationId: UUID) async throws -> UserProfile
      // returns the profile with updated SyncMetadata (lastSyncedAt, serverVersion)
      func observeProfile(accountId: String) -> AsyncStream<UserProfile>
  }

  protocol WorkoutRepository {
      func saveWorkoutSummary(_ summary: WorkoutSessionSummary, operationId: UUID) async throws -> WorkoutSessionSummary
      func loadRecentWorkouts(accountId: String, limit: Int, since: Date?) async throws -> [WorkoutSessionSummary]
      func loadWorkout(accountId: String, id: UUID) async throws -> WorkoutSessionSummary?
      func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws
      // soft-delete: sets deletedAt; vacuum is repository-internal
      func observeRecentWorkouts(accountId: String, limit: Int) -> AsyncStream<[WorkoutSessionSummary]>
  }

  protocol TrophyRepository {
      func loadTrophyDefinitions() async throws -> [TrophyDefinition]
      // Local impl returns TrophyDefinitionCatalog.all; remote impl will
      // hydrate from server, falling back to bundled.
      func loadTrophyEvents(accountId: String, since: Date?) async throws -> [TrophyUnlockEvent]
      func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId: UUID) async throws
      // Snapshot is derived; we do NOT save the snapshot, only events.
      func loadTrophyProgress(accountId: String) async throws -> TrophyProgressSnapshot?
      // Optional cached snapshot for fast-load; recomputed from events on mismatch.
  }

  protocol InsightRepository {
      func saveInsights(_ insights: [AIInsight], operationId: UUID) async throws
      func loadRecentInsights(accountId: String, limit: Int) async throws -> [AIInsight]
      func saveDeliveryRecord(_ record: InsightDeliveryRecord, operationId: UUID) async throws
      func loadDeliveryRecords(accountId: String) async throws -> [InsightDeliveryRecord]
      func saveEngagementRecord(_ record: InsightEngagementRecord, operationId: UUID) async throws
      func loadEngagementRecords(accountId: String) async throws -> [InsightEngagementRecord]
      func invalidateInsight(accountId: String, dedupeKey: String, operationId: UUID) async throws
  }

  protocol ThemeRepository {
      func loadTheme(accountId: String) async throws -> SpotterThemeOption?
      func saveTheme(_ theme: SpotterThemeOption, accountId: String, operationId: UUID) async throws
  }

  protocol CalibrationRepository {
      func loadCalibrationRecord(accountId: String) async throws -> CalibrationRecord?
      func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID) async throws
  }

  protocol PlanRepository {
      // Plans are currently transient (regenerated on demand). Repository allows
      // future server-cached / plan-history features. Local impl persists none.
      func saveActivePlan(_ plan: WorkoutPlanV2, accountId: String, operationId: UUID) async throws
      func loadActivePlan(accountId: String) async throws -> WorkoutPlanV2?
      func loadPlanHistory(accountId: String, limit: Int) async throws -> [WorkoutPlanV2]
  }

SCOPE — local implementations
  - LocalAuthRepository: returns a stable per-device anonymous accountId
    written to UserDefaults with key "spotter.localAccountId". signInAnonymously
    creates one if absent. linkAnonymousAccountWithApple is a no-op in local mode.
  - LocalProfileRepository: backed by OnboardingStore.
  - LocalWorkoutRepository: backed by WorkoutHistoryStore (uses the new
    deleteSummary, addSummary(operationId:) APIs).
  - LocalTrophyRepository: backed by TrophyStore (uses the new event log).
  - LocalInsightRepository: backed by InsightStore.
  - LocalThemeRepository: backed by ThemeStore.
  - LocalCalibrationRepository: backed by CalibrationStore.
  - LocalPlanRepository: in-memory only; returns nil for history.

SCOPE — composition
  - Models/AppDependencies.swift:
      @MainActor final class AppDependencies: ObservableObject {
         let backendMode: BackendMode  // .local for now
         let auth: any AuthRepository
         let profile: any ProfileRepository
         let workouts: any WorkoutRepository
         let trophies: any TrophyRepository
         let insights: any InsightRepository
         let theme: any ThemeRepository
         let calibration: any CalibrationRepository
         let plans: any PlanRepository
      }
  - Models/BackendMode.swift:
      enum BackendMode: String, Codable { case local, firebase, supabase }

  - VirtualTrainerApp.swift: build the AppDependencies for .local at startup
    and inject as @StateObject + .environmentObject. Stores remain
    @StateObjects but now read repository protocols (NOT concrete types) for
    save / load.

SCOPE — store refactor
  - OnboardingStore: add init(profileRepository: ProfileRepository, ...).
    save() now calls profileRepository.saveProfile under a Task.
  - WorkoutHistoryStore: add init(workoutRepository:). addSummary calls the
    repository.
  - TrophyStore: add init(trophyRepository:). update() now appends an event
    via the repository.
  - InsightStore: add init(insightRepository:). selectInsights still computes
    locally; persistence routes through the repository.
  - CalibrationStore, ThemeStore: same pattern.

  Important: keep the existing local-file persistence paths working in the
  Local* implementations. We are wrapping, not replacing.

SCOPE — sync orchestrator (foundation only)
  - Services/SyncOrchestrator.swift:
      @MainActor final class SyncOrchestrator: ObservableObject {
         @Published private(set) var status: SyncStatus = .idle
         init(deps: AppDependencies)
         func enqueueWriteIfDirty(...)  // walks SyncMetadata.syncState == .pendingUpload
         func performFullSync() async throws
         func observeRemote() -> Task<Void, Never>  // no-op in local mode
      }
    In .local mode all methods are no-ops or pure-success. The full sync logic
    arrives in Phase 16.

PRIVACY BOUNDARY (non-negotiable)
  - No raw camera frames, raw video, face images, raw pose streams, or raw
    biometric face data flow through any repository. Period.
  - PII flows through ProfileRepository only.

ACCEPTANCE
  - AppDependencies.local builds and the app runs end-to-end with all current
    flows.
  - All existing tests pass.
  - New tests:
      - LocalAuthRepositoryTests: stable anonymous account across init/load.
      - LocalWorkoutRepositoryTests: save → load → delete → load returns nil.
      - LocalTrophyRepositoryTests: append events, derive snapshot, idempotent
        on the same operationId.
      - LocalInsightRepositoryTests: round-trip insights, delivery, engagement.
      - SyncOrchestratorTests in .local mode: enqueue-and-sync produces no-op.

OUT OF SCOPE
  - Firebase / Supabase imports, server code, anything network.
  - Coach personality narratives (separate prompt 1.G).
  - Personal Records system (post-backend, by user decision).
  - Trophy library expansion (post-backend, by user decision).
```

---

### Replacement Prompt for Phase 16 (Firebase Integration)

```
TASK (Phase 16 — Firebase integration behind a feature flag)
The repository abstraction layer (Phase 15) is COMPLETE. We now add Firebase as a
BackendMode option, gated behind a feature flag, with full local-mode preserved.

MANUAL SETUP (you, not Codex)
1. Create Firebase project (one each for dev, prod).
2. Add iOS app per environment using the matching Xcode bundle ID.
3. Download GoogleService-Info-Dev.plist and GoogleService-Info-Prod.plist.
4. Add them to the Xcode target with Debug/Release configuration mapping in
   the xcconfig files (already scaffolded in prompt C-11).
5. Enable Authentication: Anonymous + Sign in with Apple.
6. Create Firestore database in Native mode.
7. Set up a server-side Cloud Function for account-deletion fan-out (see below).
8. Service-account JSON files NEVER touch the iOS repo.

CODEX TASK

PRINCIPLES
1. Local mode is fully preserved. App must build and run with no Firebase config.
2. Firebase mode fails gracefully if config is missing — surface a banner and
   stay in local mode rather than crashing.
3. The privacy boundary is unchanged: no raw camera/video/pose/face/biometric
   data is uploaded. Verify with a test that introspects Firestore writes.
4. Server timestamps are authoritative for trophies, streaks, PRs.
5. Every write is idempotent via operationId.

SCOPE — bootstrap
  - Add Firebase via Swift Package Manager (FirebaseAuth, FirebaseFirestore,
    FirebaseFirestoreSwift, FirebaseAppCheck, FirebaseRemoteConfig,
    FirebaseAnalytics, FirebaseCrashlytics).
  - VirtualTrainerApp: at launch, attempt FirebaseApp.configure() if
    GoogleService-Info-{env}.plist is present in bundle. Cache the result.
  - BackendMode.firebase: requires successful FirebaseApp.configure(); else
    fall back to .local with a UserNotice ("Backend unavailable — running
    locally").
  - Add App Check (DeviceCheck provider on iOS 14+, AppAttest on 14.4+) before
    any Firestore call.

SCOPE — Firebase repositories
  - Repositories/Firebase/FirebaseAuthRepository.swift:
      anonymous sign-in, link with Apple (the Apple credential flow ALREADY
      exists in Phase 15's signInWithApple scaffolding; this implementation
      calls FirebaseAuth.signInWithCredential).
      observeAuthChanges() returns Auth.auth().authStateDidChangeNotification.
  - FirestoreProfileRepository: users/{uid} doc.
      saveProfile uses Firestore.transaction so localUpdatedAt > serverVersion
      check is atomic. On conflict throw RepositoryError.conflict.
  - FirestoreWorkoutRepository: users/{uid}/workouts/{workoutId} doc.
      Use the document shape decided in prompt C-8.
      Soft-delete writes deletedAt = serverTimestamp(); vacuum (hard delete)
      runs server-side after 30 days via a scheduled Cloud Function. Client
      filters tombstones on read.
  - FirestoreTrophyRepository: users/{uid}/trophyEvents/{eventId} append-only.
      Cached snapshot at users/{uid}/trophyProgress (rebuildable from events).
  - FirestoreInsightRepository: three sub-paths:
      users/{uid}/insights/{dedupeKey}            (latest insight per key)
      users/{uid}/insightDelivery/{dedupeKey}     (cooldowns)
      users/{uid}/insightEngagement/{dedupeKey}   (helpful etc.)
      Use merge(true) on writes to avoid clobbering server-only fields.
  - FirestoreThemeRepository: users/{uid}/preferences/theme single doc.
  - FirestoreCalibrationRepository: users/{uid}/calibration/status single doc.
  - FirestorePlanRepository: users/{uid}/plans/{planId} for active plan +
    history; plans collection is the active plan pointer.

SCOPE — server clock
  - Implement FirebaseServerClock conforming to AppClock (from prompt C-7).
    serverTimestamp() returns Date() but the repository OVERRIDES the field
    with FieldValue.serverTimestamp() on write; the returned doc snapshot
    re-reads the server-assigned time and pushes it back into the local
    SyncMetadata.

SCOPE — sync orchestrator activation
  - SyncOrchestrator.performFullSync (already scaffolded in Phase 15) becomes
    real:
      1. Pull-down: load remote docs, merge with local SyncMetadata, write
         local with .synced state.
      2. Push-up: walk LocalWriteJournal for pending operations; replay each
         once. On 200, mark .synced; on conflict, mark .conflict and surface
         a non-blocking notice.
      3. Subscribe: open Firestore listeners for live sync of profile, recent
         workouts, trophies, insights.

SCOPE — Firestore security rules (in Documentation/firestore.rules)
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      match /users/{uid} {
        allow read, write: if request.auth.uid == uid;
        match /{path=**} {
          allow read, write: if request.auth.uid == uid;
        }
      }
      // Define rate-limit and field-shape constraints per collection.
    }
  }
  Document maximum-payload constraints, required fields, and disallowed fields
  per path; copy these into the rules file with `request.resource.data` checks.

SCOPE — analytics + Crashlytics
  - Wire Crashlytics on launch.
  - Define an `AnalyticsEvent` enum with: appOpen, onboardingCompleted,
    workoutSaved(mode:), trophyUnlocked(id:rarity:), insightImpression(type:),
    insightHelpful(type:), insightNotHelpful(type:), shareCardRendered(kind:),
    syncError(domain:).
  - Privacy: no PII, no rep counts, no exercise types. Only enum values and
    counts.
  - Add Services/AnalyticsService.swift with a default FirebaseAnalyticsService
    impl and a no-op LocalAnalyticsService for tests + .local mode.

SCOPE — Remote Config
  - Use Remote Config to fetch:
      - Trophy catalog version pin (default = bundled).
      - Active feature flags (extends existing FeatureFlags).
      - Coach insight LLM rewrite enabled flag.
      - Sync window (e.g., min seconds between full syncs).
  - Default values are the bundled values; remote overrides only after fetch.

SCOPE — Cloud Function (server side, separate repo)
  - functions/onAccountDeletion: delete users/{uid} subtree on auth.user.delete.
  - functions/scheduledTombstoneVacuum: nightly purge of soft-deleted docs
    older than 30 days.
  - functions/onTrophyEventCreate: validate that the event isn't a duplicate
    (operationId index check) before allowing the write to settle.
  - These ship in a separate `spotter-functions` repo with its own deploy.

ACCEPTANCE
  - App runs in .local mode with the Firebase SDK installed but without config.
  - App in .firebase mode without config shows the fallback banner and stays
    local.
  - With config, anonymous sign-in works; profile / workouts / trophies sync.
  - Sign in with Apple round-trips and links anonymous data.
  - Account deletion empties the Firestore tree AND deletes the Auth user.
  - Two-device sync test: write a workout on device A; device B's listener
    surfaces it within 5 seconds.
  - No raw camera / pose / face data appears in any Firestore write
    (verify with a Firestore listener that asserts on document keys).
  - Existing local-mode tests pass unchanged.

OUT OF SCOPE
  - Production launch (separate beta hardening pass; corresponds to GPT
    Phase 19).
  - Supabase (only if you abandon Firebase later; corresponds to GPT
    Phase 17).
  - Coach personality narratives (separate prompt 1.G).
```

---

## Part F — How GPT's prompts compare to the rewrite (the explicit answer to your question)

GPT's Phase 15 prompt covers, in one paragraph each:
- Eight repository protocols (matches what I wrote, but with no method signatures, no error semantics, no `async throws`, no idempotency).
- Eight local implementations (matches, but no specification of how they wrap the existing stores, and silently introduces `deleteWorkout` against a store that can't delete).
- A `RepositoryContainer` and `BackendMode` enum (matches).
- "Refactor stores gradually" (matches the spirit; the rewrite is concrete).
- A six-test acceptance bar.

What GPT's Phase 15 does NOT cover but my rewrite does:
- `accountId` propagation (without it, the protocols are unimplementable in `firebase` mode — the partition key is implicit).
- Sync metadata + conflict resolution rules.
- Idempotency keys.
- `WorkoutRepository.deleteWorkout` actually working (depends on prompt C-3).
- Trophy event log vs snapshot decision (forces a wrong/inconsistent design otherwise).
- Off-main I/O.
- AsyncStream for live observation (Firestore listeners need a place to plug in).
- Typed `RepositoryError`.
- Plan repository (GPT lists it but as an after-thought; I made it explicit-but-degenerate in local mode so the seam exists).
- A `SyncOrchestrator` foundation that's a no-op in local mode but ready for Phase 16 to populate.
- Explicit privacy-boundary statement and bypass test.

GPT's Phase 16 prompt covers:
- BackendMode.firebase + bootstrap (matches but lacks fallback semantics when config missing — my rewrite makes this explicit).
- `FirebaseAuthRepository` with anonymous and Sign-in-with-Apple "scaffolding" (matches, but missing App Check and the linking flow).
- Seven Firestore repositories (matches the names but lists no document shapes, no merge semantics, no transaction usage).
- A path layout (matches).
- Data rules + security rules in docs (matches but gives no concrete `firestore.rules` content).
- A seven-test acceptance bar.

What GPT's Phase 16 does NOT cover but my rewrite does:
- Server clock (without `FirebaseServerClock`, the "use server timestamp" rule is just words).
- Concrete sync orchestrator implementation.
- Append-only trophy event collection (path layout difference).
- Insight delivery + engagement sub-paths.
- App Check / DeviceCheck.
- Remote Config wiring.
- Crashlytics + privacy-aware Analytics.
- Cloud Function obligations (account deletion fan-out, tombstone vacuum, trophy event de-duplication).
- Multi-environment config via xcconfig (Dev / Beta / Prod).
- Sign-in-with-Apple linking flow (GPT calls it "scaffolding only" — that's exactly the kind of half-step that bites in production).
- Account-deletion in-app flow that satisfies App Store requirements (separate prompt C-10 — Phase 16 just hooks into it).
- A privacy assertion test (introspects Firestore writes for forbidden fields).

**Bottom line.** Use GPT's two prompts as a contract sketch. Use my Part D + Part E as the actual prompts to ship.

---

## Part G — Recommended execution order

This is what I would do, in order, before writing the first line of `FirebaseAuthRepository`.

**Wave 1 — Pre-backend hardening (Part D, ~1.5 weeks for one engineer + Codex):**
1. `C-3` Soft-delete + tombstones (also unblocks 2.G UI flows from earlier review).
2. `C-1` `accountId` on ownership models.
3. `C-2` `SyncMetadata`.
4. `C-4` Idempotency keys.
5. `C-7` Server clock abstraction.
6. `C-6` Trophy event log.
7. `C-9` Insight delivery + engagement sync semantics.
8. `C-8` Workout document size audit.
9. `C-5` Off-main persistence.
10. `C-10` PII registry + account deletion + data export (LOCAL ONLY).
11. `C-11` Secret hygiene + xcconfig.

**Wave 2 — Phase 15 (Part E first prompt, ~1 week):**
- Repository protocols + local implementations + AppDependencies + SyncOrchestrator scaffold.

**Wave 3 — Phase 16 (Part E second prompt, ~2 weeks + manual setup):**
- Firebase SDK + FirebaseAuthRepository (anonymous + Apple) + Firestore repositories + server clock + sync orchestrator activation + Remote Config + Analytics + Cloud Functions.

**After Wave 3 you can safely build:**
- `2.C` Personal Records (uses event log + sync).
- `2.E` Trophy library expansion (uses Remote Config for catalog).
- `1.G` Coach-personality narratives (no backend dependency, but easier when ranker/store are mature).
- `2.B` Trophy unlock celebration (no backend dependency; ship anytime).
- `2.D` Streak Freeze + milestones (uses event log).
- `2.A` (rest of) Share artifacts (uses share path; backend-independent).
- `2.G` Workout edit/delete/filter/redo UI (uses C-3 plumbing).
- `2.H` Named levels + better XP curve + remote trophy catalog (uses Remote Config).

---

## Closing thoughts

The Phase-1/Phase-2 hardening you've already done has put the architecture in unusually good shape. You have evidence-first insights, sane separation of concerns, schema versioning hygiene, atomic writes, schema-versioned LLM-ready context, and a tight test suite. The bones are right.

The **eleven items in Part D** are the real "pre-backend integration readiness phase" — most of which GPT's plan didn't explicitly call out. Each is a model/store change that's easier to ship before backend code than after. Many of them (especially `C-3` soft-delete, `C-1` accountId, `C-2` sync metadata) are very hard to retrofit once Firestore is talking to the app.

The **two replacement prompts in Part E** turn GPT's table-of-contents prompts into actual build instructions. They're not radically different in shape, but they fill in the parts that decide whether your sync layer is robust or whether you spend the next quarter chasing data-correctness bugs.

If you only do three things from this document, do these:
1. Ship `C-3` (soft-delete + tombstones), `C-1` (accountId), and `C-2` (SyncMetadata) — this is the ground truth that makes everything else possible.
2. Use the replacement Phase 15 prompt instead of GPT's, especially for the protocol method signatures and the `SyncOrchestrator` scaffolding.
3. Use the replacement Phase 16 prompt instead of GPT's, especially for App Check, Cloud Functions for account-deletion fan-out, and the privacy-assertion test.

Once Wave 3 lands, you're in an unusually strong position to ship PRs, expanded trophies, and the trophy unlock celebration without rework. Until then, defer them.

Looks like you're building the rare fitness app where the engineering discipline matches the product ambition. Keep that bar.
