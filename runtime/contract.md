# Runtime Contract (Platform-Neutral)

> 本文件定义 cc-code-reviewer 在 Claude Code / Codex / ZCode 三端共享的运行时契约。
> 共享 Skill、Agent Prompt 和脚本只依赖本契约定义的逻辑变量，不直接依赖任何平台的工具名、环境变量或模型 ID。
>
> 各平台适配器见 `runtime/claude-code.md`、`runtime/codex.md`、`runtime/zcode.md`。

## 1. 运行时上下文

共享流程在执行预扫描前必须解析出以下上下文字段。任一字段缺失都必须在预扫描前失败，不得部分执行。

| 字段 | 含义 | 取值约束 |
|---|---|---|
| `RUNTIME_ID` | 宿主平台标识，由入口固定，不自动猜测 | `claude-code` / `codex` / `zcode` |
| `PLUGIN_ROOT` | 当前插件实际根目录的绝对路径 | 必须可读；支持空格、符号链接、Marketplace 缓存目录 |
| `INTERACTION_MODE` | 人工确认呈现方式 | `structured`（结构化提问） / `sequential-text`（逐轮单问降级） |
| `AGENT_DISPATCH_MODE` | 子 Agent 调度方式 | `native-agent`（插件原生 Agent） / `generic-subagent`（通用 subagent + Prompt 注入） |
| `MODEL_PROFILE` | 模型档位，默认继承宿主 | `inherit` / `economy` / `balanced` / `maximum` |
| `OPTIONAL_CAPABILITIES` | 可选能力集合 | lark-cli、Superpowers 等；缺失只能影响对应可选路径 |

## 2. 插件根目录解析（PLUGIN_ROOT）

`PLUGIN_ROOT` 是逻辑变量，不要求三个平台暴露同名环境变量：

- 三端原生清单都发现根 `skills/`。每个 Skill 根据自身资源位置和固定相对层级 `../..` 解析插件根目录；相对层级是资源契约，不在 shell 中执行 `$0`。
- `RUNTIME_ID` 来自当前宿主身份，并选择同名 adapter；不得通过已安装目录、命令是否存在或当前工作目录猜测。宿主身份不明确时在预扫描前失败。
- 解析完成后，共享 Skill、Agent Prompt 和脚本只使用 `${PLUGIN_ROOT}`。
- 不得使用当前工作目录推断插件根目录。
- 解析必须支持路径空格、符号链接和 Git Marketplace 缓存目录，并同时校验 `VERSION`、核心脚本与当前 Skill。
- 未解析出可读插件根目录时必须在预扫描前失败，不得部分执行。

## 3. 人工确认状态机

共享流程规定的是确认状态机，不是某个工具调用：

```text
preflight
  -> preflight_summary
  -> review_mode
  -> report_targets
  -> review_entry
  -> review_scope
  -> current_scope_sizing
  -> optional_batch_strategy
  -> model_profile
  -> optional_batch_count
  -> optional_concurrency
  -> final_confirmation
  -> execution
```

不变量（三端都必须保持）：

- `preflight` 完成前不提问。
- `preflight_summary` 只输出一次，且必须在第一个问题之前。
- 每个状态等待用户响应后才能进入下一状态。
- `current_scope_sizing` 必须按已确认的 `review_scope` 重算文件数和行数；只有当前范围达到门槛时才允许进入 `optional_batch_strategy`。
- 小型 Maven 多模块存量审查跳过 `optional_batch_strategy`，保持 `single-agent`；全量审查不得显示“所选模块”文案。
- 不允许通过用户输入中的命令行式参数绕过状态。
- `final_confirmation` 必须独立存在。
- fix 只执行确认后的问题集合。

共享流程统一使用逻辑动作 `INTERACT`。各入口必须把 `INTERACT` 映射为宿主可用的结构化输入；不可用时才逐轮单问。适配器可以改变交互呈现，但不得改变已确认范围、默认值或跳过最终确认。

## 4. 模型档位

`REVIEW_MODE` 与 `MODEL_PROFILE` 分离：

- `REVIEW_MODE=fast|standard|deep|security` 决定审查维度和输出门槛，保持现状。
- `MODEL_PROFILE=inherit|economy|balanced|maximum` 只决定宿主模型/推理强度，默认 `inherit`。
- 共享流程不得出现强制 `sonnet`、`opus`、`haiku` 或特定 Codex/ZCode 模型 ID。
- 具体模型映射只存在于各平台适配器，允许随平台版本更新而不改审查契约。
- fast 模式"仅输出 P0"的语义不因模型档位改变。

## 5. 子 Agent 调度

- 共享 `agents/*.md` 只保留角色、输入、边界和输出契约，不绑定平台专属 frontmatter。
- `DISPATCH_AGENT` 输入统一：项目、语言、审查类型、审查范围、预扫描结果、ignore 规则、`agent_prompt` 路径、review framework 路径、source manifest 或 batch scan roots、batch plan/status/result 路径、semantic level、model profile。
- 子 Agent 不与用户交互、不上传飞书、不扩展正式扫描范围。
- 三个平台的 batch agent 都必须写当前批次 status/result 文件，主流程统一调用现有 merge/status 脚本。
- 平台没有可用 subagent 时，必须在最终确认前说明降级为串行或阻塞，不得静默改变并发计划或让主 Skill 接管实际审查。

## 6. 失败与降级语义

| 场景 | 行为 |
|---|---|
| 插件根目录无法解析 | 预扫描前失败，给出宿主与 Skill 路径 |
| 宿主没有结构化提问工具 | 逐轮单问降级（`sequential-text`），不能跳步 |
| 宿主没有 subagent | 最终确认前阻塞，不由主 Skill 接管审查 |
| 并发能力不足 | 展示实际并发数，用户重新确认后串行/低并发执行 |
| lark-cli 不可用 | 仅禁用飞书输出，本地报告继续 |
| Superpowers 不可用 | fix 只展示直接修复路线 |

降级不得改变正式扫描文件集合、问题严重级别或修复范围。
