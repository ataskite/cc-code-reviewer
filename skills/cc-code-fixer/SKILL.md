---
description: Java 审查问题修复 - 基于审查报告执行 TDD 修复、验证和修复报告生成
---

## 执行算法（最高优先级，必须严格按此顺序执行）

以下流程是 `cc-code-fixer` 的入口契约。主 skill 只负责解析修复输入、完成预检测、收集或校验修复计划并调用子 agent；不得在主 skill 中直接修改业务代码，也不得声称已经完成实际修复。

### 第一步：模式判定（最先执行）

检测用户输入中是否包含快速启动参数：
- `--mode`
- `--input`
- `--project`
- `--severity`
- `--dimensions`
- `--issues`
- `--workspace`
- `--strategy`
- `--upload`
- `--output`
- `--branch`
- `--verify`

判定规则：
- 包含任意快速启动参数时，设置 `FAST_MODE=true`，执行预检测后一次性校验参数，校验通过才允许调用子 agent。
- 不包含上述参数时，设置 `FAST_MODE=false`，执行预检测后逐步调用 AskUserQuestion 收集修复计划。
- 模式判定必须先于任何脚本调用和用户交互。

### 第二步：提取修复输入和项目路径

模式判定完成后，必须从用户输入中提取 `<review-source>` 和 `--project`，此阶段不得调用 AskUserQuestion。

#### 修复输入提取规则

`<review-source>` 是已有审查结果来源，支持以下形式：

1. 本地 Markdown 审查报告路径，例如 `/path/to/code-review-report-demo.md`
2. 飞书云文档 URL，例如 `https://example.feishu.cn/docx/ABC123`
3. 飞书多维表格 URL，例如 `https://example.feishu.cn/base/BASE123?table=tbl456`
4. 飞书多维表格 token 表达式，例如 `base:BASE123:tbl456`
5. 快速启动参数 `--input <review-source>` 或 `--input=<review-source>`

如果无法提取 `<review-source>`，立即输出：

```text
❌ 未识别到修复输入

请提供本地 Markdown 审查报告、飞书云文档、飞书多维表格 URL 或 base:{BASE_TOKEN}:{TABLE_ID}，例如：
  /cc-code-reviewer:cc-code-fixer /path/to/code-review-report-demo.md --project /path/to/project
  /cc-code-reviewer:cc-code-fixer --input=/path/to/report.md --project=/path/to/project --severity=P0,P1 --workspace=worktree --strategy=standard --upload=no --branch=codex/fix-review-issues
```

然后终止，不进入预检测。

#### 项目路径提取规则

必须提取 `--project`，支持 `--project /path/to/project` 和 `--project=/path/to/project`。项目路径包含空格时必须保留用户输入中的完整引号内容，传给脚本时整体加引号。

如果无法提取 `--project`，立即输出：

```text
❌ 未识别到待修复项目路径

请使用 --project 指定本地项目路径，例如：
  /cc-code-reviewer:cc-code-fixer /path/to/code-review-report-demo.md --project /path/to/project
```

然后终止，不进入预检测。

#### 快速启动参数提取规则

当 `FAST_MODE=true` 时，必须一次性解析完整参数表 `FAST_PARAMS`：

| 参数 | 支持写法 | 说明 |
|------|----------|------|
| `--input` | `--input report.md` 或 `--input=report.md` | 修复输入来源；可由位置参数 `<review-source>` 替代 |
| `--project` | `--project /path` 或 `--project=/path` | 待修复项目路径 |
| `--severity` | `--severity P0,P1` 或 `--severity=P0,P1` | 按严重级别筛选 |
| `--dimensions` | `--dimensions 安全,性能` 或 `--dimensions=安全,性能` | 按维度筛选 |
| `--issues` | `--issues P0-1,P1-2` 或 `--issues=P0-1,P1-2` | 按问题编号筛选 |
| `--workspace` | `--workspace worktree` 或 `--workspace=worktree` | 工作区策略 |
| `--strategy` | `--strategy standard` 或 `--strategy=standard` | 修复策略 |
| `--upload` | `--upload no` 或 `--upload=doc` | 输出/上传策略 |
| `--output` | `--output local-markdown` 或 `--output=local-markdown` | 输出目标，等价于更明确的上传策略 |
| `--branch` | `--branch codex/fix-x` 或 `--branch=codex/fix-x` | 修复分支名 |
| `--verify` | `--verify "mvn test"` 或 `--verify="mvn test"` | 用户补充验证命令 |

解析要求：
- 每个 `--key` 的值必须是紧随其后的非 `--` token；`--key=value` 按 `=` 后内容作为值。
- 如果某个参数出现多次，使用最后一次出现的值，并在校验失败或启动提示中展示最终采用值。
- 如果参数名不在上表中，记录为非法参数，不得忽略。
- 如果参数缺值、值为空，或下一项也是 `--` 参数，记录为缺失值。
- 解析出的参数必须保留原始字符串，用于后续完整性校验和错误提示。

### 第三步：预检测（6 个脚本按顺序执行，此阶段禁止任何用户交互）

使用第二步提取出的 `<review-source>` 和 `--project`，按以下顺序执行脚本。此阶段禁止调用 AskUserQuestion，禁止输出交互式提问。

**平台检测**：先判断当前运行环境。Windows 使用 PowerShell 脚本（`.ps1`），macOS / Linux 使用 Bash 脚本（`.sh`）。不要混用两种 shell 语法。

Windows（PowerShell）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase6-detect-fix-input.ps1" "<review-source>"
# 输出：FIX_INPUT_TYPE=local-markdown|feishu-doc|feishu-base|feishu-base-token，以及对应路径、URL 或 token 信息

powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase1-detect-project.ps1" "<--project>"
# 输出：PROJECT_DIR=<路径> PROJECT_SOURCE=local|git-cache

powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase2-detect-branches.ps1" "$PROJECT_DIR"
# 输出：IS_GIT_REPO=true/false CURRENT_BRANCH=<分支> BRANCH: ... BRANCH_REMOTE: ...

powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase3-project-scan.ps1" "$PROJECT_DIR"
# 输出：PROJECT_TYPE=... MODULE:... TECH_STACK:...

powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase4-detect-lark-plugin.ps1"
# 输出：LARK_PLUGIN_INSTALLED=true|false，失败时附带 LARK_PLUGIN_REASON

powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase7-detect-superpowers.ps1"
# 输出：SUPERPOWERS_AVAILABLE=true|false SUPERPOWER_SKILL:<skill>=available|missing
```

macOS / Linux（Bash）：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase6-detect-fix-input.sh" "<review-source>"
# 输出：FIX_INPUT_TYPE=local-markdown|feishu-doc|feishu-base|feishu-base-token，以及对应路径、URL 或 token 信息

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase1-detect-project.sh" "<--project>"
# 输出：PROJECT_DIR=<路径> PROJECT_SOURCE=local|git-cache

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase2-detect-branches.sh" "$PROJECT_DIR"
# 输出：IS_GIT_REPO=true/false CURRENT_BRANCH=<分支> BRANCH: ... BRANCH_REMOTE: ...

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase3-project-scan.sh" "$PROJECT_DIR"
# 输出：PROJECT_TYPE=... MODULE:... TECH_STACK:...

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase4-detect-lark-plugin.sh"
# 输出：LARK_PLUGIN_INSTALLED=true|false，失败时附带 LARK_PLUGIN_REASON

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase7-detect-superpowers.sh"
# 输出：SUPERPOWERS_AVAILABLE=true|false SUPERPOWER_SKILL:<skill>=available|missing
```

预检测全部完成后，必须读取或解析修复输入，归一化为问题清单。归一化问题字段至少包括：`issue_id`、`severity`、`dimension`、`location`、`confidence`、`evidence`、`impact`、`suggestion`、`source_type`、`source_ref`、`fix_status`。如果飞书读取失败且没有已归一化问题上下文，必须停止修复，只生成本地失败说明，不得继续调用子 agent。

### 第四步：输出修复输入解析完成摘要（不允许跳过）

6 个脚本和问题归一化全部完成后，必须输出以下格式的摘要。标题必须包含「修复输入解析完成」。

```text
🧭 修复输入解析完成

📄 审查报告来源：
- 类型：{FIX_INPUT_TYPE 对应展示，本地 Markdown / 飞书云文档 / 飞书多维表格 / Base token}
- 来源：{FIX_INPUT_PATH 或 FIX_INPUT_URL 或 base:{BASE_TOKEN}:{TABLE_ID}}
- 解析状态：{完整 / 部分解析 / 失败}

📂 项目：
- 路径：{PROJECT_DIR}
- 来源：{PROJECT_SOURCE}
- 类型：{PROJECT_TYPE 展示名}

🌿 Git：
- 当前分支：{CURRENT_BRANCH}
- Git 仓库：{IS_GIT_REPO}
- 工作区状态：{干净 / 存在未提交改动 / 未知}

🧩 可修复问题统计：
- 总问题数：{N}
- P0：{N0} 个，P1：{N1} 个，P2：{N2} 个，P3：{N3} 个，待确认：{NU} 个
- 已修复或跳过：{NS} 个
- 默认候选：{NC} 个
- 维度分布：{安全:n, 性能:n, ...}

🔌 lark-cli：
- {LARK_PLUGIN_INSTALLED=true 时显示 "✅ 可用，支持飞书读取与回写" / false 时显示 "⚠️ 不可用：{LARK_PLUGIN_REASON}，只能输出本地 Markdown 报告"}

🧠 Superpowers：
- 状态：{SUPERPOWERS_AVAILABLE=true 时显示 "✅ 可用" / false 时显示 "⚠️ 部分不可用，进入 degraded mode"}
- 缺失：{SUPERPOWER_MISSING 或 "无"}
```

### 第五步：参数收集（根据模式选择分支）

#### 分支 A：交互式模式（FAST_MODE=false）

按「交互式确认步骤定义」逐个调用 AskUserQuestion。每个步骤必须单独调用 AskUserQuestion 并等待用户响应后才能进入下一步。禁止在一次回复中合并多个交互步骤，禁止用纯文本问题替代 AskUserQuestion。

#### 分支 B：快速启动模式（FAST_MODE=true）

使用 `FAST_PARAMS` 校验用户提供的所有参数。校验失败时必须输出错误并终止，不得调用 AskUserQuestion，不得执行工作区准备，不得读取或更新飞书写入目标，不得调用子 agent。快速启动模式参数校验失败时，禁止降级为交互式模式。

### 第六步：Superpowers 设计与工作区准备

如果 `SUPERPOWERS_AVAILABLE=true`：
- 将归一化问题清单、项目预扫描结果、用户选择的修复范围和修复策略注入 `brainstorming`，生成修复设计、风险边界和验证思路。
- 如果选择 worktree 或新分支策略，按 Superpowers 工作区准备纪律确认隔离方式，再调用 phase8 工作区准备脚本。
- 子 agent 执行阶段必须延续 `test-driven-development` 和 `verification-before-completion` 纪律。

如果 `SUPERPOWERS_AVAILABLE=false`：
- 进入 degraded mode，但不得跳过修复设计、测试优先和完成前验证纪律。
- 在最终注入给子 agent 的修复任务参数中记录缺失的 Superpowers skills 和降级原因。

工作区准备逻辑必须在调用子 agent 之前完成：

Windows（PowerShell）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\phase8-prepare-fix-workspace.ps1" "$PROJECT_DIR" "{WORKSPACE_STRATEGY}" "{FIX_BRANCH}"
```

macOS / Linux（Bash）：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase8-prepare-fix-workspace.sh" "$PROJECT_DIR" "{WORKSPACE_STRATEGY}" "{FIX_BRANCH}"
```

### 第七步：调用子 agent 执行修复

使用 Task 工具启动 `cc-code-reviewer:cc-code-fixer`：

- description: `执行 Java 审查问题修复`
- subagent_type: `cc-code-reviewer:cc-code-fixer`
- prompt: 按「子 agent 调用规范」注入完整参数

主 skill 不执行实际代码修复；实际代码修改、测试、验证、报告生成和飞书回写由子 agent 按注入参数完成。

---

## 交互式确认步骤定义（仅 FAST_MODE=false 时执行）

> 强制规则：
> - 每一步必须单独调用 AskUserQuestion 工具并等待用户响应。
> - 不允许把多个步骤合并到一次 AskUserQuestion。
> - 不允许用纯文本提问替代 AskUserQuestion。
> - 用户响应后，必须设置对应变量并更新执行计划，再进入下一步。

### 步骤 1：选择工作区策略

必须调用 AskUserQuestion 工具：
- question: "请选择本次修复使用的工作区策略"
- header: "工作区策略"
- options:
  - label: "新建 isolated worktree（推荐）"
    description: "在独立 worktree 中创建修复分支，最大限度隔离现有工作区"
  - label: "当前仓库新建 fix 分支"
    description: "在当前仓库创建或切换到修复分支，要求工作区干净"
  - label: "当前分支直接修复"
    description: "直接在当前分支修改，适合用户明确允许的小范围修复"
- multiSelect: false

变量赋值：`WORKSPACE_STRATEGY=worktree|branch|current`。选择 `worktree` 或 `branch` 时必须生成或收集 `FIX_BRANCH`，默认使用 `codex/fix-review-issues` 或更具体的 `codex/fix-{scope}`。

### 步骤 2：选择修复范围

必须调用 AskUserQuestion 工具：
- question: "请选择本次修复范围"
- header: "修复范围"
- options:
  - label: "P0"
    description: "只修复阻塞或高风险问题"
  - label: "P1"
    description: "修复重要问题"
  - label: "P2"
    description: "修复一般问题"
  - label: "P3"
    description: "修复建议项"
  - label: "待确认"
    description: "包含需要人工确认的问题"
  - label: "自定义问题编号"
    description: "按问题编号精确选择，例如 P0-1,P1-2"
- multiSelect: true

选择「自定义问题编号」时，必须追加一次 AskUserQuestion 收集逗号分隔编号，header 使用 "问题编号"。自定义编号必须逐个校验是否存在于归一化问题清单中；不存在时提示有效编号并重新收集，最多重试 3 次。

### 步骤 3：选择修复维度

必须调用 AskUserQuestion 工具：
- question: "请选择需要纳入本次修复的维度"
- header: "修复维度"
- options: 从归一化问题清单的 `dimension` 字段动态生成，description 中标注每个维度的问题数量和最高严重级别
- multiSelect: true

如果用户在修复范围中已经精确选择问题编号，可默认选择这些问题对应维度，但仍必须展示此步骤供用户确认。

### 步骤 4：选择修复策略

必须调用 AskUserQuestion 工具：
- question: "请选择修复策略"
- header: "修复策略"
- options:
  - label: "conservative"
    description: "最小改动，优先修复明确问题，避免扩大行为变更"
  - label: "standard"
    description: "平衡修复质量与影响面，允许补充必要测试和局部重构"
  - label: "deep"
    description: "处理相关根因和调用链风险，适合已确认的高风险问题组"
- multiSelect: false

变量赋值：`FIX_STRATEGY=conservative|standard|deep`。

### 步骤 5：选择输出目标

必须调用 AskUserQuestion 工具：
- question: "请选择修复结果输出目标"
- header: "输出目标"
- options:
  - label: "仅本地 Markdown"
    description: "生成本地修复报告，不上传飞书"
  - label: "上传飞书云文档"
    description: "生成本地报告后创建飞书云文档"
  - label: "更新原飞书多维表格"
    description: "写回修复状态、修复时间、修复分支和备注"
  - label: "同时云文档和多维表格"
    description: "创建云文档并更新多维表格记录"
- multiSelect: false

如果 `LARK_PLUGIN_INSTALLED=false`，仍可展示飞书选项但必须在 description 中说明不可用；用户选择飞书目标时进入本地 Markdown 降级输出，并在执行计划中标注飞书上传不可用原因。

### 步骤 6：确认执行计划

在调用 AskUserQuestion 前必须展示完整执行计划：

```text
🛠️ 修复执行计划

- 修复输入：{FIX_INPUT_TYPE} {FIX_INPUT_SOURCE}
- 项目路径：{PROJECT_DIR}
- 工作区策略：{WORKSPACE_STRATEGY}
- 修复分支：{FIX_BRANCH}
- 修复范围：{FIX_SCOPE}
- 修复维度：{FIX_DIMENSIONS}
- 修复策略：{FIX_STRATEGY}
- 输出目标：{OUTPUT_TARGET}
- 预计问题数：{N}
- 验证命令：{VERIFY_COMMANDS}
- Superpowers：{SUPERPOWERS_STATUS}
```

然后必须调用 AskUserQuestion 工具：
- question: "确认执行以上修复计划吗？"
- header: "确认执行计划"
- options:
  - label: "确认执行"
    description: "创建或准备工作区，并启动修复子 agent"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

用户选择「取消」时立即终止，不执行工作区准备，不调用子 agent。

---

## 快速启动模式参数规范

快速启动必须提供：

| 必填项 | 说明 |
|--------|------|
| `<review-source>` 或 `--input` | 审查报告、飞书文档或飞书 Base 来源 |
| `--project` | 待修复本地项目路径 |
| `--workspace` | `current`、`branch`、`worktree`、`current-branch`、`new-branch` 之一 |
| `--strategy` | `conservative`、`standard`、`deep` 之一 |
| 范围参数 | `--severity`、`--dimensions`、`--issues` 中至少一个 |

可选项：
- `--branch`：当 `--workspace=branch|worktree|new-branch` 时建议提供；缺省时生成 `codex/fix-review-issues`
- `--upload`：`no`、`doc`、`base`、`both`
- `--output`：`local-markdown`、`feishu-doc`、`feishu-base`、`both`
- `--verify`：用户补充验证命令

枚举校验：
- `--severity` 只允许 `P0`、`P1`、`P2`、`P3`、`待确认`，可逗号分隔。
- `--workspace=current-branch` 归一化为 `current`；`--workspace=new-branch` 归一化为 `branch`。
- `--upload=no` 归一化为 `OUTPUT_TARGET=local-markdown`；`doc` 归一化为 `feishu-doc`；`base` 归一化为 `feishu-base`；`both` 保持组合输出。
- `--output` 与 `--upload` 同时出现时，以 `--output` 为准，并在启动摘要中展示覆盖关系。

校验失败时必须输出：

```text
快速启动参数校验失败：
- 已识别参数：{FAST_PARAMS 摘要}
- 缺少必填参数：{列表；无则写 无}
- 非法参数值：{列表；无则写 无}
- 正确示例：
  /cc-code-reviewer:cc-code-fixer --input=/path/to/report.md --project=/path/to/project --severity=P0,P1 --workspace=worktree --strategy=standard --upload=no --branch=codex/fix-review-issues

已停止执行。快速启动模式禁止降级为交互式模式。
```

校验失败时不得：
- 修改代码
- 创建分支或 worktree
- 读取或更新飞书写入目标
- 调用 AskUserQuestion
- 调用子 agent
- 生成误导性的修复成功报告

校验通过时必须输出快速启动摘要，然后继续执行工作区准备和子 agent 调用。

---

## 子 agent 调用规范

使用 Task 工具启动：

```text
description: 执行 Java 审查问题修复
subagent_type: cc-code-reviewer:cc-code-fixer
```

prompt 必须包含以下章节，章节标题不得改名：

### 修复任务参数

必须注入：
- `FAST_MODE`
- `FIX_INPUT_TYPE`
- `FIX_INPUT_SOURCE`
- `PROJECT_DIR`
- `FIX_WORKSPACE_PATH`
- `WORKSPACE_STRATEGY`
- `FIX_BRANCH`
- `FIX_SCOPE`
- `FIX_DIMENSIONS`
- `FIX_STRATEGY`
- `OUTPUT_TARGET`
- `VERIFY_COMMANDS`
- `SUPERPOWERS_STATUS`
- `DEGRADED_MODE_REASON`

### 归一化问题清单

注入完整的归一化问题列表，不只注入摘要。每条问题至少包含 `issue_id`、`severity`、`dimension`、`location`、`confidence`、`evidence`、`impact`、`suggestion`、`source_type`、`source_ref`、`fix_status`。

### 用户确认的修复计划

注入交互式模式下用户确认的完整执行计划，或快速启动模式下通过校验的等价计划。必须包含工作区策略、修复范围、修复维度、修复策略、输出目标、验证命令和取消状态。

### 项目预扫描结果

注入 phase1、phase2、phase3、phase4、phase6、phase7 的完整原始输出，保留 `MODULE:`、`TECH_STACK:`、`BRANCH:`、`SUPERPOWER_SKILL:` 等行，供子 agent 判断影响面、验证命令和降级状态。

子 agent 返回后，主 skill 只负责展示子 agent 的最终摘要，不重写问题状态，不补造测试结果，不追加未经验证的成功结论。
