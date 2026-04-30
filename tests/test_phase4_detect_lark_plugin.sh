#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

OUTPUT="$(bash "$ROOT_DIR/scripts/phase4-detect-lark-plugin.sh")"

echo "$OUTPUT" | grep -Eq '^LARK_PLUGIN_INSTALLED=(true|false)$'

if echo "$OUTPUT" | grep -q '^LARK_PLUGIN_INSTALLED=true$'; then
  echo "$OUTPUT" | grep -q '^LARK_PLUGIN_NAME=lark-cli$'
  echo "$OUTPUT" | grep -q '^LARK_SKILLS_INSTALLED=true$'
else
  echo "$OUTPUT" | grep -q '^LARK_PLUGIN_REASON='
fi
