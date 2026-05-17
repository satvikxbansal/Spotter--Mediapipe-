#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/VirtualTrainerBackendIntegrationDerivedData}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

"$SCRIPT_DIR/start_firebase_emulators.sh"

cd "$REPO_ROOT"
SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1 \
SPOTTER_FIREBASE_EMULATOR=1 \
xcodebuild test \
  -workspace VirtualTrainer.xcworkspace \
  -scheme VirtualTrainer \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:VirtualTrainerTests/BackendIntegrationTests
