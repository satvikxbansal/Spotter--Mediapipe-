#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
"$REPO_ROOT/Scripts/test-firestore-rules.sh"
