#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ID="${FIREBASE_EMULATOR_PROJECT_ID:-spotter-rules-test}"
FIRESTORE_HOST="${FIRESTORE_EMULATOR_HOSTNAME:-127.0.0.1}"
FIRESTORE_PORT="${FIRESTORE_EMULATOR_PORT:-8080}"
IMPORT_DIR="$REPO_ROOT/tmp/empty"
NODE_DEPS_DIR="${TMPDIR:-/tmp}/spotter-firestore-rules-node"
EMULATOR_LOG="${FIRESTORE_RULES_EMULATOR_LOG:-/tmp/spotter-firestore-rules-emulator.log}"
EMULATOR_PID=""
FIREBASE_CMD=""
OPENJDK_PREFIX=""

port_is_open() {
  nc -z "$1" "$2" >/dev/null 2>&1
}

cleanup() {
  if [[ -n "$EMULATOR_PID" ]] && kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
    kill "$EMULATOR_PID" >/dev/null 2>&1 || true
    wait "$EMULATOR_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js and npm are required to run Firestore rules tests." >&2
  exit 1
fi

if ! command -v java >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  OPENJDK_PREFIX="$(brew --prefix openjdk@21 2>/dev/null || brew --prefix openjdk 2>/dev/null || true)"
  if [[ -n "$OPENJDK_PREFIX" && -d "$OPENJDK_PREFIX/libexec/openjdk.jdk/Contents/Home/bin" ]]; then
    export JAVA_HOME="$OPENJDK_PREFIX/libexec/openjdk.jdk/Contents/Home"
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
fi

if ! command -v java >/dev/null 2>&1; then
  echo "Java is required to run the Firestore emulator. Install OpenJDK 21 or set JAVA_HOME." >&2
  exit 1
fi

mkdir -p "$IMPORT_DIR" "$NODE_DEPS_DIR"

if [[ ! -d "$NODE_DEPS_DIR/node_modules/@firebase/rules-unit-testing" ||
      ! -d "$NODE_DEPS_DIR/node_modules/firebase" ||
      ! -d "$NODE_DEPS_DIR/node_modules/firebase-tools" ]]; then
  npm install \
    --prefix "$NODE_DEPS_DIR" \
    --no-save \
    --no-package-lock \
    --no-audit \
    --no-fund \
    @firebase/rules-unit-testing \
    firebase \
    firebase-tools
fi

if command -v firebase >/dev/null 2>&1; then
  FIREBASE_CMD="$(command -v firebase)"
else
  FIREBASE_CMD="$NODE_DEPS_DIR/node_modules/.bin/firebase"
fi

if port_is_open "$FIRESTORE_HOST" "$FIRESTORE_PORT"; then
  echo "Firestore emulator is already running on $FIRESTORE_HOST:$FIRESTORE_PORT."
else
  "$FIREBASE_CMD" emulators:start \
    --only firestore \
    --project "$PROJECT_ID" \
    --import="$IMPORT_DIR" \
    --export-on-exit="$IMPORT_DIR" \
    >"$EMULATOR_LOG" 2>&1 &
  EMULATOR_PID="$!"

  for _ in $(seq 1 60); do
    if port_is_open "$FIRESTORE_HOST" "$FIRESTORE_PORT"; then
      break
    fi
    if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
      echo "Firestore emulator exited before becoming ready. See $EMULATOR_LOG." >&2
      tail -n 40 "$EMULATOR_LOG" >&2 || true
      exit 1
    fi
    sleep 1
  done

  if ! port_is_open "$FIRESTORE_HOST" "$FIRESTORE_PORT"; then
    echo "Firestore emulator did not become ready within 60 seconds. See $EMULATOR_LOG." >&2
    tail -n 40 "$EMULATOR_LOG" >&2 || true
    exit 1
  fi
fi

cd "$REPO_ROOT"
NODE_PATH="$NODE_DEPS_DIR/node_modules" \
FIREBASE_EMULATOR_PROJECT_ID="$PROJECT_ID" \
FIRESTORE_EMULATOR_HOSTNAME="$FIRESTORE_HOST" \
FIRESTORE_EMULATOR_PORT="$FIRESTORE_PORT" \
node --test "$SCRIPT_DIR/firestore-rules-tests/index.test.js"
