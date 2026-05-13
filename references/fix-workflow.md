# Fix Workflow

本文件定义 `cc-code-fixer` 的修复阶段工作流。修复器只消费已有审查报告、飞书问题清单或人工整理后的 Fix TODO List，不重新执行完整代码审查。

修复阶段的核心规则：**交互确认是硬门禁**。scan 可以自动化，fix 必须由用户确认待修复问题清单、修复关键点、模型 / effort 和输出目标后才能进入 Superpowers 与子 agent 执行。

---

## Fix Input Normalization

`cc-code-fixer` 入口只接收项目地址。待修复问题确认清单必须在项目预检测之后通过 AskUserQuestion 收集。

归一化结果至少包含：

| 字段 | 说明 |
|------|------|
| `FIX_INPUT_TYPE` | `local-markdown`、`feishu-doc`、`feishu-base` 或 `feishu-base-token` |
| `FIX_INPUT_SOURCE` | 用户在 AskUserQuestion 中提供的路径、URL 或 token 表达式 |
| `PROJECT_DIR` | 待修复项目路径，必须是本地可访问目录 |
| `ISSUE_SOURCE_SUMMARY` | 从报告或表格中提取的问题总数、优先级分布和来源说明 |
| `NORMALIZED_ISSUES` | 归一化后的完整问题清单 |
| `CONFIRMED_ISSUE_IDS` | 用户确认纳入本轮修复的问题编号 |
| `MODEL_PREFERENCE` | 用户确认的模型偏好 |
| `EFFORT_PREFERENCE` | 用户确认的 effort 偏好 |
| `OUTPUT_TARGET` | `local-markdown`、`feishu-doc`、`feishu-base` 或组合输出 |

### 本地 Markdown 报告

本地报告必须满足：

- 文件存在且扩展名为 `.md`
- 内容包含可识别的问题编号、位置、问题描述和修复建议
- 相对路径必须基于当前工作目录解析为绝对路径
- 如果报告格式不完整，修复器只能提取可确认的问题，并把其余项列入「未修复问题」或「待人工确认」

### 飞书云文档

飞书云文档输入必须先通过 `lark-cli docs` 读取文档内容，再按 Markdown 报告规则解析。读取失败时不得继续假装拥有完整问题上下文，应进入 degraded mode，并要求用户改用本地 Markdown 或飞书多维表格来源。

### 飞书多维表格

飞书 Base 输入必须解析出 `base_token` 与 `table_id`。如果 URL 无法稳定提取表 ID，必须要求用户补充 `base:{BASE_TOKEN}:{TABLE_ID}` 格式。读取记录时只处理具备「问题编号」「位置」「问题描述」「修复建议」「修复状态」字段的数据行。

---

## Preflight Sequence

代码变更前必须完成以下预检，预检失败时不得修改代码：

1. 解析项目地址，形成 `PROJECT_DIR` 与 `PROJECT_SOURCE`。
2. 检查 `PROJECT_DIR` 是否存在、是否为 Git 仓库、当前分支和工作区状态。
3. 扫描项目结构、模块、技术栈和默认验证命令线索。
4. 检测 lark-cli 与 Superpowers 可用性。
5. 通过 AskUserQuestion 收集待修复问题确认清单来源。
6. 读取本地 Markdown、飞书云文档或飞书多维表格，提取可确认的问题编号、位置、问题描述和修复建议。
7. 展示问题清单表格，获得用户对本轮修复问题集合的确认。
8. 展示修复关键点，获得用户确认。
9. 获得模型 / effort 和输出目标确认。
10. 输出最终执行计划并获得确认。

飞书云文档或飞书多维表格读取失败时，如果没有来自本地 Markdown、已确认缓存或其他可信来源的已归一化问题上下文，必须停止在代码变更之前，只生成本地失败报告。无已归一化问题上下文时必须停止修复。

---

## Superpowers Flow

修复器执行代码变更前必须按 Superpowers 风格组织工作：

1. 使用 `brainstorming` 梳理确认后的问题清单、修复关键点、影响面、风险边界、验证计划和隔离方式。
2. 工作区策略交给 Superpowers：由 brainstorming 和后续工作区纪律决定当前分支、新分支或独立 worktree。`cc-code-fixer` 的 AskUserQuestion 不再单独选择工作区策略。
3. 具体修复方案交给 Superpowers：不再由主 skill 预设档位。brainstorming 根据确认的问题集合形成本次修复设计。
4. 使用 `test-driven-development` 优先补充或定位能暴露问题的测试；无法写测试时必须说明原因，并采用最小可验证命令替代。
5. 使用 `verification-before-completion` 在报告、飞书更新和最终答复前执行完整验证命令。

如果某个 Superpowers skill 不可用，修复器不得跳过相应纪律；必须在 degraded mode 中记录缺失项，并用等价的显式步骤完成：先提出修复思路，再写或定位验证，再运行验证命令。

---

## Degraded Mode

进入 degraded mode 的典型条件：

- 飞书读取或更新失败
- Superpowers skill 检测不完整
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
- 模型 / effort 偏好
- 输出目标：仅本地报告、创建飞书云文档、更新飞书多维表格或组合输出

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

工作区策略交给 Superpowers 后仍必须满足以下底线：

- `PROJECT_DIR` 必须存在并包含 Git 仓库
- 当前分支名称、上游信息和工作区状态必须在执行计划中可见
- 用户未确认前不得在当前分支直接修改
- 推荐使用 `codex/fix-*` 分支或独立 worktree 执行修复
- 如果工作区存在未提交修改，修复器只能在 Superpowers 设计明确处理隔离方式后继续；否则应停止并说明未修改任何文件
