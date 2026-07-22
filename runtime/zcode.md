# Runtime Adapter: ZCode

> 本文件定义 cc-code-reviewer 在智谱 ZCode 宿主下的运行时映射。
> 共享契约见 `runtime/contract.md`。
>
> ZCode 插件体系仍为 Beta；Git 自定义 Marketplace 是 1.5.0 的正式分发路径。

## 1. 运行时上下文

| 字段 | ZCode 实现 |
|---|---|
| `RUNTIME_ID` | `zcode`（当前宿主为 ZCode 时固定） |
| `PLUGIN_ROOT` | 从当前已加载 Skill 的真实路径向上解析到插件根目录 |
| `INTERACTION_MODE` | `structured`（优先原生结构化输入）/ `sequential-text`（不可用时逐轮单问降级） |
| `AGENT_DISPATCH_MODE` | `generic-subagent` —— 读取共享 Agent Prompt 后派发宿主 subagent，不依赖未验证的 manifest agent 注册字段 |
| `MODEL_PROFILE` | 映射到 ZCode 暴露的模型；`inherit` 时继承会话模型 |

## 2. 插件根目录解析

ZCode 通过 `.zcode-plugin/plugin.json` 的 `skills: "skills"` 加载根共享 Skill。入口文件位于：

```text
${PLUGIN_ROOT}/skills/<skill>/SKILL.md
```

ZCode 读取 Skill 资源时以该 `SKILL.md` 所在目录为相对资源基准；共享 Skill 将固定相对层级 `../..` 解析为 `PLUGIN_ROOT`。这是资源解析规则，不是可复制执行的 shell `$0` 代码。解析后必须同时校验 `VERSION`、`scripts/core/detect-project.sh` 和当前共享 Skill；不得仅以某个同名 `scripts/` 目录存在作为成功条件。

解析必须支持路径空格、符号链接和 Marketplace 缓存目录。不使用当前工作目录推断。ZCode 当前能兼容读取 Claude/Codex 清单是加分项，但不作为架构依赖；必须提供原生 `.zcode-plugin/plugin.json`。

## 3. 人工确认映射

| 逻辑能力 | ZCode 实现 |
|---|---|
| 单选确认 | 平台原生结构化输入；不可用时逐轮单问 |
| 多选报告目标 | 平台原生多选；不可用时连续单选 |
| 4 个以上选项 | 原样或分级菜单 |
| 最终执行确认 | 单独一步 |

缺少结构化输入能力时与 Codex 使用相同的逐轮单问降级：一次只问一个问题，必须等待响应，不得合并步骤。

## 4. 模型映射

| 档位 | 说明 |
|---|---|
| `inherit` | 继承当前会话模型（默认） |
| `economy` | 低成本快速审查 |
| `balanced` | 标准审查 |
| `maximum` | 深度/安全审查 |

共享流程不硬编码特定 ZCode 模型 ID。

## 5. 子 Agent 调度

- 主 Skill 读取同一 `agents/*.md` 正文，注入参数后派发通用 subagent（与 Codex 方式一致）。
- `.zcode-plugin/plugin.json` 当前只声明官方文档明确支持的 Skill 路径；不虚构未验证的 `agents` manifest 字段。
- batch：主 Skill 按 batch plan 分发并行 subagent；每个 subagent 必须写当前批次 status/result 文件。
- 子 Agent 不与用户交互、不上传飞书；主 Skill 统一调用 merge/status 脚本和飞书上传。
- 平台没有可用 subagent 时，scan 在最终确认前报告阻塞，不得让主 Skill 静默接管实际审查。
