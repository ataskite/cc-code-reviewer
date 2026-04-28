# 飞书集成参考

本文件定义代码审查报告中飞书上传功能的详细操作规范，供子 agent 在上传云文档和创建多维表格时使用。

所有操作均通过 `lark-cli` 命令行工具完成。**禁止使用 `feishu_create_doc`、`feishu_bitable_*` 等旧版工具。**

---

## 一、上传报告到飞书云文档

**前置条件**：`FEISHU_UPLOAD_OPTION` 为 `上传到云文档` 或 `同时上传两者`，且审查报告生成完毕。

### 1.1 命令格式

```bash
cd "$PROJECT_DIR" && lark-cli docs +create \
  --title "🛡️ Java 代码审查报告 - {PROJECT_NAME} - {REVIEW_MODE}模式 - {YYYY-MM-DD}" \
  --markdown @{REPORT_FILENAME}
```

### 1.2 已验证的完整示例

```bash
# 先 cd 到报告文件所在目录（必须！--markdown 不接受绝对路径）
cd /path/to/project && \
lark-cli docs +create \
  --title "Java 代码审查报告 - agentscope-demo (deep 模式)" \
  --markdown @code-review-report-agentscope-demo-20260429-041231.md
```

### 1.3 成功响应示例

```json
{
  "ok": true,
  "data": {
    "doc_id": "JKDZdHhYVoicZuxyb82cjWPNnMc",
    "doc_url": "https://www.feishu.cn/docx/JKDZdHhYVoicZuxyb82cjWPNnMc",
    "message": "文档创建成功"
  }
}
```

从 `data.doc_url` 提取文档链接用于最终汇总。

### 1.4 常见错误与解决

| 错误 | 原因 | 解决 |
|------|------|------|
| `unknown command "doc"` | 命令拼写错误 | 使用 `docs`（有 s），不是 `doc` |
| `invalid file path ... must be a relative path` | `--markdown @` 不接受绝对路径 | 先 `cd` 到文件所在目录，使用 `@filename` 相对路径 |
| `unknown flag: --title` | 子命令层级错误 | 完整命令是 `lark-cli docs +create`，注意 `+` 号 |

### 1.5 注意事项

- 文档内容必须是完整的审查报告 Markdown 文件
- 如果创建失败，在报告中说明原因，不阻塞后续步骤
- 日期格式：YYYY-MM-DD

---

## 二、创建飞书多维表格

**前置条件**：`FEISHU_UPLOAD_OPTION` 为 `上传到多维表格` 或 `同时上传两者`，且审查报告生成完毕。

### 2.1 字段定义（共 18 个字段，必须完整使用）

| # | 字段名 | lark-cli type 值 | 选项列表 | 说明 |
|---|--------|-----------------|----------|------|
| 1 | 问题编号 | text | - | 格式：P0-1、P1-1、P2-1、P3-1、待确认-1 |
| 2 | 严重级别 | select | P0 严重、P1 重要、P2 一般、P3 建议、待确认 | 问题严重程度 |
| 3 | 所属维度 | select | 正确性、代码质量、Spring Boot 规范、数据库/MyBatis、安全、性能、资源管理、日志/可观测性、测试质量、技术债、架构、分布式系统、消息队列、缓存、API 设计 | 问题所属的审查维度 |
| 4 | 技术栈 | select（multiple） | Spring Boot、MyBatis、MyBatis Plus、JPA/Hibernate、Redis、Kafka、RabbitMQ、MySQL、Dubbo、Feign、Shiro、Spring Security、JWT、Jackson、Netty、Nginx、Docker、其他 | 关联的技术组件（多选） |
| 5 | 问题描述 | text | - | 问题的简要描述 |
| 6 | 位置 | text | - | 文件路径:行号 或 类名/方法名 |
| 7 | 置信度 | select | 高、中、低 | 问题判断的置信度 |
| 8 | 证据 | text | - | 触发判断的代码或配置依据 |
| 9 | 影响 | text | - | 为什么重要，可能造成的后果 |
| 10 | 修复建议 | text | - | 具体的修复方案和代码示例 |
| 11 | 修复状态 | select | 待修复、修复中、已修复、已忽略、不适用 | 默认"待修复" |
| 12 | 审查模式 | select | fast、standard、deep、security | 本次审查使用的模式 |
| 13 | 审查日期 | datetime | yyyy-MM-dd | 审查执行日期 |
| 14 | 负责人 | user | - | 留空，由团队分配 |
| 15 | 备注 | text | - | 补充说明 |
| 16 | 修复时间 | datetime | yyyy-MM-dd | 预留字段，初始留空 |
| 17 | 修复分支 | text | - | 预留字段，初始留空 |
| 18 | 修复人 | user | - | 预留字段，初始留空 |

### 2.2 执行步骤

#### 步骤 1：创建多维表格应用

```bash
lark-cli base +base-create --name "代码审查问题清单 - {PROJECT_NAME}"
```

成功响应：
```json
{
  "ok": true,
  "data": {
    "base": {
      "base_token": "S2slbvdMaaQHubsxAxbcsYDrnVO",
      "name": "代码审查问题清单 - agentscope-demo",
      "url": "https://xxx.feishu.cn/base/S2slbvdMaaQHubsxAxbcsYDrnVO"
    }
  }
}
```

保存 `base_token` 和 `url`。

#### 步骤 2：查看默认表 ID

```bash
lark-cli base +table-list --base-token {BASE_TOKEN}
```

响应中获取默认表的 `id`（如 `tbl1ZdE0hBsV1DVh`），保存为 `TABLE_ID`。

> 新建的多维表格会自动创建一个默认表（名为"数据表"），后续操作基于这个表。默认表自带几个空白字段（"单选"、"日期"、"文本"、"附件"），需要在本表上创建新字段，然后清理默认字段。

#### 步骤 3：逐个创建字段

**⚠️ 关键：`--json` 中 `type` 必须使用字符串名称，不能使用数字。**

正确的 type 值对照表：

| 字段类型 | lark-cli type 值 | 错误写法（数字） |
|---------|-----------------|---------------|
| 文本 | `"text"` | ~~`1`~~ |
| 单选 | `"select"` | ~~`3`~~ |
| 多选 | `"select"`（带 `"multiple": true`） | ~~`4`~~ |
| 日期 | `"datetime"` | ~~`5`~~ |
| 人员 | `"user"` | ~~`11`~~ |

**⚠️ 关键：`options` 必须是对象数组 `[{name:"..."}]`，不能用纯字符串数组，也不能放在 `property` 里。**

以下为 18 个字段的完整创建命令：

```bash
BT="{BASE_TOKEN}" && TI="{TABLE_ID}"

# 1. 问题编号
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"问题编号","type":"text"}'

# 2. 严重级别（单选）
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"严重级别","type":"select","options":[{"name":"P0 严重"},{"name":"P1 重要"},{"name":"P2 一般"},{"name":"P3 建议"},{"name":"待确认"}]}'

# 3. 所属维度（单选）
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"所属维度","type":"select","options":[{"name":"正确性"},{"name":"代码质量"},{"name":"Spring Boot 规范"},{"name":"数据库/MyBatis"},{"name":"安全"},{"name":"性能"},{"name":"资源管理"},{"name":"日志/可观测性"},{"name":"测试质量"},{"name":"技术债"},{"name":"架构"},{"name":"分布式系统"},{"name":"消息队列"},{"name":"缓存"},{"name":"API 设计"}]}'

# 4. 技术栈（多选）
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"技术栈","type":"select","multiple":true,"options":[{"name":"Spring Boot"},{"name":"MyBatis"},{"name":"MyBatis Plus"},{"name":"JPA/Hibernate"},{"name":"Redis"},{"name":"Kafka"},{"name":"RabbitMQ"},{"name":"MySQL"},{"name":"Dubbo"},{"name":"Feign"},{"name":"Shiro"},{"name":"Spring Security"},{"name":"JWT"},{"name":"Jackson"},{"name":"Netty"},{"name":"Nginx"},{"name":"Docker"},{"name":"其他"}]}'

# 5. 问题描述
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"问题描述","type":"text"}'

# 6. 位置
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"位置","type":"text"}'

# 7. 置信度（单选）
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"置信度","type":"select","options":[{"name":"高"},{"name":"中"},{"name":"低"}]}'

# 8. 证据
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"证据","type":"text"}'

# 9. 影响
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"影响","type":"text"}'

# 10. 修复建议
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"修复建议","type":"text"}'

# 11. 修复状态（单选）
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"修复状态","type":"select","options":[{"name":"待修复"},{"name":"修复中"},{"name":"已修复"},{"name":"已忽略"},{"name":"不适用"}]}'

# 12. 审查模式（单选）
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"审查模式","type":"select","options":[{"name":"fast"},{"name":"standard"},{"name":"deep"},{"name":"security"}]}'

# 13. 审查日期
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"审查日期","type":"datetime"}'

# 14. 负责人
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"负责人","type":"user"}'

# 15. 备注
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"备注","type":"text"}'

# 16. 修复时间
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"修复时间","type":"datetime"}'

# 17. 修复分支
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"修复分支","type":"text"}'

# 18. 修复人
lark-cli base +field-create --base-token $BT --table-id $TI \
  --json '{"name":"修复人","type":"user"}'
```

#### 步骤 4：批量录入问题数据

**⚠️ 关键：使用 `fields` + `rows` 格式，`rows` 是二维数组。**

```bash
lark-cli base +record-batch-create \
  --base-token {BASE_TOKEN} \
  --table-id {TABLE_ID} \
  --json '{
    "fields": ["问题编号","严重级别","所属维度","技术栈","问题描述","位置","置信度","证据","影响","修复建议","修复状态","审查模式","审查日期","负责人","备注","修复时间","修复分支","修复人"],
    "rows": [
      ["P0-1","P0 严重","安全",["Spring Boot"],"问题描述","文件.java:22","高","证据内容","影响说明","修复建议","待修复","deep",1744588800000,"","","","",""]
    ]
  }'
```

**记录字段映射**：
- `问题编号`：P0-1、P1-1、P2-1 ...
- `严重级别`：选项文本，如 `"P0 严重"`、`"P1 重要"`
- `所属维度`：选项文本，如 `"安全"`、`"性能"`
- `技术栈`：数组形式，如 `["Spring Boot", "MyBatis"]`
- `问题描述`：问题的简要描述
- `位置`：文件路径:行号
- `置信度`：`"高"` / `"中"` / `"低"`
- `证据`：问题详情中的证据部分
- `影响`：问题详情中的影响部分
- `修复建议`：问题详情中的修复建议
- `修复状态`：默认填 `"待修复"`
- `审查模式`：当前 REVIEW_MODE 值（`"fast"` / `"standard"` / `"deep"` / `"security"`）
- `审查日期`：当前日期的毫秒时间戳（如 `1744588800000`）
- `负责人`：留空 `""`
- `备注`：留空 `""`
- `修复时间`：预留字段，留空 `""`
- `修复分支`：预留字段，留空 `""`
- `修复人`：预留字段，留空 `""`

**录入规则**：
- 单次 batch_create 最多 500 条，超出需分批
- 按 P0 → P1 → P2 → P3 → 待确认 的顺序录入
- 预留字段（修复时间、修复分支、修复人）初始留空，供后续修复流程更新使用

#### 步骤 5：清理默认字段

默认表自带的字段（"单选"、"日期"、"附件"）需要删除，"文本"字段是主字段需重命名：

```bash
# 删除非主字段的默认字段（需要 --yes 确认）
lark-cli base +field-delete --base-token {BASE_TOKEN} --table-id {TABLE_ID} \
  --field-id {FIELD_ID} --yes

# 主字段（"文本"）无法删除，只能重命名
lark-cli base +field-update --base-token {BASE_TOKEN} --table-id {TABLE_ID} \
  --field-id {PRIMARY_FIELD_ID} --json '{"name":"备注","type":"text"}'
```

> **注意**：主字段是第一个被创建的字段（通常名为"文本"），无法通过 `+field-delete` 删除（会报错 `unsafe_operation_blocked`）。只能通过 `+field-update` 重命名为"备注"等名称。

#### 步骤 6：重命名数据表（可选）

```bash
lark-cli base +table-update --base-token {BASE_TOKEN} --table-id {TABLE_ID} \
  --name "问题清单"
```

### 2.3 常见错误与解决

| 错误信息 | 原因 | 解决 |
|---------|------|------|
| `Unrecognized key(s) in object: 'property'` | 字段 JSON 中使用了 `"property": {"options": [...]}` | 顶层直接用 `"options": [{...}]`，不要包裹在 `property` 里 |
| `Provide a value of type object` | options 传了字符串数组 `["A","B"]` | 改为对象数组 `[{"name":"A"},{"name":"B"}]` |
| `Invalid discriminator value` | `type` 使用了数字（如 `1`、`3`） | `type` 必须使用字符串名称（如 `"text"`、`"select"`） |
| `unsafe_operation_blocked`（删除主字段） | 尝试删除主字段 | 主字段只能重命名，不能删除。用 `+field-update` 改名 |
| `requires confirmation` | 删除字段需要确认 | 添加 `--yes` 标志 |
| `unknown command "bitable"` | 命令拼写错误 | lark-cli 中多维表格叫 `base`，不是 `bitable` |

### 2.4 完整操作示例（可直接复制执行）

以下是一个完整的、已验证通过的端到端流程，替换 `{BASE_TOKEN}` 和 `{TABLE_ID}` 即可使用：

```bash
# 1. 创建多维表格
lark-cli base +base-create --name "代码审查问题清单 - {PROJECT_NAME}"

# 2. 查看默认表 ID
lark-cli base +table-list --base-token {BASE_TOKEN}

# 3. 创建 18 个字段（见步骤 3 的完整命令）
BT="{BASE_TOKEN}" TI="{TABLE_ID}"
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"问题编号","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"严重级别","type":"select","options":[{"name":"P0 严重"},{"name":"P1 重要"},{"name":"P2 一般"},{"name":"P3 建议"},{"name":"待确认"}]}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"所属维度","type":"select","options":[{"name":"正确性"},{"name":"代码质量"},{"name":"Spring Boot 规范"},{"name":"数据库/MyBatis"},{"name":"安全"},{"name":"性能"},{"name":"资源管理"},{"name":"日志/可观测性"},{"name":"测试质量"},{"name":"技术债"},{"name":"架构"},{"name":"分布式系统"},{"name":"消息队列"},{"name":"缓存"},{"name":"API 设计"}]}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"技术栈","type":"select","multiple":true,"options":[{"name":"Spring Boot"},{"name":"MyBatis"},{"name":"MyBatis Plus"},{"name":"JPA/Hibernate"},{"name":"Redis"},{"name":"Kafka"},{"name":"RabbitMQ"},{"name":"MySQL"},{"name":"Dubbo"},{"name":"Feign"},{"name":"Shiro"},{"name":"Spring Security"},{"name":"JWT"},{"name":"Jackson"},{"name":"Netty"},{"name":"Nginx"},{"name":"Docker"},{"name":"其他"}]}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"问题描述","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"位置","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"置信度","type":"select","options":[{"name":"高"},{"name":"中"},{"name":"低"}]}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"证据","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"影响","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"修复建议","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"修复状态","type":"select","options":[{"name":"待修复"},{"name":"修复中"},{"name":"已修复"},{"name":"已忽略"},{"name":"不适用"}]}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"审查模式","type":"select","options":[{"name":"fast"},{"name":"standard"},{"name":"deep"},{"name":"security"}]}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"审查日期","type":"datetime"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"负责人","type":"user"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"备注","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"修复时间","type":"datetime"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"修复分支","type":"text"}'
lark-cli base +field-create --base-token $BT --table-id $TI --json '{"name":"修复人","type":"user"}'

# 4. 批量录入数据（18 个字段）
lark-cli base +record-batch-create --base-token $BT --table-id $TI \
  --json '{"fields":["问题编号","严重级别","所属维度","技术栈","问题描述","位置","置信度","证据","影响","修复建议","修复状态","审查模式","审查日期","负责人","备注","修复时间","修复分支","修复人"],"rows":[["P0-1","P0 严重","安全",["Spring Boot"],"问题描述","文件.java:22","高","证据","影响","建议","待修复","deep",1744588800000,"","","","",""]]}'

# 5. 清理默认字段（先查 list 获取 ID，再逐个删除 + 重命名主字段）
lark-cli base +field-list --base-token $BT --table-id $TI
lark-cli base +field-delete --base-token $BT --table-id $TI --field-id {非主字段ID} --yes
lark-cli base +field-update --base-token $BT --table-id $TI --field-id {主字段ID} --json '{"name":"备注2","type":"text"}'

# 6. 重命名数据表
lark-cli base +table-update --base-token $BT --table-id $TI --name "问题清单"
```
