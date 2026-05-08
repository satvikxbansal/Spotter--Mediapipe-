# Spotter Sync Conflict Resolution

Spotter is still local-first. This document defines the conflict rules the future repository layer must follow when it finds local and server versions of the same syncable record. The app must mark unresolved records as `conflict` instead of silently overwriting one side.

## General Rule

- `SyncMetadata.localUpdatedAt` is the local dirty timestamp.
- `SyncMetadata.serverVersion` is the future server version token.
- `SyncMetadata.lastSyncedAt` is set only after a server acknowledgement.
- `SyncMetadata.syncState == .conflict` means the repository could not safely merge the versions.
- Raw video, camera frames, face images, raw pose streams, raw biometric face data, and raw pose timelines are never part of conflict payloads.

## UserProfile

Use last-write-wins by `localUpdatedAt` for editable profile and preference fields. Always preserve the earliest valid `createdAt` and `onboardingCompletedAt` so a later device edit cannot rewrite the account's origin story. If both sides changed identity or onboarding fields in ways the resolver cannot compare, keep the record in `conflict`.

## WorkoutSessionSummary

Treat summaries as immutable after sync. A synced workout can be deleted by writing a tombstone (`deletedAt`), but direct mutation of the summary body should become a conflict. Before sync, local edits may still replace the local JSON entry. After sync, corrections should use tombstone delete plus a new summary document.

## TrophyProgress

Treat trophy progress as derived state. The canonical source for unlocks is the `TrophyUnlockEvent` log, not a device-specific progress snapshot. A merged progress view may be recomputed from workout history, calibration state, and canonical unlock events.

## TrophyUnlockEvent

Treat unlock events as append-only. If duplicate unlocks exist for the same account and trophy, the earliest server timestamp wins. Later duplicates can be retained for audit/debug while the user-facing trophy uses the earliest canonical `earnedAt`.

## AIInsight

Merge by `dedupeKey`. The latest `sourcePolicyVersion` wins because policy changes can invalidate older narratives. If the insight's evidence was tombstoned or otherwise invalidated, the insight should be tombstoned or marked invalid instead of resurfacing stale advice.

## InsightDeliveryRecord

Merge by `dedupeKey`. Preserve the earliest `firstPresentedAt`, use the latest `lastPresentedAt`, merge each surface by max `lastPresentedAt`, and use the max `presentationCount`. Delivery records are aggregate counters rather than per-impression event logs, so max is idempotent when the same remote aggregate is applied again and avoids overstating impressions.

## InsightEngagementRecord

Merge by `dedupeKey`. Sum engagement counts and keep the max last-engagement date for each engagement kind. This keeps helpful/not-helpful/opened/dismissed signals multi-device aware without losing local learning.

## CalibrationRecord

A completed calibration beats skipped or failed records when the completed record passes validation. If neither side is a valid completed record, use the latest `localUpdatedAt`. If two completed records disagree in a way that affects safety or camera readiness, preserve the latest valid completion and keep the older record as historical evidence when an attempts log exists.

## Theme

Use last-write-wins by `localUpdatedAt`. Theme is a preference, and the standalone theme envelope can safely follow the same preference rule if it remains separate from `UserProfile.selectedTheme`.
