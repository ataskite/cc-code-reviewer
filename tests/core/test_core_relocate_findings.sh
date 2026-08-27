#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-relocate.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT="$ROOT_DIR/scripts/core/relocate-findings.sh"
fail() { echo "FAIL: core relocate-findings: $*" >&2; exit 1; }

# 1) 同文件行号漂移：证据在第 40 行，报告写第 5 行 → 行号就地修正
D="$TMP_DIR/s1"; mkdir -p "$D/src"
{ for i in $(seq 1 39); do echo "int filler$i = 0;"; done
  echo 'if (user.getRole().equals("admin")) {'
  echo '    grantAll();'
  echo '}'
} > "$D/src/Main.java"
printf 'src/Main.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度5-安全] 越权检查缺失
- 文件：src/Main.java:5
- 置信度：高
- 证据：
  ```java
  if (user.getRole().equals("admin")) {
      grantAll();
  }
  ```
- 建议：补充权限校验
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
REPORT_ABS="$(cd "$D" && pwd -P)/report.md"
grep -q "^RELOCATE_REPORT_PATH=$REPORT_ABS$" <<< "$OUT" || fail "s1 report path"
grep -q '^RELOCATE_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s1 total"
grep -q '^RELOCATE_SAME_FILE_FIXED=1$' <<< "$OUT" || fail "s1 same-file fixed"
grep -q '^RELOCATE_REFILED=0$' <<< "$OUT" || fail "s1 refiled"
grep -q '^RELOCATE_UNRESOLVED=0$' <<< "$OUT" || fail "s1 unresolved"
test "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 5 || fail "s1 stdout contract"
grep -q '^- 文件：src/Main.java:40$' "$D/report.md" || fail "s1 line corrected to 40"
if grep -q '位置修正' "$D/report.md"; then fail "s1 must not add note"; fi

# 2) 跨文件唯一命中：证据只在 Other.java → 重归档并追加位置修正说明
D="$TMP_DIR/s2"; mkdir -p "$D/src/other"
{ echo 'public class Other {'
  for i in $(seq 1 9); do echo "    int pad$i;"; done
  echo '    void run() {'
  echo '        service.execute();'
  echo '    }'
  echo '}'
} > "$D/src/other/Other.java"
printf 'public class Main {\n    public static void main(String[] args) {\n        start();\n    }\n}\n' > "$D/src/Main.java"
printf 'src/Main.java\nsrc/other/Other.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度4-正确性] 调用错位
- 文件：src/Main.java:1
- 置信度：中
- 证据：
  ```java
  void run() {
      service.execute();
  }
  ```
- 建议：定位到 Other.java
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s2 total"
grep -q '^RELOCATE_REFILED=1$' <<< "$OUT" || fail "s2 refiled"
grep -q '^RELOCATE_SAME_FILE_FIXED=0$' <<< "$OUT" || fail "s2 same-file"
grep -q '^RELOCATE_UNRESOLVED=0$' <<< "$OUT" || fail "s2 unresolved"
grep -q '^- 文件：src/other/Other.java:11$' "$D/report.md" || fail "s2 relocated to Other.java:11"
NOTE_LINE="$(awk 'index($0,"- 文件：src/other/Other.java:11")==1{getline; print}' "$D/report.md")"
grep -qF -- '- 位置修正：原 src/Main.java:1，证据代码实际位于本文件（跨文件重归档）' <<< "$NOTE_LINE" || fail "s2 note line after location"
if grep -q '^- 文件：src/Main.java:1$' "$D/report.md"; then fail "s2 old location must be rewritten"; fi

# 3) 歧义：相同证据出现在两个候选文件 → 保持原状
D="$TMP_DIR/s3"; mkdir -p "$D/src"
for n in A B; do
  { echo "public class $n {"; echo '    void ping() {'; echo '        heart.beat();'; echo '    }'; echo '}'; } > "$D/src/$n.java"
done
printf 'public class Main {\n}\n' > "$D/src/Main.java"
printf 'src/Main.java\nsrc/A.java\nsrc/B.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度6-可靠性] 心跳重复
- 文件：src/Main.java:1
- 证据：
  ```java
  void ping() {
      heart.beat();
  }
  ```
- 建议：人工复核
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_REFILED=0$' <<< "$OUT" || fail "s3 refiled"
grep -q '^RELOCATE_UNRESOLVED=1$' <<< "$OUT" || fail "s3 unresolved"
grep -q '^- 文件：src/Main.java:1$' "$D/report.md" || fail "s3 location unchanged"
if grep -q '位置修正' "$D/report.md"; then fail "s3 must not add note"; fi

# 4) 证据在任何范围内都找不到 → 保持原状
D="$TMP_DIR/s4"; mkdir -p "$D/src"
printf 'public class Main {\n}\n' > "$D/src/Main.java"
printf 'public class Util {\n    int a;\n}\n' > "$D/src/Util.java"
printf 'src/Main.java\nsrc/Util.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P2 | [维度4-正确性] 幻影调用
- 文件：src/Main.java:1
- 证据：
  ```java
  missingCall();
  ```
- 建议：人工复核
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s4 total"
grep -q '^RELOCATE_UNRESOLVED=1$' <<< "$OUT" || fail "s4 unresolved"
grep -q '^- 文件：src/Main.java:1$' "$D/report.md" || fail "s4 location unchanged"

# 5) 范围围栏：证据文件在磁盘上但不在 manifest 内 → 不允许重归档
D="$TMP_DIR/s5"; mkdir -p "$D/src"
printf 'public class Main {\n}\n' > "$D/src/Main.java"
{ echo 'public class Outside {'; echo '    void hidden() {'; echo '        secret.run();'; echo '    }'; echo '}'; } > "$D/src/Outside.java"
printf 'src/Main.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度5-安全] 隐式执行
- 文件：src/Main.java:1
- 证据：
  ```java
  void hidden() {
      secret.run();
  }
  ```
- 建议：人工复核
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_REFILED=0$' <<< "$OUT" || fail "s5 refiled"
grep -q '^RELOCATE_UNRESOLVED=1$' <<< "$OUT" || fail "s5 unresolved"
grep -q '^- 文件：src/Main.java:1$' "$D/report.md" || fail "s5 location unchanged"
if grep -q '位置修正' "$D/report.md"; then fail "s5 must not add note"; fi

# 6) 匹配鲁棒性：证据带 + 前缀且穿插空行，源文件空行不断开连续性
D="$TMP_DIR/s6"; mkdir -p "$D/src"
{ echo 'public class Svc {'
  for i in $(seq 1 8); do echo "    int filler$i;"; done
  echo '    public void transfer() {'
  echo ''
  echo '        audit();'
  echo ''
  echo '    }'
  echo '}'
} > "$D/src/Svc.java"
printf 'src/Svc.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度4-正确性] 转账缺少审计
- 文件：src/Svc.java:2
- 证据：
  ```diff
  +    public void transfer() {
  +
  +        audit();
  +
  +    }
  ```
- 建议：补充审计
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_SAME_FILE_FIXED=1$' <<< "$OUT" || fail "s6 same-file fixed"
grep -q '^- 文件：src/Svc.java:10$' "$D/report.md" || fail "s6 line corrected to 10"

# 7) 二进制候选（前 8000 字节含 NUL）被跳过
D="$TMP_DIR/s7"; mkdir -p "$D/src"
printf 'public class Main {\n}\n' > "$D/src/Main.java"
{ printf 'binary\x00marker\n'; echo '    void target() {'; echo '        hit();'; echo '    }'; } > "$D/src/Blob.java"
printf 'src/Main.java\nsrc/Blob.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度5-安全] 命中二进制
- 文件：src/Main.java:1
- 证据：
  ```java
  void target() {
      hit();
  }
  ```
- 建议：人工复核
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_REFILED=0$' <<< "$OUT" || fail "s7 refiled"
grep -q '^RELOCATE_UNRESOLVED=1$' <<< "$OUT" || fail "s7 unresolved"
grep -q '^- 文件：src/Main.java:1$' "$D/report.md" || fail "s7 location unchanged"

# 8) 无围栏证据 / 无位置行的块不计入 TOTAL；未修改时报告字节不变
D="$TMP_DIR/s8"; mkdir -p "$D/src"
printf 'public class A {\n    int x = 1;\n}\n' > "$D/src/A.java"
printf 'src/A.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度1-规范] 示例
- 文件：src/A.java:2
- 证据：
  ```java
  int x = 1;
  ```
- 建议：无

### P2 | [维度2-可维护性] 无证据块
- 文件：src/A.java:1
- 建议：补充证据

### 待确认 | [维度3-性能] 无位置块
- 证据：
  ```java
  int x = 1;
  ```
- 建议：无
MD
cp "$D/report.md" "$D/report.before.md"
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s8 only full blocks counted"
grep -q '^RELOCATE_SAME_FILE_FIXED=0$' <<< "$OUT" || fail "s8 same-file"
grep -q '^RELOCATE_REFILED=0$' <<< "$OUT" || fail "s8 refiled"
grep -q '^RELOCATE_UNRESOLVED=0$' <<< "$OUT" || fail "s8 unresolved"
cmp -s "$D/report.before.md" "$D/report.md" || fail "s8 untouched report must stay byte-identical"

# 9) 待确认块头同样参与处理（跨文件唯一命中 → 重归档）
D="$TMP_DIR/s9"; mkdir -p "$D/src"
printf 'public class Main {\n}\n' > "$D/src/Main.java"
{ echo 'public class Util {'; echo '    void warmup() {'; echo '        slowScan();'; echo '    }'; echo '}'; } > "$D/src/Util.java"
printf 'src/Main.java\nsrc/Util.java\n' > "$D/manifest.txt"
cat > "$D/report.md" <<'MD'
# 代码审查报告

## 发现列表

### 待确认 | [维度7-性能] 证据位置待定
- 文件：src/Main.java:3
- 证据：
  ```java
  void warmup() {
      slowScan();
  }
  ```
- 建议：复核
MD
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_TOTAL_BLOCKS=1$' <<< "$OUT" || fail "s9 total"
grep -q '^RELOCATE_REFILED=1$' <<< "$OUT" || fail "s9 refiled"
grep -q '^- 文件：src/Util.java:2$' "$D/report.md" || fail "s9 relocated to Util.java:2"
grep -qF -- '- 位置修正：原 src/Main.java:3，证据代码实际位于本文件（跨文件重归档）' "$D/report.md" || fail "s9 note line"

# 10) CRLF 报告可正确处理，重写后行尾归一为 LF
D="$TMP_DIR/s10"; mkdir -p "$D/src"
printf 'public class App {\n    void init() {\n        boot();\n    }\n}\n' > "$D/src/App.java"
printf 'src/App.java\n' > "$D/manifest.txt"
cat > "$D/report.lf.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度1-规范] 行号漂移
- 文件：src/App.java:9
- 证据：
  ```java
  void init() {
      boot();
  }
  ```
- 建议：无
MD
perl -pe 's/\n/\r\n/g' "$D/report.lf.md" > "$D/report.md"
OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$D/manifest.txt")"
grep -q '^RELOCATE_SAME_FILE_FIXED=1$' <<< "$OUT" || fail "s10 same-file fixed"
grep -q '^- 文件：src/App.java:2$' "$D/report.md" || fail "s10 corrected line must be CR-free"

# 用法错误：manifest 不可读 → 非零退出并输出 ERROR 标签
if ERR_OUT="$(bash "$SCRIPT" "$D/report.md" "$D" "$TMP_DIR/missing-manifest.txt" 2>&1)"; then
  fail "missing manifest should exit non-zero"
fi
grep -q 'MANIFEST_FILE_NOT_READABLE=' <<< "$ERR_OUT" || fail "missing manifest error tag"

# 11) manifest 越出项目根目录（绝对路径）→ 外部文件不得成为候选
D="$TMP_DIR/s11"; mkdir -p "$D/project/src" "$D/outside"
printf 'public class Main {}\n' > "$D/project/src/Main.java"
printf 'void hidden() {\n    secret.run();\n}\n' > "$D/outside/Outside.java"
printf '%s\n' "$D/outside/Outside.java" > "$D/project/manifest.txt"
cat > "$D/project/report.md" <<'MD'
# 代码审查报告

## 发现列表

### P1 | [维度5-安全] 越界证据
- 文件：src/Main.java:1
- 证据：
  ```java
  void hidden() {
      secret.run();
  }
  ```
- 建议：人工复核
MD
OUT="$(bash "$SCRIPT" "$D/project/report.md" "$D/project" "$D/project/manifest.txt")"
grep -q '^RELOCATE_REFILED=0$' <<< "$OUT" || fail "s11 external manifest must not refile"
grep -q '^RELOCATE_UNRESOLVED=1$' <<< "$OUT" || fail "s11 external manifest must remain unresolved"
grep -q '^- 文件：src/Main.java:1$' "$D/project/report.md" || fail "s11 location must remain unchanged"
if grep -q "$D/outside/Outside.java" "$D/project/report.md"; then fail "s11 external path leaked into report"; fi

echo "PASS: core relocate-findings"
