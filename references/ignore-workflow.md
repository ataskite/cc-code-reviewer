# Project Ignore Workflow

本文件定义扫描后沉淀项目级 ignore 规则的工作流。ignore 规则是 **AI 指令型 ignore 文件**，用于告诉后续 scan agent：哪些同类问题在本项目中不要再列入扫描问题清单。

## 目标

- 从飞书 Base 或本地 Markdown 问题清单中读取候选问题。
- 允许用户指定问题编号来选择代表性问题。
- 根据代表性问题生成一条可复用的同类问题忽略规则。
- 写入项目本地 `.cc-code-reviewer/ignore/issues.yml`。

## 核心原则

- ignore 文件不存报告编号；问题编号只用于本次读取问题清单时定位代表问题。
- ignore 文件不记录 reason、created_by、fingerprint 等审计字段。
- ignore 规则面向 AI 后续扫描读取，也允许人手工编辑。
- 每条规则描述一类代表性问题，而不是一次报告中的单个位置。

## 默认路径

```text
{PROJECT_DIR}/.cc-code-reviewer/ignore/issues.yml
```

如果目录不存在，`cc-code-ignore` 技能负责创建：

```text
{PROJECT_DIR}/.cc-code-reviewer/ignore/
```

## YAML 格式

```yaml
version: 1

ignore:
  - name: "Controller 未显式鉴权"
    applies_to:
      - "所有 Controller 接口"
      - "Spring MVC 请求入口"
    skip_when: |
      如果发现的问题是 Controller 方法缺少 @PreAuthorize、@RequiresPermissions、
      权限注解、显式鉴权调用，或类似“接口未做权限校验”的结论，
      后续扫描不要再把这类问题列为扫描问题。
```

字段说明：

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 这类问题的简短名称 |
| `applies_to` | 是 | 适用范围，可写路径、模块、技术栈或接口类型 |
| `skip_when` | 是 | 给 AI 的跳过判断指令 |

## 从飞书 Base 生成规则

当用户选择飞书 Base 来源时，必须通过 `lark-base` / `lark-cli` 读取记录，不得使用脚本假装解析云端数据。

需要读取字段：

- 问题编号
- 严重级别
- 所属维度
- 问题描述
- 位置
- 证据
- 修复建议

用户指定问题编号后，技能读取对应记录，生成 `name`、`applies_to` 和 `skip_when`。生成内容必须是同类问题规则，不得把 `P1-2`、`P2-4` 等编号写入 ignore 文件。

## 从本地 Markdown 生成规则

当用户选择本地 Markdown 来源时，直接读取 Markdown 文件内容，解析用户指定的问题编号对应段落。

支持的问题编号格式包括：

- `P0-N`
- `P1-N`
- `P2-N`
- `P3-N`
- `待确认-N`

解析到代表性问题后，技能生成 `name`、`applies_to` 和 `skip_when`。如果无法从段落中确定适用范围，使用问题位置中的目录或文件模式作为 `applies_to`。

## 写入规则

写入前展示拟追加的 YAML 片段，并要求用户确认。

写入时：

- 如果文件不存在，创建 `version: 1` 和空 `ignore` 列表后追加。
- 如果文件存在，只追加新规则，不重排已有规则。
- 如果 `name` 与已有规则重复，提示用户确认是否仍然追加。
- 不删除或改写用户手工维护的已有规则。

## Scan 阶段读取

`cc-code-reviewer` 在启动 scan agent 前读取 `.cc-code-reviewer/ignore/issues.yml`。读取成功后注入：

- `IGNORE_RULES_PATH`
- `IGNORE_RULES_CONTENT`

scan agent 必须在生成问题清单前，先应用项目 ignore 规则。凡是语义上命中 `ignore.skip_when` 的同类问题，不得输出到 P0/P1/P2/P3/待确认清单。

报告必须披露：

```text
项目 ignore：已启用（命中 2 条规则，过滤 7 个同类问题）
```
