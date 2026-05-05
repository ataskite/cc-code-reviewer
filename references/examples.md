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

[第4次回复：处理步骤5 + 步骤6确认]
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

   → AskUserQuestion: "确认执行计划" [确认执行 | 取消]
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

[第5次回复：步骤5（跳过）+ 步骤6确认]
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

## 示例3：快速启动模式（定时任务/自动化场景）

**注意**：快速启动模式下不进行任何交互式确认，参数校验通过后直接启动子agent。

```
用户：帮我审查 /path/to/spring-project --mode fast --type incremental --scope 3

[单次回复：预扫描 + 参数校验 + 直接启动]
我：🔍 预扫描完成

   📂 项目：spring-project
   - 来源：本地路径
   - 路径：/path/to/spring-project
   - 类型：Maven 单模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：1 个（自动使用）

   📊 规模：
   - Java 文件：42 个
   - 代码行数：3,200 行

   🧩 技术栈扫描：
   - 识别数量：0
   - 启用专项规则：否，仅启用通用 Java 审查规则
   - 未识别专项技术栈，仅启用通用 Java 审查规则。

   🔌 lark-cli：⚠️ 飞书上传不可用：缺少lark-doc或lark-base技能，报告将保存到本地文件

   ✅ 参数校验通过：
   - --mode fast → REVIEW_MODE=fast
   - --type incremental → REVIEW_TYPE=增量审查
   - --scope 3 → REVIEW_SCOPE=最近3次提交
   - --upload (未指定，默认no) → FEISHU_UPLOAD_OPTION=仅显示报告

   🚀 快速启动模式 — 正在启动独立代码审查子代理...

   📋 任务配置：fast 模式 · 增量审查 · 最近3次提交
   🌿 审查分支：main
   📤 飞书上传：仅显示报告
   ⏱️ 预估耗时：2-3 分钟
   📌 子代理将独立执行完整审查流程，完成后自动返回结果。

   → 调用子agent执行代码审查（注入参数 + agent提示词）

[子agent完成后]
我：✅ 代码审查已完成！⏱️ 耗时 2 分 18 秒

   📄 报告已保存到：/path/to/spring-project/code-review-report-spring-project-20260429-041231.md
   📊 审查结果：1 个问题（P0: 1 / P1: 0 / P2: 0 / P3: 0 / 待确认: 0）
   💡 建议：...
   （完整审查报告）
```

---

## 示例4：快速启动模式 — 参数校验失败

```
用户：帮我审查 /path/to/project --mode standard --type stock

我：🔍 预扫描完成

   📂 项目：project
   - 来源：本地路径
   - 路径：/path/to/project
   - 类型：Maven 多模块

   📊 规模：
   - Java 文件：186 个
   - 代码行数：28,500 行
   - 模块数量：3 个
   - 模块列表：user-service(68类), order-service(72类), common-utils(46类)

   🧩 技术栈扫描：
   - 识别数量：2
   - 启用专项规则：是

   | 技术栈 | 识别证据 | 建议维度 | 专项规则 |
   |--------|----------|----------|----------|
   | Spring MVC | spring-boot-starter-web | 1,3,5,8,15 | 启用 Controller/API、输入校验、错误响应和 REST 规范审查 |
   | JPA/Hibernate | spring-boot-starter-data-jpa | 4,5,6 | 启用 JPA Repository、实体映射、懒加载、N+1、事务边界和批量写入审查 |

   ❌ 快速启动参数校验失败

   缺少必填参数：
     - --scope: 审查范围（存量审查多模块项目时必填，可选值：full 或逗号分隔的 Maven 模块名称）

   非法参数值：
     无

   已识别参数：
     - 项目路径：/path/to/project
     - --mode: standard
     - --type: stock
     - --scope: 未提供
     - --branch: 未提供
     - --upload: 未提供，默认 no

   正确格式示例：
     帮我审查 /path/to/project --mode standard --type stock --scope full
     帮我审查 /path/to/project --mode standard --type stock --scope user-service,order-service

   请补充缺失参数后重新调用。
```

---

## 示例5：快速启动模式 — 指定分支 + 飞书上传

```
用户：帮我审查 https://github.com/org/repo.git --mode deep --type stock --scope full --branch develop --upload both

[单次回复：预扫描 + 参数校验 + 直接启动]
我：🔍 预扫描完成

   📂 项目：repo
   - 来源：Git仓库（已克隆）
   - 路径：/tmp/spring-boot-multi-module
   - 类型：Maven 多模块

   🌿 Git：
   - 当前分支：main
   - 可用分支：5 个（快速启动模式，自动切换到 develop）

   📊 规模：
   - Java 文件：186 个
   - 代码行数：28,500 行
   - 模块数量：3 个
   - 模块列表：user-service(68类), order-service(72类), common-utils(46类)

   🧩 技术栈扫描：
   - 识别数量：3
   - 启用专项规则：是

   | 技术栈 | 识别证据 | 建议维度 | 专项规则 |
   |--------|----------|----------|----------|
   | Spring Boot | spring-boot-starter-web | 3,5,8 | 启用 Spring Boot 规范、配置安全、运行时暴露检查 |
   | MyBatis Plus | mybatis-plus-boot-starter | 4,5,6 | 启用 MyBatis Plus Wrapper、分页插件、批量操作和逻辑删除审查 |
   | Spring Security | spring-boot-starter-security | 3,5,8,15 | 启用认证授权、对象级越权、CSRF、会话和安全配置审查 |

   🔌 lark-cli：✅ lark-cli 与 lark-doc/lark-base 技能可用，支持飞书上传

   ✅ 已切换到分支: develop

   ✅ 参数校验通过：
   - --mode deep → REVIEW_MODE=deep
   - --type stock → REVIEW_TYPE=存量审查
   - --scope full → REVIEW_SCOPE=全量代码
   - --branch develop → TARGET_BRANCH=develop
   - --upload both → FEISHU_UPLOAD_OPTION=同时上传两者

   🚀 快速启动模式 — 正在启动独立代码审查子代理...

   📋 任务配置：deep 模式 · 存量审查 · 全量代码
   🌿 审查分支：develop
   📤 飞书上传：同时上传两者
   ⏱️ 预估耗时：30-60 分钟
   📌 子代理将独立执行完整审查流程，完成后自动返回结果。

   → 调用子agent执行代码审查

[子agent完成后]
我：✅ 代码审查已完成！⏱️ 耗时 42 分 8 秒

   📊 审查结果：15 个问题（P0: 2 / P1: 5 / P2: 6 / 待确认: 2）
   🔥 最高风险项：
     - P0-1: SQL 注入风险 — OrderMapper.xml:45
     - P0-2: 事务失效导致数据不一致 — OrderServiceImpl.java:128
   📄 审查报告：https://...
   📋 问题清单：https://...
   💡 建议：P0 问题需立即修复后再上线，SQL 注入和数据一致性风险较高。
   👉 详细报告请点击上方飞书链接查看。
```
