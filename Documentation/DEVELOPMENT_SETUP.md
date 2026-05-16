# Spotter Development Setup

Spotter builds from the Xcode workspace, not the bare project. Use this setup on a fresh clone before opening the app in Xcode.

## Required Toolchain

Use the bundled Xcode toolchain:

```sh
xcrun --find clang
xcrun --find swiftc
```

Both paths should resolve under:

```text
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
```

Do not use the standalone Swift 6.2 toolchain for normal app builds. DEBUG_LOG entry DL-045 documents a Firebase/gRPC binary-framework build failure where Xcode's custom Swift 6.2 clang crashed during stub injection with `clang frontend command failed`, `Abort trap: 6`, and missing `swbuild.tmp/.../Data.noindex/*.o` files. The fix is to switch Xcode's active Toolchain back to the bundled Xcode toolchain and confirm the `xcrun` paths above.

## First-Clone Setup

Install CocoaPods dependencies:

```sh
pod install
```

Download MediaPipe model assets:

```sh
./download_models.sh
```

Open the workspace:

```sh
open VirtualTrainer.xcworkspace
```

Avoid opening `VirtualTrainer.xcodeproj` directly. The workspace contains the CocoaPods app integration and the Firebase Swift Package graph expected by the `VirtualTrainer` scheme.

## Optional Firebase Client Config

Spotter must build and run in local-only mode without a Firebase plist. For Firebase development, copy your ignored development client config to the repository root:

```text
GoogleService-Info-Dev.plist
```

Debug builds read `GOOGLE_SERVICE_INFO_PLIST` from `Configurations/Debug.xcconfig` and copy the configured plist into the app bundle as `GoogleService-Info.plist`. A legacy ignored `GoogleService-Info.plist` fallback is accepted for Debug only. Beta and Release builds only use their configured environment plist names, so a generic local debug plist cannot silently become a non-debug Firebase config. The committed `GoogleService-Info.example.plist` shows the expected shape with placeholder values only.

Do not commit real `GoogleService-Info*.plist` files, service account JSON, private keys, `.p8`, `.pem`, or third-party provider secrets.

## Backend Mode

Debug currently defaults to:

```text
SPOTTER_BACKEND_MODE = local
```

Firebase bootstrap only runs when the desired backend mode is `firebase` and a valid client plist is bundled. Local mode remains the default, and the app's planning, trophies, stats, trends, recaps, heatmaps, and insights continue to run from local data with no Firebase plist.

## DerivedData Hygiene

Use a single `xcodebuild test` process per DerivedData path. Do not run parallel test commands against the same DerivedData directory, because simulator builds and package artifacts can contend with each other.

Recommended command shape:

```sh
xcodebuild test \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/VirtualTrainerDerivedData
```

If you hit the clang/gRPC trap from DL-045, fix the active Xcode toolchain first, then clear the affected DerivedData path and rebuild.
