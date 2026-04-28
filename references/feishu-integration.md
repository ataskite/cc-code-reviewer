# 飞书集成参考

本文件定义代码审查报告中飞书上传功能的详细操作规范，供子 agent 在第四步（上传云文档）和第五步（创建多维表格）时使用。

---

## 一、上传报告到飞书云文档

**前置条件**：`FEISHU_UPLOAD_OPTION` 为 `上传到云文档` 或 `同时上传两者`，且审查报告生成完毕。

**⚠️ 强制要求**：必须通过 `lark-cli` 命令行工具配合 `lark-doc` skill 执行上传操作。**禁止使用 `feishu_create_doc` 等旧版工具**。

**执行步骤**：

1. 使用 `Skill` 工具调用 `lark-doc` skill 创建云文档
   - 操作：从 Markdown 创建文档（`+create`）
   - 文档标题格式：`🛡️ Java 代码审查报告 - {PROJECT_NAME} - {REVIEW_MODE}模式 - {日期}`
   - 文档内容：完整的审查报告（Markdown 格式）
2. 等待文档创建完成，获取文档链接
3. 保存文档链接用于最终汇总

**注意**：
- 文档内容必须是完整的审查报告，包含所有章节
- 如果创建失败，在报告中说明原因，不阻塞后续步骤
- 日期格式：YYYY-MM-DD

---

## 二、创建飞书多维表格

**前置条件**：`FEISHU_UPLOAD_OPTION` 为 `上传到多维表格` 或 `同时上传两者`，且审查报告生成完毕。

**⚠️ 强制要求**：必须通过 `lark-cli` 命令行工具配合 `lark-base` skill 执行多维表格操作。**禁止使用 `feishu_bitable_app`、`feishu_bitable_app_table`、`feishu_bitable_app_table_record`、`feishu_bitable_app_table_field`、`feishu_bitable_app_table_view` 等旧版工具**。

### 2.1 字段定义（共 18 个字段，必须完整使用）

| # | 字段名 | 字段类型 | type | 选项列表 | 说明 |
|---|--------|---------|------|----------|------|
| 1 | 问题编号 | 文本 | 1 | - | 格式：P0-1、P1-1、P2-1、P3-1、待确认-1 等，按级别分组编号 |
| 2 | 严重级别 | 单选 | 3 | 🔴 P0 严重、🟠 P1 重要、🟡 P2 一般、🔵 P3 建议、⚪ 待确认 | 问题严重程度 |
| 3 | 所属维度 | 单选 | 3 | 正确性、代码质量、Spring Boot 规范、数据库/MyBatis、安全、性能、资源管理、日志/可观测性、测试质量、技术债、架构、分布式系统、消息队列、缓存、API 设计 | 问题所属的审查维度 |
| 4 | 技术栈 | 多选 | 4 | Spring Boot、MyBatis、MyBatis Plus、JPA/Hibernate、Redis、Kafka、RabbitMQ、MySQL、Dubbo、Feign、Shiro、Spring Security、JWT、Jackson、Netty、Nginx、Docker、其他 | 关联的技术组件 |
| 5 | 问题描述 | 文本 | 1 | - | 问题的简要描述（一句话概括） |
| 6 | 位置 | 文本 | 1 | - | 文件路径:行号 或 文件路径 + 类名/方法名 |
| 7 | 置信度 | 单选 | 3 | 高、中、低 | 问题判断的置信度 |
| 8 | 证据 | 文本 | 1 | - | 触发判断的代码或配置依据 |
| 9 | 影响 | 文本 | 1 | - | 为什么重要，可能造成的后果 |
| 10 | 修复建议 | 文本 | 1 | - | 具体的修复方案和代码示例 |
| 11 | 修复状态 | 单选 | 3 | 待修复、修复中、已修复、已忽略、不适用 | 默认"待修复" |
| 12 | 审查模式 | 单选 | 3 | fast、standard、deep、security | 本次审查使用的模式 |
| 13 | 审查日期 | 日期 | 5 | yyyy-MM-dd | 审查执行日期 |
| 14 | 负责人 | 人员 | 11 | - | 留空，由团队分配 |
| 15 | 备注 | 文本 | 1 | - | 补充说明 |
| 16 | 修复时间 | 日期 | 5 | yyyy-MM-dd | 预留字段，初始留空 |
| 17 | 修复分支 | 文本 | 1 | - | 预留字段，初始留空 |
| 18 | 修复人 | 人员 | 11 | - | 预留字段，初始留空 |

### 2.2 技术栈标注规则

- 根据问题涉及的**核心技术组件**标注，一条问题可关联多个技术栈
- 示例：MyBatis XML 中的 SQL 注入 → 标注 `MyBatis`；Spring Security 配置遗漏 → 标注 `Spring Boot`、`Spring Security`

### 2.3 创建数据表的完整字段配置 JSON

步骤 5.2 使用，`+table-create` 必须完整传入以下 JSON，仅替换 `app_token`：

```json
{
  "action": "create",
  "app_token": "{从 base-create 获取}",
  "table": {
    "name": "问题清单",
    "default_view_name": "全部问题",
    "fields": [
      {"field_name": "问题编号", "type": 1},
      {"field_name": "严重级别", "type": 3, "property": {"options": [
        {"name": "🔴 P0 严重", "color": 0},
        {"name": "🟠 P1 重要", "color": 1},
        {"name": "🟡 P2 一般", "color": 10},
        {"name": "⚪ 待确认", "color": 20},
        {"name": "🔵 P3 建议", "color": 20}
      ]}},
      {"field_name": "所属维度", "type": 3, "property": {"options": [
        {"name": "正确性"}, {"name": "代码质量"}, {"name": "Spring Boot 规范"},
        {"name": "数据库/MyBatis"}, {"name": "安全"}, {"name": "性能"},
        {"name": "资源管理"}, {"name": "日志/可观测性"}, {"name": "测试质量"},
        {"name": "技术债"}, {"name": "架构"}, {"name": "分布式系统"},
        {"name": "消息队列"}, {"name": "缓存"}, {"name": "API 设计"}
      ]}},
      {"field_name": "技术栈", "type": 4, "property": {"options": [
        {"name": "Spring Boot"}, {"name": "MyBatis"}, {"name": "MyBatis Plus"},
        {"name": "JPA/Hibernate"}, {"name": "Redis"}, {"name": "Kafka"},
        {"name": "RabbitMQ"}, {"name": "MySQL"}, {"name": "Dubbo"},
        {"name": "Feign"}, {"name": "Shiro"}, {"name": "Spring Security"},
        {"name": "JWT"}, {"name": "Jackson"}, {"name": "Netty"},
        {"name": "Nginx"}, {"name": "Docker"}, {"name": "其他"}
      ]}},
      {"field_name": "问题描述", "type": 1},
      {"field_name": "位置", "type": 1},
      {"field_name": "置信度", "type": 3, "property": {"options": [
        {"name": "高"}, {"name": "中"}, {"name": "低"}
      ]}},
      {"field_name": "证据", "type": 1},
      {"field_name": "影响", "type": 1},
      {"field_name": "修复建议", "type": 1},
      {"field_name": "修复状态", "type": 3, "property": {"options": [
        {"name": "待修复"}, {"name": "修复中"}, {"name": "已修复"},
        {"name": "已忽略"}, {"name": "不适用"}
      ]}},
      {"field_name": "审查模式", "type": 3, "property": {"options": [
        {"name": "fast"}, {"name": "standard"}, {"name": "deep"}, {"name": "security"}
      ]}},
      {"field_name": "审查日期", "type": 5, "property": {"date_formatter": "yyyy-MM-dd"}},
      {"field_name": "负责人", "type": 11, "property": {"multiple": false}},
      {"field_name": "备注", "type": 1},
      {"field_name": "修复时间", "type": 5, "property": {"date_formatter": "yyyy-MM-dd"}},
      {"field_name": "修复分支", "type": 1},
      {"field_name": "修复人", "type": 11, "property": {"multiple": false}}
    ]
  }
}
```

### 2.4 录入规则

**编号规则**：
- P0/P1/P2/P3：按级别分组编号，如 P0-1、P0-2、P1-1...
- 待确认：独立编号体系，如 待确认-1、待确认-2...

**记录字段映射**：
- `问题编号`：P0-1、P0-2、P1-1 ...
- `严重级别`：根据问题级别选择对应选项（如 `"🔴 P0 严重"`）
- `所属维度`：根据问题标注的维度选择对应选项（如 `"安全"`）
- `技术栈`：根据问题涉及的技术组件，传数组（如 `["Spring Boot", "MyBatis"]`）
- `问题描述`：问题的简要描述
- `位置`：问题的位置信息
- `置信度`：高/中/低
- `证据`：问题详情中的证据部分
- `影响`：问题详情中的影响部分
- `修复建议`：问题详情中的修复建议
- `修复状态`：默认填 `"待修复"`
- `审查模式`：当前 REVIEW_MODE 参数值（如 `"standard"`）
- `审查日期`：当前日期的毫秒时间戳（如 `1744588800000`）
- `负责人`：留空，不传值
- `备注`：留空，不传值
- `修复时间`：预留字段，初始留空，不传值
- `修复分支`：预留字段，初始留空，不传值
- `修复人`：预留字段，初始留空，不传值

**注意事项**：
- 单次 batch_create 最多 500 条，超出需分批
- 预留字段（修复时间、修复分支、修复人）初始留空，供后续修复流程更新使用

### 2.5 执行步骤

#### 5.1 创建多维表格应用

使用 `Skill` 工具调用 `lark-base` skill 创建多维表格（`+base-create`）：
- 应用名称格式：`📋 代码审查问题清单 - {PROJECT_NAME} - {日期}`
- 创建后会返回 `app_token` 和 `default_table_id`

> ⚠️ **重要**：创建应用时会自动生成一个**默认表**（含空白的默认列），该表会在 5.3 步骤中删除。

#### 5.2 创建数据表（一次性定义所有字段）

使用 `Skill` 工具调用 `lark-base` skill 创建**新数据表**（`+table-create`，不要使用默认表），表名：`问题清单`。

> **完整字段配置**：直接复制上方 2.3 节中的 JSON，将 `app_token` 替换为 5.1 步骤获取的值后传入。必须完整传入所有 18 个字段，不可省略、不可修改字段名和选项。

#### 5.3 删除默认表

使用 `Skill` 工具调用 `lark-base` skill 删除 5.1 创建应用时自动生成的默认表（`+table-delete`）：
```json
{
  "action": "delete",
  "app_token": "{从 5.1 获取}",
  "table_id": "{default_table_id}"
}
```

#### 5.4 录入问题数据

使用 `Skill` 工具调用 `lark-base` skill 的 `+record-batch-create` 操作，将所有问题批量录入多维表格。

关键要点：
- 遍历报告中所有级别的问题（P0、P1、P2、P3、待确认），按 P0 → P1 → P2 → P3 → 待确认 的顺序录入
- 同一级别内按发现顺序编号
- 如果多维表格创建失败，在报告中说明原因，不阻塞后续步骤
