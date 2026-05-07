# 代码修复示例

本文件给出 `cc-code-fixer` 的典型使用示例，覆盖本地报告、飞书多维表格、快速启动和参数校验失败。

---

## 示例一：本地 Markdown 报告

场景：用户已经通过 `cc-code-reviewer` 生成本地审查报告，希望修复 P0 和 P1 问题，并输出本地修复报告。

```text
用户：根据本地 Markdown 报告修复 /path/to/project/code-review-report-demo-20260507-103000.md，只修 P0 和 P1

修复器：
已识别修复输入：
- 类型：本地 Markdown 报告
- 报告路径：/path/to/project/code-review-report-demo-20260507-103000.md
- 问题数量：P0 1 个，P1 3 个，P2 4 个
- 项目路径：/path/to/project

请选择工作区策略：
[创建新分支 codex/fix-review-issues] [使用当前分支] [取消]

用户：创建新分支

修复器：
修复计划：
- 修复范围：P0,P1
- 工作区策略：创建新分支 codex/fix-review-issues
- 验证命令：mvn test, git diff --check
- 输出目标：本地 Markdown 报告

确认执行？
[确认执行] [取消]
```

完成后输出：

```text
修复完成摘要：
- 已修复：4 个
- 未修复：0 个
- 修复分支：codex/fix-review-issues
- 本地报告：/path/to/project/code-fix-report-demo-20260507-153000.md
- 验证：mvn test 通过；git diff --check 通过
```

---

## 示例二：飞书多维表格

场景：审查结果已经进入飞书多维表格，用户希望修复所有 `待修复` 的 P0 问题，并写回状态。

```text
用户：修复这个飞书多维表格里的 P0 待修复问题 base:BASE123:tbl456，项目在 /path/to/project

修复器：
已识别修复输入：
- 类型：飞书多维表格
- Base Token：BASE123
- Table ID：tbl456
- 已读取记录：18 条
- 本次候选：P0 待修复 2 条

将写回字段：
- 修复状态
- 修复时间
- 修复分支
- 备注

确认执行？
[确认执行] [取消]
```

完成后输出：

```text
修复完成摘要：
- 已修复：2 个
- 飞书多维表格：已更新 2 条记录
- 修复状态：已修复
- 修复分支：codex/fix-p0-issues
- 本地报告：/path/to/project/code-fix-report-demo-20260507-160000.md
```

如果飞书更新失败：

```text
代码修复和本地验证已执行，但飞书写回失败。
- 失败命令：lark-cli base +record-update ...
- 回退结果：已生成本地 Markdown 报告
- 建议：确认 Base 权限后按报告中的记录 ID 手动同步
```

---

## 示例三：快速启动模式

场景：用户明确提供所有必要参数，不需要交互确认。

```bash
/cc-code-reviewer:cc-code-fixer \
  --input=/path/to/project/code-review-report-demo-20260507-103000.md \
  --project=/path/to/project \
  --scope=P0,P1 \
  --workspace=new-branch \
  --branch=codex/fix-review-issues \
  --output=local-markdown \
  --verify="mvn test"
```

快速启动必须：

- 一次性解析完整参数表
- 校验 `--input`、`--project`、`--scope`、`--workspace`、`--output`
- 校验枚举值是否合法
- 校验本地输入文件和项目目录是否存在
- 校验失败时直接退出，不进入交互式模式

成功时输出：

```text
快速启动参数已通过校验：
- 输入：本地 Markdown 报告
- 项目：/path/to/project
- 范围：P0,P1
- 分支：codex/fix-review-issues
- 输出：本地 Markdown 报告

开始执行修复。
```

---

## 示例四：快速启动参数校验失败

场景：用户缺少必填参数或传入非法枚举值。

```bash
/cc-code-reviewer:cc-code-fixer \
  --input=/path/to/report.md \
  --scope=P0 \
  --workspace=magic \
  --output=base
```

必须失败输出：

```text
快速启动参数校验失败：
- 缺少必填参数：--project
- 非法参数值：--workspace=magic，可选值为 current-branch,new-branch,worktree
- 非法参数值：--output=base，可选值为 local-markdown,feishu-doc,feishu-base,both

已停止执行。快速启动模式禁止降级为交互式模式。
```

失败时不得：

- 修改代码
- 创建分支
- 读取或更新飞书数据
- 生成误导性的修复报告

