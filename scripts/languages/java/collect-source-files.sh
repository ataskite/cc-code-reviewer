#!/bin/bash
set -euo pipefail

# 输出 Java 正式源码的绝对路径清单。可选 scope 使用 Maven 模块相对路径，
# 用于单 agent 存量审查同样冻结正式范围；测试和 target 仅作只读上下文。
#
# 构建与配置伴随文件（白名单第二层）：正式 src/main/java 清单之外，确定性追加
# 仅命中以下白名单的文件（每行一个绝对路径，随主清单 LC_ALL=C 排序去重）：
#   1) 构建描述符：每个构建根目录（存在 pom.xml 或 build.gradle[.kts] 的目录）
#      自身的 pom.xml / build.gradle / build.gradle.kts；
#   2) 模块 src/main/resources 内仅匹配 application*、bootstrap*、*logback*、
#      log4j2*、*apper*.xml 与 *dao*.xml（mapper 命名形态）、swagger.*、openapi.* 的文件；
#   3) CI 与容器伴随面：任意未剪枝目录下的 Dockerfile / Dockerfile.* /
#      Jenkinsfile / .gitlab-ci.yml 与 .github/workflows/*.yml|.yaml。
# 目的：让 scripts/core/filetype-rule-map.json 的文件类型专项清单模式对 pom、
# mapper XML、Spring 配置等始终可触达，而不是输出永远无人命中的死映射。
# 硬上限：单次运行并入的伴随文件不超过 COMPANION_FILE_LIMIT（200），按
# LC_ALL=C 顺序截断；实际并入数通过 stderr 打印 COMPANION_FILES_ADDED=N，
# 达到上限时追加截断说明。已知影响：planned_source_loc / file_count 会因伴
# 随文件而增长（读取 manifest 做 wc -l 统计的规划脚本如实计数），属预期行为；
# src/test/resources 与 target/ 等目录始终排除，不进入正式范围。

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_SCOPE="${2:-全量代码}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

is_full_scope() {
  case "$REVIEW_SCOPE" in ""|"全量代码"|"全量审查"|all|ALL) return 0 ;; esac
  return 1
}

collect_from_root() {
  find "$1" -path '*/src/main/java/*' -name '*.java' -not -path '*/target/*' \
    -not -path '*/__snapshots__/*' -not -path '*/testdata/*' -not -path '*/fixtures/*' \
    -not -name '*.generated.*' -not -name '*.gen.java' -type f -print 2>/dev/null
}

# 伴随文件发现：与主口径一致的剪枝目录（target/node_modules/dist/build/.git/
# fixtures/testdata/__snapshots__）整树跳过；三类白名单一次遍历产出。
collect_companions() {
  find "$1" \
    \( -type d \( \
         -name target -o -name node_modules -o -name dist -o -name build -o \
         -name .git -o -name __snapshots__ -o -name testdata -o -name fixtures \
       \) \) -prune -o \
    \( -type f \( \
         -name pom.xml -o -name build.gradle -o -name build.gradle.kts \
         -o -name Dockerfile -o -name 'Dockerfile.*' -o -name Jenkinsfile \
         -o -name '.gitlab-ci.yml' \
         -o \( -path '*/.github/workflows/*' -a \( -name '*.yml' -o -name '*.yaml' \) \) \
         -o \( -path '*/src/main/resources/*' -a \( \
              -name 'application*' -o -name 'bootstrap*' -o -name '*logback*' \
              -o -name 'log4j2*' -o -name '*apper*.xml' -o -name '*dao*.xml' \
              -o -name 'swagger.*' -o -name 'openapi.*' \) \) \
       \) -print \) 2>/dev/null
}

COMPANION_FILE_LIMIT="${CC_CODE_REVIEWER_COMPANION_LIMIT:-200}"
MAIN_TMP="$(mktemp "${TMPDIR:-/tmp}/jcf-main.XXXXXX")"
COMP_TMP="$(mktemp "${TMPDIR:-/tmp}/jcf-comp.XXXXXX")"
trap 'rm -f "$MAIN_TMP" "$COMP_TMP"' EXIT

if is_full_scope; then
  collect_from_root "$PROJECT_DIR" >> "$MAIN_TMP"
  collect_companions "$PROJECT_DIR" >> "$COMP_TMP"
else
  NORMALIZED="$(printf '%s' "$REVIEW_SCOPE" | perl -CS -Mutf8 -pe 's/[，、\s]+/,/g; s/^,+//; s/,+$//')"
  IFS=',' read -r -a SELECTED_PATHS <<< "$NORMALIZED"
  for selected in "${SELECTED_PATHS[@]}"; do
    selected="$(printf '%s' "$selected" | sed 's#^\./##; s#//*#/#g; s#/$##')"
    case "$selected" in ""|/*|..|../*|*/../*|*/..) echo "INVALID_SCOPE_PATH=$selected" >&2; exit 1 ;; esac
    candidate="$PROJECT_DIR/$selected"
    [ -d "$candidate" ] || { echo "SCOPE_PATH_NOT_FOUND=$selected" >&2; exit 1; }
    candidate="$(cd "$candidate" && pwd -P)"
    case "$candidate" in "$PROJECT_DIR"/*) ;; *) echo "SCOPE_PATH_OUTSIDE_PROJECT=$selected" >&2; exit 1 ;; esac
    collect_from_root "$candidate" >> "$MAIN_TMP"
    collect_companions "$candidate" >> "$COMP_TMP"
  done
fi

# 收口：主清单与伴随候选各自去重，再去掉与主清单重合的候选，按 LC_ALL=C
# 顺序应用硬上限后并回。全程使用临时文件避免 find | head 触发 SIGPIPE。
LC_ALL=C sort -u "$MAIN_TMP" > "$MAIN_TMP.s" || true
LC_ALL=C sort -u "$COMP_TMP" > "$COMP_TMP.s" || true
comm -23 "$COMP_TMP.s" "$MAIN_TMP.s" > "$COMP_TMP.new"
ADDED="$(grep -c . "$COMP_TMP.new" || true)"
TRUNCATED_NOTE=""
if [ "$ADDED" -gt "$COMPANION_FILE_LIMIT" ]; then
  head -n "$COMPANION_FILE_LIMIT" "$COMP_TMP.new" > "$COMP_TMP.add"
  TRUNCATED_NOTE="（伴随白名单命中 ${ADDED} 个已达上限 ${COMPANION_FILE_LIMIT}，超出部分截断）"
  ADDED="$COMPANION_FILE_LIMIT"
else
  cp "$COMP_TMP.new" "$COMP_TMP.add"
fi

cat "$MAIN_TMP.s" "$COMP_TMP.add" | LC_ALL=C sort -u
if [ "$ADDED" -gt 0 ]; then
  echo "COMPANION_FILES_ADDED=${ADDED}${TRUNCATED_NOTE}" >&2
fi
