# Spotter New Mac Setup Guide

## Purpose

This guide explains how to move Spotter from the old Mac to a new Mac without copying the whole repository folder. The correct source of truth is the private GitHub repository, plus this small local handoff packet for files that Git intentionally ignores.

The goal is:

1. Clone the repo from GitHub.
2. Reinstall generated dependencies.
3. Restore local-only Firebase and MediaPipe assets.
4. Open the correct Xcode workspace.
5. Build and continue development without redoing prior work.

## Executive Summary

Do not zip the whole project folder. The repo contains generated and ignored directories that are large, machine-specific, or safe to recreate.

There are two separate things to preserve:

```text
1. GitHub private repo
   Tracks source code and safe setup documentation, including this guide.

2. Spotter_New_Mac_Handoff.zip
   Private local packet with ignored restore assets such as Firebase plist,
   MediaPipe model files, and the current SwiftPM package lock.
```

If you only clone GitHub on the new Mac, you will still have the instructions. You will not have the private restore assets unless you also move `Spotter_New_Mac_Handoff.zip` through Drive, AirDrop, USB, or another private transfer method.

Use this model:

```text
GitHub private repo
  -> source code, Xcode project, Podfile, Podfile.lock, docs, tests

Fresh Mac setup
  -> Xcode, command line tools, Git, CocoaPods

Handoff folder
  -> Firebase client plist, MediaPipe models, SwiftPM package lock, setup notes
```

On the new Mac, the short version is:

```bash
git clone https://github.com/satvikxbansal/Spotter--Mediapipe-.git
cd "Spotter--Mediapipe-"
pod install
bash Spotter_New_Mac_Handoff/scripts/restore_local_files.sh
open VirtualTrainer.xcworkspace
```

Use the detailed steps below the first time.

## What Was Found On The Old Mac

The old local repo was clean and synced with `origin/main` before this handoff packet was created.

Important local facts:

- Repo branch: `main`
- Repo commit: `84fec0a`
- Remote: `https://github.com/satvikxbansal/Spotter--Mediapipe-.git`
- Repo size before handoff packet: about 582 MB
- `.git` directory size: about 138 MB
- `Pods/` size: about 267 MB
- MediaPipe model files: about 29 MB
- `WorkoutClassifier.mlproj`: about 91 MB and tracked
- `Codex_Conversation_History`: about 29 MB and tracked

Generated or local-only files were intentionally ignored:

- `Pods/`
- `VirtualTrainer.xcworkspace/`
- `GoogleService-Info.plist`
- `VirtualTrainer/Models/*.task`
- `tmp/`
- `.vercel/`
- `firestore-debug.log`
- `.DS_Store`
- Xcode user state

## What This Handoff Packet Preserves

This folder preserves only the local files that help a new machine behave like the old one:

```text
Spotter_New_Mac_Handoff/
  README.md
  docs/
    Agent_Handoff_Brief.md
    GitHub_Push_Checklist.md
    Spotter_New_Mac_Setup_Guide.md
    Spotter_New_Mac_Setup_Guide.pdf
  local_files/
    firebase/
      GoogleService-Info.plist
    models/
      face_landmarker.task
      gesture_recognizer.task
      hand_landmarker.task
      pose_landmarker_full.task
    xcode/
      Package.resolved
    environment/
      tool_versions.txt
  scripts/
    restore_local_files.sh
```

Keep this folder private. It is ignored by Git.

## What Not To Transfer

Do not transfer these unless you have a specific reason:

- `Pods/`
- DerivedData
- Xcode package caches
- simulator device folders
- Xcode `xcuserdata`
- `.DS_Store`
- `tmp/`
- old build logs

These are either regenerated, machine-specific, or noisy.

## Step 1: Prepare The New Mac

Install Xcode first.

1. Install Xcode from the App Store or Apple Developer downloads.
2. Open Xcode once so it installs additional components.
3. In Terminal, select Xcode as the active developer directory:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

4. Accept the license if prompted:

```bash
sudo xcodebuild -license accept
```

5. Run first-launch setup:

```bash
sudo xcodebuild -runFirstLaunch
```

6. Confirm tools resolve through Xcode:

```bash
xcrun --find clang
xcrun --find swiftc
xcodebuild -version
swift --version
```

The `xcrun` paths should be under:

```text
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
```

This matters because the repo docs mention a prior Firebase/gRPC binary-framework failure when Xcode used the wrong standalone Swift toolchain.

## Step 2: Install Git And Homebrew

Git may already exist after Xcode command line tools are installed:

```bash
git --version
```

If Homebrew is not installed, install it from the official Homebrew instructions. After installation, check:

```bash
brew --version
```

If you use Conda, deactivate it before installing/running CocoaPods:

```bash
conda deactivate
```

CocoaPods/Ruby problems are easier to avoid when Terminal is using the normal macOS/Homebrew environment.

## Step 3: Install CocoaPods

The old Mac used CocoaPods `1.16.2`.

Recommended:

```bash
brew install cocoapods
pod --version
```

If Homebrew installs a newer compatible CocoaPods version, that is usually fine because `Podfile.lock` pins the actual pods. If you need the exact version:

```bash
gem install cocoapods -v 1.16.2
pod --version
```

If `pod` is not found after installing, restart Terminal and check your PATH.

Optional developer tools:

```bash
brew install gitleaks
```

Use `gitleaks` before commits that touch config or docs.

## Step 4: Clone The Private Repo

Use either HTTPS or SSH.

HTTPS:

```bash
cd ~/Desktop
git clone https://github.com/satvikxbansal/Spotter--Mediapipe-.git
cd "Spotter--Mediapipe-"
```

SSH:

```bash
cd ~/Desktop
git clone git@github.com:satvikxbansal/Spotter--Mediapipe-.git
cd "Spotter--Mediapipe-"
```

Check the state:

```bash
git status -sb
git log --oneline -5
```

You should be on `main`, tracking `origin/main`.

## Step 5: Copy The Handoff Folder Into The Clone

Put the whole folder here:

```text
Spotter--Mediapipe-/Spotter_New_Mac_Handoff/
```

The repo `.gitignore` is updated to ignore it.

Verify:

```bash
ls Spotter_New_Mac_Handoff
```

You should see:

```text
README.md
docs
local_files
scripts
```

## Step 6: Recreate CocoaPods

From the repo root:

```bash
pod install
```

This recreates:

- `Pods/`
- `VirtualTrainer.xcworkspace`
- CocoaPods support files
- MediaPipe framework integration

Do not open the `.xcodeproj` directly. Use the workspace.

If CocoaPods says the specs repo is stale, run:

```bash
pod install --repo-update
```

If CocoaPods says the sandbox is not in sync, run:

```bash
pod install
```

## Step 7: Restore Local Files From The Handoff Packet

Run:

```bash
bash Spotter_New_Mac_Handoff/scripts/restore_local_files.sh
```

The script restores:

- `GoogleService-Info.plist`
- `GoogleService-Info-Dev.plist`, if missing
- `VirtualTrainer/Models/*.task`
- `VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved`

It backs up existing destination files before overwriting them.

If you prefer manual restore:

```bash
cp Spotter_New_Mac_Handoff/local_files/firebase/GoogleService-Info.plist ./GoogleService-Info.plist
cp Spotter_New_Mac_Handoff/local_files/firebase/GoogleService-Info.plist ./GoogleService-Info-Dev.plist
cp Spotter_New_Mac_Handoff/local_files/models/*.task ./VirtualTrainer/Models/
mkdir -p VirtualTrainer.xcworkspace/xcshareddata/swiftpm
cp Spotter_New_Mac_Handoff/local_files/xcode/Package.resolved VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

## Step 8: MediaPipe Model Files

The app expects these model files in the app bundle:

- `pose_landmarker_full.task`
- `hand_landmarker.task`
- `gesture_recognizer.task`
- `face_landmarker.task`

They live in:

```text
VirtualTrainer/Models/
```

The handoff restore script copies them from the old Mac. If they are missing or you want fresh copies:

```bash
./download_models.sh
```

These files are ignored by Git because they are large binary model assets. They are public MediaPipe model downloads, not project secrets.

## Step 9: Firebase Client Config

The handoff packet includes the old Mac's local:

```text
GoogleService-Info.plist
```

The project's intended environment names are:

```text
Debug   -> GoogleService-Info-Dev.plist
Beta    -> GoogleService-Info-Dev.plist
Release -> GoogleService-Info-Prod.plist
```

Debug builds also accept a generic `GoogleService-Info.plist` fallback. The restore script copies the handoff plist to both `GoogleService-Info.plist` and `GoogleService-Info-Dev.plist` if `GoogleService-Info-Dev.plist` is missing.

For production or TestFlight later, download the correct production plist from Firebase Console and save it as:

```text
GoogleService-Info-Prod.plist
```

Do not commit real `GoogleService-Info*.plist` files.

Do not ever put these in the iOS repo:

- Firebase service account JSON
- Admin SDK private keys
- `.p8`, `.pem`, `.key`
- OpenAI keys
- ElevenLabs keys
- bearer tokens
- App Check debug tokens

## Step 10: Understand Firebase Mode

Spotter is local-first by default.

Current Debug config:

```text
SPOTTER_BACKEND_MODE = local
```

That means the app can launch, onboard, plan workouts, analyze camera sessions, save local history, compute trophies, and show insights without Firebase.

Firebase only becomes active when:

1. Desired backend mode is `firebase`.
2. A valid Firebase client plist is bundled as `GoogleService-Info.plist`.
3. Firebase bootstrap succeeds.

In DEBUG builds, the Profile debug UI can change desired backend mode. After switching to Firebase, restart the app so the mode applies at launch.

If Firebase mode is requested but no plist is bundled, the app intentionally falls back to local mode and shows a safe status message.

## Step 11: Resolve Swift Packages

Firebase is installed through Xcode Swift Package Manager, not CocoaPods.

The Xcode project references:

```text
https://github.com/firebase/firebase-ios-sdk
minimum version 12.13.0, up to next major
```

Products linked:

- `FirebaseCore`
- `FirebaseAuth`
- `FirebaseFirestore`
- `FirebaseAppCheck`
- `FirebaseAnalytics`
- `FirebaseCrashlytics`
- `FirebaseRemoteConfig`

The handoff packet preserves the exact old package graph in:

```text
Spotter_New_Mac_Handoff/local_files/xcode/Package.resolved
```

After restore, run:

```bash
xcodebuild -resolvePackageDependencies \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer
```

Or simply open Xcode and let it resolve packages.

If package resolution fails:

1. Confirm the Mac has internet access.
2. Open `VirtualTrainer.xcworkspace`.
3. In Xcode, choose `File > Packages > Reset Package Caches`.
4. Quit and reopen Xcode.
5. Run the `xcodebuild -resolvePackageDependencies` command again.

## Step 12: Open The Correct Xcode File

Always open:

```bash
open VirtualTrainer.xcworkspace
```

Do not open:

```text
VirtualTrainer.xcodeproj
```

The workspace is required because CocoaPods integrates MediaPipe through workspace-level generated projects and support files.

Expected schemes from `xcodebuild -list -workspace VirtualTrainer.xcworkspace`:

- `VirtualTrainer`
- `Pods-VirtualTrainer`
- `MediaPipeTasksCommon`
- `MediaPipeTasksVision`

Select the `VirtualTrainer` scheme to run the app.

## Step 13: Configure Signing

Open Xcode:

1. Open `VirtualTrainer.xcworkspace`.
2. Select the `VirtualTrainer` project.
3. Select the `VirtualTrainer` target.
4. Open `Signing & Capabilities`.
5. Sign in with your Apple ID under Xcode settings if needed.
6. Select your development team.

Current project team ID from the old Mac:

```text
3XM63F6FQR
```

Current bundle identifier:

```text
satvik.VirtualTrainer
```

If you are using the same Apple Developer account, Xcode may work after signing in. If you are using a different personal team, Xcode may require a unique bundle identifier for physical device installs.

For camera testing, a physical iPhone is best. The simulator may build and launch but cannot reproduce the real live camera workflow properly.

## Step 14: First Build

In Xcode:

1. Select `VirtualTrainer` scheme.
2. Select an iOS simulator or connected iPhone.
3. Let packages finish resolving.
4. Press Build.

Command-line build/list check:

```bash
xcodebuild -list -workspace VirtualTrainer.xcworkspace
```

Command-line test shape from existing docs:

```bash
xcodebuild test \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/VirtualTrainerDerivedData
```

Use one build/test process per DerivedData path.

## Step 15: Validate The App Launches

For local mode:

1. Launch the app.
2. Complete onboarding.
3. Check Dashboard.
4. Open Camera/Form Check.
5. Confirm camera permission prompt appears on device.
6. Start a simple exercise such as squat.
7. Confirm skeleton/rep analysis initializes.

For Firebase mode:

1. Confirm `GoogleService-Info-Dev.plist` exists in repo root.
2. Switch desired backend mode to Firebase in DEBUG Profile tools.
3. Restart the app.
4. Confirm active backend mode is Firebase.
5. Try anonymous sign-in from Profile debug tools.
6. Run the Firebase smoke test only against dev/emulator.

Do not test production Firebase casually.

## Step 16: Optional Firebase Emulator Setup

For backend integration testing:

```bash
brew install firebase-cli
firebase login
```

If Homebrew does not have `firebase-cli` in your environment, use npm instead:

```bash
npm install -g firebase-tools
firebase login
```

Then initialize the local emulators:

```bash
firebase init emulators
```

Select:

- Authentication Emulator
- Firestore Emulator
- Auth port `9099`
- Firestore port `8080`

Start emulators:

```bash
Scripts/start_firebase_emulators.sh
```

Run backend tests:

```bash
Scripts/run_backend_integration_tests.sh
```

Run Firestore rules tests:

```bash
Scripts/test-firestore-rules.sh
```

Read:

- `Documentation/FirebaseEmulatorSetup.md`
- `Documentation/FirestoreRulesEmulatorTests.md`
- `Documentation/BackendQAChecklist.md`

## Troubleshooting

### Module MediaPipeTasksVision Not Found

Most likely cause: opened `.xcodeproj` instead of `.xcworkspace`, or pods are missing.

Fix:

```bash
pod install
open VirtualTrainer.xcworkspace
```

Then in Xcode:

- Select `VirtualTrainer` scheme.
- Clean Build Folder.
- Build again.

### CocoaPods Sandbox Is Not In Sync

Fix:

```bash
pod install
```

If needed:

```bash
pod deintegrate
pod install
```

Use `pod deintegrate` only if normal `pod install` fails repeatedly.

### Firebase Packages Do Not Resolve

Fix:

```bash
xcodebuild -resolvePackageDependencies \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer
```

If that fails:

- Check internet.
- Reset package caches in Xcode.
- Clear DerivedData for this project.
- Reopen workspace.

### Firebase Mode Says Missing Config

Check:

```bash
ls GoogleService-Info.plist GoogleService-Info-Dev.plist
```

For Debug Firebase mode, at least one should exist. The build phase copies the selected plist into the built app bundle as `GoogleService-Info.plist`.

If using Release, you need:

```text
GoogleService-Info-Prod.plist
```

### App Builds But Firebase Stays Local

Check:

- `SPOTTER_BACKEND_MODE` in `Configurations/Debug.xcconfig`
- Desired backend mode in DEBUG Profile tools
- Whether the app was restarted after changing mode
- Whether the Firebase plist was bundled
- Profile backend status message

Local fallback is intentional and safe.

### Signing Fails

Fix:

- Sign into Xcode.
- Pick a development team.
- Let Xcode manage signing.
- If using a physical iPhone, enable Developer Mode on the iPhone.
- If bundle ID conflict appears, change bundle ID for your development team.

### Xcode Uses The Wrong Toolchain

Check:

```bash
xcrun --find clang
xcrun --find swiftc
```

Both should resolve under:

```text
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
```

If not:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

In Xcode, use the default Xcode toolchain, not a standalone custom Swift toolchain.

### MediaPipe Models Missing

Restore from handoff:

```bash
bash Spotter_New_Mac_Handoff/scripts/restore_local_files.sh
```

Or redownload:

```bash
./download_models.sh
```

Confirm:

```bash
ls -lh VirtualTrainer/Models/*.task
```

### Git Shows The Handoff Folder

The repo should ignore:

```text
Spotter_New_Mac_Handoff/
```

If Git still shows it:

```bash
git status --short --ignored
```

Do not stage it. Confirm `.gitignore` contains the handoff folder entry.

## What To Push To GitHub Before Moving

Minimum recommended:

```bash
git add .gitignore
git commit -m "Ignore local new Mac handoff packet"
git push origin main
```

Optional but useful for Firebase reproducibility:

```bash
git add -f VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "Pin Firebase Swift package versions"
git push origin main
```

Before any push, check:

```bash
git status -sb
git diff --cached --name-only
```

Make sure these are not staged:

- `Spotter_New_Mac_Handoff/`
- real `GoogleService-Info*.plist`
- `Pods/`
- `.env`
- service account JSON
- private keys
- Xcode user state

## Final New Mac Checklist

Use this as a quick completion check:

- Xcode installed and selected.
- Git works.
- CocoaPods installed.
- Private repo cloned.
- Handoff folder copied into repo root.
- `pod install` completed.
- Handoff restore script completed.
- MediaPipe `.task` files exist.
- Firebase plist exists locally if Firebase testing is needed.
- `Package.resolved` restored or packages resolved by Xcode.
- Opened `VirtualTrainer.xcworkspace`.
- `VirtualTrainer` scheme selected.
- Signing team selected.
- App builds.
- Local mode launches.
- Physical-device camera flow tested when available.

After this, you can continue exactly from the GitHub state plus the local handoff assets.
