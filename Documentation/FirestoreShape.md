# Spotter Firestore Shape

This document fixes the target Firestore shape before any Firebase repository code is added.

Spotter is still local-first. This phase adds no Firebase SDK setup, no remote repository implementation, and no upload path. The current source of truth remains local JSON.

## Firestore Size Boundary

Firestore documents have a strict 1 MiB document size limit. Workout summaries can contain set summaries, rep-quality events, cue events, structured effort summaries, sync metadata, and tombstone metadata, so the shape must be chosen from measured size rather than guesswork.

The audit uses the same JSON style as `WorkoutHistoryStore`:

- `JSONEncoder.OutputFormatting.prettyPrinted`
- `JSONEncoder.OutputFormatting.sortedKeys`
- `JSONEncoder.DateEncodingStrategy.iso8601`

It then adds a rough Firestore allowance of:

- JSON bytes * 1.35
- plus 1,024 fixed bytes

This is intentionally conservative. Firestore is not JSON internally, but this keeps room for field/type overhead, future fields, and shape drift.

## Shape Options

### Option A: Embed Everything In The Workout Document

Path:

```text
users/{uid}/workouts/{workoutId}
```

The workout document embeds the compact session fields, every set summary, all cue events, and all rep-quality events.

Pros:

- One read gives the full workout detail.
- Closest to the current local `WorkoutSessionSummary` JSON.

Cons:

- The measured worst case lands too close to Firestore's hard 1 MiB limit.
- Any future evidence field, extra set, longer cue text, or higher-rep session could break saves.
- Harder to paginate or selectively load detail screens.

### Option B: Workout Document Plus Sets Subcollection

Paths:

```text
users/{uid}/workouts/{workoutId}
users/{uid}/workouts/{workoutId}/sets/{setId}
```

The workout document stores compact session-level fields. Each set document stores one `ExerciseSetSummary`, including its small bounded `cueEvents` and `repQualityEvents` arrays.

Pros:

- Workout list/dashboard/profile queries stay small.
- Workout detail can load set evidence when needed.
- Current measured per-set documents have generous headroom.
- Keeps the data model close to existing local Codable models without adding Firebase code yet.

Cons:

- Workout detail needs one subcollection read.
- Future sync code must write a workout and its set documents as one logical operation.

### Option C: Workout Document Plus Sets And Rep Events Subcollections

Paths:

```text
users/{uid}/workouts/{workoutId}
users/{uid}/workouts/{workoutId}/sets/{setId}
users/{uid}/workouts/{workoutId}/sets/{setId}/repQualityEvents/{eventId}
```

The workout document stores compact session fields, each set document stores set aggregates and cue summaries, and rep-quality events move to event documents.

Pros:

- Best headroom for very long/open-ended sets.
- Enables paging or trimming event reads.

Cons:

- More writes per completed workout.
- More reads to show workout detail.
- More migration and idempotency complexity before the app needs it.

## Synthetic Worst-Case Audit

Fixture:

- 8 exercises
- 4 sets per exercise
- 25 rep-quality events per set
- 10 cue events per set
- optional workout, set, cue, rep, effort, sync, and tombstone fields filled
- no raw camera frames, raw video, face images, raw pose streams, raw pose timelines, or raw biometric face data

Measured by `WorkoutSummarySizeAuditTests`:

```text
fullEmbeddedJSONBytes: 660999
fullEmbeddedEstimatedFirestoreBytes: 893373
compactWorkoutDocumentJSONBytes: 1993
compactWorkoutDocumentEstimatedFirestoreBytes: 3715
maxSetDocumentJSONBytes: 20057
maxSetDocumentEstimatedFirestoreBytes: 28101
setDocumentCount: 32
repQualityEventCount: 800
cueEventCount: 320
```

The full embedded shape is below Firestore's hard 1 MiB limit, but it is not comfortably below it. The estimated embedded document is about 893 KB, leaving only about 155 KB of headroom before the hard limit. It also exceeds the 256 KB comfort threshold by a wide margin.

The compact workout document is about 3.7 KB with allowance. The largest set document is about 28.1 KB with allowance, which is comfortably below the 64 KB per-set audit threshold.

## Decision: Option B

Use:

```text
users/{uid}/workouts/{workoutId}
users/{uid}/workouts/{workoutId}/sets/{setId}
```

Store a compact workout summary document at `users/{uid}/workouts/{workoutId}` with session-level facts:

- ids and account ownership
- schema/build version
- mode, plan id/title, title, goal, coach
- started/ended/server-ended timestamps
- duration, total reps, total hold seconds
- average form score and completion percent
- set, rep-event, and cue-event counts
- top cue summary
- effort summary and structured effort summary
- outcome
- total good/excellent/high-severity evidence counts
- created/deleted timestamps
- sync metadata

Store one set summary document per completed set at `users/{uid}/workouts/{workoutId}/sets/{setId}`:

- exercise type
- set index
- target
- achieved reps and hold seconds
- average form score
- rest/skipped/completion-source flags
- completed/duration/peak-effort fields
- best and worst cue text
- set quality summary
- bounded `cueEvents`
- bounded `repQualityEvents`

For now, embed detailed `repQualityEvents` inside the set document because the measured worst-case set is small. If a future audit shows a set document approaching 64 KB, migrate that detail to Option C or store a compact/capped event summary per set.

## Privacy Boundary

Do not store or upload:

- raw video
- camera frames
- face images
- raw pose streams
- raw pose timelines
- raw biometric face data
- raw face blendshape streams
- secrets or API keys

Allowed workout data is derived evidence only: workout summaries, set summaries, cue events, rep-quality events, rest behavior, and derived effort summaries.

## Migration Plan If Shape Changes

If Option B later needs to become Option C:

1. Keep the workout document id stable.
2. Keep each set document id stable.
3. Add a new workout shape/schema version field.
4. Write new workouts with `repQualityEvents/{eventId}` documents.
5. Keep readers backward compatible with embedded per-set `repQualityEvents`.
6. Lazily migrate old set documents when they are edited, repaired, or resynced.
7. Once all active clients understand Option C, optionally strip embedded rep events from old set docs after successful event-document writes.

If a future product chooses to re-embed sets into the workout document, run the size audit first and require the embedded estimate to stay below 256 KB, not merely below Firestore's 1 MiB hard limit.

## Backend Implementation Notes

- Add repository protocols and local implementations before importing Firebase SDKs.
- Use idempotent writes with operation ids.
- In Firebase mode, `UserProfile`, `UserProfile.selectedTheme`, `CalibrationRecord`, active/history plans, trophy unlock events/progress cache, insight documents, insight delivery, and insight engagement are remote-owned durable records as their repositories ship. The existing local JSON files remain a fast launch/cache path only; local mode still treats those JSON files as the durable source of truth.
- Theme has no standalone remote document. `UserProfile.selectedTheme` is the remote source of truth, and `Theme.json` is only the local fast-cache used for immediate UI bootstrapping.
- Treat synced `WorkoutSessionSummary` bodies as immutable; corrections should tombstone and create a replacement summary.
- Write workout and set documents as one logical save.
- Prefer recomputing stats, trends, recaps, and AI insights locally from synced summaries rather than storing derived caches as source of truth.
- Keep deterministic local plan generation, trophies, stats, trends, recaps, and insights intact.
