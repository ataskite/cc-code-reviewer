# Runtime Adapter: Codex

> 本文件定义 cc-code-reviewer 在 OpenAI Codex CLI/Desktop 宿主下的运行时映射。
> 共享契约见 `runtime/contract.md`。

## 1. 运行时上下文

| 字段 | Codex 实现 |
|---|---|
| `RUNTIME_ID` | `codex`（当前宿主为 Codex 时固定） |
| `PLUGIN_ROOT` | 从当前已加载 Skill 的真实路径向上解析到插件根目录 |
| `INTERACTION_MODE` | `structured`（必须调用原生选项工具；不可用时阻塞，禁止文本降级） |
| `AGENT_DISPATCH_MODE` | `generic-subagent` —— 主 Skill 读取共享 `agents/*.md` 正文，注入参数后派发通用 subagent；不写入 `~/.codex/agents` |
| `MODEL_PROFILE` | 映射到当前 Codex 模型及 reasoning effort；`inherit` 时继承会话模型 |

## 2. 插件根目录解析

Codex 通过 `.codex-plugin/plugin.json` 的 `skills: "./skills/"` 加载根共享 Skill。入口文件位于：

```text
${PLUGIN_ROOT}/skills/<skill>/SKILL.md
```

Codex 读取 Skill 资源时以该 `SKILL.md` 所在目录为相对资源基准；共享 Skill 将固定相对层级 `../..` 解析为 `PLUGIN_ROOT`。这是资源解析规则，不是可复制执行的 shell `$0` 代码。解析后必须同时校验 `VERSION`、`scripts/core/detect-project.sh` 和当前共享 Skill；不得仅以某个同名 `scripts/` 目录存在作为成功条件。

解析必须支持路径空格、符号链接和 Marketplace 缓存目录。不使用当前工作目录推断。

## 3. 人工确认映射

`INTERACT` 必须映射为当前会话实际暴露且允许使用的原生工具调用。以下规则适用于 scan、fix 和 ignore 三个入口；不得仅在消息中打印工具名或选项来模拟调用。

### 工具选择与可用性

1. 优先使用 `request_user_input_async`（例如当前宿主暴露为 `functions.request_user_input_async`）。它展示可点击选项，并通过后续用户消息异步返回回答。
2. 异步工具不可用或不允许用于当前步骤时，仅在当前模式和用途均获宿主允许时使用 `request_user_input`（例如 `functions.request_user_input`）。若工具声明仅限 Plan 模式，普通模式下即使能看到工具也不得调用；不得自行宣称或切换为 Plan 模式来绕过限制。
3. 工具名、参数和使用条件以当前会话提供的 schema 与宿主指令为准，不能假设所有 Codex CLI/Desktop 版本都提供相同能力。不得通过 shell、MCP 或 App Server RPC 伪造内置提问调用。
4. 两者均不可用或不允许用于当前步骤时，说明当前宿主/模式与受限步骤，提示在提供原生选项工具的会话中继续，然后阻塞该步骤。禁止文本降级，不输出“回复 1/2/3”菜单，也不得自动采用默认值继续。

执行计划确认也受工具用途限制约束。宿主若禁止某工具用于权限/审批请求，不得用它收集这类批准；使用宿主允许的原生机制，没有可用机制时按上述规则说明阻塞，不得将审批伪装成偏好问题。

### 选项映射

| 逻辑能力 | Codex 实现 |
|---|---|
| 单选确认 | 一次调用一个问题；按所选工具 schema 转换标题、选项和说明 |
| 多选报告目标 | 无原生多选时按原选项顺序连续单选，每个目标问“选择 / 不选择”；累积选择后统一回显，保留任意组合与原流程的默认值、必选约束 |
| 选项超出工具上限 | 分级菜单，保留全部叶子选项；`request_user_input` 声明 2–3 个选项时遵守该限制，不把此上限套用到其他工具 |
| 自定义路径或业务背景 | 使用工具自带的自由输入；支持纯输入问题时可省略 options，不虚构 Other 选项 |
| 最终执行确认 | 展示完整执行计划后单独调用，收到明确回答后才执行 |

共享 Skill 示例中的 `header`、`description`、`multiSelect` 是逻辑配置，不得原样复制到不支持这些字段的 Codex 工具中。选项说明在没有独立 description 字段时合入选项字符串；保留 fast“仅输出 P0”等关键语义。

下面是常见 schema 的参数示例；调用前仍须核对当前工具定义。示例仅展示“审查入口”一个步骤。

`request_user_input_async`：

```json
{
  "questions": [{
    "title": "请选择本次审查入口",
    "options": ["增量审查：审查所选提交", "全量审查：审查全部生产代码", "指定模块：选择审查范围"]
  }]
}
```

`request_user_input`（仅在当前模式和用途允许时）：

```json
{
  "questions": [{
    "id": "review_entry",
    "header": "审查入口",
    "question": "请选择本次审查入口",
    "options": [
      {"label": "增量审查 (Recommended)", "description": "审查所选提交"},
      {"label": "全量审查", "description": "审查全部生产代码"},
      {"label": "指定模块", "description": "选择审查范围"}
    ]
  }]
}
```

### 回答与状态推进

- 每次只保留一个待回答步骤，记录该步骤、展示的选项及已确认配置。
- 异步调用返回不代表用户已回答；预选项不代表确认。调用后让出当前轮次等待用户回复，不得提前进入下一交互步骤、派发审查或开始修复/写入。
- 同步工具从返回结果读取回答；异步工具从后续用户消息读取回答。按当前待回答步骤解析所选项或自定义文本，校验后才推进状态。无回答、空回答、超时或工具错误都不构成确认。
- 收到无关消息或不明确回答时先回应用户，并保留待回答步骤；需要澄清时继续使用原生工具。用户取消则停止流程，用户更改先前配置则回到受影响步骤并更新最终执行计划。
- 格式错误按实际 schema 修正；调用失败且确认没有仍待回答的请求时，才可重新选择另一个允许使用的工具。不得同时发出两个等价问题或用默认选择掩盖失败。

## 4. 模型映射

| 档位 | 说明 |
|---|---|
| `inherit` | 继承当前会话模型（默认） |
| `economy` | 低成本快速审查（低 reasoning effort） |
| `balanced` | 标准审查 |
| `maximum` | 深度/安全审查（高 reasoning effort） |

共享流程不硬编码特定 Codex 模型 ID。

## 5. 子 Agent 调度

Codex 使用共享 Prompt 注入的通用 subagent：

- 主 Skill 读取对应 `agents/*.md` 正文（Java / 前端 / Python），注入审查参数表后派发通用 subagent。
- 不要求写入用户的 `~/.codex/agents`。
- batch：主 Skill 按 batch plan 分发并行通用 subagent；每个 subagent 必须写当前批次 status/result 文件。
- 子 Agent 不与用户交互、不上传飞书；主 Skill 统一调用 merge/status 脚本和飞书上传。
- 平台没有可用 subagent 时，scan 在最终确认前报告阻塞，不得让主 Skill 静默接管实际审查。

## 6. IDE Extension 支持

Codex 官方当前插件入口以 CLI/Desktop 为准。IDE Extension 场景仅提供项目级 Skill 降级说明，不承诺 IDE 插件安装。
