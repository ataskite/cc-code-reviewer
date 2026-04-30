#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase1 detect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

LOCAL_PROJECT="$TMP_DIR/local project"
mkdir -p "$LOCAL_PROJECT"

OUTPUT="$(bash "$ROOT_DIR/scripts/phase1-detect-project.sh" "$LOCAL_PROJECT")"

echo "$OUTPUT" | grep -q "PROJECT_DIR=$LOCAL_PROJECT"
echo "$OUTPUT" | grep -q "PROJECT_SOURCE=local"

MISSING_OUTPUT="$TMP_DIR/phase1-missing.out"
if bash "$ROOT_DIR/scripts/phase1-detect-project.sh" "$TMP_DIR/missing" >"$MISSING_OUTPUT" 2>&1; then
  echo "phase1 should fail for a missing local path" >&2
  exit 1
fi

grep -q "路径不存在" "$MISSING_OUTPUT"
