# Firebase Console Checklist

Phase 16H keeps Firebase available for internal testing only. Do not turn on broader account providers, App Check enforcement, Storage, RTDB, or Functions yet.

## Console Setup

- Auth: enable Anonymous sign-in.
- Auth: keep email/password, phone, Google, Apple, and all other providers disabled until Phase 19.
- Firestore Rules: paste the exact contents of `Documentation/firestore.rules` and publish after review.
- Firestore Indexes: create none initially. Let Firebase auto-suggest indexes from runtime errors, then document each accepted index in the table below.
- App Check: register the iOS app for debug usage.
- App Check: do not enable enforcement for Auth, Firestore, Storage, Functions, or any other service yet.
- Storage: keep disabled.
- Realtime Database: keep disabled.
- Functions: do not deploy functions yet. Phase 16I documents the future plan in `Documentation/FirebaseFunctionsPlan.md`; implementation lives later in the separate `spotter-functions` repo.

## Firestore Index Log

No indexes are required initially.

| Date | Query / Feature | Firebase suggested index | Status |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Manual Smoke Checks

- Cross-uid denial: using Firebase Emulator Suite or the live dev project, authenticate as one anonymous user and attempt a write at `users/SOME_OTHER_UID/profile/current` where `SOME_OTHER_UID` is different from the auth UID. Confirm Firestore denies the write.
- Local fallback: remove all real Firebase client plists from the working tree, build `BackendMode.local`, and confirm onboarding, dashboard planning, free analysis entry, planned workouts, trophies, stats, trends, recaps, weekly recaps, heatmaps, and AI insights still work locally.
