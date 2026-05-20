# Project Ignore Rules Design

> 日期：2026-05-20
> 状态：Approved

## 背景

扫描报告会反复发现一些项目特有设计，例如公司网关统一鉴权、内部 RPC 接口不按公网 API 标准校验、框架约定导致的静态误判。用户希望在查看扫描清单后，把这类问题沉淀到项目本地 ignore 目录，后续扫描同类问题不再进入问题清单。

## 设计目标

- 新增独立技能 `cc-code-ignore`，用于扫描后从飞书 Base 或本地 Markdown 读取问题清单，并根据用户指定的问题编号生成项目级 ignore 规则。
- ignore 文件面向 AI 读取，也允许人手工修改，格式必须极简。
- ignore 存“代表性问题模式”，不存报告编号；编号只作为从某次清单中选择问题的临时入口。
- scan 阶段读取项目内 `.cc-code-reviewer/ignore/issues.yml`，把规则注入 scan agent；agent 在输出问题前过滤命中的同类问题。
- 报告必须披露 ignore 是否启用、命中规则数和过滤问题数，避免静默吞掉风险。

## 文件格式

默认路径：

```text
{PROJECT_DIR}/.cc-code-reviewer/ignore/issues.yml
```

格式：

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

字段含义：

- `name`：这类问题的简短名称。
- `applies_to`：适用范围，帮助 AI 限定项目位置或技术上下文。
- `skip_when`：给后续扫描 agent 的跳过判断指令。

## 新技能行为

`cc-code-ignore` 的入口参数只需要项目路径。技能先检测项目目录，再询问问题清单来源：飞书 Base 或本地 Markdown。读取问题清单后，用户指定问题编号。技能根据对应问题详情生成一条极简 ignore 规则，展示拟写入内容，并在用户确认后追加到 `issues.yml`。

生成规则时不得把报告编号写入 ignore 文件。编号只用于定位本次报告里的具体问题。

## Scan 集成

`cc-code-reviewer` 在预扫描完成后检查 ignore 文件是否存在；存在则读取内容、注入子 agent。子 agent 在问题归类和报告生成前应用 ignore：

- 语义命中 `skip_when` 的同类问题不输出到 P0/P1/P2/P3/待确认清单。
- 必须统计命中规则数、过滤问题数。
- 报告配置快照和最终汇总中披露 ignore 状态。

## 非目标

- 不做复杂 fingerprint、created_by、reason、审计字段。
- 不在 fix 阶段读取 ignore 文件。
- 不支持全局 ignore；本轮只做项目级 ignore。
