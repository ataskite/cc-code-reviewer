#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java-source-manifest.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/a/src/main/java/demo" "$TMP_DIR/a/src/main/java/demo/fixtures" "$TMP_DIR/a/src/test/java/demo" "$TMP_DIR/a/target/generated" "$TMP_DIR/b/src/main/java/demo"
printf 'class A {}\n' > "$TMP_DIR/a/src/main/java/demo/A.java"
printf 'class ATest {}\n' > "$TMP_DIR/a/src/test/java/demo/ATest.java"
printf 'class Generated {}\n' > "$TMP_DIR/a/target/generated/Generated.java"
printf 'class Generated {}\n' > "$TMP_DIR/a/src/main/java/demo/Generated.generated.java"
printf 'class Fixture {}\n' > "$TMP_DIR/a/src/main/java/demo/fixtures/Fixture.java"
printf 'class B {}\n' > "$TMP_DIR/b/src/main/java/demo/B.java"

# 无伴随文件的仓库：口径与旧版完全一致（2 个生产 Java 文件）。
FULL="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR")"
test "$(printf '%s\n' "$FULL" | wc -l | tr -d ' ')" = 2
printf '%s\n' "$FULL" | grep -q '/a/src/main/java/demo/A.java'
printf '%s\n' "$FULL" | grep -q '/b/src/main/java/demo/B.java'

SCOPED="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR" a)"
test "$(printf '%s\n' "$SCOPED" | wc -l | tr -d ' ')" = 1
printf '%s\n' "$SCOPED" | grep -q '/a/src/main/java/demo/A.java'

set +e
OUT="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR" ../outside 2>&1)"
STATUS=$?
set -e
test "$STATUS" -ne 0
printf '%s\n' "$OUT" | grep -q 'INVALID_SCOPE_PATH'

# ---- 构建与配置伴随文件层（白名单）----
mkdir -p \
  "$TMP_DIR/c/app/src/main/java/demo" \
  "$TMP_DIR/c/app/src/main/resources" \
  "$TMP_DIR/c/app/src/test/resources" \
  "$TMP_DIR/c/target/stub" \
  "$TMP_DIR/c/.github/workflows" \
  "$TMP_DIR/c/sub/gsvc"
printf 'class C {}\n' > "$TMP_DIR/c/app/src/main/java/demo/C.java"
# T1 构建描述符：根模块 + 嵌套 Maven/Gradle
printf '<project/>\n' > "$TMP_DIR/c/pom.xml"
printf '<project/>\n' > "$TMP_DIR/c/app/pom.xml"
printf '<project/>\n' > "$TMP_DIR/c/target/stub/pom.xml"
printf "plugins {}\n" > "$TMP_DIR/c/app/build.gradle.kts"
printf "plugins {}\n" > "$TMP_DIR/c/sub/gsvc/build.gradle"
# T2 resources 白名单
printf 'a: 1\n' > "$TMP_DIR/c/app/src/main/resources/application.yml"
printf '<mapper ns="u"/>' > "$TMP_DIR/c/app/src/main/resources/UserMapper.xml"
printf '<mapper ns="d"/>' > "$TMP_DIR/c/app/src/main/resources/user_dao.xml"
printf '<config/>\n' > "$TMP_DIR/c/app/src/main/resources/logback-spring.xml"
printf '<l/>\n' > "$TMP_DIR/c/app/src/main/resources/log4j2.xml"
printf '{"openapi":"3"}\n' > "$TMP_DIR/c/app/src/main/resources/openapi.yaml"
# 白名单外的伴生文件不得进入清单
printf 'random\n' > "$TMP_DIR/c/app/src/main/java/demo/notes.xml"
printf 'testcfg\n' > "$TMP_DIR/c/app/src/test/resources/application.yml"
# T3 CI 与容器伴随面
printf 'CI\n' > "$TMP_DIR/c/.github/workflows/ci.yml"
printf 'CD\n' > "$TMP_DIR/c/.github/workflows/deploy.yaml"
printf 'pipeline\n' > "$TMP_DIR/c/Jenkinsfile"
printf 'gitlab\n' > "$TMP_DIR/c/.gitlab-ci.yml"
printf 'FROM alpine\n' > "$TMP_DIR/c/Dockerfile"

COMPANIONS_FULL="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR")"
for member in \
  "/c/pom.xml" \
  "/c/app/pom.xml" \
  "/c/app/build.gradle.kts" \
  "/c/sub/gsvc/build.gradle" \
  "/c/app/src/main/resources/application.yml" \
  "/c/app/src/main/resources/UserMapper.xml" \
  "/c/app/src/main/resources/user_dao.xml" \
  "/c/app/src/main/resources/logback-spring.xml" \
  "/c/app/src/main/resources/log4j2.xml" \
  "/c/app/src/main/resources/openapi.yaml" \
  "/c/.github/workflows/ci.yml" \
  "/c/.github/workflows/deploy.yaml" \
  "/c/Jenkinsfile" \
  "/c/.gitlab-ci.yml" \
  "/c/Dockerfile"; do
  printf '%s\n' "$COMPANIONS_FULL" | grep -Fq -- "$member" || { echo "FAIL: companion missing: $member" >&2; exit 1; }
done
# 主源码 + 全部伴随文件计数固定（发现新文件时这里必须显式更新）。
test "$(printf '%s\n' "$COMPANIONS_FULL" | wc -l | tr -d ' ')" = 18
# 排除面仍然成立：target、test resources、非白名单 xml 不入清单。
if printf '%s\n' "$COMPANIONS_FULL" | grep -qF -- "/c/target/stub/pom.xml"; then echo "FAIL: target pom leaked" >&2; exit 1; fi
if printf '%s\n' "$COMPANIONS_FULL" | grep -qF -- "/c/app/src/test/resources/application.yml"; then echo "FAIL: test resources leaked" >&2; exit 1; fi
if printf '%s\n' "$COMPANIONS_FULL" | grep -qF -- "/c/app/src/main/java/demo/notes.xml"; then echo "FAIL: non-whitelist xml leaked" >&2; exit 1; fi

# 纯 Gradle 仓库（无任何 Java 源码）：构建描述符仍需产出。
mkdir -p "$TMP_DIR/donly"
printf "plugins {}\n" > "$TMP_DIR/donly/build.gradle"
GRADLE_ONLY="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR/donly")"
test "$(printf '%s\n' "$GRADLE_ONLY" | wc -l | tr -d ' ')" = 1
printf '%s\n' "$GRADLE_ONLY" | grep -q '/donly/build.gradle'

# scoped 选择不跨出候选目录：只带回 c 内的伴随文件。
C_SCOPED="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR" c)"
test "$(printf '%s\n' "$C_SCOPED" | wc -l | tr -d ' ')" = 16
printf '%s\n' "$C_SCOPED" | grep -qF -- "/c/Jenkinsfile"
if printf '%s\n' "$C_SCOPED" | grep -qF -- "/a/src/main/java/demo/A.java"; then echo "FAIL: scope leak of a/" >&2; exit 1; fi

echo "PASS: java collect-source-files"
