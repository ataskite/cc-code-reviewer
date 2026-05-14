# Fix Feishu Integration

本文件定义 `cc-code-fixer` 使用 `lark-cli` 读取审查结果、写回原始问题清单、创建独立修复报告和降级回退的规则。所有飞书操作均通过 `lark-cli` 完成，禁止使用旧版 `feishu_create_doc` 或 `feishu_bitable_*` 工具。不得使用 Python 脚本读取飞书云文档或飞书多维表格。

---

## 读取飞书云文档

适用输入：`https://.../docx/...` 或 `https://.../docs/...`

必须使用 `lark-cli docs` 和 `lark-doc` skill 读取云文档内容。

- 飞书操作失败不得阻塞本地修复报告生成。
- 写操作前必须先读，确认目标文档或表格存在。
- 多维表格更新必须按问题编号或记录 ID 精确定位，不允许批量覆盖整表。
- 修复状态、修复时间、修复分支、修复人必须与本地报告保持一致。
- 如果飞书不可用，进入 degraded mode，并在本地报告「飞书回写结果」中记录失败原因。
- 只有用户在输出目标中选择写回原始飞书来源时，才能修改原始飞书云文档或原始飞书多维表格。
- 用户选择独立修复报告时，不得修改原始飞书问题清单。

### 读取命令

```bash
lark-cli docs +fetch --api-version v2 --doc "{DOC_URL}" --doc-format markdown
```

如果 CLI 只返回文档 token，应先提取 token，再使用对应读取命令。读取结果必须保存为临时 Markdown，用于后续问题解析和最终审计。

### 读取失败处理

读取失败时：

1. 如果没有来自其他确认来源或缓存的已归一化问题上下文，不执行代码修复。
2. 输出失败命令和错误摘要。
3. 提示用户改用本地 Markdown 报告或飞书多维表格。
4. 只生成本地失败报告，记录飞书读取失败原因。
5. 如果已经有可用且用户确认的本地缓存，可继续执行代码修复，并在报告中说明上下文来源。

无已归一化问题上下文时必须停止修复。读取失败不得被当成普通写回失败处理。

---

## 读取飞书多维表格

适用输入：Base URL、带 `table=` 参数的 Wiki URL 或 `base:{BASE_TOKEN}:{TABLE_ID}`。

必须使用 `lark-cli base` 和 `lark-base` skill 读取多维表格记录。

### URL 解析规则

对形如 `https://...feishu.cn/wiki/{WIKI_TOKEN}?table={TABLE_ID}&view={VIEW_ID}` 的链接，必须按以下顺序解析：

1. 从路径 `/wiki/{WIKI_TOKEN}` 提取 wiki token。
2. 从查询参数 `table` 提取表格 ID，作为 `--table-id`。
3. 从查询参数 `view` 提取视图 ID，作为可选 `--view-id`；如果后续读取命令不支持 view 参数，可以只用于记录来源上下文。
4. 使用 `lark-cli wiki spaces get_node` 将 wiki token 解析为真实 base token，取返回 JSON 的 `.data.node.obj_token`。
5. 使用真实 base token 和 table ID 调用 `lark-cli base +record-list`；不得把 wiki token 直接当作 base token。

### 表结构要求

必须具备以下 Base 字段：

| 字段 | 用途 |
|------|------|
| 问题编号 | 匹配修复项 |
| 严重级别 | 确定默认修复顺序 |
| 所属维度 | 支持按维度筛选和修复分组 |
| 技术栈 | 保留专项修复上下文，可为空 |
| 位置 | 定位代码 |
| 问题描述 | 理解问题 |
| 置信度 | 判断是否可自动修复或需人工确认 |
| 证据 | 保留审查依据，支持修复验证 |
| 影响 | 判断风险和修复优先级 |
| 修复建议 | 生成修复计划 |
| 修复状态 | 过滤待修复记录并写回结果 |
| 修复时间 | 写回完成时间 |
| 修复分支 | 写回修复所在分支 |
| 修复人 | 写回当前 Git 用户 |
| 备注 | 写回本地报告路径、验证摘要和未完成原因 |

### 读取命令

```bash
lark-cli base +record-list --base-token "{BASE_TOKEN}" --table-id "{TABLE_ID}"
```

Wiki 链接读取模板：

```bash
WIKI_TOKEN="FlKdwsFpIih3CzkQhl7cwR40nsz"
TABLE_ID="tblhnVIjMA4Rts1i"
VIEW_ID="vewiXLBlKx"

BASE_TOKEN=$(lark-cli wiki spaces get_node \
  --params "{\"token\": \"$WIKI_TOKEN\"}" \
  --as user | jq -r '.data.node.obj_token')

lark-cli base +record-list \
  --base-token "$BASE_TOKEN" \
  --table-id "$TABLE_ID" \
  --as user
```

如果命令环境要求显式子命令前缀，可使用等价的 `lark-cli base` 读记录命令，但必须保持同一 CLI 家族，不混用旧工具。

### 读取失败处理

Base 读取失败或缺少关键字段时，如果没有已归一化问题上下文，必须停止在代码变更之前，只生成本地失败报告。只有已存在来自本地 Markdown、已确认缓存或其他可信来源的归一化问题上下文时，才可继续执行代码修复，并将 Base 读取失败写入本地报告。

### 记录过滤

多维表格记录过滤必须和 `references/fix-workflow.md` 的统一状态过滤保持一致。默认只修复：

- `修复状态` 为空
- `修复状态` 为 `待修复`
- `修复状态` 为 `修复中` 且用户明确要求继续

必须跳过 `已修复`、`已忽略`、`不适用` 的记录，并在「修复输入解析完成」摘要中统计跳过数量。跳过记录不得出现在待确认问题表格中，也不得进入 `CONFIRMED_ISSUE_IDS`。

---

## 更新飞书多维表格

本节只适用于输出目标选择 `写回原始飞书多维表格` 的情况。用户选择独立本地 Markdown、独立飞书云文档或独立飞书多维表格修复报告时，不得更新原始 Base 记录。

### 状态映射

| 本地修复状态 | 写回 `修复状态` |
|--------------|----------------|
| 已修复 | 已修复 |
| 部分修复 | 修复中 |
| 未修复 | 待修复 |
| 已忽略 | 已忽略 |
| 待人工确认 | 待修复 |

### 写回字段

每条参与修复的问题必须写回：

- `修复状态`
- `修复时间`
- `修复分支`
- `修复人`
- `备注`

`修复时间` 必须取 `phase9-collect-fix-metadata.sh` 输出的 `FIX_COMPLETED_AT`，`修复分支` 必须取 `FIX_BRANCH`，`修复人` 必须取 `FIX_ACTOR`。`备注` 中写入本地报告路径、验证命令摘要和未完成原因。不要把完整 Markdown 报告塞入单元格。

### 更新命令

```bash
lark-cli base +record-upsert \
  --base-token "{BASE_TOKEN}" \
  --table-id "{TABLE_ID}" \
  --record-id "{RECORD_ID}" \
  --json '{"fields":{"修复状态":"已修复","修复时间":"2026-05-07 15:30:00 +0800","修复分支":"codex/fix-auth","修复人":"Fix User <fixer@example.com>","备注":"本地报告: fix-report-demo-20260507-153000.md；验证: mvn test 通过"}}'
```

更新前必须确认 `RECORD_ID` 来自读取结果。无法匹配记录时，只在本地报告中记录，不创建新记录。

写回失败不得回滚已完成代码修复；必须继续生成本地报告，并在「飞书回写结果」中记录失败命令、记录 ID、错误摘要和建议手动同步字段。

---

## 更新原始飞书云文档

本节只适用于输出目标选择 `写回原始飞书云文档` 的情况。必须使用 `lark-cli docs` 和 `lark-doc` skill 更新原文档中的对应问题状态，不得创建新问题清单替代原文档。

示例：

```bash
lark-cli docs +update \
  --api-version v2 \
  --doc "{DOC_URL}" \
  --command str_replace \
  --old-text "{原问题条目}" \
  --new-text "{追加修复状态、修复时间、修复分支、修复人和备注后的问题条目}"
```

无法稳定定位对应问题条目时，不得覆盖整份文档；必须在本地报告中记录待手动同步字段。

---

## 创建修复报告云文档

如果用户要求创建独立飞书云文档修复报告：

1. 优先创建新的修复报告云文档，不覆盖原始审查报告。
2. 本地 Markdown 修复报告的一级标题使用 `Java 代码修复报告 - {PROJECT_NAME} - {YYYY-MM-DD}`。
3. 上传内容必须来自本地 Markdown 修复报告文件。

示例：

```bash
cd "$PROJECT_DIR" && lark-cli docs +create \
  --api-version v2 \
  --doc-format markdown \
  --content @fix-report-demo-20260507-153000.md
```

---

## 创建独立飞书多维表格修复报告

如果用户要求创建独立飞书多维表格修复报告，必须新建或定位一个独立表格承载本次修复结果，不得写入原始问题清单表。表格字段至少包括：

- 问题编号
- 修复状态
- 修复时间
- 修复分支
- 修复人
- 验证摘要
- 本地报告路径
- 备注

创建或写入失败时回退为本地 Markdown 报告，并在「飞书回写结果」与「输出目标执行结果」中记录失败原因。

---

## 失败降级

出现以下任一情况时，必须回退为本地 Markdown 报告：

- `lark-cli` 不存在
- 登录态或权限不足
- 文档读取失败
- Base 读取失败
- Base 缺少关键字段
- 记录更新失败且无法安全重试

读取类失败和写入类失败的边界不同：

- 飞书云文档读取、Base 读取或 Base 关键字段检查失败，且无已归一化问题上下文时，必须停止修复，只生成本地失败报告。
- 飞书云文档读取、Base 读取或 Base 关键字段检查失败，但已有确认可用的归一化问题上下文时，可以继续代码修复和验证。
- 云文档创建、Base 写回或记录更新失败时，可以继续完成代码修复、验证和本地报告。

回退后最终报告必须包含：

- 原计划飞书目标
- 失败命令
- 错误摘要
- 已生成的本地报告路径
- 建议用户补充权限或手动同步的字段列表
