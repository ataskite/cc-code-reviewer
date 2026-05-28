# 示例对话

本文件包含各种使用场景的完整示例，帮助理解交互流程和输出格式。

---

## 示例1：本地Maven单模块项目（lark-cli 已安装）

**注意**：以下示例展示了严格的单步交互节奏——每个回复只包含一个步骤的选项，等待用户回复后再进入下一步。

```
用户：帮我审查这个项目 /Users/jiangkun/Documents/github-kb/spring-ai-agent-utils

[第1次回复：预扫描 + 步骤2（审查类型）]
我：🔍 预扫描完成

   📂 项目：spring-ai-agent-utils
   - 来源：本地路径
   - 路径：/Users/jiangkun/Documents/github-kb/spring-ai-agent-utils
   - 类型：Maven 单模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：1 个（自动使用）

   📊 规模：
   - Java 文件：42 个
   - 代码行数：3,850 行

   🧩 技术栈扫描：
   - 识别数量：3
   - 启用专项规则：是

   | 技术栈 | 识别证据 | 建议维度 | 专项规则 |
   |--------|----------|----------|----------|
   | Spring Boot | spring-boot-starter-web | 3,5,8 | 启用 Spring Boot 规范、配置安全、运行时暴露检查 |
   | Spring MVC | spring-boot-starter-web | 1,3,5,8,15 | 启用 Controller/API、输入校验、错误响应和 REST 规范审查 |
   | Validation | spring-boot-starter-validation | 1,3,5,15 | 启用 Bean Validation、输入边界和 API 参数校验审查 |

   🔌 lark-cli：✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书上传

   🧩 项目 ignore：✅ 已启用：.cc-code-reviewer/ignore/issues.yml

   → AskUserQuestion: "请选择审查类型" [增量审查 | 存量审查]
   → 用户选择: 存量审查

[第2次回复：处理步骤2 + 步骤3]
我：✅ 已选择：存量审查

   Maven 单模块项目，跳过审查范围选择，自动使用「全量代码」。

   → AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
   → 用户选择: standard

[第3次回复：处理步骤4 + 步骤5]
我：✅ 已选择：standard

   → AskUserQuestion: "检测到飞书上传能力可用，请选择审查结果的处理方式" [仅显示报告 | 上传到云文档 | 上传到多维表格 | 同时上传两者]
   → 用户选择: 同时上传两者

[第4次回复：处理步骤5 + 步骤7确认]
我：✅ 已选择：同时上传两者

   📋 执行计划：
   - 项目路径：/Users/jiangkun/Documents/github-kb/spring-ai-agent-utils
   - 项目类型：maven-single
   - 审查分支：main
   - 审查类型：存量审查
   - 审查范围：全量代码
   - 审查模式：standard
   - 启用维度：正确性、代码质量、Spring Boot 规范、数据库/数据访问、安全、性能、资源管理、日志/可观测性、测试质量(核心缺失)、技术债、架构、缓存(基础)、API设计(RESTful+错误处理+分页)
   - 飞书上传：同时上传两者

   → AskUserQuestion: "确认执行计划（步骤7）" [确认执行 | 取消]
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
   - Java 文件：186 个
   - 代码行数：28,500 行
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

[第2次回复：切换分支 + 步骤2（审查类型）]
我：✅ 已切换到分支: develop

   → AskUserQuestion: "请选择审查类型" [增量审查 | 存量审查]
   → 用户选择: 存量审查

[第3次回复：步骤3（多模块）]
我：✅ 已选择：存量审查

   → AskUserQuestion: "请选择要审查的模块（可多选）" [全量代码 | user-service | order-service | common-utils]
   → 用户选择: user-service, order-service

[第4次回复：步骤3确认 + 步骤4（审查模式）]
我：✅ 已选择：user-service, order-service

   → AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
   → 用户选择: deep

[第5次回复：步骤5（跳过）+ 步骤7确认]
我：✅ 已选择：deep

   飞书上传不可用，跳过飞书上传选项。

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

[第6次回复：启动子agent]
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

[第1次回复：预扫描 + 步骤2（审查类型）]
我：🔍 预扫描完成

   📂 项目：large-enterprise-app
   - 来源：本地路径
   - 路径：/Users/jiangkun/Documents/github-kb/large-enterprise-app
   - 类型：Maven 多模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：1 个（自动使用）

   📊 规模：
   - Java 文件：1,250 个
   - 代码行数：185,000 行
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

   → AskUserQuestion: "请选择审查类型" [增量审查 | 存量审查]
   → 用户选择: 存量审查

[第2次回复：步骤3（多模块）]
我：✅ 已选择：存量审查

   📊 项目模块概览：
   large-enterprise-app/
   ├── user-service/        320 类 · 48,000 行
   ├── order-service/       280 类 · 42,000 行
   ├── payment-service/     210 类 · 31,500 行
   ├── inventory-service/   190 类 · 28,500 行
   ├── notification-service/ 150 类 · 22,500 行
   └── common-utils/        100 类 · 12,500 行

   合计：1,250 类 · 185,000 行

   → AskUserQuestion: "请选择要审查的模块（可多选）" [全量代码 | user-service | order-service | ...]
   → 用户选择: 全量代码

[第3次回复：步骤4（审查模式）]
我：✅ 已选择：全量代码

   → AskUserQuestion: "请选择审查模式" [fast | standard | deep | security]
   → 用户选择: standard

[第4次回复：步骤5（飞书上传）]
我：✅ 已选择：standard

   → AskUserQuestion: "检测到飞书上传能力可用，请选择审查结果的处理方式" [仅显示报告 | 上传到云文档 | 上传到多维表格 | 同时上传两者]
   → 用户选择: 上传到云文档

[第5次回复：步骤6（并发数选择 — BATCH_MODE=true 自动触发）]
我：✅ 已选择：上传到云文档

   📊 大仓库分批扫描

   本次审查范围较大，将采用分批并行扫描：
   - 文件总数：1,250 个
   - 代码行数：185,000 行
   - 预计分批：8 批

   → AskUserQuestion: "请选择并发扫描策略" [串行执行 | 2 路并发（推荐） | 3 路并发]
   → 用户选择: 2 路并发（推荐）

[第6次回复：步骤7（确认执行计划）]
我：✅ 已选择：2 路并发

   📋 执行计划：
   - 项目路径：/Users/jiangkun/Documents/github-kb/large-enterprise-app
   - 项目类型：maven-multi
   - 审查分支：main
   - 审查类型：存量审查
   - 审查范围：全量代码
   - 审查模式：standard
   - 启用维度：正确性、代码质量、Spring Boot 规范、数据库/数据访问、安全、性能、资源管理、日志/可观测性、测试质量(核心缺失)、技术债、架构、缓存(基础)、API设计(RESTful+错误处理+分页)
   - 飞书上传：上传到云文档
   - 扫描策略：分批并行扫描（8 批 / 2 路并发）
   - 预计耗时：约 60 分钟

   → AskUserQuestion: "确认执行计划" [确认执行 | 取消]
   → 用户选择: 确认执行

[第7次回复：启动分批并行扫描]
我：🚀 正在启动分批并行代码审查...

   📋 任务配置：standard 模式 · 存量审查 · 全量代码
   📊 扫描策略：8 批 / 2 路并发
   ⏱️ 预估耗时：约 60 分钟
   📌 共 8 批次将按 2 路并发执行，全部完成后自动合并结果。
   📤 审查完成后将自动上传到飞书（上传到云文档），无需手动操作。
   💡 温馨提示：审查期间您可以输入 `/btw` 继续与本会话交互。

   → 轮次1：Agent(batch-1) + Agent(batch-2) 并行
   → 轮次2：Agent(batch-3) + Agent(batch-4) 并行
   → 轮次3：Agent(batch-5) + Agent(batch-6) 并行
   → 轮次4：Agent(batch-7) + Agent(batch-8) 并行
   → 读取 8 个 batch 文件 → 跨批去重 → 聚合同类问题 → 生成统一报告 → 上传飞书

[全部完成后]
我：✅ 代码审查已完成！⏱️ 耗时 38 分 12 秒

   📊 扫描策略：分批并行扫描（8 批 / 2 路并发）
   📊 审查覆盖：1,250/1,250 文件（185,000/185,000 行），覆盖率 100%
   📊 审查结果：23 个问题（P0: 2 / P1: 7 / P2: 10 / P3: 4 / 待确认: 0）

   🔥 最高风险项：
     - P0-1: SQL 注入风险 — OrderMapper.xml:45
     - P0-2: 分布式事务未正确回滚 — PaymentServiceImpl.java:128

   📄 审查报告：https://...
   💡 建议：P0 问题需立即修复后再上线，SQL 注入和分布式事务风险较高。
   👉 详细报告请点击上方飞书链接查看。
```
