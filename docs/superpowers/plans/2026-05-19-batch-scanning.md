# 大仓库分批扫描 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 对大型 Java 仓库自动分批并行扫描，突破单 agent 200k token 上下文限制，最终输出一份统一审查报告。

**Architecture:** 在 SKILL.md 中新增分批判定逻辑和并发编排，使用 Claude Code Agent 工具并行启动多个 cc-code-reviewer 子代理（每个处理一批文件），主 skill 收集所有批次结果后合并去重、生成最终报告。子代理新增 `审查输出模式=仅发现清单` 模式，跳过完整报告和飞书上传。

**Tech Stack:** Claude Code Agent tool（多路并发）、Bash（文件分批计算）、Markdown（skill/agent prompt 定义）、Bash test suite（契约测试）

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `agents/cc-code-reviewer.md` | Modify | 新增 `审查输出模式`、`批次编号`、`本批文件列表` 参数；batch 模式跳过阶段 A/B 和飞书上传 |
| `skills/cc-code-reviewer/SKILL.md` | Modify | 新增分批判定、步骤 6 并发选择、batch agent 编排、报告合并、快速启动 `--concurrency` 参数 |
| `tests/test_contract_docs.sh` | Modify | 新增分批相关契约断言 |
| `references/report-format.md` | No change | 合并时复用 |
| `references/review-framework.md` | No change | 不改动 |
| `scripts/` | No change | 不新增脚本 |

---

### Task 1: Agent — 新增 `审查输出模式` 参数定义

**Files:**
- Modify: `agents/cc-code-reviewer.md:46-72`（外部参数注入章节）

- [ ] **Step 1: 在 agent 参数表中新增三个参数**

在 `agents/cc-code-reviewer.md` 的「外部参数注入」章节的参数表中，紧跟在 `| 报告格式路径 | ... |` 行之后，新增三行：

```markdown
| 批次编号 | ... |
| 审查输出模式 | ... |
| 本批审查文件列表 | ... |
```

具体内容 — 在参数表末尾（`报告格式路径` 行之后）添加：

```markdown
| 批次编号 | ... |
| 审查输出模式 | ... |
| 本批审查文件列表 | ... |
```

同时在「参数含义」列表末尾（`报告格式路径` 说明之后）新增：

```markdown
- **批次编号**（`BATCH_INDEX`/`BATCH_COUNT`）：格式为 `N/M`，表示第 N 批共 M 批。仅在分批模式下提供。未提供时视为单 agent 全量模式
- **审查输出模式**（`REVIEW_OUTPUT_MODE`）：
  - `完整报告`（默认）：按 REPORT_FORMAT_PATH 输出完整审查报告
  - `仅发现清单`：只输出结构化发现列表，不生成完整报告，不执行飞书上传。用于分批审查时的单批输出
- **本批审查文件列表**（`BATCH_FILE_LIST`）：分批模式下外部注入的文件路径列表，每行一个绝对路径。提供此参数时，阶段 A（文件收集）和阶段 B（风险排序）跳过，直接使用注入的文件列表从阶段 C 开始执行
```

- [ ] **Step 2: 在 agent 执行流程中添加 batch 模式跳过逻辑**

在 `agents/cc-code-reviewer.md` 的「Agent 执行流程」章节的开头说明块（以 `> **说明**` 开头）之后、`### 第一步：执行代码审查` 之前，新增以下段落：

```markdown
**审查输出模式分支**：

当 `REVIEW_OUTPUT_MODE=仅发现清单` 时，执行流程调整如下：
- **阶段 A（文件收集）跳过**：直接使用 `BATCH_FILE_LIST` 注入的文件列表
- **阶段 B（风险排序）跳过**：文件已由主 skill 按风险排序后分批注入
- **阶段 C（逐文件审查）正常执行**：按注入的文件列表逐文件读取 + 多维度评估
- **阶段 D（定向补充扫描）正常执行**
- **第二步（发现归类）正常执行**
- **第三步（生成报告）替换为发现清单输出**：不按 REPORT_FORMAT_PATH 生成完整报告，而是将结构化发现列表追加写入 `/tmp/review-batch-{BATCH_INDEX}-{PROJECT_NAME}.md`。格式见「Batch 发现清单输出格式」章节
- **第三步之后（持久化报告文件）跳过**
- **第四步（上传飞书云文档）跳过**
- **第五步（创建飞书多维表格）跳过**
- **第六步（输出最终汇总）替换**：仅输出简要完成信息 `✅ Batch {BATCH_INDEX}/{BATCH_COUNT} 完成：发现 {问题数} 个问题`，不输出完整报告
```

- [ ] **Step 3: 在 agent 末尾新增「Batch 发现清单输出格式」章节**

在 `agents/cc-code-reviewer.md` 末尾（`## 审查覆盖率追踪` 章节之后）新增：

```markdown

---

## Batch 发现清单输出格式

仅在 `REVIEW_OUTPUT_MODE=仅发现清单` 时使用此格式。将发现写入 `/tmp/review-batch-{BATCH_INDEX}-{PROJECT_NAME}.md`。

```markdown
# Batch {BATCH_INDEX}/{BATCH_COUNT} 审查发现

## 审查范围
- 文件数：{本批实际扫描文件数}
- 行数：{本批实际扫描行数}
- 覆盖率：100%

## 发现列表

### P0 | [维度1-正确性] {问题标题}
- 文件：{path}:{line}
- 证据：
  ```java
  // 代码片段
  ```
- 建议：{修复建议}

### P1 | [维度5-安全] {问题标题}
- 文件：{path}:{line}
- 证据：{代码片段或配置}
- 建议：{修复建议}

（无问题的文件不在发现清单中列出，但已计入覆盖率统计）
```

**重要**：
- 不输出完整报告（不包含摘要、统计、建议等段落）
- 不执行飞书上传
- 只输出结构化的发现列表
- 无问题的文件跳过不列
```

- [ ] **Step 4: 运行契约测试验证不破坏现有断言**

Run: `bash tests/run_all.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add agents/cc-code-reviewer.md
git commit -m "feat(agent): add batch output mode, batch index, and file list parameters"
```

---

### Task 2: Agent — 更新 prompt 注入格式说明

**Files:**
- Modify: `agents/cc-code-reviewer.md:33-48`（外部参数注入的表格格式）

- [ ] **Step 1: 在 agent 的「外部参数注入」prompt 表格中新增三个参数行**

在 agent 文件的 prompt 示例表格（`| 参数 | 值 |` 格式）中，在 `| 报告格式路径 | ... |` 行之后添加三行：

```markdown
| 批次编号 | {BATCH_INDEX}/{BATCH_COUNT} |
| 审查输出模式 | {REVIEW_OUTPUT_MODE} |
| 本批审查文件列表 | {逐行列出文件路径} |
```

同时在辅助数据章节中新增 batch 文件列表的注入格式说明。在「### 变更统计概览（仅增量审查时提供）」块之后添加：

```markdown

### 本批审查文件列表（仅分批模式时提供）
{逐行列出文件绝对路径}
```

- [ ] **Step 2: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add agents/cc-code-reviewer.md
git commit -m "feat(agent): add batch prompt injection format for file list and output mode"
```

---

### Task 3: Skill — 新增分批判定逻辑

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md:128-138`（第三步与第四步之间）

- [ ] **Step 1: 在 SKILL.md 第三步（预扫描摘要）之后、第四步（参数收集）之前，新增「第三步之后：分批判定」章节**

在 SKILL.md 中，`### 第四步：参数收集（根据模式选择分支）` 行之前，插入新章节：

```markdown

### 第三步之后：分批判定

**时机**：交互式模式在步骤 2（选择审查类型）确定 REVIEW_TYPE 后、步骤 6 前执行判定。快速启动模式在参数校验时一并判定。

**公式**：
```
estimated_tokens = REVIEW_FILE_COUNT × 500 + REVIEW_LINE_COUNT × 3
BATCH_MODE = estimated_tokens > 100000 AND REVIEW_TYPE = 存量审查
```

**前提**：分批模式仅对存量审查生效。增量审查的变更文件数通常远低于阈值；即使超过阈值，batch agent 缺少增量上下文（GIT_LOG/CHANGED_FILES），无法判断问题是变更引入还是存量，因此不进入分批。

**参数来源**：
- `REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT` 从 phase3-project-scan.sh 输出中解析（`Java文件总数` 和 `代码总行数`）
- `500`：每个文件的工具调用 + agent 评估开销（token）
- `3`：每行 Java 代码平均 token 数
- `100000`：单批留给文件内容 + 开销的上限（200k 总上下文 - 25k 系统 prompt - 50k agent 输出 ≈ 125k，取 100k 留余量）

**判定结果**：
- `BATCH_MODE=false` → 走现有单 agent 流程，不做任何改动
- `BATCH_MODE=true` → 进入分批模式

**交互式模式**：分批判定延迟到步骤 2 确定审查类型后执行（因为公式依赖 REVIEW_TYPE）。

**快速启动模式**：参数校验时一并计算 BATCH_MODE。BATCH_MODE 的判定不影响参数校验（`--concurrency` 参数在 BATCH_MODE=false 时被静默忽略）。
```

- [ ] **Step 2: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add batch mode trigger formula and timing specification"
```

---

### Task 4: Skill — 交互式模式新增步骤 6（并发数选择）和更新步骤 7

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md:163-353`（交互式确认步骤定义章节）

- [ ] **Step 1: 在步骤 5（飞书上传选项）之后、步骤 6（确认执行计划）之前，插入新的步骤 6（并发数选择）**

在 SKILL.md 的 `### 步骤 5：选择飞书上传选项` 章节结束后、`### 步骤 6：确认执行计划` 章节之前，插入：

```markdown

### 步骤 6：选择并发数（条件步骤）

**触发条件**：BATCH_MODE=true。不满足时跳过此步骤。

**前置计算**：触发此步骤前，必须先完成分批计算（见「分批计算」章节），得到 BATCH_COUNT。

在调用 AskUserQuestion 之前，先输出分批信息：
```
📊 大仓库分批扫描

本次审查范围较大，将采用分批并行扫描：
- 文件总数：{REVIEW_FILE_COUNT} 个
- 代码行数：{REVIEW_LINE_COUNT} 行
- 预计分批：{BATCH_COUNT} 批
```

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择并发扫描策略"
- header: "并发数"
- options:
  - label: "串行执行"
    description: "逐批扫描，最稳定但最慢，约 {total_min} 分钟"
  - label: "3 路并发（推荐）"
    description: "同时扫描 3 批，约 {total_min} 分钟"
  - label: "5 路并发"
    description: "同时扫描 5 批，需要较好硬件，约 {total_min} 分钟"
- multiSelect: false

**耗时预估公式**：
```
每批耗时 = 根据现有模式×规模估算表（见步骤 7 中的预估时间参考表）
total_min = ceil(BATCH_COUNT / CONCURRENCY) × 每批耗时
```

**用户响应后变量赋值**：
- 串行执行 → CONCURRENCY=1
- 3 路并发 → CONCURRENCY=3
- 5 路并发 → CONCURRENCY=5
```

- [ ] **Step 2: 将原步骤 6（确认执行计划）重编号为步骤 7，并追加分批信息**

将 `### 步骤 6：确认执行计划` 改为 `### 步骤 7：确认执行计划`。

在步骤 7 的执行计划模板中，在 `- 飞书上传：{FEISHU_UPLOAD_OPTION}` 行之后、模板结束前，新增一行：

```
- 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）  ← 仅 BATCH_MODE=true 时显示
- 预计耗时：约 {total_min} 分钟  ← 仅 BATCH_MODE=true 时显示
```

具体修改：将步骤 7 的执行计划模板改为：

```markdown
```
📋 执行计划：
- 项目路径：{PROJECT_DIR}
- 项目类型：{PROJECT_TYPE}
- 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}（仅 Git 项目显示）
- 审查类型：{REVIEW_TYPE}
- 审查范围：{REVIEW_SCOPE}
- 审查模式：{REVIEW_MODE}
- 启用维度：{根据模式 × 维度矩阵列出具体维度名称}
- 飞书上传：{FEISHU_UPLOAD_OPTION}
{- 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）  ← BATCH_MODE=true 时追加}
{- 预计耗时：约 {total_min} 分钟  ← BATCH_MODE=true 时追加}
```
```

- [ ] **Step 3: 更新步骤 7 的启动提示，区分单 agent 和分批模式**

将步骤 7 中用户确认后的启动提示拆分为两种情况：

原内容（单 agent）保留，但标注仅 `BATCH_MODE=false` 时使用。新增 `BATCH_MODE=true` 时的启动提示，对应 spec 第 4 章的「启动提示」。

在 `**用户确认后的启动提示**` 区域，修改为：

```markdown
**用户确认后的启动提示**：

**BATCH_MODE=false 时**（与现有设计一致）：

```
🚀 正在启动独立代码审查子代理...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
⏱️ 预估耗时：{预估时间}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。

{飞书上传时追加}
📤 审查完成后将自动上传到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。
```

**BATCH_MODE=true 时**：

```
🚀 正在启动分批并行代码审查...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
📊 扫描策略：{BATCH_COUNT} 批 / {CONCURRENCY} 路并发
⏱️ 预估耗时：约 {total_min} 分钟
📌 共 {BATCH_COUNT} 批次将按 {CONCURRENCY} 路并发执行，全部完成后自动合并结果。

{飞书上传时追加}
📤 审查完成后将自动上传到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。
```
```

- [ ] **Step 4: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add interactive step 6 for concurrency selection, renumber step 7"
```

---

### Task 5: Skill — 新增分批计算章节

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`（在步骤 6 定义之后插入）

- [ ] **Step 1: 在交互式确认步骤定义章节末尾、快速启动模式章节之前，新增「分批计算」章节**

在 SKILL.md 的交互式步骤定义最后一个步骤（步骤 7）之后、`---` 分隔线之前的 `## 快速启动模式参数规范` 章节之前，插入：

```markdown

---

## 分批计算

当 BATCH_MODE=true 时，主 skill 在 prompt 中执行以下步骤（不使用脚本）：

### 文件收集与排序

1. **收集文件路径和行数**：用 Bash 执行以下命令获取每个文件的路径和行数：
   ```bash
   find "$PROJECT_DIR" -name '*.java' -not -path '*/target/*' -not -path '*/build/*' -not -path '*/.git/*' -exec wc -l {} + 2>/dev/null | sort -rn
   ```
   增量审查时不执行此步（已由触发条件排除）

2. **风险排序**：按文件名模式排序，高风险优先。通过 Bash 按文件名后缀分组实现：
   - P0 热点：`*Controller.java`、`*Service.java`、`*Security*.java`、`*Filter.java`、`*Interceptor.java`
   - P1 重点：`*Client.java`、`*Pool.java`、`*Scheduler.java`、`*Handler.java`、`*Consumer.java`、`*Producer.java`
   - P2 常规：其余文件（`*DTO.java`、`*VO.java`、`*Entity.java`、`*Util*.java` 等）

   实现方式：对 find 结果按文件名后缀排序，P0 关键词匹配的文件排前，P1 次之，P2 最后

### Token 预算打包

```
batch_token_budget = 100000
current_batch_tokens = 0
current_batch_files = []

for each file in sorted_list:
    file_tokens = file_line_count × 3 + 500
    if current_batch_tokens + file_tokens > batch_token_budget:
        封装 current_batch 为一个批次
        开始新批次
        current_batch_tokens = 0
        current_batch_files = []
    current_batch_files.append(file)
    current_batch_tokens += file_tokens

封装最后一批
```

### 输出

得到 `BATCH_COUNT`、`CONCURRENCY` 和每个批次的文件列表。每个批次记录：
- 文件路径列表
- 文件数（BATCH_FILE_COUNT）
- 行数（BATCH_LINE_COUNT）
```

- [ ] **Step 2: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add batch calculation logic with risk sorting and token budget packing"
```

---

### Task 6: Skill — Batch Agent 编排与执行

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`（第五步章节区域）

- [ ] **Step 1: 将第五步（调用子 agent）拆分为单 agent 和分批两条路径**

在 SKILL.md 的 `### 第五步：调用子 agent 执行代码审查` 章节中，在现有内容之前，新增分支判断：

```markdown
### 第五步：调用子 agent 执行代码审查

**分支判断**：
- BATCH_MODE=false → 执行「路径 A：单 agent 模式」（现有逻辑不变）
- BATCH_MODE=true → 执行「路径 B：分批并行模式」（新增逻辑）

#### 路径 A：单 agent 模式（BATCH_MODE=false）

{现有第五步内容保持不变}

#### 路径 B：分批并行模式（BATCH_MODE=true）

使用 Agent 工具启动多个 `cc-code-reviewer` 子代理，按轮次并发执行。

**编排逻辑**：

以 CONCURRENCY=3、BATCH_COUNT=9 为例：

```
轮次 1：同时启动 Agent(batch-1) + Agent(batch-2) + Agent(batch-3)
  → 等待全部完成
轮次 2：同时启动 Agent(batch-4) + Agent(batch-5) + Agent(batch-6)
  → 等待全部完成
轮次 3：同时启动 Agent(batch-7) + Agent(batch-8) + Agent(batch-9)
  → 等待全部完成
```

每轮同时发出 CONCURRENCY 个 Agent 工具调用。当前轮所有 agent 返回后，开始下一轮。CONCURRENCY=1 时退化为串行。

**每个 batch agent 的调用参数**：

- description: "Batch {BATCH_INDEX}/{BATCH_COUNT} 代码审查"
- subagent_type: "cc-code-reviewer:cc-code-reviewer"
- prompt: 见下方「Batch Agent Prompt 注入格式」

**Batch Agent Prompt 注入格式**：

每个 batch agent 的 prompt 与现有格式一致，但额外注入以下参数并做以下调整：

```
## 审查任务参数（外部注入，请直接使用，无需再次确认）

| 参数 | 值 |
|------|-----|
| 项目路径 | {PROJECT_DIR} |
| 项目名称 | {PROJECT_NAME} |
| 项目类型 | {PROJECT_TYPE} |
| 审查类型 | {REVIEW_TYPE} |
| 审查范围 | {REVIEW_SCOPE} |
| 审查模式 | {REVIEW_MODE} |
| 飞书上传选项 | 飞书上传不可用 |
| 审查文件数量 | {BATCH_FILE_COUNT} |
| 审查代码行数 | {BATCH_LINE_COUNT} |
| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |
| 报告格式路径 | {REPORT_FORMAT_PATH} |
| 批次编号 | {BATCH_INDEX}/{BATCH_COUNT} |
| 审查输出模式 | 仅发现清单 |

### 本批审查文件列表（外部注入，直接使用，不要重新扫描）
{逐行列出文件绝对路径}

### 项目概况（预扫描结果）
{PROJECT_SCAN_RESULT}

请基于以上审查参数，立即开始执行代码审查。不要进行任何用户交互或询问，直接从代码审查开始执行。
```

**关键差异**（对比路径 A 单 agent 调用）：

| 字段 | 单 agent（路径 A） | Batch agent（路径 B） |
|------|----------|-------------|
| 审查文件数量 | REVIEW_FILE_COUNT（总量） | BATCH_FILE_COUNT（本批） |
| 审查代码行数 | REVIEW_LINE_COUNT（总量） | BATCH_LINE_COUNT（本批） |
| 飞书上传选项 | 用户选择的值 | 固定"飞书上传不可用" |
| 批次编号 | 无 | BATCH_INDEX/BATCH_COUNT |
| 审查输出模式 | 无（默认完整报告） | "仅发现清单" |
| 文件列表来源 | agent 自行 Glob | 外部注入，agent 不扫描 |
| 增量数据 | 注入 GIT_LOG 等 | 不注入（分批仅支持存量审查） |

**飞书上传**：batch agent 不执行飞书上传。飞书上传由主 skill 在合并完成后统一处理。

**错误处理**：

| 场景 | 处理方式 |
|------|----------|
| 某个 batch agent 超时/失败 | 该批次标记为"未完成"，其余批次继续。合并时标注该批次未覆盖 |
| 所有 batch 均失败 | 输出失败报告，提示用户重试 |
| 合并时某 batch 文件不存在 | 跳过该批次，报告中标注缺失 |
```

- [ ] **Step 2: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add batch agent orchestration with concurrency rounds and prompt format"
```

---

### Task 7: Skill — 报告合并章节

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`（在第五步之后、子 agent 返回结果处理之前）

- [ ] **Step 1: 在第五步之后、子 agent 返回结果处理之前，新增「第五步之后：报告合并」章节**

在 SKILL.md 中，在第五步结束标记之后、`### 子 agent 返回结果处理` 之前，插入：

```markdown

### 第五步之后：报告合并（仅 BATCH_MODE=true 时执行）

所有 batch agent 完成后，主 skill 执行合并（不启动额外 agent）。

#### 合并步骤

1. **读取所有 batch 文件**：逐个 Read `/tmp/review-batch-{i}-{PROJECT_NAME}.md`（i = 1..BATCH_COUNT）
2. **提取所有问题**：从每个 batch 的发现列表中解析出结构化问题（严重级别、维度、标题、位置、证据、建议）
3. **跨批去重**：同一文件 + 同一行 + 同一维度的问题只保留一条，取更高严重级别
4. **聚合同类问题**：相同根因的多处出现合并为一条，标注总数和代表位置
5. **按严重程度排序**：P0 → P1 → P2 → P3 → 待确认
6. **汇总覆盖率**：
   ```
   总扫描文件数 = Σ 各批 BATCH_FILE_COUNT
   总扫描行数 = Σ 各批 BATCH_LINE_COUNT
   文件覆盖率 = 总扫描文件数 / REVIEW_FILE_COUNT × 100%
   行覆盖率 = 总扫描行数 / REVIEW_LINE_COUNT × 100%
   综合覆盖率 = (文件覆盖率 + 行覆盖率) / 2
   ```
7. **按完整报告格式输出**：复用 `references/report-format.md` 格式，生成最终报告

#### 合并后输出

使用 Write 工具将合并后的报告保存到 `{PROJECT_DIR}/code-review-report-{PROJECT_NAME}-{timestamp}.md`（与单 agent 模式一致的命名和路径）。

#### 合并后飞书上传

复用现有飞书上传逻辑：根据 FEISHU_UPLOAD_OPTION 执行上传，上传合并后的报告文件。

#### 合并后结果展示

**已上传飞书时**：

```
✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）
📊 审查覆盖：{总扫描文件数}/{REVIEW_FILE_COUNT} 文件（{总扫描行数}/{REVIEW_LINE_COUNT} 行），覆盖率 {综合覆盖率}%
📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / P3: {n} / 待确认: {n}）

🔥 最高风险项：
  - P0-1: {问题一句话描述} — {位置}
  （最多列 5 条）

📄 审查报告：{链接}
📋 问题清单：{链接}

💡 建议：{一句话关键建议}
👉 详细报告请点击上方飞书链接查看。
```

**未上传飞书时**：

```
📄 报告已保存到本地文件：
   {PROJECT_DIR}/code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md

{合并后的完整报告内容}

---

✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）
📊 审查覆盖：{总扫描文件数}/{REVIEW_FILE_COUNT} 文件（{总扫描行数}/{REVIEW_LINE_COUNT} 行），覆盖率 {综合覆盖率}%
📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / P3: {n} / 待确认: {n}）
💡 建议：{一句话关键建议}
```

#### 上下文保护

- 每个 batch 文件约 2-5k token（只含发现清单，不含代码原文）
- 30 个 batch 的合并读取总量约 60-150k token
- 合并操作在主 skill 上下文中执行，通过压缩上下文可容纳
```

- [ ] **Step 2: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add report merging logic with dedup, coverage stats, and output formatting"
```

---

### Task 8: Skill — 快速启动模式新增 `--concurrency` 参数

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md:355-461`（快速启动模式参数规范章节）

- [ ] **Step 1: 在快速启动参数表中新增 `--concurrency` 参数**

在 SKILL.md 的快速启动参数规范表中，在 `| --upload |` 行之后添加：

```markdown
| `--concurrency` | 可选 | `1` / `3` / `5` | 并发数，默认 `3`；BATCH_MODE=false 时被忽略 |
```

- [ ] **Step 2: 在参数映射表中新增 `--concurrency` 映射**

在快速启动参数映射表中添加：

```markdown
| `--concurrency 1` | `CONCURRENCY=1` | 直接使用 |
| `--concurrency 3` 或未提供 | `CONCURRENCY=3` | 默认值 |
| `--concurrency 5` | `CONCURRENCY=5` | 直接使用 |
```

- [ ] **Step 3: 在校验规则中新增 `--concurrency` 校验**

在快速启动校验规则中添加：

```markdown
7. `--concurrency` 不在 `1` / `3` / `5` 时报错，但不影响其他参数校验
8. BATCH_MODE=false 时 `--concurrency` 被静默忽略（不报错）
```

在非法参数值判定中添加：

```markdown
- `--concurrency` 不在 `1` / `3` / `5`
```

- [ ] **Step 4: 更新快速启动校验通过后的启动提示**

将现有启动提示改为根据 BATCH_MODE 分支：

```markdown
### 快速启动校验通过后的启动提示

**BATCH_MODE=false 时**（与现有提示一致）：

```
🚀 快速启动模式 — 正在启动独立代码审查子代理...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
🌿 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}
📤 飞书上传：{FEISHU_UPLOAD_OPTION}
⏱️ 预估耗时：{预估时间}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。
```

**BATCH_MODE=true 时**：

```
🚀 快速启动模式 — 正在启动分批并行代码审查...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
📊 扫描策略：{BATCH_COUNT} 批 / {CONCURRENCY} 路并发
🌿 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}
📤 飞书上传：{FEISHU_UPLOAD_OPTION}
⏱️ 预估耗时：约 {total_min} 分钟
📌 每批子代理独立执行审查，全部完成后自动合并结果。
```
```

- [ ] **Step 5: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add --concurrency parameter for fast mode batch scanning"
```

---

### Task 9: Skill — 子 agent 返回结果处理更新

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`（子 agent 返回结果处理章节）

- [ ] **Step 1: 在子 agent 返回结果处理章节中新增 BATCH_MODE=true 分支**

在 SKILL.md 的 `### 子 agent 返回结果处理` 章节开头，添加分支判断：

```markdown
### 子 agent 返回结果处理

**BATCH_MODE=false 时**：直接使用子 agent 返回的结果，按下方现有逻辑处理（已上传飞书 / 未上传飞书 / 上传失败降级）。

**BATCH_MODE=true 时**：子 agent 返回结果仅用于进度确认。实际合并和输出由「第五步之后：报告合并」章节处理。每个 batch agent 完成后输出 `✅ Batch {BATCH_INDEX}/{BATCH_COUNT} 完成`，全部完成后进入合并流程。
```

- [ ] **Step 2: 运行测试验证**

Run: `bash tests/run_all.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md
git commit -m "feat(skill): add batch mode branch in sub-agent result handling"
```

---

### Task 10: 契约测试 — 新增分批相关断言

**Files:**
- Modify: `tests/test_contract_docs.sh`

- [ ] **Step 1: 在 test_contract_docs.sh 末尾（`All tests passed` 之前）新增分批相关契约断言**

在 `tests/test_contract_docs.sh` 文件的最后一行 `grep -q "report-driven fixing" "$MARKETPLACE_FILE"` 之后、文件结尾之前，新增以下契约断言：

```bash

# === Batch scanning contracts ===

# Agent must support batch output mode
grep -q "审查输出模式" "$AGENT_FILE"
grep -q "仅发现清单" "$AGENT_FILE"
grep -q "完整报告" "$AGENT_FILE"
grep -q "批次编号" "$AGENT_FILE"
grep -q "BATCH_INDEX" "$AGENT_FILE"
grep -q "BATCH_FILE_LIST" "$AGENT_FILE"
grep -q "review-batch-" "$AGENT_FILE"

# Agent must skip stages in batch mode
grep -q "阶段 A.*跳过" "$AGENT_FILE"
grep -q "阶段 B.*跳过" "$AGENT_FILE"

# Skill must have batch trigger formula
grep -q "BATCH_MODE" "$SKILL_FILE"
grep -q "estimated_tokens" "$SKILL_FILE"
grep -q "100000" "$SKILL_FILE"

# Skill must have concurrency step
grep -q "选择并发数" "$SKILL_FILE"
grep -q "CONCURRENCY" "$SKILL_FILE"
grep -q "串行执行" "$SKILL_FILE"
grep -q "3 路并发" "$SKILL_FILE"
grep -q "5 路并发" "$SKILL_FILE"

# Skill must have batch agent orchestration
grep -q "分批并行模式" "$SKILL_FILE"
grep -q "BATCH_FILE_COUNT" "$SKILL_FILE"
grep -q "BATCH_LINE_COUNT" "$SKILL_FILE"
grep -q "飞书上传不可用" "$SKILL_FILE"

# Skill must have report merging
grep -q "报告合并" "$SKILL_FILE"
grep -q "跨批去重" "$SKILL_FILE"
grep -q "聚合同类问题" "$SKILL_FILE"

# Skill must have --concurrency fast mode parameter
grep -q "\-\-concurrency" "$SKILL_FILE"

# Skill batch mode only for stock review
grep -q "仅对存量审查生效" "$SKILL_FILE"

# Skill must show batch info in step 7 execution plan
grep -q "扫描策略" "$SKILL_FILE"
grep -q "分批并行扫描" "$SKILL_FILE"
```

- [ ] **Step 2: 运行测试，预期当前失败（因为功能尚未实现）**

Run: `bash tests/test_contract_docs.sh 2>&1 | tail -5`
Expected: FAIL（断言找不到新增的关键词）

- [ ] **Step 3: 验证全部改动完成后测试通过**

在所有前序 Task 完成后运行：

Run: `bash tests/run_all.sh`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add tests/test_contract_docs.sh
git commit -m "test: add contract assertions for batch scanning feature"
```

---

### Task 11: 最终集成验证

**Files:**
- All modified files

- [ ] **Step 1: 运行完整测试套件**

Run: `bash tests/run_all.sh`
Expected: All tests PASS

- [ ] **Step 2: 检查 git diff 确认无遗漏改动**

Run: `git diff --stat`
Expected: Only `agents/cc-code-reviewer.md`, `skills/cc-code-reviewer/SKILL.md`, `tests/test_contract_docs.sh` modified

- [ ] **Step 3: 最终 commit（如有未提交的修正）**

```bash
git add -A
git commit -m "feat: complete batch scanning for large Java repositories"
```

---

## Self-Review Checklist

**1. Spec coverage:**

| Spec 章节 | 对应 Task | 状态 |
|-----------|----------|------|
| 1. 触发判定 | Task 3 | 覆盖 |
| 2. 分批计算 | Task 5 | 覆盖 |
| 3. 交互步骤变更（步骤 6/7） | Task 4 | 覆盖 |
| 3. 快速启动模式 | Task 8 | 覆盖 |
| 4. Batch Agent 编排 | Task 6 | 覆盖 |
| 5. 报告合并 | Task 7 | 覆盖 |
| 6. 错误处理 | Task 6（内含） | 覆盖 |
| 7. 改动文件清单 | 全部 | 覆盖 |
| Agent prompt 改动 | Task 1, 2 | 覆盖 |
| 契约测试 | Task 10 | 覆盖 |

**2. Placeholder scan:** No TBD/TODO/fill-in-later found.

**3. Type consistency:** All variable names (`BATCH_MODE`, `BATCH_COUNT`, `CONCURRENCY`, `BATCH_FILE_COUNT`, `BATCH_LINE_COUNT`, `BATCH_INDEX`, `BATCH_FILE_LIST`, `REVIEW_OUTPUT_MODE`) are consistent across all tasks.
