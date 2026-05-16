# Firebase Console Checklist

Phase 16J keeps Firebase available for internal testing only. Do not turn on broader account providers, App Check enforcement, Storage, RTDB, or Functions yet.

## Console Setup

- Auth: enable Anonymous sign-in.
- Auth: keep email/password, phone, Google, Apple, and all other providers disabled until Phase 19.
- Firestore Rules: paste the exact contents of `Documentation/firestore.rules` and publish after review.
- Firestore Indexes: create none initially. Let Firebase auto-suggest indexes from runtime errors, then document each accepted index in the table below.
- Remote Config: create the parameters in the table below. Keep the console defaults aligned with `FeatureFlags.default`.
- Analytics: verify the dashboard receives the Phase 16J taxonomy only; do not add PII parameters or raw rep/frame streams.
- Crashlytics: verify firebase-mode launches show custom keys for `backendMode` and `schemaVersions`. Do not configure user identifiers from display names.
- App Check: register the iOS app for debug usage.
- App Check: do not enable enforcement for Auth, Firestore, Storage, Functions, or any other service yet.
- Storage: keep disabled.
- Realtime Database: keep disabled.
- Functions: do not deploy functions yet. Phase 16I documents the future plan in `Documentation/FirebaseFunctionsPlan.md`; implementation lives later in the separate `spotter-functions` repo.

## Remote Config Parameters

| Parameter | Default | Purpose |
|---|---:|---|
| `backendSyncEnabled` | `true` | Firebase sync kill switch. Setting false stops listeners and skips full sync while local mode remains unchanged. |
| `coachInsightLLMRewrite` | `false` | Enables the guarded rewrite path for coach insights when a future remote rewriter is available. |
| `quickStartDeckVersion` | `quick-start-deck-v1` | Bumps deterministic Quick Start deck generation without changing local decoding. |
| `trophyCatalogVersion` | `1` | Reserves a remote catalog version marker for future trophy rollout checks. |
| `runningAnalysisEnabled` | `false` | Marks the Running Analysis quick action as preview-only until the dedicated flow ships. |
| `designSystemV2Enabled` | `false` | Reserves a design-system rollout switch for future UI migration. |

## Firestore Index Log

No indexes are required initially.

| Date | Query / Feature | Firebase suggested index | Status |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Manual Smoke Checks

- Cross-uid denial: using Firebase Emulator Suite or the live dev project, authenticate as one anonymous user and attempt a write at `users/SOME_OTHER_UID/profile/current` where `SOME_OTHER_UID` is different from the auth UID. Confirm Firestore denies the write.
- Remote Config defaults: launch with network unavailable or Remote Config blocked and confirm dashboard planning, insights, and sync use bundled defaults.
- Remote Config kill switch: set `backendSyncEnabled=false` in a dev Firebase project, fetch Remote Config, and confirm local workouts still save while Firestore listeners stop.
- Analytics privacy: complete onboarding, calibration, a free-analysis save, a planned-workout save, an insight helpful/not-helpful tap, and a heatmap share render. Confirm event parameters contain only taxonomy keys like `mode`, `type`, `surface`, `id`, `rarity`, `kind`, `domain`, and `outcome`.
- Crashlytics context: launch in firebase mode and confirm custom keys appear for `backendMode=firebase` and `schemaVersions`. If a user id appears, it must be an 8-character SHA-256 prefix, not display name or raw account id.
- App Check monitoring: keep Firestore Unenforced and watch metrics before Phase 19 enforcement.
- Local fallback: remove all real Firebase client plists from the working tree, build `BackendMode.local`, and confirm onboarding, dashboard planning, free analysis entry, planned workouts, trophies, stats, trends, recaps, weekly recaps, heatmaps, and AI insights still work locally.
