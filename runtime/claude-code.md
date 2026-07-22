# Runtime Adapter: Claude Code

> 本文件定义 cc-code-reviewer 在 Claude Code 宿主下的运行时映射。
> 共享契约见 `runtime/contract.md`。

## 1. 运行时上下文

| 字段 | Claude Code 实现 |
|---|---|
| `RUNTIME_ID` | `claude-code`（入口固定，由插件清单与 Skill 安装路径确定） |
| `PLUGIN_ROOT` | 从当前根 `skills/` 下的 Skill 资源位置向上两级解析；可与宿主注入路径交叉校验 |
| `INTERACTION_MODE` | `structured` —— 使用 `AskUserQuestion` 工具 |
| `AGENT_DISPATCH_MODE` | `native-agent` —— 通过插件 Agent 类型调用 |
| `MODEL_PROFILE` | 映射到当前可用的 Claude 模型；`inherit` 时继承会话模型 |

## 2. 插件根目录解析

Claude Code 原生清单发现根 `skills/`。共享流程以当前 Skill 资源目录为基准向上两级解析 `${PLUGIN_ROOT}`；如宿主同时注入插件根路径，只用于交叉校验，不作为共享流程依赖：

```bash
[ -d "${PLUGIN_ROOT}/scripts" ] || { echo "PLUGIN_ROOT 不可读: ${PLUGIN_ROOT}"; exit 1; }
[ -f "${PLUGIN_ROOT}/VERSION" ] || { echo "VERSION 不可读: ${PLUGIN_ROOT}"; exit 1; }
```

## 3. 人工确认映射

Claude Code 继续严格使用 `AskUserQuestion`，保持现有 multiSelect 规则：

| 逻辑能力 | Claude Code 实现 |
|---|---|
| 单选确认 | `AskUserQuestion`，`multiSelect: false` |
| 多选报告目标 | `AskUserQuestion`，`multiSelect: true` |
| 4 个以上选项 | 原样展示（Claude Code 无选项上限） |
| 最终执行确认 | 单独一步 `AskUserQuestion` |

现有交互契约完全保留：预扫描先于交互、摘要先于问题、每步等待、最终单独确认。

## 4. 模型映射

`MODEL_PROFILE` 映射（允许随平台版本更新）：

| 档位 | 说明 |
|---|---|
| `inherit` | 继承当前会话模型（默认） |
| `economy` | 使用当前可用的低成本模型档位 |
| `balanced` | 标准审查 |
| `maximum` | 使用当前可用的最高能力模型档位 |

共享流程不硬编码 `sonnet`/`opus`/`haiku`；具体模型选择由适配器根据当前可用模型决定。

## 5. 子 Agent 调度

Claude Code 把共享逻辑动作 `DISPATCH_AGENT` 映射为插件 Agent 类型调用：

- scan：`cc-code-reviewer:cc-code-reviewer`（Java）、`cc-code-reviewer:cc-code-reviewer-frontend`（前端）、`cc-code-reviewer:cc-code-reviewer-python`（Python），由 `LANGUAGE_ID` 选择。
- batch：主 Skill 读取 `agents/*.md`，按 batch plan 分发并行插件 Agent。
- 子 Agent 不上传飞书；主 Skill 统一调用 merge/status 脚本和飞书上传。
