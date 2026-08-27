# Scan Examples

本文件只展示当前有效的交互顺序和关键输出契约。每次 `INTERACT` 都必须单独调用并等待用户响应。

## Java 单模块全量审查

```text
用户：帮我审查 /workspace/order-service

我：🔍 预扫描完成

📂 项目：order-service
- 类型：Maven 单模块
- Java 文件：42
- 生产代码行数：3,850

🧩 技术栈扫描
| 技术栈 | 识别证据 | 建议维度 | 专项规则 |
|--------|----------|----------|----------|
| Spring Boot | spring-boot-starter-web | 3,5,8 | 配置安全、运行时暴露 |
| Validation | spring-boot-starter-validation | 1,3,5,15 | 输入边界、参数校验 |

🔌 lark-cli：✅ 可用
🧩 项目 ignore：✅ 已启用（已忽略 2 个问题）

→ INTERACT：请选择审查模式
  [fast（仅输出 P0） | standard（推荐） | deep | security]
→ 用户：fast（仅输出 P0）

→ INTERACT：请选择审查报告的保存方式
  [本地 Markdown 报告 | 飞书云文档 | 飞书多维表格]（多选）
→ 用户：飞书云文档、飞书多维表格

→ INTERACT：请选择本次审查入口
  [增量审查 | 全量审查 | 指定模块]
→ 用户：全量审查

我：全量审查自动使用「全量代码」。
→ INTERACT：请选择审查使用的模型档位
  [继承当前会话（推荐） | 经济档 | 平衡档 | 最高能力档]
→ 用户：继承当前会话（推荐）

我：📋 执行计划
- 审查类型：存量审查
- 审查范围：全量代码
- 审查模式：fast
- 输出级别：仅 P0
- 审查模型：inherit
- 报告保存方式：飞书云文档、飞书多维表格

→ INTERACT：确认执行计划
  [确认执行 | 取消]
→ 用户：确认执行

我：🚀 启动单 Agent 审查
- 注入 REVIEW_INPUT_PATH（selected=true 是唯一正式范围）
- 注入 REVIEW_UNITS_PATH（只按结构关联组织阅读顺序，不预判安全问题）
- 注入 REVIEW_RULES_RESOLVED_PATH
- Agent 只落盘 Markdown，主 Skill 负责后续飞书保存

我：✅ 代码审查已完成
- 项目 ignore 命中 2 条规则，过滤 5 个同类问题
- 报告已保存到：/workspace/order-service/code-review-report-order-service-20260810-120000.md
```

## 增量审查

```text
用户：审查 /workspace/payment-service 最近的改动

我：完成预扫描后逐步确认审查模式、报告保存方式和审查入口。
→ 用户选择：增量审查

我：📜 最近提交概览
1. a1b2c3d validate payment callback
2. d4e5f6a add retry policy
3. 0123abc refactor payment client

→ INTERACT：审查最近几次提交的变更？
  [最近 1 次 | 最近 3 次 | 最近 5 次（推荐） | 最近 10 次]
→ 用户：最近 3 次

→ INTERACT：请选择审查使用的模型档位
→ 用户：平衡档

我：📋 执行计划
- 审查类型：增量审查
- 审查范围：最近 3 次提交
- 审查模型：balanced
- 正式输入：prepare-review-input.sh 冻结的 selected 文件
- 项目规则：只解析 selected 文件，不把范围外文件带入规则结果

→ INTERACT：确认执行计划
→ 用户：确认执行
```

## Maven 大仓库可恢复分批审查

Maven 多模块存量审查先按当前已确认范围重算规模。只有
`estimated_tokens > 1000000` 时才展示步骤 4B，选择分批策略后使用
`plan-large-batches.sh`；小于或等于 100 万估算 token 的多模块仓库跳过 4B，
直接使用单 agent。其他文件级存量审查也只在 `estimated_tokens > 1000000` 时进入文件分批；
所有模型统一按 1M 上下文规划。

```text
用户：帮我审查 /workspace/large-enterprise-app

我：完成预扫描后逐步确认：
1. 审查模式：standard
2. 报告保存方式：本地 Markdown 报告
3. 审查入口：全量审查
4. 当前全量范围达到大仓门槛，存量审查方式：AI 智能规划分批
5. 审查模型：最高能力档

注意：模型必须在分批判定和批次选择之前确认。

我：📦 大仓库审查任务
- Run ID：20260810-120000-main-standard
- 语义增强：jdtls-lsp
- 批次数：8
- 生产 Java 文件：1,250
- 生产 Java 行数：185,000

| 批次 | 状态 | 行数 | 文件数 | 模块 |
|------|------|------:|------:|------|
| batch-001 | 待执行 | 28,400 | 310 | order-api,order-service |
| batch-002 | 待执行 | 27,900 | 295 | payment-service |
| batch-003 | 待执行 | 26,800 | 276 | inventory-service |

→ INTERACT：请选择本轮执行批次
  [执行 3 批 | 执行 5 批（推荐） | 执行全部 8 批]
→ 用户：执行 5 批（推荐）

→ INTERACT：请选择并发扫描策略
  [串行执行（默认） | 2 路并发 | 3 路并发]
→ 用户：2 路并发

我：📋 执行计划
- 审查模型：maximum
- 本轮批次：5 / 8
- 并发数：2
- 亲和性 cost 放宽只作用于软预算，批次成本不得超过 HARD_MAX_BATCH_COST=325000
- 每批完成后写入 BATCH_RESULT_PATH（对应 results/batch-XXX.md）和状态文件
- 批次中断但已产出至少一条正式发现时写 partial（部分完成待重跑）：已产出发现照常落盘，后续可整批重跑
- 合并前对纳入批次自动执行跨文件重归档（fail-open）：证据代码唯一命中审查范围内另一文件时迁移位置，多命中保持原状

→ INTERACT：确认执行计划
→ 用户：确认执行

我：完成本轮后生成阶段性报告；未纳入本轮的批次保持 leftover，不进入正式结论。partial 批次的已产出发现会在合并时纳入（标注"部分完成已纳入"），但覆盖统计保守不计，报告保持阶段性。

我：✅ 本轮审查完成
- P0-1：高置信已证实：生产订单请求参数直达未参数化 SQL，无有效校验或绑定防护，可破坏关键订单数据，必须阻断发布
- P0-2：高置信已证实：生产支付链路发生部分提交，无回滚或补偿防护，可造成资金错误，必须阻断发布
- run-manifest.json 使用仓库相对路径，并为跨 clone/workspace 生成稳定 item_id

我：批次失败归因示例——假设本轮 batch-004 因上下文耗尽失败且零产出，状态 JSON 按「中断归因枚举」（封闭五值）写入必填的 failure_class：

{ "batch_id": "batch-004", "status": "failed", "finding_count": 0, "result_path": null, "failure_class": "context_exhausted", "error": "上下文耗尽，需要整批重跑" }

失败与 partial 批次的 failure_class 会反映到失败归因统计：批次状态总览的错误列随之显示 [短标签] 原error（如 [上下文耗尽] 前缀），summary.json 的 failed_by_class 按解析后枚举计数，show-batch-status.sh 追加一行失败归因统计：
失败归因: 上下文耗尽 ×1

我：恢复前必须过 validate-resume-input 门禁（--rules）。用户次日要求复用未完成的 RUN_DIR，展示可调度批次之前主 skill 必须先执行：
bash scripts/core/validate-resume-input.sh "$RUN_DIR" "$PROJECT_DIR" --rules
→ 本次门禁 exit 2 输出单行 INPUT_CHANGED=review-input.json sha256 mismatch recorded=… actual=…，stderr 另有 ERROR_INPUT_CHANGED 行与中文处置建议。

门禁退出码非 0（INPUT_CHANGED / RULES_CHANGED / FROZEN_INPUT_MISSING / 用法错误）：不得列出任何可调度批次，向用户转述门禁输出的单行原因与建议行，经用户确认整体重新规划并创建新的 RUN_DIR；legacy 计划缺 rules_snapshot_sha256 在 --rules 下同样 fail-closed（RULES_CHANGED=legacy run lacks rules snapshot）。仅当输出 GATE_OK=<run_id> 时才放行进入既有 pending/partial/failed 调度流程。
```

## lark-cli 不可用时

```text
🔌 lark-cli：⚠️ 飞书保存不可用：lark-cli 命令未安装

我：报告保存方式自动设为本地 Markdown 报告，不再询问飞书输出；其他 INTERACT 步骤保持不变。

审查完成后：
📄 报告已保存到：/workspace/demo/code-review-report-demo-20260810-123000.md
```

## Vue 3 与 React 信号共存

```text
用户：帮我审查 /workspace/admin-dashboard

我：🔍 预扫描完成
- 类型：frontend-vue3
- 证据：.vue SFC、vue@3、@vitejs/plugin-vue、pinia
- 额外检测到 React 依赖，但按 Vue 优先策略路由到 Vue 3
- 正式范围：受支持 package-local src 下的生产源码

后续仍按同一顺序逐步确认：审查模式 → 报告保存方式 → 审查入口 →
可选目录范围 → 审查模型 → 可选批次/并发 → 最终执行计划。
```
