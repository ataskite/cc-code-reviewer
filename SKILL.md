---
name: cc-code-reviewer
description: Java代码审查、代码检查、发现Bug和安全漏洞、性能优化、架构评估、技术债挖掘。15维度全面审查，支持fast/standard/deep/security模式和增量/存量审查。
---

## 用途

当用户要求**审查Java代码**、**代码检查**、**发现Bug**、**安全漏洞**、**性能问题**、**潜在风险**、**技术债挖掘**、**安全检查**、**性能优化**、**架构评估**时使用此技能。

**常见触发场景**：
- "帮我审查这个项目"
- "检查一下代码有没有问题"
- "发现潜在Bug和安全漏洞"
- "评估代码质量和架构"
- "挖掘技术债和改进点"
- "代码安全检查"
- "性能优化建议"

## 工作流程

### 阶段一：项目识别与准备（自动执行，无需确认）

**目标**：识别用户提供的路径类型，Git仓库自动克隆到工作目录。

**识别规则**：
- 以`http://`、`https://`、`git://`或`git@`开头的URL → Git仓库
- 其他情况 → 本地路径

**执行脚本**：
```bash
bash scripts/phase1-detect-project.sh "<用户输入的路径>"
```

脚本输出：
- `PROJECT_DIR=<项目绝对路径>`：最终的项目根目录

---

### 阶段二：Git 分支探测与选择

**前置条件**：阶段一已完成，`PROJECT_DIR` 已确定。

**目标**：如果项目是 Git 仓库，探测最近活跃的分支供用户选择。非 Git 项目或仅有单一分支时自动跳过。

#### 步骤 A：检测 Git 分支（自动执行，无需确认）

**执行脚本**：
```bash
bash scripts/phase2-detect-branches.sh "$PROJECT_DIR"
```

脚本输出：
- `IS_GIT_REPO=true/false`：是否为 Git 仓库
- `CURRENT_BRANCH=<分支名>`：当前分支名
- `BRANCH: 分支名 | 提交日期 | 提交信息`：本地分支列表
- `BRANCH_REMOTE: origin/分支名 | 提交日期 | 提交信息`：远程分支列表

**分支列表解析说明**：

检测输出中包含 `BRANCH:` 或 `BRANCH_REMOTE:` 前缀的行，格式为：
- `BRANCH: 分支名 | 提交日期 | 提交信息` — 本地分支
- `BRANCH_REMOTE: origin/分支名 | 提交日期 | 提交信息` — 远程分支（需去掉远程前缀展示给用户，如 `origin/feature-x` → 展示为 `feature-x`）

主agent在步骤 B 中应解析这些行生成交互选项。

#### 步骤 B：选择分支（条件步骤，使用 `feishu_ask_user_question`）

**判断逻辑**：

| 条件 | 动作 |
|------|------|
| `IS_GIT_REPO=false` | **跳过**，非 Git 项目 |
| 仅有 1 个本地分支且无远程分支补充 | **跳过**，自动使用当前分支 |
| 多个分支存在 | **必须询问** |

**调用参数**：
- `header`：`选择分支`
- `question`：`检测到 Git 仓库（当前分支：{CURRENT_BRANCH}），请选择要审查的分支`
- `multiSelect`：`false`
- `options`：

| 标签 | 描述 | 变量赋值 |
|------|------|----------|
| {分支名1} (当前) | {提交日期} · {提交信息前30字} | `TARGET_BRANCH={分支名1}` |
| {分支名2} | {提交日期} · {提交信息前30字} | `TARGET_BRANCH={分支名2}` |
| ... | ... | ... |

> **注意**：
> - 选项列表从步骤 A 的 `BRANCH:` / `BRANCH_REMOTE:` 行中动态生成，最多展示 8 个
> - 当前分支标记 `(当前)` 放在标签末尾
> - 远程分支的标签使用去掉远程前缀的短名称（如 `origin/feature-x` → `feature-x`），但 `TARGET_BRANCH` 记录带前缀的完整名（如 `origin/feature-x`），供步骤 C 切换时使用
> - 用户也可通过「Other」手动输入分支名

#### 步骤 C：切换分支（自动执行）

用户选择分支后，如果选择的不是当前分支，执行切换。

**执行脚本**：
```bash
bash scripts/phase2-switch-branch.sh "$PROJECT_DIR" "{TARGET_BRANCH}" "$CURRENT_BRANCH"
```

脚本会自动判断分支类型（本地/远程）并执行相应切换操作。

**切换失败时的处理**：
1. 脚本会输出警告：`⚠️ 分支切换失败，将使用当前分支 {CURRENT_BRANCH} 继续审查`
2. 继续执行后续流程，不阻塞
3. 在执行计划确认环节（阶段五步骤5）中明确显示实际使用的分支

---

### 阶段三：项目预扫描（自动执行，无需确认）

**目标**：快速了解项目规模、模块分布和项目类型，**在预扫描阶段完成单模块/多模块判断**，供后续交互阶段直接使用。

**执行脚本**：
```bash
bash scripts/phase3-project-scan.sh "$PROJECT_DIR"
```

脚本输出：
- `PROJECT_TYPE=maven-single|maven-multi|gradle-single|gradle-multi|unknown`
- `MODULE:模块名|相对路径|Java文件数|代码行数`：每个模块的详细信息
- 项目概况和模块树的可视化展示

**模块结构解析说明**：

预扫描输出中包含 `MODULE:` 前缀的行，格式为 `MODULE:模块名|相对路径|Java文件数|代码行数`。主agent在步骤2（方案B）动态生成模块选项时，应解析这些行提取模块信息，而非解析树状文本。

---

### 阶段四：openclaw-lark插件检测（自动执行，无需确认）

**目标**：检测OpenClaw是否安装openclaw-lark插件，决定是否在交互阶段显示飞书上传选项。

**执行脚本**：
```bash
bash scripts/phase4-detect-lark-plugin.sh
```

脚本输出：
- `LARK_PLUGIN_INSTALLED=true|false`：插件是否已安装并启用

---

### 阶段五：交互式确认（必须通过feishu_ask_user_question完成）

所有用户交互必须使用`feishu_ask_user_question`工具，**禁止跳过任何步骤**。每个步骤必须严格按照以下定义传递参数，不得自行增减选项或修改文案。

#### 步骤1：选择审查类型

**调用参数**：
- `header`：`审查类型`
- `question`：`请选择审查类型`
- `multiSelect`：`false`
- `options`：

| 标签 | 描述 | 变量赋值 |
|------|------|----------|
| 增量审查 | 审查最近 N 次提交的变更文件及其关联代码 | `REVIEW_TYPE=增量审查` |
| 存量审查 | 审查指定模块或全量代码 | `REVIEW_TYPE=存量审查` |

---

#### 步骤2：选择审查范围（条件步骤）

**判断逻辑**（基于步骤1结果和阶段三的 `PROJECT_TYPE`）：

| 条件 | 动作 |
|------|------|
| 步骤1 = 增量审查 | **必须询问**（方案 A） |
| 步骤1 = 存量审查 且 `PROJECT_TYPE` 为 `*-single` | **跳过此步骤**，自动设 `REVIEW_SCOPE=全量代码` |
| 步骤1 = 存量审查 且 `PROJECT_TYPE` 为 `*-multi` | **必须询问**（方案 B） |

**方案 A：增量审查 — 选择提交次数**

- `header`：`提交次数`
- `question`：`审查最近几次提交的变更？`
- `multiSelect`：`false`
- `options`：

| 标签 | 描述 | 变量赋值 |
|------|------|----------|
| 最近 1 次 | 仅审查最近一次提交 | `REVIEW_SCOPE=最近1次提交` |
| 最近 3 次 | 审查最近 3 次提交 | `REVIEW_SCOPE=最近3次提交` |
| 最近 5 次 | 审查最近 5 次提交（推荐） | `REVIEW_SCOPE=最近5次提交` |
| 最近 10 次 | 审查最近 10 次提交 | `REVIEW_SCOPE=最近10次提交` |

> 用户也可通过「Other」输入自定义次数，此时 `REVIEW_SCOPE=最近{N}次提交`。

**方案 B：存量审查（多模块）— 选择审查模块**

- `header`：`审查范围`
- `question`：`请选择要审查的模块（可多选）`
- `multiSelect`：`true`
- `options`：

| 标签 | 描述 | 变量赋值 |
|------|------|----------|
| 全量代码 | 审查所有模块 | `REVIEW_SCOPE=全量代码` |
| {模块1名称} | {模块1相对路径}，{N} 类 {M} 行 | `REVIEW_SCOPE` 追加模块路径 |
| {模块2名称} | {模块2相对路径}，{N} 类 {M} 行 | `REVIEW_SCOPE` 追加模块路径 |
| ... | ... | ... |

> **注意**：
> - 模块列表从阶段三预扫描结果中动态生成，每个模块的名称、路径和统计信息都来自预扫描输出
> - `multiSelect=true` 允许用户选择多个模块
> - 如果用户同时选了「全量代码」和具体模块，以「全量代码」为准
> - 用户选择具体模块后，`REVIEW_SCOPE` 为逗号分隔的模块相对路径，如 `user-service,order-service`

---

#### 步骤3：选择审查模式

**调用参数**：
- `header`：`审查模式`
- `question`：`请选择审查模式`
- `multiSelect`：`false`
- `options`：

| 标签 | 描述 | 变量赋值 |
|------|------|----------|
| fast | 快速扫雷，聚焦关键风险，约 5 分钟内出结果 | `REVIEW_MODE=fast` |
| standard | 标准审查，覆盖常规核心维度 + API设计 + 缓存基础 + 核心测试缺失，日常迭代推荐 | `REVIEW_MODE=standard` |
| deep | 深度审查，全量 15 维度，适合大版本上线前 | `REVIEW_MODE=deep` |
| security | 安全专项，聚焦安全核心维度 | `REVIEW_MODE=security` |

---

#### 步骤4：选择飞书上传选项（条件步骤）

**判断逻辑**（基于阶段四检测结果）：

| 条件 | 动作 |
|------|------|
| `LARK_PLUGIN_INSTALLED=true` | **必须询问** |
| `LARK_PLUGIN_INSTALLED=false` | **跳过此步骤**，自动设 `FEISHU_UPLOAD_OPTION=插件未安装` |

**调用参数**：
- `header`：`飞书上传`
- `question`：`检测到 openclaw-lark 插件，请选择审查结果的处理方式`
- `multiSelect`：`false`
- `options`：

| 标签 | 描述 | 变量赋值 |
|------|------|----------|
| 仅显示报告 | 只在聊天中显示完整审查报告 | `FEISHU_UPLOAD_OPTION=仅显示报告` |
| 上传到云文档 | 审查报告上传到飞书云文档，聊天中显示精简摘要 | `FEISHU_UPLOAD_OPTION=上传到云文档` |
| 上传到多维表格 | 问题清单录入飞书多维表格，聊天中显示精简摘要 | `FEISHU_UPLOAD_OPTION=上传到多维表格` |
| 同时上传两者 | 同时上传云文档和多维表格，聊天中显示精简摘要 | `FEISHU_UPLOAD_OPTION=同时上传两者` |

---

#### 步骤5：确认执行计划

**必须展示完整执行计划并等待用户确认后，才能进入阶段六。**

**调用参数**：
- `header`：`确认执行`
- `question`：`请确认以下审查配置`

```
📋 执行计划：
- 项目路径：{PROJECT_DIR}
- 项目类型：{PROJECT_TYPE}
- 审查类型：{REVIEW_TYPE}
- 审查范围：{REVIEW_SCOPE}
- 审查模式：{REVIEW_MODE}
- 启用维度：{根据模式 × 维度矩阵列出具体维度名称}
- 飞书上传：{FEISHU_UPLOAD_OPTION}
```

- `multiSelect`：`false`
- `options`：

| 标签 | 描述 |
|------|------|
| ✅ 确认执行 | 按以上配置开始审查 |
| ❌ 取消 | 取消本次审查 |

> **注意**：用户选择「确认执行」后进入阶段六调用子agent；选择「取消」则终止流程。

#### 步骤5确认后的启动提示

用户确认后、调用子agent之前，**必须立即输出以下格式的提示信息**，让用户清楚知道正在启动独立子代理执行长时间任务：

```
🚀 正在启动独立代码审查子代理...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
⏱️ 预估耗时：{预估时间}
📌 子代理将独立执行完整审查流程，完成后自动返回结果。

{FEISHU_UPLOAD_OPTION 不是「仅显示报告」/「插件未安装」时，追加以下行}
📤 审查完成后将自动上传到飞书（{FEISHU_UPLOAD_OPTION}），无需手动操作。

💡 温馨提示：审查期间您可以继续使用 OpenClaw 进行其他操作。
```

**预估时间参考**（根据 `REVIEW_MODE` + 项目规模估算）：

| 模式 | 小型项目（<50 类） | 中型项目（50-200 类） | 大型项目（>200 类） |
|------|:---:|:---:|:---:|
| fast | 2-3 分钟 | 3-5 分钟 | 5-8 分钟 |
| standard | 5-8 分钟 | 8-15 分钟 | 15-25 分钟 |
| deep | 10-15 分钟 | 15-30 分钟 | 30-60 分钟 |
| security | 5-10 分钟 | 10-20 分钟 | 20-35 分钟 |

> 项目规模从阶段三的「Java文件总数」获取。增量审查的时间按变更文件数估算，通常比全量快 30-50%。

---


### 阶段六：代码审查（使用子agent执行）

**目标**：将用户确认的审查配置和项目信息作为参数注入子agent prompt，由子agent独立完成代码审查和飞书上传（可选），最后将结果汇总返回主agent。

#### 子agent调用方式

使用 Agent 工具，按以下方式构造 prompt：

**1. 注入审查参数**（替换 `{变量名}` 为实际值）：

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

### 项目概况（阶段三预扫描结果）
{PROJECT_SCAN_RESULT}

> 以下数据已由预扫描获取，子agent **禁止重复执行**：项目类型、模块结构（MODULE:行）、文件数、行数统计。子agent应直接利用这些数据确定审查范围，仅需对目标文件执行 grep/read 操作。

### 增量提交记录（仅增量审查时提供）
{GIT_LOG_OUTPUT}

### 变更文件列表（仅增量审查时提供）
{CHANGED_FILES_OUTPUT}

### 变更统计概览（仅增量审查时提供）
{DIFF_STATS_OUTPUT}
```

**2. 附加 agent 提示词内容**：由 `agents/cc-code-reviewer.md` 子代理自动加载

**3. 附加执行指令**：
```
请基于以上审查参数，立即开始执行代码审查。不要进行任何用户交互或询问，直接从代码审查开始执行。
```

#### 参数来源说明

| 变量名 | 来源 | 示例值 |
|--------|------|--------|
| `PROJECT_DIR` | 阶段一输出 | `/tmp/openclaw/cc-code-reviewer/1744567890` 或本地路径 |
| `PROJECT_NAME` | `basename "$PROJECT_DIR"` 自动提取 | `spring-ai-agent-utils` |
| `PROJECT_TYPE` | 阶段三输出 | `maven-single` / `maven-multi` / `gradle-single` / `gradle-multi` / `unknown` |
| `REVIEW_TYPE` | 阶段五步骤1用户选择 | `增量审查` / `存量审查` |
| `REVIEW_SCOPE` | 阶段五步骤2用户选择 | `最近5次提交` / `全量代码` / `user-service,order-service` |
| `REVIEW_MODE` | 阶段五步骤3用户选择 | `fast` / `standard` / `deep` / `security` |
| `FEISHU_UPLOAD_OPTION` | 阶段五步骤4用户选择 | `仅显示报告` / `上传到云文档` / `上传到多维表格` / `同时上传两者` / `插件未安装` |
| `PROJECT_SCAN_RESULT` | 阶段三完整输出 | 项目概况、模块结构的原始输出 |
| `GIT_LOG_OUTPUT` | 条件生成（见下方） | `git log --oneline -N` 的输出 |
| `CHANGED_FILES_OUTPUT` | 条件生成（仅增量审查） | `git diff --name-only` 的输出，变更文件路径列表 |
| `DIFF_STATS_OUTPUT` | 条件生成（仅增量审查） | `git diff --stat` 的输出，各文件改动行数统计 |

#### 增量审查预处理（仅增量审查时执行）

在调用子agent之前，先执行以下命令获取提交记录、变更文件列表和变更统计。**注意**：脚本会自动处理提交数不足 N 的情况，防止 `HEAD~N` 越界。

**执行脚本**：
```bash
bash scripts/phase6-prepare-incremental.sh "$PROJECT_DIR" {N}
```

脚本输出（三个部分用 `# ===` 分隔）：
1. `# === 提交记录 ===` 之后的内容 → `GIT_LOG_OUTPUT`
2. `# === 变更文件列表 ===` 之后的内容 → `CHANGED_FILES_OUTPUT`
3. `# === 变更统计 ===` 之后的内容 → `DIFF_STATS_OUTPUT`

**主 Agent 需解析脚本输出，分别提取三个部分作为独立变量注入子 Agent**。

**异常情况处理**：
- 如果 `CHANGED_FILES_OUTPUT` 为空（没有变更文件），主agent应：
  1. 告知用户：选择的提交范围内没有变更文件
  2. 询问是否调整提交次数或切换到存量审查
  3. 不应调用子agent处理空文件列表

#### 子agent返回结果

子agent执行完成后，根据飞书上传选项返回不同格式的结果，主agent需将此结果展示给用户。

**已上传飞书时**（简化汇总 + 飞书链接）：

```
✅ 代码审查已完成！

📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / 待确认: {n} / P3: {n}）

🔥 最高风险项：
  - P0-1: {问题一句话描述} — {位置}
  （最多列 5 条）

📄 飞书云文档：{链接}
📋 问题清单：{链接}

💡 建议：{一句话关键建议}
👉 详细报告请点击上方飞书链接查看。
```

**未上传飞书时**（完整报告）：子agent会将第三步生成的完整审查报告原样输出，包含所有章节（审查配置快照、执行摘要、各级别问题详情、修复优先级、总结等）。

**异常降级**：如果飞书上传步骤失败，子agent会降级为输出完整报告，并说明失败原因。主agent应将结果直接展示给用户。


---

## 重要规则

### 强制规则

1. **必须使用`feishu_ask_user_question`**：所有用户交互（分支选择、审查类型选择、模块选择、模式选择、飞书上传选项、执行确认）都必须使用此工具
2. **禁止模拟工具**：不得用普通文本问答替代工具交互
3. **执行前强制确认**：必须通过`feishu_ask_user_question`展示执行计划并等待用户确认，**不能跳过**
4. **三个核心选项必须全部明确**：审查类型 + 审查范围 + 审查模式，缺一不可
5. **强制交互流程**：无论用户是否提供参数，都必须通过`feishu_ask_user_question`依次引导用户完成所有步骤
6. **强制中文输出**：所有交互和报告都必须使用中文
7. **最终确认前零审查动作**：不得在用户确认前执行任何代码扫描
8. **禁止跳过步骤**：任何时候都不能跳过任何交互步骤，即使参数已经明确

### 条件步骤规则

1. **单模块项目自动跳过步骤2**：如果 `PROJECT_TYPE` 为 `maven-single` 或 `gradle-single` 且步骤1选择了「存量审查」，步骤2（选择审查范围）必须跳过，自动设 `REVIEW_SCOPE=全量代码`
2. **openclaw-lark插件检测**：阶段四检测插件安装状态，根据结果决定是否执行步骤4（飞书上传选项）；插件未安装时自动设 `FEISHU_UPLOAD_OPTION=插件未安装`
3. **飞书上传执行**：子agent根据 `FEISHU_UPLOAD_OPTION` 参数执行对应上传动作（云文档、多维表格或两者）
4. **Git 分支选择**：阶段二仅在项目为 Git 仓库且存在多个活跃分支时执行；非 Git 项目或单分支项目自动跳过

---

## 错误处理

如果`feishu_ask_user_question`工具不可用或调用失败：
- 必须明确告知阻塞原因
- 停止在该步骤
- 不能退回为普通文本提问

---

## 示例对话

### 示例1：本地Maven单模块项目（openclaw-lark插件已安装）

```
用户：帮我审查这个项目 /Users/jiangkun/Documents/github-kb/spring-ai-agent-utils

我：[阶段一] 检测到本地项目: /Users/jiangkun/Documents/github-kb/spring-ai-agent-utils
   [阶段二] 检测 Git 分支 → 仅 main 分支，跳过分支选择
   [阶段三] 执行项目预扫描，展示项目概览和模块树
           ✅ 检测到 Maven 单模块项目
   [阶段四] 检测 openclaw-lark 插件...
           ✅ 检测到 openclaw-lark 插件已安装

   [然后通过 feishu_ask_user_question 引导用户完成：
      步骤1: 选择审查类型（增量/存量）
         → 用户选择：存量审查
      步骤2: [Maven 单模块项目，跳过审查范围选择] 自动使用「全量代码」
      步骤3: 选择审查模式（fast/standard/deep/security）
         → 用户选择：standard
      步骤4: [检测到 openclaw-lark 插件已安装] 询问飞书上传选项
         → 用户选择：同时上传两者
      步骤5: 展示执行计划并等待用户确认
         → 用户确认执行]

   [阶段六] 用户确认执行后，输出启动提示：
      🚀 正在启动独立代码审查子代理...
      📋 任务配置：standard 模式 · 存量审查 · 全量代码
      ⏱️ 预估耗时：8-15 分钟
      📌 子代理将独立执行完整审查流程，完成后自动返回结果。
      📤 审查完成后将自动上传到飞书（同时上传两者），无需手动操作。
      💡 温馨提示：审查期间您可以继续使用 OpenClaw 进行其他操作。

           → 调用子agent执行代码审查（注入参数 + agent提示词）
           → 子agent执行审查 → 上传飞书云文档 → 创建多维表格 → 返回精简汇总
   [展示结果]
      ✅ 代码审查已完成！
      📊 审查结果：8 个问题（P0: 1 / P1: 3 / P2: 4）
      🔥 最高风险项：...
      📄 飞书云文档：https://...
      📋 问题清单：https://...
      💡 建议：...
```

### 示例2：Git仓库（Maven多模块，openclaw-lark插件未安装）

```
用户：帮我审查这个项目 https://github.com/spring-ai-examples/spring-boot-multi-module.git

我：[阶段一] 检测到 Git 仓库，正在克隆...
           ✅ 克隆成功: /tmp/openclaw/cc-code-reviewer/1744567890
   [阶段二] 检测 Git 分支 → 检测到 main, develop, feature/auth 三个分支
           → 用户选择：develop
           ✅ 已切换到分支: develop
   [阶段三] 执行项目预扫描，展示项目概览和模块树
           ✅ 检测到 Maven 多模块项目
   [阶段四] 检测 openclaw-lark 插件...
           ⚠️ 未检测到 openclaw-lark 插件，跳过飞书上传功能

   [然后通过 feishu_ask_user_question 引导用户完成：
      步骤1: 选择审查类型（增量/存量）
         → 用户选择：存量审查
      步骤2: 选择审查范围（因为是多模块项目）
         → 用户选择：user-service, order-service
      步骤3: 选择审查模式
         → 用户选择：deep
      步骤4: [openclaw-lark 插件未安装，跳过飞书上传选项]
      步骤5: 展示执行计划并等待用户确认
         → 用户确认执行]

   [阶段六] 用户确认执行后，输出启动提示：
      🚀 正在启动独立代码审查子代理...
      📋 任务配置：deep 模式 · 存量审查 · user-service,order-service
      ⏱️ 预估耗时：30-45 分钟
      📌 子代理将独立执行完整审查流程，完成后自动返回结果。
      💡 温馨提示：审查期间您可以继续使用 OpenClaw 进行其他操作。

           → 调用子agent执行代码审查（注入参数 + agent提示词）
           → 子agent执行审查 → 返回完整审查报告
   [展示结果]
      （完整审查报告，包含所有章节）
```