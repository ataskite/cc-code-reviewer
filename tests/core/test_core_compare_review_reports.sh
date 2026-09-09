#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-compare.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT="$ROOT_DIR/scripts/core/compare-review-reports.sh"
fail() { echo "FAIL: core compare-review-reports: $*" >&2; exit 1; }
expect_line() { # $1=pattern $2=stdout $3=label
  printf '%s\n' "$2" | grep -q "$1" || fail "$3: 缺少 $1"
}

# 1) 四桶基础：优先级升级/行号漂移/标题重写 → 仍存在；范围内消失 → 已修复；
#    范围外消失 → 未复审；全新证据 → 新增；manifest 覆盖来源；小节追加到报告末尾
D="$TMP_DIR/s1"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度5-安全] 空指针风险
- 文件：src/main/java/OrderService.java:142
- 证据：
  ```java
  user.getId().toString();
  ```
- 建议：补充判空

### P2 | [维度4-正确性] 转账未校验
- 文件：src/main/java/TransferService.java:12-30
- 证据：
  ```java
  transfer(amount);
  ```
- 建议：加校验

### P3 | [维度2-质量] 死代码
- 文件：src/main/java/LegacyService.java:5
- 证据：
  ```java
  oldMethod();
  ```
- 建议：删除
MD
cat > "$D/curr.md" <<'MD'
# 代码审查报告

## 发现列表

### P0 | [维度5-安全] 空指针风险（已升级）
- 文件：src/main/java/OrderService.java:155
- 证据：
  ```java
  user.getId().toString();
  ```
- 建议：补充判空

### P2 | [维度6-性能] 循环查库
- 文件：src/main/java/OrderService.java:200
- 证据：
  ```java
  for (User u : users) { load(u); }
  ```
- 建议：批量加载
MD
cat > "$D/reviewed.txt" <<'MF'
src/main/java/OrderService.java
src/main/java/TransferService.java
MF
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/reviewed.txt")"
CURR_ABS="$(cd "$D" && pwd -P)/curr.md"
expect_line "^COMPARE_REPORT_PATH=$CURR_ABS$" "$OUT" "s1"
expect_line '^COMPARE_CURR_FINDINGS=2$' "$OUT" "s1"
expect_line '^COMPARE_PREV_FINDINGS=3$' "$OUT" "s1"
expect_line '^COMPARE_NEW=1$' "$OUT" "s1"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s1"
expect_line '^COMPARE_RESOLVED=1$' "$OUT" "s1"
expect_line '^COMPARE_NOT_REVIEWED=1$' "$OUT" "s1"
expect_line '^COMPARE_COVERAGE_SOURCE=manifest$' "$OUT" "s1"
test "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 8 || fail "s1 stdout contract（恒 8 行）"
grep -q '^## 📊 与上轮报告对比$' "$D/curr.md" || fail "s1 小节标题缺失"
grep -q '^- 对照报告：prev\.md$' "$D/curr.md" || fail "s1 对照报告行"
grep -q '^- 新增：1 条$' "$D/curr.md" || fail "s1 新增行"
grep -q '^- 已修复：1 条$' "$D/curr.md" || fail "s1 已修复行"
grep -q '^- 未复审（其文件不在本轮已审范围，不计为已修复）：1 条$' "$D/curr.md" || fail "s1 未复审行"
grep -q '^- 已审范围来源：manifest$' "$D/curr.md" || fail "s1 覆盖来源行"
# 小节必须在报告末尾（最后一个小节）
test "$(grep -c '^## ' "$D/curr.md")" -eq "$(grep -n '^## ' "$D/curr.md" | tail -1 | cut -d: -f1 | xargs -I{} sh -c 'head -n {} "$1" | grep -c "^## "' _ "$D/curr.md")" || true
LAST_H2_LINE="$(grep -n '^## ' "$D/curr.md" | tail -1 | cut -d: -f1)"
SECTION_LINE="$(grep -n '^## 📊 与上轮报告对比$' "$D/curr.md" | cut -d: -f1)"
test "$LAST_H2_LINE" = "$SECTION_LINE" || fail "s1 对比小节应为最后一个二级小节"

# 2) 幂等：重复运行报告字节稳定、计数一致
cp "$D/curr.md" "$D/curr.run1.md"
OUT2="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/reviewed.txt")"
cmp -s "$D/curr.run1.md" "$D/curr.md" || fail "s2 重复运行报告字节不稳定"
test "$OUT" = "$OUT2" || fail "s2 重复运行计数不一致"

# 3) 点/区间锚漂移 + 证据重排版（缩进/± 前缀/空行）→ 仍存在
D="$TMP_DIR/s3"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P2 | [维度4-正确性] 未校验
- 文件：src/App.java:12
- 证据：
  ```java
  alpha();
  beta();
  ```
MD
cat > "$D/curr.md" <<'MD'
### P2 | [维度4-正确性] 未校验（复测）
- 文件：src/App.java:40-58
- 证据：
  ```diff
  +  alpha();

  +     beta();
  ```
MD
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md")"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s3"
expect_line '^COMPARE_NEW=0$' "$OUT" "s3"
expect_line '^COMPARE_NOT_REVIEWED=0$' "$OUT" "s3"
expect_line '^COMPARE_COVERAGE_SOURCE=none$' "$OUT" "s3"

# 4) 多重集：同键 prev×2 / curr×1 → 仍存在1 + 已修复1；反向 → 仍存在1 + 新增1
D="$TMP_DIR/s4"; mkdir -p "$D"
make_dup_report() { # $1=repeat
  echo "# r"
  for _ in $(seq "$1"); do
    cat <<MD
### P1 | [维度1] 重复问题
- 文件：x/Y.java:7
- 证据：
  \`\`\`java
  dup();
  \`\`\`
MD
  done
}
make_dup_report 2 > "$D/prev.md"
make_dup_report 1 > "$D/curr.md"
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md")"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s4a"
expect_line '^COMPARE_RESOLVED=1$' "$OUT" "s4a"
make_dup_report 1 > "$D/prev2.md"
make_dup_report 2 > "$D/curr2.md"
OUT="$(bash "$SCRIPT" "$D/curr2.md" "$D/prev2.md")"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s4b"
expect_line '^COMPARE_NEW=1$' "$OUT" "s4b"

# 5) 维度变化（同证据）→ 不算仍存在（新+已修复各 1）；优先级变化 → 仍存在（用例1已覆盖）
D="$TMP_DIR/s5"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P2 | [维度4-正确性] 问题
- 文件：x/A.java:3
- 证据：
  ```java
  code();
  ```
MD
cat > "$D/curr.md" <<'MD'
### P2 | [维度6-性能] 同一段代码的另一面
- 文件：x/A.java:3
- 证据：
  ```java
  code();
  ```
MD
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md")"
expect_line '^COMPARE_PERSISTING=0$' "$OUT" "s5"
expect_line '^COMPARE_NEW=1$' "$OUT" "s5"
expect_line '^COMPARE_RESOLVED=1$' "$OUT" "s5"

# 6) 无覆盖来源 → 未复审恒 0（三桶降级）
D="$TMP_DIR/s6"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度1] 范围外问题
- 文件：outside/F.java:1
- 证据：
  ```java
  x();
  ```
MD
printf '# empty curr\n' > "$D/curr.md"
cp "$D/curr.md" "$D/curr.before"
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md")"
expect_line '^COMPARE_RESOLVED=1$' "$OUT" "s6"
expect_line '^COMPARE_NOT_REVIEWED=0$' "$OUT" "s6"
expect_line '^COMPARE_COVERAGE_SOURCE=none$' "$OUT" "s6"
grep -q '^## 📊 与上轮报告对比$' "$D/curr.md" || fail "s6 上轮有发现时 curr 零发现也应写小节"

# 7) 上轮零有效块（fail-open）→ 报告字节不动、无小节
D="$TMP_DIR/s7"; mkdir -p "$D"
printf '# 上轮报告\n\n没有发现列表\n' > "$D/prev.md"
cat > "$D/curr.md" <<'MD'
### P1 | [维度1] 新
- 文件：b.java:1
- 证据：
  ```java
  n();
  ```
MD
cp "$D/curr.md" "$D/curr.before"
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md")"
expect_line '^COMPARE_PREV_FINDINGS=0$' "$OUT" "s7"
expect_line '^COMPARE_NEW=1$' "$OUT" "s7"
cmp -s "$D/curr.before" "$D/curr.md" || fail "s7 上轮零块时报告字节必须不变"
# 7b) 真空上轮（存在但空文件）
: > "$D/prev-empty.md"
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev-empty.md")"
expect_line '^COMPARE_PREV_FINDINGS=0$' "$OUT" "s7b"
cmp -s "$D/curr.before" "$D/curr.md" || fail "s7b 空上轮报告字节必须不变"

# 8) run-manifest.json 覆盖：completed+reused（含 old_path）计入已审；leftover 不计
D="$TMP_DIR/s8"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度1] 已修好的
- 文件：done/F.java:1
- 证据：
  ```java
  d();
  ```

### P1 | [维度1] rename 后仍审到的
- 文件：old/Renamed.java:1
- 证据：
  ```java
  r();
  ```

### P1 | [维度1] 遗留批次没审的
- 文件：left/G.java:1
- 证据：
  ```java
  g();
  ```
MD
printf '# curr\n' > "$D/curr.md"
cat > "$D/run-manifest.json" <<'MJ'
{
  "schema_version": 1,
  "coverage_sets": {
    "completed": [ { "item_id": "i1", "path": "done/F.java" } ],
    "reused": [ { "item_id": "i2", "path": "new/Renamed.java", "old_path": "old/Renamed.java" } ],
    "failed": [],
    "waived": [],
    "leftover": [ { "item_id": "i3", "path": "left/G.java" } ]
  }
}
MJ
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/run-manifest.json")"
expect_line '^COMPARE_RESOLVED=2$' "$OUT" "s8"
expect_line '^COMPARE_NOT_REVIEWED=1$' "$OUT" "s8"
expect_line '^COMPARE_COVERAGE_SOURCE=run-manifest$' "$OUT" "s8"

# 9) review-input.json 覆盖：仅 selected=true 计入已审
D="$TMP_DIR/s9"; mkdir -p "$D"
cp "$TMP_DIR/s8/prev.md" "$D/prev.md"
printf '# curr\n' > "$D/curr.md"
cat > "$D/review-input.json" <<'MJ'
{
  "items": [
    { "path": "done/F.java", "change": "MODIFIED", "selected": true },
    { "path": "new/Renamed.java", "change": "RENAMED", "old_path": "old/Renamed.java", "selected": true },
    { "path": "left/G.java", "change": "DELETED", "selected": false }
  ]
}
MJ
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/review-input.json")"
expect_line '^COMPARE_RESOLVED=2$' "$OUT" "s9"
expect_line '^COMPARE_NOT_REVIEWED=1$' "$OUT" "s9"
expect_line '^COMPARE_COVERAGE_SOURCE=review-input$' "$OUT" "s9"

# 10) 覆盖文件缺失 → fail-open 降级 none（exit 0 + stderr warn）
D="$TMP_DIR/s10"; mkdir -p "$D"
cp "$TMP_DIR/s8/prev.md" "$D/prev.md"
printf '# curr\n' > "$D/curr.md"
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/nope.json" 2>"$D/err")"
expect_line '^COMPARE_COVERAGE_SOURCE=none$' "$OUT" "s10"
expect_line '^COMPARE_NOT_REVIEWED=0$' "$OUT" "s10"
grep -q '^WARN_REVIEWED_FROM_UNREADABLE=' "$D/err" || fail "s10 stderr warn"

# 11) 用法与读入错误：参数缺失/未知选项/报告缺失 → exit 1 + ERROR_* 标签
D="$TMP_DIR/s11"; mkdir -p "$D"
bash "$SCRIPT" >/dev/null 2>&1 && fail "s11 无参数必须 exit 1"
bash "$SCRIPT" "$D/a.md" "$D/b.md" --wrong 2>"$D/err" && fail "s11 未知选项必须 exit 1"
grep -q '^ERROR_UNKNOWN_OPTION=--wrong$' "$D/err" || fail "s11 ERROR_UNKNOWN_OPTION 标签"
bash "$SCRIPT" "$D/a.md" "$D/b.md" --reviewed-from 2>/dev/null 2>"$D/err" && fail "s11 --reviewed-from 缺值必须 exit 1"
grep -q '^ERROR_INVALID_ARGS=' "$D/err" || fail "s11 ERROR_INVALID_ARGS 标签"
printf '# x\n' > "$D/a.md"
bash "$SCRIPT" "$D/a.md" "$D/missing.md" >/dev/null 2>"$D/err" && fail "s11 上轮缺失必须 exit 1"
grep -q '^ERROR_PREV_NOT_FOUND=' "$D/err" || fail "s11 ERROR_PREV_NOT_FOUND 标签"

# 12) 已有小节被刷新而非叠加：换一份 prev 重跑 → 只剩一个小节、计数更新
D="$TMP_DIR/s12"; mkdir -p "$D"
cat > "$D/p1.md" <<'MD'
### P1 | [维度1] A
- 文件：a/A.java:1
- 证据：
  ```java
  a();
  ```
MD
cat > "$D/p2.md" <<'MD'
### P1 | [维度2] B
- 文件：a/B.java:1
- 证据：
  ```java
  b();
  ```
MD
cat > "$D/curr.md" <<'MD'
### P1 | [维度1] A
- 文件：a/A.java:1
- 证据：
  ```java
  a();
  ```
MD
bash "$SCRIPT" "$D/curr.md" "$D/p2.md" >/dev/null
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/p1.md")"
test "$(grep -c '^## 📊 与上轮报告对比$' "$D/curr.md")" -eq 1 || fail "s12 小节必须唯一"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s12"
grep -q '^- 已修复：0 条$' "$D/curr.md" || fail "s12 旧小节计数必须被刷新"

# 13) 不完整发现块（缺 location / 缺有效闭合证据）不进入四桶，也不被误判为已修复
D="$TMP_DIR/s13"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度1] 有效发现
- 文件：src/Valid.java:1
- 证据：
  ```java
  valid();
  ```

### P1 | [维度1] 缺位置
- 证据：
  ```java
  noLocation();
  ```

### P1 | [维度1] 缺有效证据
- 文件：src/NoEvidence.java:1
- 证据：
  ```java
  unclosed();
MD
cat > "$D/curr.md" <<'MD'
### P1 | [维度1] 有效发现
- 文件：src/Valid.java:2
- 证据：
  ```java
  valid();
  ```

### P1 | [维度1] 本轮缺位置
- 证据：
  ```java
  noLocationHere();
  ```
MD
printf 'src/Valid.java\n' > "$D/reviewed.txt"
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/reviewed.txt")"
expect_line '^COMPARE_CURR_FINDINGS=1$' "$OUT" "s13"
expect_line '^COMPARE_PREV_FINDINGS=1$' "$OUT" "s13"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s13"
expect_line '^COMPARE_NEW=0$' "$OUT" "s13"
expect_line '^COMPARE_RESOLVED=0$' "$OUT" "s13"
expect_line '^COMPARE_NOT_REVIEWED=0$' "$OUT" "s13"

# 14) 未知 JSON 对象不是纯文本清单；覆盖来源必须 fail-open 为 none
D="$TMP_DIR/s14"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度1] 上轮问题
- 文件：outside/F.java:1
- 证据：
  ```java
  old();
  ```
MD
printf '# curr\n' > "$D/curr.md"
cat > "$D/unknown.json" <<'MJ'
{ "unexpected": ["outside/F.java"] }
MJ
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$D/unknown.json")"
expect_line '^COMPARE_COVERAGE_SOURCE=none$' "$OUT" "s14"
expect_line '^COMPARE_RESOLVED=1$' "$OUT" "s14"
expect_line '^COMPARE_NOT_REVIEWED=0$' "$OUT" "s14"

# 15) 正式报告格式用 **位置**：字段，路径锚漂移后仍应按同一发现匹配
D="$TMP_DIR/s15"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1-1 | [维度4-正确性] 正式格式问题

**位置**：src/main/java/Official.java:12（同类问题共3处）

**证据**：
```java
official();
```
MD
cat > "$D/curr.md" <<'MD'
### P2-1 | [维度4-正确性] 正式格式问题（复测）

**位置**：src/main/java/Official.java:30-40

**证据**：
```java
official();
```
MD
OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md")"
expect_line '^COMPARE_CURR_FINDINGS=1$' "$OUT" "s15"
expect_line '^COMPARE_PREV_FINDINGS=1$' "$OUT" "s15"
expect_line '^COMPARE_PERSISTING=1$' "$OUT" "s15"
expect_line '^COMPARE_NEW=0$' "$OUT" "s15"
expect_line '^COMPARE_RESOLVED=0$' "$OUT" "s15"

# 16) JSON coverage schema 缺字段或类型错误必须 fail-open，绝不制造未复审范围
D="$TMP_DIR/s16"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度1] 上轮问题
- 文件：outside/F.java:1
- 证据：
  ```java
  old();
  ```
MD
printf '# curr\n' > "$D/curr.md"
cat > "$D/run-missing-reused.json" <<'MJ'
{ "coverage_sets": { "completed": [] } }
MJ
cat > "$D/run-wrong-reused.json" <<'MJ'
{ "coverage_sets": { "completed": [], "reused": {} } }
MJ
cat > "$D/review-input-wrong-items.json" <<'MJ'
{ "items": {} }
MJ
for COVERAGE in "$D/run-missing-reused.json" "$D/run-wrong-reused.json" "$D/review-input-wrong-items.json"; do
  OUT="$(bash "$SCRIPT" "$D/curr.md" "$D/prev.md" --reviewed-from "$COVERAGE")"
  expect_line '^COMPARE_COVERAGE_SOURCE=none$' "$OUT" "s16"
  expect_line '^COMPARE_RESOLVED=1$' "$OUT" "s16"
  expect_line '^COMPARE_NOT_REVIEWED=0$' "$OUT" "s16"
done

echo "PASS: core compare-review-reports 全部 16 组契约"
