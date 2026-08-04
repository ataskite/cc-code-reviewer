# Language Adapter Contract

本文件定义语言适配器与共享内核之间的标准协议。预扫描采用版本化的 key=value 输出。

## Java 字段 → 公共字段映射（兼容桥）

| Java 现有输出 | 公共中性字段 | 说明 |
|---|---|---|
| `Java文件总数`（languages/java/project-scan.sh 文本行） | `source_file_count` | 仅 src/main/java 生产源码 |
| `代码总行数` | `source_line_count` | 仅 src/main/java |
| `MODULE:` 行 | `COMPONENT:` 行 | 公共层消费目录概览/范围选择/manifest 收敛（中性目录操作，不解释框架语义） |
| `TECH_STACK:` 行 | `TECH_STACK:` 行 | 透传，公共层不解释 |
| languages/java/detect-code-intelligence.sh 输出 | `CODE_INTELLIGENCE_PROVIDER` | jdtls-lsp / none |

> Java 适配器在迁移前（Phase 4 之前）继续输出原有字段；前端适配器已直接输出 PROFILE_SCHEMA v1。公共层 `scripts/core/` 使用 `source_file_count` 等中性概念消费所有语言。

## PROFILE_SCHEMA v1（标准预扫描输出协议）

适配器预扫描必须输出版本化的 key=value，第一版至少包含：

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
FORMAL_CONFIG_FILE:/project/pyproject.toml
CONTEXT_ROOT:tests|/project/tests
TECH_STACK:React|dependency:react@19|rules:react
TECH_STACK:Vue 2|dependency:vue@2/vue-template-compiler|rules:vue2
TECH_STACK:Node.js|dependency:package.json|rules:node-runtime
RUNTIME_SIGNAL:package.type|module
SOURCE_SCOPE:formal|src/**/*.tsx
SOURCE_SCOPE:formal|src/**/*.vue
SOURCE_SCOPE:context|**/*.test.tsx
SOURCE_SCOPE:excluded|node_modules/**
```

### 处理规则

- `PROFILE_SCHEMA_VERSION` 不匹配时**必须停止**，不得猜测解析。
- `LANGUAGE_ID` 在一次运行中不可变。
- `SOURCE_FILE_COUNT` 只统计生产源码，且必须与覆盖率分母来自同一份不可变 source manifest。
- `FORMAL_CONFIG_FILE_COUNT` 单独记录可产生正式问题的配置文件，**不进入源码覆盖率分母**。
- 适配器应为每个正式配置输出 `FORMAL_CONFIG_FILE:<绝对路径>`；它可以产生正式问题，但不进入 source manifest 和源码覆盖率分母。文件级分批时只由首批审查正式配置，避免重复发现。
- 适配器应为每个只读上下文根目录输出 `CONTEXT_ROOT:<类型>|<绝对路径>`，类型如 `tests`（测试目录）、`migrations`（Django/Alembic 生成代码）。上下文根目录可用于测试质量/迁移质量判断，但**不得成为正式问题位置**，也**不计入源码覆盖率分母**。
- 公共层使用 `source_file_count` 等中性概念；Java 兼容输出可暂时保留 `selected_java_file_count` 别名（Phase 4 迁移后废弃）。
- `COMPONENT` / `TECH_STACK` / `SOURCE_SCOPE` 可重复出现。
  - `COMPONENT` 是语言中性的、互不重叠的「目录分区」（前端/Python = source manifest 的顶层源码分区，Java 兼容映射自 `MODULE:`）；公共层**可以**消费 `COMPONENT:` 行做目录概览展示、范围选择和 source manifest 收敛——这些都是目录结构操作，**不涉及框架语义**。
  - 前端 source manifest 收敛必须通过 `scripts/languages/frontend/filter-source-manifest.sh`：`src/components` 或 `components` 匹配所有支持技术栈的 package-local `*/src/components/`，`apps/web/src/components` 只匹配对应 package；绝对路径和 `..` 路径穿越必须拒绝。
  - `TECH_STACK` / `SOURCE_SCOPE` 公共层只负责保存和展示，**不解释框架语义**（专项规则解释仍由各语言 agent 完成）。
- 混合仓库：用户选择语言后，另一语言只能作仓库背景，不得成为正式问题来源。

## 适配器职责

1. 识别项目类型、框架、构建器、包管理器、workspace。
2. 定义正式源码、只读上下文、排除项、生成代码。
3. 统计组件、文件、行数和批次成本。
4. 探测语言语义工具并定义可靠的静态降级路径。
5. 提供语言审查维度、框架专项规则、Agent。
6. 将语言专属数据映射到公共协议。

## 共享内核职责（不得解析框架语义）

- 项目获取、Git 分支与增量范围。
- 结构化交互和最终确认。
- 标准化 source manifest、批次状态和结果契约。
- `review-input.json`、`review-rules.json`、`review-units.json` 与 `run-manifest.json` 的文件协议；共享内核只解释路径、状态、指纹和直接 import，不解释框架语义。
- 批次选择、并发编排、恢复、等待和失败门禁。
- 文件覆盖率、确定性去重和阶段性/完整报告判断。
- Ignore 规则加载、报告持久化和飞书输出。

共享内核不得解析 Maven、`package.json`，也不得包含 Spring、React、Django 等专项规则。
