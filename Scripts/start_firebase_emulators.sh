#!/usr/bin/env bash
set -euo pipefail

AUTH_HOST="${FIREBASE_AUTH_EMULATOR_HOST:-127.0.0.1}"
AUTH_PORT="${FIREBASE_AUTH_EMULATOR_PORT:-9099}"
FIRESTORE_HOST="${FIRESTORE_EMULATOR_HOSTNAME:-127.0.0.1}"
FIRESTORE_PORT="${FIRESTORE_EMULATOR_PORT:-8080}"
PROJECT_ID="${FIREBASE_EMULATOR_PROJECT_ID:-spotter-local}"
LOG_FILE="${FIREBASE_EMULATOR_LOG_FILE:-/tmp/spotter-firebase-emulators.log}"
PID_FILE="${FIREBASE_EMULATOR_PID_FILE:-/tmp/spotter-firebase-emulators.pid}"

port_is_open() {
  nc -z "$1" "$2" >/dev/null 2>&1
}

if port_is_open "$AUTH_HOST" "$AUTH_PORT" && port_is_open "$FIRESTORE_HOST" "$FIRESTORE_PORT"; then
  echo "Firebase Auth and Firestore emulators are already running."
  exit 0
fi

if [[ -f "$PID_FILE" ]]; then
  existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" >/dev/null 2>&1; then
    echo "Firebase emulator process is starting. Waiting for ports..."
  fi
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "Firebase CLI is required. Install it, then run firebase init emulators." >&2
  exit 1
fi

if ! port_is_open "$AUTH_HOST" "$AUTH_PORT" || ! port_is_open "$FIRESTORE_HOST" "$FIRESTORE_PORT"; then
  nohup firebase emulators:start --only auth,firestore --project "$PROJECT_ID" >"$LOG_FILE" 2>&1 &
  echo "$!" >"$PID_FILE"
fi

for _ in $(seq 1 60); do
  if port_is_open "$AUTH_HOST" "$AUTH_PORT" && port_is_open "$FIRESTORE_HOST" "$FIRESTORE_PORT"; then
    echo "Firebase Auth and Firestore emulators are ready."
    exit 0
  fi
  sleep 1
done

echo "Firebase emulators did not become ready within 60 seconds. See $LOG_FILE." >&2
exit 1
