#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

grep -q "tests/run_all.sh" "$ROOT_DIR/README.md"
grep -q "tests/run_all.sh" "$ROOT_DIR/CLAUDE.md"
grep -q "tests/run_all.sh" "$ROOT_DIR/AGENTS.md"
