#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-repeat.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT="$ROOT_DIR/scripts/core/mark-repeat-findings.sh"
fail() { echo "FAIL: core mark-repeat-findings: $*" >&2; exit 1; }

# 1) 同路径同维度同行同证据长度 → 标记；表头精确追加「（上轮已报）」，其余行零改动
D="$TMP_DIR/s1"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度5-安全] 空指针风险
- 文件：src/main/java/com/example/OrderService.java:142
- 置信度：高
- 证据：
  ```java
  user.getId().toString();
  ```
- 建议：补充判空
MD
cp "$D/prev.md" "$D/new.md"
cp "$D/new.md" "$D/new.before.md"
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
NEW_ABS="$(cd "$D" && pwd -P)/new.md"
grep -q "^REPEAT_REPORT_PATH=$NEW_ABS$" <<< "$OUT" || fail "s1 report path"
grep -q '^REPEAT_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s1 total"
grep -q '^REPEAT_PREV_BLOCKS=1$' <<< "$OUT" || fail "s1 prev"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s1 marked"
test "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 4 || fail "s1 stdout contract"
grep -q '^### P1 | \[维度5-安全\] 空指针风险（上轮已报）$' "$D/new.md" || fail "s1 header suffix"
DIFF="$(diff "$D/new.before.md" "$D/new.md" || true)"
DIFF_LINES="$(printf '%s\n' "$DIFF" | grep -c '^[<>]' || true)"
test "$DIFF_LINES" -eq 2 || fail "s1 only header line changed (got $DIFF_LINES diff lines)"
grep -q '^< ### P1 | \[维度5-安全\] 空指针风险$' <<< "$DIFF" || fail "s1 removed header line"
grep -q '^> ### P1 | \[维度5-安全\] 空指针风险（上轮已报）$' <<< "$DIFF" || fail "s1 added header line"

# 2) 行号漂移 +2 且多行证据大幅重叠（新区间 [10,17] vs 旧区间 [12,17]，IoU=6/8=0.75）→ 命中
D="$TMP_DIR/s2"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P2 | [维度4-正确性] 转账未校验
- 文件：src/App.java:12
- 证据：
  ```java
  alpha();
  beta();
  gamma();
  delta();
  epsilon();
  zeta();
  ```
- 建议：无
MD
cat > "$D/new.md" <<'MD'
### P2 | [维度4-正确性] 转账未校验
- 文件：src/App.java:10
- 证据：
  ```java
  pre();
  alpha();
  beta();
  gamma();
  delta();
  epsilon();
  zeta();
  eta();
  ```
- 建议：无
MD
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s2 marked under drift"
grep -q '^### P2 | \[维度4-正确性\] 转账未校验（上轮已报）$' "$D/new.md" || fail "s2 header suffix"

# 3) 维度前置条件：同路径不同维度不标；单侧缺方括号不标；双侧都缺方括号可标
D="$TMP_DIR/s3"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度4-正确性] 维度不同
- 文件：src/PathA.java:10
- 证据：
  ```java
  alpha();
  ```
- 建议：无

### P1 | [维度2-可维护性] 上轮有括号
- 文件：src/PathB.java:10
- 证据：
  ```java
  beta();
  ```
- 建议：无

### P1 双方都无括号
- 文件：src/PathC.java:10
- 证据：
  ```java
  gamma();
  ```
- 建议：无
MD
cat > "$D/new.md" <<'MD'
### P1 | [维度5-安全] 维度不同
- 文件：src/PathA.java:10
- 证据：
  ```java
  alpha();
  ```
- 建议：无

### P1 本轮无括号
- 文件：src/PathB.java:10
- 证据：
  ```java
  beta();
  ```
- 建议：无

### P1 双方都无括号
- 文件：src/PathC.java:10
- 证据：
  ```java
  gamma();
  ```
- 建议：无
MD
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_TOTAL_BLOCKS=3$' <<< "$OUT" || fail "s3 total"
grep -q '^REPEAT_PREV_BLOCKS=3$' <<< "$OUT" || fail "s3 prev"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s3 only both-missing-bracket block marked"
grep -q '^### P1 | \[维度5-安全\] 维度不同$' "$D/new.md" || fail "s3 different dimension untouched"
grep -q '^### P1 本轮无括号$' "$D/new.md" || fail "s3 one-sided bracket untouched"
grep -q '^### P1 双方都无括号（上轮已报）$' "$D/new.md" || fail "s3 both-missing bracket marked"

# 4) 同路径同维度但区间不相交（[10,17] vs [40,47]）→ 不标
D="$TMP_DIR/s4"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度5-安全] 远处样本
- 文件：src/Far.java:40
- 证据：
  ```java
  a1();
  a2();
  a3();
  a4();
  a5();
  a6();
  a7();
  a8();
  ```
- 建议：无
MD
cat > "$D/new.md" <<'MD'
### P1 | [维度5-安全] 近处样本
- 文件：src/Far.java:10
- 证据：
  ```java
  b1();
  b2();
  b3();
  b4();
  b5();
  b6();
  b7();
  b8();
  ```
- 建议：无
MD
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=0$' <<< "$OUT" || fail "s4 disjoint must not mark"

# 5) IoU 边界：A=[1,3] vs [1,5] 恰为 3/5=0.6（严格大于不命中）；B=[1,2] vs [1,3] 为 2/3≈0.667 命中；
#    CLI 阈值 0.3 时 0.6 > 0.3，A 也命中
D="$TMP_DIR/s5"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度5-安全] 边界A
- 文件：src/A.java:1-5
- 建议：无

### P1 | [维度5-安全] 边界B
- 文件：src/B.java:1-3
- 建议：无
MD
make_s5_new() {
  cat > "$D/new.md" <<'MD'
### P1 | [维度5-安全] 边界A
- 文件：src/A.java:1-3
- 建议：无

### P1 | [维度5-安全] 边界B
- 文件：src/B.java:1-2
- 建议：无
MD
}
make_s5_new
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s5 default only B marked"
grep -q '^### P1 | \[维度5-安全\] 边界A$' "$D/new.md" || fail "s5 exact 0.6 must stay unmarked (strict >)"
grep -q '^### P1 | \[维度5-安全\] 边界B（上轮已报）$' "$D/new.md" || fail "s5 0.667 marked"
make_s5_new
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md" 0.3)"
grep -q '^REPEAT_MARKED=2$' <<< "$OUT" || fail "s5 cli threshold 0.3 marks A too"
grep -q '^### P1 | \[维度5-安全\] 边界A（上轮已报）$' "$D/new.md" || fail "s5 cli override marks A"

# 6) 范围语法 prev path:10-40 vs 点发现：[12,16]→5/31 不标；[10,20]→11/31≈0.35 不标；[10,30]→21/31≈0.677 标
D="$TMP_DIR/s6"; mkdir -p "$D"
emit_point_block() { # <输出文件> <标题> <位置> <证据非空行数>
  local out=$1 title=$2 loc=$3 n=$4 i
  {
    echo "### P1 | [维度5-安全] $title"
    echo "- 文件：$loc"
    echo "- 证据："
    echo '  ```java'
    for i in $(seq 1 "$n"); do echo "  stmt$i();"; done
    echo '  ```'
    echo "- 建议：无"
    echo ""
  } >> "$out"
}
: > "$D/new.md"
emit_point_block "$D/new.md" "One" "src/One.java:12" 5
emit_point_block "$D/new.md" "Two" "src/Two.java:10" 11
emit_point_block "$D/new.md" "Three" "src/Three.java:10" 21
: > "$D/prev.md"
for name in One Two Three; do
  printf '### P1 | [维度5-安全] %s-prev\n- 文件：src/%s.java:10-40\n- 建议：无\n\n' "$name" "$name" >> "$D/prev.md"
done
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_TOTAL_BLOCKS=3$' <<< "$OUT" || fail "s6 total"
grep -q '^REPEAT_PREV_BLOCKS=3$' <<< "$OUT" || fail "s6 prev"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s6 only Three marked"
grep -q '^### P1 | \[维度5-安全\] One$' "$D/new.md" || fail "s6 One (5/31) untouched"
grep -q '^### P1 | \[维度5-安全\] Two$' "$D/new.md" || fail "s6 Two (11/31) untouched"
grep -q '^### P1 | \[维度5-安全\] Three（上轮已报）$' "$D/new.md" || fail "s6 Three (21/31) marked"
grep -q '^- 文件：src/One.java:12$' "$D/new.md" || fail "s6 location lines untouched"

# 7) 待确认块同等参与；无位置 / 无行号锚点的块不计入双方计数
D="$TMP_DIR/s7"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### 待确认 | [维度3-性能] 前次待确认
- 文件：src/Perf.java:20
- 证据：
  ```java
  slow();
  ```
- 建议：复核

### P2 | [维度2-可维护性] 上轮无位置
- 证据：
  ```java
  orphan();
  ```
- 建议：无
MD
cat > "$D/new.md" <<'MD'
### 待确认 | [维度3-性能] 本次待确认
- 文件：src/Perf.java:20
- 证据：
  ```java
  slow();
  ```
- 建议：复核

### P2 | [维度2-可维护性] 本轮无位置
- 证据：
  ```java
  orphan2();
  ```
- 建议：无

### P3 | [维度1-规范] 本轮无行号
- 文件：src/NoLine.java
- 建议：无
MD
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s7 total counts only parseable blocks"
grep -q '^REPEAT_PREV_BLOCKS=1$' <<< "$OUT" || fail "s7 prev counts only parseable blocks"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s7 marked"
grep -q '^### 待确认 | \[维度3-性能\] 本次待确认（上轮已报）$' "$D/new.md" || fail "s7 pending block marked"

# 8) 零标记 → 磁盘字节不变；stdout 计数仍正确
D="$TMP_DIR/s8"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P2 | [维度1-规范] 上轮零标记
- 文件：src/Zero.java:99
- 建议：无
MD
cat > "$D/new.md" <<'MD'
### P2 | [维度1-规范] 本轮零标记
- 文件：src/Zero.java:5
- 建议：无
MD
cp "$D/new.md" "$D/new.before.md"
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s8 total"
grep -q '^REPEAT_PREV_BLOCKS=1$' <<< "$OUT" || fail "s8 prev"
grep -q '^REPEAT_MARKED=0$' <<< "$OUT" || fail "s8 marked"
cmp -s "$D/new.before.md" "$D/new.md" || fail "s8 unmarked run must stay byte-identical"

# 9) 环境变量覆盖生效；CLI 参数优先于环境变量（双向验证）
D="$TMP_DIR/s9"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度5-安全] 阈值样本
- 文件：src/A.java:1-5
- 建议：无
MD
make_s9_new() {
  cat > "$D/new.md" <<'MD'
### P1 | [维度5-安全] 阈值样本
- 文件：src/A.java:1-3
- 建议：无
MD
}
make_s9_new
OUT="$(CC_CODE_REVIEWER_REPEAT_IOU_THRESHOLD=0.5 bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s9 env override 0.5 marks exact-0.6 block"
make_s9_new
OUT="$(CC_CODE_REVIEWER_REPEAT_IOU_THRESHOLD=0.9 bash "$SCRIPT" "$D/new.md" "$D/prev.md" 0.3)"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s9 cli 0.3 must beat env 0.9"
make_s9_new
OUT="$(CC_CODE_REVIEWER_REPEAT_IOU_THRESHOLD=0.3 bash "$SCRIPT" "$D/new.md" "$D/prev.md" 0.7)"
grep -q '^REPEAT_MARKED=0$' <<< "$OUT" || fail "s9 cli 0.7 must beat env 0.3"

# 10) 用法错误：缺参 / 报告缺失 / 上轮报告不可读 / 阈值非法 → exit 1 + stderr 标签
D="$TMP_DIR/s10"; mkdir -p "$D"
printf '### P1 | [维度5-安全] 样本\n- 文件：src/A.java:1\n- 建议：无\n' > "$D/new.md"
printf '### P1 | [维度5-安全] 样本\n- 文件：src/A.java:1\n- 建议：无\n' > "$D/prev.md"
if ERR_OUT="$(bash "$SCRIPT" 2>&1)"; then fail "s10 no args must exit non-zero"; fi
grep -q '请输入' <<< "$ERR_OUT" || fail "s10 no-args error message"
if ERR_OUT="$(bash "$SCRIPT" "$D/new.md" 2>&1)"; then fail "s10 missing prev arg must exit non-zero"; fi
grep -q '请输入' <<< "$ERR_OUT" || fail "s10 missing-prev-arg error message"
if ERR_OUT="$(bash "$SCRIPT" "$TMP_DIR/no-such-new.md" "$D/prev.md" 2>&1)"; then fail "s10 missing new must exit non-zero"; fi
grep -q 'NEW_REPORT_NOT_FOUND=' <<< "$ERR_OUT" || fail "s10 missing new tag"
if ERR_OUT="$(bash "$SCRIPT" "$D/new.md" "$TMP_DIR/no-such-prev.md" 2>&1)"; then fail "s10 missing prev must exit non-zero"; fi
grep -q 'PREV_REPORT_NOT_FOUND=' <<< "$ERR_OUT" || fail "s10 missing prev tag"
printf '### P1 | [维度5-安全] 锁定\n- 文件：src/A.java:1\n' > "$D/locked-prev.md"
chmod 000 "$D/locked-prev.md"
if ERR_OUT="$(bash "$SCRIPT" "$D/new.md" "$D/locked-prev.md" 2>&1)"; then fail "s10 unreadable prev must exit non-zero"; fi
grep -q 'PREV_REPORT_NOT_READABLE=' <<< "$ERR_OUT" || fail "s10 unreadable prev tag"
chmod 644 "$D/locked-prev.md"
if ERR_OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md" abc 2>&1)"; then fail "s10 non-numeric threshold must exit non-zero"; fi
grep -q 'ERROR_REPEAT_IOU_THRESHOLD=' <<< "$ERR_OUT" || fail "s10 non-numeric threshold tag"
if ERR_OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md" 1.5 2>&1)"; then fail "s10 out-of-range threshold must exit non-zero"; fi
grep -q 'ERROR_REPEAT_IOU_THRESHOLD=' <<< "$ERR_OUT" || fail "s10 out-of-range threshold tag"

# 11) CRLF 报告：标记行干净重写，无 \r 残留
D="$TMP_DIR/s11"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度1-规范] CRLF 样本
- 文件：src/Crlf.java:7
- 证据：
  ```java
  ping();
  ```
- 建议：无
MD
cat > "$D/new.lf.md" <<'MD'
### P1 | [维度1-规范] CRLF 样本
- 文件：src/Crlf.java:7
- 证据：
  ```java
  ping();
  ```
- 建议：无
MD
perl -pe 's/\n/\r\n/g' "$D/new.lf.md" > "$D/new.md"
OUT="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT" || fail "s11 marked"
if grep -q $'\r' "$D/new.md"; then fail "s11 CR corruption in rewritten report"; fi
grep -q '^### P1 | \[维度1-规范\] CRLF 样本（上轮已报）$' "$D/new.md" || fail "s11 header rewritten cleanly"
grep -q '^- 文件：src/Crlf.java:7$' "$D/new.md" || fail "s11 location intact"

# 12) 双重运行确定性：第二次运行零改动、标记不叠加、字节稳定
D="$TMP_DIR/s12"; mkdir -p "$D"
cat > "$D/prev.md" <<'MD'
### P1 | [维度5-安全] 幂等样本
- 文件：src/Idem.java:8
- 证据：
  ```java
  check();
  ```
- 建议：无
MD
cp "$D/prev.md" "$D/new.md"
OUT1="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=1$' <<< "$OUT1" || fail "s12 first run marked"
cp "$D/new.md" "$D/new.run1.md"
OUT2="$(bash "$SCRIPT" "$D/new.md" "$D/prev.md")"
grep -q '^REPEAT_MARKED=0$' <<< "$OUT2" || fail "s12 second run must not re-mark"
grep -q '^REPEAT_TOTAL_BLOCKS=1$' <<< "$OUT2" || fail "s12 second run total"
cmp -s "$D/new.run1.md" "$D/new.md" || fail "s12 double-run bytes must be identical"
MARKER_LINES="$(grep -c '（上轮已报）' "$D/new.md" || true)"
test "$MARKER_LINES" -eq 1 || fail "s12 exactly one marker per block"

echo "PASS: core mark-repeat-findings"
