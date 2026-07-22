# Runtime Adapter: Codex

> 本文件定义 cc-code-reviewer 在 OpenAI Codex CLI/Desktop 宿主下的运行时映射。
> 共享契约见 `runtime/contract.md`。

## 1. 运行时上下文

| 字段 | Codex 实现 |
|---|---|
| `RUNTIME_ID` | `codex`（当前宿主为 Codex 时固定） |
| `PLUGIN_ROOT` | 从当前已加载 Skill 的真实路径向上解析到插件根目录 |
| `INTERACTION_MODE` | `structured`（能力存在时）/ `sequential-text`（无结构化输入时逐轮单问降级） |
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

Codex 能力存在时使用结构化输入；受限时降级，但不得改变确认状态机：

| 逻辑能力 | Codex 实现 |
|---|---|
| 单选确认 | 平台结构化输入；不可用时逐轮单问 |
| 多选报告目标 | 拆成组合选项或连续单选（Codex 可能无原生多选） |
| 4 个以上选项 | 分级菜单，满足 Codex 2–3 选项上限 |
| 最终执行确认 | 单独一步 |

只有宿主没有结构化输入能力时才允许 `sequential-text`：一次只问一个问题，必须等待响应，不得把多个步骤合并成一段文本。

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
