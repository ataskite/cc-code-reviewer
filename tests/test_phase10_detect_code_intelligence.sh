#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase10.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/demo"
mkdir -p "$PROJECT_DIR/src/main/java/com/example"
printf 'public class Demo {}\n' > "$PROJECT_DIR/src/main/java/com/example/Demo.java"

OUTPUT="$(PATH="/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_LANGUAGE=java"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PROVIDER=none"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_REASON="

NON_JAVA="$TMP_DIR/non-java"
mkdir -p "$NON_JAVA"
OUTPUT="$(PATH="/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$NON_JAVA")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_REASON=未识别Java项目"

CUSTOM_GRADLE="$TMP_DIR/custom-gradle"
mkdir -p "$CUSTOM_GRADLE"
printf 'plugins { id "java" }\n' > "$CUSTOM_GRADLE/build.gradle.custom"
OUTPUT="$(PATH="/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$CUSTOM_GRADLE")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_LANGUAGE=java"
if printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_REASON=未识别Java项目"; then
  echo "build.gradle* project should be treated as a Java project" >&2
  exit 1
fi

FAKE_BIN="$TMP_DIR/bin"
FAKE_PLUGIN_ROOT="$TMP_DIR/plugins"
mkdir -p "$FAKE_BIN" "$FAKE_PLUGIN_ROOT/claude-plugins-official/jdtls-lsp"
cat > "$FAKE_BIN/jdtls" <<'SH'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "jdtls fake"
  exit 0
fi
exit 0
SH
chmod +x "$FAKE_BIN/jdtls"

MISSING_PLUGIN_ROOT="$TMP_DIR/not-installed-jdtls-lsp"
OUTPUT="$(CLAUDE_CODE_PLUGIN_ROOTS="$MISSING_PLUGIN_ROOT" PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PLUGIN_INSTALLED=false"

mkdir -p "$MISSING_PLUGIN_ROOT"
OUTPUT="$(CLAUDE_CODE_PLUGIN_ROOTS="$MISSING_PLUGIN_ROOT" PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PLUGIN_INSTALLED=false"

if ! OUTPUT="$(env -u HOME PATH="$FAKE_BIN:/usr/bin:/bin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR")"; then
  echo "missing HOME should not make detection fail" >&2
  exit 1
fi
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PLUGIN_INSTALLED=false"

HANGING_BIN="$TMP_DIR/hanging-bin"
mkdir -p "$HANGING_BIN"
cat > "$HANGING_BIN/jdtls" <<'SH'
#!/bin/sh
sleep 10
SH
chmod +x "$HANGING_BIN/jdtls"

OUTPUT="$(CLAUDE_CODE_PLUGIN_ROOTS="$FAKE_PLUGIN_ROOT" PATH="$HANGING_BIN:/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=true"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PROVIDER=jdtls-lsp"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_JDTLS_READY=true"

OUTPUT="$(CLAUDE_CODE_PLUGIN_ROOTS="$FAKE_PLUGIN_ROOT" PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$TMP_DIR/home-no-plugin" bash "$ROOT_DIR/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=true"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PROVIDER=jdtls-lsp"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_JDTLS_READY=true"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PLUGIN_INSTALLED=true"

echo "PASS"
