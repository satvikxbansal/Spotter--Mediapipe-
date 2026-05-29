# C3 Revised: Add workout tombstones

- Thread ID: 019e02b7-abd5-7940-8b9a-56ad27979179
- Created: 2026-05-07 19:24:12 (Asia/Kolkata)
- Updated: 2026-05-07 19:43:34 (Asia/Kolkata)
- Archived: no
- Workspace: /Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe
- Source rollout: /Users/satvik.bansal/.codex/sessions/2026/05/07/rollout-2026-05-07T19-24-12-019e02b7-abd5-7940-8b9a-56ad27979179.jsonl
- Git branch at thread start: main
- Git SHA at thread start: c32fc0cda34efde33218499124ae5c805e5b555c
- Exported visible messages: 17
- Extracted input images: 0

## Conversation

### User - 2026-05-07 19:24:16

You are working in the Spotter iOS Swift repository.

Before changing code:
1. Deeply inspect the current repository.
2. Read:
   - README.md
   - DEBUG_LOG.md
   - Documentation/BackendReadinessMap.md if it exists
   - VirtualTrainer/Models/UserProfile.swift
   - VirtualTrainer/Models/WorkoutSessionSummary.swift
   - VirtualTrainer/Models/WorkoutHistoryStore.swift
   - VirtualTrainer/Models/TrophyModels.swift
   - VirtualTrainer/Models/InsightStore.swift
   - VirtualTrainer/Models/AIInsightModels.swift
   - VirtualTrainer/Models/CalibrationRecord.swift
   - VirtualTrainer/Models/CalibrationStore.swift
   - VirtualTrainer/UI/ProfileView.swift
   - VirtualTrainer/UI/WorkoutDetailSheetView.swift
   - VirtualTrainer/UI/TrophiesView.swift
   - VirtualTrainerTests/WorkoutHistoryStoreTests.swift
   - VirtualTrainerTests/TrophyEngineTests.swift
   - VirtualTrainerTests/InsightStoreTests.swift
   - VirtualTrainerTests/CalibrationStoreTests.swift
3. Treat this prompt as implementation guidance, not a blind spec. If the current code reveals a safer approach, choose it and explain why.
4. Do not rewrite MediaPipe, CameraManager, PoseEstimator, UniversalRepCounter, FormFeedbackEngine, HandGestureDetector, ExertionAnalyzer, or the live camera pipeline.
5. Do not add Firebase, Supabase, repository protocols, accountId, SyncMetadata, or WriteOperation in this phase.
6. Preserve deterministic local planning, trophies, stats, trends, recaps, and AI insights.
7. Maintain backwards-compatible Codable decoding for existing local JSON.
8. Keep the app compiling after this phase.
9. Run available tests/build commands and summarize results.
10. Summarize changed files, key decisions, migration behavior, and known follow-ups.

GOAL:
Add backend-safe soft-delete/tombstone semantics for local workout history and dependent insight invalidation.

This phase prepares the app for future offline-first sync. A hard local delete would be resurrected by another device later. Tombstones prevent that.

IMPORTANT PRODUCT DECISIONS:
1. Workout deletion is user-facing.
2. Insight invalidation is user-facing only as a consequence of deleted evidence.
3. Trophy retraction is NOT part of this phase.
4. Deleting a workout should NOT casually remove already-earned trophies.
5. Trophy canonical unlock events will be handled later in C6.
6. Account deletion/export belongs later in C10.
7. accountId belongs later in C1.
8. SyncMetadata belongs later in C2.

MODEL CHANGES:

1. Add deletedAt: Date? with decodeIfPresent defaulting to nil to:
   - UserProfile
   - WorkoutSessionSummary
   - AIInsight
   - CalibrationRecord

2. Add convenience helpers where useful:
   - var isDeleted: Bool { deletedAt != nil }
   - func markedDeleted(at date: Date) -> Self
   - func restored() -> Self

3. Do NOT add normal deletedAt semantics to:
   - TrophyProgress
   - TrophyUnlockEvent
   - TrophyProgressSnapshot
   - InsightDeliveryRecord
   - InsightEngagementRecord

Reason:
- TrophyProgress is derived.
- TrophyUnlockEvent should later use append-only event semantics with optional revokedAt/retractedAt in C6.
- Insight delivery and engagement records are mergeable behavior signals and should not be wiped when one insight is invalidated.

WORKOUT HISTORY STORE:

Current store publishes summaries and persists WorkoutHistory.json.

Refactor carefully so tombstones are not lost.

Implement an internal all-records source of truth:

- private var allSummaries: [WorkoutSessionSummary]
- @Published private(set) var summaries: [WorkoutSessionSummary]

Rules:
- allSummaries includes deleted and non-deleted records.
- summaries is the visible non-deleted projection for SwiftUI and existing UI.
- persist() writes allSummaries, not summaries.
- loadSummaries() loads all records into allSummaries and refreshes summaries by filtering out deleted records.

Add methods:

1. addSummary(_ summary: WorkoutSessionSummary) -> Bool
   - Upsert into allSummaries by id.
   - If summary.deletedAt is nil, it should appear in summaries.
   - Persist allSummaries.
   - Keep existing behavior for non-deleted saves.

2. updateSummary(_ summary: WorkoutSessionSummary) -> Bool
   - Upsert by id.
   - Persist allSummaries.
   - Intended for future safe metadata/update paths, not broad workout editing UI yet.

3. deleteSummary(id: UUID, deletedAt: Date = Date()) -> Bool
   - Find in allSummaries.
   - Set deletedAt.
   - Persist allSummaries.
   - Refresh summaries to hide it.
   - Return false if not found.

4. restoreSummary(id: UUID) -> Bool
   - Find in allSummaries.
   - Clear deletedAt.
   - Persist allSummaries.
   - Refresh summaries.
   - Return false if not found.

5. purgeTombstones(olderThan cutoff: Date) -> Int
   - Hard-remove records whose deletedAt is non-nil and earlier than cutoff.
   - Persist.
   - Return number purged.
   - This should not run automatically in normal app flow yet.

6. fetchRecentSummaries(limit:) should hide deleted records by default.

7. fetchSummary(id:) should hide deleted records by default.

8. Add sync/debug-facing methods:
   - fetchSummaryIncludingDeleted(id:)
   - allSummariesIncludingTombstones()
   - fetchDeletedSummaries()
   - fetchDirtyOrDeletedSummaries placeholder only if easy; otherwise defer to C2.

9. aggregateStats(now:) must ignore deleted workouts.

10. recentWorkoutHistoryItems(limit:) must ignore deleted workouts.

INSIGHT INVALIDATION:

Add InsightStore support:

1. invalidateInsight(dedupeKey: String, deletedAt: Date = Date()) -> Bool
   - Mark matching AIInsight.deletedAt.
   - Persist.
   - Default insight selection must hide deleted insights.
   - Keep InsightDeliveryRecord and InsightEngagementRecord intact.

2. invalidateInsightsReferencingWorkout(id: UUID, deletedAt: Date = Date()) -> Int
   - Find insights whose evidence references the deleted workout id.
   - Mark them deleted.
   - Persist.
   - Return invalidated count.

3. Ensure:
   - selectInsights
   - selectGeneratedInsights
   - insights(for:)
   do not return deleted insights.

CALIBRATION:

Add deletedAt to CalibrationRecord with backwards-compatible decoding.

CalibrationStore:
- Keep existing completed/skipped/failed flows.
- Keep resetForDebug() behavior clearly debug-oriented.
- If there is a production-like reset/delete path, make it tombstone the record instead of hard-deleting.
- Do not add attempts history yet.

USER PROFILE:

Add deletedAt to UserProfile with backwards-compatible decoding.

Do not add production account deletion UI in C3.
Do not change resetOnboarding semantics beyond what is necessary for decoding/persistence compatibility.
Full account deletion/export arrives in C10.

TROPHIES:

Do not add retractTrophy as a normal public product flow in this phase.

When a workout is deleted:
- Recompute trophy progress if current UI/store architecture already makes this straightforward.
- Do not remove already-earned trophy status.
- Do not introduce a new trophy retraction model here.
- Add a TODO/comment that canonical trophy unlock and optional admin/debug retraction will be handled by C6 append-only trophy events.

UI:

1. WorkoutDetailSheetView:
   - Add a simple destructive “Delete Workout” action.
   - Require confirmation.
   - On delete:
     - call WorkoutHistoryStore.deleteSummary(id:)
     - invalidate insights referencing that workout id
     - dismiss the detail sheet
     - trigger any existing stat/trophy refresh if the current architecture supports it
   - Keep UI simple.

2. ProfileView workout history list:
   - Add swipe-to-delete or overflow delete if simple.
   - Use the same delete path.
   - Do not add edit workout UI yet.

3. Empty states:
   - If the deleted workout was the last visible workout, Profile/Dashboard/History should show existing empty states without crashing.

TESTS:

Add or update tests:

WorkoutSessionSummary:
1. Existing legacy JSON without deletedAt decodes with deletedAt == nil.
2. markedDeleted/restored helper works if implemented.
3. Codable roundtrip includes deletedAt.

WorkoutHistoryStore:
1. addSummary saves a visible summary.
2. deleteSummary hides it from summaries.
3. fetchRecentSummaries excludes deleted records.
4. fetchSummary excludes deleted records.
5. fetchSummaryIncludingDeleted returns it.
6. allSummariesIncludingTombstones includes it.
7. restoreSummary makes it visible again.
8. purgeTombstones removes only tombstones older than cutoff.
9. aggregateStats ignores deleted workouts.
10. recentWorkoutHistoryItems ignores deleted workouts.
11. persisted JSON keeps tombstones after reload.
12. addSummary still upserts by id.

InsightStore:
1. AIInsight legacy JSON without deletedAt decodes.
2. invalidateInsight hides an insight from selection.
3. invalidateInsightsReferencingWorkout hides dependent insights.
4. delivery and engagement records are preserved after invalidation.
5. deleted insights are not returned by dashboard/profile/workout summary selection methods.

CalibrationStore:
1. CalibrationRecord legacy JSON without deletedAt decodes.
2. completed/skipped/failed behavior remains unchanged.
3. tombstoned calibration record is not treated as completed if production reset path exists.

UI / integration if feasible:
1. Deleting a workout from detail removes it from visible history.
2. Deleting a workout does not crash Profile/Dashboard.
3. Deleting a workout does not erase earned trophy state.

DOCUMENTATION:

Update:
- Documentation/BackendReadinessMap.md, if present, with a short “C3 implemented” note.
- DEBUG_LOG.md, following existing repo convention.

ACCEPTANCE CRITERIA:
- The app still runs locally with no backend SDK.
- Workout deletes are tombstone-based, not hard deletes.
- Default app views hide deleted workouts.
- Sync-facing methods can still access tombstones.
- Deleted workout evidence invalidates dependent insights.
- Existing local JSON decodes safely.
- Trophies are not incorrectly retracted.
- Tests pass.

### Assistant - 2026-05-07 19:24:22

I’ll first map the repo and read the requested files before touching anything, then I’ll make the smallest backend-safe changes that fit the existing architecture. After that I’ll run the test/build path the project already supports and report the real results.

### Assistant - 2026-05-07 19:24:31

I found the expected Xcode project and noticed the worktree already has untracked documentation files, including `Documentation/`. I’m treating those as existing user work and will only edit the requested docs if the implementation needs it.

### Assistant - 2026-05-07 19:24:52

The docs confirm this is still intentionally local JSON, no backend SDK, and the current readiness map already calls out tombstones as an open sync need. The model style is strongly backward-compatible custom `Codable`, so I’m going to follow that pattern rather than relying on synthesized decoding.

### Assistant - 2026-05-07 19:25:22

The key architecture point is nice and useful here: trophies already merge earned progress forward, so recomputing progress after hiding a deleted workout won’t remove earned trophies. That lines up with the product decision, and I’ll preserve it with a short C6 note rather than inventing retraction now.

### Assistant - 2026-05-07 19:27:51

I’m going to edit the persisted value models first, then the stores, then the small UI surface. The important safety choice is that `WorkoutHistoryStore` will persist the all-record list while publishing only the non-deleted projection, so SwiftUI keeps its current shape while tombstones survive reload.

### Assistant - 2026-05-07 19:36:48

The store/UI edits are in place now. I added the delete affordance in the detail sheet and a compact trash action in profile history, both flowing through the same tombstone path and then invalidating workout-backed insights.

### Assistant - 2026-05-07 19:37:26

I’m updating the readiness doc and debug log now, following the repo’s append-only convention. I’ll keep the note narrow: C3 soft deletes are local-only prep, with no account IDs, sync metadata, repositories, or backend SDKs added.

### Assistant - 2026-05-07 19:37:59

I’m going to run focused XCTest slices first so compile errors surface close to the changes, then I’ll run the broader workspace test/build command if the focused pass is clean.

### Assistant - 2026-05-07 19:38:16

The first focused build caught a small Swift getter issue in `CalibrationStore.status`: adding the guard turned it into a multi-statement getter, so the final expression now needs an explicit `return`. Fixing that and rerunning the focused suite.

### Assistant - 2026-05-07 19:39:23

I’m picking up from the test pass that was already running, then I’ll chase down any compile fallout and run the broader verification. The implementation shape is already in place: hidden tombstones as the durable source, visible projections for app UI, and insight invalidation without trophy retraction.

### Assistant - 2026-05-07 19:39:35

The focused tombstone suites are green, which is a nice sanity checkpoint: workout history, insight invalidation, calibration, and trophy preservation all passed together. I’m running the wider project tests next so we can catch any UI or integration fallout outside the files we touched.

### Assistant - 2026-05-07 19:40:30

The full suite is in the simulator phase now, so while it runs I’m doing a second-pass review of the changed files. This is mostly looking for the sneaky stuff tests don’t always say plainly: persistence source of truth, preview environment objects, and any accidental broadening of product flows.

### Assistant - 2026-05-07 19:40:50

One product wording issue popped up in the review: the confirmation dialog was exposing “tombstone” language to the person using the app. I’m tightening that copy so the backend-safe behavior stays an implementation detail while the UI remains simple: delete means “hide from history.”

### Assistant - 2026-05-07 19:41:17

The full suite passed once, but I made a final copy cleanup while it was already running. I’m rerunning verification on the finished tree now, then I’ll do a clean diff/status pass and wrap it up.

### Assistant - 2026-05-07 19:42:32

Final full test run on the actual completed tree is green. I’m doing one explicit app build now, then a whitespace/status check so the wrap-up can be exact rather than hand-wavy.

### Assistant - 2026-05-07 19:43:33

Implemented the C3 tombstone prep.

Key changes:
- Added backwards-compatible `deletedAt` tombstone fields/helpers to profile, workout summary, AI insight, and calibration record models.
- Refactored [WorkoutHistoryStore.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/WorkoutHistoryStore.swift:55>) to persist `allSummaries` while publishing only visible non-deleted `summaries`.
- Added soft delete, restore, purge, and sync/debug tombstone fetch methods.
- Added insight invalidation in [InsightStore.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/Models/InsightStore.swift:275>) while preserving delivery and engagement records.
- Added confirmed Delete Workout actions in [WorkoutDetailSheetView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/WorkoutDetailSheetView.swift:60>) and [ProfileView.swift](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/VirtualTrainer/UI/ProfileView.swift:43>).
- Left trophies unretracted; recompute uses visible history and has a C6 TODO for append-only unlock/retraction semantics.
- Updated [BackendReadinessMap.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/Documentation/BackendReadinessMap.md:74>) and [DEBUG_LOG.md](</Users/satvik.bansal/Desktop/VirtualTrainer - mediapipe/DEBUG_LOG.md:740>).

Migration behavior: old local JSON without `deletedAt` decodes as active (`nil`). Deletes now stay in `WorkoutHistory.json` as tombstones, default UI/stat/history queries hide them, and sync/debug methods can still access them.

Verification:
- Focused tombstone suites: passed.
- Full `xcodebuild test -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'`: passed.
- `xcodebuild build -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer -destination 'platform=iOS Simulator,name=iPhone 17'`: passed.
- `git diff --check`: clean.

No backend SDK, `accountId`, `SyncMetadata`, repository protocols, or live camera/MediaPipe pipeline changes were added. Known follow-ups remain C2 dirty/sync metadata, C6 canonical trophy events/retraction semantics, and C10 account export/delete. Note: `Documentation/` is currently untracked in this worktree, and the pre-existing untracked `Spotter_Pre_Backend_Readiness.md` remains untouched.
