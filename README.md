# cc-code-reviewer

> Claude Code / Codex / ZCode 三平台代码审查与修复插件 · Java、React/Vue/Node/TypeScript/JavaScript 与 Python（Django/FastAPI/通用 Python）代码审查 + 报告驱动修复

`cc-code-reviewer` 是一个面向工程团队的代码审查插件。统一入口同时支持 **Java**、**React/Vue2/Vue3/Node/TS/JS 前端族群**与 **Python（Django/FastAPI/通用 Python）**审查：先预扫描项目与语言，再通过结构化交互确认范围，最后生成可追踪的审查报告。Fix 阶段只消费人工确认后的问题清单，避免扫描和修复混在一起。

```mermaid
flowchart LR
    Input["项目路径 / Git 仓库"] --> Prescan["预扫描<br/>语言 / 分支 / 技术栈"]
    Prescan --> Gate["人工确认<br/>模式 / 范围 / 输出"]
    Gate --> Scan["Scan Agent<br/>Java / Frontend / Python"]
    Scan --> Report["审查报告"]
    Report --> Confirm["人工确认问题"]
    Confirm --> Fix["Fix<br/>修复 / 验证 / 写回"]
```

## 适用范围

| 语言 | 当前支持 | 说明 |
|------|----------|------|
| Java | Maven / Gradle / 常见企业 Java 项目 | 支持增量、全量、指定 Maven 模块、大仓库分批 |
| Frontend family | React、Vue 2.x、Vue 3.x、Node.js + TypeScript / JavaScript | 支持 Vite / Webpack / workspace/monorepo 的 package-local `src`；Vue2/Vue3 与 React 信号共存时按 Vue 优先仲裁，Vue2 legacy 按专项规则加强审查 |
| Python | Django / FastAPI / 通用 Python | 支持 src layout 与 flat layout；Django/FastAPI 专项规则；ORM N+1、反序列化 RCE、async 阻塞等 Python 高频事故点 |
| Mixed repo | Java + 前端 + Python 同仓 | 运行时选择一种语言；其他语言只作为背景，不产出正式问题 |

Next.js、Nuxt 和无 React/Vue/Node 信号的通用 TS/JS 仍会标记为不支持并停止，不会误套专项规则。

## 安装

同一 Git 仓库可被 Claude Code、Codex CLI/Desktop 和 ZCode 安装；三个原生清单共同发现根 `skills/` 唯一权威流程，并共享 `scripts/`、`references/`、`agents/`。平台差异限制在插件清单和运行时适配器（`runtime/`）。

### 前置条件

- macOS / Linux
- Bash 3.0+、`git`、系统自带 `perl`
- 已安装下列任一 Agent 产品：[Claude Code](https://claude.ai/code)、[Codex CLI/Desktop](https://chatgpt.com/codex) 或 [ZCode](https://zcode.z.ai)
- 可选：`lark-cli`，用于飞书云文档 / 多维表格输出与写回

### Claude Code

```bash
claude plugin marketplace add ataskite/cc-code-reviewer
claude plugin install cc-code-reviewer
```

安装或更新后，在 Claude Code 会话内执行：

```text
/reload-plugins
```

更新：

```bash
claude plugin update cc-code-reviewer@cc-code-reviewer
```

### Codex CLI / Desktop

```bash
codex plugin marketplace add ataskite/cc-code-reviewer
codex plugin add cc-code-reviewer@cc-code-reviewer
```

安装后开启新会话即可发现三个 Skill。Codex 插件主要面向 CLI/Desktop；IDE Extension 场景当前以项目级 Skill 降级说明为准，不承诺 IDE 插件安装。

### ZCode（Beta）

ZCode 插件体系仍为 Beta。通过 **Settings → Plugins → Marketplace** 添加同一 GitHub/Git source（`ataskite/cc-code-reviewer`），然后安装插件。ZCode 通过原生 `.zcode-plugin/plugin.json` 清单发现三个 Skill。

> Git 自定义 Marketplace 是 1.5.0 的正式分发路径；进入 ZCode 官方目录不作为发版阻塞项。

## 快速使用

### 代码审查

```text
/cc-code-reviewer:cc-code-reviewer /path/to/project
```

也可以使用 Git 仓库地址：

```text
/cc-code-reviewer:cc-code-reviewer https://github.com/org/repo.git
```

入口会先执行预扫描，再逐步询问分支、审查模式、报告保存方式、审查入口、范围、批次和最终确认。纯 Java / 纯前端会自动路由；混合仓库会让你选择本次审查目标语言。

### 报告驱动修复

```text
/cc-code-reviewer:cc-code-fixer /path/to/project
```

Fix 阶段只接受项目路径。待修复问题清单来源会在交互中收集，可来自本地 Markdown、飞书云文档或飞书多维表格。确认问题范围和输出目标后才开始修复。

### Ignore 规则维护

```text
/cc-code-reviewer:cc-code-ignore /path/to/project
```

用于把项目内反复出现的误报或特定设计约束沉淀到 `.cc-code-reviewer/ignore/issues.yml`。ignore 文件保存的是“同类问题跳过规则”，不是某次报告里的临时问题编号。

## 审查能力

### Java 审查

- 15 个审查维度：正确性、代码质量、异常处理、数据访问、安全、性能、资源管理、并发、缓存、消息队列、API 设计、架构、配置、测试、技术债等
- 技术栈感知：Spring Boot、MyBatis / MyBatis Plus、JPA/Hibernate、Redis、Kafka/RocketMQ、Spring Security 等
- 文件类型专项清单（v1.6.5）：`resolve-review-rules.sh` 按路径模式对命中文件叠加聚焦检查清单——pom.xml / mapper XML / Spring 与日志配置 / Dockerfile / CI workflow（Jenkinsfile、GitLab CI、GitHub Actions）/ npm package.json 等 11 类（清单文档 content 内嵌注入，逐文件第一命中唯一分组）；文件级分批与单 Agent 路由全量可达，Maven 大仓模块分批路由仅覆盖模块内命中路径
- Maven 多模块大仓库：支持 `module-sequential` 和 `ai-planned` 分批，批次可恢复，合并报告区分阶段性/完整
- 续跑准入门禁（v1.6.5）：恢复未完成 RUN_DIR 前必须先执行 `validate-resume-input.sh <RUN_DIR> <PROJECT_DIR> --rules` 校验冻结输入与规则快照未被改动；仅 `GATE_OK=<run_id>` 放行，`INPUT_CHANGED` / `RULES_CHANGED` / `FROZEN_INPUT_MISSING` 一律 fail-closed——禁止列出可调度批次，由用户确认重新规划并新建 RUN_DIR
- 批次失败归因（v1.6.5）：失败批次状态 JSON 写入五值封闭 `failure_class` 枚举（`failed` / `partial` 必填、判不准写 `unknown`、`completed` 禁带）；批次表错误列显示 `[短标签] 原error` 前缀，`summary.json` 新增 `failed_by_class` 归因对象并输出「失败归因」统计行与分类重试提示
- partial 部分完成批次（v1.6.4）：批次中断但已产出发现时写入 partial 状态；合并纳入其发现但覆盖保守不计，报告保持阶段性，批次可整批重跑
- Maven 多模块小仓库：按当前审查范围计算规模；`estimated_tokens <= 1000000` 时跳过分批方式选择，只有严格大于 100 万才开启分批
- Maven 大仓依赖图亲和分批（v1.6.0）：有依赖边的模块装箱时 cost 容差放宽 15%，相关模块优先同批
- Java 覆盖率口径固定为 `src/main/java` 生产源码，测试源码只作为上下文
- 安全设计不变量审查：脚本只按 import/直接依赖组织关联代码，大模型从代码行为识别受保护动作、授权证据、完整状态空间和默认路径，不依赖预置类名、方法名或字段名词表

### 发现清单自校验（v1.6.0）

三个审查 agent（Java / Frontend / Python）在生成报告前执行两轮自校验，吸收阿里 OpenCodeReview 的反思两阶段思想：

- **行号回抽校验（RE_LOCATION）**：对带 `file:line` 的发现，用 Read 回抽 ±3 行验证证据代码真实存在；漂移则修正，缺失则降级为待确认项
- **证伪式过滤（REVIEW_FILTER）**：只删当前可见证据能直接证伪的误报，凡需 diff 外信息才能判定的评论一律放行
- **跨文件重归档（v1.6.4）**：声明文件中找不到的证据代码，若在审查范围内逐行唯一命中另一文件，把位置（文件+行号）整体迁移到真实位置；合并阶段还会对纳入批次自动执行同一重归档（fail-open，多命中绝不猜测）
- **组内次要文件覆盖义务（v1.6.4）**：批次结果必须以 `## 覆盖情况` 逐文件披露已审 N/M 与跳过原因，次要文件不得静默跳过
- **fail-open**：自校验失败的问题保留原状，只会让结果变好或不变，绝不会让结果变没

### 增量对照与输出增强（v1.6.6）

- 增量重复抑制：增量审查可选择对照上一份本地 Markdown 报告，同文件 + 同维度 + 行区间 IoU > 0.6 的发现标题追加「上轮已报」标记（fail-open，只标记不删除）
- 业务背景注入：最终确认可选「附业务背景」，自定义文本或默认使用所审提交的 commit message（≤8000 字符）注入三个审查 agent，辅助判断变更是有意为之还是缺陷
- SARIF 导出：报告保存方式新增「SARIF 文件（本地 .sarif，CI 对接）」，在本地 Markdown 报告旁生成同名 `.sarif`（P0→error / P1→warning / 其余→note，指纹与跨批次去重同源），可直接接入 GitHub Code Scanning 等 CI 平台

### Frontend Family 审查

- 12 个前端维度：正确性、类型安全、组件边界、框架规范、状态与数据请求、安全、性能、副作用与资源清理、可访问性、测试质量、API/错误处理、设计系统一致性（仅 deep）
- React TS/JS 支持：可识别 `.tsx/.jsx`，也支持有 React import / `createElement` 证据的 `.ts/.js`
- Vue 支持：识别 Vue 2.x / Vue 3.x 和 `.vue` SFC，信号覆盖 `vue@2/3`、`vue-template-compiler`、`@vue/cli-service`、`@vitejs/plugin-vue`、`pinia`、`vue-router@3/4`、`vue-loader` 版本、`vite-plugin-vue2` 等；无版本锁定时按 `createApp(` / `new Vue(` 等内容信号判版本；React/Vue 信号共存时按 Vue 优先；Vue2 legacy 重点检查 Options API、响应式限制、mixin 全局污染、filter 迁移债、Vuex 3、Vue Router 3、事件总线和生命周期清理
- Node 支持：识别 `package.json` 的 `type`、`main`/`exports`、`engines.node`、Express/Koa/Fastify 等服务端信号
- 正式源码范围：只统计受支持 package 的 `src` 下生产 `.ts/.tsx/.js/.jsx/.vue/.mjs/.cjs`，排除测试、构建产物、配置脚本、`.d.ts`
- Monorepo 范围选择：`src/components` 或 `components` 会匹配所有前端族群 package-local `*/src/components/`；`apps/web/src/components` 只匹配指定 package
- TypeScript LSP 可用时用于语义增强；不可用时降级到 import graph + 配置 + 文本检索

## 审查模式

| 模式 | 输出边界 | 适用场景 |
|------|----------|----------|
| `fast` | 仅输出 P0（且必须满足全部 P0 硬门槛） | PR 合并前快速卡口 |
| `standard` | 日常核心维度 | 常规迭代上线 |
| `deep` | 全量维度 | 大版本发布前、重要模块审查 |
| `security` | 安全核心 + 强相关交叉维度 | 安全合规、上线前安全检查 |

P0 必须同时满足：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。`fast` 模式不会输出 P1/P2/P3 或待确认项。高危安全问题满足前四项时必为 P0，不得以触发概率低、触发条件非攻击者可控为由降级；认证/鉴权路径上的 fail-open 按认证绕过定级，仓库内代码链完整即视为生产可达且证据完整。

## 审查范围

| 入口 | Java | Frontend |
|------|------|----------|
| 增量审查 | 最近 N 次提交的变更及必要关联上下文 | 最近 N 次提交的前端变更及必要关联上下文 |
| 全量审查 | 全部 `src/main/java` 生产源码 | 全部受支持 package-local `src` 生产源码 |
| 指定模块 | Maven 模块相对路径 | `src` 顶层目录或 package-local `src` 子目录 |

范围选择会在分批、覆盖率、报告和子 agent 参数中保持一致。前端指定目录通过不可变 source manifest 收敛，不会误扫测试文件或构建产物。

单 Agent 与分批 Agent 都接收同一冻结输入派生的关联审查单元。关联单元只保持跨文件语义上下文，不预判风险，也不改变正式扫描边界。

所有受支持模型统一按 1M 上下文分批。文件级 planner 默认使用 500k token 输入预算，并通过 First-Fit Decreasing 回填已有批次；可用 `CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET` 显式调整文件批次预算。

增量审查在冻结输入后自动生成语义分组清单（同模块同功能、接口+实现+调用点、测试+被测、i18n/配置变体、rename 对应物）：单 agent 审查按组组织上下文，文件级分批按组做亲和装箱（预算硬限制优先）。分组只依据输入元数据、不确定即跳过，不改变审查范围。

## 输出

- 本地 Markdown 审查报告：`code-review-report-{PROJECT}-{YYYYMMDD-HHmmss}.md`
- 不可变审查输入：`review-input.json` 固化 Git 基准、选中/排除文件、变更类型和内容指纹
- 运行覆盖清单：`run-manifest.json` 固化每个计划文件的 completed / failed / leftover 状态；文件路径统一为仓库相对路径，`item_id` 由稳定仓库身份、语言和相对路径生成，跨 clone/workspace 保持一致，同时提供分组覆盖集合、失败分类、终态和输入模式；不从 Markdown 反推覆盖率
- 默认源码排除：`__snapshots__`、`testdata`、`fixtures` 与常见生成文件不进入正式源码分母，Java 规划和清单保持同一口径
- 本地 Markdown 修复报告：`fix-report-{PROJECT}-{YYYYMMDD-HHmmss}.md`
- 可选飞书云文档：使用 Markdown 一级标题作为云文档标题
- 可选飞书多维表格：按扫描/修复阶段字段契约写入和更新
- 分批合并报告：支持 `[阶段性]` 与 `[合并阻塞]` 标题，明确已纳入批次、遗留批次和覆盖率；合并前对纳入批次自动执行跨文件重归档（fail-open），partial 批次发现标注入纳但报告保持阶段性
- 跨批次指纹去重（v1.6.5）：合并时按 文件路径 ␀ 维度标签 ␀ 归一化证据行 的 sha256 内容指纹（即按文件 × 维度 × 证据代码）确定性合并措辞漂移的重复发现；证据归一与跨文件重归档同口径，路径按原字节保留，行号与措辞不入键，无文件行且无闭合围栏的块退回整块折叠键兜底；`summary.json` 的 `dedup` 对象与报告「跨批次去重」行披露统计
- SARIF 导出（v1.6.6）：报告保存方式勾选「SARIF 文件（本地 .sarif，CI 对接）」时，在本地 Markdown 报告同目录生成同名 `.sarif`（P0→error / P1→warning / 其余→note；指纹与跨批次去重同源）；仅本地导出，与飞书上传互不影响

## 项目级审查规则

`.cc-code-reviewer/review-rules.yml` 用于为路径附加审查重点，不会像 ignore 规则一样隐藏发现。它以确定性 glob 匹配并写入本轮 `review-rules.json`，供当前批次 Agent 读取：

```yaml
version: 1
rules:
  - name: api-boundary
    paths:
      - "**/controller/**"
    instruction: "核对鉴权、输入校验和错误契约"
    merge_language_rule: true
```

关联文件分批只使用直接相对 import、Python 同包 import 与无歧义 Java class import；无法可靠识别关联时保留单文件单元，不猜测框架语义。

## 架构

![cc-code-reviewer 架构总览](docs/assets/architecture-overview.png)

插件采用 skill-only 入口和专属子 agent，三端共享同一审查内核：

- `skills/cc-code-reviewer`：Scan 编排、预扫描、交互确认、批次调度、飞书输出
- `agents/cc-code-reviewer`：Java 审查执行，只保存本地报告，不上传飞书
- `agents/cc-code-reviewer-frontend`：React/Vue2/Vue3/Node/TS/JS 前端族群审查执行
- `agents/cc-code-reviewer-python`：Django/FastAPI/通用 Python 审查执行
- `skills/cc-code-fixer`：读取确认后的问题清单，执行修复、验证、报告和写回
- `skills/cc-code-ignore`：维护项目级 ignore 规则
- `scripts/core`：语言无关内核，负责项目获取、Git、固定 1M 分批、合并和状态展示
- `scripts/languages/java` / `scripts/languages/frontend` / `scripts/languages/python`：语言适配器，负责预扫描、源码边界和语言专属能力探测
- `runtime/`：三端运行时适配器（`contract.md` 平台无关契约 + `claude-code.md` / `codex.md` / `zcode.md` 平台映射），定义 `PLUGIN_ROOT`、人工确认、模型档位和子 Agent 调度
- `.claude-plugin/` / `.codex-plugin/` / `.zcode-plugin/` / `.agents/plugins/`：三端插件清单；版本化 plugin manifest 由 `VERSION` 驱动，Codex marketplace 通过 local source 读取 plugin version

## 详细文档

| 文档 | 说明 |
|------|------|
| [Java 审查框架](references/languages/java/review-framework.md) | Java 15 维度、技术栈规则、模式矩阵 |
| [Frontend 审查框架](references/languages/frontend/review-framework.md) | 前端 12 维度（维度 12 设计系统一致性仅 deep）、模式矩阵、P0 门槛 |
| [Python 审查框架](references/languages/python/review-framework.md) | Python 12 维度、技术栈规则（Django/FastAPI/SQLAlchemy/Celery）、模式矩阵、P0 门槛 |
| [React 专项规则](references/languages/frontend/react-rules.md) | React / Router / 构建配置专项审查规则 |
| [Vue 专项规则](references/languages/frontend/vue-rules.md) | Vue2 legacy / Vue3 / Router / Vuex / Pinia 专项审查规则 |
| [Node 专项规则](references/languages/frontend/node-rules.md) | Node runtime / HTTP API / BFF / 模块系统专项审查规则 |
| [Django 专项规则](references/languages/python/django-rules.md) | Django ORM / middleware / signals / admin / CSRF / migration 专项审查规则 |
| [FastAPI 专项规则](references/languages/python/fastapi-rules.md) | FastAPI DI / Pydantic / async / OpenAPI 专项审查规则 |
| [源码范围契约](references/languages/frontend/source-scope.md) | 前端正式源码、上下文和排除项 |
| [Python 源码范围契约](references/languages/python/source-scope.md) | Python 正式源码、上下文和排除项 |
| [语言适配器契约](references/language-adapter-contract.md) | Java / Frontend / Python 与共享内核之间的 PROFILE_SCHEMA |
| [报告格式](references/report-format.md) | Scan 报告结构化输出规范 |
| [飞书集成](references/feishu-integration.md) | Scan 阶段云文档和多维表格输出 |
| [Fix 工作流](references/fix-workflow.md) | 修复阶段输入、范围确认、执行路线和写回规则 |
| [Fix 报告格式](references/fix-report-format.md) | 修复报告结构化输出规范 |
| [Fix 飞书集成](references/fix-feishu-integration.md) | 修复阶段飞书读取、写回和降级规则 |
| [Ignore 规则](references/ignore-workflow.md) | 项目级 ignore 文件格式与维护流程 |
| [示例对话](references/examples.md) | Scan / Fix / Ignore 使用示例 |

## License

MIT
