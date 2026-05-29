# GitHub Push Checklist Before Moving Macs

This checklist answers: what should be pushed to GitHub, what should stay local, and what was found during the handoff audit.

## Current Repo State At Handoff

- Branch: `main`
- Remote: `origin/main`
- Status before this handoff packet: clean and synced
- Untracked non-ignored files before this handoff packet: none
- Ignored local files included `Pods/`, `VirtualTrainer.xcworkspace/`, `GoogleService-Info.plist`, MediaPipe `.task` models, logs, `tmp/`, `.vercel/`, and Xcode user state.

After creating this packet, `.gitignore` was updated to ignore:

```text
Spotter_New_Mac_Handoff/
```

That `.gitignore` change should be committed and pushed so the handoff folder cannot be accidentally staged later.

## Already In Git And Good For Migration

These important files are already tracked:

- `VirtualTrainer.xcodeproj/project.pbxproj`
- `Podfile`
- `Podfile.lock`
- `download_models.sh`
- `Configurations/Debug.xcconfig`
- `Configurations/Beta.xcconfig`
- `Configurations/Release.xcconfig`
- `GoogleService-Info.example.plist`
- `.gitleaks.toml`
- `README.md`
- `Documentation/DEVELOPMENT_SETUP.md`
- `Documentation/SECRETS.md`
- `Documentation/FirebaseEmulatorSetup.md`
- `Documentation/BackendQAChecklist.md`
- `Documentation/firestore.rules`
- `VirtualTrainer/`
- `VirtualTrainerTests/`

## Should Not Be Pushed

Do not push these, even to a private repo:

- `Spotter_New_Mac_Handoff/`
- `GoogleService-Info.plist`
- `GoogleService-Info-Dev.plist`
- `GoogleService-Info-Prod.plist`
- `Configurations/LocalSecrets.xcconfig`
- `.env` or `.env.*`
- Firebase service account JSON
- `.p8`, `.pem`, `.key`
- `Pods/`
- `VirtualTrainer.xcworkspace/` as a generated workspace, except optionally the package lock noted below
- Xcode `xcuserdata/`
- DerivedData
- `tmp/`
- `firestore-debug.log`
- `.DS_Store`

## One Thing Worth Pushing Or Pinning

Firebase is an Xcode Swift Package dependency. The exact resolved versions are currently in:

```text
VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

That file is inside the generated ignored CocoaPods workspace, so it is not currently tracked. The Xcode project can resolve Firebase again on the new Mac from the committed package reference, but tracking the lock prevents accidental version drift.

Recommended options:

Option A, simplest: keep using the handoff packet.

- The handoff packet already preserves `local_files/xcode/Package.resolved`.
- The restore script copies it back after `pod install`.

Option B, better for long-term reproducibility: force-add just the package lock.

```bash
git add .gitignore
git add -f VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "Pin Firebase package resolution"
git push origin main
```

If you choose Option B, keep the rest of `VirtualTrainer.xcworkspace/` ignored. Do not commit workspace user state.

## Push Commands

Minimum recommended push after this handoff work:

```bash
git status -sb
git add .gitignore
git commit -m "Ignore local new Mac handoff packet"
git push origin main
```

Optional reproducibility push:

```bash
git add -f VirtualTrainer.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "Pin Firebase Swift package versions"
git push origin main
```

Run a secret scan before pushing any larger change:

```bash
gitleaks detect --config .gitleaks.toml --redact --no-banner
```

If `gitleaks` is unavailable, at minimum run:

```bash
git status --short --ignored
git diff --cached --name-only
```

Then verify no real plist, service account, key, or handoff folder file is staged.
