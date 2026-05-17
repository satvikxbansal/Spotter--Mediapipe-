# Firestore Rules Emulator Tests

Spotter keeps Firestore rules testable outside Xcode so backend hardening can be checked before publishing rules in Firebase Console.

## Run

From the repository root:

```bash
Scripts/test-firestore-rules.sh
```

The script:

- Starts the Firestore emulator for the local project.
- Loads `Documentation/firestore.rules` through `@firebase/rules-unit-testing`.
- Runs `Scripts/firestore-rules-tests/index.test.js`.
- Exits non-zero if any allow/deny assertion fails.

The first run installs Node test dependencies and `firebase-tools` into a temporary directory under `/tmp` when they are not already available; no npm package, lockfile, or `node_modules` folder is written into the repo.

## Coverage

The rules suite verifies:

- Cross-uid profile reads and writes are denied.
- The authenticated owner can write `profile/current` when `accountId == uid`.
- Arbitrary `users/{uid}` root fields are denied.
- Reserved root user metadata with only allowlisted fields is allowed.
- Raw sensor and secret-like field names are denied in user subcollections.
- Workout tombstone merge writes are allowed.
- Normal workout writes are allowed.
- Trophy events are create-only.
- Insights can be created and updated, but not deleted.

## Pre-Commit Stub

To run the same check before local commits, copy or symlink:

```bash
Scripts/pre-commit-firestore-rules.sample.sh
```

to:

```bash
.git/hooks/pre-commit
```

Keep this hook local until CI wiring is added.
