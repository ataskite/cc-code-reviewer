# 脚本目录重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `scripts/` 从扁平 phaseN 平铺重构为 `core/`（语言中立）+ `languages/{java,frontend}/`（语言专属）分层结构，去掉 phase 编号，执行顺序写进 SKILL.md，消除两对重复脚本，让前端补齐批次状态展示。

**Architecture:** 单向依赖 `languages/* → core/*`。通用脚本入 `core/`（功能名），Java 专属入 `languages/java/`，前端专属入 `languages/frontend/`（已就位）。旧路径降为 exec 转发 wrapper，分 5 阶段迁移，全程可回滚，`tests/run_all.sh` 每阶段全绿。字段层用「读时 fallback」策略让 core/ 脚本同时兼容 Java 的 `java_*` 字段和前端的 `source_*` 字段。

**Tech Stack:** Bash（`set -euo pipefail`），perl（JSON 解析/文本处理），bash 测试套件（`tests/run_all.sh` 自动发现 `test_*.sh`）。

## Global Constraints

- 平台仅 macOS/Linux，perl 由系统提供，保持现有 Bash + perl 混用风格。
- 每个旧路径 wrapper 必须 `exec` 新路径并透传 `"$@"`，输出与退出码与新路径完全一致。
- 迁移期间所有旧测试（`tests/test_phaseN_*.sh`）经 wrapper 调用必须**逐字节不变**通过。
- core/ 不得反向依赖 `languages/`；引用方向严格单向。
- 字段兼容策略：core/ 脚本读 JSON 时，先读 `source_*` 字段，为空则 fallback 读 `java_*` 字段（Java 现有 plan.json 不改字段名即可被 core/ 脚本读取）。
- 预估耗时单一真相源：`core/estimate-review-minutes.sh`（已存在），phase13/新版 show-batch-status 必须 source 它。
- 完整设计见 `docs/superpowers/specs/2026-06-28-scripts-restructure-design.md`。

---

## File Structure

迁移涉及的全部文件（按目标目录组织）：

```
scripts/
├── core/                                    # 语言中立（Task 1 充实, Task 3 迁入通用脚本）
│   ├── estimate-review-minutes.sh           # 已存在（不改）
│   ├── detect-language.sh                   # 已存在（不改）
│   ├── validate-scope.sh                    # 已存在（Task 1 加预留注释）
│   ├── plan-file-batches.sh                 # 已存在（Task 1 加 java_* 读时 fallback）
│   ├── merge-batch-results.sh               # 已存在（Task 1 加 java_* 读时 fallback）
│   ├── show-batch-status.sh                 # ★Task 1 新增（从 phase13 提取）
│   ├── detect-project.sh                    # ←Task 3 phase1
│   ├── detect-branches.sh                   # ←Task 3 phase2-detect
│   ├── switch-branch.sh                     # ←Task 3 phase2-switch
│   ├── detect-lark-plugin.sh                # ←Task 3 phase4
│   ├── preview-recent-commits.sh            # ←Task 3 phase5-preview
│   ├── prepare-incremental.sh               # ←Task 3 phase5-prepare
│   ├── detect-fix-input.sh                  # ←Task 3 phase6
│   ├── detect-superpowers.sh                # ←Task 3 phase7
│   ├── prepare-fix-workspace.sh             # ←Task 3 phase8
│   ├── collect-fix-metadata.sh              # ←Task 3 phase9
│   └── detect-model-context.sh              # ←Task 3 phase14
├── languages/
│   ├── java/                                # Task 2 建
│   │   ├── project-scan.sh                  # ←Task 2 phase3
│   │   ├── detect-code-intelligence.sh      # ←Task 2 phase10
│   │   ├── plan-large-batches.sh            # ←Task 2 phase11-large
│   │   └── plan-file-batches.sh             # ←Task 1/2 瘦身（文件发现+调 core）
│   └── frontend/                            # 已存在（不改路径）
│       ├── scan-project.sh                  # 已存在
│       ├── detect-code-intelligence.sh      # 已存在
│       ├── collect-source-files.sh          # 已存在
│       └── detect-project.sh                # 已存在
├── phase1..phase14-*.sh                     # 旧路径（各 Task 降为 wrapper）
└── (wrapper 在 Task 5 迁移稳定后删除)

skills/cc-code-reviewer/SKILL.md             # Task 4 改路径引用+加调用顺序段
skills/cc-code-fixer/SKILL.md                # Task 4 改路径引用+加调用顺序段
agents/cc-code-reviewer.md                   # Task 4 同步路径
agents/cc-code-reviewer-frontend.md          # Task 4 同步路径
AGENTS.md                                    # Task 4 更新文件结构树
CLAUDE.md                                    # Task 4 同步
references/examples.md                       # Task 4 同步脚本路径
tests/test_contract_docs.sh                  # Task 1/4 加断言
tests/core/test_core_show_batch_status.sh    # ★Task 1 新增
tests/core/test_java_plan_file_batches_uses_core.sh  # ★Task 1 新增
tests/core/test_core_merge_java_fields.sh    # ★Task 1 新增
```

---

## Task 1: 充实 core/ —— 提取 show-batch-status + Java 复用 core（消除重复）

**目标**：从 phase13 提取中立的 `core/show-batch-status.sh`（字段按 language_id + fallback 兼容 java_*），让 phase11-file/phase12 改为复用 core/ 版本（消除两对重复），前端补齐状态展示。本任务**不移动文件位置**，只充实 core/ 的实现 + 让 Java 脚本委托 core/。

**Files:**
- Create: `scripts/core/show-batch-status.sh`
- Create: `tests/core/test_core_show_batch_status.sh`
- Create: `tests/core/test_core_merge_java_fields.sh`
- Create: `tests/core/test_java_plan_file_batches_uses_core.sh`
- Modify: `scripts/core/merge-batch-results.sh`（加 java_* 读时 fallback）
- Modify: `scripts/core/plan-file-batches.sh`（加 java_* 读时 fallback，供 merge 用）
- Modify: `scripts/phase13-show-large-batch-status.sh`（瘦身为转发 core/show-batch-status.sh）
- Modify: `scripts/phase11-plan-file-batches.sh`（瘦身为生成 manifest + 调 core/plan-file-batches.sh）
- Modify: `scripts/phase12-merge-large-batches.sh`（瘦身为转发 core/merge-batch-results.sh）
- Modify: `scripts/core/validate-scope.sh`（加预留注释）
- Modify: `skills/cc-code-reviewer/SKILL.md`（前端分批流程加 show-batch-status 接入点）
- Modify: `tests/test_contract_docs.sh`（加 show-batch-status.sh 存在性断言）

**Interfaces:**
- Consumes: `core/estimate-review-minutes.sh`（已存在，提供 `target_review_minutes`/`ceil_div`/`review_cost_of`/`estimate_review_minutes`）
- Produces:
  - `core/show-batch-status.sh` CLI：`bash core/show-batch-status.sh <PROJECT_DIR>`，读 `$PROJECT_DIR/.cc-code-reviewer/runs/{RUN_DIR}/plan.json`，按 `language_id` 字段切换展示。输出 Markdown 状态表 + 动态执行计划（与旧 phase13 逐字节一致）。
  - `core/merge-batch-results.sh` 增强：读 JSON 时 `total_source_loc` 为空则 fallback `total_java_loc`；`planned_source_loc` 为空则 fallback `planned_java_loc`。覆盖率标签按 `language_id` 切换（已存在该逻辑，确认 fallback 即可）。

### 核心策略：字段读时 fallback

Java 的 plan.json 用 `total_java_loc`/`planned_java_loc`，前端用 `total_source_loc`/`planned_source_loc`。core/ 脚本读时统一用 fallback 模式，Java 现有 plan.json 无需改字段名：

```bash
# 读总行数：先 source_，空则 java_
TOTAL_LOC="$(json_get "$PLAN_PATH" total_source_loc)"
[ -n "$TOTAL_LOC" ] || TOTAL_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
```

- [ ] **Step 1: 写失败测试 —— core/show-batch-status 字段切换**

`tests/core/test_core_show_batch_status.sh`：构造两个 plan.json（一个 `language_id=java`+`total_java_loc`，一个 `language_id=frontend`+`total_source_loc`），断言两者都能被 `core/show-batch-status.sh` 渲染出状态表，且 Java 输出含「Java 行数」、前端输出含「源码行数」。

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/core/show-batch-status.sh"

make_run() {
  local lang="$1" loc_field="$2" file_field="$3"
  local tmp; tmp="$(mktemp -d)"
  local run_dir="$tmp/.cc-code-reviewer/runs/20260101-000000-main-standard"
  mkdir -p "$run_dir/batches" "$run_dir/results"
  cat > "$run_dir/plan.json" <<EOF
{"language_id":"$lang","batch_count":1,"$loc_field":1500,"$file_field":20,"review_mode":"standard","run_id":"test","project_name":"p","review_scope":"全量"}
EOF
  cat > "$run_dir/batches/batch-001.json" <<EOF
{"batch_id":"batch-001","scan_roots":["src"],"planned_${lang}_loc":1500,"planned_${lang}_file_count":20,"planned_review_cost":1500,"modules":"mod-a"}
EOF
  echo "$tmp"
}

# Java plan（java_* 字段）
JTMP="$(make_run java total_java_loc total_java_file_count)"
JOUT="$(bash "$SCRIPT" "$JTMP")"
echo "$JOUT" | grep -q "batch-001"
echo "$JOUT" | grep -qE "Java 行数|Java 行覆盖"

# 前端 plan（source_* 字段）
FTMP="$(make_run frontend total_source_loc total_source_file_count)"
FOUT="$(bash "$SCRIPT" "$FTMP")"
echo "$FOUT" | grep -q "batch-001"
echo "$FOUT" | grep -qE "源码行数|源码行覆盖"

# Java plan.json 缺 language_id 时应 fallback 为 java（旧行为兼容）
JTMP2="$(mktemp -d)"; JRUN2="$JTMP2/.cc-code-reviewer/runs/r2"; mkdir -p "$JRUN2/batches"
cat > "$JRUN2/plan.json" <<'EOF'
{"batch_count":0,"total_java_loc":0,"total_java_file_count":0,"review_mode":"standard","run_id":"r2","project_name":"p","review_scope":"全量"}
EOF
bash "$SCRIPT" "$JTMP2" >/dev/null  # 不应报错

rm -rf "$JTMP" "$FTMP" "$JTMP2"
echo "PASS: core show-batch-status"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/core/test_core_show_batch_status.sh`
Expected: FAIL（`scripts/core/show-batch-status.sh` 不存在）

- [ ] **Step 3: 实现 core/show-batch-status.sh**

以 `scripts/phase13-show-large-batch-status.sh` 为蓝本复制，关键修改：
1. 顶部已有的 `source core/estimate-review-minutes.sh` 保留。
2. 读 plan.json 的字段改为 fallback 模式（见下方「字段 fallback 片段」）。
3. 展示文案按 `language_id` 切换：`LOC_LABEL`（"Java 行数" vs "前端源码行数"）、`COVERAGE_LABEL`（"Java 行覆盖" vs "前端源码行覆盖"）。
4. 读 batch.json 的 `planned_loc`/`planned_files` 同样 fallback。

字段 fallback 片段（替换原 phase13 第 318-319、368-369、373-374 行）：

```bash
# 从 plan.json 读总规模，兼容 java_* 和 source_* 两套字段名
LANGUAGE_ID="$(json_get "$PLAN_PATH" language_id)"
[ -n "$LANGUAGE_ID" ] || LANGUAGE_ID="java"   # 旧 Java plan.json 无此字段，默认 java
case "$LANGUAGE_ID" in
  frontend) LOC_LABEL="前端源码行数"; FILE_LABEL="前端源码文件"; COVERAGE_LABEL="前端源码行覆盖" ;;
  *)        LOC_LABEL="Java 行数";    FILE_LABEL="Java 文件";    COVERAGE_LABEL="Java 行覆盖" ;;
esac
TOTAL_LOC="$(json_get "$PLAN_PATH" total_source_loc)"
[ -n "$TOTAL_LOC" ] || TOTAL_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_source_file_count)"
[ -n "$TOTAL_FILE_COUNT" ] || TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"
```

batch 循环内（原 368-374 行）改为：

```bash
planned_loc="$(json_get "$batch_path" planned_source_loc)"
[ -n "$planned_loc" ] || planned_loc="$(json_get "$batch_path" planned_java_loc)"
planned_files="$(json_get "$batch_path" planned_source_file_count)"
[ -n "$planned_files" ] || planned_files="$(json_get "$batch_path" planned_java_file_count)"
```

echo 文案（原 351、408 行）改为用 `$LOC_LABEL`/`$COVERAGE_LABEL` 变量。

- [ ] **Step 4: 运行新测试确认通过**

Run: `bash tests/core/test_core_show_batch_status.sh`
Expected: PASS

- [ ] **Step 5: 写失败测试 —— phase13 转发 wrapper 输出不变**

在 `tests/test_phase13_show_large_batch_status.sh` 末尾追加一条断言：`core/show-batch-status.sh` 对同一 plan.json 的输出与 `phase13-show-large-batch-status.sh` **完全一致**（`diff` 为空），确保转发无行为变化。

```bash
# 追加到 tests/test_phase13_show_large_batch_status.sh 末尾（echo "✅..." 之前）
OLD_OUT="$(bash "$ROOT_DIR/scripts/phase13-show-large-batch-status.sh" "$RUN_DIR_PROJECT" 2>&1)"
NEW_OUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$RUN_DIR_PROJECT" 2>&1)"
if [ "$OLD_OUT" != "$NEW_OUT" ]; then
  echo "FAIL: phase13 转发后输出必须与 core/show-batch-status 一致" >&2
  diff <(echo "$OLD_OUT") <(echo "$NEW_OUT") | head -20 >&2
  exit 1
fi
```

- [ ] **Step 6: 实现 phase13 转发 wrapper**

把 `scripts/phase13-show-large-batch-status.sh` 内容替换为转发 wrapper（逻辑已全部移到 core/show-batch-status.sh）：

```bash
#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/show-batch-status.sh
# 本文件仅为向后兼容旧调用路径，新代码请直接引用新路径。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/show-batch-status.sh" "$@"
```

- [ ] **Step 7: 运行 phase13 全量测试确认逐字节不变**

Run: `bash tests/test_phase13_show_large_batch_status.sh`
Expected: PASS（含新增的 diff 一致断言）

- [ ] **Step 8: 写失败测试 —— core/merge-batch-results 兼容 java_* 字段**

`tests/core/test_core_merge_java_fields.sh`：构造一个 Java plan.json（`total_java_loc` + `language_id=java` 的 batch），跑 `core/merge-batch-results.sh`，断言 summary.json 不报错、覆盖率字段非空。

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
RUN_DIR="$TMP/.cc-code-reviewer/runs/20260101-000000-main-standard"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
cat > "$RUN_DIR/plan.json" <<'EOF'
{"language_id":"java","batch_count":1,"total_java_loc":1000,"total_java_file_count":10,"review_mode":"standard","run_id":"test","project_name":"p","review_scope":"全量"}
EOF
cat > "$RUN_DIR/batches/batch-001.json" <<'EOF'
{"batch_id":"batch-001","scan_roots":["src"],"planned_java_loc":1000,"planned_java_file_count":10,"planned_review_cost":1000,"modules":"m"}
EOF
# 构造已完成状态
cat > "$RUN_DIR/results/batch-001.status.json" <<'EOF'
{"status":"completed","planned_java_loc":1000,"planned_java_file_count":10}
EOF
# 构造一个空的发现清单
echo "## 审查发现" > "$RUN_DIR/results/batch-001.findings.md"

MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" >/dev/null 2>&1 || true
[ -f "$RUN_DIR/summary.json" ] || { echo "FAIL: summary.json 未生成" >&2; exit 1; }
grep -q '"java_loc_coverage_percent"' "$RUN_DIR/summary.json" 2>/dev/null || \
  grep -q '"source_file_coverage_percent"' "$RUN_DIR/summary.json" || \
  { echo "FAIL: 覆盖率字段缺失" >&2; exit 1; }
rm -rf "$TMP"
echo "PASS: core merge java fields"
```

- [ ] **Step 9: 实现 core/merge-batch-results.sh 的 java_* fallback**

在 `scripts/core/merge-batch-results.sh` 第 113-114 行（读 `total_source_loc`/`total_source_file_count`）后追加 fallback：

```bash
# 兼容 Java 旧 plan.json 的 java_* 字段名
[ -n "$TOTAL_LOC" ] || TOTAL_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
[ -n "$TOTAL_FILE_COUNT" ] || TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"
```

在读取每个 batch.json 的 planned 字段处（grep `planned_source_loc` 定位），同样加 fallback 到 `planned_java_loc`/`planned_java_file_count`。

- [ ] **Step 10: 运行测试确认通过**

Run: `bash tests/core/test_core_merge_java_fields.sh && bash tests/core/test_core_merge_batch_results.sh`
Expected: PASS

- [ ] **Step 11: 写失败测试 —— phase11-plan-file-batches 委托 core/**

`tests/core/test_java_plan_file_batches_uses_core.sh`：跑 `phase11-plan-file-batches.sh` 后，断言生成的 plan.json 含 `language_id: "java"`（证明走了 core/ 版本），且 `total_java_loc`/`total_source_loc` 至少一个非空。

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
mkdir -p "$TMP/src/main/java/com/example"
echo "public class A {}" > "$TMP/src/main/java/com/example/A.java"

OUT="$(CC_REVIEW_CONTEXT_SCALE=1 bash "$ROOT_DIR/scripts/phase11-plan-file-batches.sh" "$TMP" standard main 2>&1)"
RUN_DIR_LINE="$(echo "$OUT" | grep -oE '\.cc-code-reviewer/runs/[^"]*plan.json' | head -1)"
[ -n "$RUN_DIR_LINE" ] || { echo "FAIL: 未输出 plan.json 路径" >&2; exit 1; }
PLAN_PATH="$TMP/$RUN_DIR_LINE"
grep -q '"language_id": "java"' "$PLAN_PATH" || \
  grep -q '"language_id":"java"' "$PLAN_PATH" || \
  { echo "FAIL: Java 文件分批应通过 core/ 走，plan.json 须含 language_id=java" >&2; exit 1; }
rm -rf "$TMP"
echo "PASS: java plan-file-batches uses core"
```

- [ ] **Step 12: 瘦身 phase11-plan-file-batches.sh 委托 core/**

把 `scripts/phase11-plan-file-batches.sh` 改为薄 wrapper：
1. 保留 Java 文件发现逻辑（`find ... -path '*/src/main/java/*' -name '*.java'`），生成 manifest 文件（TSV：`path\tloc`）。
2. 调用 `core/plan-file-batches.sh "$PROJECT_DIR" "$REVIEW_MODE" "$BRANCH_NAME" "java" "$MANIFEST_PATH"`。
3. core/ 版本会写 `total_source_loc` 等字段——为保持旧测试兼容，在 wrapper 末尾把生成的 plan.json 里的 `source_*` 字段**同步写一份 java_* 别名**（perl 脚本读 JSON 加 key），或让旧测试改读 source_* 字段（更干净，推荐后者，在 Step 13 处理）。

具体实现（替换 phase11-plan-file-batches.sh 主体）：

```bash
#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:-standard}"
BRANCH_NAME="${3:-no-branch}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Java 文件发现（Java 专属逻辑，保留在此）
MANIFEST="$(mktemp)"
find "$PROJECT_DIR" -path '*/src/main/java/*' -name '*.java' -type f 2>/dev/null | while read -r f; do
  loc="$(wc -l < "$f" 2>/dev/null || echo 0)"
  printf '%s\t%s\n' "$f" "$loc"
done > "$MANIFEST"

[ -s "$MANIFEST" ] || { echo "NO_JAVA_FILES: 未在 src/main/java 下找到 .java 文件" >&2; rm -f "$MANIFEST"; exit 1; }

# 2. 委托语言中立的 core/plan-file-batches.sh
CC_REVIEW_CONTEXT_SCALE="${CC_REVIEW_CONTEXT_SCALE:-1}" \
  bash "$SCRIPT_DIR/core/plan-file-batches.sh" "$PROJECT_DIR" "$REVIEW_MODE" "$BRANCH_NAME" "java" "$MANIFEST"
RC=$?
rm -f "$MANIFEST"
exit $RC
```

- [ ] **Step 13: 修复旧测试读新字段名**

检查 `tests/test_phase11_plan_file_batches.sh`：若它断言 `total_java_loc`，改为同时接受 `total_java_loc` 或 `total_source_loc`（用 `grep -qE`），或直接改读 `total_source_loc`。确保旧测试通过 wrapper 仍绿。

Run: `bash tests/test_phase11_plan_file_batches.sh`
Expected: PASS

- [ ] **Step 14: 瘦身 phase12-merge-large-batches.sh 转发 core/**

`scripts/phase12-merge-large-batches.sh` 的合并逻辑已全部在 `core/merge-batch-results.sh`（Step 9 已加 java_* fallback）。把 phase12 替换为转发 wrapper：

```bash
#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/merge-batch-results.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/merge-batch-results.sh" "$@"
```

- [ ] **Step 15: 运行 phase12 旧测试确认通过**

Run: `bash tests/test_phase12_merge_large_batches.sh`
Expected: PASS（经 wrapper + fallback，Java 字段被正确读取）

- [ ] **Step 16: 前端分批流程接入 show-batch-status**

在 `skills/cc-code-reviewer/SKILL.md` 前端分批段（约 L933-L942 附近），在 `core/merge-batch-results.sh` 调用前，新增调用 `core/show-batch-status.sh` 展示前端批次状态。插入说明文字：

```markdown
### 前端分批：批次状态展示
在前端分批规划完成后、启动 agent 前，调用批次状态展示脚本，向用户展示批次表与动态执行计划：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

此脚本按前端 plan.json 的 `language_id=frontend` 字段读取 `total_source_loc`/`planned_source_loc`，展示「前端源码行数」「前端源码行覆盖」。
```

- [ ] **Step 17: validate-scope.sh 加预留注释**

在 `scripts/core/validate-scope.sh` 顶部 shebang 后插入注释：

```bash
# 状态：预留脚本，当前未接入运行时流程。
# 计划在后续 scope 校验增强中接入（多模块选择时的路径边界校验）。
# 保留 test_contract_docs.sh 的存在性断言。
```

- [ ] **Step 18: test_contract_docs.sh 加 show-batch-status 断言**

在 `tests/test_contract_docs.sh` 末尾（`echo "✅ 契约文档测试通过"` 前）加：

```bash
[ -f "$ROOT_DIR/scripts/core/show-batch-status.sh" ] || { echo "MISSING: scripts/core/show-batch-status.sh" >&2; exit 1; }
```

- [ ] **Step 19: 跑全量测试**

Run: `bash tests/run_all.sh`
Expected: 全绿（含所有新增测试 + 全部旧测试经 wrapper 通过）

- [ ] **Step 20: 提交**

```bash
git add scripts/core/show-batch-status.sh scripts/core/merge-batch-results.sh \
        scripts/phase13-show-large-batch-status.sh scripts/phase11-plan-file-batches.sh \
        scripts/phase12-merge-large-batches.sh scripts/core/validate-scope.sh \
        skills/cc-code-reviewer/SKILL.md tests/test_contract_docs.sh \
        tests/core/test_core_show_batch_status.sh tests/core/test_core_merge_java_fields.sh \
        tests/core/test_java_plan_file_batches_uses_core.sh tests/test_phase13_show_large_batch_status.sh \
        tests/test_phase11_plan_file_batches.sh
git commit -m "refactor: 充实 core/ —— 提取 show-batch-status + Java 复用 core（消除重复）

- 从 phase13 提取 core/show-batch-status.sh，字段按 language_id + fallback 兼容 java_*/source_*
- phase13 降为转发 wrapper，输出逐字节不变
- phase11-plan-file-batches 瘦身为 Java 文件发现 + 委托 core/plan-file-batches.sh
- phase12-merge-large-batches 转发 core/merge-batch-results.sh
- core/merge-batch-results 加 java_* 字段读时 fallback
- 前端分批流程接入 show-batch-status（补齐缺失的状态展示）"
```

---

## Task 2: 建 languages/java/ 目录，移动 Java 专属脚本

**目标**：创建 `scripts/languages/java/`，把 4 个 Java 专属脚本移入（含 Task 1 瘦身后的 plan-file-batches），旧路径留 wrapper 转发。

**Files:**
- Create: `scripts/languages/java/project-scan.sh`（移动自 phase3）
- Create: `scripts/languages/java/detect-code-intelligence.sh`（移动自 phase10）
- Create: `scripts/languages/java/plan-large-batches.sh`（移动自 phase11-large）
- Create: `scripts/languages/java/plan-file-batches.sh`（移动自 Task 1 瘦身后的 phase11-file）
- Modify: `scripts/phase3-project-scan.sh`（→ wrapper 转发 languages/java/）
- Modify: `scripts/phase10-detect-code-intelligence.sh`（→ wrapper）
- Modify: `scripts/phase11-plan-large-batches.sh`（→ wrapper）
- Modify: `scripts/phase11-plan-file-batches.sh`（→ wrapper，转发到 languages/java/plan-file-batches.sh）

**Interfaces:**
- Consumes: Task 1 的 `core/plan-file-batches.sh`（`languages/java/plan-file-batches.sh` 内部调用它）
- Produces: `languages/java/*.sh` 四个 Java 专属脚本，被 SKILL.md Java 流程引用

- [ ] **Step 1: 创建 languages/java/ 并移动 phase3**

```bash
mkdir -p scripts/languages/java
git mv scripts/phase3-project-scan.sh scripts/languages/java/project-scan.sh
```

创建 `scripts/phase3-project-scan.sh` 转发 wrapper：

```bash
#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/languages/java/project-scan.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/languages/java/project-scan.sh" "$@"
```

- [ ] **Step 2: 移动 phase10**

```bash
git mv scripts/phase10-detect-code-intelligence.sh scripts/languages/java/detect-code-intelligence.sh
```

创建 `scripts/phase10-detect-code-intelligence.sh` 转发 wrapper（同 Step 1 模式，转发到 `languages/java/detect-code-intelligence.sh`）。

- [ ] **Step 3: 移动 phase11-large**

```bash
git mv scripts/phase11-plan-large-batches.sh scripts/languages/java/plan-large-batches.sh
```

创建 `scripts/phase11-plan-large-batches.sh` 转发 wrapper（转发到 `languages/java/plan-large-batches.sh`）。

- [ ] **Step 4: 移动 phase11-file（Task 1 已瘦身的版本）**

```bash
git mv scripts/phase11-plan-file-batches.sh scripts/languages/java/plan-file-batches.sh
```

创建 `scripts/phase11-plan-file-batches.sh` 转发 wrapper（转发到 `languages/java/plan-file-batches.sh`）。

注意：`languages/java/plan-file-batches.sh` 内部调用 `core/plan-file-batches.sh`，其 `SCRIPT_DIR` 计算会变为 `scripts/languages/java/`。需确认脚本内 `$SCRIPT_DIR/core/...` 路径改为相对项目根的绝对路径。修改 `languages/java/plan-file-batches.sh` 第 6 行：

```bash
# 原：SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 改为（向上两级到 scripts/ 根）：
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
```

这样 `$SCRIPT_DIR/core/plan-file-batches.sh` 仍指向 `scripts/core/plan-file-batches.sh`。

- [ ] **Step 5: 跑 Java 相关全量测试**

Run: `bash tests/test_phase3_project_scan.sh && bash tests/test_phase10_detect_code_intelligence.sh && bash tests/test_phase11_plan_large_batches.sh && bash tests/test_phase11_plan_file_batches.sh && bash tests/run_all.sh`
Expected: 全绿（所有旧测试经 wrapper 通过，路径正确解析）

- [ ] **Step 6: 提交**

```bash
git add scripts/languages/java/ scripts/phase3-project-scan.sh \
        scripts/phase10-detect-code-intelligence.sh scripts/phase11-plan-large-batches.sh \
        scripts/phase11-plan-file-batches.sh
git commit -m "refactor: 建 languages/java/ 目录，移动 Java 专属脚本

- phase3 → languages/java/project-scan.sh
- phase10 → languages/java/detect-code-intelligence.sh
- phase11-large → languages/java/plan-large-batches.sh
- phase11-file → languages/java/plan-file-batches.sh
- 旧路径降为 exec 转发 wrapper，测试逐字节不变"
```

---

## Task 3: 迁移 11 个通用脚本到 core/

**目标**：把 11 个语言无关脚本从 `scripts/phaseN-*.sh` 移入 `scripts/core/`（功能名），旧路径留 wrapper。

**Files:**（每个脚本 = 移动 + 建 wrapper，共 11 对）
- `phase1-detect-project.sh` → `core/detect-project.sh`
- `phase2-detect-branches.sh` → `core/detect-branches.sh`
- `phase2-switch-branch.sh` → `core/switch-branch.sh`
- `phase4-detect-lark-plugin.sh` → `core/detect-lark-plugin.sh`
- `phase5-preview-recent-commits.sh` → `core/preview-recent-commits.sh`
- `phase5-prepare-incremental.sh` → `core/prepare-incremental.sh`
- `phase6-detect-fix-input.sh` → `core/detect-fix-input.sh`
- `phase7-detect-superpowers.sh` → `core/detect-superpowers.sh`
- `phase8-prepare-fix-workspace.sh` → `core/prepare-fix-workspace.sh`
- `phase9-collect-fix-metadata.sh` → `core/collect-fix-metadata.sh`
- `phase14-detect-model-context.sh` → `core/detect-model-context.sh`

**Interfaces:**
- 这些脚本无内部脚本依赖（都是独立的），移动后只需建 wrapper。
- Produces: `core/` 下 11 个功能名脚本。

- [ ] **Step 1: 批量移动 11 个脚本到 core/**

对每个脚本执行 `git mv`，移动后建转发 wrapper。由于这 11 个脚本都是独立的（无 `SCRIPT_DIR/core/...` 内部引用，除了 phase13 已在 Task 1 处理），移动是安全的。

逐个执行（示例前 3 个，其余同理）：

```bash
# phase1
git mv scripts/phase1-detect-project.sh scripts/core/detect-project.sh
cat > scripts/phase1-detect-project.sh <<'EOF'
#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/detect-project.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/detect-project.sh" "$@"
EOF
chmod +x scripts/phase1-detect-project.sh

# phase2-detect
git mv scripts/phase2-detect-branches.sh scripts/core/detect-branches.sh
cat > scripts/phase2-detect-branches.sh <<'EOF'
#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/detect-branches.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/detect-branches.sh" "$@"
EOF
chmod +x scripts/phase2-detect-branches.sh

# ... 其余 9 个同理（switch-branch, detect-lark-plugin, preview-recent-commits,
#     prepare-incremental, detect-fix-input, detect-superpowers,
#     prepare-fix-workspace, collect-fix-metadata, detect-model-context）
```

每个 wrapper 模板一致，仅替换目标脚本名。

- [ ] **Step 2: 跑全量测试**

Run: `bash tests/run_all.sh`
Expected: 全绿（所有旧测试经 wrapper 通过）

- [ ] **Step 3: 提交**

```bash
git add scripts/core/ scripts/phase1-detect-project.sh scripts/phase2-detect-branches.sh \
        scripts/phase2-switch-branch.sh scripts/phase4-detect-lark-plugin.sh \
        scripts/phase5-preview-recent-commits.sh scripts/phase5-prepare-incremental.sh \
        scripts/phase6-detect-fix-input.sh scripts/phase7-detect-superpowers.sh \
        scripts/phase8-prepare-fix-workspace.sh scripts/phase9-collect-fix-metadata.sh \
        scripts/phase14-detect-model-context.sh
git commit -m "refactor: 迁移 11 个通用脚本到 core/（功能名，去 phase 编号）

移动：phase1/2/4/5/6/7/8/9/14 → core/{detect-project,detect-branches,
switch-branch,detect-lark-plugin,preview-recent-commits,prepare-incremental,
detect-fix-input,detect-superpowers,prepare-fix-workspace,collect-fix-metadata,
detect-model-context}.sh
旧路径降为 exec 转发 wrapper，测试逐字节不变"
```

---

## Task 4: 更新 SKILL.md / agent.md / AGENTS.md 路径引用 + 加调用顺序段

**目标**：把文档中的脚本引用从旧路径改为新路径（core/ 或 languages/），在每个 SKILL.md 新增「脚本调用顺序」编号列表段，更新 AGENTS.md/CLAUDE.md 文件结构树，加防回退断言。

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`（17 处路径 + Java/前端两段调用顺序）
- Modify: `skills/cc-code-fixer/SKILL.md`（9 处路径 + 修复流程调用顺序）
- Modify: `agents/cc-code-reviewer.md`（内部脚本引用同步）
- Modify: `agents/cc-code-reviewer-frontend.md`（内部脚本引用同步）
- Modify: `AGENTS.md`（文件结构树）
- Modify: `CLAUDE.md`（文件结构树同步）
- Modify: `references/examples.md`（脚本路径引用）
- Modify: `tests/test_contract_docs.sh`（加调用顺序段断言 + 防回退断言）

**Interfaces:**
- Consumes: Task 1-3 完成的新路径结构
- Produces: 文档全部用新路径；含「脚本调用顺序」编排段；防回退断言

- [ ] **Step 1: 替换 cc-code-reviewer/SKILL.md 的脚本路径**

用精确的 Edit 替换 17 处。映射表（旧→新）：

| 行 | 旧路径片段 | 新路径片段 |
|----|-----------|-----------|
| L39 | `scripts/phase1-detect-project.sh` | `scripts/core/detect-project.sh` |
| L42 | `scripts/phase2-detect-branches.sh` | `scripts/core/detect-branches.sh` |
| L58 | `scripts/phase2-switch-branch.sh` | `scripts/core/switch-branch.sh` |
| L68 | `scripts/phase3-project-scan.sh` | `scripts/languages/java/project-scan.sh` |
| L71 | `scripts/phase10-detect-code-intelligence.sh` | `scripts/languages/java/detect-code-intelligence.sh` |
| L74/L117 | `scripts/phase4-detect-lark-plugin.sh` | `scripts/core/detect-lark-plugin.sh` |
| L219 | `scripts/phase14-detect-model-context.sh` | `scripts/core/detect-model-context.sh` |
| L337/L883 | `scripts/phase11-plan-large-batches.sh` | `scripts/languages/java/plan-large-batches.sh` |
| L338/L690 | `scripts/phase13-show-large-batch-status.sh` | `scripts/core/show-batch-status.sh` |
| L590 | `scripts/phase5-preview-recent-commits.sh` | `scripts/core/preview-recent-commits.sh` |
| L909 | `scripts/phase11-plan-file-batches.sh` | `scripts/languages/java/plan-file-batches.sh` |
| L1036 | `scripts/phase5-prepare-incremental.sh` | `scripts/core/prepare-incremental.sh` |
| L1051 | `scripts/phase12-merge-large-batches.sh` | `scripts/core/merge-batch-results.sh` |

对每行用 Edit 工具精确替换（`old_string` 含足够上下文确保唯一）。例如：

```
old: bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase1-detect-project.sh" "<用户输入的路径>"
new: bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-project.sh" "<用户输入的路径>"
```

- [ ] **Step 2: 在 cc-code-reviewer/SKILL.md 加 Java 扫描流程调用顺序段**

在 SKILL.md 的预扫描流程描述之后（Step 1-9 预扫描步骤附近），新增一段：

```markdown
## 脚本调用顺序（Java 扫描流程）
1. `core/detect-project.sh` → 识别项目路径
2. `core/detect-branches.sh` → 列出分支（多分支则 AskUserQuestion 选）
3. `core/switch-branch.sh` → 切换到选定分支（按需）
4. `core/detect-language.sh` → 探测语言（固定 java）
5. `languages/java/project-scan.sh` → Java 预扫描（Maven/技术栈）
6. `languages/java/detect-code-intelligence.sh` → jdtls 探测
7. `core/detect-lark-plugin.sh` → lark-cli 检测
8. `core/detect-model-context.sh` → 模型窗口 → CONTEXT_SCALE
9. 读 ignore 规则 → 输出预扫描摘要
10. AskUserQuestion 交互（模式/报告/入口/范围…）
11. `core/estimate-review-minutes.sh` → 计算预估耗时（单 agent 模式）
12. [分批] `languages/java/plan-large-batches.sh` 或 `plan-file-batches.sh`
13. [分批] `core/show-batch-status.sh` → 展示批次状态
14. [分批] 启动 agent → `core/merge-batch-results.sh` 合并
15. [增量] `core/preview-recent-commits.sh` + `core/prepare-incremental.sh`
```

- [ ] **Step 3: 在 cc-code-reviewer/SKILL.md 加前端扫描流程调用顺序段**

紧接 Java 段后新增：

```markdown
## 脚本调用顺序（前端扫描流程）
1. `core/detect-project.sh` → 识别项目路径
2. `core/detect-branches.sh` → 列出分支（多分支则 AskUserQuestion 选）
3. `core/switch-branch.sh` → 切换到选定分支（按需）
4. `core/detect-language.sh` → 探测语言（固定 frontend）
5. `languages/frontend/scan-project.sh` → 前端预扫描（PROFILE_SCHEMA）
6. `languages/frontend/detect-code-intelligence.sh` → typescript-lsp 探测
7. `core/detect-lark-plugin.sh` → lark-cli 检测
8. `core/detect-model-context.sh` → 模型窗口 → CONTEXT_SCALE
9. 读 ignore 规则 → 输出预扫描摘要
10. AskUserQuestion 交互（模式/报告/入口/范围…）
11. `core/estimate-review-minutes.sh` → 计算预估耗时（单 agent 模式）
12. [分批] `core/plan-file-batches.sh` → 前端文件级分批
13. [分批] `core/show-batch-status.sh` → 展示批次状态
14. [分批] 启动 agent → `core/merge-batch-results.sh` 合并
15. [增量] `core/preview-recent-commits.sh` + `core/prepare-incremental.sh`
```

- [ ] **Step 4: 替换 cc-code-fixer/SKILL.md 的脚本路径 + 加调用顺序段**

替换 9 处路径（映射表）：

| 行 | 旧 → 新 |
|----|---------|
| L61 | `phase1-detect-project.sh` → `core/detect-project.sh` |
| L64 | `phase2-detect-branches.sh` → `core/detect-branches.sh` |
| L67 | `phase3-project-scan.sh` → `languages/java/project-scan.sh` |
| L70 | `phase4-detect-lark-plugin.sh` → `core/detect-lark-plugin.sh` |
| L73 | `phase7-detect-superpowers.sh` → `core/detect-superpowers.sh` |
| L126 | `phase6-detect-fix-input.sh` → `core/detect-fix-input.sh` |
| L284/L356 | `phase8-prepare-fix-workspace.sh` → `core/prepare-fix-workspace.sh` |
| L332 | `phase9-collect-fix-metadata.sh` → `core/collect-fix-metadata.sh` |

在 fixer SKILL.md 预检测流程后新增：

```markdown
## 脚本调用顺序（修复流程）
1. `core/detect-project.sh` → 识别项目路径
2. `core/detect-branches.sh` → 列出分支
3. `languages/java/project-scan.sh` → 预扫描（修复只支持 Java）
4. `core/detect-lark-plugin.sh` → lark-cli 检测
5. `core/detect-superpowers.sh` → Superpowers 探测
6. `core/detect-fix-input.sh` → 修复输入校验
7. AskUserQuestion 收集确认问题清单与输出目标
8. `core/prepare-fix-workspace.sh` → 修复工作区准备
9. 执行修复 → `core/collect-fix-metadata.sh` → 收集修复元数据
```

- [ ] **Step 5: 同步两个 agent.md 的脚本路径**

读取 `agents/cc-code-reviewer.md` 和 `agents/cc-code-reviewer-frontend.md`，将其中的 `${CLAUDE_PLUGIN_ROOT}/scripts/phaseN-` 引用替换为新路径（同 Step 1 映射表）。若 agent 内部仅引用参考文件（references/）而不直接调脚本，则无需改动——先 grep 确认。

Run: `grep -n "scripts/phase" agents/cc-code-reviewer.md agents/cc-code-reviewer-frontend.md`

- [ ] **Step 6: 更新 AGENTS.md 文件结构树**

替换 `AGENTS.md` 中的 `## File Structure` 段，反映新的 core/ + languages/ 结构（参考 spec 第三节的目标目录结构）。删除旧的 phaseN 扁平列表，替换为分层结构树。

- [ ] **Step 7: 同步 CLAUDE.md**

读取 `CLAUDE.md`，若它与 `AGENTS.md` 内容相同（软链接或副本），同步更新文件结构树。

Run: `diff AGENTS.md CLAUDE.md | head`（确认是否相同）

- [ ] **Step 8: 更新 references/examples.md 脚本路径**

替换 examples.md 中对话示例里出现的脚本路径引用（如 phase1-detect-project.sh → core/detect-project.sh）。

Run: `grep -n "scripts/phase" references/examples.md`（定位后逐个替换）

- [ ] **Step 9: 加防回退断言到 test_contract_docs.sh**

在 `tests/test_contract_docs.sh` 末尾（`echo "✅..."` 前）加：

```bash
# 防回退：SKILL.md 必须含「脚本调用顺序」段
grep -q "脚本调用顺序" "$ROOT_DIR/skills/cc-code-reviewer/SKILL.md" || { echo "FAIL: cc-code-reviewer SKILL.md 缺「脚本调用顺序」段" >&2; exit 1; }
grep -q "脚本调用顺序" "$ROOT_DIR/skills/cc-code-fixer/SKILL.md" || { echo "FAIL: cc-code-fixer SKILL.md 缺「脚本调用顺序」段" >&2; exit 1; }

# 防回退：SKILL.md 的新引用不应再用旧 phase 路径调用核心脚本（允许 wrapper 存在，但文档引用应用新路径）
# 注：此断言宽松——只检查是否至少有一处用了 core/ 新路径，证明迁移发生
grep -q "scripts/core/detect-project.sh" "$ROOT_DIR/skills/cc-code-reviewer/SKILL.md" || { echo "FAIL: SKILL.md 应引用 core/detect-project.sh" >&2; exit 1; }
grep -q "scripts/languages/java/project-scan.sh" "$ROOT_DIR/skills/cc-code-reviewer/SKILL.md" || { echo "FAIL: SKILL.md 应引用 languages/java/project-scan.sh" >&2; exit 1; }
```

- [ ] **Step 10: 跑全量测试**

Run: `bash tests/run_all.sh`
Expected: 全绿（含新断言）

- [ ] **Step 11: 提交**

```bash
git add skills/ agents/ AGENTS.md CLAUDE.md references/examples.md tests/test_contract_docs.sh
git commit -m "docs: 更新脚本路径引用 + 加调用顺序编排段 + 防回退断言

- SKILL.md 26 处脚本引用改为 core/ 或 languages/ 新路径
- 新增 Java/前端/修复三段「脚本调用顺序」编号列表
- AGENTS.md/CLAUDE.md 文件结构树更新为分层结构
- test_contract_docs 加调用顺序段存在性 + 新路径引用防回退断言"
```

---

## Task 5: 清理旧 wrapper（迁移稳定后）

**目标**：确认所有文档与测试调用点已用新路径后，删除旧 phaseN wrapper 及其专属旧测试（或改为指向新路径）。**此任务必须在 Task 1-4 全部完成、且经过完整端到端验证后执行**。

**Files:**
- Delete: `scripts/phase1-detect-project.sh` ... `scripts/phase14-detect-model-context.sh`（全部旧 wrapper，约 15 个）
- Modify: `tests/test_phaseN_*.sh`（改为直接测新路径，或删除已无意义的 wrapper 测试）

- [ ] **Step 1: 确认无任何运行时引用旧路径**

Run:
```bash
grep -rn "scripts/phase[0-9]" skills/ agents/ references/ AGENTS.md CLAUDE.md
```
Expected: 无输出（所有引用已改为新路径）。若有残留，先修复。

- [ ] **Step 2: 删除旧 wrapper 文件**

```bash
git rm scripts/phase1-detect-project.sh scripts/phase2-detect-branches.sh \
        scripts/phase2-switch-branch.sh scripts/phase4-detect-lark-plugin.sh \
        scripts/phase5-preview-recent-commits.sh scripts/phase5-prepare-incremental.sh \
        scripts/phase6-detect-fix-input.sh scripts/phase7-detect-superpowers.sh \
        scripts/phase8-prepare-fix-workspace.sh scripts/phase9-collect-fix-metadata.sh \
        scripts/phase14-detect-model-context.sh scripts/phase3-project-scan.sh \
        scripts/phase10-detect-code-intelligence.sh scripts/phase11-plan-large-batches.sh \
        scripts/phase11-plan-file-batches.sh scripts/phase13-show-large-batch-status.sh \
        scripts/phase12-merge-large-batches.sh
```

- [ ] **Step 3: 迁移旧测试到新路径名**

对每个 `tests/test_phaseN_*.sh`：将其内部调用的旧脚本路径改为新路径。例如 `tests/test_phase1_detect_project.sh` 内的 `scripts/phase1-detect-project.sh` 改为 `scripts/core/detect-project.sh`。可选：重命名测试文件为 `tests/core/test_core_detect_project.sh`（保持一致性）。

逐个处理（以 phase1 测试为例）：

```bash
# 改测试内部路径
sed -i '' 's|scripts/phase1-detect-project.sh|scripts/core/detect-project.sh|g' tests/test_phase1_detect_project.sh
# 重命名（可选，推荐）
git mv tests/test_phase1_detect_project.sh tests/core/test_core_detect_project.sh
```

对其余测试同理。

- [ ] **Step 4: 跑全量测试**

Run: `bash tests/run_all.sh`
Expected: 全绿（所有测试直接测新路径，无 wrapper 依赖）

- [ ] **Step 5: 端到端验证**

手动触发一次 Java 审查请求和一次前端审查请求，确认完整流程跑通（或用现有测试套件覆盖）。确认 `scripts/` 根目录只剩 `core/` 和 `languages/`，无残留 phaseN 文件。

Run: `ls scripts/*.sh 2>/dev/null`（应为空，只有目录）
Expected: 无输出

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "refactor: 清理旧 phaseN wrapper，迁移完成

- 删除全部旧路径 wrapper（15 个）
- 旧测试迁移到新路径名（tests/test_phaseN_* → tests/core/test_core_*）
- scripts/ 根目录只保留 core/ 和 languages/ 分层结构
- 目录重构全部完成"
```

---

## Self-Review

**1. Spec 覆盖检查**：
- 第三节目录结构 → Task 1（core/show-batch-status）、Task 2（languages/java/）、Task 3（core/ 通用脚本）✓
- 第四节迁移映射 → Task 1（4.3/4.4）、Task 2（4.1/4.2 Java）、Task 3（4.1 core 通用）✓
- 第五节兼容 wrapper → Task 1/2/3 每步建 wrapper ✓
- 第六节调用顺序写进 SKILL.md → Task 4 Step 2-4 ✓
- 第七节路径引用更新 → Task 4 Step 1-8 ✓
- 第八节测试策略 → Task 1（3 个新测试）、Task 4（防回退断言）、Task 5（测试迁移）✓
- 第九节 5 阶段 → Task 1-5 一一对应 ✓
- 第 4.6 validate-scope 预留注释 → Task 1 Step 17 ✓

**2. 占位符扫描**：无 TBD/TODO/「类似 Task N」。Task 3 Step 1 用「其余 9 个同理」+ 给出 wrapper 模板，因 11 个脚本移动逻辑完全一致（`git mv` + 同模板 wrapper），重复 11 遍冗余——这是合理的 DRY，非占位符。

**3. 类型/命名一致性**：
- `core/show-batch-status.sh` 在 Task 1 定义，Task 4 引用 ✓
- `languages/java/project-scan.sh` 在 Task 2 定义，Task 4 引用 ✓
- 字段 fallback 模式（source_* → java_*）在 Task 1 Step 3/9 定义，贯穿 ✓
- `SCRIPT_DIR` 路径修正（Task 2 Step 4 向上两级）✓

**4. 风险点**：
- Task 1 Step 12 phase11-file 瘦身后，`languages/java/plan-file-batches.sh`（Task 2 Step 4）调 `$SCRIPT_DIR/core/plan-file-batches.sh`，SCRIPT_DIR 需向上两级。已在 Task 2 Step 4 明确。
- Task 1 字段 fallback 是核心难点——Java plan.json 用 java_*，core 读 source_*，fallback 桥接两者。已用 3 个测试（Step 1/8/11）覆盖。
