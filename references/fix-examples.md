# Fix Examples

本文件给出 `cc-code-fixer` 的典型使用示例。修复阶段必须交互确认。

---

## 本地 Markdown 报告

场景：用户已经把 scan 阶段报告整理成人工确认过的本地 Markdown Fix TODO List，希望对项目执行修复。

```text
用户：/cc-code-reviewer:cc-code-fixer /path/to/project

修复器：
🧭 修复项目预检测完成
- 项目：/path/to/project
- 当前分支：main
- lark-cli：可用
- Superpowers：可用

问题清单位置：
请在 Other/free-form 中粘贴本地 Markdown 路径、飞书云文档 URL、飞书多维表格 URL 或 base:{BASE_TOKEN}:{TABLE_ID}
[粘贴路径或链接] [取消]

用户：/path/to/project/fix-todo-confirmed.md

修复器：
根据输入动态识别为本地 Markdown，开始解析确认清单。
```

修复器解析后必须展示待修复问题确认清单表格：

```text
| 问题ID | 严重级别 | 维度 | 问题摘要 | 修复建议 |
|--------|----------|------|----------|----------|
| P0-1 | P0 | 安全 | 接口缺少鉴权 | 增加权限校验和测试 |
| P1-1 | P1 | 正确性 | 空值路径 NPE | 补充空值保护测试 |
```

随后确认：

```text
请确认本次要纳入修复的问题：
[确认全部纳入修复] [只修 P0/P1] [按问题编号自定义] [取消]

用户：确认全部纳入修复

修复器：
🎯 修复关键点

| 问题ID | 修复意图 | 边界 | 不修内容 | 建议验证 |
|--------|----------|------|----------|----------|
| P0-1 | 阻断未授权访问 | 只改目标接口和直接权限测试 | 不重构权限框架 | mvn -Dtest=UserControllerTest test |
| P1-1 | 消除空值异常 | 只改订单读取路径 | 不改变订单状态流转 | mvn -Dtest=OrderServiceTest test |

请确认以上修复关键点是否符合预期：
[确认] [调整问题清单] [取消]

用户：确认

请选择修复结果输出目标：
[写回原始本地 Markdown] [创建独立本地 Markdown 修复报告] [创建独立飞书云文档修复报告] [创建独立飞书多维表格修复报告]

用户：创建独立本地 Markdown 修复报告

请选择本次修复的执行方式：
[直接开始修复] [使用 Superpowers 修复] [取消]

用户：直接开始修复

请选择直接修复使用的工作区策略：
[当前分支修复] [创建新分支修复] [创建 worktree 修复] [取消]

用户：创建新分支修复

修复分支：
请在 Other/free-form 中粘贴修复分支名，例如 fix/review-confirmed-issues

用户：fix/review-confirmed-issues
```

最终确认后，直接修复路线由主 skill 调用 `phase8-prepare-fix-workspace.sh` 准备工作区，然后执行修复、测试、验证和输出目标处理。若选择 `使用 Superpowers 修复`，则从 `brainstorming` 开始，并由 `subagent-driven-development` 调度修复。

完成后输出：

```text
修复完成摘要：
- 已修复：2 个
- 待人工确认：0 个
- 修复分支：codex/fix-confirmed-issues
- 本地报告：/path/to/project/fix-report-demo-20260507-153000.md
- 验证：相关测试通过；git diff --check 通过
```

---

## 飞书多维表格

场景：scan 阶段已把问题写入飞书多维表格，用户先人工筛选了要修复的记录，再用表格作为待修复问题确认清单。

```text
用户：/cc-code-reviewer:cc-code-fixer /path/to/project

修复器：
问题清单位置：
请在 Other/free-form 中粘贴本地 Markdown 路径、飞书云文档 URL、飞书多维表格 URL 或 base:{BASE_TOKEN}:{TABLE_ID}
[粘贴路径或链接] [取消]

用户：base:BASE123:tbl456

修复器：
根据输入动态识别为飞书多维表格，使用 lark-base 读取确认清单。
```

读取后展示：

```text
| 问题ID | 严重级别 | 维度 | 问题摘要 | 修复建议 |
|--------|----------|------|----------|----------|
| P0-2 | P0 | 数据库/数据访问 | 事务边界不足 | 纳入同一事务并测回滚 |
```

确认输出目标时，只展示一个与原始输入对应的写回选项；这里因为输入是飞书多维表格，所以原始来源选项是写回原始飞书多维表格：

```text
请选择修复结果输出目标：
[写回原始飞书多维表格] [创建独立本地 Markdown 修复报告] [创建独立飞书云文档修复报告] [创建独立飞书多维表格修复报告]

用户：写回原始飞书多维表格

请选择本次修复的执行方式：
[直接开始修复] [使用 Superpowers 修复] [取消]

用户：使用 Superpowers 修复
```

写回命令示例：

```bash
lark-cli base +record-upsert \
  --base-token "BASE123" \
  --table-id "tbl456" \
  --record-id "rec789" \
  --json '{"fields":{"修复状态":"已修复","修复时间":"2026-05-07 16:00:00 +0800","修复分支":"codex/fix-p0-issues","修复人":"Fix User <fixer@example.com>","备注":"本地报告: fix-report-demo-20260507-160000.md；验证: mvn test 通过"}}'
```

如果飞书更新失败：

```text
代码修复和本地验证已执行，但飞书写回失败。
- 失败命令：lark-cli base +record-upsert --record-id ...
- 回退结果：已生成本地 Markdown 报告
- 建议：确认 Base 权限后按报告中的记录 ID 手动同步
```
