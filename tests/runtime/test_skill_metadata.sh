#!/bin/bash
# Task 2: 共享 Skill 元数据契约测试
#
# 校验三个 Skill 拥有平台无关、稳定、唯一的 name 和 description frontmatter。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "FAIL test_skill_metadata: $*" >&2; exit 1; }

for skill in cc-code-reviewer cc-code-ignore cc-code-fixer; do
  skill_file="$ROOT_DIR/skills/$skill/SKILL.md"
  [ -f "$skill_file" ] || fail "Skill 缺失: $skill_file"

  # 必须有 YAML frontmatter（首行恰好是 ---）
  first_line="$(head -1 "$skill_file")"
  [ "$first_line" = "---" ] || fail "$skill 缺少 YAML frontmatter 起始 ---（首行: '$first_line'）"

  # name 字段必须存在且与目录名一致（目录名即期望 name）
  name_line="$(sed -n '2,10p' "$skill_file" | grep -E '^name:' | head -1 || true)"
  [ -n "$name_line" ] || fail "$skill 缺少 name frontmatter 字段"
  name_value="$(printf '%s' "$name_line" | sed 's/^name:[[:space:]]*//')"
  [ "$name_value" = "$skill" ] || fail "$skill name 不一致: '$name_value' != '$skill'"

  # description 字段必须存在且非空
  desc_line="$(sed -n '2,10p' "$skill_file" | grep -E '^description:' | head -1 || true)"
  [ -n "$desc_line" ] || fail "$skill 缺少 description frontmatter 字段"
  desc_value="$(printf '%s' "$desc_line" | sed 's/^description:[[:space:]]*//')"
  [ -n "$desc_value" ] || fail "$skill description 为空"

  # name 不得包含平台绑定词
  case "$name_value" in
    *claude*|*codex*|*zcode*) fail "$skill name 不得绑定平台: '$name_value'" ;;
  esac
done

# 三个 Skill name 必须唯一
names_file="$(mktemp)"
trap 'rm -f "$names_file"' EXIT
for skill in cc-code-reviewer cc-code-ignore cc-code-fixer; do
  sed -n '2,10p' "$ROOT_DIR/skills/$skill/SKILL.md" | grep -E '^name:' | head -1 | sed 's/^name:[[:space:]]*//' >> "$names_file"
done
unique_count="$(sort -u "$names_file" | wc -l | tr -d ' ')"
[ "$unique_count" -eq 3 ] || fail "三个 Skill name 必须唯一，当前唯一数: $unique_count"

echo "✅ Skill 元数据契约测试通过"
