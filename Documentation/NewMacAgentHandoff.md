# Agent Handoff Brief For Spotter

This is the working context for a coding agent or developer taking over Spotter on a new Mac.

## Project Identity

- Product name in docs: Spotter
- Xcode project name: VirtualTrainer
- Repository remote: `https://github.com/satvikxbansal/Spotter--Mediapipe-.git`
- Current local branch at handoff: `main`
- Current local commit at handoff: `84fec0a` (`Convo History`)
- Current status at handoff before creating this packet: clean against `origin/main`
- Current repo size before handoff packet: about 582 MB

## What The App Is

Spotter is a SwiftUI iOS fitness coaching app. It uses the camera for on-device pose, hand, gesture, and optional face analysis through MediaPipe. The app is local-first by default and has an optional Firebase mode behind app configuration and debug controls.

Core areas:

- SwiftUI app in `VirtualTrainer/`
- Unit tests in `VirtualTrainerTests/`
- CocoaPods dependency integration through `Podfile`
- Firebase Swift Package integration through the Xcode project
- MediaPipe model files under `VirtualTrainer/Models/`
- Setup and backend docs under `Documentation/`

Read these first:

- `README.md`
- `Documentation/DEVELOPMENT_SETUP.md`
- `Documentation/SECRETS.md`
- `Documentation/FirebaseEmulatorSetup.md`
- `Documentation/BackendQAChecklist.md`
- `Documentation/FirebaseConsoleChecklist.md`

## Dependency Model

Use `VirtualTrainer.xcworkspace`, not `VirtualTrainer.xcodeproj`.

MediaPipe is installed with CocoaPods:

- `Podfile`
- `Podfile.lock`
- Pod: `MediaPipeTasksVision`
- Locked version from `Podfile.lock`: `MediaPipeTasksVision 0.10.33` and `MediaPipeTasksCommon 0.10.33`
- `Pods/` is ignored and must be regenerated with `pod install`

Firebase is installed with Xcode Swift Package Manager:

- Package reference is committed in `VirtualTrainer.xcodeproj/project.pbxproj`
- Minimum version: Firebase iOS SDK `12.13.0`, up to next major
- Products linked: `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`, `FirebaseAppCheck`, `FirebaseAnalytics`, `FirebaseCrashlytics`, `FirebaseRemoteConfig`
- Exact resolved package graph from this Mac is copied to `Spotter_New_Mac_Handoff/local_files/xcode/Package.resolved`
- That lock currently lives under the generated ignored workspace path `VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved`

MediaPipe model assets are local files:

- `pose_landmarker_full.task`
- `hand_landmarker.task`
- `gesture_recognizer.task`
- `face_landmarker.task`

They are ignored by Git and can be restored from this handoff packet or redownloaded with `./download_models.sh`.

## Local-Only Files In This Packet

The handoff includes:

- Firebase client plist: `local_files/firebase/GoogleService-Info.plist`
- MediaPipe task models: `local_files/models/*.task`
- SwiftPM package lock: `local_files/xcode/Package.resolved`

The handoff does not include:

- `Pods/`
- DerivedData
- Xcode user state
- Simulator data
- temporary logs
- service account JSON
- private keys

## Firebase And Secrets Rules

Do not commit real Firebase plist files or service credentials.

Firebase client plist files are not Admin SDK private keys, but they still contain environment-specific client configuration and should remain out of the repo unless the project later makes a deliberate policy decision.

Committed config mapping:

- Debug: `GoogleService-Info-Dev.plist`
- Beta: `GoogleService-Info-Dev.plist`
- Release: `GoogleService-Info-Prod.plist`

There is a Debug-only fallback for a generic `GoogleService-Info.plist`. The restore script copies the handoff plist to both `GoogleService-Info.plist` and, if missing, `GoogleService-Info-Dev.plist`.

Never put these in the iOS repo:

- Firebase service account JSON
- Admin SDK credentials
- `.p8`, `.pem`, `.key`
- OpenAI, ElevenLabs, or other provider secrets
- bearer tokens
- App Check debug tokens in logs

## Backend Mode

The app is local-first. `Configurations/Debug.xcconfig` currently sets:

```text
SPOTTER_BACKEND_MODE = local
```

Firebase only becomes active when the desired backend mode is `firebase` and the app bundle contains a valid `GoogleService-Info.plist`. In DEBUG builds, desired mode can also be changed through the Profile debug UI and is persisted in `UserDefaults` under `spotter.backendMode`; restart the app after changing modes.

## Current Tool Versions On Old Mac

Stored in `local_files/environment/tool_versions.txt`.

Observed at handoff:

- Xcode 26.3, build `17C529`
- Apple Swift 6.2.4 driver, project `SWIFT_VERSION = 5.0`
- CocoaPods 1.16.2
- Ruby 3.3.0
- Git 2.50.1
- macOS Darwin 25.4.0, arm64

## Build Sanity Checks

From the repo root:

```bash
pod install
./download_models.sh
xcodebuild -list -workspace VirtualTrainer.xcworkspace
```

Expected schemes:

- `VirtualTrainer`
- `Pods-VirtualTrainer`
- `MediaPipeTasksCommon`
- `MediaPipeTasksVision`

Open:

```bash
open VirtualTrainer.xcworkspace
```

Use the `VirtualTrainer` scheme.

## Common Failure Modes

If `Module 'MediaPipeTasksVision' not found`:

- Make sure the workspace is open, not the project.
- Run `pod install`.
- Clean Build Folder in Xcode.
- Check that `Pods/` exists.

If Xcode says the CocoaPods sandbox is not in sync:

- Run `pod install` from repo root.

If Firebase packages do not resolve:

- Open `VirtualTrainer.xcworkspace`.
- Let Xcode resolve packages.
- Or run `xcodebuild -resolvePackageDependencies -workspace VirtualTrainer.xcworkspace -scheme VirtualTrainer`.
- If needed, use Xcode `File > Packages > Reset Package Caches`.

If signing fails:

- Sign into Xcode with the Apple ID.
- Select the correct development team.
- The old team ID in the project is `3XM63F6FQR`.
- If using a different personal team, Xcode may require a unique bundle identifier for device installs.

## Agent Behavior Request

Before editing code on the new Mac:

1. Run `git status -sb`.
2. Confirm the handoff restore has been applied.
3. Confirm `pod install` has succeeded.
4. Confirm Xcode resolves Firebase package dependencies.
5. Preserve local-first mode unless the user explicitly asks for Firebase active testing.
6. Do not commit files from `Spotter_New_Mac_Handoff/`, `Pods/`, real `GoogleService-Info*.plist`, `.env`, service accounts, private keys, or Xcode user state.
