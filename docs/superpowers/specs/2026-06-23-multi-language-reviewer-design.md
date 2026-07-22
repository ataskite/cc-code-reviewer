# cc-code-reviewer 多语言扩展与前端审查设计

**日期**：2026-06-23  
**状态**：已批准（本文保留首期历史边界；当前实现状态见下）
**首期范围**：统一入口、多语言扩展内核、TypeScript/JavaScript + React Scan  
**后续顺序**：Vue → Python；前端 Fix 在 Scan 稳定后单独设计

> **1.5.0 实现状态（2026-07-22）**：统一入口现已正式支持 Java、前端族群（React/Vue2/Vue3/Node/TS/JS）和 Python（Django/FastAPI/通用 Python）。下文的“首期”“非目标”和阶段顺序保留为历史设计决策，不再代表当前支持范围。

## 1. 背景

`cc-code-reviewer` 当前是面向企业级 Java 项目的 Claude Code 插件。Java 假设已经进入项目识别、源码统计、技术栈探测、代码智能、分批规划、文件覆盖率、审查维度、Agent 提示词、报告以及契约测试。

本次扩展不采用三个独立项目，也不把前端规则直接追加到现有 Java 流程。目标是在同一仓库和统一入口下建立语言无关的审查内核，由独立语言适配器承载 Java、前端和未来 Python 的差异。

## 2. 已确认决策

1. 保持单仓库和统一入口 `/cc-code-reviewer:cc-code-reviewer`。
2. 纯语言仓库自动选择对应适配器；混合仓库识别所有候选语言，但一次运行只审查一种语言。
3. 首期前端范围是 TypeScript/JavaScript + React + Vite/Webpack + npm/pnpm/yarn。
4. React 稳定后增加 Vue，再进入 Python 的独立设计周期。
5. 前端首期只完成 Scan 闭环；报告驱动 Fix 后置。
6. TypeScript LSP 是可选语义增强，不是运行前置条件；不可用时必须明确降级。
7. Java 行为先冻结，通过兼容桥接逐步迁移，不能以多语言改造为由削弱已有大仓库能力。

## 3. 目标与非目标

### 3.1 目标

- 将语言识别、源码口径、技术栈规则、语义工具、审查维度和 Agent 提示词从公共流程中解耦。
- 复用 Git 范围、交互门禁、批次运行、状态恢复、覆盖率、结果合并、Ignore、报告和飞书输出。
- 建立可被 Java、React、Vue 和 Python 共同实现的稳定 Language Adapter Contract。
- 交付可用于真实 React 项目的增量/存量审查、分批执行、覆盖率、Ignore 和结构化报告。
- 保持现有 Java Scan 与 Fix 的用户可见契约。

### 3.2 非目标

- 首期不实现 Vue、Next.js、Nuxt、Node/BFF 或 Python 审查。
- 首期不让一次运行同时审查并合并多种语言。
- 首期不为前端接入报告驱动 Fix。
- 不一次性重写或搬迁全部 Java 脚本。
- 不自动执行 `npm install`、包管理器脚本、项目构建或应用代码。

## 4. 方案选择

### 4.1 采用：共享内核 + 独立语言适配器

```text
统一入口 cc-code-reviewer
          |
          v
+---------------------------+
| 项目与语言探测            |
| Java / Frontend / Python  |
+-------------+-------------+
              |
       混合仓库选择一种语言
              |
              v
+-----------------------------------------+
|              共享审查内核               |
| Git范围 | 交互门禁 | 批次运行 | 状态恢复 |
| 覆盖率  | 合并去重 | Ignore   | 报告/飞书 |
+-------------------+---------------------+
                    |
          Language Adapter Contract
                    |
      +-------------+-------------+
      |                           |
      v                           v
+-------------------+     +-----------------------+
| Java Adapter      |     | Frontend Adapter      |
| Maven/Gradle      |     | TS/JS + React         |
| src/main/java     |     | src + 构建配置         |
| jdtls-lsp         |     | TypeScript LSP        |
| Java审查矩阵      |     | 前端审查矩阵          |
| 现有流程兼容桥接  |     | React专项规则         |
+-------------------+     +-----------------------+
```

### 4.2 未采用：同仓库并行三套流程

该方案可以更快绕开 Java，但会复制交互、批次、Ignore、覆盖率、合并和报告逻辑，长期维护成本接近三个独立项目。

### 4.3 未采用：先重写通用框架再迁移 Java

该方案结构整齐，但前端价值交付最晚，而且会同时扰动已经稳定的 Java 大仓库、覆盖率和合并门禁契约。

## 5. 架构和目录边界

新结构旁路接入，现有 Java 文件在迁移前保留原路径：

```text
cc-code-reviewer/
├── skills/
│   └── cc-code-reviewer/SKILL.md       # 统一入口与交互编排
├── agents/
│   ├── cc-code-reviewer.md             # 现有 Java Agent，暂不改名
│   └── cc-code-reviewer-frontend.md    # 前端专属 Agent
├── scripts/
│   ├── core/
│   │   ├── detect-language.sh          # 候选语言识别
│   │   ├── validate-scope.sh           # 通用路径边界校验
│   │   ├── plan-file-batches.sh        # 通用文件批次规划
│   │   └── merge-batch-results.sh      # 通用状态门禁、去重与合并
│   ├── languages/
│   │   ├── java/                       # Java 兼容桥与逐步迁入代码
│   │   └── frontend/
│   │       ├── detect-project.sh
│   │       ├── scan-project.sh
│   │       ├── detect-code-intelligence.sh
│   │       └── collect-source-files.sh
│   └── phase*.sh                       # 现有 Java 脚本暂时保留
├── references/
│   ├── language-adapter-contract.md
│   ├── shared-review-framework.md
│   └── languages/
│       ├── java/review-framework.md
│       └── frontend/
│           ├── source-scope.md
│           ├── review-framework.md
│           └── react-rules.md
└── tests/
    ├── contract/
    ├── java/
    └── frontend/
```

### 5.1 共享内核职责

- 项目获取、Git 分支与增量范围。
- 结构化交互和最终确认。
- 标准化 source manifest、批次状态和结果契约。
- 批次选择、并发编排、恢复、等待和失败门禁。
- 文件覆盖率、确定性去重和阶段性/完整报告判断。
- Ignore 规则加载、报告持久化和飞书输出。

共享内核不得解析 Maven、`package.json`，也不得包含 Spring、React、Django 等专项规则。

### 5.2 语言适配器职责

- 识别项目类型、框架、构建器、包管理器和 workspace。
- 定义正式源码、只读上下文、排除项和生成代码。
- 统计组件、文件、行数和批次成本。
- 探测语言语义工具并定义可靠的静态降级路径。
- 提供语言审查维度、框架专项规则和 Agent。
- 将语言专属数据映射到公共协议。

## 6. Language Adapter Contract

预扫描采用版本化的标准输出协议。第一版至少包含：

```text
PROFILE_SCHEMA_VERSION=1
LANGUAGE_ID=frontend
PROJECT_TYPE=frontend-react
SOURCE_FILE_COUNT=318
SOURCE_LINE_COUNT=42680
FORMAL_CONFIG_FILE_COUNT=7
CODE_INTELLIGENCE_PROVIDER=typescript-lsp
CODE_INTELLIGENCE_AVAILABLE=true

COMPONENT:app|src/app|126|18200
TECH_STACK:React|dependency:react@19|rules:react
SOURCE_SCOPE:formal|src/**/*.tsx
SOURCE_SCOPE:context|**/*.test.tsx
SOURCE_SCOPE:excluded|node_modules/**
```

约束：

- `PROFILE_SCHEMA_VERSION` 不匹配时必须停止，不得猜测解析。
- `LANGUAGE_ID` 在一次运行中不可变。
- `SOURCE_FILE_COUNT` 只统计生产源码，且必须与覆盖率分母来自同一份不可变 source manifest。
- `FORMAL_CONFIG_FILE_COUNT` 单独记录可产生正式问题的配置文件，不进入源码文件覆盖率分母，避免把源码和配置混成多个覆盖指标。
- 公共层使用 `source_file_count` 等中性概念；Java 兼容输出可暂时保留 `selected_java_file_count` 等别名。
- `COMPONENT`、`TECH_STACK` 和 `SOURCE_SCOPE` 可以重复出现，公共层只负责保存和展示，不解释框架语义。

### 6.1 首期候选语言识别

- Java 候选继续按 Maven、Gradle 或 Java 源文件识别，保持现有判断兼容。
- React 候选必须有 `package.json` 中的 React 依赖证据，并存在 `.tsx`、`.jsx` 或可确认的 React 入口；不能仅凭仓库存在 `package.json` 判定为前端项目。
- workspace/monorepo 按 package 边界收集 React 候选，根目录只负责聚合，不把所有 JavaScript 文件自动纳入正式范围。
- 检测到 Next.js、Nuxt、Node/BFF 或不含 React 的通用 TS/JS 项目时，预扫描必须标记为首期不支持并停止，不能套用 React 规则生成报告。
- 同时存在 Java 和 React 候选时进入一次语言选择；用户选择后，另一语言只能作为仓库背景，不能成为正式问题来源。

## 7. 前端正式审查范围

### 7.1 正式问题范围

- `src` 及适配器确认的应用源码目录内的 `.ts`、`.tsx`、`.js`、`.jsx`。
- React 组件、Hooks、状态管理、路由和数据请求代码。
- `package.json`、TypeScript 配置、Vite/Webpack 配置、路由配置及非敏感环境配置模板。

报告只展示一个“前端源码文件覆盖率”，分母是生产 `.ts/.tsx/.js/.jsx` 文件。上述正式配置文件可以产生问题，但单独记录数量，不进入该覆盖率分母；这与 Java 当前只统计生产 Java 文件覆盖率的口径一致。

### 7.2 只读上下文

- 单元测试、组件测试和端到端测试。
- 类型声明文件。
- lockfile，用于依赖版本证据，不作为正式源码覆盖率分母。
- 生成代码，但仅在理解调用关系确有必要时读取。

测试文件只用于判断核心逻辑或关键路径是否缺少测试，不在测试代码中输出正式问题，也不计入正式文件覆盖率。

### 7.3 默认排除

- `node_modules`、`dist`、`build`、coverage 产物和缓存目录。
- 压缩、压缩映射、vendor 和自动生成文件。
- 经项目 Ignore 或适配器规则确认的生成目录。

## 8. 审查维度模型

公共层定义稳定 ID，不硬编码某种语言的展示名称：

```text
D01_CORRECTNESS
D02_MAINTAINABILITY
D03_PLATFORM_PRACTICES
D04_DATA_STATE
D05_SECURITY
D06_PERFORMANCE
D07_RESOURCE_LIFECYCLE
D08_OBSERVABILITY
D09_TESTING
D10_TECH_DEBT
D11_ARCHITECTURE
D12_DISTRIBUTED_INTEGRATION
D13_ASYNC_EVENTS
D14_CACHE_CONSISTENCY
D15_INTERFACE_CONTRACT
```

语言适配器将公共 ID 映射为语言名称。例如，`D03` 在 Java 中继续展示为 Spring Boot 规范，在前端中展示为 React Hooks、渲染与组件规范；`D04` 在 Java 中是数据库与数据访问，在前端中是状态管理与数据请求。

Java 报告继续使用原有用户可见名称。公共 ID 用于内核、Ignore、合并和未来扩展，不要求所有语言使用完全相同的具体规则。

## 9. React MVP 审查重点

- Hooks 依赖、陈旧闭包、生命周期清理和重复渲染。
- 类型逃逸、空值边界、Promise 处理和异步竞态。
- 状态归属、数据请求、加载/错误状态和缓存失效。
- XSS、危险 HTML、前端凭据、开放重定向和不安全 URL。
- Bundle、懒加载、列表渲染和不必要的重计算。
- Event listener、timer、订阅和请求取消。
- Error Boundary、关键错误观测和用户可恢复错误。
- 组件边界、循环依赖、跨层引用和公共组件滥用。
- 可访问性、表单标签、键盘操作和语义化结构。

依赖风险只有在版本明确且证据可靠时才能形成确定性漏洞结论；否则必须归为待确认或依赖扫描建议。

## 10. 执行数据流

```text
用户输入项目路径
        |
        v
获取项目 + Git/分支探测
        |
        v
语言探测
Java + Frontend? ---> 用户选择一种
        |
        v
Frontend Adapter 预扫描
        |
        v
统一预扫描摘要
        |
        v
模式 -> 模型 -> 报告 -> 增量/存量 -> 范围 -> 确认
        |
        v
生成不可变 source manifest
        |
        v
按文件成本和组件边界规划批次
        |
        v
Frontend Agent
├── TypeScript LSP：定义/引用/调用关系
└── 静态降级：import graph + 配置 + 文本检索
        |
        v
批次状态门禁 -> 确定性去重 -> 覆盖率 -> 报告/飞书
```

## 11. 失败、降级与安全边界

- TypeScript LSP 不可用时允许审查，但预扫描和报告必须披露降级。
- LSP 在批次执行中失败时，可以回退静态分析，并记录失败能力和影响范围。
- 未找到正式源码时停止执行，不生成“零问题”报告。
- 混合仓库的正式问题不得越过用户选择的语言和目标目录。
- 单批失败、超时、结果缺失或未终止时阻止完整合并。
- 适配器不得自动安装依赖、执行 package scripts、构建项目或运行应用。
- 所有用户输入的模块、package 和目录必须经过项目根目录边界校验，拒绝绝对路径、`..` 和解析后逃逸路径。
- 生成代码、测试和上下文文件不得计入正式覆盖率，也不得成为正式问题位置。

## 12. 分阶段 Roadmap

### Phase 0：锁定 Java 基线

- 为 Java 预扫描、范围、批次、覆盖率、合并和报告建立契约快照。
- 明确 Java 专属字段及公共字段映射。
- 增加混合仓库测试样例。
- 保持现有入口、交互顺序、报告和 Fix 不变。

验收：完整测试通过；Java 用户可见输出无非预期变化；文件覆盖率、批次门禁和 Feishu 标题契约保持不变。

### Phase 1：建立语言扩展内核

- 新增语言探测和混合仓库选择。
- 定义统一预扫描、源码范围和语义能力协议。
- 建立通用 source manifest。
- 抽取路径校验、文件批次、状态机、覆盖率和合并接口。
- Java 通过兼容桥继续调用现有实现。

验收：纯语言仓库自动路由；混合仓库必须选择一种语言；公共内核无语言或框架判断；新增适配器不修改公共状态机。

### Phase 2：React 小仓库纵向闭环

- 支持 TS/JS、React、Vite/Webpack、npm/pnpm/yarn。
- 支持正式源码、测试上下文和生成目录排除。
- 新增前端审查矩阵、React 规则和 Frontend Agent。
- 接入统一交互、增量/存量、Ignore 和本地报告。
- 接入可选 TypeScript LSP 与静态降级。

验收：React TypeScript 和 JavaScript 样例均可完成审查；正式问题不落在测试或构建产物；报告披露范围、覆盖率和语义状态；Java 无回归。

### Phase 3：React 大项目与交付闭环

- 按 workspace/package、路由和组件边界规划批次。
- 支持上下文缩放、批次选择、并发、恢复和阶段性报告。
- 接入确定性去重、完整合并门禁和 Feishu 输出。
- 完善 React 专项规则和误报治理。

验收：覆盖率分母来自不可变 manifest；失败或缺失批次不能生成完整报告；批次结果不越过 `scan_roots`；支持跨会话恢复；Ignore 不保存临时问题编号。

### Phase 4：Java 公共能力迁移

按语言探测、source manifest、通用文件批次、通用覆盖率、通用合并状态机、通用报告元数据的顺序逐项迁移。Maven 多模块语义规划保留在 Java Adapter。

验收：每迁移一项就删除对应重复公共实现；Java 用户可见契约不变；语言适配器只保留语言职责。

Phase 4 是双轨期的强制退出门：通用状态机、文件覆盖率和结果合并仍存在两套实现时，不进入 Vue 适配。

### Phase 5：Vue 适配

- 复用 TS/JS、包管理器、批次和报告能力。
- 增加 `.vue` SFC、Composition API、响应式状态和 Vue Router 规则。
- 接入 Vue Language Server 和静态降级。

验收：主要接入不修改共享内核；React/Vue 共享基础规则并独立启用框架规则；混合 React/Vue 仓库能选择目标或限定目录。

### Phase 6：Python 独立设计与接入

Python 在 Java、React、Vue 验证适配器接口后进入独立设计周期，顺序为：项目识别 → 依赖与 lockfile → 源码/测试边界 → Python LSP/静态降级 → 通用审查矩阵 → Django/FastAPI 专项 → 批次/报告/Ignore → 最后接 Fix。

## 13. 测试策略

### 13.1 脚本单测

- 语言识别、项目类型、正式文件收集和排除规则。
- LSP 能力检测与运行中降级。
- source manifest 稳定性和批次规划确定性。
- 路径边界、空项目和异常输入。

### 13.2 契约测试

- Java 输出兼容和现有交互顺序。
- Adapter 标准字段与 schema version。
- 报告结构、一级标题、覆盖率和阶段状态。
- `README.md`、`AGENTS.md`、`CLAUDE.md`、Skill、Agent 和 references 同步。

### 13.3 场景测试

- 纯 Java、React TypeScript、React JavaScript。
- Java + React 混合仓库。
- TypeScript LSP 可用、不可用和运行中失败。
- 批次成功、失败、缺失、恢复、阶段性和完整合并。

### 13.4 安全测试

- 不执行依赖安装、package scripts 或构建命令。
- 拒绝逃逸项目根目录的范围。
- 测试、生成代码和排除文件不进入正式问题或覆盖率。

每个 Phase 完成前必须运行 `bash tests/run_all.sh`，并同步所有受影响的代码、文档和契约测试。

## 14. 完成定义

React Scan 可以视为完成，必须同时满足：

1. 统一入口可以正确路由纯 Java、纯前端和混合仓库。
2. React TS/JS 项目支持增量、存量、范围选择和结构化确认。
3. 正式源码口径、排除规则和文件覆盖率可追溯且一致。
4. TypeScript LSP 与静态降级均有测试，报告如实披露能力。
5. 大项目批次支持状态恢复、失败门禁和确定性合并。
6. 本地 Markdown、Ignore 和 Feishu Scan 输出可用。
7. Java Scan/Fix 的现有契约和完整测试保持通过。
8. 公共层不包含 React 或 Java 专属判断，React Adapter 不复制公共状态机。
