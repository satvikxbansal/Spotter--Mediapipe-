# Firebase Functions Plan

Phase 16I is a documentation and iOS scaffolding phase. No Firebase Functions are shipped or deployed from this repository.

Functions live in a separate repository:

```text
spotter-functions
```

Service account keys never ship in the iOS repo. The Functions runtime uses a Firebase project service account configured outside this Swift app; any dedicated service account material must live only in Firebase project secrets, with the managed runtime service account preferred when it is sufficient. Do not add Admin SDK JSON, private keys, `.p8`, `.pem`, OpenAI keys, or other third-party secrets to this Swift repository.

## onAuthUserDelete

Trigger:

```text
auth.user().onDelete()
```

Purpose:

- Fan out account deletion after `Auth.auth().currentUser.delete()` succeeds in the iOS app.
- Recursively delete `users/{uid}/**` with the Firebase Admin SDK.
- Cover durable records the client cannot hard-delete under Firestore rules, including profile, workouts, workout sets, trophy events, trophy progress, insights, insight delivery, insight engagement, and calibration.
- Treat repeated invocations as idempotent. If the user tree is already gone, the function should finish successfully.

Implementation notes:

- Use the Functions Firestore Admin SDK, not iOS client credentials.
- Prefer the Admin SDK recursive delete helper or a bounded paginated traversal with retry/backoff.
- Log only operation metadata such as operation id, uid hash/prefix, document counts, and status. Do not log profile contents, Firebase client API keys, App Check debug tokens, third-party tokens, workout evidence payloads, or secret-like values.
- Do not copy raw video, camera frames, face images, raw pose streams, raw pose timelines, raw biometric face data, or raw face blendshape streams into any deletion queue.

## scheduledTombstoneVacuum

Trigger:

```text
nightly scheduled job
```

Purpose:

- Hard-delete documents whose `deletedAt < now - 30 days`.
- Keep client tombstones available long enough for offline devices to observe deletes.
- Remove old tombstones after the retention window so Firestore does not grow forever.

Scope:

- User-owned tombstoned documents under `users/{uid}/**`.
- Any future top-level operational tombstone collections created by `spotter-functions`.

## operationIdDedupe

Status: optional.

The current iOS rules and client idempotency cover most duplicate-write cases:

- Local writes carry operation IDs.
- Firestore repositories retry safely where each record owns its operation ID.
- Client-side delete can be re-run without blocking the user.

A backend operation-dedupe ledger can still be added later if Functions need at-least-once delivery protection across queues, retries, or external providers. If added, store only operation metadata and TTL it aggressively.

## insightRewriteProxy

Status: future.

The iOS client must not call third-party LLMs directly and must not ship OpenAI, Anthropic, ElevenLabs, or other provider secrets.

A future function can:

1. Accept an `InsightLLMContext` produced from derived, privacy-reviewed training evidence.
2. Validate that the payload contains no raw video, frames, face images, raw pose streams, raw pose timelines, raw biometric face data, raw face blendshape streams, or secret-like values.
3. Call OpenAI or another provider using a server-side secret stored in Firebase project secrets.
4. Return a `RewriteResult`.
5. Let the iOS `RewriteValidator` keep rejecting copy that loses the exercise, action, or evidence anchor.

This proxy is not part of Phase 16I.

## iOS Responsibility In Phase 16I

The iOS app initiates deletion in Firebase mode, stops sync listeners, waits for local writes, attempts the small client-allowed plan cleanup while the Firebase user is still authenticated, requests Firebase Auth account deletion, wipes local files, clears `AccountContext`, and routes the user back to onboarding.

Any cloud cleanup that the client cannot do immediately is intentionally left to `onAuthUserDelete`, with user-facing copy that some cloud data may take up to 7 days to delete.
