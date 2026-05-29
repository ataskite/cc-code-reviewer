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

### 第二步：预扫描（5 个脚本按顺序执行，此阶段禁止任何用户交互）

使用第一步之后提取出的 `PROJECT_INPUT`，然后按以下顺序执行 5 个脚本。

仅支持 macOS / Linux（Bash）：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase1-detect-project.sh" "<用户输入的路径>"
# 输出：PROJECT_DIR=<路径> PROJECT_SOURCE=local|git-cache

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase2-detect-branches.sh" "$PROJECT_DIR"
# 输出：IS_GIT_REPO=true/false CURRENT_BRANCH=<分支> BRANCH: ... BRANCH_REMOTE: ...

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase3-project-scan.sh" "$PROJECT_DIR"
# 输出：PROJECT_TYPE=maven-single|maven-multi|... MODULE:模块名|相对路径|Java文件数|代码行数 TECH_STACK:技术栈|dependency:命中依赖|dimensions:建议维度|rules:专项规则

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase10-detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出：CODE_INTELLIGENCE_AVAILABLE=true|false CODE_INTELLIGENCE_PROVIDER=jdtls-lsp|none CODE_INTELLIGENCE_REASON=...

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase4-detect-lark-plugin.sh"
# 输出：LARK_PLUGIN_INSTALLED=true|false，失败时附带 LARK_PLUGIN_REASON
```

> ⚠️ 5 个脚本必须全部执行完成后才能继续。此阶段禁止调用 AskUserQuestion，禁止输出任何交互式提问。

### 第二步之后：读取项目级 ignore 规则

5 个预扫描脚本完成后，在输出预扫描摘要前，检查项目内是否存在 AI 指令型 ignore 文件：

```bash
IGNORE_RULES_PATH="$PROJECT_DIR/.cc-code-reviewer/ignore/issues.yml"
```

读取规则：
- 文件存在且可读：读取完整内容到 `IGNORE_RULES_CONTENT`，设置 `IGNORE_RULES_ENABLED=true`
- 文件不存在：设置 `IGNORE_RULES_ENABLED=false`、`IGNORE_RULES_CONTENT=""`
- 文件存在但不可读：设置 `IGNORE_RULES_ENABLED=false`，在预扫描摘要中提示不可读原因，但不得阻塞扫描
- 不解析 YAML，不做脚本级过滤；过滤由 scan agent 基于 `skip_when` 语义执行

ignore 文件格式定义在 `references/ignore-workflow.md`。该文件是 AI 指令型 ignore 文件，不存报告编号，只描述同类问题的跳过规则。

### 第三步：输出预扫描摘要（不允许跳过）

5 个脚本全部完成后，必须输出以下格式的摘要（这是预扫描阶段的唯一输出）：

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
- Java 文件：{N} 个
- 代码行数：{M} 行
{多模块时追加以下行}
- 模块数量：{K} 个
- 模块列表：{模块1名称}({n1}类), {模块2名称}({n2}类), ...

🧩 技术栈扫描：
- 识别数量：{解析 `TECH_STACK:` 行数量；未识别专项技术栈时显示 0}
- 启用专项规则：{识别到专项技术栈时显示 "是"，否则显示 "否，仅启用通用 Java 审查规则"}

{识别到 TECH_STACK 且 dependency != none 时展示以下表格，最多展示 12 个}
| 技术栈 | 识别证据 | 建议维度 | 专项规则 |
|--------|----------|----------|----------|
| {技术栈名称} | {dependency，若为 file: 前缀则展示为 文件:{路径}} | {dimensions} | {rules} |

{超过 12 个时追加}
- 另有 {N} 个技术栈未在摘要表中展示，完整结果已注入子 agent。

{未识别专项技术栈时展示}
- 未识别专项技术栈，仅启用通用 Java 审查规则。

🔌 lark-cli：{LARK_PLUGIN_INSTALLED=true 时显示 "✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书上传" / false 时显示 "⚠️ 飞书上传不可用：{LARK_PLUGIN_REASON}，报告将保存到本地文件"}

🧠 代码智能：{CODE_INTELLIGENCE_AVAILABLE=true 时显示 "✅ jdtls-lsp 可用，可用于跨目录调用链理解" / false 时显示 "⚠️ 未启用 jdtls-lsp，将使用 Maven 静态依赖分批；建议安装 jdtls 并启用 jdtls-lsp 提升跨模块理解质量"}

🧩 项目 ignore：{IGNORE_RULES_ENABLED=true 时显示 "✅ 已启用：.cc-code-reviewer/ignore/issues.yml" / false 且文件不存在时显示 "未配置" / false 且不可读时显示 "⚠️ 文件存在但不可读：{原因}"}
```

**技术栈扫描展示规则**：
- 数据来源：phase3 输出中的 `TECH_STACK:{技术栈}|dependency:{命中依赖或 file:路径}|dimensions:{建议维度}|rules:{专项规则}` 行
- 必须逐行解析所有 `TECH_STACK:` 行，`PROJECT_SCAN_RESULT` 注入子 agent 时仍保留完整原文
- `dependency:none` 表示未识别专项技术栈，不展示表格，只展示通用 Java 审查规则提示
- `dependency:file:` 表示通过配置文件识别，摘要中的识别证据展示为 `文件:{路径}`
- 识别证据超过 80 字可截断，但不得截断技术栈名称、建议维度和专项规则
- 摘要表最多展示 12 个技术栈；超过 12 个时追加 `另有 {N} 个技术栈未在摘要表中展示，完整结果已注入子 agent。`

### 第三步之后：分批判定

**时机**：在步骤 2（选择审查类型）确定 REVIEW_TYPE 后、步骤 6 前执行判定。

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

**执行要求**：分批判定延迟到步骤 2 确定审查类型后执行（因为公式依赖 REVIEW_TYPE）。

### Maven 大仓库模式判定

仅当以下条件全部满足时进入 Maven 大仓库模式：
- `PROJECT_TYPE=maven-multi`（Maven 多模块）
- `REVIEW_TYPE=存量审查`
- `REVIEW_SCOPE=全量代码`
- `TOTAL_JAVA_LOC >= 120000`

判定公式：
```text
TOTAL_JAVA_LOC >= 120000
TARGET_BATCH_LOC = 25000
SOFT_MIN_BATCH_LOC = 15000
SOFT_MAX_BATCH_LOC = 30000
HARD_MAX_BATCH_LOC = 35000
```

Maven 大仓库模式仍然只对存量审查生效。增量审查、Gradle 项目、单模块项目、局部模块审查继续走现有流程。

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

规划命令：
```bash
SEMANTIC_LEVEL="maven-static"
if [ "$CODE_INTELLIGENCE_AVAILABLE" = "true" ]; then
  SEMANTIC_LEVEL="jdtls-lsp"
fi

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase11-plan-large-batches.sh" "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "$SEMANTIC_LEVEL"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase13-show-large-batch-status.sh" "$PROJECT_DIR"
```

### 第四步：交互式参数收集

按以下步骤逐个调用 **AskUserQuestion 工具**（禁止用纯文本输出替代）。每个步骤必须单独调用 AskUserQuestion 并等待用户响应后才能进入下一步。**禁止在一次回复中合并多个交互步骤。**

详细步骤定义见下方「交互式确认步骤定义」章节。

### 第五步之前：准备审查参考文件路径

在调用子 agent 之前，必须基于插件根目录生成参考文件绝对路径，并校验文件可读：

```bash
REVIEW_FRAMEWORK_PATH="${CLAUDE_PLUGIN_ROOT}/references/review-framework.md"
REPORT_FORMAT_PATH="${CLAUDE_PLUGIN_ROOT}/references/report-format.md"
test -r "$REVIEW_FRAMEWORK_PATH"
test -r "$REPORT_FORMAT_PATH"
```

如果任一文件不存在或不可读，必须终止并输出缺失路径，不得调用子 agent。禁止只依赖 `../references/...` 这类相对路径启动子 agent。

### 第五步：调用子 agent 执行代码审查

**分支判断**：
- BATCH_MODE=false → 执行「路径 A：单 agent 模式」（现有逻辑不变）
- BATCH_MODE=true → 执行「路径 B：分批并行模式」（新增逻辑）

#### 路径 A：单 agent 模式（BATCH_MODE=false）

使用 Task 工具启动 `cc-code-reviewer` 子代理：
- description: "执行 Java 代码审查"
- prompt: 注入审查参数表 + 审查参考文件路径 + 项目概况 + 增量数据
- subagent_type: "cc-code-reviewer:cc-code-reviewer"

详细参数注入格式见下方「子 agent 调用规范」章节。

#### 路径 B：分批并行模式（BATCH_MODE=true）

使用 Agent 工具启动多个 `cc-code-reviewer` 子代理，按轮次并发执行。

**编排逻辑**：

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
| 项目 ignore 文件路径 | {IGNORE_RULES_PATH 或 未配置} |
| 项目 ignore 是否启用 | {IGNORE_RULES_ENABLED} |
| 运行目录 | {RUN_DIR} |
| 批次计划文件 | {BATCH_PLAN_PATH} |
| 批次状态文件 | {BATCH_STATUS_PATH} |
| 批次结果文件 | {BATCH_RESULT_PATH} |
| 批次编号 | {BATCH_INDEX}/{BATCH_COUNT} |
| 审查输出模式 | 仅发现清单 |

### 本批审查边界
请读取 `BATCH_PLAN_PATH`，以其中 `scan_roots` 作为正式审查边界。
允许使用 jdtls 跨目录理解调用链，但正式问题必须位于 `scan_roots` 内。
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

---

## 交互式确认步骤定义

> **强制规则**：
> - 每个步骤必须调用 AskUserQuestion 工具，**禁止用纯文本提问替代**
> - 每个步骤的 AskUserQuestion 调用后，必须等待用户响应
> - 不允许在一次回复中包含多个交互步骤的动作
> - 用户响应后，处理结果、设置变量，然后才能进入下一步

### 步骤 1：选择审查分支（条件步骤）

**触发条件**：IS_GIT_REPO=true 且分支数 > 1。不满足条件时跳过，自动使用 CURRENT_BRANCH。

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "检测到 Git 仓库（当前分支：{CURRENT_BRANCH}），请选择要审查的分支"
- header: "选择分支"
- options: 从预扫描结果动态生成分支选项（最多 4 个，超 4 个时选最热门的 + "其他分支"选项）
- multiSelect: false

**用户响应后**：
- 设置 TARGET_BRANCH
- 如果用户选择"其他分支"，不得把字面值作为分支名；必须读取用户提供的自定义分支名。若 AskUserQuestion 当前交互不支持自定义文本，追加一次 AskUserQuestion 收集分支名，header 使用 "输入分支"，options 使用可用分支中的剩余热门分支并允许 Other/free-form。
- 如不是当前分支，执行 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase2-switch-branch.sh" "$PROJECT_DIR" "{TARGET_BRANCH}" "$CURRENT_BRANCH" "$PROJECT_SOURCE"`
- 切换失败时继续使用当前分支

### 步骤 2：选择审查类型

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择审查类型"
- header: "审查类型"
- options:
  - label: "增量审查"
    description: "审查最近 N 次提交的变更文件及其关联代码"
  - label: "存量审查"
    description: "审查指定模块或全量代码"
- multiSelect: false

**变量赋值**：增量审查 → REVIEW_TYPE=增量审查，存量审查 → REVIEW_TYPE=存量审查

### 步骤 3：选择审查范围（条件步骤）

**触发条件**：
- 增量审查时 → 必须执行
- 存量审查 + 多模块 → 必须执行
- 存量审查 + 单模块 → 跳过，自动设 REVIEW_SCOPE=全量代码

**增量审查时，必须先扫描并展示最近提交，再调用 AskUserQuestion 工具**：

1. 执行最近提交预览脚本（仅用于交互式用户决策，不替代后续增量预处理）：`bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase5-preview-recent-commits.sh" "$PROJECT_DIR"`
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

**存量审查 + 多模块时，先展示模块树，再调用 AskUserQuestion 工具**：

**展示模块树**（在调用 AskUserQuestion 之前，用文本输出）：
```
📊 项目模块概览：

{项目名称}/
├── {模块1名称}/     {N} 类 · {M} 行
├── {模块2名称}/     {N} 类 · {M} 行
└── {模块3名称}/     {N} 类 · {M} 行

合计：{总类数} 类 · {总行数} 行
```

数据来源：解析阶段三预扫描输出的 `MODULE:` 行，提取每个模块的名称、Java 文件数、代码行数。

**然后调用 AskUserQuestion 工具，参数如下**：
- question: "请选择要审查的模块"
- header: "审查范围"
- options: 从预扫描结果动态生成，每个模块的 description 中标注类数和行数（如 `12 类 · 1,580 行`）；模块超过 10 个时展示前 9 个 + "其他模块"
- multiSelect: true

**存量审查 + 多模块用户响应后**：
- 选择"全量代码" → REVIEW_SCOPE=全量代码，并忽略其他模块选项
- 选择一个或多个具体模块 → REVIEW_SCOPE=模块相对路径列表（逗号分隔）
- 选择"其他模块" → 不得把字面值作为模块名；必须读取用户提供的模块相对路径，支持逗号分隔多个模块。若 AskUserQuestion 当前交互不支持自定义文本，追加一次 AskUserQuestion 收集模块路径，header 使用 "输入模块"。
- 自定义模块路径必须逐个校验是否存在于预扫描结果的 `MODULE:` 行中；不存在时提示有效模块列表并重新收集，最多重试 3 次

**变量赋值**：
- 全量代码 → REVIEW_SCOPE=全量代码
- 具体模块 → REVIEW_SCOPE=模块路径（逗号分隔）
- 自定义数字 → REVIEW_SCOPE=最近N次提交

### 步骤 4：选择审查模式

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择审查模式"
- header: "审查模式"
- options:
  - label: "fast"
    description: "快速扫雷，聚焦关键风险，约 5 分钟内出结果"
  - label: "standard（推荐）"
    description: "标准审查，覆盖常规核心维度 + API设计 + 缓存基础 + 核心测试缺失，日常迭代推荐"
  - label: "deep"
    description: "深度审查，全量 15 维度，适合大版本上线前"
  - label: "security"
    description: "安全专项，聚焦安全核心维度"
- multiSelect: false

### 步骤 5：选择飞书上传选项（条件步骤）

**触发条件**：LARK_PLUGIN_INSTALLED=true。不满足时跳过，设 FEISHU_UPLOAD_OPTION=飞书上传不可用。

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "检测到飞书上传能力可用，请选择审查结果的处理方式"
- header: "飞书上传"
- options:
  - label: "仅显示报告"
    description: "只在聊天中显示完整审查报告"
  - label: "上传到云文档"
    description: "审查报告上传到飞书云文档，聊天中显示精简摘要"
  - label: "上传到多维表格"
    description: "问题清单录入飞书多维表格，聊天中显示精简摘要"
  - label: "同时上传两者"
    description: "同时上传云文档和多维表格，聊天中显示精简摘要"
- multiSelect: false

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
  - label: "2 路并发（推荐）"
    description: "同时扫描 2 批，速度与稳定性更均衡，约 {total_min} 分钟"
  - label: "3 路并发"
    description: "同时扫描 3 批，需要较好硬件，约 {total_min} 分钟"
- multiSelect: false

**耗时预估公式**：
```
每批耗时 = 根据现有模式×规模估算表（见步骤 7 中的预估时间参考表）
total_min = ceil(BATCH_COUNT / CONCURRENCY) × 每批耗时
```

**用户响应后变量赋值**：
- 串行执行 → CONCURRENCY=1
- 2 路并发 → CONCURRENCY=2
- 3 路并发 → CONCURRENCY=3
- 并发数仅允许 1 / 2 / 3，默认 `2`

### 步骤 6B：选择本轮执行批次（Maven 大仓库模式）

**触发条件**：满足「Maven 大仓库模式判定」。不满足时跳过此步骤。

在调用 AskUserQuestion 之前，必须先展示当前 run 状态：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase13-show-large-batch-status.sh" "$PROJECT_DIR"
```

**必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择本轮执行批次"
- header: "执行批次"
- options:
  - label: "执行 3 批"
    description: "适合额度紧张或先试跑"
  - label: "执行 5 批（推荐）"
    description: "适合大多数 50 万行级项目，便于跨天继续"
  - label: "执行 10 批"
    description: "适合当前额度充足时加速推进"
  - label: "执行全部未完成批次"
    description: "一次性执行所有待执行和失败待重试批次"
- multiSelect: false

**用户响应后**：
- 设置 `CURRENT_RUN_BATCH_LIMIT=3|5|10|all`
- 从 `RUN_DIR/batches/*.json` 中选择状态为 `pending` 或 `failed` 的批次
- `completed` 批次必须跳过
- 只调度本轮选择数量内的批次；未调度批次保持 `pending`

### 步骤 7：确认执行计划

先输出完整执行计划：

```
📋 执行计划：
- 项目路径：{PROJECT_DIR}
- 项目类型：{PROJECT_TYPE}
- 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}（仅 Git 项目显示）
- 审查类型：{REVIEW_TYPE}
- 审查范围：{REVIEW_SCOPE}
- 审查模式：{REVIEW_MODE}
- 启用维度：{根据模式 × 维度矩阵列出具体维度名称}
- 项目 ignore：{IGNORE_RULES_ENABLED=true 时显示 "已启用 .cc-code-reviewer/ignore/issues.yml"；否则显示 "未配置"}
- 飞书上传：{FEISHU_UPLOAD_OPTION}
- 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）  ← 仅 BATCH_MODE=true 时显示
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

**预估时间参考**：

| 模式 | 小型（<50类） | 中型（50-200类） | 大型（>200类） |
|------|:---:|:---:|:---:|
| fast | 2-3 分钟 | 3-5 分钟 | 5-8 分钟 |
| standard | 5-8 分钟 | 8-15 分钟 | 15-25 分钟 |
| deep | 10-15 分钟 | 15-30 分钟 | 30-60 分钟 |
| security | 5-10 分钟 | 10-20 分钟 | 20-35 分钟 |

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

---

## 子 agent 调用规范

### 调用方式

使用 Task 工具启动内置的 `cc-code-reviewer` 子代理：
- description: "执行 Java 代码审查"
- subagent_type: "cc-code-reviewer:cc-code-reviewer"
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
| 飞书上传选项 | {FEISHU_UPLOAD_OPTION} |
| 审查文件数量 | {REVIEW_FILE_COUNT} |
| 审查代码行数 | {REVIEW_LINE_COUNT} |
| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |
| 报告格式路径 | {REPORT_FORMAT_PATH} |
| 项目 ignore 文件路径 | {IGNORE_RULES_PATH 或 未配置} |
| 项目 ignore 是否启用 | {IGNORE_RULES_ENABLED} |

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
| `REVIEW_TYPE` | 交互步骤2 | `增量审查` / `存量审查` |
| `REVIEW_SCOPE` | 交互步骤3 | `最近5次提交` / `全量代码` |
| `REVIEW_MODE` | 交互步骤4 | `fast` / `standard` 等 |
| `FEISHU_UPLOAD_OPTION` | 交互步骤5 | `仅显示报告` 等 |
| `PROJECT_SCAN_RESULT` | phase3 完整输出 | 项目概况、模块结构 |
| `DETECTED_TECH_STACK` | 从 `PROJECT_SCAN_RESULT` 的 `TECH_STACK:` 行解析，来源为 Maven/Gradle 依赖指纹 | `Spring Boot, MyBatis, Redis/Cache` |
| `REVIEW_FILE_COUNT` | 从 `PROJECT_SCAN_RESULT` 解析 | `76` |
| `REVIEW_LINE_COUNT` | 从 `PROJECT_SCAN_RESULT` 解析 | `16637` |
| `REVIEW_FRAMEWORK_PATH` | `${CLAUDE_PLUGIN_ROOT}/references/review-framework.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/review-framework.md` |
| `REPORT_FORMAT_PATH` | `${CLAUDE_PLUGIN_ROOT}/references/report-format.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/report-format.md` |
| `GIT_LOG_OUTPUT` | phase5 脚本输出（仅增量） | `git log --oneline -N` |
| `CHANGED_FILES_OUTPUT` | phase5 脚本输出（仅增量） | `git diff --name-only` |
| `DIFF_STATS_OUTPUT` | phase5 脚本输出（仅增量） | `git diff --stat` |

### 增量审查预处理（仅增量审查时执行）

在调用子 agent 之前，执行增量预处理脚本：`bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase5-prepare-incremental.sh" "$PROJECT_DIR" {N}`

脚本输出用 `# ===` 分隔为三部分：
1. `# === 提交记录 ===` → GIT_LOG_OUTPUT
2. `# === 变更文件列表 ===` → CHANGED_FILES_OUTPUT
3. `# === 变更统计 ===` → DIFF_STATS_OUTPUT

**异常处理**：如果 CHANGED_FILES_OUTPUT 为空，告知用户没有变更文件，询问是否调整提交次数或切换到存量审查，不调用子 agent。

### 第五步之后：报告合并（仅 BATCH_MODE=true 时执行）

所有 batch agent 完成后，主 skill 执行合并（不启动额外 agent）。

Maven 大仓库模式必须通过确定性脚本合并，只读取 `RUN_DIR` 下状态为 `completed` 的批次：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase12-merge-large-batches.sh" "$RUN_DIR"
```

该脚本会生成 `summary.json` 和 `final/code-review-report-*`。当并非所有批次都完成时，报告必须标记为 `[阶段性]`；只有所有批次均为 `completed` 时才称为完整报告。

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

### 子 agent 返回结果处理

**BATCH_MODE=false 时**：直接使用子 agent 返回的结果，按下方现有逻辑处理（已上传飞书 / 未上传飞书 / 上传失败降级）。

**BATCH_MODE=true 时**：子 agent 返回结果仅用于进度确认。实际合并和输出由「第五步之后：报告合并」章节处理。每个 batch agent 完成后输出 `✅ Batch {BATCH_INDEX}/{BATCH_COUNT} 完成`，全部完成后进入合并流程。

---

**已上传飞书时**：

```
✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

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
📄 审查报告已保存到本地文件：
   {PROJECT_DIR}/code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md

{完整报告内容}

---

✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 审查结果：{从报告中提取问题总数}
💡 建议：{从报告中提取一句话关键建议}
```

**飞书上传失败时**：降级为未上传模式，输出完整报告并说明失败原因。

---

## 重要规则

1. **输入校验**：用户自定义输入必须与当前问题相关且合理，无效输入需提示重新选择，每步最多重试 3 次
2. **执行前强制确认**：必须展示执行计划并等待用户确认
3. **三个核心选项必须全部明确**：审查类型 + 审查范围 + 审查模式，缺一不可
4. **强制中文输出**：所有交互和报告都必须使用中文
5. **最终确认前零深度审查动作**：在用户最终确认前，不得启动子 agent 或执行正式代码审查；但允许执行预扫描脚本

### 条件步骤规则

- **单模块项目自动跳过步骤3**：`PROJECT_TYPE` 为 `*-single` 且选择存量审查时，自动设 `REVIEW_SCOPE=全量代码`
- **lark-cli 检测**：lark-cli、lark-doc、lark-base 任一不可用时自动设 `FEISHU_UPLOAD_OPTION=飞书上传不可用`
- **Git 分支选择**：仅在 Git 仓库且多分支时执行步骤1
- **飞书上传执行**：子 agent 使用 `lark-doc`/`lark-base` skill，通过 `lark-cli` 执行

---

## 错误处理

如果用户输入无法识别或与当前问题无关：
- 输出 `⚠️ 输入无效` 提示，重新展示当前步骤的选项
- 每个步骤最多重试 3 次
- 超过 3 次仍无效时，输出 `❌ 多次输入无效，已终止本次审查` 并结束流程

---

## 示例对话

完整的示例对话详见 `${CLAUDE_PLUGIN_ROOT}/references/examples.md`。
