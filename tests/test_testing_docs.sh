#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

grep -q "tests/run_all.sh" "$ROOT_DIR/CLAUDE.md"
grep -q "tests/run_all.sh" "$ROOT_DIR/AGENTS.md"

if grep -q "tests/run_all.sh" "$ROOT_DIR/README.md"; then
  echo "README should not include test script details" >&2
  exit 1
fi
