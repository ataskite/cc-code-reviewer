#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java reviewer scan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/demo project"
MODULE_DIR="$PROJECT_DIR/user service"
mkdir -p "$MODULE_DIR/src/main/java/com/example"

cat > "$PROJECT_DIR/pom.xml" <<'POM'
<project>
  <modules>
    <module>user service</module>
  </modules>
</project>
POM

cat > "$MODULE_DIR/pom.xml" <<'POM'
<project></project>
POM

cat > "$MODULE_DIR/src/main/java/com/example/UserService.java" <<'JAVA'
package com.example;

public class UserService {
    public String name() {
        return "demo";
    }
}
JAVA

OUTPUT="$(bash "$ROOT_DIR/scripts/phase3-project-scan.sh" "$PROJECT_DIR")"

echo "$OUTPUT" | grep -q "PROJECT_TYPE=maven-multi"
echo "$OUTPUT" | grep -q "Java文件总数: 1"
echo "$OUTPUT" | grep -q "代码总行数: 7"
echo "$OUTPUT" | grep -q "MODULE:user service|/user service|1|7"
