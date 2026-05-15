# App Check Rollout

Phase 16H installs the App Check debug provider in DEBUG builds before Firebase configures. This prepares Firebase mode for App Check testing without enforcing App Check yet.

## Debug Token Setup

1. Build a DEBUG app with Firebase mode active and a development Firebase client plist bundled.
2. Launch the app on the simulator or a development device.
3. Find the App Check debug token in the local Xcode console output. Do not paste that token into source, test fixtures, screenshots, shared logs, or documentation.
4. In Firebase Console, open App Check for the iOS app, choose debug token management, and add the copied token with a short device/developer label.
5. Re-launch the app and verify Auth/Firestore continue to work in Firebase mode.

## Why Enforcement Stays Off

Do not enable App Check enforcement in Phase 16H. The current Firebase path is still internal and partial, Firestore rules are being published for owner-only access, and the team still needs emulator/live-dev verification for cross-uid denial, listener behavior, and debug-token onboarding. Enforcing now could block legitimate developer testing before those checks are automated.

## Production Path

For production, replace the DEBUG debug-provider setup with an App Attest provider path on iOS 14.5 and newer. Keep DeviceCheck or another reviewed fallback only if product support requires older OS coverage. Turn on enforcement service by service after App Attest telemetry is healthy, denial/error rates are understood, and Phase 17/19 backend QA signs off.
