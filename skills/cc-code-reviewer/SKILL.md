---
name: cc-code-reviewer
description: Java、前端与 Python 代码审查 — 支持增量/存量审查、按语言矩阵评估、飞书报告上传
---

## 执行算法（最高优先级，必须严格按此顺序执行）

以下是你必须遵循的执行顺序。不允许跳过、合并、重新排序或即兴发挥。

### 第零步：解析插件根目录 PLUGIN_ROOT（最先执行）

本文件是 Claude Code / Codex / ZCode 三端共同发现的唯一权威审查流程。开始前必须根据当前宿主身份固定 `RUNTIME_ID=claude-code|codex|zcode`，完整读取 `runtime/contract.md` 和对应 adapter；若当前宿主身份不明确，必须在预扫描前失败，不得通过已安装目录、工具名称或当前工作目录猜测。所有脚本和参考文件路径只使用平台无关的 `${PLUGIN_ROOT}`。

- **三端统一**：本 Skill 位于 `${PLUGIN_ROOT}/skills/cc-code-reviewer/SKILL.md`。以 Skill 资源目录为基准向上两级解析绝对路径，不把文档示例当作 shell 脚本执行，也不使用 shell 入口参数。

解析后必须同时校验版本文件、核心脚本与当前共享 Skill。未解析出可读插件根目录时必须立即失败，不得进入预扫描，不得部分执行：

```bash
[ -f "${PLUGIN_ROOT}/VERSION" ] && \
[ -f "${PLUGIN_ROOT}/scripts/core/detect-project.sh" ] && \
[ -f "${PLUGIN_ROOT}/skills/cc-code-reviewer/SKILL.md" ] || \
  { echo "❌ PLUGIN_ROOT 不可读或不是 cc-code-reviewer 插件根: ${PLUGIN_ROOT}"; exit 1; }
```

### 跨平台人工确认契约（三端等价）

本 Skill 的人工确认状态机在三端语义等价，差异只存在于交互呈现（见 `runtime/contract.md`「人工确认状态机」与各平台适配器）。本文中的 `INTERACT` 是逻辑动作，不是具体工具名：

- **单选确认**：Claude Code adapter 映射为 `AskUserQuestion`（`multiSelect: false`）；Codex / ZCode 用平台结构化输入，不可用时逐轮单问。
- **多选报告目标**：Claude Code 用 `multiSelect: true`；Codex 拆成组合选项或连续单选；ZCode 用原生多选，不可用时连续单选。
- **4 个以上选项**：Claude Code 原样展示；Codex 分级菜单满足 2–3 选项上限；ZCode 原样或分级菜单。
- **最终执行确认**：三端都必须单独一步，不得跳过。

不变量（三端都必须保持）：预扫描先于交互、摘要先于问题、每步等待用户响应、禁止合并步骤、禁止命令行参数绕过确认。适配器可以改变交互呈现，但不得改变已确认范围、默认值或跳过最终确认。无结构化输入能力时，一次只问一个问题，必须等待响应，不得把多个步骤合并成一段文本。

### 第一步：提取项目路径（最先执行）

必须先从用户输入中提取 `PROJECT_INPUT`，再进入预扫描。此步骤只是解析输入，不得调用 INTERACT。

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
bash "${PLUGIN_ROOT}/scripts/core/detect-project.sh" "<用户输入的路径>"
# 输出：PROJECT_DIR=<路径> PROJECT_SOURCE=local|git-cache

bash "${PLUGIN_ROOT}/scripts/core/detect-branches.sh" "$PROJECT_DIR"
# 输出：IS_GIT_REPO=true/false CURRENT_BRANCH=<分支> BRANCH: ...（最多5个本地分支）
```

**Git 项目分支选择**（在此阶段立即执行）：

当 `IS_GIT_REPO=true` 且本地分支数 > 1 时，**必须**立即调用 INTERACT 让用户选择分支。

**分支选择交互**：
- question: "检测到 Git 仓库（当前分支：{CURRENT_BRANCH}），请选择要审查的分支"
- header: "选择分支"
- options: 从 detect-branches.sh 输出的 BRANCH: 行动态生成选项（最多5个本地分支，按最近活动时间排序）
- multiSelect: false

**用户响应后**：
- 设置 TARGET_BRANCH
- 如不是当前分支，执行 `bash "${PLUGIN_ROOT}/scripts/core/switch-branch.sh" "$PROJECT_DIR" "{TARGET_BRANCH}" "$CURRENT_BRANCH" "$PROJECT_SOURCE"`
- 切换失败时继续使用当前分支

**单分支或非 Git 项目**：跳过交互，自动使用 CURRENT_BRANCH。

### 第三步：语言探测与路由

分支选择完成后，必须先识别候选语言，再执行任何语言专属预扫描脚本：

```bash
bash "${PLUGIN_ROOT}/scripts/core/detect-language.sh" "$PROJECT_DIR"
# 输出：CANDIDATE_LANGUAGE:java|evidence=... 和/或 CANDIDATE_LANGUAGE:frontend|evidence=... 和/或 CANDIDATE_LANGUAGE:python|evidence=... 或 CANDIDATE_LANGUAGE:none
```

**路由规则**：
- **纯 Java**（仅 `CANDIDATE_LANGUAGE:java`）：走现有 Java 预扫描（detect-project -> detect-branches -> project-scan -> detect-code-intelligence -> detect-lark-plugin），流程不变。
- **纯前端**（仅 `CANDIDATE_LANGUAGE:frontend`）：走「前端预扫描」分支。
- **纯 Python**（仅 `CANDIDATE_LANGUAGE:python`）：走「Python 预扫描」分支。
- **混合仓库**（两者或以上皆有）：**必须调用 INTERACT** 让用户选择一种语言：
  - question: "检测到多语言仓库（{命中的语言列表}），本次审查目标语言？"
  - header: "审查语言"
  - options（按命中顺序，仅命中的语言出现在选项中）:
    - label: "Java"
      description: "审查 Java 生产源码（src/main/java），使用 Java 审查矩阵"
    - label: "前端族群（React/Vue/Node）"
      description: "审查 React、Vue2/Vue3 或 Node 的生产源码（src 下 .ts/.tsx/.js/.jsx/.vue/.mjs/.cjs），使用前端审查矩阵"
    - label: "Python（Django/FastAPI/通用 Python）"
      description: "审查 Python 生产源码（src 或顶层包下 .py），使用 Python 审查矩阵"
  - multiSelect: false
  - 用户选择后设 `LANGUAGE_ID`，其他语言仅作仓库背景，不得产出正式问题。
- **none**：输出"❌ 未识别到支持的审查目标（Java、React、Vue、Node 或 Python）"并终止。

### 第四步：按语言执行项目预扫描

语言已确定后，按 `LANGUAGE_ID` 执行且只执行对应语言的预扫描脚本。此阶段必须全部脚本执行完成后才能继续；禁止调用 INTERACT，禁止输出任何交互式提问。

**Java 预扫描分支**（`LANGUAGE_ID=java` 时执行）：

```bash
bash "${PLUGIN_ROOT}/scripts/languages/java/project-scan.sh" "$PROJECT_DIR"
# 输出：PROJECT_TYPE=maven-single|maven-multi|... MODULE:模块名|相对路径|Java文件数|代码行数 TECH_STACK:技术栈|dependency:命中依赖|dimensions:建议维度|rules:专项规则

bash "${PLUGIN_ROOT}/scripts/languages/java/detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出：CODE_INTELLIGENCE_AVAILABLE=true|false CODE_INTELLIGENCE_PROVIDER=jdtls-lsp|none CODE_INTELLIGENCE_REASON=...

bash "${PLUGIN_ROOT}/scripts/core/detect-lark-plugin.sh"
# 输出：LARK_PLUGIN_INSTALLED=true|false，失败时附带 LARK_PLUGIN_REASON
```

**前端预扫描分支**（`LANGUAGE_ID=frontend` 时执行）：

```bash
bash "${PLUGIN_ROOT}/scripts/languages/frontend/detect-project.sh" "$PROJECT_DIR"
# 输出 PROJECT_TYPE=frontend-react|frontend-vue2|frontend-vue3|node；不支持（nextjs/nuxt/generic-tsjs）时停止，不套用专项规则

bash "${PLUGIN_ROOT}/scripts/languages/frontend/scan-project.sh" "$PROJECT_DIR"
# 输出 PROFILE_SCHEMA v1：SOURCE_FILE_COUNT/SOURCE_LINE_COUNT/FORMAL_CONFIG_FILE_COUNT/COMPONENT/TECH_STACK/SOURCE_SCOPE

bash "${PLUGIN_ROOT}/scripts/languages/frontend/detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出 CODE_INTELLIGENCE_PROVIDER=typescript-lsp|none（覆盖 scan-project 的占位）
# 主 skill 据此派生 SEMANTIC_LEVEL：CODE_INTELLIGENCE_PROVIDER=typescript-lsp → SEMANTIC_LEVEL=typescript-lsp；否则 SEMANTIC_LEVEL=none

bash "${PLUGIN_ROOT}/scripts/core/detect-lark-plugin.sh"
# 复用 lark-cli 检测
```

> 前端分支下，后续交互步骤（模式/报告/入口/范围/确认）、增量预处理（`core/prepare-incremental.sh`）、固定 1M 分批、合并、报告保存、飞书输出**全部复用现有流程**；差异仅在：预扫描数据来自前端 PROFILE，`SEMANTIC_LEVEL` 从 `CODE_INTELLIGENCE_PROVIDER` 派生（`typescript-lsp`/`none`，非 Java 的 `jdtls-lsp`/`maven-static`），分批用 `scripts/core/plan-file-batches.sh` + source manifest，合并用 `scripts/core/merge-batch-results.sh`，子 agent 用 `cc-code-reviewer-frontend`。

**Python 预扫描分支**（`LANGUAGE_ID=python` 时执行）：

```bash
bash "${PLUGIN_ROOT}/scripts/languages/python/detect-project.sh" "$PROJECT_DIR"
# 输出 PROJECT_TYPE=python-django|python-fastapi|python-generic|python-unsupported

bash "${PLUGIN_ROOT}/scripts/languages/python/scan-project.sh" "$PROJECT_DIR"
# 输出 PROFILE_SCHEMA v1：SOURCE_FILE_COUNT/SOURCE_LINE_COUNT/FORMAL_CONFIG_FILE_COUNT/COMPONENT/TECH_STACK/SOURCE_SCOPE

bash "${PLUGIN_ROOT}/scripts/languages/python/detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出 CODE_INTELLIGENCE_PROVIDER=pyright|pyright-cli|pylsp|jedi|none（覆盖 scan-project 的占位）
# 主 skill 据此派生 SEMANTIC_LEVEL：pyright/pylsp/jedi -> 同名 LSP；pyright-cli -> pyright-cli（仅 diagnostics）；none -> none

bash "${PLUGIN_ROOT}/scripts/core/detect-lark-plugin.sh"
# 复用 lark-cli 检测
```

> Python 分支下，后续交互步骤（模式/报告/入口/范围/确认）、增量预处理、固定 1M 分批、合并、报告保存、飞书输出**全部复用现有流程**；差异仅在：预扫描数据来自 Python PROFILE_SCHEMA，`SEMANTIC_LEVEL` 从 `CODE_INTELLIGENCE_PROVIDER` 派生（`pyright`/`pylsp`/`jedi` 为 LSP，`pyright-cli` 仅提供 diagnostics，`none` 静态降级），分批用 `scripts/core/plan-file-batches.sh` + source manifest，合并用 `scripts/core/merge-batch-results.sh`，子 agent 用 `cc-code-reviewer-python`。

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

### 第三步之后：读取项目级审查规则

独立读取可选的 `.cc-code-reviewer/review-rules.yml`。它与 ignore 规则不同：**只附加路径审查重点，绝不屏蔽发现**。文件级 batch planner 会在创建 `RUN_DIR` 后自动将同一 source manifest 的规则解析到 `RUN_DIR/review-rules.json`；主 Skill 只注入该路径，不自行解释 YAML 内容。

### 第五步：输出预扫描摘要（不允许跳过）

语言专属预扫描脚本全部完成后，必须输出以下格式的摘要（这是预扫描阶段的唯一输出）：

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
- 前端源码文件（src 下 .ts/.tsx/.js/.jsx/.vue/.mjs/.cjs）：{SOURCE_FILE_COUNT} 个
- 代码行数：{SOURCE_LINE_COUNT} 行
- 配置文件：{FORMAL_CONFIG_FILE_COUNT} 个
- src 目录概览：{解析预扫描 `COMPONENT:` 行，格式为 `目录名(文件数)` 逗号分隔，如 `components(42), pages(18), hooks(8)`；无 `COMPONENT:` 行时显示"无可选子目录"}
{LANGUAGE_ID=python 时}
- Python 源码文件（src 或顶层包下 .py）：{SOURCE_FILE_COUNT} 个
- 代码行数：{SOURCE_LINE_COUNT} 行
- 配置文件：{FORMAL_CONFIG_FILE_COUNT} 个
- 包目录概览：{解析预扫描 `COMPONENT:` 行，格式为 `目录名(文件数)` 逗号分隔，如 `myapp(42), api(18)`；无 `COMPONENT:` 行时显示"无可选子目录"}

🧩 技术栈扫描：
- 识别数量：{解析 `TECH_STACK:` 行数量；未识别专项技术栈时显示 0}
- 启用专项规则：{识别到专项技术栈时显示 "是"，否则显示 "否，仅启用通用{LANGUAGE_ID=java 时显示 Java，frontend 时显示前端，python 时显示 Python}审查规则"}

{识别到 TECH_STACK 且 dependency != none 时展示以下表格，最多展示 12 个}
| 技术栈 | 识别证据 | 建议维度 | 专项规则 |
|--------|----------|----------|----------|
| {技术栈名称} | {dependency，若为 file: 前缀则展示为 文件:{路径}} | {dimensions} | {rules} |

{超过 12 个时追加}
- 另有 {N} 个技术栈未在摘要表中展示，完整结果已注入子 agent。

{未识别专项技术栈时展示}
- 未识别专项技术栈，仅启用通用{LANGUAGE_ID=java 时显示 Java，frontend 时显示前端，python 时显示 Python}审查规则。

🔌 lark-cli：{LARK_PLUGIN_INSTALLED=true 时显示 "✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书保存" / false 时显示 "⚠️ 飞书保存不可用：{LARK_PLUGIN_REASON}，报告将仅保存到本地文件"}

🧠 代码智能：{LANGUAGE_ID=java 时，CODE_INTELLIGENCE_AVAILABLE=true 显示 "✅ jdtls-lsp 可用，可用于跨目录调用链理解" / false 显示 "⚠️ 未启用 jdtls-lsp，将使用 Maven 静态依赖分批；建议安装 jdtls 并启用 jdtls-lsp 提升跨模块理解质量"}{LANGUAGE_ID=frontend 时，CODE_INTELLIGENCE_PROVIDER=typescript-lsp 显示 "✅ typescript-lsp 可用，可用于跨目录调用链理解" / none 显示 "⚠️ 未启用 typescript-lsp，将使用 import graph + 配置 + 文本检索静态分析；建议启用 typescript-lsp 提升跨文件理解质量"}{LANGUAGE_ID=python 时，CODE_INTELLIGENCE_PROVIDER=pyright|pylsp|jedi 显示 "✅ {PROVIDER} LSP 可用，可用于跨文件调用链理解" / pyright-cli 显示 "ℹ️ pyright CLI 可用，仅提供类型诊断；定义/引用查询使用静态检索" / none 显示 "⚠️ 未启用 Python LSP，将使用配置 + 文本检索静态分析；建议安装 pyright language server 或 python-lsp-server 提升跨文件理解质量"}

🧩 项目 ignore：{IGNORE_RULES_ENABLED=true 时显示 "✅ 已启用：.cc-code-reviewer/ignore/issues.yml（已忽略 {IGNORE_RULE_COUNT} 个问题）" / false 且文件不存在时显示 "未配置" / false 且不可读时显示 "⚠️ 文件存在但不可读：{原因}"}
```

**技术栈扫描展示规则**：
- 数据来源：{LANGUAGE_ID=java 时为 languages/java/project-scan.sh 输出；LANGUAGE_ID=frontend 时为前端 scan-project.sh 输出；LANGUAGE_ID=python 时为 Python scan-project.sh 输出}中的 `TECH_STACK:{技术栈}|dependency:{命中依赖或 file:路径}|dimensions:{建议维度}|rules:{专项规则}` 行
- 必须逐行解析所有 `TECH_STACK:` 行，`PROJECT_SCAN_RESULT` 注入子 agent 时仍保留完整原文
- `dependency:none` 表示未识别专项技术栈，不展示表格，只展示通用审查规则提示
- `dependency:file:` 表示通过配置文件识别，摘要中的识别证据展示为 `文件:{路径}`
- 识别证据超过 80 字可截断，但不得截断技术栈名称、建议维度和专项规则
- 摘要表最多展示 12 个技术栈；超过 12 个时追加 `另有 {N} 个技术栈未在摘要表中展示，完整结果已注入子 agent。`

### 第五步之后：按当前审查范围固化规模与分批门槛

**时机**：步骤 4 确定 `REVIEW_SCOPE` 后、步骤 4B 和模型选择之前执行。分批判定只能使用当前已确认范围，禁止继续沿用全仓预扫描规模。

- 进入步骤 3 的存量审查分支时先设置 `STOCK_REVIEW_STRATEGY=single-agent`，避免复用上一轮或上一入口的分批状态。
- `LANGUAGE_ID=java`：调用 `languages/java/collect-source-files.sh "$PROJECT_DIR" "$REVIEW_SCOPE"` 固化当前范围；全量审查传入 `全量代码`，指定模块传入已校验的模块路径列表。
- `LANGUAGE_ID=frontend|python`：调用对应 `collect-source-files.sh`；`REVIEW_SCOPE!=全量代码` 时再调用对应 `filter-source-manifest.sh` 收敛当前范围。
- 从收敛后的 manifest 重新计算 `REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT`。即使预扫描显示整个仓库很大，只要用户选择的当前范围未达到门槛，也不得进入分批。
- 增量审查固定不分批，后续仍由 `prepare-review-input.sh` 给出最终增量规模。

随后先以默认的 `single-agent` 调用确定性判定脚本：

```bash
BATCH_DECISION="$(bash "${PLUGIN_ROOT}/scripts/core/decide-batch-mode.sh" \
  "$PROJECT_TYPE" "$REVIEW_TYPE" "$REVIEW_FILE_COUNT" "$REVIEW_LINE_COUNT" \
  "$STOCK_REVIEW_STRATEGY")"
ESTIMATED_TOKENS="$(printf '%s\n' "$BATCH_DECISION" | sed -n 's/^ESTIMATED_TOKENS=//p')"
STEP_4B_REQUIRED="$(printf '%s\n' "$BATCH_DECISION" | sed -n 's/^STEP_4B_REQUIRED=//p')"
STOCK_REVIEW_STRATEGY="$(printf '%s\n' "$BATCH_DECISION" | sed -n 's/^STOCK_REVIEW_STRATEGY=//p')"
BATCH_MODE="$(printf '%s\n' "$BATCH_DECISION" | sed -n 's/^BATCH_MODE=//p')"
MAVEN_LARGE_REPO_MODE="$(printf '%s\n' "$BATCH_DECISION" | sed -n 's/^MAVEN_LARGE_REPO_MODE=//p')"
# 其他固定键可按同样方式解析。不得 eval 脚本输出。
```

脚本输出 `ESTIMATED_TOKENS`、`STEP_4B_REQUIRED`、`STOCK_REVIEW_STRATEGY`、`BATCH_MODE` 和 `MAVEN_LARGE_REPO_MODE`。只有 `STEP_4B_REQUIRED=true` 才执行步骤 4B；用户选择分批策略后，必须用新策略再次调用该脚本，最终结果是后续路径分支的唯一依据。禁止由主 Skill 口头估算或仅凭 `PROJECT_TYPE=maven-multi` 设置 `BATCH_MODE=true`。

### 第五步之后：选择审查模型 + 固定 1M 上下文

**时机**：在当前范围规模固化与可选步骤 4B 之后、批次规划之前执行。

不再读取底层模型映射或侦测上下文窗口。模型选择前直接设置固定分批常量：

```bash
CONTEXT_WINDOW_TOKENS=1000000
CONTEXT_SCALE=5
CONTEXT_TIER=large
```

所有受支持模型都按 1M 上下文规划。模型档位只影响审查质量与速度，不影响批次预算。

**必须调用 INTERACT 工具，参数如下**：
- question: "请选择审查使用的模型档位"
- header: "审查模型"
- options:
  - label: "继承当前会话（推荐）"
    description: "不切换宿主模型，保持当前会话的模型与推理强度"
  - label: "经济档"
    description: "优先低成本和速度，适合小项目或快速扫雷"
  - label: "平衡档"
    description: "平衡速度与分析质量"
  - label: "最高能力档"
    description: "优先最高推理能力，适合深度、安全或大仓库审查"
- multiSelect: false

**用户响应后变量赋值**：
- 继承当前会话 → `MODEL_PROFILE=inherit`
- 经济档 → `MODEL_PROFILE=economy`
- 平衡档 → `MODEL_PROFILE=balanced`
- 最高能力档 → `MODEL_PROFILE=maximum`

> **设计依据**：后续模型统一使用 1M 上下文，不再保留易误判的模型白名单、后缀标记和 200k 回退。模型选择放在分批之前，保持交互顺序稳定。

> **跨平台模型档位**：共享流程只保存 `inherit / economy / balanced / maximum`。具体模型 ID 或 reasoning effort 只由当前 runtime adapter 决定；不得把 Claude、Codex 或 ZCode 的具体模型名写回共享状态。

### 第五步之后：分批判定

**时机**：在模型选择 + 固定 1M 常量设置完成后、步骤 5 前执行判定。

**确定性判定**（固定 1M 上下文）：
```
estimated_tokens = REVIEW_FILE_COUNT × 500 + REVIEW_LINE_COUNT × 3
非 Maven 多模块：BATCH_MODE = 存量审查 AND estimated_tokens > 1000000
Maven 多模块：只有当前范围达到 estimated_tokens > 1000000，
               且用户在步骤 4B 选择 module-sequential / ai-planned，BATCH_MODE 才为 true
```

以上规则必须由 `scripts/core/decide-batch-mode.sh` 执行。小型 Maven 多模块项目即使是全量存量审查，也保持 `STOCK_REVIEW_STRATEGY=single-agent`、`BATCH_MODE=false`；不得展示步骤 4B，不得生成批次计划。

**前提**：分批模式仅对存量审查生效。增量审查的变更文件数通常远低于阈值；即使超过阈值，batch agent 缺少增量上下文（GIT_LOG/CHANGED_FILES），无法判断问题是变更引入还是存量，因此不进入分批。

**参数来源**：
- `REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT` 的来源按语言分支：
  - `LANGUAGE_ID=java`：从步骤 4 后 `collect-source-files.sh` 固化的当前范围 manifest 统计，口径仅包含 `src/main/java` 生产源码
  - `LANGUAGE_ID=frontend`：从步骤 4 后收集并按需过滤的当前范围 manifest 统计，口径仅包含 `src/` 下生产 `.ts/.tsx/.js/.jsx/.vue/.mjs/.cjs`
  - `LANGUAGE_ID=python`：从步骤 4 后收集并按需过滤的当前范围 manifest 统计，口径仅包含 `src/` 或顶层包下生产 `.py`
- `500`：每个文件的工具调用 + agent 评估开销（token）
- `3`：每行代码平均 token 数
- `1000000`：自动开启分批的严格触发阈值；`estimated_tokens=1000000` 时仍走单 agent，只有大于该值才分批

> 自动触发阈值与单批预算是两个概念：是否分批看 `estimated_tokens > 1000000`；进入文件级分批后，planner 的默认单批输入预算仍为 `500000`，用于给系统提示、工具调用、跨文件分析和报告输出留出空间。

**判定结果**：
- `BATCH_MODE=false` → 走现有单 agent 流程，不做任何改动
- `BATCH_MODE=true` → 进入分批模式

**执行要求**：分批判定至少延迟到步骤 3 确定审查入口后执行；如果审查范围会影响 `REVIEW_FILE_COUNT` / `REVIEW_LINE_COUNT`，必须在步骤 4 确定范围后按所选范围重新计算。

### Maven 大仓库模式判定

仅当确定性脚本输出 `MAVEN_LARGE_REPO_MODE=true` 时进入 Maven 大仓库模式。其前提全部成立：
- `PROJECT_TYPE=maven-multi`（Maven 多模块）
- `REVIEW_TYPE=存量审查`
- 当前 `REVIEW_SCOPE` 固化后的 `estimated_tokens > 1000000`
- 用户已在步骤 4B 选择 `STOCK_REVIEW_STRATEGY=ai-planned` 或 `module-sequential`

进入 Maven 多模块存量分批后必须调用 `languages/java/plan-large-batches.sh`，并把 `REVIEW_SCOPE` 原样作为第 5 个参数传入。即使只选择一个模块，只要当前范围已达到门槛并选定分批策略，也不得改走文件级 planner。Maven 多模块存量分批绝不调用 `languages/java/plan-file-batches.sh`；该文件级 planner 只服务 Maven 单模块、Gradle 或未知 Java 项目。

固定 1M 上下文下的判定与批次上限：
```text
estimated_tokens > 1000000
TARGET_BATCH_LOC = 250000
SOFT_MIN_BATCH_LOC = 150000
SOFT_MAX_BATCH_LOC = 250000
HARD_MAX_BATCH_LOC = 250000
review_cost = java_loc + java_file_count * 25
TARGET_BATCH_COST = 260000
SOFT_MIN_BATCH_COST = 160000
SOFT_MAX_BATCH_COST = 300000
HARD_MAX_BATCH_COST = 325000
```

**固定 1M 机制**：`CONTEXT_WINDOW_TOKENS=1000000`、`CONTEXT_SCALE=5` 只作为统一计划元数据保留。planner 不接受任何模型上下文参数或环境变量；只有 `CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET` 可人工覆盖文件级单批输入预算。

Maven 大仓库规划使用 semantic-cost batching：
- 先生成 work units，而不是直接把顶层 Maven module 当批次
- 超过 `HARD_MAX_BATCH_LOC` 或 `HARD_MAX_BATCH_COST` 的 work unit 必须继续拆分；oversized modules are split before plan emission
- 优先按嵌套 Maven 子模块拆分，仍超限时按稳定 Java package root 拆分
- 0 行依赖/BOM 模块与极小 bootstrap 模块默认进入 `context_roots`，不单独成批
- tiny tail batches 必须合并、转为 context，或写明无法合法合并的原因
- `context_roots` 只用于理解，受 context cost 上限约束，不计入 Java 文件覆盖率

Maven 大仓库模式仍然只对达到当前范围门槛的存量审查生效。增量审查、未达门槛的 Maven 多模块项目、Gradle 小项目和单模块小项目继续走单 agent 流程。指定模块审查达到门槛后可以进入 Maven 大仓库模式：`ai-planned` 使用 semantic-cost batching 在所选模块内智能拆分，`module-sequential` 按所选模块依次启动批次；模块过大时必须提醒用户但不阻断。

Maven 大仓库模式必须在步骤 1 确定 `REVIEW_MODE` 且步骤 3/4 确定审查入口与范围后、步骤 5 选择本轮执行批次前完成规划；规划完成后必须立即展示分批表格和推荐计划，再进入 INTERACT。

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

bash "${PLUGIN_ROOT}/scripts/languages/java/plan-large-batches.sh" "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "$SEMANTIC_LEVEL" "$REVIEW_SCOPE" "$STOCK_REVIEW_STRATEGY"
bash "${PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

### 第五步：交互式参数收集

按以下步骤逐个调用 **INTERACT 工具**（禁止用纯文本输出替代）。每个步骤必须单独调用 INTERACT 并等待用户响应后才能进入下一步。**禁止在一次回复中合并多个交互步骤。**

**注意**：分支选择已在第二步（项目识别与分支检测）完成，本步骤从选择审查类型开始。

详细步骤定义见下方「交互式确认步骤定义」章节。

### 第六步之前：准备审查参考文件路径

在调用子 agent 之前，必须基于插件根目录生成参考文件绝对路径，并校验文件可读：

```bash
REPORT_FORMAT_PATH="${PLUGIN_ROOT}/references/report-format.md"
if [ "$LANGUAGE_ID" = "frontend" ]; then
  REVIEW_FRAMEWORK_PATH="${PLUGIN_ROOT}/references/languages/frontend/review-framework.md"
  REACT_RULES_PATH="${PLUGIN_ROOT}/references/languages/frontend/react-rules.md"
  VUE_RULES_PATH="${PLUGIN_ROOT}/references/languages/frontend/vue-rules.md"
  NODE_RULES_PATH="${PLUGIN_ROOT}/references/languages/frontend/node-rules.md"
  SOURCE_SCOPE_PATH="${PLUGIN_ROOT}/references/languages/frontend/source-scope.md"
  test -r "$REVIEW_FRAMEWORK_PATH"
  test -r "$REACT_RULES_PATH"
  test -r "$VUE_RULES_PATH"
  test -r "$NODE_RULES_PATH"
  test -r "$SOURCE_SCOPE_PATH"
elif [ "$LANGUAGE_ID" = "python" ]; then
  REVIEW_FRAMEWORK_PATH="${PLUGIN_ROOT}/references/languages/python/review-framework.md"
  DJANGO_RULES_PATH="${PLUGIN_ROOT}/references/languages/python/django-rules.md"
  FASTAPI_RULES_PATH="${PLUGIN_ROOT}/references/languages/python/fastapi-rules.md"
  SOURCE_SCOPE_PATH="${PLUGIN_ROOT}/references/languages/python/source-scope.md"
  test -r "$REVIEW_FRAMEWORK_PATH"
  test -r "$DJANGO_RULES_PATH"
  test -r "$FASTAPI_RULES_PATH"
  test -r "$SOURCE_SCOPE_PATH"
else
  REVIEW_FRAMEWORK_PATH="${PLUGIN_ROOT}/references/languages/java/review-framework.md"
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

**单 agent 模式下的 source manifest 与审查输入生成**：

三种语言都必须在调用子 agent 前固化正式源码边界。Java 使用 `collect-source-files.sh` 收集 `src/main/java`；前端和 Python 继续使用各自的正式源码收集器。存量审查随后由 `prepare-review-input.sh` 写入不可变 `REVIEW_INPUT_PATH`，并一并注入子 agent：

```bash
# 所有语言：生成不可变 source manifest；Java 额外接受指定模块范围。
if [ "$LANGUAGE_ID" = "java" ]; then
  MANIFEST="$(mktemp)"
  bash "${PLUGIN_ROOT}/scripts/languages/java/collect-source-files.sh" \
    "$PROJECT_DIR" "${REVIEW_SCOPE:-全量代码}" > "$MANIFEST"
else
  MANIFEST="$(mktemp)"
  bash "${PLUGIN_ROOT}/scripts/languages/${LANGUAGE_ID}/collect-source-files.sh" "$PROJECT_DIR" > "$MANIFEST"

  # 只有前端/Python 存量审查的「指定目录/模块」才按 REVIEW_SCOPE 过滤。
  # 增量审查以 CHANGED_FILES_OUTPUT 为主输入，manifest 只用作生产源码边界，不做目录过滤。
  if [ "$REVIEW_TYPE" = "存量审查" ] && [ "${REVIEW_SCOPE:-全量代码}" != "全量代码" ]; then
    FILTERED="$(mktemp)"
    bash "${PLUGIN_ROOT}/scripts/languages/${LANGUAGE_ID}/filter-source-manifest.sh" \
      "$PROJECT_DIR" "$MANIFEST" "$REVIEW_SCOPE" > "$FILTERED"
    mv "$FILTERED" "$MANIFEST"
    if [ ! -s "$MANIFEST" ]; then
      echo "NO_${LANGUAGE_ID}_SOURCE_FILES_IN_SCOPE=$REVIEW_SCOPE" >&2
      exit 1
    fi
  fi

fi

if [ ! -s "$MANIFEST" ]; then
  echo "NO_${LANGUAGE_ID}_SOURCE_FILES=$PROJECT_DIR" >&2
  exit 1
fi

if [ "$REVIEW_TYPE" = "存量审查" ]; then
  INPUT_MODE=full
  [ "${REVIEW_SCOPE:-全量代码}" = "全量代码" ] || INPUT_MODE=scoped
  REVIEW_INPUT_PATH="$(bash "${PLUGIN_ROOT}/scripts/core/prepare-review-input.sh" \
    "$PROJECT_DIR" "$LANGUAGE_ID" "$INPUT_MODE" 0 "$MANIFEST" | sed -n 's/^REVIEW_INPUT_PATH=//p')"
else
  REVIEW_INPUT_PATH="$(bash "${PLUGIN_ROOT}/scripts/core/prepare-review-input.sh" \
    "$PROJECT_DIR" "$LANGUAGE_ID" incremental "$COMMIT_COUNT" "$MANIFEST" | sed -n 's/^REVIEW_INPUT_PATH=//p')"
fi
test -r "$REVIEW_INPUT_PATH"

# 项目审查规则必须和冻结输入使用同一正式文件集合。resolver 的
# review-input 模式只读取 selected=true，增量审查不会带入范围外文件。
REVIEW_RULES_RESOLVED_PATH="${REVIEW_INPUT_PATH%.json}-review-rules.json"
bash "${PLUGIN_ROOT}/scripts/core/resolve-review-rules.sh" \
  "$PROJECT_DIR" "$REVIEW_INPUT_PATH" "$REVIEW_RULES_RESOLVED_PATH" \
  "${CC_CODE_REVIEWER_REVIEW_RULES_PATH:-$PROJECT_DIR/.cc-code-reviewer/review-rules.yml}" review-input >/dev/null
test -r "$REVIEW_RULES_RESOLVED_PATH"

# 规模必须来自同一个冻结输入，不能在增量路径继续展示全量 manifest 规模。
REVIEW_FILE_COUNT="$(perl -MJSON::PP -e 'local $/; print decode_json(<>)->{selected_item_count}+0' "$REVIEW_INPUT_PATH")"
REVIEW_LINE_COUNT="$(perl -MJSON::PP -e 'local $/; print decode_json(<>)->{selected_line_count}+0' "$REVIEW_INPUT_PATH")"
```

调用逻辑动作 `DISPATCH_AGENT` 启动子代理，`agent_prompt` 按 `LANGUAGE_ID` 选择：
- `LANGUAGE_ID=java` -> `${PLUGIN_ROOT}/agents/cc-code-reviewer.md`，description: `"执行 Java 代码审查"`
- `LANGUAGE_ID=frontend` -> `${PLUGIN_ROOT}/agents/cc-code-reviewer-frontend.md`，description: `"执行前端代码审查"`
- `LANGUAGE_ID=python` -> `${PLUGIN_ROOT}/agents/cc-code-reviewer-python.md`，description: `"执行 Python 代码审查"`
- prompt: 注入审查参数表 + 审查参考文件路径 + 项目概况 + 增量数据（所有语言的存量/增量审查均注入 `REVIEW_INPUT_PATH`、`REVIEW_RULES_RESOLVED_PATH` 和 source manifest；正式范围只认 selected=true）
- model_profile: {MODEL_PROFILE}

详细参数注入格式见下方「子 agent 调用规范」章节。

#### 路径 B：分批并行模式（BATCH_MODE=true）

重复调用逻辑动作 `DISPATCH_AGENT` 启动多个子代理，按轮次并发执行。

**编排逻辑**：

如果当前为 Maven 大仓库模式，主 skill 必须先根据 `CURRENT_RUN_BATCH_LIMIT` 或 `BATCH_SELECTION` 计算本轮 `RUN_BATCH_IDS`：
- `BATCH_SELECTION` 存在时，只调度该列表中的批次
- `CURRENT_RUN_BATCH_LIMIT=3|5|10` 时，只调度状态表顺序中前 N 个 `pending` / `failed` 批次
- `CURRENT_RUN_BATCH_LIMIT=all` 时，调度全部 `pending` / `failed` 批次
- `completed` 批次永远不进入 `RUN_BATCH_IDS`
- 后续启动和合并文案都必须使用 `RUN_BATCH_IDS` / `RUN_BATCH_COUNT`，不得用总 `BATCH_COUNT` 代替本轮执行批次

以 CONCURRENCY=2、BATCH_COUNT=6 为例：

```
轮次 1：同时启动 Agent(batch-1) + Agent(batch-2)
  → 等待全部完成
轮次 2：同时启动 Agent(batch-3) + Agent(batch-4)
  → 等待全部完成
轮次 3：同时启动 Agent(batch-5) + Agent(batch-6)
  → 等待全部完成
```

每轮同时发出 CONCURRENCY 个 `DISPATCH_AGENT` 调用。当前轮所有 agent 返回后，开始下一轮。CONCURRENCY=1 时退化为串行。

**每个 batch agent 的调用参数**：

- description: "Batch {BATCH_INDEX}/{BATCH_COUNT} 代码审查"
- agent_prompt: 按 `LANGUAGE_ID` 选择 `${PLUGIN_ROOT}/agents/cc-code-reviewer.md`、`${PLUGIN_ROOT}/agents/cc-code-reviewer-frontend.md` 或 `${PLUGIN_ROOT}/agents/cc-code-reviewer-python.md`
- model_profile: {MODEL_PROFILE}
- prompt: 见下方「Batch Agent Prompt 注入格式」

**文件级分批参数派生**（`strategy=file-token-batching`）：每次启动子 agent 前必须用当前 `BATCH_ID` 生成并校验以下路径，不得只在 prompt 中保留未替换的 `{BATCH_FILE_LIST}` 占位符：

```bash
BATCH_PLAN_PATH="$RUN_DIR/batches/$BATCH_ID.json"
BATCH_FILE_LIST="$RUN_DIR/batches/$BATCH_ID.files"
BATCH_STATUS_PATH="$RUN_DIR/results/$BATCH_ID.status.json"
BATCH_RESULT_PATH="$RUN_DIR/results/$BATCH_ID.md"
test -r "$BATCH_PLAN_PATH"
test -r "$BATCH_FILE_LIST"
```

Maven 大仓库模式不注入 `BATCH_FILE_LIST`，仍以 `BATCH_PLAN_PATH` 中的 `scan_roots` / `units` 为正式边界。

**Batch Agent Prompt 注入格式**：

每个 batch agent 的 prompt 与现有格式一致，但额外注入以下参数并做以下调整：

```
## 审查任务参数（外部注入，请直接使用，无需再次确认）

| 参数 | 值 |
|------|-----|
| 项目路径 | {PROJECT_DIR} |
| 项目名称 | {PROJECT_NAME} |
| 项目类型 | {PROJECT_TYPE} |
| 语言 ID | {LANGUAGE_ID} |
| 审查类型 | {REVIEW_TYPE} |
| 审查范围 | {REVIEW_SCOPE} |
| 审查模式 | {REVIEW_MODE} |
| 审查模型 | {MODEL_PROFILE} |
| 审查文件数量 | {BATCH_FILE_COUNT} |
| 审查代码行数 | {BATCH_LINE_COUNT} |
| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |
| React 规则路径 | {REACT_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| Vue 规则路径 | {VUE_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| Node 规则路径 | {NODE_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| Django 规则路径 | {DJANGO_RULES_PATH}（仅 LANGUAGE_ID=python） |
| FastAPI 规则路径 | {FASTAPI_RULES_PATH}（仅 LANGUAGE_ID=python） |
| 源码范围路径 | {SOURCE_SCOPE_PATH}（仅 LANGUAGE_ID=frontend 或 python） |
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
| source manifest | {不可变源码清单绝对路径}（仅 frontend/python 文件级分批） |
| 本批审查文件列表 | {BATCH_FILE_LIST}（仅文件级分批模式） |
| 审查输入清单 | {RUN_DIR/review-input.json 或 未生成} |
| 项目审查规则解析结果 | {RUN_DIR/review-rules.json} |
| 审查输出模式 | 仅发现清单 |

### 本批审查边界
请读取 `BATCH_PLAN_PATH`，按批次计划中的策略字段确定正式审查边界：
- **Maven 大仓库模式**（plan.json 含 `scan_roots` 或 `units`）：以 `scan_roots` 作为正式审查边界。若批次计划包含 `units`，以 `units[].path` / `units[].scan_roots` 对应的 `scan_roots` 为准；`context_roots` are read-only context，只能用于理解依赖关系。
- **文件级分批模式**（plan.json 含 `batch_file_list`，即 file-token-batching 策略）：以 `BATCH_FILE_LIST` 指向的文件清单（对应 batch.json 的 `batch_file_list` 字段）作为本批正式审查文件集合。该清单由主 skill 通过 `collect-source-files.sh` 生成并经 `filter-source-manifest.sh` 收敛，子 agent 直接使用，不得再次扫描或外扩。

**LANGUAGE_ID=java 时**：
Maven 大仓库批次的正式文件必须限定为 `scan_roots` 内的 `src/main/java`；Maven 单模块、Gradle 或未知项目的 file-token-batching 批次必须限定为 `BATCH_FILE_LIST`。`src/test/java` 只能作为测试质量判断的只读上下文，不计入已审查 Java 文件，也不得作为正式问题位置。
`SEMANTIC_LEVEL=jdtls-lsp` 时表示 jdtls-lsp 可用时必须使用：本批子 agent 必须用 jdtls 查询 definition、references、implementations、call hierarchy 来理解跨目录调用链，并在批次结果中写明「语义增强使用情况」。正式问题必须位于当前模式的 `scan_roots` 或 `BATCH_FILE_LIST` 边界内。
`SEMANTIC_LEVEL=maven-static` 时才允许回退 Maven 静态依赖与文本检索。

**LANGUAGE_ID=frontend 时**：
正式扫描文件必须限定为 `BATCH_FILE_LIST`（文件级分批）内的 `src/` 下生产源码（`.ts/.tsx/.js/.jsx/.vue/.mjs/.cjs`）；测试文件（`*.test.*`/`*.spec.*`/`__tests__`/`e2e`/`cypress`）、产物（`dist`/`build`）、`.d.ts` 只能作为只读上下文，不计入已审查前端文件，也不得作为正式问题位置。
`SEMANTIC_LEVEL=typescript-lsp` 时必须用 TS LSP 查询 definition/references/implementations/diagnostics 理解跨目录调用链，并在批次结果中写明「语义增强使用情况」。正式问题必须位于 `BATCH_FILE_LIST` 内的生产源码。
`SEMANTIC_LEVEL=none` 时才允许回退 import graph + 配置 + 文本检索静态分析。

**LANGUAGE_ID=python 时**：
正式源码必须限定为 `BATCH_FILE_LIST`（文件级分批）内的生产源码（`src/**/*.py` 或顶层包 `*.py`，含根级单文件应用入口）。`PROJECT_SCAN_RESULT` 的 `FORMAL_CONFIG_FILE:` 路径（含 `uv.lock`/`poetry.lock`/`Pipfile.lock`）也可产生正式配置问题，但不计入 Python 源码覆盖率；分批模式仅 `batch-001` 审查这些正式配置，避免跨批重复。`tests/`、`test_*.py`、`migrations/`（Django/Alembic 生成代码）、`venv/`、`__pycache__/`、`build/` 只能作为只读上下文，不得作为正式问题位置。
`SEMANTIC_LEVEL=pyright`/`pylsp`/`jedi` 时必须用对应 LSP 查询 definition/references/diagnostics 理解跨文件调用链，并在批次结果中写明「语义增强使用情况」。生产源码问题必须位于 `BATCH_FILE_LIST` 内；正式配置问题必须位于 `FORMAL_CONFIG_FILE:` 路径内。
`SEMANTIC_LEVEL=pyright-cli` 时只运行注入命令获取 diagnostics；definition/references/hover 必须使用静态检索，不得声称由 LSP 提供。
`SEMANTIC_LEVEL=none` 时才允许回退配置 + 文本检索静态分析。

如果疑似问题位置在当前正式边界（`BATCH_FILE_LIST`、`scan_roots`，或 Python 的 `FORMAL_CONFIG_FILE:`）外，写入「跨批依赖待复核」。

若注入“项目审查规则解析结果”，只读取其中本批正式文件命中的规则并作为额外审查重点；`merge_language_rule=true` 时与语言框架规则共同执行，任何规则不得降低现有 P0 门槛、ignore 规则或正式扫描边界。

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
| 文件列表来源 | 所有语言：注入固化后的 `REVIEW_INPUT_PATH`（selected=true 为正式范围）；Java 由 collect-source-files.sh 收集，frontend/python 由各自 collect 收集 | 外部注入（BATCH_FILE_LIST 或 scan_roots），agent 不扫描 |
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

脚本文件名不再带 phase 编号（功能名描述职责，执行顺序在此编排）。通用脚本在 `scripts/core/`，Java 专属在 `scripts/languages/java/`，前端专属在 `scripts/languages/frontend/`。1.4.0 起不再保留旧 phase 脚本入口。

### Java 扫描流程

1. `core/detect-project.sh` → 识别项目路径
2. `core/detect-branches.sh` → 列出分支（多分支则 INTERACT 选）
3. `core/switch-branch.sh` → 切换到选定分支（按需）
4. `core/detect-language.sh` → 探测语言（固定 java）
5. `languages/java/project-scan.sh` → Java 预扫描（Maven/技术栈）
6. `languages/java/detect-code-intelligence.sh` → jdtls 探测
7. `core/detect-lark-plugin.sh` → lark-cli 检测
8. 设置固定 1M 上下文常量（`CONTEXT_WINDOW_TOKENS=1000000`、`CONTEXT_SCALE=5`）
9. 读 ignore 规则 → 输出预扫描摘要
10. INTERACT 交互（模式/报告/入口/范围…）
11. `core/decide-batch-mode.sh` → 按当前范围决定是否展示步骤 4B / 是否分批
12. [分批] `languages/java/plan-large-batches.sh` 或 `plan-file-batches.sh`
13. [分批] `core/show-batch-status.sh` → 展示批次状态
14. [分批] 启动 agent → `core/merge-batch-results.sh` 合并
15. [增量] `core/preview-recent-commits.sh` + `core/prepare-incremental.sh`

### 前端扫描流程

1. `core/detect-project.sh` → 识别项目路径
2. `core/detect-branches.sh` → 列出分支（多分支则 INTERACT 选）
3. `core/switch-branch.sh` → 切换到选定分支（按需）
4. `core/detect-language.sh` → 探测语言（固定 frontend）
5. `languages/frontend/scan-project.sh` → 前端预扫描（PROFILE_SCHEMA）
6. `languages/frontend/detect-code-intelligence.sh` → typescript-lsp 探测
7. `core/detect-lark-plugin.sh` → lark-cli 检测
8. 设置固定 1M 上下文常量（`CONTEXT_WINDOW_TOKENS=1000000`、`CONTEXT_SCALE=5`）
9. 读 ignore 规则 → 输出预扫描摘要
10. INTERACT 交互（模式/报告/入口/范围…）
11. `core/decide-batch-mode.sh` → 按当前范围确定单 agent / 文件级分批
12. [分批] `core/plan-file-batches.sh` → 前端文件级分批
13. [分批] `core/show-batch-status.sh` → 展示批次状态
14. [分批] 启动 agent → `core/merge-batch-results.sh` 合并
15. [增量] `core/preview-recent-commits.sh` + `core/prepare-incremental.sh`


### Python 扫描流程

1. `core/detect-project.sh` -> 识别项目路径
2. `core/detect-branches.sh` -> 列出分支（多分支则 INTERACT 选）
3. `core/switch-branch.sh` -> 切换到选定分支（按需）
4. `core/detect-language.sh` -> 探测语言（固定 python）
5. `languages/python/scan-project.sh` -> Python 预扫描（PROFILE_SCHEMA）
6. `languages/python/detect-code-intelligence.sh` -> pyright/pylsp/jedi 探测
7. `core/detect-lark-plugin.sh` -> lark-cli 检测
8. 设置固定 1M 上下文常量（`CONTEXT_WINDOW_TOKENS=1000000`、`CONTEXT_SCALE=5`）
9. 读 ignore 规则 -> 输出预扫描摘要
10. INTERACT 交互（模式/报告/入口/范围…）
11. `core/decide-batch-mode.sh` -> 按当前范围确定单 agent / 文件级分批
12. [分批] `core/plan-file-batches.sh` -> Python 文件级分批
13. [分批] `core/show-batch-status.sh` -> 展示批次状态
14. [分批] 启动 agent → `core/merge-batch-results.sh` 合并
15. [增量] `core/preview-recent-commits.sh` + `core/prepare-incremental.sh`

---

## 交互式确认步骤定义

> **强制规则**：
> - 每个步骤必须调用 INTERACT 工具，**禁止用纯文本提问替代**
> - 每个步骤的 INTERACT 调用后，必须等待用户响应
> - 不允许在一次回复中包含多个交互步骤的动作
> - 用户响应后，处理结果、设置变量，然后才能进入下一步

> **注意**：分支选择已在第二步（项目识别与分支检测）完成，本步骤从选择审查模式开始；审查模式和报告保存方式必须在审查入口前确认。

### 步骤 1：选择审查模式

审查模式选择是固定必问步骤。无论是否进入分批、无论当前项目是 Java、前端还是 Python，都**必须调用 INTERACT 工具，参数如下**：
- question: "请选择审查模式"
- header: "审查模式"
- options:
  - label: "fast（仅输出 P0）"
    description: "只报告已证实、足以阻断上线的 P0；P1/P2/P3 和待确认项均不输出"
  - label: "standard（推荐）"
    description: "标准审查，覆盖常规核心维度 + API设计 + 缓存基础 + 核心测试缺失，日常迭代推荐"
  - label: "deep"
    description: "深度审查，启用目标语言的全部审查维度（Java 15 维度；前端/Python 12 维度），适合大版本上线前"
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

**必须调用 INTERACT 工具，参数如下**：
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

**必须调用 INTERACT 工具，参数如下**：
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
- 增量审查 → REVIEW_ENTRY=增量审查，REVIEW_TYPE=增量审查，STOCK_REVIEW_STRATEGY=single-agent
- 全量审查 → REVIEW_ENTRY=全量审查，REVIEW_TYPE=存量审查，REVIEW_SCOPE=全量代码，STOCK_REVIEW_STRATEGY=single-agent
- 指定模块 → REVIEW_ENTRY=指定模块，REVIEW_TYPE=存量审查，STOCK_REVIEW_STRATEGY=single-agent

### 步骤 4：选择审查范围（条件步骤）

**触发条件**：
- 增量审查时 → 必须执行
- 指定模块 + 多模块 → 必须执行（模块选择流程见下）
- 指定模块 + 前端（`LANGUAGE_ID=frontend`，`PROJECT_TYPE=frontend-react|frontend-vue2|frontend-vue3|node`）→ 按前端目录选择流程处理（见下）；若预扫描无 `COMPONENT:` 行（`src/` 下无子目录），跳过并自动设 `REVIEW_SCOPE=全量代码`，提示用户"前端项目未识别到可选择的 src 子目录，将进行全量审查"
- 指定模块 + Python（`LANGUAGE_ID=python`，`PROJECT_TYPE=python-django|python-fastapi|python-generic`）→ 按 Python 包目录选择流程处理（见下）；若预扫描无 `COMPONENT:` 行（只有根级单文件等情形），跳过并自动设 `REVIEW_SCOPE=全量代码`，提示用户"Python 项目未识别到可选择的包目录，将进行全量审查"
- 指定模块 + 单模块 → 跳过，自动设 REVIEW_SCOPE=全量代码
- 全量审查 → 跳过，已在步骤 3 设 REVIEW_SCOPE=全量代码

> 前端项目（`PROJECT_TYPE=frontend-react|frontend-vue2|frontend-vue3|node`）既非 `*-single` 也非 `maven-multi`，不进入 Java 的模块树流程；前端的"模块"语义是 `src/` 下的顶层目录（即预扫描 `COMPONENT:` 行）。

> Python 项目也不进入 Java 模块树流程；Python 的"模块"语义是最终 source manifest 派生的不重叠顶层包目录（即预扫描 `COMPONENT:` 行）。

**增量审查时，必须先扫描并展示最近提交，再调用 INTERACT 工具**：

1. 执行最近提交预览脚本（仅用于交互式用户决策，不替代后续增量预处理）：`bash "${PLUGIN_ROOT}/scripts/core/preview-recent-commits.sh" "$PROJECT_DIR"`
2. 展示脚本输出，格式如下；最多展示最近 10 次提交，不足 10 次时展示实际数量：
   ```text
   📜 最近提交概览：
   # === 最近提交预览 ===
   1. {short_hash} {commit message}
   2. {short_hash} {commit message}
   ...
   ```
3. 如果输出为 `（无提交记录）`，告知用户当前 Git 仓库没有可用于增量审查的提交，不进入提交次数选择。

**然后必须调用 INTERACT 工具，参数如下**：
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

**增量审查用户响应后变量赋值**：
- 最近 1 次 → `COMMIT_COUNT=1`，`REVIEW_SCOPE=最近 1 次提交`
- 最近 3 次 → `COMMIT_COUNT=3`，`REVIEW_SCOPE=最近 3 次提交`
- 最近 5 次 → `COMMIT_COUNT=5`，`REVIEW_SCOPE=最近 5 次提交`
- 最近 10 次 → `COMMIT_COUNT=10`，`REVIEW_SCOPE=最近 10 次提交`

**指定模块 + 多模块时，先展示模块树，再调用 INTERACT 工具**：

**展示模块树**（在调用 INTERACT 之前，用文本输出；完整模块列表只能作为普通文本展示，不得放入 INTERACT options）：
```
📊 项目模块概览：

{项目名称}/
├── {模块1名称}/     {N} 类 · {M} 行
├── {模块2名称}/     {N} 类 · {M} 行
└── {模块3名称}/     {N} 类 · {M} 行

合计：{总类数} 类 · {总行数} 行
```

数据来源：解析阶段四预扫描输出的 `MODULE:` 行，提取每个模块的名称、Java 文件数、代码行数。

**INTERACT payload 约束**：
- 不得把每个模块都作为 INTERACT option；大仓库模块数量可能很多，容易触发 Invalid tool parameters
- 该步骤最多 3 个固定选项，模块路径通过 Other/free-form 或后续输入步骤收集
- 模块列表越长，越应该只在普通文本概览中展示，并引导用户输入模块相对路径

**然后调用 INTERACT 工具，参数如下**：
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
- 选择"手动输入模块路径" 或 Other/free-form → 读取用户提供的模块相对路径，支持逗号、中文逗号、顿号、空格或换行分隔多个模块；若 INTERACT 当前交互没有返回自定义文本，追加一次 INTERACT 收集模块路径，header 使用 "输入模块"，仍只提供固定选项并要求用户在 Other/free-form 填写模块路径
- 模块路径必须是 `PROJECT_DIR` 内的相对路径；不得接受绝对路径、`..` 路径穿越或解析后位于项目根之外的路径，规划脚本必须以 `SELECTED_MODULE_OUTSIDE_PROJECT` 阻止越界输入
- 自定义模块路径必须逐个校验是否存在于预扫描结果的 `MODULE:` 行中；不存在时提示有效模块列表并重新收集，最多重试 3 次

**变量赋值**：
- 全部模块 → REVIEW_SCOPE=全量代码
- 前 5 个大模块 → REVIEW_SCOPE=模块路径（逗号分隔）
- 自定义模块路径 → REVIEW_SCOPE=模块路径（逗号分隔）

---

**指定模块 + 前端时，先展示 src 目录概览，再调用 INTERACT 工具**：

前端没有 Maven 模块，其可选择的"分区"是 `src/` 下的顶层目录（如 `components`/`pages`/`hooks`/`store`），由前端 `scan-project.sh` 输出的 `COMPONENT:` 行提供。

**展示目录概览**（在调用 INTERACT 之前，用文本输出；完整目录列表只能作为普通文本展示，不得放入 INTERACT options）：
```
📂 前端目录概览：

{项目名称}/src/
├── {目录1}/     {N} 文件 · {M} 行
├── {目录2}/     {N} 文件 · {M} 行
└── {目录3}/     {N} 文件 · {M} 行

合计：{总文件数} 文件 · {总行数} 行
```

数据来源：解析阶段四预扫描输出的 `COMPONENT:` 行（格式 `COMPONENT:{目录名}|{相对路径}|{文件数}|{代码行数}`），提取每个目录的名称、文件数、代码行数。单包项目相对路径通常是 `src/{目录名}`；monorepo/package 项目可能是 `apps/web/src/{目录名}` 或 `packages/admin/src/{目录名}`。仅展示 `COMPONENT:` 行，不展示 `src/` 下的零散文件。

**INTERACT payload 约束**：
- 不得把每个目录都作为 INTERACT option；目录数量可能较多
- 该步骤最多 3 个固定选项，目录路径通过 Other/free-form 或后续输入步骤收集

**然后调用 INTERACT 工具，参数如下**：
- question: "请选择本次希望 AI 扫描的 src 目录"
- header: "扫描目录"
- options:
  - label: "全部目录"
    description: "扫描 src 下的全部生产源码，等同全量审查"
  - label: "手动输入目录路径"
    description: "在 Other/free-form 中输入一个或多个 src 下相对路径（如 src/components,src/pages），逗号分隔"
  - label: "前 3 个大目录"
    description: "按代码行数选择预扫描结果中最大的 3 个 src 目录，适合先覆盖主要复杂度"
- multiSelect: false

**指定模块 + 前端用户响应后**：
- 选择"全部目录" → REVIEW_SCOPE=全量代码
- 选择"前 3 个大目录" → REVIEW_SCOPE=按 `COMPONENT:` 行代码行数降序取前 3 个目录的相对路径（如 `src/components`），逗号分隔
- 选择"手动输入目录路径" 或 Other/free-form → 读取用户提供的相对路径，支持逗号、中文逗号、顿号、空格或换行分隔多个目录；若 INTERACT 当前交互没有返回自定义文本，追加一次 INTERACT 收集目录路径，header 使用 "输入目录"，仍只提供固定选项并要求用户在 Other/free-form 填写目录路径
- 目录路径必须是 `src/` 下的相对路径（形如 `src/{目录名}` 或 `{目录名}`，后者自动补 `src/` 前缀）；不得接受绝对路径、`..` 路径穿越或解析后位于 `PROJECT_DIR/src/` 之外的路径
- 自定义目录路径必须逐个校验是否存在于预扫描结果的 `COMPONENT:` 行中；不存在时提示有效目录列表并重新收集，最多重试 3 次
- 校验通过后，主 skill 在前端 manifest 生成阶段（见「前端分批」段落）按所选目录过滤 source manifest，使分批与扫描真正收敛到所选目录

**变量赋值**：
- 全部目录 → REVIEW_SCOPE=全量代码
- 前 3 个大目录 → REVIEW_SCOPE=src 子目录相对路径（逗号分隔，如 `src/components,src/pages,src/hooks`）
- 自定义目录路径 → REVIEW_SCOPE=src 子目录相对路径（逗号分隔）

---

**指定模块 + Python 时，先展示包目录概览，再调用 INTERACT 工具**：

Python 可选分区由 `scan-project.sh` 基于最终 source manifest 输出的 `COMPONENT:` 行提供，各分区不重叠。分区策略：
- **Monorepo**（仓库内有 ≥2 个子项目根，即含 `pyproject.toml`/`setup.py`/`setup.cfg`/`requirements*.txt`/`Pipfile` 的子目录）：每个子项目根各成独立 COMPONENT，使 `services/api`、`services/worker` 等真实业务模块可被单独选择扫描。
- **单项目**（0 或 1 个子项目根）：`src` layout 使用 `src/` 下顶层包，flat layout 使用项目根下顶层包。

**展示包目录概览**：
```text
📂 Python 包目录概览：

{项目名称}/
├── {包1路径}/     {N} 文件 · {M} 行
├── {包2路径}/     {N} 文件 · {M} 行
└── {包3路径}/     {N} 文件 · {M} 行
```

数据来源：解析预扫描输出的 `COMPONENT:{名称}|{相对路径}|{文件数}|{代码行数}` 行。只展示这些行，根级单文件不作为可选包目录。

**必须调用 INTERACT 工具，参数如下**：
- question: "请选择本次希望 AI 扫描的 Python 包目录"
- header: "扫描包"
- options:
  - label: "全部包"
    description: "扫描所有 Python 生产源码，等同全量审查"
  - label: "手动输入包路径"
    description: "在 Other/free-form 中输入一个或多个 COMPONENT 相对路径，逗号分隔"
  - label: "前 3 个大包"
    description: "按代码行数选择最大的 3 个包目录"
- multiSelect: false

**Python 用户响应与校验**：
- "全部包" → `REVIEW_SCOPE=全量代码`
- "前 3 个大包" → 按 `COMPONENT:` 行代码行数降序取前 3 个相对路径，逗号分隔
- "手动输入包路径" 或 Other/free-form → 读取用户提供的相对路径；若未返回自定义文本，追加一次 INTERACT，header 使用"输入包"
- 路径必须是 `PROJECT_DIR` 内的相对路径，拒绝绝对路径、`..` 和越界解析
- 每个路径必须精确存在于预扫描 `COMPONENT:` 行；无效时展示有效路径并重新收集，最多重试 3 次
- 校验通过后设置 `REVIEW_SCOPE`，由 Python `filter-source-manifest.sh` 在单 agent 或分批路径中收敛清单

### 步骤 4B：选择存量审查方式（条件步骤）

**触发条件**：
- 当前范围已完成 manifest 固化和规模重算
- `scripts/core/decide-batch-mode.sh` 输出 `STEP_4B_REQUIRED=true`

也就是说，只有 `REVIEW_TYPE=存量审查`、`PROJECT_TYPE=maven-multi`，且**当前审查范围**满足 `ESTIMATED_TOKENS > 1000000` 时才展示本步骤。`ESTIMATED_TOKENS <= 1000000` 的 Maven 多模块仓库必须跳过本步骤并保持 `STOCK_REVIEW_STRATEGY=single-agent`、`BATCH_MODE=false`。

**必须调用 INTERACT 工具，参数如下**：
- question: "请选择存量审查方式"
- header: "审查方式"
- options（第一项必须根据 `REVIEW_SCOPE` 动态生成，禁止把全量审查称为“所选模块”）：
  - `REVIEW_SCOPE=全量代码` 时：
    - label: "按全部模块依次启动"
    - description: "当前全量范围内每个模块对应一个批次；模块过大时提醒但不阻断"
  - `REVIEW_SCOPE!=全量代码` 时：
    - label: "按所选模块依次启动"
    - description: "当前已选模块各对应一个批次；模块过大时提醒但不阻断"
  - label: "AI 智能规划分批"
    description: "按语义单元和 review cost 自动拆分，适合超大模块或希望批次更均衡时使用"
- multiSelect: false

**变量赋值**：
- 按全部模块依次启动 / 按所选模块依次启动 → STOCK_REVIEW_STRATEGY=module-sequential
- AI 智能规划分批 → STOCK_REVIEW_STRATEGY=ai-planned

赋值后必须再次调用 `scripts/core/decide-batch-mode.sh`，并以其输出覆盖 `BATCH_MODE` 和 `MAVEN_LARGE_REPO_MODE`。不得直接因为用户看到步骤 4B 就自行设置分批状态。

当用户选择 `module-sequential` 且当前范围内任一模块超过 `HARD_MAX_BATCH_LOC` 或 `HARD_MAX_BATCH_COST` 时，必须在确认计划前提示该模块为大批次，可能耗时更长或消耗更多 token，但不得阻断执行。

### 步骤 5：选择本轮执行批次（Maven 大仓库模式）

**触发条件**：满足「Maven 大仓库模式判定」。不满足时跳过此步骤。

触发此步骤前，必须先完成 Maven 大仓库分批规划，生成或恢复 `RUN_DIR/plan.json` 和 `RUN_DIR/batches/*.json`。

在调用 INTERACT 之前，必须先展示当前 run 状态、批次表、可执行批次和预估时间计划。`core/show-batch-status.sh` 只作为数据来源；不得只依赖 Bash 工具输出，因为宿主可能折叠工具结果。主 Skill 必须读取脚本输出，并在普通助手消息中重新展示完整 Markdown 表格和推荐计划，像技术栈扫描摘要一样直接展示给用户。
```bash
bash "${PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

该输出必须包含：
- 批次状态表：使用用户可见的 Markdown 表格，表头固定为 `| 批次 | 状态 | 行数 | 文件数 | 模块 |`，下一行必须为 `|------|------|------:|------:|------|`
- 模块列必须使用缩略名展示；当同一批次内模块存在共同工程前缀（例如 `yudao-module-`）时，去掉共同前缀，只展示真正的业务模块含义名称，例如 `trade-server,statistics-api`。
- 本轮可执行批次：`pending` 和 `failed` 批次；`completed` 批次只展示不调度
- 推荐执行计划：必须根据本轮可执行批次数动态生成，不能固定展示 3 / 5 / 10 批选项
- 自行输入批次号提示：允许用户根据表格在 Other/free-form 中输入若干批次号，例如 `batch-002,batch-004` 或 `2,4,7`

**展示要求**：
- 普通助手消息必须包含 `大仓库审查任务` 摘要、Markdown 批次表、`本轮可执行批次` 和 `推荐执行计划`。
- 批次表不得放入代码块，不得只留在 Bash 工具输出中，不得只说“分批规划完成，展示批次状态”。
- 可以保留 Bash 工具调用用于读取数据，但用户可见的表格必须由主 skill 重新输出。

**动态选项规则**：
- 先从状态表计算 `RUNNABLE_BATCH_IDS` 和 `RUNNABLE_COUNT`，只包含 `pending` / `failed` 批次。
- `RUNNABLE_COUNT=0` → 不调用 INTERACT；输出没有可执行批次，进入合并或结束提示。
- `RUNNABLE_COUNT=1` → 不调用 INTERACT；自动设置 `RUN_BATCH_IDS` 为唯一可执行批次，`RUN_BATCH_COUNT=1`，直接进入步骤 5B 选择并发数。
- `RUNNABLE_COUNT=2` → options 只包含 `执行 1 批`、`执行全部 2 批（推荐）` 和 Other/free-form；不得出现 `执行 3 批`、`执行 5 批` 或 `执行 10 批`。
- `RUNNABLE_COUNT=3` → options 只包含 `执行 1 批`、`执行 2 批`、`执行全部 3 批（推荐）` 和 Other/free-form；不得出现 `执行 5 批` 或 `执行 10 批`。
- `RUNNABLE_COUNT=4|5` → options 只包含 `执行 2 批`、`执行 3 批（推荐）`、`执行全部 {RUNNABLE_COUNT} 批` 和 Other/free-form。
- `RUNNABLE_COUNT=6..10` → options 只包含 `执行 3 批`、`执行 5 批（推荐）`、`执行全部 {RUNNABLE_COUNT} 批` 和 Other/free-form；不得出现 `执行 10 批`。
- `RUNNABLE_COUNT>10` → options 只包含 `执行 3 批`、`执行 5 批（推荐）`、`执行 10 批`、`执行全部 {RUNNABLE_COUNT} 批` 和 Other/free-form。
- 固定选项描述中的批次数必须使用实际 `RUNNABLE_COUNT` 截断后的数量；不得出现“执行 5 批”但描述里又显示“最多 3 批”。

**必须调用 INTERACT 工具，参数如下**：
- question: "请选择本轮执行批次"
- header: "执行批次"
- options: 按上方「动态选项规则」生成，不得写死 3 / 5 / 10 / 全部四个选项
- multiSelect: false

**用户响应后**：
- 固定选项 → 设置 `CURRENT_RUN_BATCH_LIMIT` 为该选项对应的实际批次数，`执行全部 {RUNNABLE_COUNT} 批` 设置为 `all`
- Other/free-form 批次号 → 设置 `BATCH_SELECTION` 为用户输入的批次号列表；支持 `batch-002,batch-004`、`2,4,7`、空格或中文顿号/逗号分隔
- 解析 `BATCH_SELECTION` 时必须标准化为 `batch-XXX` 格式，并校验这些批次存在且状态为 `pending` 或 `failed`
- 输入包含不存在、已完成或执行中的批次时，不得继续执行；必须再次调用 INTERACT 让用户重新选择
- `completed` 批次必须跳过
- 固定选项只调度状态表顺序中前 N 个 `pending` / `failed` 批次；未调度批次保持 `pending`

### 步骤 5B：选择并发数（条件步骤）

**触发条件**：BATCH_MODE=true。不满足时跳过此步骤。

**前置计算**：触发此步骤前，必须先完成分批计算（见「分批计算」章节），得到 BATCH_COUNT。
- 若 `MAVEN_LARGE_REPO_MODE=true`，必须先完成 Maven 大仓库模式的步骤 5 批次表展示和本轮执行批次选择；不得改走文件级 planner。
- 若 `LANGUAGE_ID=java` 且不满足 Maven 大仓库模式，但 `BATCH_MODE=true`（Maven 单模块、Gradle 或未知 Java 项目），必须先调用 `languages/java/plan-file-batches.sh` 生成文件级批次，并把脚本输出的 `简要分批计划` 原样展示到控制台；不得只输出总批次数后直接询问并发数。
- 若 `LANGUAGE_ID=frontend` 且 `BATCH_MODE=true`，必须先调用 `scripts/core/plan-file-batches.sh` 生成前端文件级批次，并确认 `plan.json budget.context_scale=5`、`budget.context_window_tokens=1000000`。
- 若 `LANGUAGE_ID=python` 且 `BATCH_MODE=true`，必须先调用 `scripts/core/plan-file-batches.sh` 生成 Python 文件级批次，并确认 `plan.json budget.context_scale=5`、`budget.context_window_tokens=1000000`。

在调用 INTERACT 之前，先输出并发策略摘要：
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
- `RUN_BATCH_COUNT=1` → 不调用 INTERACT；自动设置 `CONCURRENCY=1`，直接进入步骤 6 确认执行计划。
- `RUN_BATCH_COUNT=2` → INTERACT options 只包含 `串行执行（默认）` 和 `2 路并发`；不得出现 `3 路并发`。
- `RUN_BATCH_COUNT>=3` → INTERACT options 包含 `串行执行（默认）`、`2 路并发`、`3 路并发`。
- 任意路径下都不得提供大于 `RUN_BATCH_COUNT` 的并发选项；例如只执行 1 批时不能展示 2 / 3 路，只执行 2 批时不能展示 3 路。

**必须调用 INTERACT 工具，参数如下**：
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
目标批次成本 = plan.json budget.target_batch_cost 或 budget.batch_token_budget（固定 1M 默认：Maven semantic planner 260000，文件级 planner 500000）
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
- 审查模型：{MODEL_PROFILE}（固定 1M 上下文）
- 启用维度：{根据模式 × 维度矩阵列出具体维度名称}
- 项目 ignore：{IGNORE_RULES_ENABLED=true 时显示 "已启用 .cc-code-reviewer/ignore/issues.yml（已忽略 {IGNORE_RULE_COUNT} 个问题）"；否则显示 "未配置"}
- 报告保存方式：{FEISHU_UPLOAD_OPTION}
- 扫描策略：分批并行扫描（本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} / 总 {BATCH_COUNT} 批 / {CONCURRENCY} 路并发）  ← 仅 BATCH_MODE=true 时显示
```

**必须调用 INTERACT 工具，参数如下**：
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

📋 任务配置：{REVIEW_MODE} 模式（{MODEL_PROFILE}） · {REVIEW_TYPE} · {REVIEW_SCOPE}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。

{选择飞书输出时追加}
📤 审查完成后将由主代理保存到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。
```

**BATCH_MODE=true 时**：

```
🚀 正在启动分批并行代码审查...

📋 任务配置：{REVIEW_MODE} 模式（{MODEL_PROFILE}） · {REVIEW_TYPE} · {REVIEW_SCOPE}
📊 扫描策略：本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} / 总 {BATCH_COUNT} 批 / {CONCURRENCY} 路并发
📌 本轮 {RUN_BATCH_COUNT 或 BATCH_COUNT} 批次将按 {CONCURRENCY} 路并发执行；未调度批次保持 pending，完成后生成阶段性或完整合并结果。

{选择飞书输出时追加}
📤 审查完成后将由主代理保存到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。
```

---

## 分批计算

当 `BATCH_MODE=true` 时，主 skill 必须优先使用确定性脚本生成批次计划，不得临时拼接 Bash 数组或在 shell 中即兴实现 token 打包。

**固定预算门禁**：任何新生成的 `plan.json` 都必须写入 `budget.context_scale=5` 和 `budget.context_window_tokens=1000000`。文件级计划在未显式设置 `CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET` 时还必须写入 `budget.batch_token_budget=500000`；不满足时必须重新运行对应 planner，不得展示或执行旧的小窗口计划。

### Maven 多模块大仓分批

`MAVEN_LARGE_REPO_MODE=true` 后，Maven 多模块项目不得使用内联 Bash 数组分批，必须统一调用 `languages/java/plan-large-batches.sh`。未达到当前范围门槛的 Maven 多模块项目不得进入本节：

```bash
SEMANTIC_LEVEL="maven-static"
if [ "$CODE_INTELLIGENCE_AVAILABLE" = "true" ]; then
  SEMANTIC_LEVEL="jdtls-lsp"
fi

bash "${PLUGIN_ROOT}/scripts/languages/java/plan-large-batches.sh" \
  "$PROJECT_DIR" \
  "$REVIEW_MODE" \
  "{TARGET_BRANCH 或 CURRENT_BRANCH}" \
  "$SEMANTIC_LEVEL" \
  "$REVIEW_SCOPE" \
  "$STOCK_REVIEW_STRATEGY"
```

适用范围：
- 全量审查：`REVIEW_SCOPE=全量代码`
- 指定模块：`REVIEW_SCOPE` 为模块相对路径列表，例如 `yudao-module-mes,yudao-framework`
- 按模块依次：`STOCK_REVIEW_STRATEGY=module-sequential`
- AI 智能规划：`STOCK_REVIEW_STRATEGY=ai-planned`

脚本输出的 `RUN_DIR`、`plan.json`、`batches/*.json` 和 `results/*.status.json` 是后续批次展示、选择本轮执行批次、启动 batch agent 和合并报告的唯一数据来源。

### Java 非 Maven 多模块文件级分批

仅当 `LANGUAGE_ID=java`、`PROJECT_TYPE` 不是 Maven 多模块且 `BATCH_MODE=true` 时，必须统一调用 `languages/java/plan-file-batches.sh` 生成简单文件级批次，覆盖 Maven 单模块、Gradle 项目和未知 Java 项目。`LANGUAGE_ID=frontend|python` 绝不得进入本分支：

Maven 多模块存量分批绝不调用 `languages/java/plan-file-batches.sh`。即使只选择一个模块，也必须使用 Maven 多模块 planner，以便 `REVIEW_SCOPE` 限定在所选模块内，避免生成全项目批次。

```bash
bash "${PLUGIN_ROOT}/scripts/languages/java/plan-file-batches.sh" \
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

前端项目（含 React/Vue/Node monorepo 单语言运行）必须使用 `scripts/core/plan-file-batches.sh`（语言中立），不得使用 Java 的 `languages/java/plan-file-batches.sh` 或 `languages/java/plan-large-batches.sh`：

```bash
# 先生成不可变 source manifest（生产 .ts/.tsx/.js/.jsx/.vue/.mjs/.cjs，排除测试/产物/配置脚本）
MANIFEST="$(mktemp)"
bash "${PLUGIN_ROOT}/scripts/languages/frontend/collect-source-files.sh" "$PROJECT_DIR" > "$MANIFEST"

# 若用户在步骤 4 选了「指定目录」（REVIEW_SCOPE 为 src 子目录路径列表，非"全量代码"），
# 用前端专属过滤脚本收敛 manifest：只保留落在所选 src 子目录内的文件。
# 这是前端「指定模块」真正缩小扫描范围的唯一关卡——分批脚本只读 manifest，
# manifest 收敛后，分批/扫描/文件计数自动收敛，无需改分批脚本或子 agent。
# 过滤脚本支持单包和 monorepo：`src/components` 或 `components` 会匹配所有前端族群 package-local
# `*/src/components/`；`apps/web/src/components` 这类完整相对路径只匹配对应 package。
if [ "$LANGUAGE_ID" = "frontend" ] && [ "$REVIEW_SCOPE" != "全量代码" ]; then
  FILTERED="$(mktemp)"
  bash "${PLUGIN_ROOT}/scripts/languages/frontend/filter-source-manifest.sh" \
    "$PROJECT_DIR" "$MANIFEST" "$REVIEW_SCOPE" > "$FILTERED"
  mv "$FILTERED" "$MANIFEST"
fi

bash "${PLUGIN_ROOT}/scripts/core/plan-file-batches.sh" \
  "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "frontend" "$MANIFEST"
```

**REVIEW_SCOPE 过滤后必须重算审查规模**：manifest 收敛后，`REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT` 必须按过滤后的 manifest 重新统计（文件数 = `grep -c . "$MANIFEST"`，行数 = 各文件 `wc -l` 之和），覆盖步骤 4 之前按全项目算的值。重算后的值用于子 agent 参数表的「审查文件数量/审查代码行数」、最终汇总的覆盖率分母、以及前端分批表展示。`REVIEW_SCOPE=全量代码` 时跳过过滤和重算，保持原行为。

> 过滤规则：manifest 中每行是绝对路径。`src/{目录名}` 或 `{目录名}` 按 `*/src/{目录名}/` 边界匹配，因此 monorepo 多包场景下，同名子目录（如两个包都有 `src/components`）会同时命中；`apps/web/src/{目录名}` 这类完整相对路径只匹配对应 package。过滤脚本必须拒绝绝对路径和 `..` 路径穿越；过滤后为空时必须终止并提示有效目录，而不是继续生成空批次。

合并：
```bash
RUN_BATCH_IDS="{RUN_BATCH_IDS}" bash "${PLUGIN_ROOT}/scripts/core/merge-batch-results.sh" "$RUN_DIR"
```

前端批次状态展示：在前端分批规划完成后、启动 agent 前（或本轮批次跑完准备合并时），调用批次状态展示脚本向用户展示批次表与动态执行计划。此脚本按前端 plan.json 的 `language_id=frontend` 读取 `total_source_loc`/`planned_source_loc`，展示「前端源码行数」「前端源码行覆盖」：
```bash
bash "${PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

`scripts/core/merge-batch-results.sh` 的覆盖率展示名根据 `plan.json.language_id` 自动切换为「前端源码文件覆盖率」。前端 batch agent 使用 `cc-code-reviewer-frontend` 子代理，注入 PROFILE 行、source manifest、`SEMANTIC_LEVEL`、批次参数（`RUN_DIR`/`BATCH_PLAN_PATH`/`BATCH_STATUS_PATH`/`BATCH_RESULT_PATH`）。

### Python 分批（LANGUAGE_ID=python）

Python 项目（Django/FastAPI/通用 Python）必须使用 `scripts/core/plan-file-batches.sh`（语言中立），不得使用 Java 的 `languages/java/plan-file-batches.sh` 或 `languages/java/plan-large-batches.sh`：

```bash
# 先生成不可变 source manifest（生产 .py，排除 tests/migrations/venv/__pycache__/build）
MANIFEST="$(mktemp)"
bash "${PLUGIN_ROOT}/scripts/languages/python/collect-source-files.sh" "$PROJECT_DIR" > "$MANIFEST"

# 若用户选了「指定目录」（REVIEW_SCOPE 为 src 子目录或包目录路径列表，非"全量代码"），
# 用 Python 专属过滤脚本收敛 manifest。
if [ "$LANGUAGE_ID" = "python" ] && [ "$REVIEW_SCOPE" != "全量代码" ]; then
  FILTERED="$(mktemp)"
  bash "${PLUGIN_ROOT}/scripts/languages/python/filter-source-manifest.sh" \
    "$PROJECT_DIR" "$MANIFEST" "$REVIEW_SCOPE" > "$FILTERED"
  mv "$FILTERED" "$MANIFEST"
fi

bash "${PLUGIN_ROOT}/scripts/core/plan-file-batches.sh" \
  "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "python" "$MANIFEST"
```

**REVIEW_SCOPE 过滤后必须重算审查规模**：manifest 收敛后，`REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT` 必须按过滤后的 manifest 重新统计，覆盖之前按全项目算的值。`REVIEW_SCOPE=全量代码` 时跳过过滤和重算。

合并：
```bash
RUN_BATCH_IDS="{RUN_BATCH_IDS}" bash "${PLUGIN_ROOT}/scripts/core/merge-batch-results.sh" "$RUN_DIR"
```

Python 批次状态展示：在 Python 分批规划完成后、启动 agent 前，调用批次状态展示脚本。此脚本按 Python plan.json 的 `language_id=python` 读取 `total_source_loc`/`planned_source_loc`，展示「Python 行数」「Python 行覆盖」：
```bash
bash "${PLUGIN_ROOT}/scripts/core/show-batch-status.sh" "$PROJECT_DIR"
```

`scripts/core/merge-batch-results.sh` 的覆盖率展示名根据 `plan.json.language_id` 自动切换为「Python 文件覆盖率」。Python batch agent 使用 `cc-code-reviewer-python` 子代理，注入 PROFILE 行、source manifest、`SEMANTIC_LEVEL`、批次参数。

---

## 子 agent 调用规范

### 调用方式

调用逻辑动作 `DISPATCH_AGENT`，`agent_prompt` 按 `LANGUAGE_ID` 选择：
- `LANGUAGE_ID=java` → `${PLUGIN_ROOT}/agents/cc-code-reviewer.md`
- `LANGUAGE_ID=frontend` → `${PLUGIN_ROOT}/agents/cc-code-reviewer-frontend.md`
- `LANGUAGE_ID=python` → `${PLUGIN_ROOT}/agents/cc-code-reviewer-python.md`
- model_profile: {MODEL_PROFILE}
- prompt: 下方参数注入格式

不得让主 Skill 代替子 Agent 执行正式审查。子 Agent 独立执行审查，主 Agent 等待其返回结构化结果后展示给用户；具体调度字段由 runtime adapter 映射。

### 参数注入格式

```
## 审查任务参数（外部注入，请直接使用，无需再次确认）

| 参数 | 值 |
|------|-----|
| 项目路径 | {PROJECT_DIR} |
| 项目名称 | {PROJECT_NAME} |
| 项目类型 | {PROJECT_TYPE} |
| 语言 ID | {LANGUAGE_ID} |
| 审查类型 | {REVIEW_TYPE} |
| 审查范围 | {REVIEW_SCOPE} |
| 审查模式 | {REVIEW_MODE} |
| 审查模型 | {MODEL_PROFILE} |
| 审查文件数量 | {REVIEW_FILE_COUNT} |
| 审查代码行数 | {REVIEW_LINE_COUNT} |
| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |
| React 规则路径 | {REACT_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| Vue 规则路径 | {VUE_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| Node 规则路径 | {NODE_RULES_PATH}（仅 LANGUAGE_ID=frontend） |
| Django 规则路径 | {DJANGO_RULES_PATH}（仅 LANGUAGE_ID=python） |
| FastAPI 规则路径 | {FASTAPI_RULES_PATH}（仅 LANGUAGE_ID=python） |
| 源码范围路径 | {SOURCE_SCOPE_PATH}（仅 LANGUAGE_ID=frontend 或 python） |
| 报告格式路径 | {REPORT_FORMAT_PATH} |
| 项目 ignore 文件路径 | {IGNORE_RULES_PATH 或 未配置} |
| 项目 ignore 是否启用 | {IGNORE_RULES_ENABLED} |
| 项目 ignore 问题数量 | {IGNORE_RULE_COUNT} |
| 语义增强 | {SEMANTIC_LEVEL} |
| 审查输入清单 | {REVIEW_INPUT_PATH} |
| 项目审查规则解析结果 | {REVIEW_RULES_RESOLVED_PATH} |
| source manifest | {MANIFEST 绝对路径}（所有语言均注入；正式范围以 REVIEW_INPUT_PATH 中 selected=true 为准） |
| 本批审查文件列表 | {BATCH_FILE_LIST}（仅文件级分批模式，单 agent 模式不注入） |

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
| `PROJECT_DIR` | detect-project.sh 脚本输出 | `/tmp/{仓库名}` 或本地路径 |
| `PROJECT_SOURCE` | detect-project.sh 脚本输出 | `local` / `git-cache` |
| `PROJECT_NAME` | `basename "$PROJECT_DIR"` | `spring-ai-agent-utils` |
| `PROJECT_TYPE` | languages/java/project-scan.sh 脚本输出 | `maven-single` 等 |
| `REVIEW_MODE` | 交互步骤1 | `fast` / `standard` 等 |
| `MODEL_PROFILE` | 第五步之后（分批判定之前） | `inherit` / `economy` / `balanced` / `maximum` |
| `CONTEXT_SCALE` | 固定 1M 分批常量 | `5` |
| `CONTEXT_WINDOW_TOKENS` | 固定 1M 分批常量 | `1000000` |
| `FEISHU_UPLOAD_OPTION` | 交互步骤2 | `本地 Markdown 报告` 或 `飞书云文档, 飞书多维表格` 等 |
| `REVIEW_ENTRY` | 交互步骤3 | `增量审查` / `全量审查` / `指定模块` |
| `REVIEW_TYPE` | 交互步骤3 | `增量审查` / `存量审查` |
| `REVIEW_SCOPE` | 交互步骤4 | `最近5次提交` / `全量代码` / `yudao-module-mes,yudao-framework` |
| `STOCK_REVIEW_STRATEGY` | 步骤3默认 `single-agent`；仅达到当前范围门槛时由步骤4B覆盖 | `single-agent` / `module-sequential` / `ai-planned` |
| `PROJECT_SCAN_RESULT` | languages/java/project-scan.sh 完整输出 | 项目概况、模块结构 |
| `SEMANTIC_LEVEL` | Java：`detect-code-intelligence.sh` 输出转换（`CODE_INTELLIGENCE_AVAILABLE=true` → `jdtls-lsp`，否则 `maven-static`）；前端：`CODE_INTELLIGENCE_PROVIDER=typescript-lsp` → `typescript-lsp`，否则 `none`；Python：`CODE_INTELLIGENCE_PROVIDER=pyright|pylsp|jedi` → 同名 LSP，`pyright-cli` → `pyright-cli`（仅 diagnostics），否则 `none` | `jdtls-lsp` / `typescript-lsp` / `pyright` / `pyright-cli` |
| `DETECTED_TECH_STACK` | 从 `PROJECT_SCAN_RESULT` 的 `TECH_STACK:` 行解析，来源为各语言依赖指纹 | `Spring Boot, MyBatis, Redis/Cache` |
| `REVIEW_FILE_COUNT` | 步骤4后从当前范围 manifest 重算；增量执行时再由 `REVIEW_INPUT_PATH.selected_item_count` 覆盖 | `76` |
| `REVIEW_LINE_COUNT` | 步骤4后从当前范围 manifest 重算；增量执行时再由 `REVIEW_INPUT_PATH.selected_line_count` 覆盖 | `16637` |
| `REVIEW_FRAMEWORK_PATH` | 按 `LANGUAGE_ID` 分支：`java` → `references/languages/java/review-framework.md`；`frontend` → `references/languages/frontend/review-framework.md`；`python` → `references/languages/python/review-framework.md`。启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/java/review-framework.md` |
| `REACT_RULES_PATH` | 仅 `LANGUAGE_ID=frontend`：`references/languages/frontend/react-rules.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/frontend/react-rules.md` |
| `VUE_RULES_PATH` | 仅 `LANGUAGE_ID=frontend`：`references/languages/frontend/vue-rules.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/frontend/vue-rules.md` |
| `NODE_RULES_PATH` | 仅 `LANGUAGE_ID=frontend`：`references/languages/frontend/node-rules.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/frontend/node-rules.md` |
| `DJANGO_RULES_PATH` | 仅 `LANGUAGE_ID=python`：`references/languages/python/django-rules.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/python/django-rules.md` |
| `FASTAPI_RULES_PATH` | 仅 `LANGUAGE_ID=python`：`references/languages/python/fastapi-rules.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/python/fastapi-rules.md` |
| `SOURCE_SCOPE_PATH` | 仅 `LANGUAGE_ID=frontend` 或 `python`：对应 `references/languages/{lang}/source-scope.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/frontend/source-scope.md` |
| `REPORT_FORMAT_PATH` | `${PLUGIN_ROOT}/references/report-format.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/report-format.md` |
| `GIT_LOG_OUTPUT` | core/prepare-incremental.sh 脚本输出（仅增量） | `git log --oneline -N` |
| `CHANGED_FILES_OUTPUT` | core/prepare-incremental.sh 脚本输出（仅增量） | `git diff --name-only` |
| `DIFF_STATS_OUTPUT` | core/prepare-incremental.sh 脚本输出（仅增量） | `git diff --stat` |
| `REVIEW_INPUT_PATH` | core/prepare-review-input.sh 输出（所有入口） | 不可变输入、ref、选中/排除原因和内容指纹 |
| `REVIEW_RULES_RESOLVED_PATH` | core/resolve-review-rules.sh 基于 REVIEW_INPUT_PATH 的 selected 文件解析 | 当前正式范围逐文件命中的项目审查规则；不作为 ignore |

### 增量审查预处理（仅增量审查时执行）

在调用子 agent 之前，执行增量预处理脚本：`bash "${PLUGIN_ROOT}/scripts/core/prepare-incremental.sh" "$PROJECT_DIR" {N}`。随后由路径 A 的统一输入生成块，以 `COMMIT_COUNT={N}` 生成 `REVIEW_INPUT_PATH`，再从其中 `selected=true` 的文件解析 `REVIEW_RULES_RESOLVED_PATH`。两条路径都必须注入单 Agent；`REVIEW_INPUT_PATH` 是增量正式范围的唯一清单，Agent 不得另行扩展发现范围。文件级存量分批与 Maven 大仓模块分批都会生成 `RUN_DIR/review-input.json` 和 `RUN_DIR/review-rules.json`，并将路径注入每个 batch agent。

脚本输出用 `# ===` 分隔为三部分：
1. `# === 提交记录 ===` → GIT_LOG_OUTPUT
2. `# === 变更文件列表 ===` → CHANGED_FILES_OUTPUT
3. `# === 变更统计 ===` → DIFF_STATS_OUTPUT

**异常处理**：如果 CHANGED_FILES_OUTPUT 为空，告知用户没有变更文件，询问是否调整提交次数或切换到存量审查，不调用子 agent。

### 第五步之后：报告合并（仅 BATCH_MODE=true 时执行）

所有本轮 batch agent 完成或进入终态后，主 skill 执行合并（不启动额外 agent）。

Maven 大仓库模式必须通过确定性脚本合并，并把本轮主任务批次通过 `RUN_BATCH_IDS` 传给脚本：
```bash
RUN_BATCH_IDS="{RUN_BATCH_IDS}" bash "${PLUGIN_ROOT}/scripts/core/merge-batch-results.sh" "$RUN_DIR"
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

- **包含 `飞书云文档`**：通过 `lark-cli` + `lark-doc` skill 创建飞书云文档。CLI 固定使用 `lark-cli docs +create --api-version v2 --doc-format markdown --content @{REPORT_BASENAME}`，先 `cd` 到报告文件所在目录再用相对文件名。文档标题由 Markdown 一级标题承载，不要传 `--title`。从响应 `data.doc_url` 提取云文档链接 `DOC_URL`。详细步骤见 `${PLUGIN_ROOT}/references/feishu-integration.md`「上传报告到飞书云文档」章节。
- **包含 `飞书多维表格`**：通过 `lark-cli` + `lark-base` skill 创建飞书多维表格并录入问题清单。按 17 字段定义创建表 → 重命名默认主字段为"备注" → 创建其余 16 字段 → 批量录入问题数据（从子 agent 返回的完整报告内容中解析各级别问题）→ 清理默认字段。从响应提取多维表格链接 `BASE_URL`。详细步骤见 `${PLUGIN_ROOT}/references/feishu-integration.md`「创建飞书多维表格」章节。
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

完整的示例对话详见 `${PLUGIN_ROOT}/references/examples.md`。
