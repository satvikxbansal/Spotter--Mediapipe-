# Spotter Secrets And Service Config

Spotter is still local-first. The iOS app should be ready for Firebase client configuration, but it must not become a place where private service credentials live.

## Rules

- Do not put API keys directly in Swift source.
- Do not commit service-role keys, Firebase service account JSON, Admin SDK credentials, `.p8` signing keys, private keys, or backend-only tokens to this iOS repo.
- Do not print secret values in logs, build scripts, README snippets, debug banners, or test output.
- Do not store or upload raw video, camera frames, face images, raw pose streams, raw biometric face data, or raw pose timelines while adding config.
- Keep Firebase/Auth and any third-party service calls local-first until the backend phase explicitly begins.

## Firebase Client Config

Firebase iOS `GoogleService-Info.plist` files are client configuration files, not private service-role keys. They can contain a Firebase client API key, project ID, app ID, and bundle ID. That is different from a service account private key, but the files still need environment discipline.

Use environment-scoped names:

```text
GoogleService-Info-Dev.plist
GoogleService-Info-Prod.plist
```

Current build-setting mapping:

```text
Debug   -> GoogleService-Info-Dev.plist
Beta    -> GoogleService-Info-Dev.plist until a staging/prod beta decision is made
Release -> GoogleService-Info-Prod.plist
```

When the Firebase phase starts, add the selected client plist to the app target deliberately and keep the mapping in `Configurations/*.xcconfig` aligned with the Firebase project the build should use. A future Firebase bootstrap should use that build setting in a deliberate copy/load step, for example by copying the selected file into the name expected by `FirebaseApp.configure()`.

Never add Firebase service account JSON to the app bundle. Service accounts and Admin SDK credentials belong only in trusted backend infrastructure.

## Third-Party AI And Voice Keys

`ElevenLabsService` currently reads `ELEVENLABS_API_KEY` from `Bundle.main` and remains dormant unless configured. Keep that lookup path, but do not commit a real value to Swift source, project files, or `Configurations/*.xcconfig`.

OpenAI, ElevenLabs, generic LLM rewrite, or similar third-party keys should move behind backend functions before production use. The app can send derived, privacy-reviewed training context to a backend later, but it should not ship provider secrets or call LLM services directly from the client.

The existing LLM rewrite seam stays safe because `FeatureFlag.coachInsightLLMRewrite` is off by default and `NoopInsightRewriter` is the default implementation.

## Local Developer Setup

1. Run normal local setup:

   ```sh
   pod install
   ./download_models.sh
   ```

2. Use `VirtualTrainer.xcworkspace`.

3. Keep local config experiments out of git. Most developers should not need this file, but Debug builds may include ignored build-setting overrides from:

   ```text
   Configurations/LocalSecrets.xcconfig
   ```

   Example shape for non-secret local experiments:

   ```text
   LOCAL_BACKEND_BASE_URL = http://127.0.0.1:5001
   ```

4. Do not put production provider keys in `LocalSecrets.xcconfig`. If a feature needs a real third-party key, that is a backend-functions task. Temporary remote-TTS experiments should use a local, uncommitted app configuration only and must not ship.

## Pre-Commit Secret Scan

Recommended before commits:

```sh
gitleaks detect --config .gitleaks.toml --redact --no-banner
```

If `gitleaks` is not installed, run the repository's documented fallback scan from the current task notes or use another scanner that reports only file and line metadata in shared logs.

If a likely secret is found:

1. Stop and remove the value from source.
2. Replace app code with a bundle/config lookup or backend function call as appropriate.
3. Rotate the exposed credential in the provider console.
4. Document the rotation and follow-up in the project notes without copying the secret value.

Firebase client plist findings should be reviewed carefully. A Firebase client API key is not a service-role key, but the file must still be mapped to the correct environment and must not be confused with Admin SDK credentials.
