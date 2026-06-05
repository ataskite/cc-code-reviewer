# 示例对话

本文件包含各种使用场景的完整示例，帮助理解交互流程和输出格式。

---

## 示例1：本地Maven单模块项目（lark-cli 已安装）

**注意**：以下示例展示了严格的单步交互节奏——每个回复只包含一个步骤的选项，等待用户回复后再进入下一步。

```
用户：帮我审查这个项目 /Users/jiangkun/Documents/github-kb/spring-ai-agent-utils

[第1次回复：预扫描 + 步骤1（审查模式）]
我：🔍 预扫描完成

   📂 项目：spring-ai-agent-utils
   - 来源：本地路径
   - 路径：/Users/jiangkun/Documents/github-kb/spring-ai-agent-utils
   - 类型：Maven 单模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：1 个（自动使用）

   📊 规模：
   - Java 文件（src/main/java）：42 个
   - 代码行数（src/main/java）：3,850 行

   🧩 技术栈扫描：
   - 识别数量：3
   - 启用专项规则：是

   | 技术栈 | 识别证据 | 建议维度 | 专项规则 |
   |--------|----------|----------|----------|
   | Spring Boot | spring-boot-starter-web | 3,5,8 | 启用 Spring Boot 规范、配置安全、运行时暴露检查 |
   | Spring MVC | spring-boot-starter-web | 1,3,5,8,15 | 启用 Controller/API、输入校验、错误响应和 REST 规范审查 |
   | Validation | spring-boot-starter-validation | 1,3,5,15 | 启用 Bean Validation、输入边界和 API 参数校验审查 |

   🔌 lark-cli：✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书上传

   🧩 项目 ignore：✅ 已启用：.cc-code-reviewer/ignore/issues.yml（已忽略 2 个问题）

   → AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
   → 用户选择: standard

[第2次回复：处理步骤2]
我：✅ 已选择：standard

   → AskUserQuestion: "检测到飞书上传能力可用，请选择审查结果的处理方式" [本地 Markdown 报告 | 上传到云文档 | 上传到多维表格 | 同时上传两者]
   → 用户选择: 同时上传两者

[第3次回复：处理步骤3]
我：✅ 已选择：同时上传两者

   → AskUserQuestion: "请选择本次审查入口" [增量审查 | 全量审查 | 指定模块]
   → 用户选择: 全量审查

[第4次回复：处理步骤4 + 步骤6确认]
我：✅ 已选择：全量审查

   Maven 单模块项目，跳过审查范围选择，自动使用「全量代码」。

   📋 执行计划：
   - 项目路径：/Users/jiangkun/Documents/github-kb/spring-ai-agent-utils
   - 项目类型：maven-single
   - 审查分支：main
   - 审查类型：存量审查
   - 审查范围：全量代码
   - 审查模式：standard
   - 启用维度：正确性、代码质量、Spring Boot 规范、数据库/数据访问、安全、性能、资源管理、日志/可观测性、测试质量(核心缺失)、技术债、架构、缓存(基础)、API设计(RESTful+错误处理+分页)
   - 飞书上传：同时上传两者

   → AskUserQuestion: "确认执行计划（步骤6）" [确认执行 | 取消]
   → 用户选择: 确认执行

[第5次回复：启动子agent]
我：🚀 正在启动独立代码审查子代理...

   📋 任务配置：standard 模式 · 存量审查 · 全量代码
   ⏱️ 预估耗时：8-15 分钟
   📌 子代理将独立执行完整审查流程，完成后自动返回结果。
   📤 审查完成后将自动上传到飞书（同时上传到云文档和多维表格），无需手动操作。
   💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。

   → 调用子agent执行代码审查（注入参数 + agent提示词）
   → 子agent执行审查 → 上传飞书云文档 → 创建多维表格 → 返回精简汇总

[子agent完成后]
我：✅ 代码审查已完成！⏱️ 耗时 12 分 35 秒

   📊 审查结果：8 个问题（P0: 1 / P1: 3 / P2: 4）
   🧩 项目 ignore 命中 2 条规则，过滤 5 个同类问题
   🔥 最高风险项：...
   📄 审查报告：https://...
   📋 问题清单：https://...
   💡 建议：...
```

---

## 示例2：Git仓库（Maven多模块，多分支，lark-cli 未安装）

```
用户：帮我审查这个项目 https://github.com/spring-ai-examples/spring-boot-multi-module.git

[第1次回复：预扫描 + 步骤1（分支选择）]
我：🔍 预扫描完成

   📂 项目：spring-boot-multi-module
   - 来源：Git仓库（已克隆）
   - 路径：/tmp/spring-boot-multi-module
   - 类型：Maven 多模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：3 个（需选择）

   📊 规模：
   - Java 文件（src/main/java）：186 个
   - 代码行数（src/main/java）：28,500 行
   - 模块数量：3 个
   - 模块列表：user-service(68类), order-service(72类), common-utils(46类)

   🧩 技术栈扫描：
   - 识别数量：5
   - 启用专项规则：是

   | 技术栈 | 识别证据 | 建议维度 | 专项规则 |
   |--------|----------|----------|----------|
   | Spring Boot | spring-boot-starter-web | 3,5,8 | 启用 Spring Boot 规范、配置安全、运行时暴露检查 |
   | MyBatis | mybatis-spring-boot-starter | 4,5,6 | 启用 MyBatis Mapper/XML、参数绑定、动态 SQL、分页和结果映射审查 |
   | Redis/Cache | spring-boot-starter-data-redis | 6,7,12,14 | 启用缓存穿透/击穿/雪崩、一致性、Redis key/连接池和分布式锁审查 |
   | Kafka | spring-kafka | 12,13 | 启用消息可靠性、消费者幂等、顺序性、重试和死信审查 |
   | Docker | 文件:Dockerfile | 3,5,7,8,12 | 启用镜像基础版本、运行用户、密钥注入、资源限制、健康检查和优雅停机审查 |

   🔌 lark-cli：⚠️ 飞书上传不可用：lark-cli命令未安装，报告将保存到本地文件

   → AskUserQuestion: "检测到 Git 仓库（当前分支：main），请选择要审查的分支" [main(当前) | develop | feature/auth]
   → 用户选择: develop

[第2次回复：切换分支 + 步骤1（审查模式）]
我：✅ 已切换到分支: develop

   → AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
   → 用户选择: deep

[第3次回复：步骤2（飞书上传跳过）]
我：✅ 已选择：deep

   飞书上传不可用，跳过飞书上传选项。

   → AskUserQuestion: "请选择本次审查入口" [增量审查 | 全量审查 | 指定模块]
   → 用户选择: 指定模块

[第4次回复：步骤4（多模块）]
我：✅ 已选择：指定模块

   → AskUserQuestion: "请选择本次希望 AI 扫描的模块" [全部模块 | 手动输入模块路径 | 前 5 个大模块]
   → 用户在 Other/free-form 输入: user-service, order-service

[第5次回复：步骤4B（审查方式）]
我：✅ 已选择：user-service, order-service

   → AskUserQuestion: "请选择存量审查方式" [按所选模块依次启动 | AI 智能规划分批]
   → 用户选择: 按所选模块依次启动

[第6次回复：步骤6确认]
我：✅ 已选择：按所选模块依次启动

   📋 执行计划：
   - 项目路径：/tmp/spring-boot-multi-module
   - 项目类型：maven-multi
   - 审查分支：develop
   - 审查类型：存量审查
   - 审查范围：user-service,order-service
   - 审查模式：deep
   - 启用维度：全量 15 维度
   - 飞书上传：飞书上传不可用

   → AskUserQuestion: "确认执行计划" [确认执行 | 取消]
   → 用户选择: 确认执行

[第7次回复：启动子agent]
我：🚀 正在启动独立代码审查子代理...

   📋 任务配置：deep 模式 · 存量审查 · user-service,order-service
   ⏱️ 预估耗时：30-45 分钟
   📌 子代理将独立执行完整审查流程，完成后自动返回结果。
   💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。

   → 调用子agent执行代码审查（注入参数 + agent提示词）
   → 子agent执行审查 → 返回完整审查报告

[子agent完成后]
📄 报告已保存到：/tmp/spring-boot-multi-module/code-review-report-spring-boot-multi-module-20260429-041231.md

（完整审查报告，包含所有章节）
```

---

## 示例3：大仓库分批扫描（交互式流程）

**注意**：当审查范围较大时（预估 token > 100,000 且为存量审查），自动触发分批扫描，多一个并发数选择步骤。

```
用户：帮我审查这个项目 /Users/jiangkun/Documents/github-kb/large-enterprise-app

[第1次回复：预扫描 + 步骤1（审查模式）]
我：🔍 预扫描完成

   📂 项目：large-enterprise-app
   - 来源：本地路径
   - 路径：/Users/jiangkun/Documents/github-kb/large-enterprise-app
   - 类型：Maven 多模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：1 个（自动使用）

   📊 规模：
   - Java 文件（src/main/java）：1,250 个
   - 代码行数（src/main/java）：185,000 行
   - 模块数量：6 个
   - 模块列表：user-service(320类), order-service(280类), payment-service(210类), inventory-service(190类), notification-service(150类), common-utils(100类)

   🧩 技术栈扫描：
   - 识别数量：7
   - 启用专项规则：是

   | 技术栈 | 识别证据 | 建议维度 | 专项规则 |
   |--------|----------|----------|----------|
   | Spring Boot | spring-boot-starter-web | 3,5,8 | 启用 Spring Boot 规范审查 |
   | MyBatis Plus | mybatis-plus-boot-starter | 4,5,6 | 启用 Wrapper、分页、批量操作审查 |
   | Redis/Cache | spring-boot-starter-data-redis | 6,7,12,14 | 启用缓存穿透/一致性审查 |
   | Kafka | spring-kafka | 12,13 | 启用消息可靠性审查 |
   | Spring Security | spring-boot-starter-security | 3,5,8,15 | 启用认证授权审查 |
   | Docker | 文件:Dockerfile | 3,5,7,8,12 | 启用镜像安全审查 |
   | Kubernetes | 文件:k8s/deployment.yaml | 3,5,7,8,12 | 启用探针、资源限制审查 |

   🔌 lark-cli：✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书上传

   → AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
   → 用户选择: standard

[第2次回复：步骤2（审查结果处理方式）]
我：✅ 已选择：standard

   → AskUserQuestion: "检测到飞书上传能力可用，请选择审查结果的处理方式" [本地 Markdown 报告 | 上传到云文档 | 上传到多维表格 | 同时上传两者]
   → 用户选择: 上传到云文档

[第3次回复：步骤3（审查入口）]
我：✅ 已选择：上传到云文档

   → AskUserQuestion: "请选择本次审查入口" [增量审查 | 全量审查 | 指定模块]
   → 用户选择: 全量审查

[第4次回复：步骤4（范围）]
我：✅ 已选择：全量审查

   📊 项目模块概览：
   large-enterprise-app/
   ├── user-service/        320 类 · 48,000 行
   ├── order-service/       280 类 · 42,000 行
   ├── payment-service/     210 类 · 31,500 行
   ├── inventory-service/   190 类 · 28,500 行
   ├── notification-service/ 150 类 · 22,500 行
   └── common-utils/        100 类 · 12,500 行

   合计：1,250 类 · 185,000 行

   全量审查已自动使用「全量代码」，跳过模块选择。

[第5次回复：步骤4B（审查方式）]
我：✅ 已选择：全量代码

   → AskUserQuestion: "请选择存量审查方式" [按所选模块依次启动 | AI 智能规划分批]
   → 用户选择: AI 智能规划分批

[第6次回复：步骤5（本轮执行批次 — 大仓库自动触发）]
我：✅ 已选择：AI 智能规划分批

   大仓库审查任务
   项目: large-enterprise-app
   模式: standard  范围: 全量代码  语义: jdtls-lsp
   批次数: 8  Java 行数: 185,000  Java 文件: 1,250

   | 批次 | 状态 | 行数 | 文件数 | 模块 |
   |------|------|------:|------:|------|
   | batch-001 | 待执行 | 28,400 | 310 | mes-server |
   | batch-002 | 待执行 | 27,900 | 295 | quality-server,material-server |
   | batch-003 | 待执行 | 26,800 | 276 | mall（部分） |

   本轮可执行批次: batch-001 batch-002 batch-003 batch-004 batch-005 batch-006 batch-007 batch-008
   也可以自行输入批次号，例如 batch-002,batch-004 或 2,4,7。

   推荐执行计划
   执行 3 批 最多 3 批 预估耗时: 串行约 75 分钟 / 2 路约 50 分钟 / 3 路约 25 分钟
   执行 5 批（推荐） 最多 5 批 预估耗时: 串行约 125 分钟 / 2 路约 75 分钟 / 3 路约 50 分钟
   执行全部 8 批 最多 8 批 预估耗时: 串行约 200 分钟 / 2 路约 100 分钟 / 3 路约 75 分钟

   → AskUserQuestion: "请选择本轮执行批次" [执行 3 批 | 执行 5 批（推荐） | 执行全部 8 批]
   → 用户选择: 执行 5 批（推荐）

[第6次回复：步骤5B（并发数选择）]
我：✅ 已选择：执行 5 批（推荐）

   📊 分批并行扫描

   本轮将执行：5 批
   总批次数：8 批
   生产代码行数：185,000 行

   → AskUserQuestion: "请选择并发扫描策略" [串行执行（默认） | 2 路并发 | 3 路并发]
   → 用户选择: 串行执行（默认）

[第7次回复：步骤6（确认执行计划）]
我：✅ 已选择：串行执行（默认）

   📋 执行计划：
   - 项目路径：/Users/jiangkun/Documents/github-kb/large-enterprise-app
   - 项目类型：maven-multi
   - 审查分支：main
   - 审查类型：存量审查
   - 审查范围：全量代码
   - 审查模式：standard
   - 启用维度：正确性、代码质量、Spring Boot 规范、数据库/数据访问、安全、性能、资源管理、日志/可观测性、测试质量(核心缺失)、技术债、架构、缓存(基础)、API设计(RESTful+错误处理+分页)
   - 飞书上传：上传到云文档
   - 扫描策略：分批并行扫描（本轮 5 / 总 8 批 / 1 路并发）
   - 预计耗时：约 125 分钟

   → AskUserQuestion: "确认执行计划" [确认执行 | 取消]
   → 用户选择: 确认执行

[第8次回复：启动分批并行扫描]
我：🚀 正在启动分批并行代码审查...

   📋 任务配置：standard 模式 · 存量审查 · 全量代码
   📊 扫描策略：本轮 5 / 总 8 批 / 1 路并发
   ⏱️ 预估耗时：约 125 分钟
   📌 本轮批次会先完成状态检查；如有失败或等待超时会生成合并阻塞报告，全部本轮批次完成后生成阶段性或完整合并报告。
   📤 审查完成后将自动上传到飞书（上传到云文档），无需手动操作。
   💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。

   → 轮次1：Agent(batch-001)
   → 轮次2：Agent(batch-002)
   → 轮次3：Agent(batch-003)
   → 轮次4：Agent(batch-004)
   → 轮次5：Agent(batch-005)
   → 检查 RUN_BATCH_IDS 状态 → 等待本轮 pending/running 批次终态 → 合并 completed 结果或生成合并阻塞报告 → 上传飞书

[全部完成后]
我：✅ 代码审查已完成！⏱️ 耗时 38 分 12 秒

   📊 扫描策略：分批并行扫描（本轮 5 / 总 8 批 / 1 路并发）
   📊 审查覆盖：本轮已完成批次生成阶段性报告；批次状态总览列出已纳入批次和遗留批次
   📊 审查结果：23 个问题（P0: 2 / P1: 7 / P2: 10 / P3: 4 / 待确认: 0）

   🔥 最高风险项：
     - P0-1: SQL 注入风险 — OrderMapper.xml:45
     - P0-2: 分布式事务未正确回滚 — PaymentServiceImpl.java:128

   📄 审查报告：https://...
   💡 建议：P0 问题需立即修复后再上线，SQL 注入和分布式事务风险较高。
   👉 详细报告请点击上方飞书链接查看。
```

## 示例4：Maven 大仓库可恢复分批审查

适用场景：Maven 多模块、存量审查、全量代码、Java 代码行数超过 `TOTAL_JAVA_LOC >= 120000`。

```text
用户：帮我审查 /repo/large-maven

[预扫描完成]
我：
🔍 预扫描完成

📂 项目：large-maven
- 类型：Maven 多模块

📊 规模：
- Java 文件（src/main/java）：4,000 个
- 代码行数（src/main/java）：500,000 行
- 模块数量：42 个

🧠 代码智能：✅ jdtls-lsp 可用，可用于跨目录调用链理解

→ AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
→ 用户选择：standard

→ AskUserQuestion: "检测到飞书上传能力可用，请选择审查结果的处理方式"
   [本地 Markdown 报告 | 上传到云文档 | 上传到多维表格 | 同时上传两者]
→ 用户选择：本地 Markdown 报告

→ AskUserQuestion: "请选择本次审查入口" [增量审查 | 全量审查 | 指定模块]
→ 用户选择：全量审查

→ AskUserQuestion: "请选择存量审查方式" [按所选模块依次启动 | AI 智能规划分批]
→ 用户选择：AI 智能规划分批

[进入 Maven 大仓库模式]
我：
📦 大仓库审查任务

Run ID: 20260528-143000-main-standard
项目: large-maven
模式: standard
范围: 全量代码
语义增强: jdtls-lsp
总规模: 500,000 行
批次: 20
完成: 0 / 20
Java 文件覆盖: 0 / 4,000 (0%)

| 批次 | 状态 | 行数 | 文件数 | 模块 |
|------|------|------:|------:|------|
| batch-001 | 待执行 | 28,400 | 310 | mes-server |
| batch-002 | 待执行 | 27,900 | 295 | quality-server,material-server |
| batch-003 | 待执行 | 26,800 | 276 | mall（部分） |

本轮可执行批次: batch-001 batch-002 batch-003 ... batch-020
也可以自行输入批次号，例如 batch-002,batch-004 或 2,4,7。

推荐执行计划
执行 3 批 最多 3 批 预估耗时: 串行约 75 分钟 / 2 路约 50 分钟 / 3 路约 25 分钟
执行 5 批（推荐） 最多 5 批 预估耗时: 串行约 125 分钟 / 2 路约 75 分钟 / 3 路约 50 分钟
执行 10 批 最多 10 批 预估耗时: 串行约 250 分钟 / 2 路约 125 分钟 / 3 路约 100 分钟
执行全部 20 批 最多 20 批 预估耗时: 串行约 500 分钟 / 2 路约 250 分钟 / 3 路约 175 分钟

→ AskUserQuestion: "请选择本轮执行批次"
   [执行 3 批 | 执行 5 批（推荐） | 执行 10 批 | 执行全部 20 批]
→ 用户选择：执行 5 批（推荐）

→ AskUserQuestion: "请选择并发扫描策略" [串行执行（默认） | 2 路并发 | 3 路并发]
→ 用户选择：串行执行（默认）

[本轮执行]
我：
🚀 正在启动 Maven 大仓库分批审查...
- 本轮执行：5 批
- 并发策略：1 路并发
- 已完成批次会自动跳过
- 每批完成后写入 results/batch-XXX.md 和 results/batch-XXX.status.json

[本轮结束]
我：
📄 阶段性报告已生成：
/repo/large-maven/.cc-code-reviewer/runs/20260528-143000-main-standard/final/code-review-report-large-maven-20260528-180000.md

📊 当前进度：
- 已完成：5 / 20 批
- Java 文件覆盖：1,000 / 4,000（25%）
- 报告包含批次状态总览：batch-001 ~ batch-005 已纳入本次合并，batch-006 ~ batch-020 未纳入本轮，遗留
- 未完成或未纳入本轮批次不会进入正式问题结论

[第二天继续]
用户：继续审查 /repo/large-maven

我：
📦 大仓库审查任务
- 读取已有 RUN_DIR
- 跳过已完成批次：batch-001 ~ batch-005
- 继续待执行或失败待重试批次

→ AskUserQuestion: "请选择本轮执行批次"
→ 用户选择：执行 5 批（推荐）

[全部批次完成后]
我：
✅ Maven 大仓库审查已完成
- 已完成：20 / 20 批
- Java 文件覆盖：4,000 / 4,000（100%）
- 完整报告已生成并按用户选择上传飞书或保存本地
```
