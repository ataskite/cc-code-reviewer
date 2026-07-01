# 前端审查（React Scan）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `cc-code-reviewer` 统一入口支持 TypeScript/JavaScript + React 项目的增量与存量代码审查（含分批、覆盖率、Ignore、本地报告与飞书输出），同时保证 Java 现有契约零回归。

**Architecture:** 采用「共享内核 + 独立语言适配器」。共享内核负责 Git 范围、交互门禁、批次运行/恢复、覆盖率、合并去重、Ignore、报告与飞书输出；语言适配器负责项目识别、源码口径、技术栈规则、语义工具、审查维度与 Agent 提示词。前端通过 `scripts/languages/frontend/` 适配器与 `agents/cc-code-reviewer-frontend.md` 接入，不改 Java 现有脚本，Java 在 Phase 4 才逐步迁入 `scripts/core/`。

**Tech Stack:** Bash + perl（脚本层，与现有 phase*.sh 一致）；Markdown（Skill / Agent / references）；Claude Code Task 子代理（`cc-code-reviewer-frontend`）；TypeScript LSP（可选语义增强，不可用时静态降级）；`lark-cli` + `lark-doc`/`lark-base`（飞书输出）。

---

## Global Constraints

以下约束来自 spec（`docs/superpowers/specs/2026-06-23-multi-language-reviewer-design.md`），每个任务的需求都隐式包含本节：

- **首期范围**：TS/JS + React + Vite/Webpack + npm/pnpm/yarn；Vue/Next.js/Nuxt/Node/BFF/Python 为非目标。
- **前端只做 Scan 闭环**：不为前端接入报告驱动 Fix。
- **TypeScript LSP 是可选增强**：不可用时必须明确降级并在报告披露，不作为运行前置条件。
- **一次运行只审一种语言**：混合仓库识别所有候选语言后，由用户选择一种；另一种只能作为仓库背景，不能产出正式问题。
- **不自动执行依赖安装/构建**：适配器不得运行 `npm install`、package scripts、构建或应用代码。
- **正式源码口径**：生产 `.ts/.tsx/.js/.jsx`；测试、生成代码、`node_modules`、`dist`/`build` 产物不计入正式覆盖率，也不得成为正式问题位置。
- **配置单独计数**：`package.json`、TS/Vite/Webpack/路由配置等正式配置文件可产生问题，但单独记 `FORMAL_CONFIG_FILE_COUNT`，不进入源码覆盖率分母。
- **Java 契约冻结**：Phase 0–2 不改 Java 脚本逻辑、交互顺序、报告与 Fix；Java 行为先冻结，Phase 4 才迁移。
- **平台**：仅 macOS / Linux（Bash）；脚本用 Bash 调用 `perl`，保持与现有 phase*.sh 相同的混用风格。
- **CONTEXT_SCALE**：前端分批预算同样按 `phase14-detect-model-context.sh` 的 `CONTEXT_SCALE` 缩放，1M 窗口模型产生更少、更大批次。
- **公共内核不得含框架/语言语义**：`scripts/core/` 不解析 `package.json`、不包含 React/Vue/Django 专项规则。
- **中文输出**：所有交互与报告必须中文；代码标识符、框架名、配置键可保留原文。

---

## File Structure

新建文件与改动文件总览（Phase 0–3 范围；Phase 4 迁移任务在末尾单独列出）：

```
cc-code-reviewer/
├── skills/cc-code-reviewer/SKILL.md            # 改：在预扫描后增加语言探测与路由分支
├── agents/
│   ├── cc-code-reviewer.md                     # 不动（Java Agent 冻结）
│   └── cc-code-reviewer-frontend.md            # 新：前端专属 Agent
├── scripts/
│   ├── core/
│   │   ├── detect-language.sh                  # 新：候选语言识别 + 混合仓库选择输出
│   │   ├── validate-scope.sh                   # 新：通用项目根目录边界校验
│   │   ├── collect-source-files.sh             # 新：按语言 source manifest 收集生产源码（供前端复用）
│   │   ├── plan-file-batches.sh                # 新：通用文件 token 批次规划（语言中立）
│   │   └── merge-batch-results.sh              # 新：通用状态门禁、去重与合并（语言中立）
│   ├── languages/
│   │   └── frontend/
│   │       ├── detect-project.sh               # 新：前端项目类型识别（package.json + React 证据）
│   │       ├── scan-project.sh                 # 新：源码统计、组件、技术栈、SOURCE_SCOPE
│   │       ├── collect-source-files.sh         # 新：前端生产源码清单（排除测试/产物）
│   │       └── detect-code-intelligence.sh     # 新：TypeScript LSP 探测与降级
│   └── phase*.sh                               # 不动（Java 脚本冻结）
├── references/
│   ├── language-adapter-contract.md            # 新：PROFILE_SCHEMA 协议与适配器职责
│   ├── shared-review-framework.md              # 新：15 维度公共 ID 定义与语言映射说明
│   ├── report-format.md                        # 改：增加前端报告字段（覆盖率口径、语义状态披露）
│   └── languages/
│       └── frontend/
│           ├── source-scope.md                 # 新：前端正式范围/只读上下文/排除规则
│           ├── review-framework.md             # 新：前端模式 × 维度覆盖矩阵
│           └── react-rules.md                  # 新：React MVP 专项规则
└── tests/
    ├── core/
    │   ├── test_detect_language.sh
    │   ├── test_validate_scope.sh
    │   ├── test_core_plan_file_batches.sh
    │   └── test_core_merge_batch_results.sh
    ├── frontend/
    │   ├── test_frontend_detect_project.sh
    │   ├── test_frontend_scan_project.sh
    │   ├── test_frontend_collect_source_files.sh
    │   ├── test_frontend_detect_code_intelligence.sh
    │   ├── test_frontend_route_react.sh
    │   ├── test_frontend_reject_nextjs.sh
    │   └── test_frontend_full_scan_smoke.sh     # 场景测试（合成 React 仓库）
    └── test_contract_docs.sh                    # 改：增加前端文档同步断言
```

**职责边界**：
- `scripts/core/*.sh`：语言中立。`detect-language.sh` 只判断「有哪些候选语言」并输出，不解释框架；其余 4 个脚本只消费 PROFILE_SCHEMA 的中性字段（`source_file_count` 等），不含 React/Java 判断。
- `scripts/languages/frontend/*.sh`：只服务前端；负责 `package.json`/构建配置解析、React 证据、生产源码口径、TS LSP 探测；输出 PROFILE_SCHEMA v1。
- `agents/cc-code-reviewer-frontend.md`：消费注入参数（含 PROFILE 行、source manifest、SEMANTIC_LEVEL），按前端审查矩阵执行，不得交互。

---

## Task 0（Phase 0）：锁定 Java 基线契约快照

**Goal:** 在引入任何前端代码前，固化 Java 现有契约，确保后续改造可被回归验证。本任务**只新增测试与文档快照，不改 Java 脚本逻辑**。

**Files:**
- Create: `tests/java/test_java_baseline_contract.sh`
- Create: `tests/java/fixtures/`（合成 Java 仓库，供契约测试复用）
- Modify: `tests/run_all.sh:11`（遍历改为递归包含 `tests/java/`、`tests/core/`、`tests/frontend/` 下的 `test_*.sh`）
- Modify: `references/language-adapter-contract.md`（本任务先建文件骨架，写入 Java 字段→公共字段映射表，后续任务补充）

**Interfaces:**
- Consumes: 现有 `scripts/phase3-project-scan.sh`、`scripts/phase11-plan-file-batches.sh`、`scripts/phase12-merge-large-batches.sh` 的输出契约（Java 现状）
- Produces: `tests/java/test_java_baseline_contract.sh`（断言 Java 用户可见输出字段名不变）；`tests/java/fixtures/`（后续前端混合仓库测试复用其中的 Java 仓库结构）

- [ ] **Step 1: 写失败测试 — Java 单模块预扫描字段契约**

`tests/java/test_java_baseline_contract.sh`：

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java-baseline.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/maven-single"
SRC_DIR="$PROJECT_DIR/src/main/java/com/example"
mkdir -p "$SRC_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
cat > "$PROJECT_DIR/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion>
<groupId>com.example</groupId><artifactId>maven-single</artifactId><version>1.0</version>
</project>
XML
cat > "$SRC_DIR/Foo.java" <<'JAVA'
package com.example; public class Foo { public void m() {} }
JAVA

OUTPUT="$(bash "$ROOT_DIR/scripts/phase3-project-scan.sh" "$PROJECT_DIR")"

# Java 用户可见输出字段必须保持不变
grep -q "项目类型: Maven" <<< "$OUTPUT"
grep -q "PROJECT_TYPE=maven-single" <<< "$OUTPUT"
grep -q "Java文件总数: 1" <<< "$OUTPUT"
grep -q "模块类型: 单模块项目" <<< "$OUTPUT"
# TECH_STACK 行格式不变（即使未识别也必须输出兜底行）
grep -q "TECH_STACK:" <<< "$OUTPUT"

echo "PASS: java baseline prescan contract"
```

- [ ] **Step 2: 运行测试，确认它通过（固化基线，非 TDD 失败）**

Run: `bash tests/java/test_java_baseline_contract.sh`
Expected: PASS（当前 Java 行为已满足；此测试用于锁死字段，未来重构不得破坏）

- [ ] **Step 3: 写失败测试 — Java 文件批次 planner 字段契约**

追加到 `tests/java/test_java_baseline_contract.sh` 末尾（`echo "PASS"` 之前）：

```bash
# === 文件批次 planner 字段契约（现有 phase11-plan-file-batches.sh）===
SRC2="$PROJECT_DIR/src/main/java/com/example/svc"
mkdir -p "$SRC2"
for i in 1 2 3 4 5; do
  { echo "package com.example.svc;"; echo "public class S${i} {"; seq 1 9000 | sed 's/.*/  public void m&() {}/'; echo "}"; } > "$SRC2/S${i}.java"
done

BOUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-000000 bash "$ROOT_DIR/scripts/phase11-plan-file-batches.sh" "$PROJECT_DIR" "standard" "main")"
grep -q "RUN_ID=" <<< "$BOUT"
grep -q "RUN_DIR=" <<< "$BOUT"
grep -q "BATCH_COUNT=" <<< "$BOUT"
grep -q "TOTAL_JAVA_FILE_COUNT=" <<< "$BOUT"
grep -q "TOTAL_JAVA_LOC=" <<< "$BOUT"
grep -q "BATCH_FILE_LIST_DIR=" <<< "$BOUT"
grep -q "简要分批计划" <<< "$BOUT"
BRUN_DIR="$(printf '%s\n' "$BOUT" | sed -n 's/^RUN_DIR=//p')"
grep -q '"strategy": "file-token-batching"' "$BRUN_DIR/plan.json"
grep -q '"schema_version": 1' "$BRUN_DIR/plan.json"
test -f "$BRUN_DIR/batches/batch-001.files"
test -f "$BRUN_DIR/batches/batch-001.json"
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `bash tests/java/test_java_baseline_contract.sh`
Expected: PASS

- [ ] **Step 5: 写失败测试 — Java 合并报告字段契约（source_file_count 中性映射前快照）**

追加：

```bash
# === 合并报告字段契约（现有 phase12-merge-large-batches.sh）===
LRUN_DIR="$TMP_DIR/large-run"
mkdir -p "$LRUN_DIR/batches" "$LRUN_DIR/results"
cat > "$LRUN_DIR/plan.json" <<'JSON'
{"schema_version":1,"run_id":"r1","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","semantic_level":"maven-static",
 "total_java_loc":500,"total_java_file_count":2,"batch_count":1}
JSON
cat > "$LRUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":500,"planned_java_file_count":2,
 "scan_roots":["src"],"modules":[{"name":"root"}]}
JSON
cat > "$LRUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_java_loc":500,
 "planned_java_file_count":2,"result_path":"$LRUN_DIR/results/batch-001.md","finding_count":0}
JSON
cat > "$LRUN_DIR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
（无正式发现）
MD
MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$LRUN_DIR")"
grep -q "SUMMARY_PATH=" <<< "$MOUT"
grep -q "FINAL_REPORT_PATH=" <<< "$MOUT"
SUMMARY="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
grep -q '"report_title"' "$SUMMARY"
grep -q '"finding_count"' "$SUMMARY"
grep -q '"java_file_coverage_percent"' "$SUMMARY"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT" | grep -q '^# '
```

- [ ] **Step 6: 运行测试，确认通过**

Run: `bash tests/java/test_java_baseline_contract.sh`
Expected: PASS

- [ ] **Step 7: 让 run_all.sh 递归发现子目录测试**

Modify `tests/run_all.sh`（替换第 11 行的 for 循环）：

```bash
# 递归发现所有子目录下的 test_*.sh，保证 tests/java、tests/core、tests/frontend 被纳入
while IFS= read -r -d '' test_file; do
  test_name="${test_file#$TEST_DIR/}"
  echo "==> $test_name"
  bash "$test_file"
  echo "    ok"
done < <(find "$TEST_DIR" -type f -name 'test_*.sh' -print0 | sort -z)
```

- [ ] **Step 8: 运行完整测试套件，确认 Java 无回归**

Run: `bash tests/run_all.sh`
Expected: All tests passed（含新增 `java/test_java_baseline_contract.sh`）

- [ ] **Step 9: 建 language-adapter-contract 骨架，写入 Java 字段映射表**

Create `references/language-adapter-contract.md`（骨架 + Java 映射，完整 PROFILE_SCHEMA 在 Task 3 定义）：

```markdown
# Language Adapter Contract

本文件定义语言适配器与共享内核之间的标准协议。预扫描采用版本化的 key=value 输出。

## Java 字段 → 公共字段映射（兼容桥）

| Java 现有输出 | 公共中性字段 | 说明 |
|---|---|---|
| `Java文件总数`（phase3 文本行） | `source_file_count` | 仅 src/main/java 生产源码 |
| `代码总行数` | `source_line_count` | 仅 src/main/java |
| `MODULE:` 行 | `COMPONENT:` 行 | 公共层只保存展示 |
| `TECH_STACK:` 行 | `TECH_STACK:` 行 | 透传，公共层不解释 |
| phase10 输出 | `CODE_INTELLIGENCE_PROVIDER` | jdtls-lsp / none |

> Java 适配器在迁移前（Phase 4 之前）继续输出原有字段；公共层在 Task 1 引入兼容映射。完整 PROFILE_SCHEMA v1 定义见「Phase 1」段。

（Phase 1 将补充 PROFILE_SCHEMA 完整定义、适配器职责与 schema version 处理规则。）
```

- [ ] **Step 10: 提交**

```bash
git add tests/run_all.sh tests/java/ references/language-adapter-contract.md
git commit -m "test: lock Java baseline contract before multi-language extension"
```

---

## Task 1（Phase 1 核心）：语言探测内核 + validate-scope

**Goal:** 实现 `scripts/core/detect-language.sh` 识别候选语言（Java / Frontend），`scripts/core/validate-scope.sh` 做项目根目录边界校验。本任务**不**改主 SKILL 流程（路由分支在 Task 6 接入）。

**Files:**
- Create: `scripts/core/validate-scope.sh`
- Create: `scripts/core/detect-language.sh`
- Create: `tests/core/test_validate_scope.sh`
- Create: `tests/core/test_detect_language.sh`

**Interfaces:**
- Consumes: 项目目录路径
- Produces:
  - `validate-scope.sh`：输入 `PROJECT_DIR` + 路径列表（逗号分隔）；逃逸路径返回非 0 并打印 `SCOPE_OUTSIDE_PROJECT=<path>`；合法路径逐行回显规范化绝对路径。
  - `detect-language.sh`：输入 `PROJECT_DIR`；输出 `CANDIDATE_LANGUAGE:java|evidence=...` 和/或 `CANDIDATE_LANGUAGE:frontend|evidence=...`；无候选时 `CANDIDATE_LANGUAGE:none`。

- [ ] **Step 1: 写失败测试 — validate-scope 边界校验**

`tests/core/test_validate_scope.sh`：

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/validate-scope.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/proj"
mkdir -p "$PROJECT_DIR/src/app" "$PROJECT_DIR/node_modules"

# 合法相对路径 → 输出绝对路径，退出 0
OUT="$(bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "src/app,src/app/sub")"
grep -F "$PROJECT_DIR/src/app" <<< "$OUT"
grep -F "$PROJECT_DIR/src/app/sub" <<< "$OUT"

# 绝对路径 → 拒绝
set +e
bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "/etc/passwd" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -ne 0

# .. 穿越 → 拒绝
set +e
bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "../outside" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -ne 0

# 解析后逃逸（符号链接到项目外）→ 拒绝
ln -s "$TMP_DIR/outside" "$PROJECT_DIR/link"
set +e
bash "$ROOT_DIR/scripts/core/validate-scope.sh" "$PROJECT_DIR" "link" >/dev/null 2>&1
RC=$?
set -e
test "$RC" -ne 0

echo "PASS: validate-scope"
```

- [ ] **Step 2: 运行测试，确认它失败**

Run: `bash tests/core/test_validate_scope.sh`
Expected: FAIL（`scripts/core/validate-scope.sh` 不存在）

- [ ] **Step 3: 实现 validate-scope.sh**

`scripts/core/validate-scope.sh`：

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
SCOPE_INPUT="${2:-}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

normalize_input() {
  printf '%s' "$SCOPE_INPUT" | perl -CS -Mutf8 -pe 's/[，、\s]+/,/g; s/^,+|,+//g' | tr ',' '\n'
}

fail() { echo "SCOPE_OUTSIDE_PROJECT=$1" >&2; exit 1; }

[ -n "$SCOPE_INPUT" ] || { echo "$PROJECT_DIR"; exit 0; }

while IFS= read -r raw; do
  [ -n "$raw" ] || continue
  case "$raw" in
    /*|\~*) fail "$raw" ;;
  esac
  resolved="$PROJECT_DIR/$raw"
  case "$resolved" in
    "$PROJECT_DIR"/*) ;;
    *) fail "$raw" ;;
  esac
  # 解析符号链接后再校验是否仍在项目内
  if resolved_real="$(cd "$resolved" 2>/dev/null && pwd)"; then
    case "$resolved_real" in
      "$PROJECT_DIR"/*|"$PROJECT_DIR") printf '%s\n' "$resolved_real" ;;
      *) fail "$raw" ;;
    esac
  else
    printf '%s\n' "$PROJECT_DIR/$raw"
  fi
done < <(normalize_input)
```

Run: `bash tests/core/test_validate_scope.sh` → Expected: PASS

- [ ] **Step 4: 写失败测试 — detect-language 候选识别**

`tests/core/test_detect_language.sh`：

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/detect-lang.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mk_java() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src/main/java/com/x"
  cat > "$d/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion><groupId>com.x</groupId><artifactId>j</artifactId><version>1</version></project>
XML
  echo "package com.x; public class A {}" > "$d/src/main/java/com/x/A.java"
}

mk_react() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
  echo 'export function App(){return <div/>}' > "$d/src/App.tsx"
}

# 纯 Java
mk_java java_only
JOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/java_only")"
grep -q "CANDIDATE_LANGUAGE:java" <<< "$JOUT"
! grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$JOUT"

# 纯前端（有 React 依赖 + tsx 证据）
mk_react react_only
FOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/react_only")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$FOUT"
! grep -q "CANDIDATE_LANGUAGE:java" <<< "$FOUT"

# 混合：两者都报
mk_java mixed; mk_react mixed
MOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/mixed")"
grep -q "CANDIDATE_LANGUAGE:java" <<< "$MOUT"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$MOUT"

# 仅有 package.json 但无 React 依赖 → 不报前端
mkdir -p "$TMP_DIR/no_react"
cat > "$TMP_DIR/no_react/package.json" <<'JSON'
{"name":"lib","dependencies":{"lodash":"^4.0.0"}}
JSON
NOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/no_react")"
! grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$NOUT"

# 空目录 → none
mkdir -p "$TMP_DIR/empty"
grep -q "CANDIDATE_LANGUAGE:none" < <(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/empty")

echo "PASS: detect-language"
```

- [ ] **Step 5: 运行测试，确认失败**

Run: `bash tests/core/test_detect_language.sh`
Expected: FAIL（脚本不存在）

- [ ] **Step 6: 实现 detect-language.sh**

`scripts/core/detect-language.sh`：

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "CANDIDATE_LANGUAGE:none"; exit 0; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

PRUNE_EXPR='\( -path */node_modules/* -o -path */target/* -o -path */build/* -o -path */dist/* -o -path */.git/* \) -prune'

has_java() {
  [ -f "$PROJECT_DIR/pom.xml" ] && return 0
  find "$PROJECT_DIR" -maxdepth 1 -name 'build.gradle*' -type f -print -quit 2>/dev/null | grep -q . && return 0
  eval "find '$PROJECT_DIR' $PRUNE_EXPR -o -name '*.java' -print -quit 2>/dev/null | grep -q ."
}

# 仅 package.json 不算前端；必须有 react 依赖 + .tsx/.jsx 或 React 入口证据
has_frontend() {
  # 收集候选 package.json（根 + maxdepth 3，排除 node_modules/dist/build）
  local pkgs
  pkgs="$(find "$PROJECT_DIR" -maxdepth 3 \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune -o -name 'package.json' -type f -print 2>/dev/null)"
  [ -n "$pkgs" ] || return 1
  local has_react=0 pkg
  while IFS= read -r pkg; do
    if grep -Eq '"react"\s*:\s*"[^"]+' "$pkg" 2>/dev/null; then
      has_react=1; break
    fi
  done <<< "$pkgs"
  [ "$has_react" -eq 1 ] || return 1
  # React 入口证据
  eval "find '$PROJECT_DIR' $PRUNE_EXPR -o \( -name '*.tsx' -o -name '*.jsx' \) -print -quit 2>/dev/null | grep -q ."
}

emit() { printf 'CANDIDATE_LANGUAGE:%s|evidence=%s\n' "$1" "$2"; }

found=0
if has_java; then emit java "maven/gradle-or-java-source"; found=1; fi
if has_frontend; then emit frontend "react-dependency+tsx-or-jsx"; found=1; fi
[ "$found" -eq 0 ] && echo "CANDIDATE_LANGUAGE:none"
```

- [ ] **Step 7: 运行测试，确认通过**

Run: `bash tests/core/test_detect_language.sh`
Expected: PASS

- [ ] **Step 8: 运行全套测试，确认无回归**

Run: `bash tests/run_all.sh`
Expected: All tests passed

- [ ] **Step 9: 提交**

```bash
git add scripts/core/validate-scope.sh scripts/core/detect-language.sh tests/core/
git commit -m "feat(core): add language detection and scope boundary validation"
```

---

## Task 2（Phase 1）：前端项目识别 + 源码口径

**Goal:** 实现 `scripts/languages/frontend/detect-project.sh`、`scan-project.sh`、`collect-source-files.sh`，产出前端 PROFILE_SCHEMA v1。

**Files:**
- Create: `scripts/languages/frontend/detect-project.sh`
- Create: `scripts/languages/frontend/scan-project.sh`
- Create: `scripts/languages/frontend/collect-source-files.sh`
- Create: `tests/frontend/test_frontend_detect_project.sh`
- Create: `tests/frontend/test_frontend_scan_project.sh`
- Create: `tests/frontend/test_frontend_collect_source_files.sh`

**Interfaces:**
- Consumes: `PROJECT_DIR`
- Produces:
  - `detect-project.sh`：输出 `PROJECT_TYPE=frontend-react` 或 `PROJECT_TYPE=frontend-unsupported|reason=nextjs|nuxt|node-bff|generic-tsjs`
  - `scan-project.sh`：输出完整 PROFILE_SCHEMA v1（`PROFILE_SCHEMA_VERSION=1`、`LANGUAGE_ID=frontend`、`SOURCE_FILE_COUNT`、`SOURCE_LINE_COUNT`、`FORMAL_CONFIG_FILE_COUNT`、`CODE_INTELLIGENCE_*`、`COMPONENT:`、`TECH_STACK:`、`SOURCE_SCOPE:` 行）
  - `collect-source-files.sh`：输出不可变 source manifest（逐行绝对路径，仅生产 `.ts/.tsx/.js/.jsx`）

- [ ] **Step 1: 写失败测试 — detect-project（React 识别 + Next.js 拒绝）**

`tests/frontend/test_frontend_detect_project.sh`：

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-detect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mk_react_vite() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"},
 "devDependencies":{"vite":"^5.0.0","typescript":"^5.0.0"}}
JSON
  echo 'export default function App(){return <h1/>}' > "$d/src/App.tsx"
  cat > "$d/vite.config.ts" <<'TS'
import { defineConfig } from 'vite'; export default defineConfig({})
TS
}

mk_nextjs() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src/app"
  cat > "$d/package.json" <<'JSON'
{"name":"next","dependencies":{"next":"^14.0.0","react":"^18.2.0"}}
JSON
  echo 'export default function P(){return <div/>}' > "$d/src/app/page.tsx"
}

# React + Vite → frontend-react
mk_react_vite react_vite
grep -q "PROJECT_TYPE=frontend-react" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/react_vite")

# Next.js → 不支持
mk_nextjs nx
OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/nx")"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$OUT"
grep -q "reason=nextjs" <<< "$OUT"

echo "PASS: frontend detect-project"
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash tests/frontend/test_frontend_detect_project.sh` → Expected: FAIL

- [ ] **Step 3: 实现 detect-project.sh**

`scripts/languages/frontend/detect-project.sh`：

```bash
#!/bin/bash
set -euo piefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

PRUNE='\( -path */node_modules/* -o -path */dist/* -o -path */build/* -o -path */.git/* \) -prune'

# 收集所有候选 package.json（根 + maxdepth 3）
PKGS="$(eval "find '$PROJECT_DIR' $PRUNE -o -maxdepth 3 -name 'package.json' -type f -print" 2>/dev/null)"

has_dep_any_root() {
  local pat="$1"
  printf '%s\n' "$PKGS" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -Eq "\"$pat\"\s*:\s*\"[^\"]+" "$p" 2>/dev/null && exit 0
  done
}

reject=0; reason=""
if has_dep_any_root "next"; then reject=1; reason="nextjs"
elif has_dep_any_root "nuxt"; then reject=1; reason="nuxt"
elif grep -Eq '"express"\s*:\s*"' <<< "$PKGS" 2>/dev/null && printf '%s\n' "$PKGS" | xargs -I{} grep -El '"express"\s*:\s*"' {} 2>/dev/null | grep -q .; then
  # Node/BFF：无 react 入口时拒绝
  :
fi

# 不支持：next/nuxt
if printf '%s\n' "$PKGS" | xargs -I{} grep -El '"(next)"\s*:\s*"[^"]+' {} 2>/dev/null | grep -q .; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=nextjs"; exit 0
fi
if printf '%s\n' "$PKGS" | xargs -I{} grep -El '"(nuxt)"\s*:\s*"[^"]+' {} 2>/dev/null | grep -q .; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=nuxt"; exit 0
fi

# 需要 react 依赖 + tsx/jsx 入口证据
has_react=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if grep -Eq '"react"\s*:\s*"[^"]+' "$p" 2>/dev/null; then has_react=1; break; fi
done <<< "$PKGS"

if [ "$has_react" -eq 1 ] && eval "find '$PROJECT_DIR' $PRUNE -o \( -name '*.tsx' -o -name '*.jsx' \) -print -quit" 2>/dev/null | grep -q .; then
  echo "PROJECT_TYPE=frontend-react"; exit 0
fi

# 有 TS/JS 但无 React → 通用 TS/JS，首期不支持
if eval "find '$PROJECT_DIR' $PRUNE -o \( -name '*.ts' -o -name '*.js' \) -print -quit" 2>/dev/null | grep -q .; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=generic-tsjs"; exit 0
fi

echo "PROJECT_TYPE=frontend-unsupported|reason=no-frontend-evidence"
```

> 注：`xargs grep` 跨包检测 next/nuxt 以覆盖 monorepo；其余判断与 `detect-language.sh` 保持一致。

- [ ] **Step 4: 运行，确认通过**

Run: `bash tests/frontend/test_frontend_detect_project.sh` → Expected: PASS

- [ ] **Step 5: 写失败测试 — collect-source-files（生产源码口径 + 排除产物）**

`tests/frontend/test_frontend_collect_source_files.sh`：

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-collect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src/components" "$D/src/test" "$D/dist" "$D/node_modules"
echo 'export const A: number = 1;' > "$D/src/a.ts"
echo 'export function C(){return <div/>}' > "$D/src/components/C.tsx"
echo 'export const B = 2;' > "$D/src/b.js"
echo 'export const T = () => null;' > "$D/src/test/T.test.tsx"      # 测试，必须排除
echo 'minified' > "$D/dist/bundle.js"                                # 产物，必须排除
echo 'module.exports=1' > "$D/node_modules/x.js"                     # 依赖，必须排除

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D")"
grep -F "$D/src/a.ts" <<< "$OUT"
grep -F "$D/src/components/C.tsx" <<< "$OUT"
grep -F "$D/src/b.js" <<< "$OUT"
! grep -F "test/T.test.tsx" <<< "$OUT"
! grep -F "dist/bundle.js" <<< "$OUT"
! grep -F "node_modules/x.js" <<< "$OUT"

echo "PASS: frontend collect-source-files"
```

- [ ] **Step 6: 运行，确认失败**

Run: `bash tests/frontend/test_frontend_collect_source_files.sh` → Expected: FAIL

- [ ] **Step 7: 实现 collect-source-files.sh**

`scripts/languages/frontend/collect-source-files.sh`：

```bash
#!/bin/bash
set -euo piefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# 正式生产源码：src 下（及 detect-project 确认的应用源码目录）的 .ts/.tsx/.js/.jsx
# 排除：node_modules、dist、build、coverage、测试、生成代码、vendor、压缩
find "$PROJECT_DIR" \
  \( \
    -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \
    -o -path '*/.git/*' -o -path '*/.next/*' -o -path '*/.nuxt/*' \
  \) -prune -o \
  -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \
  -not -name '*.test.ts' -not -name '*.test.tsx' -not -name '*.test.js' -not -name '*.test.jsx' \
  -not -name '*.spec.ts' -not -name '*.spec.tsx' -not -name '*.spec.js' -not -name '*.spec.jsx' \
  -not -path '*/__tests__/*' -not -path '*/e2e/*' -not -path '*/cypress/*' \
  -not -name '*.min.js' -not -name '*.bundle.js' \
  -print 2>/dev/null | sort
```

- [ ] **Step 8: 运行，确认通过**

Run: `bash tests/frontend/test_frontend_collect_source_files.sh` → Expected: PASS

- [ ] **Step 9: 写失败测试 — scan-project（PROFILE_SCHEMA v1 完整字段）**

`tests/frontend/test_frontend_scan_project.sh`：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-scan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src/components"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0","react-router-dom":"^6.0.0"},
 "devDependencies":{"vite":"^5.0.0","typescript":"^5.0.0"}}
JSON
printf 'export const A: number = 1;\n' > "$D/src/a.ts"
printf 'export function C(){return <div/>}\n' > "$D/src/components/C.tsx"
cat > "$D/tsconfig.json" <<'JSON'
{"compilerOptions":{"strict":true}}
JSON
cat > "$D/vite.config.ts" <<'TS'
import { defineConfig } from 'vite'; export default defineConfig({})
TS

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"

# PROFILE_SCHEMA v1 必备字段
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$OUT"
grep -q "LANGUAGE_ID=frontend" <<< "$OUT"
grep -q "PROJECT_TYPE=frontend-react" <<< "$OUT"
grep -qE "^SOURCE_FILE_COUNT=2$" <<< "$OUT"
grep -qE "^SOURCE_LINE_COUNT=[1-9]" <<< "$OUT"
# 正式配置单独计数（package.json + tsconfig + vite.config = 3）
grep -qE "^FORMAL_CONFIG_FILE_COUNT=3$" <<< "$OUT"
# 技术栈行
grep -q "TECH_STACK:React" <<< "$OUT"
# source scope 声明
grep -q "SOURCE_SCOPE:formal|" <<< "$OUT"
grep -q "SOURCE_SCOPE:excluded|node_modules" <<< "$OUT"
# CODE_INTELLIGENCE 占位（detect-code-intelligence.sh 在 Task 4 接入；此处先输出 none 占位）
grep -q "CODE_INTELLIGENCE_PROVIDER=" <<< "$OUT"

echo "PASS: frontend scan-project"
```

- [ ] **Step 10: 运行，确认失败**

Run: `bash tests/frontend/test_frontend_scan_project.sh` → Expected: FAIL

- [ ] **Step 11: 实现 scan-project.sh**

`scripts/languages/frontend/scan-project.sh`：

```bash
#!/bin/bash
set -euo piefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PTYPE="$(bash "$SCRIPT_DIR/detect-project.sh" "$PROJECT_DIR" | sed -n 's/^PROJECT_TYPE=//p' | head -1)"

# 统计生产源码
MANIFEST="$(bash "$SCRIPT_DIR/collect-source-files.sh" "$PROJECT_DIR")"
FILE_COUNT="$(printf '%s\n' "$MANIFEST" | grep -c . || true)"
LINE_COUNT=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  LINE_COUNT=$((LINE_COUNT + $(wc -l < "$f" | tr -d ' ')))
done <<< "$MANIFEST"

# 正式配置文件计数（package.json/tsconfig/vite.config/webpack.config/路由配置）
CONFIG_COUNT="$(find "$PROJECT_DIR" -maxdepth 3 \
  \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune -o \
  -type f \( -name 'package.json' -o -name 'tsconfig.json' -o -name 'tsconfig.*.json' \
    -o -name 'vite.config.*' -o -name 'webpack.config.*' -o -name 'vite.config.ts' \) -print 2>/dev/null | grep -c . || true)"

# 组件维度（src 下顶层目录作为粗粒度 COMPONENT）
emit_components() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    local rel="${d#$PROJECT_DIR/}"
    local cnt=0 ln=0 f
    while IFS= read -r f; do [ -n "$f" ] || continue; cnt=$((cnt+1)); ln=$((ln + $(wc -l < "$f" | tr -d ' '))); done \
      < <(find "$d" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \
            -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' \
            -not -name '*.test.*' -not -name '*.spec.*' 2>/dev/null)
    [ "$cnt" -gt 0 ] && printf 'COMPONENT:%s|%s|%s|%s\n' "$(basename "$rel")" "$rel" "$cnt" "$ln"
  done < <(find "$PROJECT_DIR/src" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
}

# 输出 PROFILE_SCHEMA v1
echo "PROFILE_SCHEMA_VERSION=1"
echo "LANGUAGE_ID=frontend"
echo "PROJECT_TYPE=$PTYPE"
echo "SOURCE_FILE_COUNT=$FILE_COUNT"
echo "SOURCE_LINE_COUNT=$LINE_COUNT"
echo "FORMAL_CONFIG_FILE_COUNT=$CONFIG_COUNT"
# CODE_INTELLIGENCE 占位：detect-code-intelligence.sh 在 Task 4 接入后由主 skill 覆盖
echo "CODE_INTELLIGENCE_PROVIDER=none"
echo "CODE_INTELLIGENCE_AVAILABLE=false"
echo "CODE_INTELLIGENCE_REASON=typescript-lsp-detection-pending"

emit_components

# 技术栈（依赖证据）
if grep -Eq '"react"\s*:\s*"[^"]+' "$PROJECT_DIR/package.json" 2>/dev/null; then
  echo "TECH_STACK:React|dependency:react|rules:react"
fi
if grep -Eq '"react-router-dom"\s*:\s*"[^"]+' "$PROJECT_DIR/package.json" 2>/dev/null; then
  echo "TECH_STACK:React Router|dependency:react-router-dom|rules:react-router"
fi
if grep -Eq '"vite"\s*:\s*"[^"]+' "$PROJECT_DIR/package.json" 2>/dev/null; then
  echo "TECH_STACK:Vite|dependency:file:vite.config|rules:build-config"
elif grep -Eq '"webpack"\s*:\s*"[^"]+' "$PROJECT_DIR/package.json" 2>/dev/null; then
  echo "TECH_STACK:Webpack|dependency:file:webpack.config|rules:build-config"
fi

# 源码范围声明
echo "SOURCE_SCOPE:formal|src/**/*.ts"
echo "SOURCE_SCOPE:formal|src/**/*.tsx"
echo "SOURCE_SCOPE:formal|src/**/*.js"
echo "SOURCE_SCOPE:formal|src/**/*.jsx"
echo "SOURCE_SCOPE:context|**/*.test.tsx"
echo "SOURCE_SCOPE:context|**/*.d.ts"
echo "SOURCE_SCOPE:excluded|node_modules/**"
echo "SOURCE_SCOPE:excluded|dist/**"
echo "SOURCE_SCOPE:excluded|build/**"
```

- [ ] **Step 12: 运行，确认通过**

Run: `bash tests/frontend/test_frontend_scan_project.sh` → Expected: PASS

- [ ] **Step 13: 运行全套，确认无回归**

Run: `bash tests/run_all.sh`
Expected: All tests passed

- [ ] **Step 14: 提交**

```bash
git add scripts/languages/frontend/ tests/frontend/test_frontend_detect_project.sh \
        tests/frontend/test_frontend_scan_project.sh tests/frontend/test_frontend_collect_source_files.sh
git commit -m "feat(frontend): add project detection, source collection, and PROFILE_SCHEMA scan"
```

---

## Task 3（Phase 1）：通用批次规划与合并（语言中立）

**Goal:** 抽取语言中立的 `scripts/core/plan-file-batches.sh` 和 `merge-batch-results.sh`，供前端复用；Java 仍用原 `phase11-plan-file-batches.sh` / `phase12-merge-large-batches.sh`（冻结）。前端在 Task 7 接入。

**Files:**
- Create: `scripts/core/plan-file-batches.sh`
- Create: `scripts/core/merge-batch-results.sh`
- Create: `tests/core/test_core_plan_file_batches.sh`
- Create: `tests/core/test_core_merge_batch_results.sh`

**Interfaces:**
- Consumes: `PROJECT_DIR`、`REVIEW_MODE`、`BRANCH_NAME`、`LANGUAGE_ID`、`SOURCE_MANIFEST`（绝对路径清单，每行一个）、`CONTEXT_SCALE`（环境变量 `CC_REVIEW_CONTEXT_SCALE`）
- Produces:
  - `plan-file-batches.sh`：输出 `RUN_ID`/`RUN_DIR`/`BATCH_COUNT`/`TOTAL_SOURCE_FILE_COUNT`/`TOTAL_SOURCE_LOC`/`BATCH_FILE_LIST_DIR`，写 `plan.json`（`schema_version:1`、`language_id`、`strategy:"file-token-batching"`）与 `batches/batch-*.json`（`planned_source_loc`/`planned_source_file_count`/`batch_file_list`，**语言中立字段名**）
  - `merge-batch-results.sh`：与 `phase12` 同构，读 `plan.json` + `batches/batch-*.json` + `results/*.status.json`，产出 `summary.json`（含 `report_title`/`finding_count`/`source_file_coverage_percent`）与 `final/*.md`

- [ ] **Step 1: 写失败测试 — 通用文件批次规划**

`tests/core/test_core_plan_file_batches.sh`：

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-plan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
for i in 1 2 3 4 5; do
  { printf 'export const X%d: number = 0;\n' "$i"; seq 1 9000 | sed 's/.*/export const y& = 0;/'; } > "$D/src/m${i}.ts"
done

MANIFEST="$(mktemp)"
find "$D/src" -name '*.ts' -print | sort > "$MANIFEST"

OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-010000 \
       CC_REVIEW_CONTEXT_SCALE=1 \
       bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"

RUN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
grep -q "RUN_ID=" <<< "$OUT"
grep -q "BATCH_COUNT=" <<< "$OUT"
grep -q "TOTAL_SOURCE_FILE_COUNT=5" <<< "$OUT"
grep -q "TOTAL_SOURCE_LOC=" <<< "$OUT"
grep -q "BATCH_FILE_LIST_DIR=" <<< "$OUT"
grep -q '"language_id": "frontend"' "$RUN_DIR/plan.json"
grep -q '"strategy": "file-token-batching"' "$RUN_DIR/plan.json"
test -f "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_loc"' "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_file_count"' "$RUN_DIR/batches/batch-001.json"
grep -q '"batch_file_list"' "$RUN_DIR/batches/batch-001.json"

echo "PASS: core plan-file-batches"
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash tests/core/test_core_plan_file_batches.sh` → Expected: FAIL

- [ ] **Step 3: 实现 core/plan-file-batches.sh**

以 `scripts/phase11-plan-file-batches.sh` 为蓝本，关键差异：
1. 输入第 4 参数 `LANGUAGE_ID`、第 5 参数 `SOURCE_MANIFEST`（绝对路径清单）。
2. 不再 `find ... -path '*/src/main/java/*'`，改为从 `SOURCE_MANIFEST` 读取文件。
3. `risk_priority` 按语言中性化（前端：`*.tsx`/`*Controller*`/路由/`*Service*` 优先；可接收第 6 可选参数 `RISK_HINTS`，缺省用通用规则）。
4. JSON 字段名改为 `planned_source_loc`/`planned_source_file_count`/`total_source_loc`/`total_source_file_count`，并新增 `language_id`。

`scripts/core/plan-file-batches.sh`（核心实现）：

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
LANGUAGE_ID="${4:?请输入语言 ID}"
SOURCE_MANIFEST="${5:?请输入 source manifest 路径}"

CONTEXT_SCALE="${CC_REVIEW_CONTEXT_SCALE:-1}"
[ "$CONTEXT_SCALE" -lt 1 ] 2>/dev/null && CONTEXT_SCALE=1
[ "$CONTEXT_SCALE" -gt 10 ] && CONTEXT_SCALE=10

BATCH_TOKEN_BUDGET="${CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET:-$((100000 * CONTEXT_SCALE))}"
LINE_TOKEN_ESTIMATE=3
FILE_TOKEN_OVERHEAD=500

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
branch_slug() {
  local s; s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
  [ -n "$s" ] || s="no-branch"; printf '%s' "$s"
}
format_number() { local v="${1:-0}"; [ -n "$v" ] || v=0; perl -e 'my $n=shift; $n=0 if !defined($n)||$n eq ""; 1 while $n=~s/^(-?\d+)(\d{3})/$1,$2/; print $n' "$v"; }

# 语言中性的风险优先级：路由/页面/组件入口优先
risk_priority() {
  case "$1" in
    *route*|*Router*|*Page*|*App.tsx|*App.jsx|*index.tsx|*main.tsx) echo 0 ;;
    *Service*|*api*|*hook*|*Hook*|*store*|*Store*) echo 1 ;;
    *) echo 2 ;;
  esac
}

sum_field() { awk -F '\t' -v f="$2" '{s+=$f} END{print s+0}' "$1"; }

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
RUN_ID="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"
RUNS_ROOT="${CC_CODE_REVIEWER_RUNS_ROOT:-$PROJECT_DIR/.cc-code-reviewer/runs}"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
FILES_TSV="$RUN_DIR/source-files.tsv"; SORTED="$RUN_DIR/source-files.sorted.tsv"
DRAFT="$RUN_DIR/current-batch.tsv"; PLAN_ROWS="$RUN_DIR/batch-plan.tsv"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
: > "$FILES_TSV"; : > "$PLAN_ROWS"; : > "$DRAFT"

while IFS= read -r file; do
  [ -n "$file" ] || continue
  rel="${file#$PROJECT_DIR/}"
  loc="$(wc -l < "$file" | tr -d ' ')"
  cost=$((loc * LINE_TOKEN_ESTIMATE + FILE_TOKEN_OVERHEAD))
  printf '%s\t%s\t%s\t%s\n' "$(risk_priority "${file##*/}")" "$cost" "$loc" "$file" >> "$FILES_TSV"
done < "$SOURCE_MANIFEST"

[ -s "$FILES_TSV" ] || { echo "NO_SOURCE_FILES=$PROJECT_DIR" >&2; exit 1; }

sort -t "$(printf '\t')" -k1,1n -k2,2rn "$FILES_TSV" > "$SORTED"
TOTAL_LOC="$(sum_field "$FILES_TSV" 3)"
TOTAL_FILES="$(awk 'END{print NR+0}' "$FILES_TSV")"

BATCH_COUNT=0; CUR_COST=0
flush_batch() {
  [ -s "$DRAFT" ] || return 0
  BATCH_COUNT=$((BATCH_COUNT+1))
  local id; id="$(printf 'batch-%03d' "$BATCH_COUNT")"
  local bf="$RUN_DIR/batches/$id.files"; local bj="$RUN_DIR/batches/$id.json"
  local loc files cost
  loc="$(sum_field "$DRAFT" 3)"; files="$(awk 'END{print NR+0}' "$DRAFT")"; cost="$(sum_field "$DRAFT" 2)"
  awk -F '\t' '{print $4}' "$DRAFT" > "$bf"
  cat > "$bj.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$id",
  "strategy": "file-token-batching",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "planned_source_loc": $loc,
  "planned_source_file_count": $files,
  "planned_review_cost": $cost,
  "batch_file_list": "$(json_escape "$bf")"
}
JSON
  mv "$bj.tmp" "$bj"
  printf '%s\t%s\t%s\t%s\n' "$id" "$loc" "$files" "$cost" >> "$PLAN_ROWS"
  : > "$DRAFT"
}

while IFS="$(printf '\t')" read -r pri cost loc file; do
  [ -n "$file" ] || continue
  if [ "$CUR_COST" -gt 0 ] && [ $((CUR_COST + cost)) -gt "$BATCH_TOKEN_BUDGET" ]; then
    flush_batch "$DRAFT"; CUR_COST=0
  fi
  printf '%s\t%s\t%s\t%s\n' "$pri" "$cost" "$loc" "$file" >> "$DRAFT"
  CUR_COST=$((CUR_COST + cost))
done < "$SORTED"
flush_batch "$DRAFT"

CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RUN_DIR/plan.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "project_name": "$(json_escape "$PROJECT_NAME")",
  "project_dir": "$(json_escape "$PROJECT_DIR")",
  "review_mode": "$(json_escape "$REVIEW_MODE")",
  "branch": "$(json_escape "$BRANCH_NAME")",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "strategy": "file-token-batching",
  "total_source_loc": $TOTAL_LOC,
  "total_source_file_count": $TOTAL_FILES,
  "batch_count": $BATCH_COUNT,
  "budget": { "batch_token_budget": $BATCH_TOKEN_BUDGET, "line_token_estimate": $LINE_TOKEN_ESTIMATE, "file_token_overhead": $FILE_TOKEN_OVERHEAD },
  "created_at": "$CREATED"
}
JSON
mv "$RUN_DIR/plan.json.tmp" "$RUN_DIR/plan.json"

echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_SOURCE_LOC=$TOTAL_LOC"
echo "TOTAL_SOURCE_FILE_COUNT=$TOTAL_FILES"
echo "BATCH_FILE_LIST_DIR=$RUN_DIR/batches"
```

- [ ] **Step 4: 运行，确认通过**

Run: `bash tests/core/test_core_plan_file_batches.sh` → Expected: PASS

- [ ] **Step 5: 写失败测试 — 通用合并**

`tests/core/test_core_merge_batch_results.sh`（结构同 `test_phase12_merge_large_batches.sh`，断言中性字段 `source_file_coverage_percent`/`report_title`/完整 vs 阶段性判断）：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-merge.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run"; mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
cat > "$RUN_DIR/plan.json" <<'JSON'
{"schema_version":1,"run_id":"r1","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b"}]}
JSON
cat > "$RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/batch-001.md","finding_count":1}
JSON
cat > "$RUN_DIR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度4-状态与数据请求] 示例
- 文件：src/a/x.tsx:10
- 证据：示例
- 建议：示例
MD

# batch-002 未完成 → 合并阻塞
MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
        bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" 2>&1 || true)"
grep -q "MERGE_BLOCKED=true" <<< "$MOUT"

# 仅 batch-001（未纳入 batch-002）→ 阶段性报告标题
MOUT2="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" || true)"
SUMM="$(printf '%s\n' "$MOUT2" | sed -n 's/^SUMMARY_PATH=//p')"
grep -q '"source_file_coverage_percent"' "$SUMM"
grep -q '"report_title"' "$SUMM"
grep -q '"finding_count": 1' "$SUMM"
REPORT="$(printf '%s\n' "$MOUT2" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT" | grep -q '\[阶段性\]'

echo "PASS: core merge-batch-results"
```

- [ ] **Step 6: 运行，确认失败**

Run: `bash tests/core/test_core_merge_batch_results.sh` → Expected: FAIL

- [ ] **Step 7: 实现 core/merge-batch-results.sh**

以 `scripts/phase12-merge-large-batches.sh` 为蓝本，关键差异：
1. 读 `total_source_loc`/`total_source_file_count`（而非 `total_java_*`）。
2. 输出字段名 `covered_source_loc`/`source_file_coverage_percent`。
3. 报告覆盖率文案改为「前端源码文件覆盖率」（参数化：从 `plan.json.language_id` 决定展示名，frontend→「前端源码」，java→「Java 文件」）。
4. 保留 `report_title`/`[阶段性]`/`[合并阻塞]`/确定性去重/`RUN_BATCH_IDS` 门禁逻辑。

由于实现较长，逐行复制 `phase12` 并做以下替换（标注每处改动）：
- L186-187：`TOTAL_JAVA_LOC`/`TOTAL_JAVA_FILE_COUNT` → 读 `total_source_loc`/`total_source_file_count`
- L467-471：`covered_java_loc`/`java_file_coverage_percent` → `covered_source_loc`/`source_file_coverage_percent`
- L493/515/558：覆盖率文案 `Java 文件覆盖率` → 根据 `LANGUAGE_ID` 选择展示名（`frontend`→`前端源码文件覆盖率`，否则→`Java 文件覆盖率`）
- 其余（`dedupe_issue_blocks`/`RUN_BATCH_IDS`/等待门禁/`[合并阻塞]`/`[阶段性]`/`summary.json.report_title`）原样保留

`LANGUAGE_ID` 解析：

```bash
LANGUAGE_ID="$(json_get "$PLAN_PATH" language_id)"
[ -n "$LANGUAGE_ID" ] || LANGUAGE_ID="java"
case "$LANGUAGE_ID" in
  frontend) COVERAGE_LABEL="前端源码文件覆盖率" ;;
  *) COVERAGE_LABEL="Java 文件覆盖率" ;;
esac
```

> 工程师执行此步时：完整复制 `phase12-merge-large-batches.sh` 内容到 `scripts/core/merge-batch-results.sh`，然后按上述 4 处做替换；不得遗漏 `summary.json` 的 `report_title` 字段。

- [ ] **Step 8: 运行，确认通过**

Run: `bash tests/core/test_core_merge_batch_results.sh` → Expected: PASS

- [ ] **Step 9: 运行全套，确认无回归**

Run: `bash tests/run_all.sh`
Expected: All tests passed

- [ ] **Step 10: 提交**

```bash
git add scripts/core/plan-file-batches.sh scripts/core/merge-batch-results.sh \
        tests/core/test_core_plan_file_batches.sh tests/core/test_core_merge_batch_results.sh
git commit -m "feat(core): add language-neutral file batch planner and merge gate"
```

---

## Task 4（Phase 1）：TypeScript LSP 探测与降级

**Goal:** 实现 `scripts/languages/frontend/detect-code-intelligence.sh`，对标 `phase10` 的 jdtls 探测，输出 `CODE_INTELLIGENCE_PROVIDER=typescript-lsp|none` 与降级原因。

**Files:**
- Create: `scripts/languages/frontend/detect-code-intelligence.sh`
- Create: `tests/frontend/test_frontend_detect_code_intelligence.sh`

**Interfaces:**
- Consumes: `PROJECT_DIR`
- Produces: `CODE_INTELLIGENCE_AVAILABLE`/`CODE_INTELLIGENCE_LANGUAGE=frontend`/`CODE_INTELLIGENCE_PROVIDER`/`CODE_INTELLIGENCE_REASON`/`CODE_INTELLIGENCE_INSTALL_HINT`

- [ ] **Step 1: 写失败测试**

`tests/frontend/test_frontend_detect_code_intelligence.sh`：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-lsp.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.0.0"}}
JSON
echo 'export const A: number = 1;' > "$D/src/a.ts"

OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-code-intelligence.sh "$D")"
grep -q "CODE_INTELLIGENCE_LANGUAGE=frontend" <<< "$OUT"
grep -qE "^CODE_INTELLIGENCE_PROVIDER=(typescript-lsp|none)$" <<< "$OUT"
# 不可用时必须有 reason 与 install hint
grep -q "CODE_INTELLIGENCE_REASON=" <<< "$OUT"
grep -q "CODE_INTELLIGENCE_INSTALL_HINT=" <<< "$OUT"
# provider=none 时 AVAILABLE 必须为 false
if grep -q "^CODE_INTELLIGENCE_PROVIDER=none$" <<< "$OUT"; then
  grep -q "^CODE_INTELLIGENCE_AVAILABLE=false$" <<< "$OUT"
fi

echo "PASS: frontend detect-code-intelligence"
```

- [ ] **Step 2: 运行，确认失败**

Run: `bash tests/frontend/test_frontend_detect_code_intelligence.sh` → Expected: FAIL（注意：修正测试文件中的命令替换引号错误——`detect-code-intelligence.sh "$D"` 应为 `detect-code-intelligence.sh" "$D"` 的笔误，实现前先按 Step 3 正确脚本运行）

> 修正：Step 1 测试中 `detect-code-intelligence.sh "$D"` 引号闭合无误；保持原样即可。

- [ ] **Step 3: 实现 detect-code-intelligence.sh**

`scripts/languages/frontend/detect-code-intelligence.sh`：

```bash
#!/bin/bash
set -euo piefail
PROJECT_DIR="${1:?请输入项目路径}"

emit() {
  echo "CODE_INTELLIGENCE_AVAILABLE=false"
  echo "CODE_INTELLIGENCE_LANGUAGE=frontend"
  echo "CODE_INTELLIGENCE_PROVIDER=none"
  echo "CODE_INTELLIGENCE_REASON=$1"
  echo "CODE_INTELLIGENCE_INSTALL_HINT=建议启用 TypeScript LSP（如 typescript-language-server）以获得定义/引用/调用链语义增强；不可用时回退 import graph + 配置 + 文本检索静态分析"
}

[ -d "$PROJECT_DIR" ] || { emit "项目路径不存在"; exit 0; }

# TypeScript LSP 检测：typescript-language-server 或本地 node_modules/.bin/tsserver
TS_LSP=""
if command -v typescript-language-server >/dev/null 2>&1; then
  TS_LSP="typescript-language-server"
elif [ -x "$PROJECT_DIR/node_modules/.bin/tsserver" ]; then
  TS_LSP="node_modules/.bin/tsserver"
fi

if [ -n "$TS_LSP" ]; then
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=frontend"
  echo "CODE_INTELLIGENCE_PROVIDER=typescript-lsp"
  echo "CODE_INTELLIGENCE_COMMAND=$TS_LSP"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,implementations,diagnostics"
else
  emit "未检测到 typescript-language-server 或本地 tsserver"
fi
```

- [ ] **Step 4: 运行，确认通过**

Run: `bash tests/frontend/test_frontend_detect_code_intelligence.sh` → Expected: PASS（CI 环境无 tsserver 时走 none 分支，测试已兼容）

- [ ] **Step 5: 运行全套**

Run: `bash tests/run_all.sh` → Expected: All tests passed

- [ ] **Step 6: 提交**

```bash
git add scripts/languages/frontend/detect-code-intelligence.sh \
        tests/frontend/test_frontend_detect_code_intelligence.sh
git commit -m "feat(frontend): add TypeScript LSP detection with static fallback"
```

---

## Task 5（Phase 2）：前端审查矩阵 + React 规则 + source-scope

**Goal:** 定义前端审查维度、模式 × 维度矩阵、React MVP 专项规则与源码范围口径（references）。

**Files:**
- Create: `references/shared-review-framework.md`
- Create: `references/languages/frontend/source-scope.md`
- Create: `references/languages/frontend/review-framework.md`
- Create: `references/languages/frontend/react-rules.md`
- Modify: `references/language-adapter-contract.md`（补全 PROFILE_SCHEMA v1 完整定义）

- [ ] **Step 1: 写 shared-review-framework.md（15 维度公共 ID）**

`references/shared-review-framework.md`：

```markdown
# Shared Review Framework（公共维度定义）

公共层定义 15 个稳定维度 ID，语言适配器负责映射为语言专属展示名称。

| 公共 ID | 名称（中性） | Java 展示名 | 前端展示名 |
|---|---|---|---|
| D01_CORRECTNESS | 正确性 | 正确性 | 正确性 |
| D02_MAINTAINABILITY | 代码质量 | 代码质量 | 代码质量 |
| D03_PLATFORM_PRACTICES | 平台规范 | Spring Boot 规范 | React Hooks/渲染/组件规范 |
| D04_DATA_STATE | 数据与状态 | 数据库与数据访问 | 状态管理与数据请求 |
| D05_SECURITY | 安全 | 安全 | 安全 |
| D06_PERFORMANCE | 性能 | 性能 | 性能 |
| D07_RESOURCE_LIFECYCLE | 资源生命周期 | 资源管理 | 副作用与资源清理 |
| D08_OBSERVABILITY | 可观测性 | 日志/可观测性 | 错误监控与可观测性 |
| D09_TESTING | 测试质量 | 测试质量 | 测试质量 |
| D10_TECH_DEBT | 技术债 | 技术债 | 技术债 |
| D11_ARCHITECTURE | 架构 | 架构 | 组件边界与架构 |
| D12_DISTRIBUTED_INTEGRATION | 分布式集成 | 分布式系统 | 跨端集成（首期弱化） |
| D13_ASYNC_EVENTS | 异步事件 | 消息队列 | 异步与事件 |
| D14_CACHE_CONSISTENCY | 缓存一致性 | 缓存 | 客户端缓存一致性 |
| D15_INTERFACE_CONTRACT | 接口契约 | API 设计 | 接口/类型契约 |

**规则**：公共 ID 用于内核、Ignore、合并与未来扩展；Java 报告继续使用原有用户可见名称。语言适配器的具体规则与模式矩阵定义在各自 `languages/<id>/review-framework.md`。
```

- [ ] **Step 2: 写前端 source-scope.md**

`references/languages/frontend/source-scope.md`（落地 spec 第 7 节）：

```markdown
# 前端正式审查范围

## 正式问题范围（formal）
- `src` 及适配器确认的应用源码目录内的 `.ts`、`.tsx`、`.js`、`.jsx`
- React 组件、Hooks、状态管理、路由和数据请求代码
- 正式配置文件（`package.json`、`tsconfig.json`、`vite.config.*`、`webpack.config.*`、路由配置）：可产生问题，但单独计入 `FORMAL_CONFIG_FILE_COUNT`，不进入源码覆盖率分母

## 只读上下文（context）
- 单元/组件/E2E 测试：只用于判断核心逻辑或关键路径是否缺少测试，不输出正式问题，不计入正式覆盖率
- 类型声明文件 `.d.ts`
- lockfile：仅作依赖版本证据
- 生成代码：仅在理解调用关系确有必要时读取

## 默认排除（excluded）
- `node_modules`、`dist`、`build`、`coverage`、`.next`、`.nuxt`
- 压缩（`.min.js`）、bundle（`.bundle.js`）、vendor、自动生成文件
- 经 Ignore 或适配器确认的生成目录

**覆盖率口径**：报告只展示一个「前端源码文件覆盖率」，分母为生产 `.ts/.tsx/.js/.jsx` 文件数。
```

- [ ] **Step 3: 写前端 review-framework.md（模式 × 维度矩阵）**

`references/languages/frontend/review-framework.md`（前端矩阵；与 Java 矩阵结构对齐，便于复用合并/报告逻辑）：

```markdown
# 前端代码审查框架

## 审查模式 × 维度覆盖矩阵

| 维度编号 | 维度名称 | fast | standard | deep | security |
|---|---|:---:|:---:|:---:|:---:|
| 1 | 正确性 | ✅ | ✅ | ✅ | ✅ |
| 2 | 代码质量 | — | ✅ | ✅ | — |
| 3 | React Hooks/渲染/组件规范 | ✅ 仅 Hooks 依赖+配置安全 | ✅ | ✅ | ✅ 仅配置安全子项 |
| 4 | 状态管理与数据请求 | — | ✅ | ✅ | ✅ 仅注入/越权子项 |
| 5 | 安全 | ✅ 仅 P0 级 | ✅ | ✅ | ✅ 全深度 |
| 6 | 性能 | — | ✅ | ✅ | — |
| 7 | 副作用与资源清理 | ✅ | ✅ | ✅ | — |
| 8 | 错误监控与可观测性 | — | ✅ | ✅ | ✅ 仅敏感信息泄露 |
| 9 | 测试质量 | — | ✅ 仅核心测试缺失 | ✅ | — |
| 10 | 技术债 | — | ✅ | ✅ | — |
| 11 | 组件边界与架构 | — | ✅ | ✅ | — |
| 12 | 跨端集成 | — | — | ✅ | ✅ 仅认证/幂等 |
| 13 | 异步与事件 | — | — | ✅ | — |
| 14 | 客户端缓存一致性 | — | ✅ 仅缓存基础 | ✅ | — |
| 15 | 接口/类型契约 | — | ✅ 仅 RESTful+错误处理 | ✅ | ✅ 仅鉴权/错误信息 |

## 模式说明
- **fast**：仅 P0 硬门槛问题，聚焦正确性、Hooks 依赖/配置安全、资源清理、P0 安全（XSS/危险 HTML/凭据/开放重定向）。
- **standard**：日常迭代，覆盖核心维度 + 接口契约 + 缓存基础 + 核心测试缺失。
- **deep**：全量 15 维度，含测试质量与技术债深挖。
- **security**：聚焦安全核心与强相关交叉维度。

## P0 分级门槛
复用 Java 的「P0 五项硬门槛」：生产可达、证据完整、事故级影响、缺少有效防护、阻断发布。fast 模式只输出 P0。

*版本：前端 1.0*
```

- [ ] **Step 4: 写 react-rules.md（React MVP 专项规则）**

`references/languages/frontend/react-rules.md`（落地 spec 第 9 节）：

```markdown
# React MVP 审查规则

## D01 正确性
- Hooks 依赖数组遗漏/多余导致陈旧闭包
- 异步竞态：effect 中未取消的请求、Promise 未处理
- 空值/类型逃逸边界（`as any`、非空断言滥用）

## D03 React 规范
- useEffect 依赖正确性与清理函数（订阅/timer/listener 必须清理）
- 避免不必要重渲染（缺失 memo、内联对象/函数 props）
- Hooks 规则（不在条件/循环调用）
- key 使用（列表用 index 作 key 的风险）

## D04 状态与数据请求
- 状态归属（局部 vs 提升 vs 全局）
- 数据请求的 loading/error 状态处理
- 缓存失效与 SWR/React Query 误用

## D05 安全
- XSS：dangerouslySetInnerHTML、用户输入直接渲染
- 前端凭据（token 写入 localStorage/public 代码）
- 开放重定向、不安全 URL 拼接

## D06 性能
- Bundle 体积、懒加载缺失、列表虚拟化
- 不必要重计算（缺 useMemo/useCallback 或滥用）

## D07 副作用与资源清理
- Event listener、timer、订阅、请求未在 unmount 清理

## D08 可观测性
- Error Boundary 覆盖关键路由
- 关键错误上报与用户可恢复错误

## D11 组件边界
- 循环依赖、跨层引用、公共组件滥用

## 可访问性（并入相关维度）
- 表单标签、键盘操作、语义化结构

## 依赖风险结论规则
- 仅当 lockfile 版本明确且证据可靠时才下确定性漏洞结论；否则归为待确认或依赖扫描建议。
```

- [ ] **Step 5: 补全 language-adapter-contract.md（PROFILE_SCHEMA v1）**

在 `references/language-adapter-contract.md` 末尾「Phase 1 将补充」段替换为完整定义：

```markdown
## PROFILE_SCHEMA v1（标准预扫描输出协议）

适配器预扫描必须输出版本化的 key=value，第一版至少包含：

\`\`\`text
PROFILE_SCHEMA_VERSION=1
LANGUAGE_ID=frontend
PROJECT_TYPE=frontend-react
SOURCE_FILE_COUNT=318
SOURCE_LINE_COUNT=42680
FORMAL_CONFIG_FILE_COUNT=7
CODE_INTELLIGENCE_PROVIDER=typescript-lsp
CODE_INTELLIGENCE_AVAILABLE=true

COMPONENT:app|src/app|126|18200
TECH_STACK:React|dependency:react@19|rules:react
SOURCE_SCOPE:formal|src/**/*.tsx
SOURCE_SCOPE:context|**/*.test.tsx
SOURCE_SCOPE:excluded|node_modules/**
\`\`\`

### 处理规则
- `PROFILE_SCHEMA_VERSION` 不匹配时**必须停止**，不得猜测解析。
- `LANGUAGE_ID` 在一次运行中不可变。
- `SOURCE_FILE_COUNT` 只统计生产源码，且必须与覆盖率分母来自同一份不可变 source manifest。
- `FORMAL_CONFIG_FILE_COUNT` 单独记录可产生正式问题的配置文件，不进入源码覆盖率分母。
- 公共层使用 `source_file_count` 等中性概念；Java 兼容输出可暂时保留 `selected_java_file_count` 别名（Phase 4 迁移后废弃）。
- `COMPONENT`/`TECH_STACK`/`SOURCE_SCOPE` 可重复出现；公共层只负责保存和展示，不解释框架语义。
- 混合仓库：用户选择语言后，另一语言只能作仓库背景，不得成为正式问题来源。

## 适配器职责
1. 识别项目类型、框架、构建器、包管理器、workspace
2. 定义正式源码、只读上下文、排除项、生成代码
3. 统计组件/文件/行数/批次成本
4. 探测语言语义工具并定义可靠静态降级路径
5. 提供语言审查维度、框架专项规则、Agent
6. 将语言专属数据映射到公共协议
```

- [ ] **Step 6: 运行全套测试（含 contract_docs 若已引用新文件则更新断言）**

Run: `bash tests/run_all.sh` → Expected: All tests passed（若 `test_contract_docs.sh` 因新增文件失败，在 Task 8 的文档同步任务中统一修复；此处若失败先记录但不阻断——这些是纯文档，不破坏脚本契约）

> 若 `test_contract_docs.sh` 立即失败，本步允许先 `git stash` 该测试的失败，留待 Task 8 修复；但不得删除测试断言。

- [ ] **Step 7: 提交**

```bash
git add references/shared-review-framework.md references/language-adapter-contract.md \
        references/languages/
git commit -m "docs(frontend): add shared dimensions, frontend review matrix, React rules, source scope"
```

---

## Task 6（Phase 2）：前端 Agent

**Goal:** 实现 `agents/cc-code-reviewer-frontend.md`，消费注入参数（PROFILE 行、source manifest、SEMANTIC_LEVEL），按前端矩阵执行，产出发现清单或完整报告。

**Files:**
- Create: `agents/cc-code-reviewer-frontend.md`

**Interfaces:**
- Consumes: 主 skill 注入的参数表（含 `LANGUAGE_ID=frontend`、`PROJECT_TYPE`、`SEMANTIC_LEVEL`、`REVIEW_FRAMEWORK_PATH` 指向 `references/languages/frontend/review-framework.md`、`REACT_RULES_PATH` 指向 `references/languages/frontend/react-rules.md`、`SOURCE_SCOPE_PATH` 指向 `references/languages/frontend/source-scope.md`、source manifest 路径、批次参数）
- Produces: 发现清单（`REVIEW_OUTPUT_MODE=仅发现清单`）或完整报告（`完整报告`）；批次模式下写入 `BATCH_RESULT_PATH` + `BATCH_STATUS_PATH`

- [ ] **Step 1: 写前端 Agent（以 Java Agent 为蓝本，关键差异）**

`agents/cc-code-reviewer-frontend.md`：以前端专家视角，保留 Java Agent 的结构（审查原则、外部参数注入、执行流程阶段 A-D、发现归类、证据规范、ignore 应用、报告生成、覆盖率追踪、批次发现清单格式），关键替换：

```markdown
---
name: cc-code-reviewer-frontend
description: 执行前端（React/TS/JS）代码审查的专属子代理，按维度逐文件评估，生成结构化报告
model: sonnet
effort: high
maxTurns: 50
---
你是一位拥有 15+ 年经验的资深前端架构师，精通 React、TypeScript、现代前端工程化与 Web 安全。

## 审查原则
（同 Java Agent 的 7 条原则；增加：）
- **正式范围约束**：正式问题只位于 SOURCE_SCOPE:formal 范围内的生产源码；测试、生成代码、node_modules、dist/build 产物不得成为正式问题位置，也不计入正式覆盖率。
- **依赖风险结论规则**：仅当 lockfile 版本明确且证据可靠时才下确定性漏洞结论；否则归为待确认。

## 外部参数注入
参数表新增字段（其余与 Java Agent 一致）：
| 参数 | 值 |
|------|-----|
| 语言 ID | frontend |
| 前端审查框架路径 | {references/languages/frontend/review-framework.md 绝对路径} |
| React 规则路径 | {references/languages/frontend/react-rules.md 绝对路径} |
| 源码范围路径 | {references/languages/frontend/source-scope.md 绝对路径} |
| source manifest | {不可变源码清单绝对路径} |

参考文件读取：必须先读取 `REVIEW_FRAMEWORK_PATH`（前端矩阵）、`REACT_RULES_PATH`、`SOURCE_SCOPE_PATH`、`REPORT_FORMAT_PATH`；任一缺失立即停止并返回失败路径。

## 执行流程
- 阶段 A：从 source manifest（或 BATCH_PLAN_PATH 的 scan_roots + 生产源码口径）确定文件集合；禁止重新 find 统计
- 阶段 B：风险排序（路由/页面/App 入口 > Service/api/hook/store > 其余）
- 阶段 C：逐文件单次读取 + 按前端矩阵多维度评估
- 阶段 D：定向补充（import graph、配置引用、跨文件聚合）

## 语义增强
- SEMANTIC_LEVEL=typescript-lsp 时必须用 TS LSP 查询 definition/references/implementations/diagnostics 理解调用链，并在结果披露使用情况
- 不可用或运行中失败时回退 import graph + 配置 + 文本检索，记录降级

## 副作用/资源清理专项（D07）
- useEffect/useLayoutEffect 的清理函数：订阅、timer、listener、请求取消、AbortController
- 未清理导致内存泄漏或陈旧状态更新

## 文件类型 × 维度快速参考表
| 文件类型 | 必检维度 | 条件启用 |
|---|---|---|
| 组件（.tsx/.jsx） | 1,3,5,6,7,11 | 4(状态),8 |
| Hook（use*） | 1,3,6,7 | 4 |
| store/状态管理 | 1,4,6,11 | 14(缓存) |
| api/请求层 | 1,4,5,6,15 | 8 |
| 路由 | 1,3,5,11 | — |
| 配置（tsconfig/vite/webpack） | 3,5,6,10 | — |
| 测试文件 | 9 | 1(测试正确性) |

## 报告输出
复用 REPORT_FORMAT_PATH；覆盖率口径为「前端源码文件覆盖率」，分母为 source manifest 生产文件数。

## 批次发现清单格式
（同 Java Agent 的 Batch 发现清单格式；位置示例改为 `src/components/C.tsx:10`）
```

- [ ] **Step 2: 验证 Agent 文件可被引用（语法自检）**

Run: `test -f agents/cc-code-reviewer-frontend.md && head -5 agents/cc-code-reviewer-frontend.md`
Expected: 显示 frontmatter，含 `name: cc-code-reviewer-frontend`

- [ ] **Step 3: 运行全套（无脚本逻辑变更，应通过）**

Run: `bash tests/run_all.sh` → Expected: All tests passed

- [ ] **Step 4: 提交**

```bash
git add agents/cc-code-reviewer-frontend.md
git commit -m "feat(frontend): add frontend review sub-agent"
```

---

## Task 7（Phase 2）：主 SKILL 路由分支 + 前端预扫描接入

**Goal:** 在 `skills/cc-code-reviewer/SKILL.md` 预扫描后增加语言探测与路由：纯前端直接走前端流程；混合仓库让用户选一种语言；Java 走原流程不变。

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`（第三步后插入语言探测；新增「前端审查流程」分支章节）
- Create: `tests/frontend/test_frontend_route_react.sh`（契约测试：纯 React → 走前端脚本）

**Interfaces:**
- Consumes: `scripts/core/detect-language.sh`、`scripts/languages/frontend/*.sh`、`scripts/core/*.sh`
- Produces: `LANGUAGE_ID`（java|frontend）、前端分支调用 `scan-project.sh` + `detect-code-intelligence.sh`，复用交互/分批/合并/报告

- [ ] **Step 1: 写失败测试 — 路由契约**

`tests/frontend/test_frontend_route_react.sh`（断言：纯 React 项目下，detect-language 报 frontend，前端 scan-project 可独立产出 PROFILE，且 Java phase3 不被调用）：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/react"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
echo 'export default function App(){return <div/>}' > "$D/src/App.tsx"

# 1. detect-language 报 frontend 不报 java
LOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$LOUT"
! grep -q "CANDIDATE_LANGUAGE:java" <<< "$LOUT"

# 2. 前端 scan-project 产出 PROFILE_SCHEMA v1
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$SOUT"
grep -q "LANGUAGE_ID=frontend" <<< "$SOUT"
grep -q "PROJECT_TYPE=frontend-react" <<< "$SOUT"

# 3. 混合仓库两者都报
JDIR="$TMP_DIR/mixed"; mkdir -p "$JDIR/src/main/java/com/x" "$JDIR/fe/src"
cat > "$JDIR/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion><groupId>com.x</groupId><artifactId>j</artifactId><version>1</version></project>
XML
echo 'package com.x; public class A {}' > "$JDIR/src/main/java/com/x/A.java"
cat > "$JDIR/fe/package.json" <<'JSON'
{"name":"fe","dependencies":{"react":"^18.0.0"}}
JSON
echo 'export const P=()=><div/>' > "$JDIR/fe/src/P.tsx"
MOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$JDIR")"
grep -q "CANDIDATE_LANGUAGE:java" <<< "$MOUT"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$MOUT"

echo "PASS: frontend route react"
```

- [ ] **Step 2: 运行，确认通过（路由脚本已在 Task 1/2 实现；此测试锁定集成契约）**

Run: `bash tests/frontend/test_frontend_route_react.sh` → Expected: PASS（脚本已就绪；本测试是集成回归门禁）

- [ ] **Step 3: 修改 SKILL.md — 第三步后插入语言探测**

在 `skills/cc-code-reviewer/SKILL.md` 的「第三步」预扫描块之后、「第三步之后：读取项目级 ignore 规则」之前，插入：

```markdown
### 第三步之后：语言探测与路由

预扫描脚本执行前，先识别候选语言：

\`\`\`bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-language.sh" "$PROJECT_DIR"
# 输出：CANDIDATE_LANGUAGE:java|evidence=... 和/或 CANDIDATE_LANGUAGE:frontend|evidence=... 或 CANDIDATE_LANGUAGE:none
\`\`\`

**路由规则**：
- **纯 Java**（仅 `CANDIDATE_LANGUAGE:java`）：走现有 Java 预扫描（phase1/2/3/10/4），流程不变。
- **纯前端**（仅 `CANDIDATE_LANGUAGE:frontend`）：走「前端预扫描」分支。
- **混合仓库**（两者皆有）：**必须调用 AskUserQuestion** 让用户选择一种语言：
  - question: "检测到多语言仓库（Java + 前端），本次审查目标语言？"
  - header: "审查语言"
  - options:
    - label: "Java"
      description: "审查 Java 生产源码（src/main/java），使用 Java 审查矩阵"
    - label: "前端（React/TS/JS）"
      description: "审查前端生产源码（src 下 .ts/.tsx/.js/.jsx），使用前端审查矩阵"
  - multiSelect: false
  - 用户选择后设 `LANGUAGE_ID`，另一语言仅作仓库背景，不得产出正式问题。
- **none**：输出"❌ 未识别到支持的审查目标（Java 或 React/TS/JS）"并终止。

**前端预扫描分支**（`LANGUAGE_ID=frontend` 时执行，替代 phase3/phase10）：

\`\`\`bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/detect-project.sh" "$PROJECT_DIR"
# 不支持（nextjs/nuxt/generic-tsjs）时停止，不套用 React 规则

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/scan-project.sh" "$PROJECT_DIR"
# 输出 PROFILE_SCHEMA v1：SOURCE_FILE_COUNT/SOURCE_LINE_COUNT/FORMAL_CONFIG_FILE_COUNT/COMPONENT/TECH_STACK/SOURCE_SCOPE

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出 CODE_INTELLIGENCE_PROVIDER=typescript-lsp|none（覆盖 scan-project 的占位）

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase4-detect-lark-plugin.sh"
# 复用 lark-cli 检测
\`\`\`

> 前端分支下，后续交互步骤（模式/报告/入口/范围/确认）、增量预处理（phase5）、模型侦测（phase14）、分批、合并、报告保存、飞书输出**全部复用现有流程**；差异仅在：预扫描数据来自前端 PROFILE，分批用 `scripts/core/plan-file-batches.sh` + source manifest，合并用 `scripts/core/merge-batch-results.sh`，子 agent 用 `cc-code-reviewer-frontend`。
```

- [ ] **Step 4: 修改 SKILL.md — 前端分支的分批与合并说明**

在「分批计算」章节末尾追加前端专用段：

```markdown
### 前端分批（LANGUAGE_ID=frontend）

前端项目（含 React monorepo 单语言运行）必须使用 `scripts/core/plan-file-batches.sh`（语言中立），不得使用 Java 的 `phase11-plan-file-batches.sh` 或 `phase11-plan-large-batches.sh`：

\`\`\`bash
# 先生成不可变 source manifest
MANIFEST="$(mktemp)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/collect-source-files.sh" "$PROJECT_DIR" > "$MANIFEST"

CC_REVIEW_CONTEXT_SCALE="$CONTEXT_SCALE" \
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/plan-file-batches.sh" \
  "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "frontend" "$MANIFEST"
\`\`\`

合并：
\`\`\`bash
RUN_BATCH_IDS="{RUN_BATCH_IDS}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/merge-batch-results.sh" "$RUN_DIR"
\`\`\`

`scripts/core/merge-batch-results.sh` 的覆盖率展示名根据 `plan.json.language_id` 自动切换为「前端源码文件覆盖率」。
```

- [ ] **Step 5: 运行全套（含路由契约测试）**

Run: `bash tests/run_all.sh` → Expected: All tests passed

- [ ] **Step 6: 提交**

```bash
git add skills/cc-code-reviewer/SKILL.md tests/frontend/test_frontend_route_react.sh
git commit -m "feat(skill): add language detection routing and frontend prescan branch"
```

---

## Task 8（Phase 2）：前端完整 Scan 闭环场景测试 + 文档同步

**Goal:** 用合成 React TypeScript 仓库跑通完整前端 Scan（单 agent + 文件分批两路径），并同步 README/AGENTS/CLAUDE/contract_docs。

**Files:**
- Create: `tests/frontend/test_frontend_full_scan_smoke.sh`
- Create: `tests/frontend/test_frontend_reject_nextjs.sh`
- Modify: `tests/test_contract_docs.sh`（增加前端文档同步断言）
- Modify: `README.md`、`AGENTS.md`、`CLAUDE.md`（前端支持说明）

- [ ] **Step 1: 写失败测试 — Next.js 拒绝（锁定不支持边界）**

`tests/frontend/test_frontend_reject_nextjs.sh`：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-nx.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/next"; mkdir -p "$D/src/app"
cat > "$D/package.json" <<'JSON'
{"name":"n","dependencies":{"next":"^14.0.0","react":"^18.0.0"}}
JSON
echo 'export default function P(){return <div/>}' > "$D/src/app/page.tsx"

# detect-project 必须标记不支持，不能套用 React 规则
OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D")"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$OUT"
grep -q "reason=nextjs" <<< "$OUT"

# scan-project 仍然输出 PROFILE（但 PROJECT_TYPE 为 unsupported）
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D" 2>&1 || true)"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$SOUT"

echo "PASS: frontend reject nextjs"
```

- [ ] **Step 2: 写失败测试 — 完整 Scan 冒烟（端到端脚本链路）**

`tests/frontend/test_frontend_full_scan_smoke.sh`（不启动 LLM 子 agent；验证脚本链路：detect → scan → manifest → plan → 模拟 batch 结果 → merge → 报告标题/覆盖率）：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-full.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/react"; mkdir -p "$D/src/components" "$D/src/api"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"},
 "devDependencies":{"vite":"^5.0.0","typescript":"^5.0.0"}}
JSON
echo 'export function App(){return <div/>}' > "$D/src/App.tsx"
echo 'export function C(){return <span/>}' > "$D/src/components/C.tsx"
seq 1 9000 | sed 's/.*/export const x& = () => null;/' > "$D/src/api/client.ts"  # 大文件触发分批
cat > "$D/tsconfig.json" <<'JSON'
{"compilerOptions":{"strict":true}}
JSON
cat > "$D/vite.config.ts" <<'TS'
import { defineConfig } from 'vite'; export default defineConfig({})
TS

# 1. detect + scan
bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D" | grep -q "frontend-react"
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$SOUT"
FCNT="$(printf '%s\n' "$SOUT" | sed -n 's/^SOURCE_FILE_COUNT=//p')"
test "$FCNT" -ge 3

# 2. manifest + plan
MANIFEST="$(mktemp)"
bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D" > "$MANIFEST"
test "$(grep -c . "$MANIFEST")" -ge 3
POUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-020000 CC_REVIEW_CONTEXT_SCALE=1 \
        bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"
RUN_DIR="$(printf '%s\n' "$POUT" | sed -n 's/^RUN_DIR=//p')"
test -f "$RUN_DIR/plan.json"
grep -q '"language_id": "frontend"' "$RUN_DIR/plan.json"

# 3. 模拟所有批次 completed（写 status + 结果）
for bj in "$RUN_DIR"/batches/batch-*.json; do
  bid="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{batch_id}' "$bj")"
  cat > "$RUN_DIR/results/$bid.md" <<MD
# Batch ${bid}
## 发现列表
### P2 | [维度3-React规范] 示例
- 文件：src/components/C.tsx:1
- 证据：示例
- 建议：示例
MD
  cat > "$RUN_DIR/results/$bid.status.json" <<JSON
{"batch_id":"$bid","status":"completed",
 "planned_source_loc":100,"planned_source_file_count":1,
 "result_path":"$RUN_DIR/results/$bid.md","finding_count":1}
JSON
done

# 4. merge → 完整报告（无 [阶段性]，覆盖率 = 100%）
MOUT="$(RUN_BATCH_IDS="" bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR")"
SUMM="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"finding_count": 1' "$SUMM"
grep -q '"source_file_coverage_percent": 100' "$SUMM"
head -n1 "$REPORT" | grep -qv '\[阶段性\]'      # 全部批次纳入 → 完整报告
head -n1 "$REPORT" | grep -qv '\[合并阻塞\]'

echo "PASS: frontend full scan smoke"
```

- [ ] **Step 3: 运行两个新测试**

Run: `bash tests/frontend/test_frontend_reject_nextjs.sh && bash tests/frontend/test_frontend_full_scan_smoke.sh`
Expected: PASS

- [ ] **Step 4: 更新 test_contract_docs.sh — 前端文档同步断言**

在 `tests/test_contract_docs.sh` 中增加（若该测试已有「文件存在性」断言段，追加；否则新增一段）：

```bash
# === 前端多语言文档同步断言 ===
for f in \
  "scripts/core/detect-language.sh" \
  "scripts/core/validate-scope.sh" \
  "scripts/core/plan-file-batches.sh" \
  "scripts/core/merge-batch-results.sh" \
  "scripts/languages/frontend/detect-project.sh" \
  "scripts/languages/frontend/scan-project.sh" \
  "scripts/languages/frontend/collect-source-files.sh" \
  "scripts/languages/frontend/detect-code-intelligence.sh" \
  "agents/cc-code-reviewer-frontend.md" \
  "references/language-adapter-contract.md" \
  "references/shared-review-framework.md" \
  "references/languages/frontend/source-scope.md" \
  "references/languages/frontend/review-framework.md" \
  "references/languages/frontend/react-rules.md"; do
  test -f "$ROOT_DIR/$f" || { echo "MISSING: $f" >&2; exit 1; }
done

# SKILL.md 必须含语言路由分支
grep -q "语言探测与路由" "$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
grep -q "CANDIDATE_LANGUAGE:frontend" "$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
grep -q "cc-code-reviewer-frontend" "$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"

# 前端矩阵与 React 规则必须被引用
grep -q "frontend-review-framework\|languages/frontend/review-framework" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "react-rules" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
```

- [ ] **Step 5: 同步 README.md / AGENTS.md / CLAUDE.md**

在这三处的「项目概述/支持范围」段补充一行（措辞与现有风格一致）：

```markdown
- **多语言支持**：首期支持 Java 与 React/TypeScript/JavaScript 前端审查；统一入口 `/cc-code-reviewer:cc-code-reviewer` 自动路由，混合仓库由用户选择一种语言；前端基于语言无关的共享内核 + 前端适配器，详见 `docs/superpowers/specs/2026-06-23-multi-language-reviewer-design.md`。
```

并在 AGENTS.md「Architecture > Key Responsibilities」补充前端 Agent 职责条目（对应 `agents/cc-code-reviewer-frontend.md`）。

- [ ] **Step 6: 运行全套**

Run: `bash tests/run_all.sh` → Expected: All tests passed

- [ ] **Step 7: 提交**

```bash
git add tests/frontend/test_frontend_full_scan_smoke.sh tests/frontend/test_frontend_reject_nextjs.sh \
        tests/test_contract_docs.sh README.md AGENTS.md CLAUDE.md
git commit -m "test(frontend): add full scan smoke + nextjs rejection; sync docs"
```

---

## Task 9（Phase 3）：前端大项目分批恢复与门禁

**Goal:** 验证前端大仓库的分批恢复、失败门禁、阶段性报告与确定性去重，确保与 Java 大仓库同等能力。

**Files:**
- Create: `tests/frontend/test_frontend_batch_resume_and_gate.sh`

**Interfaces:**
- Consumes: `scripts/core/plan-file-batches.sh` + `merge-batch-results.sh`（已实现）
- Produces: 验证恢复语义（completed 跳过）、失败门禁（`[合并阻塞]`）、阶段性（部分完成）、去重（重复发现只计 1）

- [ ] **Step 1: 写失败测试 — 恢复 + 门禁 + 去重**

`tests/frontend/test_frontend_batch_resume_and_gate.sh`：

```bash
#!/bin/bash
set -euo piefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-gate.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.0.0"}}
JSON
for i in 1 2 3; do seq 1 9000 | sed "s/.*/export const m&_$i = 0;/" > "$D/src/m$i.ts"; done
MANIFEST="$(mktemp)"; bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D" > "$MANIFEST"

POUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-030000 CC_REVIEW_CONTEXT_SCALE=1 \
        bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"
RUN_DIR="$(printf '%s\n' "$POUT" | sed -n 's/^RUN_DIR=//p')"

# 仅完成 batch-001（含重复发现），batch-002/003 未完成 → 阶段性 + 覆盖率 < 100
B1="$RUN_DIR/batches/batch-001.json"
BID1="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; print decode_json(<$fh>)->{batch_id}' "$B1")"
cat > "$RUN_DIR/results/$BID1.md" <<MD
# Batch $BID1
## 发现列表
### P2 | [维度3-React规范] 重复发现
- 文件：src/m1.ts:1
- 证据：示例
- 建议：示例
MD
cat > "$RUN_DIR/results/$BID1.status.json" <<JSON
{"batch_id":"$BID1","status":"completed","planned_source_loc":9000,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/$BID1.md","finding_count":1}
JSON

MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS="$BID1" \
        bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" || true)"
SUMM="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"finding_count": 1' "$SUMM"
# 覆盖率必须 < 100（只纳入 1/3 批次）
COV="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; print decode_json(<$fh>)->{source_file_coverage_percent}' "$SUMM")"
test "$COV" -lt 100
head -n1 "$REPORT" | grep -q '\[阶段性\]'

echo "PASS: frontend batch resume and gate"
```

- [ ] **Step 2: 运行，确认通过（核心脚本已在 Task 3 实现）**

Run: `bash tests/frontend/test_frontend_batch_resume_and_gate.sh` → Expected: PASS

- [ ] **Step 3: 运行全套 + git diff --check**

Run: `bash tests/run_all.sh` → Expected: All tests passed（含 `git diff --check`）

- [ ] **Step 4: 提交**

```bash
git add tests/frontend/test_frontend_batch_resume_and_gate.sh
git commit -m "test(frontend): verify batch resume, partial merge gate, and coverage"
```

---

## Phase 4（迁移，Vue 前置门槛）— 列入后续计划

> Phase 4 是「双轨期强制退出门」：通用状态机、文件覆盖率和结果合并仍存在两套实现时，不进入 Vue 适配。本计划范围（React Scan 完成）= Task 0–9。Phase 4–6 应作为**独立的后续 plan**（各产出一个 spec）后再生成计划，不在本计划展开。

建议的 Phase 4 拆解顺序（供后续 plan 参考）：
1. `phase11-plan-file-batches.sh` → 删除，Java 改调 `scripts/core/plan-file-batches.sh`（通过兼容桥喂 `src/main/java` manifest）
2. `phase12-merge-large-batches.sh` → 删除，Java 改调 `scripts/core/merge-batch-results.sh`
3. phase3/phase10 → 拆为 `scripts/languages/java/`，输出 PROFILE_SCHEMA（带 Java 字段别名）
4. 每迁一项删一项重复实现，跑 `tests/java/test_java_baseline_contract.sh` 保证 Java 可见契约不变

---

## Self-Review（已在撰写时完成）

**1. Spec 覆盖**（对照 spec 第 12 节 Phase 0–3 验收 + 第 14 节完成定义）：
- Phase 0（锁 Java 基线）→ Task 0 ✅
- Phase 1（语言扩展内核：探测/混合选择/PROFILE/source manifest/路径校验/文件批次/状态机/覆盖/合并/Java 兼容桥）→ Task 1–4 ✅
- Phase 2（React 闭环：TS/JS+React+Vite/Webpack、正式范围/测试上下文/排除、前端矩阵/React 规则/Frontend Agent、统一交互/增量存量/Ignore/本地报告、可选 TS LSP + 降级）→ Task 5–8 ✅
- Phase 3（大项目分批/恢复/门禁/去重/覆盖率/Ignore 不存临时编号）→ Task 9 ✅
- 第 14 节完成定义 8 条：① 路由（Task 7）② 增量/存量/范围（复用现有 phase5/交互）③ 正式口径/覆盖率（Task 2/9）④ LSP+降级（Task 4）⑤ 批次恢复/门禁/合并（Task 3/9）⑥ 本地/Ignore/飞书（复用现有）⑦ Java 无回归（Task 0 + 每任务 run_all）⑧ 公共层无框架语义（Task 3 中性化）✅

**2. 占位符扫描**：无 TBD/TODO；每个代码步骤含完整实现或明确「以某文件为蓝本 + 标注每处改动」。

**3. 类型/字段一致性**：
- `planned_source_loc`/`planned_source_file_count`/`total_source_loc`/`total_source_file_count`/`source_file_coverage_percent`/`covered_source_loc` 在 Task 3（plan+merge）与 Task 8/9（测试）一致。
- `PROFILE_SCHEMA_VERSION=1`/`LANGUAGE_ID=frontend`/`PROJECT_TYPE=frontend-react` 在 scan-project（Task 2）、路由测试（Task 7）、冒烟测试（Task 8）一致。
- `batch_file_list`/`language_id` 在 plan（Task 3）与测试断言一致。
- 已知遗留：Task 6 前端 Agent 为文档型工件（非脚本），其参数字段名需与 SKILL.md（Task 7）注入对齐——已在 Task 6 Step 1 明确列出新增字段，Task 7 注入时引用同名。
