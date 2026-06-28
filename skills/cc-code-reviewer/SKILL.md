---
description: Java 代码审查 — 支持增量/存量审查、15维度评估、飞书报告上传
---

## 执行算法（最高优先级，必须严格按此顺序执行）

以下是你必须遵循的执行顺序。不允许跳过、合并、重新排序或即兴发挥。

### 第一步：提取项目路径（最先执行）

必须先从用户输入中提取 `PROJECT_INPUT`，再进入预扫描。此步骤只是解析输入，不得调用 AskUserQuestion。

#### 项目路径提取规则

必须按以下优先级提取项目路径，禁止简单取"第一个非 `--` token"：

1. **优先提取 Git URL**：匹配 `https://...`、`http://...`、`git://...`、`git@...` 的完整 token，作为 `PROJECT_INPUT`
2. 其次提取本地路径 token：
   - Unix/macOS 绝对路径：`/path/to/project`
   - 相对路径：`.`、`..`、`./project`、`../project`、`project/subdir`
3. 路径可以出现在自然语言中，例如 `帮我审查 /path/to/project`，不得把 `帮我审查`、`这个项目` 等自然语言词当作路径
4. 路径包含空格时，应使用用户输入中带引号的完整路径；传给脚本时必须整体加引号
5. 如果无法提取项目路径，立即输出：
   ```text
   ❌ 未识别到项目路径

   请提供本地项目路径或 Git 仓库地址，例如：
     /cc-code-reviewer:cc-code-reviewer /path/to/project
     /cc-code-reviewer:cc-code-reviewer https://github.com/org/repo.git
   ```
   然后终止，不进入预扫描。

### 第二步：项目识别与分支检测（2 个脚本，Git 项目时在此阶段选择分支）

使用第一步之后提取出的 `PROJECT_INPUT`，先执行以下 2 个脚本：

仅支持 macOS / Linux（Bash）：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-project.sh" "<用户输入的路径>"
# 输出：PROJECT_DIR=<路径> PROJECT_SOURCE=local|git-cache

bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-branches.sh" "$PROJECT_DIR"
# 输出：IS_GIT_REPO=true/false CURRENT_BRANCH=<分支> BRANCH: ...（最多5个本地分支）
```

**Git 项目分支选择**（在此阶段立即执行）：

当 `IS_GIT_REPO=true` 且本地分支数 > 1 时，**必须**立即调用 AskUserQuestion 让用户选择分支。

**分支选择交互**：
- question: "检测到 Git 仓库（当前分支：{CURRENT_BRANCH}），请选择要审查的分支"
- header: "选择分支"
- options: 从 phase2 输出的 BRANCH: 行动态生成选项（最多5个本地分支，按最近活动时间排序）
- multiSelect: false

**用户响应后**：
- 设置 TARGET_BRANCH
- 如不是当前分支，执行 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/switch-branch.sh" "$PROJECT_DIR" "{TARGET_BRANCH}" "$CURRENT_BRANCH" "$PROJECT_SOURCE"`
- 切换失败时继续使用当前分支

**单分支或非 Git 项目**：跳过交互，自动使用 CURRENT_BRANCH。

### 第三步：项目预扫描（3 个脚本按顺序执行）

分支选择完成后，继续执行以下 3 个脚本：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/java/project-scan.sh" "$PROJECT_DIR"
# 输出：PROJECT_TYPE=maven-single|maven-multi|... MODULE:模块名|相对路径|Java文件数|代码行数 TECH_STACK:技术栈|dependency:命中依赖|dimensions:建议维度|rules:专项规则

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出：CODE_INTELLIGENCE_AVAILABLE=true|false CODE_INTELLIGENCE_PROVIDER=jdtls-lsp|none CODE_INTELLIGENCE_REASON=...

bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-lark-plugin.sh"
# 输出：LARK_PLUGIN_INSTALLED=true|false，失败时附带 LARK_PLUGIN_REASON
```

> ⚠️ 3 个脚本必须全部执行完成后才能继续。此阶段禁止调用 AskUserQuestion，禁止输出任何交互式提问。

### 第三步之后：语言探测与路由

预扫描脚本执行前，先识别候选语言：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-language.sh" "$PROJECT_DIR"
# 输出：CANDIDATE_LANGUAGE:java|evidence=... 和/或 CANDIDATE_LANGUAGE:frontend|evidence=... 或 CANDIDATE_LANGUAGE:none
```

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

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/detect-project.sh" "$PROJECT_DIR"
# 不支持（nextjs/nuxt/generic-tsjs）时停止，不套用 React 规则

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/scan-project.sh" "$PROJECT_DIR"
# 输出 PROFILE_SCHEMA v1：SOURCE_FILE_COUNT/SOURCE_LINE_COUNT/FORMAL_CONFIG_FILE_COUNT/COMPONENT/TECH_STACK/SOURCE_SCOPE

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出 CODE_INTELLIGENCE_PROVIDER=typescript-lsp|none（覆盖 scan-project 的占位）
# 主 skill 据此派生 SEMANTIC_LEVEL：CODE_INTELLIGENCE_PROVIDER=typescript-lsp → SEMANTIC_LEVEL=typescript-lsp；否则 SEMANTIC_LEVEL=none

bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-lark-plugin.sh"
# 复用 lark-cli 检测
```

> 前端分支下，后续交互步骤（模式/报告/入口/范围/确认）、增量预处理（phase5）、模型侦测（phase14）、分批、合并、报告保存、飞书输出**全部复用现有流程**；差异仅在：预扫描数据来自前端 PROFILE，`SEMANTIC_LEVEL` 从 `CODE_INTELLIGENCE_PROVIDER` 派生（`typescript-lsp`/`none`，非 Java 的 `jdtls-lsp`/`maven-static`），分批用 `scripts/core/plan-file-batches.sh` + source manifest，合并用 `scripts/core/merge-batch-results.sh`，子 agent 用 `cc-code-reviewer-frontend`。

### 第三步之后：读取项目级 ignore 规则

3 个预扫描脚本完成后，在输出预扫描摘要前，检查项目内是否存在 AI 指令型 ignore 文件：

```bash
IGNORE_RULES_PATH="$PROJECT_DIR/.cc-code-reviewer/ignore/issues.yml"
```

读取规则：
- 文件存在且可读：读取完整内容到 `IGNORE_RULES_CONTENT`，设置 `IGNORE_RULES_ENABLED=true`，统计 `ignore:` 下一级规则条目数到 `IGNORE_RULE_COUNT`
- 文件不存在：设置 `IGNORE_RULES_ENABLED=false`、`IGNORE_RULES_CONTENT=""`、`IGNORE_RULE_COUNT=0`
- 文件存在但不可读：设置 `IGNORE_RULES_ENABLED=false`、`IGNORE_RULE_COUNT=0`，在预扫描摘要中提示不可读原因，但不得阻塞扫描
- 只统计 `ignore:` 下缩进 2 个空格的 `- name:` 规则项数量用于展示；不得统计 `applies_to:` 下缩进更深的子列表项
- 不做脚本级过滤，不校验规则语义；过滤由 scan agent 基于 `skip_when` 语义执行

推荐统计方式：

```bash
IGNORE_RULE_COUNT="$(
  awk '
    /^ignore:[[:space:]]*$/ { in_ignore=1; next }
    in_ignore && /^[^[:space:]]/ { in_ignore=0 }
    in_ignore && /^  -[[:space:]]+name:/ { count++ }
    END { print count + 0 }
  ' "$IGNORE_RULES_PATH"
)"
```

ignore 文件格式定义在 `references/ignore-workflow.md`。该文件是 AI 指令型 ignore 文件，不存报告编号，只描述同类问题的跳过规则。

### 第四步：输出预扫描摘要（不允许跳过）

3 个脚本全部完成后，必须输出以下格式的摘要（这是预扫描阶段的唯一输出）：

```
🔍 预扫描完成

📂 项目：{项目名称}
- 来源：{PROJECT_SOURCE 对应展示，本地路径 / Git仓库缓存}
- 路径：{PROJECT_DIR}
- 类型：{PROJECT_TYPE 展示名，如 Maven 单模块 / Gradle 多模块 / 未知}

🌿 Git：{IS_GIT_REPO=true 时显示}
- 当前分支：{CURRENT_BRANCH}
- 可用分支：{分支数量} 个{分支数 > 1 时显示"（需选择）"，否则显示"（自动使用）"}

📊 规模：
{LANGUAGE_ID=java 时}
- Java 文件（src/main/java）：{N} 个
- 代码行数（src/main/java）：{M} 行
{多模块时追加以下行}
- 模块数量：{K} 个
- 模块列表：{模块1名称}({n1}类), {模块2名称}({n2}类), ...
{LANGUAGE_ID=frontend 时}
- 前端源码文件（src 下 .ts/.tsx/.js/.jsx）：{SOURCE_FILE_COUNT} 个
- 代码行数：{SOURCE_LINE_COUNT} 行
- 配置文件：{FORMAL_CONFIG_FILE_COUNT} 个

🧩 技术栈扫描：
- 识别数量：{解析 `TECH_STACK:` 行数量；未识别专项技术栈时显示 0}
- 启用专项规则：{识别到专项技术栈时显示 "是"，否则显示 "否，仅启用通用{LANGUAGE_ID=java 时显示 Java，frontend 时显示前端}审查规则"}

{识别到 TECH_STACK 且 dependency != none 时展示以下表格，最多展示 12 个}
| 技术栈 | 识别证据 | 建议维度 | 专项规则 |
|--------|----------|----------|----------|
| {技术栈名称} | {dependency，若为 file: 前缀则展示为 文件:{路径}} | {dimensions} | {rules} |

{超过 12 个时追加}
- 另有 {N} 个技术栈未在摘要表中展示，完整结果已注入子 agent。

{未识别专项技术栈时展示}
- 未识别专项技术栈，仅启用通用{LANGUAGE_ID=java 时显示 Java，frontend 时显示前端}审查规则。

🔌 lark-cli：{LARK_PLUGIN_INSTALLED=true 时显示 "✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书保存" / false 时显示 "⚠️ 飞书保存不可用：{LARK_PLUGIN_REASON}，报告将仅保存到本地文件"}

🧠 代码智能：{LANGUAGE_ID=java 时，CODE_INTELLIGENCE_AVAILABLE=true 显示 "✅ jdtls-lsp 可用，可用于跨目录调用链理解" / false 显示 "⚠️ 未启用 jdtls-lsp，将使用 Maven 静态依赖分批；建议安装 jdtls 并启用 jdtls-lsp 提升跨模块理解质量"}{LANGUAGE_ID=frontend 时，CODE_INTELLIGENCE_PROVIDER=typescript-lsp 显示 "✅ typescript-lsp 可用，可用于跨目录调用链理解" / none 显示 "⚠️ 未启用 typescript-lsp，将使用 import graph + 配置 + 文本检索静态分析；建议启用 typescript-lsp 提升跨文件理解质量"}

🧩 项目 ignore：{IGNORE_RULES_ENABLED=true 时显示 "✅ 已启用：.cc-code-reviewer/ignore/issues.yml（已忽略 {IGNORE_RULE_COUNT} 个问题）" / false 且文件不存在时显示 "未配置" / false 且不可读时显示 "⚠️ 文件存在但不可读：{原因}"}
```

**技术栈扫描展示规则**：
- 数据来源：{LANGUAGE_ID=java 时为 phase3 输出；LANGUAGE_ID=frontend 时为前端 scan-project.sh 输出}中的 `TECH_STACK:{技术栈}|dependency:{命中依赖或 file:路径}|dimensions:{建议维度}|rules:{专项规则}` 行
- 必须逐行解析所有 `TECH_STACK:` 行，`PROJECT_SCAN_RESULT` 注入子 agent 时仍保留完整原文
- `dependency:none` 表示未识别专项技术栈，不展示表格，只展示通用审查规则提示
- `dependency:file:` 表示通过配置文件识别，摘要中的识别证据展示为 `文件:{路径}`
- 识别证据超过 80 字可截断，但不得截断技术栈名称、建议维度和专项规则
- 摘要表最多展示 12 个技术栈；超过 12 个时追加 `另有 {N} 个技术栈未在摘要表中展示，完整结果已注入子 agent。`

### 第四步之后：选择审查模型 + 上下文窗口侦测

**时机**：在步骤 4B（选择存量审查方式）之后、分批判定之前执行。

**先探测三个角色的上下文窗口**（用于动态推荐，不阻塞）：

```bash
for role in opus sonnet haiku; do
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/detect-model-context.sh" "$role"
done
```
解析每个角色的 `CONTEXT_WINDOW_TOKENS`、`CONTEXT_SCALE`、`ACTUAL_MODEL_NAME`。**把「（推荐）」标给 `CONTEXT_WINDOW_TOKENS` 最大的角色**——上下文窗口最大的模型能一次审查更多代码、减少分批，且通常是配置里质量最强的档位。若多个角色窗口相同，优先级 opus > sonnet > haiku。

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择审查使用的 AI 模型"
- header: "审查模型"
- options（按 opus / sonnet / haiku 顺序，仅窗口最大的那个标「（推荐）」；description 必须带实际底层模型名 + 窗口大小）:
  - label: "opus（推荐）" 或 "opus"  ← 窗口最大时标推荐
    description: "{ACTUAL_MODEL_NAME}，{CONTEXT_WINDOW_TOKENS} tokens 上下文，最强推理，适合深度/大仓库审查"
  - label: "sonnet（推荐）" 或 "sonnet"  ← 窗口最大时标推荐
    description: "{ACTUAL_MODEL_NAME}，{CONTEXT_WINDOW_TOKENS} tokens 上下文，平衡速度与质量"
  - label: "haiku（推荐）" 或 "haiku"  ← 窗口最大时标推荐
    description: "{ACTUAL_MODEL_NAME}，{CONTEXT_WINDOW_TOKENS} tokens 上下文，最快速度，适合快速扫雷或小项目"
- multiSelect: false

> 示例：若 opus=glm-5.2[1M](1M)、sonnet=glm-5-turbo(200k)、haiku=glm-4.7(200k)，则 opus 窗口最大，标「opus（推荐）」，description 写「glm-5.2，1000000 tokens 上下文，最强推理…」。

**用户响应后变量赋值**：
- 选哪个角色 → REVIEW_MODEL = 该角色（opus / sonnet / haiku）

**用户选定后，复用上一步已探测的该角色窗口数据**设置 `CONTEXT_WINDOW_TOKENS`、`CONTEXT_SCALE`、`CONTEXT_TIER`、`ACTUAL_MODEL_NAME`、`DETECTION_SOURCE`（无需再跑一次 phase14）。若用户选的角色上一步未探测（异常情况），则补跑一次 `core/detect-model-context.sh "$REVIEW_MODEL"`。

> **设计依据**：模型选择放在分批之前，是因为分批预算（每批装多少代码）依赖模型的上下文窗口大小。大窗口模型（1M）可一次性审查 5 倍代码量，显著减少批次数。动态推荐窗口最大的角色，避免向用户推荐「逻辑档位中等但实际配置最弱」的模型。

### 第四步之后：分批判定

**时机**：在模型选择 + 上下文窗口侦测完成后、步骤 5 前执行判定。

**公式**（分批阈值随 CONTEXT_SCALE 缩放，大窗口下更少项目进入分批）：
```
estimated_tokens = REVIEW_FILE_COUNT × 500 + REVIEW_LINE_COUNT × 3
BATCH_MODE = REVIEW_TYPE = 存量审查 AND (
  estimated_tokens > (100000 × CONTEXT_SCALE)
  OR STOCK_REVIEW_STRATEGY=module-sequential
  OR STOCK_REVIEW_STRATEGY=ai-planned
)
```

**前提**：分批模式仅对存量审查生效。增量审查的变更文件数通常远低于阈值；即使超过阈值，batch agent 缺少增量上下文（GIT_LOG/CHANGED_FILES），无法判断问题是变更引入还是存量，因此不进入分批。

**参数来源**：
- `REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT` 的来源按语言分支：
  - `LANGUAGE_ID=java`：从 phase3-project-scan.sh 输出中解析（`Java文件总数` 和 `代码总行数`），口径仅包含 `src/main/java` 生产源码
  - `LANGUAGE_ID=frontend`：从前端 `scan-project.sh` 输出的 PROFILE_SCHEMA 行解析（`SOURCE_FILE_COUNT` 和 `SOURCE_LINE_COUNT`），口径仅包含 `src/` 下生产 `.ts/.tsx/.js/.jsx`
- `500`：每个文件的工具调用 + agent 评估开销（token）
- `3`：每行代码平均 token 数
- `100000 × CONTEXT_SCALE`：单批留给文件内容 + 开销的上限。基准 100000（200k 总上下文 - 25k 系统 prompt - 50k agent 输出 ≈ 125k，取 100k 留余量），大窗口模型按 CONTEXT_SCALE 同比放大

**判定结果**：
- `BATCH_MODE=false` → 走现有单 agent 流程，不做任何改动
- `BATCH_MODE=true` → 进入分批模式

**执行要求**：分批判定至少延迟到步骤 3 确定审查入口后执行；如果审查范围会影响 `REVIEW_FILE_COUNT` / `REVIEW_LINE_COUNT`，必须在步骤 4 确定范围后按所选范围重新计算。

### Maven 大仓库模式判定

仅当以下条件全部满足时进入 Maven 大仓库模式：
- `PROJECT_TYPE=maven-multi`（Maven 多模块）
- `REVIEW_TYPE=存量审查`
- `REVIEW_SCOPE=全量代码` 或 指定模块路径列表
- `STOCK_REVIEW_STRATEGY=ai-planned` 或 `module-sequential`
- `TOTAL_JAVA_LOC >= 120000`，或用户已在存量审查方式中明确选择分批策略

只要 `PROJECT_TYPE=maven-multi` 且用户已经选择 `STOCK_REVIEW_STRATEGY=ai-planned` 或 `module-sequential`，就必须进入 Maven 大仓库模式。即使只选择一个模块、即使所选模块低于 `TOTAL_JAVA_LOC >= 120000` 自动阈值，也必须调用 `languages/java/plan-large-batches.sh`，并把 `REVIEW_SCOPE` 原样作为第 5 个参数传入。Maven 多模块存量分批绝不调用 `languages/java/plan-file-batches.sh`；该文件级 planner 只服务 Maven 单模块、Gradle 或未知 Java 项目。

判定公式（以下为 CONTEXT_SCALE=1 即 200k 窗口下的基准值；实际值 = 基准值 × CONTEXT_SCALE）：
```text
TOTAL_JAVA_LOC >= 120000
TARGET_BATCH_LOC = 50000            # 基准，实际 = 50000 × CONTEXT_SCALE
SOFT_MIN_BATCH_LOC = 30000
SOFT_MAX_BATCH_LOC = 50000
HARD_MAX_BATCH_LOC = 50000
review_cost = java_loc + java_file_count * 25
TARGET_BATCH_COST = 52000           # 基准，实际 = 52000 × CONTEXT_SCALE
SOFT_MIN_BATCH_COST = 32000
SOFT_MAX_BATCH_COST = 60000
HARD_MAX_BATCH_COST = 65000
```

**CONTEXT_SCALE 缩放机制**：批次成本与 LOC 上限按模型上下文窗口缩放。`CONTEXT_SCALE` 由 `core/detect-model-context.sh` 探测得出：1M 窗口（如 `glm-5.2[1M]`）→ scale=5，单批可装 5 倍代码；200k 窗口 → scale=1（与旧行为一致）。调用 `languages/java/plan-large-batches.sh` 时须把 `CONTEXT_SCALE` 作为第 7 个参数传入；文件级 planner 通过 `CC_REVIEW_CONTEXT_SCALE` 环境变量接收。

Maven 大仓库规划使用 semantic-cost batching：
- 先生成 work units，而不是直接把顶层 Maven module 当批次
- 超过 `HARD_MAX_BATCH_LOC` 或 `HARD_MAX_BATCH_COST` 的 work unit 必须继续拆分；oversized modules are split before plan emission
- 优先按嵌套 Maven 子模块拆分，仍超限时按稳定 Java package root 拆分
- 0 行依赖/BOM 模块与极小 bootstrap 模块默认进入 `context_roots`，不单独成批
- tiny tail batches 必须合并、转为 context，或写明无法合法合并的原因
- `context_roots` 只用于理解，受 context cost 上限约束，不计入 Java 文件覆盖率

Maven 大仓库模式仍然只对存量审查生效。增量审查、Gradle 项目、单模块项目继续走现有流程。指定模块审查可以进入 Maven 大仓库模式：`ai-planned` 使用 semantic-cost batching 在所选模块内智能拆分，`module-sequential` 按所选模块依次启动批次；模块过大时必须提醒用户但不阻断。

Maven 大仓库模式必须在步骤 1 确定 `REVIEW_MODE` 且步骤 3/4 确定审查入口与范围后、步骤 5 选择本轮执行批次前完成规划；规划完成后必须立即展示分批表格和推荐计划，再进入 AskUserQuestion。

批次状态值固定为：
```text
pending 待执行
running 执行中
completed 已完成
failed 失败待重试
```

如果发现兼容的未完成 `RUN_DIR`，必须先读取 `plan.json` 并展示状态表。恢复时：
- `completed` 批次默认跳过，不重跑
- `running` 批次一律转为 `failed`，错误写为"上次执行中断，需要整批重跑"
- `pending` 和 `failed` 批次按用户本轮执行批次数调度
- 重新规划必须由用户明确选择，并创建新的 `RUN_DIR`

`RUN_DIR` 目录名固定为 `{YYYYMMDD-HHMMSS}-{branch_slug}-{REVIEW_MODE}`，例如 `20260603-143000-master-deep`。目录名不得包含审查范围、分批策略、`large-maven` 或 `file-batches` 后缀；审查范围、分批策略和任务类型必须从 `plan.json` 读取。

规划命令：
```bash
SEMANTIC_LEVEL="maven-static"
if [ "$CODE_INTELLIGENCE_AVAILABLE" = "true" ]; then
  SEMANTIC_LEVEL="jdtls-lsp"
fi

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/java/plan-large-batches.sh" "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "$SEMANTIC_LEVEL" "$REVIEW_SCOPE" "$STOCK_REVIEW_STRATEGY" "$CONTEXT_SCALE"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

### 第五步：交互式参数收集

按以下步骤逐个调用 **AskUserQuestion 工具**（禁止用纯文本输出替代）。每个步骤必须单独调用 AskUserQuestion 并等待用户响应后才能进入下一步。**禁止在一次回复中合并多个交互步骤。**

**注意**：分支选择已在第二步（项目识别与分支检测）完成，本步骤从选择审查类型开始。

详细步骤定义见下方「交互式确认步骤定义」章节。

### 第六步之前：准备审查参考文件路径

在调用子 agent 之前，必须基于插件根目录生成参考文件绝对路径，并校验文件可读：

```bash
REPORT_FORMAT_PATH="${CLAUDE_PLUGIN_ROOT}/references/report-format.md"
if [ "$LANGUAGE_ID" = "frontend" ]; then
  REVIEW_FRAMEWORK_PATH="${CLAUDE_PLUGIN_ROOT}/references/languages/frontend/review-framework.md"
  REACT_RULES_PATH="${CLAUDE_PLUGIN_ROOT}/references/languages/frontend/react-rules.md"
  SOURCE_SCOPE_PATH="${CLAUDE_PLUGIN_ROOT}/references/languages/frontend/source-scope.md"
  test -r "$REVIEW_FRAMEWORK_PATH"
  test -r "$REACT_RULES_PATH"
  test -r "$SOURCE_SCOPE_PATH"
else
  REVIEW_FRAMEWORK_PATH="${CLAUDE_PLUGIN_ROOT}/references/languages/java/review-framework.md"
  test -r "$REVIEW_FRAMEWORK_PATH"
fi
test -r "$REPORT_FORMAT_PATH"
```

如果任一文件不存在或不可读，必须终止并输出缺失路径，不得调用子 agent。禁止只依赖 `../references/...` 这类相对路径启动子 agent。

### 第七步：调用子 agent 执行代码审查

**分支判断**：
- BATCH_MODE=false → 执行「路径 A：单 agent 模式」（子 agent 只审查+落盘报告，飞书上传由主 skill 接管）
- BATCH_MODE=true → 执行「路径 B：分批并行模式」（子 agent 仅输出发现清单，合并与上传由主 skill 处理）

#### 路径 A：单 agent 模式（BATCH_MODE=false）

使用 Task 工具启动子代理，子代理类型按 `LANGUAGE_ID` 选择：
- `LANGUAGE_ID=java` → subagent_type: `"cc-code-reviewer:cc-code-reviewer"`，description: `"执行 Java 代码审查"`
- `LANGUAGE_ID=frontend` → subagent_type: `"cc-code-reviewer:cc-code-reviewer-frontend"`，description: `"执行前端代码审查"`
- prompt: 注入审查参数表 + 审查参考文件路径 + 项目概况 + 增量数据
- model: {REVIEW_MODEL}

详细参数注入格式见下方「子 agent 调用规范」章节。

#### 路径 B：分批并行模式（BATCH_MODE=true）

使用 Agent 工具启动多个 `cc-code-reviewer` 子代理，按轮次并发执行。

**编排逻辑**：

如果当前为 Maven 大仓库模式，主 skill 必须先根据 `CURRENT_RUN_BATCH_LIMIT` 或 `BATCH_SELECTION` 计算本轮 `RUN_BATCH_IDS`：
- `BATCH_SELECTION` 存在时，只调度该列表中的批次
- `CURRENT_RUN_BATCH_LIMIT=3|5|10` 时，只调度状态表顺序中前 N 个 `pending` / `failed` 批次
- `CURRENT_RUN_BATCH_LIMIT=all` 时，调度全部 `pending` / `failed` 批次
- `completed` 批次永远不进入 `RUN_BATCH_IDS`
- 后续启动、预估耗时和合并文案都必须使用 `RUN_BATCH_IDS` / `RUN_BATCH_COUNT`，不得用总 `BATCH_COUNT` 代替本轮执行批次

以 CONCURRENCY=2、BATCH_COUNT=6 为例：

```
轮次 1：同时启动 Agent(batch-1) + Agent(batch-2)
  → 等待全部完成
轮次 2：同时启动 Agent(batch-3) + Agent(batch-4)
  → 等待全部完成
轮次 3：同时启动 Agent(batch-5) + Agent(batch-6)
  → 等待全部完成
```

每轮同时发出 CONCURRENCY 个 Agent 工具调用。当前轮所有 agent 返回后，开始下一轮。CONCURRENCY=1 时退化为串行。

**每个 batch agent 的调用参数**：

- description: "Batch {BATCH_INDEX}/{BATCH_COUNT} 代码审查"
- subagent_type: 按 `LANGUAGE_ID` 选择（`java` → `cc-code-reviewer:cc-code-reviewer`；`frontend` → `cc-code-reviewer:cc-code-reviewer-frontend`）
- model: {REVIEW_MODEL}
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
| 审查模型 | {REVIEW_MODEL} |
| 审查文件数量 | {BATCH_FILE_COUNT} |
| 审查代码行数 | {BATCH_LINE_COUNT} |
| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |
| React 规则路径 | {REACT_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| 源码范围路径 | {SOURCE_SCOPE_PATH}（仅 LANGUAGE_ID=frontend） |
| 报告格式路径 | {REPORT_FORMAT_PATH} |
| 项目 ignore 文件路径 | {IGNORE_RULES_PATH 或 未配置} |
| 项目 ignore 是否启用 | {IGNORE_RULES_ENABLED} |
| 项目 ignore 问题数量 | {IGNORE_RULE_COUNT} |
| 运行目录 | {RUN_DIR} |
| 批次计划文件 | {BATCH_PLAN_PATH} |
| 批次状态文件 | {BATCH_STATUS_PATH} |
| 批次结果文件 | {BATCH_RESULT_PATH}（对应 RUN_DIR/results/batch-XXX.md） |
| 批次编号 | {BATCH_INDEX}/{BATCH_COUNT}（仅旧批次模式） |
| 语义增强 | {SEMANTIC_LEVEL} |
| 审查输出模式 | 仅发现清单 |

### 本批审查边界
请读取 `BATCH_PLAN_PATH`，以其中 `scan_roots` 作为正式审查边界。
若批次计划包含 `units`，以 `units[].path` / `units[].scan_roots` 对应的 `scan_roots` 为准；`context_roots` are read-only context，只能用于理解依赖关系。

**LANGUAGE_ID=java 时**：
正式扫描文件必须限定为 `scan_roots` 内的 `src/main/java` 生产源码；`src/test/java` 只能作为测试质量判断的只读上下文，不计入已审查 Java 文件，也不得作为正式问题位置。
`SEMANTIC_LEVEL=jdtls-lsp` 时表示 jdtls-lsp 可用时必须使用：本批子 agent 必须用 jdtls 查询 definition、references、implementations、call hierarchy 来理解跨目录调用链，并在批次结果中写明「语义增强使用情况」。正式问题必须位于 `scan_roots` 内的 `src/main/java` 生产源码。
`SEMANTIC_LEVEL=maven-static` 时才允许回退 Maven 静态依赖与文本检索。

**LANGUAGE_ID=frontend 时**：
正式扫描文件必须限定为 `scan_roots` 内的 `src/` 下生产源码（`.ts/.tsx/.js/.jsx`）；测试文件（`*.test.*`/`*.spec.*`/`__tests__`/`e2e`/`cypress`）、产物（`dist`/`build`）、`.d.ts` 只能作为只读上下文，不计入已审查前端文件，也不得作为正式问题位置。
`SEMANTIC_LEVEL=typescript-lsp` 时必须用 TS LSP 查询 definition/references/implementations/diagnostics 理解跨目录调用链，并在批次结果中写明「语义增强使用情况」。正式问题必须位于 `scan_roots` 内的生产源码。
`SEMANTIC_LEVEL=none` 时才允许回退 import graph + 配置 + 文本检索静态分析。

如果疑似问题位置在 `scan_roots` 外，写入「跨批依赖待复核」。

### 项目概况（预扫描结果）
{PROJECT_SCAN_RESULT}

### 项目 ignore 规则（外部注入，直接使用）
{IGNORE_RULES_CONTENT；未启用时写 "未配置"}

请基于以上审查参数，立即开始执行代码审查。不要进行任何用户交互或询问，直接从代码审查开始执行。
```

**关键差异**（对比路径 A 单 agent 调用）：

| 字段 | 单 agent（路径 A） | Batch agent（路径 B） |
|------|----------|-------------|
| 审查文件数量 | REVIEW_FILE_COUNT（总量） | BATCH_FILE_COUNT（本批） |
| 审查代码行数 | REVIEW_LINE_COUNT（总量） | BATCH_LINE_COUNT（本批） |
| 报告保存方式 | 不注入子 agent（飞书上传由主 skill 处理） | 不注入子 agent（飞书上传由主 skill 合并后处理） |
| 批次编号 | 无 | BATCH_INDEX/BATCH_COUNT |
| 审查输出模式 | 无（默认完整报告） | "仅发现清单" |
| 文件列表来源 | agent 自行 Glob | 外部注入，agent 不扫描 |
| 增量数据 | 注入 GIT_LOG 等 | 不注入（分批仅支持存量审查） |

**飞书保存**：batch agent 不执行飞书保存。飞书保存由主 skill 在合并完成后统一处理。

**错误处理**：

| 场景 | 处理方式 |
|------|----------|
| 某个 batch agent 超时/失败 | 该批次状态写为 `failed` 并记录错误；其余批次可以继续执行 |
| 本轮批次仍为 pending/running | 合并脚本等待本轮批次进入终态；等待超时后生成 `[合并阻塞]` 报告 |
| 本轮批次 failed 或 completed 但结果文件缺失 | 合并脚本不得静默跳过；生成 `[合并阻塞]` 报告，提示失败/缺失批次 |
| 非本轮批次未执行 | 合并脚本生成 `[阶段性]` 报告，并在批次状态总览中列为遗留 |

---

## 脚本调用顺序

脚本文件名不再带 phase 编号（功能名描述职责，执行顺序在此编排）。通用脚本在 `scripts/core/`，Java 专属在 `scripts/languages/java/`，前端专属在 `scripts/languages/frontend/`。旧 `scripts/phaseN-*.sh` 路径保留为兼容转发 wrapper。

### Java 扫描流程

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

### 前端扫描流程

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

---

## 交互式确认步骤定义

> **强制规则**：
> - 每个步骤必须调用 AskUserQuestion 工具，**禁止用纯文本提问替代**
> - 每个步骤的 AskUserQuestion 调用后，必须等待用户响应
> - 不允许在一次回复中包含多个交互步骤的动作
> - 用户响应后，处理结果、设置变量，然后才能进入下一步

> **注意**：分支选择已在第二步（项目识别与分支检测）完成，本步骤从选择审查模式开始；审查模式和报告保存方式必须在审查入口前确认。审查模型在步骤 5C 最后选择。

### 步骤 1：选择审查模式

当 `RUN_BATCH_COUNT>=2` 时，**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择审查模式"
- header: "审查模式"
- options:
  - label: "fast（仅输出 P0）"
    description: "只报告已证实、足以阻断上线的 P0；P1/P2/P3 和待确认项均不输出"
  - label: "standard（推荐）"
    description: "标准审查，覆盖常规核心维度 + API设计 + 缓存基础 + 核心测试缺失，日常迭代推荐"
  - label: "deep"
    description: "深度审查，全量 15 维度，适合大版本上线前"
  - label: "security"
    description: "安全专项，聚焦安全核心维度"
- multiSelect: false

**用户响应后变量赋值（必须归一化）**：
- fast（仅输出 P0） → REVIEW_MODE=fast
- standard（推荐） → REVIEW_MODE=standard
- deep → REVIEW_MODE=deep
- security → REVIEW_MODE=security

后续 planner、条件判断和子 agent 参数注入只能使用归一化后的 `REVIEW_MODE` 枚举，不得传递展示 label。

### 步骤 2：选择审查报告保存方式（条件步骤）

**触发条件**：LARK_PLUGIN_INSTALLED=true。不满足时跳过，设 FEISHU_UPLOAD_OPTION=本地 Markdown 报告。

报告保存方式为多选。用户可选择本地 Markdown 报告、飞书云文档和飞书多维表格中的任意一个或多个，支持任意组合多选。

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择审查报告的保存方式"
- header: "报告保存方式"
- options:
  - label: "本地 Markdown 报告"
    description: "生成并保存本地 Markdown 完整审查报告"
  - label: "飞书云文档"
    description: "审查报告保存到飞书云文档，聊天中显示精简摘要"
  - label: "飞书多维表格"
    description: "问题清单录入飞书多维表格，聊天中显示精简摘要"
- multiSelect: true

**用户响应后变量赋值**：
- 将用户选择的 label 按选择顺序写入 `FEISHU_UPLOAD_OPTION`，多个值用 `, ` 分隔
- 如果用户同时选择「飞书云文档」和「飞书多维表格」，后续执行云文档上传和多维表格创建两个步骤
- 如果用户只选择「本地 Markdown 报告」，不执行飞书保存步骤
- 即使用户未选择「本地 Markdown 报告」，scan agent 仍必须先生成并保存本地 Markdown 完整报告文件，作为上传和降级复用源

### 步骤 3：选择审查入口

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择本次审查入口"
- header: "审查入口"
- options:
  - label: "增量审查"
    description: "审查最近 N 次提交的变更文件及其关联代码"
  - label: "全量审查"
    description: "审查当前分支的全部代码，适合历史遗留项目或周期性巡检"
  - label: "指定模块"
    description: "只审查本次选择的一个或多个模块，适合大仓库分阶段推进"
- multiSelect: false

**变量赋值**：
- 增量审查 → REVIEW_ENTRY=增量审查，REVIEW_TYPE=增量审查
- 全量审查 → REVIEW_ENTRY=全量审查，REVIEW_TYPE=存量审查，REVIEW_SCOPE=全量代码
- 指定模块 → REVIEW_ENTRY=指定模块，REVIEW_TYPE=存量审查

### 步骤 4：选择审查范围（条件步骤）

**触发条件**：
- 增量审查时 → 必须执行
- 指定模块 + 多模块 → 必须执行
- 指定模块 + 单模块 → 跳过，自动设 REVIEW_SCOPE=全量代码
- 全量审查 → 跳过，已在步骤 3 设 REVIEW_SCOPE=全量代码

**增量审查时，必须先扫描并展示最近提交，再调用 AskUserQuestion 工具**：

1. 执行最近提交预览脚本（仅用于交互式用户决策，不替代后续增量预处理）：`bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/preview-recent-commits.sh" "$PROJECT_DIR"`
2. 展示脚本输出，格式如下；最多展示最近 10 次提交，不足 10 次时展示实际数量：
   ```text
   📜 最近提交概览：
   # === 最近提交预览 ===
   1. {short_hash} {commit message}
   2. {short_hash} {commit message}
   ...
   ```
3. 如果输出为 `（无提交记录）`，告知用户当前 Git 仓库没有可用于增量审查的提交，不进入提交次数选择。

**然后必须调用 AskUserQuestion 工具，参数如下**：
- question: "审查最近几次提交的变更？"
- header: "提交次数"
- options:
  - label: "最近 1 次"
    description: "仅审查列表中的第 1 条提交"
  - label: "最近 3 次"
    description: "审查列表中的第 1-3 条提交"
  - label: "最近 5 次（推荐）"
    description: "审查列表中的第 1-5 条提交"
  - label: "最近 10 次"
    description: "审查列表中的第 1-10 条提交"
- multiSelect: false

**指定模块 + 多模块时，先展示模块树，再调用 AskUserQuestion 工具**：

**展示模块树**（在调用 AskUserQuestion 之前，用文本输出；完整模块列表只能作为普通文本展示，不得放入 AskUserQuestion options）：
```
📊 项目模块概览：

{项目名称}/
├── {模块1名称}/     {N} 类 · {M} 行
├── {模块2名称}/     {N} 类 · {M} 行
└── {模块3名称}/     {N} 类 · {M} 行

合计：{总类数} 类 · {总行数} 行
```

数据来源：解析阶段四预扫描输出的 `MODULE:` 行，提取每个模块的名称、Java 文件数、代码行数。

**AskUserQuestion payload 约束**：
- 不得把每个模块都作为 AskUserQuestion option；大仓库模块数量可能很多，容易触发 Invalid tool parameters
- 该步骤最多 3 个固定选项，模块路径通过 Other/free-form 或后续输入步骤收集
- 模块列表越长，越应该只在普通文本概览中展示，并引导用户输入模块相对路径

**然后调用 AskUserQuestion 工具，参数如下**：
- question: "请选择本次希望 AI 扫描的模块"
- header: "扫描模块"
- options:
  - label: "全部模块"
    description: "扫描当前多模块项目的全部模块"
  - label: "手动输入模块路径"
    description: "在 Other/free-form 中输入一个或多个模块相对路径，逗号分隔"
  - label: "前 5 个大模块"
    description: "按 Java 行数选择预扫描结果中最大的 5 个模块，适合先覆盖主要复杂度"
- multiSelect: false

**指定模块 + 多模块用户响应后**：
- 选择"全部模块" → REVIEW_SCOPE=全量代码
- 选择"前 5 个大模块" → REVIEW_SCOPE=按 `MODULE:` 行 Java 行数降序取前 5 个模块路径，逗号分隔
- 选择"手动输入模块路径" 或 Other/free-form → 读取用户提供的模块相对路径，支持逗号、中文逗号、顿号、空格或换行分隔多个模块；若 AskUserQuestion 当前交互没有返回自定义文本，追加一次 AskUserQuestion 收集模块路径，header 使用 "输入模块"，仍只提供固定选项并要求用户在 Other/free-form 填写模块路径
- 模块路径必须是 `PROJECT_DIR` 内的相对路径；不得接受绝对路径、`..` 路径穿越或解析后位于项目根之外的路径，规划脚本必须以 `SELECTED_MODULE_OUTSIDE_PROJECT` 阻止越界输入
- 自定义模块路径必须逐个校验是否存在于预扫描结果的 `MODULE:` 行中；不存在时提示有效模块列表并重新收集，最多重试 3 次

**变量赋值**：
- 全部模块 → REVIEW_SCOPE=全量代码
- 前 5 个大模块 → REVIEW_SCOPE=模块路径（逗号分隔）
- 自定义模块路径 → REVIEW_SCOPE=模块路径（逗号分隔）

### 步骤 4B：选择存量审查方式（条件步骤）

**触发条件**：
- REVIEW_TYPE=存量审查
- PROJECT_TYPE=maven-multi

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择存量审查方式"
- header: "审查方式"
- options:
  - label: "按所选模块依次启动"
    description: "每个所选模块对应一个批次；模块过大时提醒但不阻断，适合按业务域推进"
  - label: "AI 智能规划分批"
    description: "按语义单元和 review cost 自动拆分，适合超大模块或希望批次更均衡时使用"
- multiSelect: false

**变量赋值**：
- 按所选模块依次启动 → STOCK_REVIEW_STRATEGY=module-sequential
- AI 智能规划分批 → STOCK_REVIEW_STRATEGY=ai-planned

当用户选择 `module-sequential` 且任一所选模块超过 `HARD_MAX_BATCH_LOC` 或 `HARD_MAX_BATCH_COST` 时，必须在确认计划前提示该模块为大批次，可能耗时更长或消耗更多 token，但不得阻断执行。

### 步骤 5：选择本轮执行批次（Maven 大仓库模式）

**触发条件**：满足「Maven 大仓库模式判定」。不满足时跳过此步骤。

触发此步骤前，必须先完成 Maven 大仓库分批规划，生成或恢复 `RUN_DIR/plan.json` 和 `RUN_DIR/batches/*.json`。

在调用 AskUserQuestion 之前，必须先展示当前 run 状态、批次表、可执行批次和预估时间计划。`core/show-batch-status.sh` 只作为数据来源；不得只依赖 Bash 工具输出，因为 Claude Code 会折叠工具输出，导致用户必须按 `ctrl+o` 才能看到。主 skill 必须读取脚本输出，并在普通助手消息中重新展示完整 Markdown 表格和推荐计划，像技术栈扫描摘要一样直接展示给用户。
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

该输出必须包含：
- 批次状态表：使用用户可见的 Markdown 表格，表头固定为 `| 批次 | 状态 | 行数 | 文件数 | 模块 |`，下一行必须为 `|------|------|------:|------:|------|`
- 模块列必须使用缩略名展示；当同一批次内模块存在共同工程前缀（例如 `yudao-module-`）时，去掉共同前缀，只展示真正的业务模块含义名称，例如 `trade-server,statistics-api`。
- 本轮可执行批次：`pending` 和 `failed` 批次；`completed` 批次只展示不调度
- 推荐执行计划：必须根据本轮可执行批次数动态生成，不能固定展示 3 / 5 / 10 批选项
- 预估耗时：按当前 `REVIEW_MODE` 和 1 / 2 / 3 路并发给出参考
- 自行输入批次号提示：允许用户根据表格在 Other/free-form 中输入若干批次号，例如 `batch-002,batch-004` 或 `2,4,7`

**展示要求**：
- 普通助手消息必须包含 `大仓库审查任务` 摘要、Markdown 批次表、`本轮可执行批次` 和 `推荐执行计划`。
- 批次表不得放入代码块，不得只留在 Bash 工具输出中，不得只说“分批规划完成，展示批次状态”。
- 可以保留 Bash 工具调用用于读取数据，但用户可见的表格必须由主 skill 重新输出。

**动态选项规则**：
- 先从状态表计算 `RUNNABLE_BATCH_IDS` 和 `RUNNABLE_COUNT`，只包含 `pending` / `failed` 批次。
- `RUNNABLE_COUNT=0` → 不调用 AskUserQuestion；输出没有可执行批次，进入合并或结束提示。
- `RUNNABLE_COUNT=1` → 不调用 AskUserQuestion；自动设置 `RUN_BATCH_IDS` 为唯一可执行批次，`RUN_BATCH_COUNT=1`，直接进入步骤 5B 选择并发数。
- `RUNNABLE_COUNT=2` → options 只包含 `执行 1 批`、`执行全部 2 批（推荐）` 和 Other/free-form；不得出现 `执行 3 批`、`执行 5 批` 或 `执行 10 批`。
- `RUNNABLE_COUNT=3` → options 只包含 `执行 1 批`、`执行 2 批`、`执行全部 3 批（推荐）` 和 Other/free-form；不得出现 `执行 5 批` 或 `执行 10 批`。
- `RUNNABLE_COUNT=4|5` → options 只包含 `执行 2 批`、`执行 3 批（推荐）`、`执行全部 {RUNNABLE_COUNT} 批` 和 Other/free-form。
- `RUNNABLE_COUNT=6..10` → options 只包含 `执行 3 批`、`执行 5 批（推荐）`、`执行全部 {RUNNABLE_COUNT} 批` 和 Other/free-form；不得出现 `执行 10 批`。
- `RUNNABLE_COUNT>10` → options 只包含 `执行 3 批`、`执行 5 批（推荐）`、`执行 10 批`、`执行全部 {RUNNABLE_COUNT} 批` 和 Other/free-form。
- 固定选项描述中的批次数和预估耗时必须使用实际 `RUNNABLE_COUNT` 截断后的数量；不得出现“执行 5 批”但描述里又显示“最多 3 批”。

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择本轮执行批次"
- header: "执行批次"
- options: 按上方「动态选项规则」生成，不得写死 3 / 5 / 10 / 全部四个选项
- multiSelect: false

**用户响应后**：
- 固定选项 → 设置 `CURRENT_RUN_BATCH_LIMIT` 为该选项对应的实际批次数，`执行全部 {RUNNABLE_COUNT} 批` 设置为 `all`
- Other/free-form 批次号 → 设置 `BATCH_SELECTION` 为用户输入的批次号列表；支持 `batch-002,batch-004`、`2,4,7`、空格或中文顿号/逗号分隔
- 解析 `BATCH_SELECTION` 时必须标准化为 `batch-XXX` 格式，并校验这些批次存在且状态为 `pending` 或 `failed`
- 输入包含不存在、已完成或执行中的批次时，不得继续执行；必须再次调用 AskUserQuestion 让用户重新选择
- `completed` 批次必须跳过
- 固定选项只调度状态表顺序中前 N 个 `pending` / `failed` 批次；未调度批次保持 `pending`

### 步骤 5B：选择并发数（条件步骤）

**触发条件**：BATCH_MODE=true。不满足时跳过此步骤。

**前置计算**：触发此步骤前，必须先完成分批计算（见「分批计算」章节），得到 BATCH_COUNT。
- 若 `PROJECT_TYPE=maven-multi` 且 `STOCK_REVIEW_STRATEGY=module-sequential|ai-planned`，必须先完成 Maven 大仓库模式的步骤 5 批次表展示和本轮执行批次选择；不得改走文件级 planner。
- 若不满足 Maven 大仓库模式但 `BATCH_MODE=true`（包括 Maven 单模块、Gradle 或其他 Java 项目），必须先调用 `languages/java/plan-file-batches.sh` 生成文件级批次，并把脚本输出的 `简要分批计划` 原样展示到控制台；不得只输出总批次数后直接询问并发数。

在调用 AskUserQuestion 之前，先输出并发策略摘要：
```
📊 分批并行扫描

本轮将执行：{RUN_BATCH_COUNT 或 BATCH_COUNT} 批
总批次数：{BATCH_COUNT} 批
生产代码行数：{REVIEW_LINE_COUNT 或 TOTAL_JAVA_LOC} 行
```

并发数必须小于等于本轮实际执行批次数，即 `CONCURRENCY <= RUN_BATCH_COUNT`。生成并发选项前必须先计算 `RUN_BATCH_COUNT`：
- Maven 大仓库模式：根据步骤 5 的 `RUN_BATCH_IDS` 得到 `RUN_BATCH_COUNT`
- 文件级分批模式：默认 `RUN_BATCH_COUNT=BATCH_COUNT`
- 如果用户通过 Other/free-form 选择具体批次，`RUN_BATCH_COUNT` 为标准化后有效批次号数量

**动态并发规则**：
- `RUN_BATCH_COUNT=1` → 不调用 AskUserQuestion；自动设置 `CONCURRENCY=1`，进入步骤 5C 选择审查模型。
- `RUN_BATCH_COUNT=2` → AskUserQuestion options 只包含 `串行执行（默认）` 和 `2 路并发`；不得出现 `3 路并发`。
- `RUN_BATCH_COUNT>=3` → AskUserQuestion options 包含 `串行执行（默认）`、`2 路并发`、`3 路并发`。
- 任意路径下都不得提供大于 `RUN_BATCH_COUNT` 的并发选项；例如只执行 1 批时不能展示 2 / 3 路，只执行 2 批时不能展示 3 路。

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择并发扫描策略"
- header: "并发数"
- options: 按上方「动态并发规则」生成
  - label: "串行执行（默认）"
    description: "逐批扫描，token 消耗最可控，约 {total_min} 分钟"
  - label: "2 路并发"
    description: "同时扫描 2 批，速度更快但 token 消耗更集中，约 {total_min} 分钟"
  - label: "3 路并发"
    description: "同时扫描 3 批，最大并发，token 消耗最快，约 {total_min} 分钟"
- multiSelect: false

**耗时预估公式**：
```
单批成本 = batch JSON 中的 planned_review_cost；缺失时回退 planned_java_loc + planned_java_file_count × 25
目标批次成本 = plan.json budget.target_batch_cost（随 CONTEXT_SCALE 缩放，基准 52000）
目标批次耗时 = fast 4 分钟 / standard 8 分钟 / deep 15 分钟 / security 10 分钟
单批耗时 = ceil(单批成本 × 目标批次耗时 / 目标批次成本)，最低 1 分钟
total_min = 将本轮批次按单批耗时贪心分配到 CONCURRENCY 条执行 lane 后的最大 lane 耗时
```

不得使用 `ceil(本轮执行批次数 / CONCURRENCY) × 大型项目固定耗时` 作为分批预估；固定模式耗时表是单 agent 参考，不适合作为每个 batch 的固定耗时。

**用户响应后变量赋值**：
- 串行执行（默认） → CONCURRENCY=1
- 2 路并发 → CONCURRENCY=2
- 3 路并发 → CONCURRENCY=3
- 并发数仅允许 `1..min(3, RUN_BATCH_COUNT)`，默认 `1`

### 步骤 5C：（已前移）

审查模型选择已前移到「第四步之后：选择审查模型 + 上下文窗口侦测」段（在分批判定之前执行），因为分批预算依赖模型上下文窗口大小。此处不再重复询问。

执行计划展示中的「审查模型」行直接引用前移步骤确定的 `REVIEW_MODEL`。

### 步骤 6：确认执行计划

先输出完整执行计划：

```
📋 执行计划：
- 项目路径：{PROJECT_DIR}
- 项目类型：{PROJECT_TYPE}
- 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}（仅 Git 项目显示）
- 审查类型：{REVIEW_TYPE}
- 审查范围：{REVIEW_SCOPE}
- 审查模式：{REVIEW_MODE}
- 输出级别：仅 P0  ← 仅 REVIEW_MODE=fast 时显示
- 审查模型：{REVIEW_MODEL}（{ACTUAL_MODEL_NAME}，{CONTEXT_WINDOW_TOKENS} tokens{CONTEXT_SCALE>1 时显示 "，缩放 {CONTEXT_SCALE}x"}）
- 启用维度：{根据模式 × 维度矩阵列出具体维度名称}
- 项目 ignore：{IGNORE_RULES_ENABLED=true 时显示 "已启用 .cc-code-reviewer/ignore/issues.yml（已忽略 {IGNORE_RULE_COUNT} 个问题）"；否则显示 "未配置"}
- 报告保存方式：{FEISHU_UPLOAD_OPTION}
- 扫描策略：分批并行扫描（本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} / 总 {BATCH_COUNT} 批 / {CONCURRENCY} 路并发）  ← 仅 BATCH_MODE=true 时显示
- 预计耗时：约 {total_min} 分钟  ← 仅 BATCH_MODE=true 时显示
```

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "确认以上执行计划后开始审查"
- header: "确认执行"
- options:
  - label: "确认执行"
    description: "按以上配置开始审查"
  - label: "取消"
    description: "取消本次审查"
- multiSelect: false

**用户确认后的启动提示**：

**BATCH_MODE=false 时**（子 agent 只审查+落盘报告，主 skill 接管飞书上传）：

```
🚀 正在启动独立代码审查子代理...

📋 任务配置：{REVIEW_MODE} 模式（{REVIEW_MODEL}） · {REVIEW_TYPE} · {REVIEW_SCOPE}
⏱️ 预估耗时：{预估时间}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。

{选择飞书输出时追加}
📤 审查完成后将由主代理保存到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。
```

**BATCH_MODE=true 时**：

```
🚀 正在启动分批并行代码审查...

📋 任务配置：{REVIEW_MODE} 模式（{REVIEW_MODEL}） · {REVIEW_TYPE} · {REVIEW_SCOPE}
📊 扫描策略：本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} / 总 {BATCH_COUNT} 批 / {CONCURRENCY} 路并发
⏱️ 预估耗时：约 {total_min} 分钟
📌 本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} 批次将按 {CONCURRENCY} 路并发执行；未调度批次保持 pending，完成后生成阶段性或完整合并结果。

{选择飞书输出时追加}
📤 审查完成后将由主代理保存到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。
```

**预估时间参考**：

| 模式 | 小型（<50类） | 中型（50-200类） | 大型（>200类） |
|------|:---:|:---:|:---:|
| fast | 2-3 分钟 | 3-5 分钟 | 5-8 分钟 |
| standard | 5-8 分钟 | 8-15 分钟 | 15-25 分钟 |
| deep | 10-15 分钟 | 15-30 分钟 | 30-60 分钟 |
| security | 5-10 分钟 | 10-20 分钟 | 20-35 分钟 |

---

## 分批计算

当 `BATCH_MODE=true` 时，主 skill 必须优先使用确定性脚本生成批次计划，不得临时拼接 Bash 数组或在 shell 中即兴实现 token 打包。

### Maven 多模块分批

Maven 多模块项目不得使用内联 Bash 数组分批，必须统一调用 `languages/java/plan-large-batches.sh`：

```bash
SEMANTIC_LEVEL="maven-static"
if [ "$CODE_INTELLIGENCE_AVAILABLE" = "true" ]; then
  SEMANTIC_LEVEL="jdtls-lsp"
fi

bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/java/plan-large-batches.sh" \
  "$PROJECT_DIR" \
  "$REVIEW_MODE" \
  "{TARGET_BRANCH 或 CURRENT_BRANCH}" \
  "$SEMANTIC_LEVEL" \
  "$REVIEW_SCOPE" \
  "$STOCK_REVIEW_STRATEGY" \
  "$CONTEXT_SCALE"
```

适用范围：
- 全量审查：`REVIEW_SCOPE=全量代码`
- 指定模块：`REVIEW_SCOPE` 为模块相对路径列表，例如 `yudao-module-mes,yudao-framework`
- 按模块依次：`STOCK_REVIEW_STRATEGY=module-sequential`
- AI 智能规划：`STOCK_REVIEW_STRATEGY=ai-planned`

脚本输出的 `RUN_DIR`、`plan.json`、`batches/*.json` 和 `results/*.status.json` 是后续批次展示、选择本轮执行批次、启动 batch agent 和合并报告的唯一数据来源。

### 非 Maven 兼容分批

仅当 `PROJECT_TYPE` 不是 Maven 多模块且 `BATCH_MODE=true` 时，必须统一调用 `languages/java/plan-file-batches.sh` 生成简单文件级批次，覆盖 Maven 单模块、Gradle 项目和未知 Java 项目：

Maven 多模块存量分批绝不调用 `languages/java/plan-file-batches.sh`。即使只选择一个模块，也必须使用 Maven 多模块 planner，以便 `REVIEW_SCOPE` 限定在所选模块内，避免生成全项目批次。

```bash
CC_REVIEW_CONTEXT_SCALE="$CONTEXT_SCALE" \
bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/java/plan-file-batches.sh" \
  "$PROJECT_DIR" \
  "$REVIEW_MODE" \
  "{TARGET_BRANCH 或 CURRENT_BRANCH}"
```

脚本必须输出并由主 skill 原样展示：
- `RUN_DIR`、`BATCH_COUNT`、`TOTAL_JAVA_LOC`、`TOTAL_JAVA_FILE_COUNT`
- `BATCH_FILE_LIST_DIR`，其中每个 `batch-XXX.files` 是注入 batch agent 的 `BATCH_FILE_LIST`
- `简要分批计划` 表：批次号、行数、文件数、每批代表性文件或目录概要

执行要求：
- 禁止在主 skill 中临时拼接 Bash 数组、Python heredoc 或手写 token 打包逻辑
- 批次清单必须来自 `BATCH_FILE_LIST_DIR/batch-XXX.files`
- 每个批次的 `BATCH_FILE_COUNT` 和 `BATCH_LINE_COUNT` 从对应 `batch-XXX.json` 或 `.files` 清单统计
- 增量审查不执行此分批路径

### 前端分批（LANGUAGE_ID=frontend）

前端项目（含 React monorepo 单语言运行）必须使用 `scripts/core/plan-file-batches.sh`（语言中立），不得使用 Java 的 `languages/java/plan-file-batches.sh` 或 `languages/java/plan-large-batches.sh`：

```bash
# 先生成不可变 source manifest（生产 .ts/.tsx/.js/.jsx，排除测试/产物/配置脚本）
MANIFEST="$(mktemp)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/languages/frontend/collect-source-files.sh" "$PROJECT_DIR" > "$MANIFEST"

CC_REVIEW_CONTEXT_SCALE="$CONTEXT_SCALE" \
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/plan-file-batches.sh" \
  "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "frontend" "$MANIFEST"
```

合并：
```bash
RUN_BATCH_IDS="{RUN_BATCH_IDS}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/merge-batch-results.sh" "$RUN_DIR"
```

前端批次状态展示：在前端分批规划完成后、启动 agent 前（或本轮批次跑完准备合并时），调用批次状态展示脚本向用户展示批次表与动态执行计划。此脚本按前端 plan.json 的 `language_id=frontend` 读取 `total_source_loc`/`planned_source_loc`，展示「前端源码行数」「前端源码行覆盖」：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

`scripts/core/merge-batch-results.sh` 的覆盖率展示名根据 `plan.json.language_id` 自动切换为「前端源码文件覆盖率」。前端 batch agent 使用 `cc-code-reviewer-frontend` 子代理，注入 PROFILE 行、source manifest、`SEMANTIC_LEVEL`、批次参数（`RUN_DIR`/`BATCH_PLAN_PATH`/`BATCH_STATUS_PATH`/`BATCH_RESULT_PATH`）。

---

## 子 agent 调用规范

### 调用方式

使用 Task 工具启动子代理，子代理类型按 `LANGUAGE_ID` 选择：
- `LANGUAGE_ID=java` → description: `"执行 Java 代码审查"`，subagent_type: `"cc-code-reviewer:cc-code-reviewer"`
- `LANGUAGE_ID=frontend` → description: `"执行前端代码审查"`，subagent_type: `"cc-code-reviewer:cc-code-reviewer-frontend"`
- model: {REVIEW_MODEL}
- prompt: 下方参数注入格式

不要传 `run_in_background`；该字段不属于 Claude Code Task 调用契约。子 agent 会独立执行审查，主 agent 等待其返回结构化结果后展示给用户。

### 参数注入格式

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
| 审查模型 | {REVIEW_MODEL} |
| 审查文件数量 | {REVIEW_FILE_COUNT} |
| 审查代码行数 | {REVIEW_LINE_COUNT} |
| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |
| React 规则路径 | {REACT_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| 源码范围路径 | {SOURCE_SCOPE_PATH}（仅 LANGUAGE_ID=frontend） |
| 报告格式路径 | {REPORT_FORMAT_PATH} |
| 项目 ignore 文件路径 | {IGNORE_RULES_PATH 或 未配置} |
| 项目 ignore 是否启用 | {IGNORE_RULES_ENABLED} |
| 项目 ignore 问题数量 | {IGNORE_RULE_COUNT} |
| 语义增强 | {SEMANTIC_LEVEL} |

### 项目概况（预扫描结果）
{PROJECT_SCAN_RESULT}

### 项目 ignore 规则（外部注入，直接使用）
{IGNORE_RULES_CONTENT；未启用时写 "未配置"}

### 增量提交记录（仅增量审查时提供）
{GIT_LOG_OUTPUT}

### 变更文件列表（仅增量审查时提供）
{CHANGED_FILES_OUTPUT}

### 变更统计概览（仅增量审查时提供）
{DIFF_STATS_OUTPUT}

请基于以上审查参数，立即开始执行代码审查。不要进行任何用户交互或询问，直接从代码审查开始执行。
```

### 参数来源说明

| 变量名 | 来源 | 示例值 |
|--------|------|--------|
| `PROJECT_DIR` | phase1 脚本输出 | `/tmp/{仓库名}` 或本地路径 |
| `PROJECT_SOURCE` | phase1 脚本输出 | `local` / `git-cache` |
| `PROJECT_NAME` | `basename "$PROJECT_DIR"` | `spring-ai-agent-utils` |
| `PROJECT_TYPE` | phase3 脚本输出 | `maven-single` 等 |
| `REVIEW_MODE` | 交互步骤1 | `fast` / `standard` 等 |
| `REVIEW_MODEL` | 第四步之后（模型选择已前移至分批前） | `sonnet` / `opus` / `haiku` |
| `CONTEXT_SCALE` | core/detect-model-context.sh 输出 | `1`（200k 窗口）/ `5`（1M 窗口） |
| `CONTEXT_WINDOW_TOKENS` | core/detect-model-context.sh 输出 | `200000` / `1000000` |
| `FEISHU_UPLOAD_OPTION` | 交互步骤2 | `本地 Markdown 报告` 或 `飞书云文档, 飞书多维表格` 等 |
| `REVIEW_ENTRY` | 交互步骤3 | `增量审查` / `全量审查` / `指定模块` |
| `REVIEW_TYPE` | 交互步骤3 | `增量审查` / `存量审查` |
| `REVIEW_SCOPE` | 交互步骤4 | `最近5次提交` / `全量代码` / `yudao-module-mes,yudao-framework` |
| `STOCK_REVIEW_STRATEGY` | 交互步骤4B（仅 Maven 多模块存量） | `module-sequential` / `ai-planned` |
| `PROJECT_SCAN_RESULT` | phase3 完整输出 | 项目概况、模块结构 |
| `SEMANTIC_LEVEL` | Java：phase10 输出转换（`CODE_INTELLIGENCE_AVAILABLE=true` → `jdtls-lsp`，否则 `maven-static`）；前端：`detect-code-intelligence.sh` 输出转换（`CODE_INTELLIGENCE_PROVIDER=typescript-lsp` → `typescript-lsp`，否则 `none`） | `jdtls-lsp` / `typescript-lsp` |
| `DETECTED_TECH_STACK` | 从 `PROJECT_SCAN_RESULT` 的 `TECH_STACK:` 行解析，来源为 Maven/Gradle 依赖指纹 | `Spring Boot, MyBatis, Redis/Cache` |
| `REVIEW_FILE_COUNT` | 从 `PROJECT_SCAN_RESULT` 解析 | `76` |
| `REVIEW_LINE_COUNT` | 从 `PROJECT_SCAN_RESULT` 解析 | `16637` |
| `REVIEW_FRAMEWORK_PATH` | 按 `LANGUAGE_ID` 分支：`java` → `references/languages/java/review-framework.md`；`frontend` → `references/languages/frontend/review-framework.md`。启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/java/review-framework.md` |
| `REACT_RULES_PATH` | 仅 `LANGUAGE_ID=frontend`：`references/languages/frontend/react-rules.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/frontend/react-rules.md` |
| `SOURCE_SCOPE_PATH` | 仅 `LANGUAGE_ID=frontend`：`references/languages/frontend/source-scope.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/frontend/source-scope.md` |
| `REPORT_FORMAT_PATH` | `${CLAUDE_PLUGIN_ROOT}/references/report-format.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/report-format.md` |
| `GIT_LOG_OUTPUT` | phase5 脚本输出（仅增量） | `git log --oneline -N` |
| `CHANGED_FILES_OUTPUT` | phase5 脚本输出（仅增量） | `git diff --name-only` |
| `DIFF_STATS_OUTPUT` | phase5 脚本输出（仅增量） | `git diff --stat` |

### 增量审查预处理（仅增量审查时执行）

在调用子 agent 之前，执行增量预处理脚本：`bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/prepare-incremental.sh" "$PROJECT_DIR" {N}`

脚本输出用 `# ===` 分隔为三部分：
1. `# === 提交记录 ===` → GIT_LOG_OUTPUT
2. `# === 变更文件列表 ===` → CHANGED_FILES_OUTPUT
3. `# === 变更统计 ===` → DIFF_STATS_OUTPUT

**异常处理**：如果 CHANGED_FILES_OUTPUT 为空，告知用户没有变更文件，询问是否调整提交次数或切换到存量审查，不调用子 agent。

### 第五步之后：报告合并（仅 BATCH_MODE=true 时执行）

所有本轮 batch agent 完成或进入终态后，主 skill 执行合并（不启动额外 agent）。

Maven 大仓库模式必须通过确定性脚本合并，并把本轮主任务批次通过 `RUN_BATCH_IDS` 传给脚本：
```bash
RUN_BATCH_IDS="{RUN_BATCH_IDS}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/core/merge-batch-results.sh" "$RUN_DIR"
```

该脚本会生成 `summary.json` 和 `final/code-review-report-*`，并在报告中写入“批次状态总览”，列明本轮主任务批次、已纳入合并的批次、失败/缺失/等待超时遗留批次，以及未纳入本轮的遗留批次。
`summary.json` 中的 `report_title` 是合并报告用于飞书云文档标题校验的唯一标题来源；`final_report_path` 指向的 Markdown 文件第一条非空内容必须等于 `# {report_title}`。

合并门禁：
- `RUN_BATCH_IDS` 为空时，默认检查 `plan.json` 中的全部批次；Maven 大仓库模式正常执行时必须传入本轮 `RUN_BATCH_IDS`。
- 本轮批次处于 `pending` / `running` 时，脚本等待其进入终态；等待超时后生成 `[合并阻塞]` 报告并以非 0 退出。
- 本轮批次为 `failed`，或 `completed` 但结果文件缺失时，不得静默跳过；生成 `[合并阻塞]` 报告并以非 0 退出。
- 本轮批次均 `completed` 且结果文件存在时，才合并这些批次的审查结果。
- 若 `plan.json` 中仍有未纳入本轮的批次，报告标记为 `[阶段性]`；只有全部批次均已完成并纳入合并时才称为完整报告。
- 完整/阶段性判断以已纳入合并的批次数为准；即使非本轮批次已经 completed，只要没有纳入本次合并，仍必须保留为遗留批次并输出 `[阶段性]` 报告。

#### 合并步骤

1. **确定本轮批次集合**：读取 `RUN_BATCH_IDS`；为空时回退到 `RUN_DIR/batches/batch-*.json` 全量批次。
2. **等待本轮批次终态**：检查 `results/batch-XXX.status.json`，对 `pending` / `running` 批次按脚本超时配置等待。
3. **阻塞判断**：本轮存在 `failed`、结果缺失或等待超时，生成 `[合并阻塞]` 报告，提示用户重试或补齐对应批次。
4. **批次状态总览**：在报告中列出所有批次的状态、本轮主任务标记、合并处理、文件数、行数、模块和错误信息。
5. **合并已完成本轮批次**：只把本轮 `completed` 且结果文件存在的批次纳入正式发现；非本轮批次列为遗留。
6. **跨批线索汇总**：抽取各批 `跨批依赖待复核` 段落，集中列在报告中。
7. **跨批去重**：对已纳入本次合并的发现按文件、行号、维度和根因去重；未完成或遗留批次不得参与正式结论。
8. **聚合同类问题**：对同一根因的多处出现聚合为一条，保留代表位置和影响范围。
9. **汇总覆盖率**：Java 文件覆盖率只统计已纳入合并的批次文件数；LOC 与 review cost 仅作为规划规模参考。
10. **按分批合并报告格式输出**：复用 `references/report-format.md` 中的合并报告格式，至少包含审查配置快照、审查范围说明、执行摘要、批次状态总览、已完成批次发现、跨批依赖线索、覆盖限制与未审查范围。

#### 合并后输出

使用 Write 工具将合并后的报告保存到 `{PROJECT_DIR}/code-review-report-{PROJECT_NAME}-{timestamp}.md`（与单 agent 模式一致的命名和路径）。

#### 合并后报告保存

复用现有飞书保存逻辑：根据 FEISHU_UPLOAD_OPTION 执行上传，上传合并后的报告文件。上传飞书云文档前必须校验合并报告标题：读取 `summary.json.report_title`，确认待上传 Markdown 文件第一条非空内容等于 `# {report_title}`；不得上传会在飞书显示为 `untitled` 的无标题内容。

#### 合并后结果展示

**已上传飞书时**：

```
✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 扫描策略：分批并行扫描（本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} / 总 {BATCH_COUNT} 批 / {CONCURRENCY} 路并发）
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

📊 扫描策略：分批并行扫描（本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} / 总 {BATCH_COUNT} 批 / {CONCURRENCY} 路并发）
📊 审查覆盖：{总扫描文件数}/{REVIEW_FILE_COUNT} 文件（{总扫描行数}/{REVIEW_LINE_COUNT} 行），覆盖率 {综合覆盖率}%
📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / P3: {n} / 待确认: {n}）
💡 建议：{一句话关键建议}
```

#### 上下文保护

- 每个 batch 文件约 2-5k token（只含发现清单，不含代码原文）
- 30 个 batch 的合并读取总量约 60-150k token
- 合并操作在主 skill 上下文中执行，通过压缩上下文可容纳

### 子 agent 返回结果处理

**BATCH_MODE=false 时**：子 agent 不执行飞书上传，只返回本地报告文件绝对路径 + 完整报告内容 + 结构化摘要（覆盖率/问题统计/最高风险项/一句话建议）。主 skill 接收返回结果后，执行下方「单 agent 模式报告保存与飞书上传」章节。

**BATCH_MODE=true 时**：子 agent 返回结果仅用于进度确认。实际合并和输出由「第五步之后：报告合并」章节处理。每个 batch agent 完成后输出 `✅ Batch {BATCH_INDEX}/{BATCH_COUNT} 完成`，全部完成后进入合并流程。

---

### 单 agent 模式报告保存与飞书上传（BATCH_MODE=false）

**前置条件**：子 agent 已返回本地报告文件绝对路径（`REPORT_FILE_PATH`）+ 完整报告内容 + 结构化摘要。本地 Markdown 报告文件已由子 agent 落盘，主 skill 无需重新 Write。

主 skill 按以下顺序处理报告保存与飞书上传，该流程与分批模式的「合并后报告保存」复用同一份 `references/feishu-integration.md` 操作规范：

#### 步骤 1：标题校验（上传前置）

从子 agent 返回的 `REPORT_FILE_PATH` 读取该 Markdown 文件，校验第一条非空内容是一级标题（形如 `# 代码审查报告 - {PROJECT_NAME}`）。不得上传会在飞书显示为 `untitled` 的无标题内容；校验不通过时必须先修正本地报告文件标题行再执行上传。

#### 步骤 2：按 FEISHU_UPLOAD_OPTION 执行飞书上传

- **包含 `飞书云文档`**：通过 `lark-cli` + `lark-doc` skill 创建飞书云文档。CLI 固定使用 `lark-cli docs +create --api-version v2 --doc-format markdown --content @{REPORT_BASENAME}`，先 `cd` 到报告文件所在目录再用相对文件名。文档标题由 Markdown 一级标题承载，不要传 `--title`。从响应 `data.doc_url` 提取云文档链接 `DOC_URL`。详细步骤见 `${CLAUDE_PLUGIN_ROOT}/references/feishu-integration.md`「上传报告到飞书云文档」章节。
- **包含 `飞书多维表格`**：通过 `lark-cli` + `lark-base` skill 创建飞书多维表格并录入问题清单。按 17 字段定义创建表 → 重命名默认主字段为"备注" → 创建其余 16 字段 → 批量录入问题数据（从子 agent 返回的完整报告内容中解析各级别问题）→ 清理默认字段。从响应提取多维表格链接 `BASE_URL`。详细步骤见 `${CLAUDE_PLUGIN_ROOT}/references/feishu-integration.md`「创建飞书多维表格」章节。
- **只含 `本地 Markdown 报告`、或值为 `lark-cli未安装` / `飞书上传不可用`**：跳过飞书上传，直接进入步骤 3 的「未上传飞书」分支。

#### 步骤 3：输出最终汇总

根据是否完成飞书上传，套用对应模板。模板中的统计字段（问题总数/P0数/覆盖率/最高风险项/一句话建议）从子 agent 返回的结构化摘要中提取，链接字段从步骤 2 的上传结果中提取。

**已上传飞书时**（FEISHU_UPLOAD_OPTION 包含云文档或多维表格，且上传成功）：

```
✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 审查覆盖：{实际扫描文件数}/{审查文件数量} 文件（{实际扫描行数}/{审查代码行数} 行），覆盖率 {覆盖率}%
📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / P3: {n} / 待确认: {n}）

🔥 最高风险项：
  - P0-1: {问题一句话描述} — {位置}
  （最多列 5 条）

{按实际 FEISHU_UPLOAD_OPTION 展示对应链接；如果包含 `本地 Markdown 报告`，同时展示本地报告路径}
📄 本地报告：{REPORT_FILE_PATH}
📄 审查报告：{DOC_URL}  ← 仅包含飞书云文档时显示
📋 问题清单：{BASE_URL}  ← 仅包含飞书多维表格时显示

💡 建议：{一句话关键建议}
👉 详细报告请点击上方飞书链接查看。
```

**未上传飞书时**（FEISHU_UPLOAD_OPTION 为本地 Markdown / lark-cli未安装 / 飞书上传不可用）：

```
📄 审查报告已保存到本地文件：
   {REPORT_FILE_PATH}

{完整报告内容}

---

✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 审查覆盖：{实际扫描文件数}/{审查文件数量} 文件（{实际扫描行数}/{审查代码行数} 行），覆盖率 {覆盖率}%
📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / P3: {n} / 待确认: {n}）
💡 建议：{一句话关键建议}
```

#### 失败降级

如果飞书上传任一步骤失败（云文档创建失败、多维表格创建/录入失败），降级为「未上传飞书」分支：展示子 agent 返回的本地报告文件路径 + 完整报告内容，并说明上传失败原因。本地报告文件已由子 agent 落盘，主 skill 无需重新生成。

---

## 重要规则

1. **输入校验**：用户自定义输入必须与当前问题相关且合理，无效输入需提示重新选择，每步最多重试 3 次
2. **执行前强制确认**：必须展示执行计划并等待用户确认
3. **三个核心选项必须全部明确**：审查类型 + 审查范围 + 审查模式，缺一不可
4. **强制中文输出**：所有交互和报告都必须使用中文
5. **最终确认前零深度审查动作**：在用户最终确认前，不得启动子 agent 或执行正式代码审查；但允许执行预扫描脚本

### 条件步骤规则

- **单模块项目自动跳过步骤4**：`PROJECT_TYPE` 为 `*-single` 且选择存量审查时，自动设 `REVIEW_SCOPE=全量代码`
- **lark-cli 检测**：lark-cli、lark-doc、lark-base 任一不可用时自动设 `FEISHU_UPLOAD_OPTION=本地 Markdown 报告`
- **Git 分支选择**：仅在 Git 仓库且多分支时执行前置分支选择步骤
- **飞书保存执行**：主 skill 使用 `lark-doc`/`lark-base` skill，通过 `lark-cli` 执行；子 agent 不执行飞书上传，只返回本地报告文件路径由主 skill 统一上传

---

## 错误处理

如果用户输入无法识别或与当前问题无关：
- 输出 `⚠️ 输入无效` 提示，重新展示当前步骤的选项
- 每个步骤最多重试 3 次
- 超过 3 次仍无效时，输出 `❌ 多次输入无效，已终止本次审查` 并结束流程

---

## 示例对话

完整的示例对话详见 `${CLAUDE_PLUGIN_ROOT}/references/examples.md`。
