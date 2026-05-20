# 大仓库分批扫描设计

> 日期：2026-05-19
> 状态：Approved

## 背景与问题

当审查大型 Java 仓库时（如 6000 文件 / 200k 行），单个 sub-agent 的 200k token 上下文无法容纳所有文件内容 + 审查推理 + 输出报告。当前架构只启动一个 agent，agent 会自行缩减审查范围，导致不可控的覆盖率丢失。

## 设计目标

- 仅在大仓库时自动触发，小仓库保持现有单 agent 流程不变
- 用户体验上只多一步并发数选择，其余自动完成
- 最终输出一份统一的审查报告，用户无需感知分批细节

## 决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 触发阈值 | 动态公式：`FILE_COUNT × 500 + LINE_COUNT × 3 > 100,000` | 精确反映上下文压力，不依赖硬编码文件数 |
| 并发策略 | 用户自选（1/3/5 路） | 机器差异大，让用户按硬件选择 |
| 分批粒度 | 纯 token 预算打包，不按模块 | 模块大小不均，token 预算可保证批次均衡 |
| 合并方式 | 主 skill 直接合并 | 不额外启动 agent，减少复杂度和 token 消耗 |
| 实现路径 | prompt 内实现，不新增脚本 | 分批计算简单，prompt 指令足够；改动面最小 |

## 1. 触发判定

**时机**：交互式模式在步骤 2（选择审查类型）确定 REVIEW_TYPE 后、步骤 6 前执行判定。快速启动模式在参数校验时一并判定。

**公式**：
```
estimated_tokens = REVIEW_FILE_COUNT × 500 + REVIEW_LINE_COUNT × 3
BATCH_MODE = estimated_tokens > 100,000 AND REVIEW_TYPE = 存量审查
```

**前提**：分批模式仅对存量审查生效。增量审查的变更文件数通常远低于阈值；即使超过阈值，batch agent 缺少增量上下文（GIT_LOG/CHANGED_FILES），无法判断问题是变更引入还是存量，因此不进入分批。

- `REVIEW_FILE_COUNT` 和 `REVIEW_LINE_COUNT` 从 phase3-project-scan.sh 输出中解析
- `500`：每个文件的工具调用 + agent 评估开销（token）
- `3`：每行 Java 代码平均 token 数
- `100,000`：单批留给文件内容 + 开销的上限（200k 总上下文 - 25k 系统 prompt - 50k agent 输出 ≈ 125k，取 100k 留余量）

**判定结果**：
- `BATCH_MODE=false` → 走现有单 agent 流程，不做任何改动
- `BATCH_MODE=true` → 进入分批模式

## 2. 分批计算

主 skill 在 prompt 中执行以下步骤（不使用脚本）：

1. **收集文件路径和行数**：用 Bash 执行 `find "$PROJECT_DIR" -name '*.java' ... -exec wc -l {} +` 获取每个文件的路径和行数。增量审查时不执行此步（已由触发条件排除）
2. **风险排序**：按文件名模式排序（Controller/Service/Security → 客户端/线程池/定时任务 → DTO/工具类），通过 Bash 按文件名后缀分组实现：`*Controller.java`、`*Service.java` 排前，`*DTO.java`、`*VO.java` 排后
3. **逐文件累加**：
   ```
   batch_token_budget = 100,000
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
4. **输出**：得到 `BATCH_COUNT` 和每个批次的文件列表

**注意**：分批模式仅对存量审查生效（由触发条件保证）。增量审查不会进入分批流程。

## 3. 交互步骤变更

### 交互式模式（FAST_MODE=false）

分批模式启用时，在现有步骤 5（飞书上传选项）之后、确认执行计划之前，新增一个步骤。

**完整步骤编号**：

| 步骤 | 内容 | 条件 |
|------|------|------|
| 1 | 选择审查分支 | IS_GIT_REPO=true 且分支数 > 1 |
| 2 | 选择审查类型 | 始终 |
| 3 | 选择审查范围 | 增量 / 存量+多模块 |
| 4 | 选择审查模式 | 始终 |
| 5 | 选择飞书上传选项 | LARK_PLUGIN_INSTALLED=true |
| **6** | **选择并发数** | **BATCH_MODE=true** |
| 7 | 确认执行计划 | 始终 |

**新增步骤 6**（条件步骤，仅 BATCH_MODE=true）：

在调用 AskUserQuestion 之前，先输出分批信息：
```
📊 大仓库分批扫描

本次审查范围较大，将采用分批并行扫描：
- 文件总数：{REVIEW_FILE_COUNT} 个
- 代码行数：{REVIEW_LINE_COUNT} 行
- 预计分批：{BATCH_COUNT} 批
```

AskUserQuestion 参数：
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
每批耗时 = 根据现有模式×规模估算表
total_min = ceil(BATCH_COUNT / CONCURRENCY) × 每批耗时
```

**步骤 7 确认执行计划**（BATCH_MODE=true 时追加）：
```
📋 执行计划：
- 项目路径：{PROJECT_DIR}
- 项目类型：{PROJECT_TYPE}
- 审查分支：{TARGET_BRANCH 或 CURRENT_BRANCH}
- 审查类型：{REVIEW_TYPE}
- 审查范围：{REVIEW_SCOPE}
- 审查模式：{REVIEW_MODE}
- 启用维度：{维度列表}
- 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）
- 预计耗时：约 {total_min} 分钟
- 飞书上传：{FEISHU_UPLOAD_OPTION}
```

BATCH_MODE=false 时，步骤 6 跳过，步骤 7 内容与现有设计一致（无扫描策略行）。

### 快速启动模式（FAST_MODE=true）

新增可选参数 `--concurrency`：

| 参数 | 是否必填 | 取值范围 | 说明 |
|------|----------|----------|------|
| `--concurrency` | 可选 | `1` / `3` / `5` | 并发数，默认 `3` |

- 不提供时使用默认值 3
- BATCH_MODE=false 时该参数被忽略（不报错）
- 校验规则：不在取值范围内时报错，但不影响其他参数校验

**参数映射**：
| 快速启动参数 | 映射变量 | 值转换 |
|-------------|----------|--------|
| `--concurrency 1` | `CONCURRENCY=1` | 直接使用 |
| `--concurrency 3` 或未提供 | `CONCURRENCY=3` | 默认值 |
| `--concurrency 5` | `CONCURRENCY=5` | 直接使用 |

**快速启动校验通过后的启动提示**（BATCH_MODE=true 时追加分批信息）：
```
🚀 快速启动模式 — 正在启动分批并行代码审查...

📋 任务配置：{REVIEW_MODE} 模式 · {REVIEW_TYPE} · {REVIEW_SCOPE}
📊 扫描策略：{BATCH_COUNT} 批 / {CONCURRENCY} 路并发
🌿 审查分支：{TARGET_BRANCH}
📤 飞书上传：{FEISHU_UPLOAD_OPTION}
⏱️ 预估耗时：约 {total_min} 分钟
📌 每批子代理独立执行审查，全部完成后自动合并结果。
```

## 4. Batch Agent 编排与执行

### 启动提示

步骤 7 用户确认后（或快速启动校验通过后）：

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

### Prompt 注入格式

每个 batch agent 的 prompt 与现有格式一致，但额外注入以下参数：

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
{逐行列出文件路径}

### 项目概况（预扫描结果）
{PROJECT_SCAN_RESULT}

请基于以上审查参数，立即开始执行代码审查。不要进行任何用户交互或询问，直接从代码审查开始执行。
```

**关键差异**（对比现有单 agent 调用）：

| 字段 | 单 agent | Batch agent |
|------|----------|-------------|
| 审查文件数量 | REVIEW_FILE_COUNT（总量） | BATCH_FILE_COUNT（本批） |
| 审查代码行数 | REVIEW_LINE_COUNT（总量） | BATCH_LINE_COUNT（本批） |
| 飞书上传选项 | 用户选择的值 | 固定"飞书上传不可用" |
| 批次编号 | 无 | BATCH_INDEX/BATCH_COUNT |
| 审查输出模式 | 无 | "仅发现清单" |
| 文件列表来源 | agent 自行 Glob | 外部注入，agent 不扫描 |
| 增量数据 | 注入 GIT_LOG 等 | 不注入（分批模式仅支持存量审查的文件子集） |

**飞书上传**：batch agent 不执行飞书上传。飞书上传由主 skill 在合并完成后统一处理。

### 编排逻辑

以 CONCURRENCY=3、BATCH_COUNT=9 为例：

```
轮次 1：同时启动 Agent(batch-1) + Agent(batch-2) + Agent(batch-3)
  → 等待全部完成
轮次 2：同时启动 Agent(batch-4) + Agent(batch-5) + Agent(batch-6)
  → 等待全部完成
轮次 3：同时启动 Agent(batch-7) + Agent(batch-8) + Agent(batch-9)
  → 等待全部完成
```

每轮同时发出 CONCURRENCY 个 Agent 工具调用。当前轮所有 agent 返回后，开始下一轮。

CONCURRENCY=1 时退化为串行，每次启动一个 agent。

### Batch Agent 输出格式

每个 batch agent 完成后，将发现写入文件 `/tmp/review-batch-{BATCH_INDEX}-{PROJECT_NAME}.md`，格式如下：

```markdown
# Batch {BATCH_INDEX}/{BATCH_COUNT} 审查发现

## 审查范围
- 文件数：{BATCH_FILE_COUNT}
- 行数：{BATCH_LINE_COUNT}
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

**重要**：batch agent 使用 `审查输出模式=仅发现清单` 时，必须：
- 不输出完整报告（不包含摘要、统计、建议等段落）
- 不执行飞书上传
- 只输出结构化的发现列表
- 无问题的文件跳过不列

### Agent Prompt 改动（cc-code-reviewer.md）

在 agent prompt 中新增 `审查输出模式` 参数处理：

```
- **审查输出模式**（`REVIEW_OUTPUT_MODE`）：
  - `完整报告`（默认）：按 REPORT_FORMAT_PATH 输出完整审查报告
  - `仅发现清单`：只输出结构化发现列表，不生成完整报告，不执行飞书上传。用于分批审查时的单批输出
```

当 `REVIEW_OUTPUT_MODE=仅发现清单` 时：
- 跳过第四步（飞书上传）和第五步（多维表格）
- 跳过完整报告格式，直接输出发现列表
- 输出追加写入到 `/tmp/review-batch-{BATCH_INDEX}-{PROJECT_NAME}.md`
- 阶段 A（文件收集）跳过，直接使用注入的文件列表
- 阶段 B（风险排序）跳过，文件已按风险排序注入
- 直接从阶段 C（逐文件审查）开始

## 5. 报告合并

所有 batch agent 完成后，主 skill 执行合并（不启动额外 agent）。

### 合并步骤

1. **读取所有 batch 文件**：逐个 Read `/tmp/review-batch-{i}-{PROJECT_NAME}.md`（i = 1..BATCH_COUNT）
2. **提取所有问题**：从每个 batch 的发现列表中解析出结构化问题
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

### 输出方式

复用现有逻辑：
- 仅显示报告 → 输出合并后的完整报告到聊天
- 飞书上传 → 用 `lark-doc`/`lark-base` skill 上传合并后的报告
- 报告文件保存到 `{PROJECT_DIR}/code-review-report-{PROJECT_NAME}-{timestamp}.md`

### 合并后结果展示

```
✅ 代码审查已完成！⏱️ 耗时 {X} 分 {Y} 秒

📊 扫描策略：分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）
📊 审查覆盖：{总扫描文件数}/{REVIEW_FILE_COUNT} 文件（{总扫描行数}/{REVIEW_LINE_COUNT} 行），覆盖率 {综合覆盖率}%
📊 审查结果：{问题总数} 个问题（P0: {n} / P1: {n} / P2: {n} / P3: {n} / 待确认: {n}）

🔥 最高风险项：
  - P0-1: {问题一句话描述} — {位置}
  （最多列 5 条）

{飞书上传时}
📄 审查报告：{链接}
📋 问题清单：{链接}

💡 建议：{一句话关键建议}
```

### 上下文保护

- 每个 batch 文件约 2-5k token（只含发现清单，不含代码原文）
- 30 个 batch 的合并读取总量约 60-150k token
- 合并操作在主 skill 上下文中执行，通过压缩上下文可容纳

## 6. 错误处理

| 场景 | 处理方式 |
|------|----------|
| 某个 batch agent 超时/失败 | 该批次标记为"未完成"，其余批次继续。合并时标注该批次未覆盖 |
| 所有 batch 均失败 | 输出失败报告，提示用户重试 |
| 合并时某 batch 文件不存在 | 跳过该批次，报告中标注缺失 |
| 用户中途取消 | 已完成的批次结果保存到 `/tmp/`，提示用户可恢复 |

## 7. 改动文件清单

| 文件 | 改动内容 |
|------|----------|
| `skills/cc-code-reviewer/SKILL.md` | 新增分批判定逻辑、步骤 6（并发数选择）、步骤 7 追加分批信息、batch agent 编排、报告合并 |
| `agents/cc-code-reviewer.md` | 新增 `审查输出模式` 参数、`批次编号` 参数、`本批文件列表` 参数；batch 模式下跳过阶段 A/B 和飞书上传 |
| `references/report-format.md` | 无改动，合并时复用 |
| `references/review-framework.md` | 无改动 |
| `scripts/` | 无新增脚本 |

## 8. 未覆盖事项

以下不在本次设计范围内：
- 分批模式的增量审查支持（当前仅支持存量审查的分批；增量审查文件数通常不多，不需要分批）
- 断点续扫（跨会话恢复未完成的批次）
- DTO/Entity 等低风险文件的自动跳过优化
- 分批扫描的飞书 Base 分批写入（飞书上传在合并后统一处理）
