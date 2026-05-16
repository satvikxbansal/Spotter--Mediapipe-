# App Check Rollout

Phase 16J keeps App Check installed but unenforced. DEBUG builds use Firebase's debug provider for simulator and development-device smoke tests. Release builds install App Attest on iOS 14.5+ before Firebase configures, so the app is ready for production telemetry without changing Firebase Console enforcement yet.

## Debug Token Setup

1. Build a DEBUG app with Firebase mode active and a development Firebase client plist bundled.
2. Launch the app on the simulator or a development device.
3. Find the App Check debug token in the local Xcode console output. Do not paste that token into source, test fixtures, screenshots, shared logs, or documentation.
4. In Firebase Console, open App Check for the iOS app, choose debug token management, and add the copied token with a short device/developer label.
5. Re-launch the app and verify Auth/Firestore continue to work in Firebase mode.

## Staged Firestore Enforcement

### Stage 1: Monitoring Mode

1. In Firebase Console, open App Check.
2. Select Firestore.
3. Keep enforcement set to Unenforced.
4. Collect App Check request metrics for at least 7 days across simulator debug-token testing and release/TestFlight physical-device testing.
5. Confirm anonymous sign-in, basic two-simulator sync, owner-only Firestore reads/writes, listener startup, listener teardown, and account deletion still work.
6. Investigate any invalid, missing, or unknown-token traffic before moving to enforcement.

### Stage 2: Enforce

1. Complete Phase 19 physical-device validation with App Attest.
2. In Firebase Console, open App Check.
3. Select Firestore.
4. Change enforcement from Unenforced to Enforced.
5. Watch App Check, Firestore, Analytics, and Crashlytics dashboards during the first rollout window.

## Why Enforcement Stays Off

Do not enable App Check enforcement in Phase 16J. The app is instrumented and release-ready, but enforcement belongs to Phase 19 after physical-device App Attest validation. Enforcing early could block legitimate developer, TestFlight, or simulator verification even though the code path is now installed.

## Production Path

Release builds use App Attest on supported devices. Keep DeviceCheck fallback only for older OS support if product requirements change; Spotter currently targets iOS 17, so App Attest is the expected production path. Turn on enforcement service by service only after telemetry is healthy and backend QA signs off.
