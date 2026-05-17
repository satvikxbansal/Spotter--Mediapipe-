# Firebase Emulator Setup

Use the Firebase Local Emulator Suite for Phase 17 backend integration tests. Keep emulator runs separate from production projects and do not commit generated secrets or local machine config.

## One-Time Setup

From the repository root:

```bash
firebase init emulators
```

Select:

- Authentication Emulator
- Firestore Emulator
- Ports: Auth `9099`, Firestore `8080`
- Project ID for local use: `spotter-local` or another non-production alias

The app does not require Cloud Storage, Realtime Database, or Functions for this phase.

## Start Emulators

Manual command:

```bash
firebase emulators:start --only auth,firestore
```

Guarded script:

```bash
Scripts/start_firebase_emulators.sh
```

The script checks `127.0.0.1:9099` and `127.0.0.1:8080`, starts the Auth and Firestore emulators in the background when needed, and writes logs to `/tmp/spotter-firebase-emulators.log`.

## App Emulator Opt-In

Add this launch argument to a DEBUG scheme or test plan:

```text
--firebase-emulator
```

For command-line integration tests, the runner script sets the equivalent environment opt-in:

```bash
SPOTTER_FIREBASE_EMULATOR=1
```

When Firebase bootstrap succeeds and either opt-in is present, Spotter routes:

- Firebase Auth -> `localhost:9099`
- Firestore -> `localhost:8080`

The emulator opt-in is ignored when `GoogleService-Info.plist` is absent, so local mode remains fully functional.

## Running Backend Integration Tests

The normal unit suite keeps emulator tests skipped. To run them intentionally:

```bash
Scripts/run_backend_integration_tests.sh
```

That script invokes `Scripts/start_firebase_emulators.sh`, sets `SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1` and `SPOTTER_FIREBASE_EMULATOR=1`, then runs only `VirtualTrainerTests/BackendIntegrationTests` against `VirtualTrainer.xcworkspace`.

To run manually from Xcode instead, start the emulators, set `SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1` in the test scheme environment, and add `--firebase-emulator` to the scheme's test arguments.

## Rules Testing

Automated rules check:

```bash
Scripts/test-firestore-rules.sh
```

The script starts the Firestore emulator, loads `Documentation/firestore.rules`, and runs `Scripts/firestore-rules-tests/index.test.js` with `@firebase/rules-unit-testing`. See `Documentation/FirestoreRulesEmulatorTests.md` for the assertion list and local pre-commit stub.

For manual denial testing:

1. Start emulators.
2. Load the normal rules from `Documentation/firestore.rules`.
3. Run the integration tests once.
4. Temporarily mutate the emulator rules to deny one category, such as workout writes.
5. Run the forbidden-write scenario.
6. Restore the normal rules.

Expected behavior:

- App surfaces a sanitized permission error.
- Local data remains pending or conflict-marked.
- Journal replay succeeds after rules are restored.
- No duplicate docs are created.

## Safety Notes

- Do not point the emulator test suite at a production Firebase project.
- Do not paste plist contents, API keys, App Check debug tokens, service accounts, or bearer tokens into logs.
- Emulator test fixtures must contain only derived workout summaries and metadata, never raw frames, raw pose streams, face images, or raw biometric face data.
