# Firebase Cost Budget

Phase 17 uses a soft budget for the internal beta. The goal is not exact billing prediction; it is an engineering guardrail that keeps write volume visible before inviting more testers.

## Typical Active User Week

Assumption: 5 planned workouts per week.

Per planned workout:

- 1 profile read
- 1 workout write
- ~4 set writes
- 1 trophy event write
- ~2 insight writes
- ~4 insight delivery merges
- ~2 insight engagement merges

Estimated write volume:

```text
5 planned workouts x
(1 workout write + 4 set writes + 1 trophy event + 2 insight writes + 4 delivery merges + 2 engagement merges)
= ~70 direct writes/week
```

Add profile/theme/calibration/plan retries, listener-driven metadata merges, and occasional replays:

```text
Soft budget: ~80 writes/week
4 weeks: ~320 writes/month per active user
10 internal testers: ~3,200 writes/month
```

Read volume depends more on listeners, history windows, and detail screens than on workout count. Current beta expectations:

- Compact history load: recent 80 workouts.
- Detail load: set subcollection only when the workout detail is opened.
- Trophy progress: derived from event docs unless cache is fresh.
- Insight delivery and engagement: merged per dedupe key, not append-only per impression.

## Cost Snapshot Toggle

DEBUG builds include a "Cost Snapshot" toggle in Profile -> Settings & Debug -> Backend -> Sync Diagnostics.

When enabled for the current app session, the toggle logs cumulative Firestore adapter counts:

- Reads from document gets, queries, listeners, and transaction document gets.
- Writes from batch commits and transaction set/update calls.

These are DEBUG-only, session-local adapter counters. They are useful for spotting surprising sync volume, not for exact invoice prediction; transaction counts are recorded after the transaction returns successfully and represent the logical read/write operations the adapter performed.

The output is intentionally sanitized and does not include paths, account IDs, payloads, plist contents, API keys, App Check tokens, or user-entered profile values.

Example shape:

```text
Spotter Firestore Cost Snapshot reads=12 writes=7 reason=commitBatch
```

Use it during internal beta scripts:

1. Enable Cost Snapshot.
2. Sign in anonymously.
3. Run onboarding/profile sync.
4. Save one Free Analysis workout.
5. Save one Planned Workout with 4 sets.
6. Pull on another simulator.
7. Compare session counts with the budget above.

## Guardrails

- Keep detail set documents lazy-loaded.
- Keep listeners debounced.
- Do not start heavy sync while `WorkoutSessionContext.isLive`.
- Queue large workout writes until the live workout ends.
- Prefer merge/idempotent operation IDs over append-only retries.
- Review the Cost Snapshot before expanding beyond ~10 internal testers.
