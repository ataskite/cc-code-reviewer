---
description: Java 审查问题修复 - 基于人工确认的问题清单，支持直接修复或可选 Superpowers 修复路线
---

## 执行算法（最高优先级，必须严格按此顺序执行）

`cc-code-fixer` 的入口和 scan 阶段保持一致：用户只需要提供待修复项目地址（本地路径或 Git URL）。待修复问题清单必须通过 AskUserQuestion 在交互中收集和确认。修复阶段必须交互确认，不接受用参数绕过人工确认。

主 skill 负责解析项目、预检测、收集待修复问题确认清单、确认执行方式和输出目标。修复执行有两条路线：默认的直接修复路线由主 skill 执行；检测到 Superpowers 相关技能完整安装时，才额外展示 Superpowers 修复路线（brainstorming → subagent-driven-development）。两条路线都必须遵守用户确认的问题范围、测试优先和完成前验证。

### 第零步：模式判定（固定交互式）

修复阶段固定为交互式人工确认流程。除项目地址外的任何修复计划都必须通过 AskUserQuestion 在后续步骤中确认。

### 第一步：提取项目路径

从用户输入中提取 `PROJECT_INPUT`，此阶段不得调用 AskUserQuestion。

#### 项目路径提取规则

必须按以下优先级提取项目路径：

1. 优先提取 Git URL：匹配 `https://...`、`http://...`、`git://...`、`git@...` 的完整 token，作为 `PROJECT_INPUT`
2. 其次提取本地路径 token：
   - 绝对路径：`/path/to/project`
   - 相对路径：`.`、`..`、`./project`、`../project`、`project/subdir`
3. 路径可以出现在自然语言中，例如 `帮我修复 /path/to/project`，不得把 `帮我修复`、`这个项目` 等自然语言词当作路径
4. 路径包含空格时，应使用用户输入中带引号的完整路径；传给脚本时必须整体加引号

如果无法提取项目路径，立即输出：

```text
❌ 未识别到待修复项目路径

请提供本地项目路径或 Git 仓库地址，例如：
  /cc-code-reviewer:cc-code-fixer /path/to/project
  /cc-code-reviewer:cc-code-fixer https://github.com/org/repo.git
```

然后终止，不进入预检测。

#### 不支持的修复计划参数

修复阶段只接受项目地址。若用户提供项目地址之外的修复计划参数，必须提示：

```text
❌ 修复阶段必须交互确认

cc-code-fixer 只接受项目地址。待修复问题确认清单和输出目标会在后续 AskUserQuestion 中逐步确认。
```

然后终止，不得降级执行，不得继续调用子 agent。

### 第二步：项目预检测（5 个脚本按顺序执行，此阶段禁止任何用户交互）

使用第一步提取出的 `PROJECT_INPUT`，按以下顺序执行脚本。此阶段禁止调用 AskUserQuestion，禁止输出交互式提问。

仅支持 macOS / Linux（Bash）：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase1-detect-project.sh" "<项目路径或 Git URL>"
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

### 第三步：输出项目预检测摘要（不允许跳过）

5 个脚本全部完成后，必须输出以下格式的摘要：

```text
🧭 修复项目预检测完成

📂 项目：
- 来源：{PROJECT_SOURCE 对应展示，本地路径 / Git仓库缓存}
- 路径：{PROJECT_DIR}
- 类型：{PROJECT_TYPE 展示名}

🌿 Git：
- 当前分支：{CURRENT_BRANCH}
- Git 仓库：{IS_GIT_REPO}
- 工作区状态：{干净 / 存在未提交改动 / 未知}

📊 规模：
- Java 文件：{N} 个
- 代码行数：{M} 行

🔌 lark-cli：
- {LARK_PLUGIN_INSTALLED=true 时显示 "✅ 可用，支持读取飞书问题清单和回写修复结果" / false 时显示 "⚠️ 不可用：{LARK_PLUGIN_REASON}，只能使用本地 Markdown 清单并输出本地报告"}

🧠 Superpowers：
- 状态：{SUPERPOWERS_AVAILABLE=true 时显示 "✅ 可用，可作为执行方式选项" / false 时显示 "未完整安装，仅展示直接修复路线"}
- 缺失：{SUPERPOWER_MISSING 或 "无"}
```

### 第四步：通过 AskUserQuestion 收集待修复问题确认清单

第一轮 AskUserQuestion 必须用于确认待修复问题清单来源。该清单必须是人确认过的本地 Markdown、scan 阶段产出的飞书云文档、或 scan 阶段产出的飞书多维表格。不得默认把 scan 产物中的全部候选问题自动纳入修复。

必须调用 AskUserQuestion：

- question: "请提供本次待修复问题确认清单的来源"
- header: "问题清单"
- options:
  - label: "本地 Markdown"
    description: "使用已经人工确认过的本地审查报告或 Fix TODO List"
  - label: "飞书云文档"
    description: "读取 scan 阶段产出的飞书云文档问题清单"
  - label: "飞书多维表格"
    description: "读取 scan 阶段产出的飞书多维表格问题记录"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

用户选择来源后，必须追加一次 AskUserQuestion 收集「问题清单位置」，即本地 Markdown 路径、飞书云文档链接、飞书多维表格 URL 或 `base:{BASE_TOKEN}:{TABLE_ID}` token。question 使用 "请提供待修复问题确认清单的具体位置，并在 Other/free-form 中粘贴 URL 或本地路径"，header 使用 "问题清单位置"。如果当前 AskUserQuestion 不支持自由文本，必须使用 Other/free-form 收集，并在选项描述里明确要求用户在 Other/free-form 中粘贴本地 Markdown 路径、飞书云文档 URL、飞书多维表格 URL 或 `base:{BASE_TOKEN}:{TABLE_ID}`。

收集到 `FIX_INPUT_SOURCE` 后，执行：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase6-detect-fix-input.sh" "<FIX_INPUT_SOURCE>"
```

然后读取或解析修复输入，归一化为问题清单。归一化问题字段至少包括：`issue_id`、`severity`、`dimension`、`location`、`confidence`、`evidence`、`impact`、`suggestion`、`source_type`、`source_ref`、`fix_status`。如果飞书读取失败且没有已归一化问题上下文，必须停止修复，只生成本地失败说明，不得继续进入修复执行。

输入读取规则：

- 本地 Markdown 必须直接读取文件内容，再按 Markdown 报告规则解析。
- 飞书云文档必须使用 `lark-cli docs` 和 `lark-doc` skill 读取。
- 飞书多维表格必须使用 `lark-cli base` 和 `lark-base` skill 读取。
- `phase6-detect-fix-input.sh` 只用于识别输入类型和提取必要 token，不得读取云文档或多维表格内容。
- 不得使用 Python 脚本读取飞书云文档或飞书多维表格。

读取完成后必须输出「修复输入解析完成」摘要，说明清单类型、来源、解析状态、问题总数、严重级别分布和已跳过数量。

### 第五步：展示问题清单表格并确认修复范围

解析完成后，必须先输出真正的终端表格，再调用 AskUserQuestion。不要输出项目符号列表，也不要把问题逐条展开成段落。表格最多展示 30 条；超过 30 条时按 P0、P1、P2、P3、待确认排序展示前 30 条，并说明完整清单会注入后续步骤。

问题清单表格只展示 5 列：`问题ID`、`严重级别`、`维度`、`问题摘要`、`修复建议`。不要展示 `置信度`、`位置`、`证据`、`影响` 等宽字段；这些细节保留在归一化上下文和后续修复关键点中。

问题摘要和修复建议必须压缩成终端可扫读的短句：

- `问题摘要`：概括成一句话，建议不超过 18 个中文字符或 36 个英文字符。
- `修复建议`：概括修复动作，建议不超过 22 个中文字符或 44 个英文字符。
- 单元格内容过长时必须先摘要，不要依赖终端自动换行。

问题清单表格格式必须是：

```text
| 问题ID | 严重级别 | 维度 | 问题摘要 | 修复建议 |
|--------|----------|------|----------|----------|
| P0-1 | P0 | 安全 | 接口缺少鉴权 | 增加权限校验和测试 |
```

随后必须调用 AskUserQuestion：

- question: "请确认本次要纳入修复的问题"
- header: "确认清单"
- options:
  - label: "确认全部纳入修复"
    description: "修复表格中的全部可确认问题"
  - label: "只修 P0/P1"
    description: "只修阻塞、高风险和重要问题"
  - label: "按问题编号自定义"
    description: "输入逗号分隔的问题编号，例如 P0-1,P1-2"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

选择「按问题编号自定义」时，必须追加一次 AskUserQuestion 收集编号，header 使用 "问题编号"。自定义编号必须逐个校验是否存在于归一化问题清单中；不存在时提示有效编号并重新收集，最多重试 3 次。

### 第六步：确认修复关键点

基于用户确认的问题集合，输出本次修复关键点：

```text
🎯 修复关键点

| 问题ID | 修复意图 | 边界 | 不修内容 | 建议验证 |
|--------|----------|------|----------|----------|
| P0-1 | ... | ... | ... | ... |
```

然后调用 AskUserQuestion：

- question: "请确认以上修复关键点是否符合预期"
- header: "关键点确认"
- options:
  - label: "确认"
    description: "按以上关键点继续选择执行方式"
  - label: "调整问题清单"
    description: "返回上一步重新选择问题"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

### 第七步：选择输出目标

必须调用 AskUserQuestion：

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

### 第八步：选择执行方式

必须调用 AskUserQuestion：

- question: "请选择本次修复的执行方式"
- header: "执行方式"
- options:
  - label: "直接开始修复"
    description: "由主 skill 按确认范围直接执行修复、测试、验证和报告生成"
  - label: "使用 Superpowers 修复"
    description: "从 brainstorming 开始，再由 subagent-driven-development 执行修复；SUPERPOWERS_AVAILABLE=true 时才展示"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

`使用 Superpowers 修复` 选项必须在 `SUPERPOWERS_AVAILABLE=true` 时才展示。`SUPERPOWERS_AVAILABLE=false` 时不得展示该选项，也不得把 Superpowers 缺失当作 degraded mode；此时只展示 `直接开始修复` 和 `取消`。

用户选择「取消」时立即终止，不执行工作区准备，不修改任何文件。

### 第九步：直接修复路线选择工作区策略

仅当用户选择 `直接开始修复` 时执行本步骤。必须调用 AskUserQuestion：

- question: "请选择直接修复使用的工作区策略"
- header: "工作区策略"
- options:
  - label: "当前分支修复"
    description: "在当前分支和当前工作区直接修改，适合已确认可以原地修复的场景"
  - label: "创建新分支修复"
    description: "在当前仓库创建或切换到新的修复分支后再修改"
  - label: "创建 worktree 修复"
    description: "创建独立 worktree 和修复分支，适合隔离较强的修复"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

选择 `创建新分支修复` 或 `创建 worktree 修复` 时，必须追加一次 AskUserQuestion 收集修复分支名，header 使用 "修复分支"。默认建议分支名为 `fix/review-confirmed-issues`，但必须允许用户在 Other/free-form 中输入自定义分支名。

随后调用工作区准备脚本：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase8-prepare-fix-workspace.sh" "$PROJECT_DIR" "{current|branch|worktree}" "{FIX_BRANCH}"
```

`当前分支修复` 使用 `current`，分支名参数可为空。脚本失败时必须停止在代码变更之前，输出失败原因，不得继续修复。

### 第十步：确认执行计划

在调用 AskUserQuestion 前必须展示完整执行计划：

```text
🛠️ 修复执行计划

- 项目路径：{PROJECT_DIR}
- 待修复问题确认清单：{FIX_INPUT_TYPE} {FIX_INPUT_SOURCE}
- 确认修复问题数：{N}
- 问题编号：{CONFIRMED_ISSUE_IDS}
- 输出目标：{OUTPUT_TARGET}
- 执行方式：{EXECUTION_ROUTE=direct|superpowers}
- 工作区策略：{WORKSPACE_STRATEGY，Superpowers 路线显示 "由 Superpowers 设计阶段决定"}
- Superpowers：{SUPERPOWERS_STATUS}
```

然后必须调用 AskUserQuestion：

- question: "确认以上修复计划后开始执行"
- header: "确认执行计划"
- options:
  - label: "确认执行"
    description: "按选择的执行方式开始修复"
  - label: "取消"
    description: "停止本次修复，不修改任何文件"
- multiSelect: false

用户选择「取消」时立即终止。直接修复路线如尚未执行工作区准备，不得再执行；如已经完成工作区准备，必须说明未做代码修改。

### 第十一步 A：直接修复执行

仅当 `EXECUTION_ROUTE=direct` 时执行本路线。主 skill 必须直接启动修复，不调用 Superpowers skill，不调用 dedicated fix sub-agent。

直接修复路线必须遵守以下顺序：

1. 基于确认的问题集合输出简短修复设计，说明修复意图、影响面、风险边界和验证命令。
2. 先补充或定位能暴露问题的测试；无法写测试时必须说明原因，并采用最小可验证命令替代。
3. 只修改用户确认问题所需的业务代码、测试和必要配置，不修复范围外问题。
4. 运行对应验证命令和 `git diff --check`，未验证前不得声称已修复。
5. 按 `references/fix-report-format.md` 生成 `fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md`。
6. 如用户选择飞书输出目标，按 `references/fix-feishu-integration.md` 执行云文档创建或 Base 写回。

直接修复路线仍必须执行测试优先和完成前验证纪律；这些纪律由主 skill 显式执行，不依赖 Superpowers skill 是否安装。

### 第十一步 B：启动 Superpowers 设计与修复执行

仅当 `EXECUTION_ROUTE=superpowers` 且 `SUPERPOWERS_AVAILABLE=true` 时执行本路线。若用户尝试选择但 Superpowers 不可用，必须回到第八步重新选择执行方式。

确认执行后，调用 `brainstorming` skill。brainstorming 运行在主 skill 的共享上下文中，可以直接访问前面的预检测摘要、报告解析结果、问题表格和修复关键点，无需额外注入参数。

brainstorming 负责形成：
- 修复设计（方案、影响面、风险边界）
- 验证思路
- 工作区隔离建议
- 产出 spec 和 plan

如果 brainstorming 建议使用 worktree 或新分支策略，调用 phase8 工作区准备脚本：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase8-prepare-fix-workspace.sh" "$PROJECT_DIR" "{WORKSPACE_STRATEGY}" "{FIX_BRANCH}"
```

brainstorming 产出 plan 后，调用 `subagent-driven-development` skill 执行修复计划。修复执行必须遵守以下约束：

- **范围优先**：只修复用户确认的问题，不得修复范围外问题
- **测试驱动**：遵守 `test-driven-development`
- **验证后声明**：遵守 `verification-before-completion`
- **修复报告**：按 `references/fix-report-format.md` 生成 `fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md`
- **飞书回写**：按 `references/fix-feishu-integration.md` 执行（如用户选择了飞书输出目标）
- **默认中文**：报告、状态说明和最终汇总使用中文

---

## Degraded Mode

进入 degraded mode 的典型条件：

- 飞书读取或更新失败
- 项目依赖无法下载或测试环境不可用
- 审查报告字段缺失，只能解析部分问题
- 当前工作区存在用户修改且无法安全创建隔离分支

degraded mode 下必须继续保护用户代码：

- 不扩大修复范围
- 不覆盖已有未提交修改
- 报告中明确列出降级原因、已完成动作、未完成动作和建议补救步骤
- 能生成本地报告时必须生成本地 Markdown 报告

飞书读取失败的 degraded mode 是只读失败降级：没有已归一化问题上下文时必须停止修复并生成本地失败报告。飞书写入或更新失败的 degraded mode 允许继续完成代码修复、验证和本地报告，只把飞书回写结果标记为失败。
