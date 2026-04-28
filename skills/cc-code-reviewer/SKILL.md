---
description: Java 代码审查 — 支持增量/存量审查、15维度评估、飞书报告上传
---

## 执行算法（最高优先级，必须严格按此顺序执行）

以下是你必须遵循的执行顺序。不允许跳过、合并、重新排序或即兴发挥。

### 第一步：模式判定（最先执行）

检测用户输入中是否包含 `--mode` 参数：
- **包含 `--mode`** → 快速启动模式（FAST_MODE=true），执行预扫描 → 参数校验 → 必要时切换分支 → 直接启动子agent
- **不包含 `--mode`** → 交互式模式（FAST_MODE=false），执行预扫描 → 逐步 AskUserQuestion → 启动子agent

### 第二步：预扫描（4 个脚本按顺序执行，此阶段禁止任何用户交互）

从用户输入中提取项目路径（第一个非 `--` 开头的参数，或整个输入路径），然后按以下顺序执行 4 个脚本：

```bash
# 脚本1：项目识别
bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase1-detect-project.sh "<用户输入的路径>"
# 输出：PROJECT_DIR=<路径> PROJECT_SOURCE=local|git-cache

# 脚本2：分支探测
bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase2-detect-branches.sh "$PROJECT_DIR"
# 输出：IS_GIT_REPO=true/false CURRENT_BRANCH=<分支> BRANCH: ... BRANCH_REMOTE: ...

# 脚本3：项目扫描
bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase3-project-scan.sh "$PROJECT_DIR"
# 输出：PROJECT_TYPE=maven-single|maven-multi|... MODULE:模块名|相对路径|Java文件数|代码行数

# 脚本4：lark-cli 检测
bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase4-detect-lark-plugin.sh
# 输出：LARK_PLUGIN_INSTALLED=true|false，失败时附带 LARK_PLUGIN_REASON
```

> ⚠️ 4 个脚本必须全部执行完成后才能继续。此阶段禁止调用 AskUserQuestion，禁止输出任何交互式提问。

### 第三步：输出预扫描摘要（不允许跳过）

4 个脚本全部完成后，必须输出以下格式的摘要（这是预扫描阶段的唯一输出）：

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

🔌 lark-cli：{LARK_PLUGIN_INSTALLED=true 时显示 "✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书上传" / false 时显示 "⚠️ 飞书上传不可用：{LARK_PLUGIN_REASON}，报告将保存到本地文件"}
```

### 第四步：参数收集（根据模式选择分支）

#### 分支 A：交互式模式（FAST_MODE=false）

按以下步骤逐个调用 **AskUserQuestion 工具**（禁止用纯文本输出替代）。每个步骤必须单独调用 AskUserQuestion 并等待用户响应后才能进入下一步。**禁止在一次回复中合并多个交互步骤。**

详细步骤定义见下方「交互式确认步骤定义」章节。

#### 分支 B：快速启动模式（FAST_MODE=true）

校验用户提供的所有参数；如提供 `--branch` 且不同于当前分支，必须先执行分支切换；全部通过后进入第五步。详细校验规则见下方「快速启动模式参数规范」章节。

### 第五步：调用子 agent 执行代码审查

使用 Task 工具启动 `cc-code-reviewer` 子代理：
- description: "执行 Java 代码审查"
- prompt: 注入审查参数表 + 项目概况 + 增量数据
- subagent_type: "cc-code-reviewer"

详细参数注入格式见下方「子 agent 调用规范」章节。

---

## 交互式确认步骤定义（仅 FAST_MODE=false 时执行）

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
- 如不是当前分支，执行：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase2-switch-branch.sh "$PROJECT_DIR" "{TARGET_BRANCH}" "$CURRENT_BRANCH" "$PROJECT_SOURCE"`
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

**增量审查时，必须调用 AskUserQuestion 工具，参数如下**：
- question: "审查最近几次提交的变更？"
- header: "提交次数"
- options:
  - label: "最近 1 次"
    description: "仅审查最近一次提交"
  - label: "最近 3 次"
    description: "审查最近 3 次提交"
  - label: "最近 5 次（推荐）"
    description: "审查最近 5 次提交"
  - label: "最近 10 次"
    description: "审查最近 10 次提交"
- multiSelect: false

**存量审查 + 多模块时，必须调用 AskUserQuestion 工具，参数如下**：
- question: "请选择要审查的模块"
- header: "审查范围"
- options: 从预扫描结果动态生成（全量代码 + 所有模块；模块超过 10 个时展示前 9 个 + "其他模块"）
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
- 启用维度：{根据模式 × 维度矩阵列出具体维度名称}
- 飞书上传：{FEISHU_UPLOAD_OPTION}
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

```
🚀 正在启动独立代码审查子代理...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
⏱️ 预估耗时：{预估时间}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。

{飞书上传时追加}
📤 审查完成后将自动上传到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以继续使用 Claude Code 进行其他操作。
```

**预估时间参考**：

| 模式 | 小型（<50类） | 中型（50-200类） | 大型（>200类） |
|------|:---:|:---:|:---:|
| fast | 2-3 分钟 | 3-5 分钟 | 5-8 分钟 |
| standard | 5-8 分钟 | 8-15 分钟 | 15-25 分钟 |
| deep | 10-15 分钟 | 15-30 分钟 | 30-60 分钟 |
| security | 5-10 分钟 | 10-20 分钟 | 20-35 分钟 |

---

## 快速启动模式参数规范

适用于定时任务、自动化脚本、CI/CD 集成等无需人工交互的场景。

### 参数规范

| 参数 | 是否必填 | 取值范围 | 说明 |
|------|----------|----------|------|
| `--mode` | **必填** | `fast` / `standard` / `deep` / `security` | 审查模式 |
| `--type` | **必填** | `incremental` / `stock` | 审查类型 |
| `--scope` | 条件必填 | 见下方规则 | 审查范围 |
| `--branch` | 可选 | 任意分支名 | 审查分支，默认当前分支 |
| `--upload` | 可选 | `no` / `doc` / `bitable` / `both` | 飞书上传选项，默认 `no` |

**`--scope` 条件必填规则**：

| `--type` 值 | `--scope` 是否必填 | 合法值 | 默认值 |
|-------------|-------------------|--------|--------|
| `incremental` | **必填** | 正整数（提交次数） | 无，缺则报错 |
| `stock` + 多模块 | **必填** | `full` 或逗号分隔模块名 | 无，缺则报错 |
| `stock` + 单模块 | 可选 | `full` | 自动设为 `full` |

### 参数映射

| 快速启动参数 | 映射变量 | 值转换 |
|-------------|----------|--------|
| `--mode fast` | `REVIEW_MODE=fast` | 直接使用 |
| `--type incremental` | `REVIEW_TYPE=增量审查` | 转换为中文 |
| `--type stock` | `REVIEW_TYPE=存量审查` | 转换为中文 |
| `--scope 5`（incremental） | `REVIEW_SCOPE=最近5次提交` | 转换为中文 |
| `--scope full`（stock） | `REVIEW_SCOPE=全量代码` | 转换为中文 |
| `--scope user-service,order-service` | `REVIEW_SCOPE=user-service,order-service` | 直接使用 |
| `--branch develop` | `TARGET_BRANCH=develop` | 直接使用 |
| `--upload no` / 未提供 | `FEISHU_UPLOAD_OPTION=仅显示报告` | 转换为中文 |
| `--upload doc` | `FEISHU_UPLOAD_OPTION=上传到云文档` | 转换为中文 |
| `--upload bitable` | `FEISHU_UPLOAD_OPTION=上传到多维表格` | 转换为中文 |
| `--upload both` | `FEISHU_UPLOAD_OPTION=同时上传两者` | 转换为中文 |

### 校验规则

1. `--mode` 和 `--type` 必须同时存在，缺失任何一个立即报错终止
2. 每个参数值必须在合法取值范围内
3. 根据 `--type` 的值校验 `--scope` 是否缺失
4. `--branch` 指定的分支不存在时报错并列出可用分支
5. `--scope` 为具体模块名时校验模块是否存在于预扫描结果中
6. `--upload` 不是 `no` 但 LARK_PLUGIN_INSTALLED=false 时，警告并降级为 `仅显示报告`

### 快速启动分支处理

参数校验通过后、启动子 agent 前：

1. 未提供 `--branch`：TARGET_BRANCH=CURRENT_BRANCH
2. 提供 `--branch` 且等于 CURRENT_BRANCH：无需切换
3. 提供 `--branch` 且不同于 CURRENT_BRANCH：必须执行
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase2-switch-branch.sh "$PROJECT_DIR" "{TARGET_BRANCH}" "$CURRENT_BRANCH" "$PROJECT_SOURCE"
   ```
4. 快速启动模式下，如果显式分支切换失败，必须终止本次审查并说明原因，不得静默回退到当前分支继续审查
5. 切换成功后，重新记录 CURRENT_BRANCH/TARGET_BRANCH，用切换后的分支生成增量数据和调用子 agent

**校验失败输出格式**：

```
❌ 快速启动参数校验失败

缺少必填参数：
  - --mode: 审查模式（fast/standard/deep/security）
  - --scope: ...

正确格式示例：
  帮我审查 /path/to/project --mode fast --type incremental --scope 5
  帮我审查 /path/to/project --mode standard --type stock --scope full --upload doc

请补充缺失参数后重新调用。
```

### 快速启动校验通过后的启动提示

```
🚀 快速启动模式 — 正在启动独立代码审查子代理...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
🌿 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}
📤 飞书上传：{FEISHU_UPLOAD_OPTION}
⏱️ 预估耗时：{预估时间}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。
```

### 快速启动调用示例

```
# 增量审查 — 最近5次提交
帮我审查 /path/to/project --mode fast --type incremental --scope 5

# 存量审查 — 全量代码，上传飞书云文档
帮我审查 /path/to/project --mode standard --type stock --scope full --upload doc

# 存量审查 — 指定模块，深度模式
帮我审查 /path/to/project --mode deep --type stock --scope user-service,order-service --upload both

# 指定分支 + 增量审查
帮我审查 https://github.com/org/repo.git --mode standard --type incremental --scope 3 --branch develop --upload bitable
```

---

## 子 agent 调用规范

### 调用方式

使用 Task 工具启动内置的 `cc-code-reviewer` 子代理：
- description: "执行 Java 代码审查"
- subagent_type: "cc-code-reviewer"
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

### 项目概况（预扫描结果）
{PROJECT_SCAN_RESULT}

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
| `REVIEW_TYPE` | 交互步骤2 / 快速启动 `--type` | `增量审查` / `存量审查` |
| `REVIEW_SCOPE` | 交互步骤3 / 快速启动 `--scope` | `最近5次提交` / `全量代码` |
| `REVIEW_MODE` | 交互步骤4 / 快速启动 `--mode` | `fast` / `standard` 等 |
| `FEISHU_UPLOAD_OPTION` | 交互步骤5 / 快速启动 `--upload` | `仅显示报告` 等 |
| `PROJECT_SCAN_RESULT` | phase3 完整输出 | 项目概况、模块结构 |
| `REVIEW_FILE_COUNT` | 从 `PROJECT_SCAN_RESULT` 解析 | `76` |
| `REVIEW_LINE_COUNT` | 从 `PROJECT_SCAN_RESULT` 解析 | `16637` |
| `GIT_LOG_OUTPUT` | phase5 脚本输出（仅增量） | `git log --oneline -N` |
| `CHANGED_FILES_OUTPUT` | phase5 脚本输出（仅增量） | `git diff --name-only` |
| `DIFF_STATS_OUTPUT` | phase5 脚本输出（仅增量） | `git diff --stat` |

### 增量审查预处理（仅增量审查时执行）

在调用子 agent 之前，执行：
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/phase5-prepare-incremental.sh "$PROJECT_DIR" {N}
```

脚本输出用 `# ===` 分隔为三部分：
1. `# === 提交记录 ===` → GIT_LOG_OUTPUT
2. `# === 变更文件列表 ===` → CHANGED_FILES_OUTPUT
3. `# === 变更统计 ===` → DIFF_STATS_OUTPUT

**异常处理**：如果 CHANGED_FILES_OUTPUT 为空，告知用户没有变更文件，询问是否调整提交次数或切换到存量审查，不调用子 agent。

### 子 agent 返回结果处理

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
2. **执行前强制确认**：交互式模式下必须展示执行计划并等待用户确认（快速启动模式豁免）
3. **三个核心选项必须全部明确**：审查类型 + 审查范围 + 审查模式，缺一不可
4. **强制中文输出**：所有交互和报告都必须使用中文
5. **最终确认前零深度审查动作**：在用户最终确认前，不得启动子 agent 或执行正式代码审查；但允许执行预扫描脚本
6. **快速启动参数完整性**：`--mode` 和 `--type` 必须同时存在，缺少必填参数立即报错终止，不允许降级为交互式模式

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
