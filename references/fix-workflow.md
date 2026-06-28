# Fix Workflow

本文件定义 `cc-code-fixer` 的修复阶段工作流。修复器只消费已有审查报告、飞书问题清单或人工整理后的 Fix TODO List，不重新执行完整代码审查。

修复阶段的核心规则：**交互确认是硬门禁**。scan 可以自动化，fix 必须由用户确认待修复问题清单、修复关键点、输出目标和执行方式后才能修改代码。输出目标根据输入的问题清单类型动态展示：一个写回原始来源选项，加三个额外创建独立修复报告的选项。Superpowers 可选：只有检测到相关技能完整安装时，才展示 Superpowers 修复路线；否则只进入直接修复路线。

---

## Fix Input Normalization

`cc-code-fixer` 入口只接收项目地址。待修复问题确认清单必须在项目预检测之后通过一次 AskUserQuestion 收集问题清单位置。不得先让用户选择本地 Markdown、飞书云文档或飞书多维表格；必须明确要求用户在 Other/free-form 中粘贴 URL 或本地路径，并根据输入动态识别为本地 Markdown、飞书云文档或飞书多维表格。

归一化结果至少包含：

| 字段 | 说明 |
|------|------|
| `FIX_INPUT_TYPE` | `local-markdown`、`feishu-doc`、`feishu-base` 或 `feishu-base-token` |
| `FIX_INPUT_SOURCE` | 用户在「问题清单位置」步骤中提供的本地 Markdown 路径、飞书文档 URL、Base URL、带 `table=` 的 wiki URL 或 `base:{BASE_TOKEN}:{TABLE_ID}` |
| `PROJECT_DIR` | 待修复项目路径，必须是本地可访问目录 |
| `ISSUE_SOURCE_SUMMARY` | 从报告或表格中提取的问题总数、优先级分布和来源说明 |
| `NORMALIZED_ISSUES` | 归一化后的完整问题清单 |
| `STATUS_FILTERED_ISSUES` | 排除已完成或明确不处理状态后的待确认问题清单 |
| `SKIPPED_STATUS_COUNTS` | 因 `fix_status` 跳过的问题数量，按状态聚合 |
| `CONFIRMED_ISSUE_IDS` | 用户确认纳入本轮修复的问题编号 |
| `OUTPUT_TARGET` | `original-source`、`report-local-markdown`、`report-feishu-doc` 或 `report-feishu-base` |
| `EXECUTION_ROUTE` | `direct` 或 `superpowers` |
| `WORKSPACE_STRATEGY` | 直接修复路线下为 `current`、`branch` 或 `worktree` |
| `FIX_COMPLETED_AT` | 修复完成后由 `phase9-collect-fix-metadata.sh` 输出的当前时间 |
| `FIX_BRANCH` | 修复完成后由实际修复工作区 Git 状态输出的当前分支 |
| `FIX_ACTOR` | 修复完成后由实际修复工作区 `git config user.name/user.email` 输出的当前 Git 用户 |

### 本地 Markdown 报告

本地报告必须满足：

- 文件存在且扩展名为 `.md`
- 只有本地 Markdown 输入允许调用 `core/detect-fix-input.sh`，用于路径存在性校验和绝对路径归一化
- 本地 Markdown 必须直接读取文件内容，再按 Markdown 报告规则解析
- 内容包含可识别的问题编号、位置、问题描述和修复建议
- 相对路径必须基于当前工作目录解析为绝对路径
- 如果报告格式不完整，修复器只能提取可确认的问题，并把其余项列入「未修复问题」或「待人工确认」

本地 Markdown 的识别基于用户输入的路径形态和文件存在性。识别为本地 Markdown 后才允许调用 `core/detect-fix-input.sh` 做路径校验和绝对路径归一化。

### 飞书云文档

飞书云文档输入必须根据用户粘贴的 URL 动态识别，常见形态包括飞书或 Lark 的 `/docx/`、`/docs/` 文档 URL。识别后必须先通过 `lark-cli docs` 和 `lark-doc` skill 读取文档内容，再按 Markdown 报告规则解析。飞书云文档和飞书多维表格不得调用 `core/detect-fix-input.sh`，不得使用 Bash 脚本识别、提取或归一化云端问题清单输入。不得使用 Python 脚本读取飞书云文档或飞书多维表格。读取失败时不得继续假装拥有完整问题上下文，应进入 degraded mode，并要求用户改用本地 Markdown 或飞书多维表格来源。

### 飞书多维表格

飞书 Base 输入必须根据用户粘贴的 URL 或 token 动态识别，可以是 `/base/` URL、带 `table=` 参数的 `/wiki/` URL 或 `base:{BASE_TOKEN}:{TABLE_ID}`。输入必须解析出 `table_id`；可直接解析 `base_token` 时也要保留，并通过 `lark-cli base` 和 `lark-base` skill 读取记录。如果输入是 `/wiki/{WIKI_TOKEN}?table={TABLE_ID}&view={VIEW_ID}` 链接，必须从查询参数中提取 `table` 作为 `table_id`、可选提取 `view` 作为 `view_id`，并用 `lark-cli wiki spaces get_node` 将 wiki token 解析为真实 `base_token`（`.data.node.obj_token`）后再读取记录；不得把 wiki token 当作 base token 使用。如果 URL 无法稳定提取表 ID，必须要求用户补充 `base:{BASE_TOKEN}:{TABLE_ID}` 格式。读取记录时只处理具备「问题编号」「位置」「问题描述」「修复建议」「修复状态」字段的数据行。飞书 Base 输入不得调用 `core/detect-fix-input.sh`。

### 状态过滤

本地 Markdown、飞书云文档和飞书 Base 都可能是重复使用的有状态问题清单。修复器必须在归一化后、展示确认表格前执行统一状态过滤：

- `fix_status` 为空或为 `待修复`：进入待确认问题清单。
- `fix_status` 为 `修复中`：默认跳过；只有用户明确要求继续处理修复中的问题时才进入待确认问题清单。
- `fix_status` 为 `已修复`、`已忽略` 或 `不适用`：必须跳过，不能进入待确认问题清单，不能被「确认全部纳入修复」隐式选中。
- 本地 Markdown 和飞书云文档如果出现 `修复状态`、`fix_status`、`状态：已修复` 等状态行，或问题位于「已修复问题」分区下，必须映射到对应 `fix_status`；没有状态信息时才按 `待修复` 处理。
- 「修复输入解析完成」摘要必须展示原始问题总数、可纳入确认数、因状态跳过数量和 `SKIPPED_STATUS_COUNTS`。

---

## Preflight Sequence

代码变更前必须完成以下预检，预检失败时不得修改代码：

1. 解析项目地址，形成 `PROJECT_DIR` 与 `PROJECT_SOURCE`。
2. 检查 `PROJECT_DIR` 是否存在、是否为 Git 仓库、当前分支和工作区状态。
3. 扫描项目结构、模块、技术栈和默认验证命令线索。
4. 检测 lark-cli 与 Superpowers 可用性。
5. 通过一次 AskUserQuestion 收集问题清单位置，并根据输入动态识别清单类型。
6. 按识别结果读取本地 Markdown、飞书云文档或飞书多维表格，提取可确认的问题编号、位置、问题描述、修复建议和修复状态。
7. 对归一化问题清单执行状态过滤，跳过明确 `已修复`、`已忽略`、`不适用` 的问题。
8. 展示状态过滤后的问题清单表格，获得用户对本轮修复问题集合的确认。
9. 展示修复关键点，获得用户确认。
10. 获得输出目标确认：根据 `FIX_INPUT_TYPE` 只展示一个写回原始问题清单来源的选项，并同时展示三种独立修复报告选项。
11. 通过 AskUserQuestion 选择执行方式：直接开始修复，或在 Superpowers 可用时使用 Superpowers 修复。
12. 直接修复路线必须确认工作区策略：当前分支、新分支或 worktree。
13. 输出最终执行计划并获得确认。

飞书云文档或飞书多维表格读取失败时，如果没有来自本地 Markdown、已确认缓存或其他可信来源的已归一化问题上下文，必须停止在代码变更之前，只生成本地失败报告。无已归一化问题上下文时必须停止修复。

---

## Execution Route Selection

修复器必须在问题范围、修复关键点和输出目标都确认后，使用 AskUserQuestion 询问执行方式：

- `直接开始修复`：由主 skill 执行修复、测试、验证和报告生成。
- `使用 Superpowers 修复`：只有 `SUPERPOWERS_AVAILABLE=true` 时展示；进入 brainstorming 和 subagent-driven-development。
- `取消`：停止，不修改任何文件。

Superpowers 不完整安装时，不进入 degraded mode，也不展示 `使用 Superpowers 修复`。缺失项只出现在预检测摘要中，作为为什么没有该选项的说明。

---

## Output Target Selection

输出目标只通过一次 AskUserQuestion 确认，不得在修复完成后追加新的回写确认问题。

该 AskUserQuestion 必须根据用户先前提供的问题清单类型动态生成选项：

- 如果 `FIX_INPUT_TYPE=local-markdown`，写回原始来源选项为 `写回原始本地 Markdown`，只更新 `FIX_INPUT_SOURCE` 指向的原始本地 Markdown 文件。
- 如果 `FIX_INPUT_TYPE=feishu-doc`，写回原始来源选项为 `写回原始飞书云文档`，只更新 `FIX_INPUT_SOURCE` 指向的原始云文档。
- 如果 `FIX_INPUT_TYPE=feishu-base` 或 `feishu-base-token`，写回原始来源选项为 `写回原始飞书多维表格`，只更新读取阶段定位到的原始 Base 表格记录。

同时必须展示三个额外创建独立修复报告的选项：

- `创建独立本地 Markdown 修复报告`
- `创建独立飞书云文档修复报告`
- `创建独立飞书多维表格修复报告`

用户选择写回原始来源时，必须只更新本轮 `CONFIRMED_ISSUE_IDS` 对应的问题项，字段至少包括：`修复状态`、`修复时间`、`修复分支`、`修复人`、`备注`。本地 Markdown 和云文档没有结构化字段时，必须在对应问题条目下追加或更新同名状态行。无法稳定定位条目时不得整文件重写，只在本地报告中记录待手动同步。

用户选择独立修复报告时，不得修改原始问题清单来源。独立报告必须包含修复配置快照、修复输入摘要、问题状态、验证结果和后续建议。

如果 `LARK_PLUGIN_INSTALLED=false`，飞书云文档和飞书多维表格独立报告选项仍可展示，但 description 必须说明不可用；用户选择飞书目标时进入本地 Markdown 降级输出，并在执行计划中标注飞书上传不可用原因。

---

## Direct Fix Flow

直接修复路线由主 skill 执行，不能调用 Superpowers skill 或 dedicated fix sub-agent。直接修复路线必须确认工作区策略，并在代码变更前调用 `phase8-prepare-fix-workspace.sh`：

1. `current`：在当前分支和当前工作区修复。
2. `branch`：在当前仓库创建或切换修复分支。
3. `worktree`：创建独立 worktree 和修复分支。

选择 `branch` 或 `worktree` 时必须收集修复分支名。工作区准备失败时必须停止在代码变更之前。

直接修复仍必须执行以下纪律：

1. 先输出简短修复设计，说明修复意图、影响面、风险边界和验证命令。
2. 优先补充或定位能暴露问题的测试；无法写测试时必须说明原因，并采用最小可验证命令替代。
3. 只修复用户确认的问题，不扩大范围。
4. 验证命令和 `git diff --check` 通过前，不得声称完成。
5. 修复完成后在实际修复工作区执行 `phase9-collect-fix-metadata.sh`，用 `FIX_COMPLETED_AT` 填写修复时间、`FIX_BRANCH` 填写修复分支、`FIX_ACTOR` 填写修复人；这些值不得再次询问用户。
6. 按 `OUTPUT_TARGET` 写回原始问题清单来源，或创建独立修复报告。

---

## Superpowers Flow

Superpowers 路线仅在 `SUPERPOWERS_AVAILABLE=true` 且用户明确选择 `使用 Superpowers 修复` 时执行：

1. 使用 `brainstorming` 梳理确认后的问题清单、修复关键点、影响面、风险边界、验证计划和隔离方式。
2. 由 brainstorming 和后续工作区纪律决定当前分支、新分支或独立 worktree。
3. 具体修复方案交给 Superpowers：brainstorming 根据确认的问题集合形成本次修复设计。
4. 使用 `test-driven-development` 优先补充或定位能暴露问题的测试；无法写测试时必须说明原因，并采用最小可验证命令替代。
5. 使用 `verification-before-completion` 在报告、飞书更新和最终答复前执行完整验证命令。
6. 使用 `subagent-driven-development` 执行 brainstorming 产出的修复计划。
7. 修复完成后在实际修复工作区执行 `phase9-collect-fix-metadata.sh`，用 `FIX_COMPLETED_AT` 填写修复时间、`FIX_BRANCH` 填写修复分支、`FIX_ACTOR` 填写修复人；这些值不得再次询问用户。
8. 按 `OUTPUT_TARGET` 写回原始问题清单来源，或创建独立修复报告。

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

---

## Fix Scope Rules

修复器在修改代码前必须向用户确认：

- 待修复问题确认清单来源
- 解析得到的问题清单表格
- 本次确认修复的问题编号集合
- 修复关键点：修复意图、边界、不修内容和建议验证
- 输出目标：写回原始问题清单来源，或创建独立本地 Markdown、飞书云文档、飞书多维表格修复报告

默认修复顺序为：

1. P0 严重问题
2. P1 重要问题
3. P2 一般问题
4. P3 建议项
5. 待确认项

同一优先级内按依赖关系排序：先修基础设施和公共工具，再修业务调用方；先修测试能覆盖的行为，再修仅能静态验证的清理项。

---

## 状态分类

每个问题最终必须归入以下状态之一：

| 状态 | 使用条件 |
|------|----------|
| 已修复 | 已完成代码或配置修改，并通过对应验证 |
| 部分修复 | 已降低主要风险，但仍有明确剩余工作 |
| 未修复 | 未修改或验证失败 |
| 已忽略 | 用户确认不修或问题不适用于当前目标 |
| 待人工确认 | 缺少上下文、权限、环境或业务判断 |

状态必须有证据支撑，不能只写结论。

---

## Workspace Rules

直接修复路线必须由用户明确确认工作区策略。Superpowers 路线的工作区策略由 Superpowers 设计阶段决定，但仍必须满足以下底线：

- `PROJECT_DIR` 必须存在并包含 Git 仓库
- 当前分支名称、上游信息和工作区状态必须在执行计划中可见
- 用户未确认前不得在当前分支直接修改
- 推荐使用 `codex/fix-*` 分支或独立 worktree 执行修复
- 如果工作区存在未提交修改，直接修复路线只能在用户明确选择当前分支修复后继续；新分支和 worktree 策略必须由 `phase8-prepare-fix-workspace.sh` 阻止脏工作区创建
