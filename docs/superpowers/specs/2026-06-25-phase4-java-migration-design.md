# Phase 4：Java 公共能力迁移设计

**日期**：2026-06-25
**状态**：草案（待批准）
**依赖**：`2026-06-23-multi-language-reviewer-design.md` 第 12 节 Phase 4（强制退出门）
**前置条件**：前端 React Scan（原 spec Phase 0–3）已在 `feat/frontend-reviewer` 分支实现并通过测试

## 1. 背景与动机

多语言扩展的首期（React Scan）已落地。共享内核（`scripts/core/`）与前端适配器（`scripts/languages/frontend/`）已建立，但 Java 仍走独立的 `phase11-plan-large-batches.sh` / `phase11-plan-file-batches.sh` / `phase12-merge-large-batches.sh`，与 `scripts/core/plan-file-batches.sh` / `merge-batch-results.sh` 形成**两套重复的批次与合并实现**。

原 spec 第 12 节将 Phase 4 定义为「双轨期强制退出门」：通用状态机、文件覆盖率和结果合并仍存在两套实现时，不进入 Vue 适配。本 spec 细化 Phase 4 的迁移范围、顺序、契约边界与风险控制。

## 2. 关键约束（来自原 spec 与现有契约）

迁移必须严格遵守以下约束，否则会破坏 Java 现有能力：

1. **Java 用户可见契约不变**：`tests/java/test_java_baseline_contract.sh` 与 `tests/test_phase11_plan_file_batches.sh` / `test_phase11_plan_large_batches.sh` / `test_phase12_merge_large_batches.sh` 锁死的字段名（`TOTAL_JAVA_LOC`、`planned_java_loc`、`java_file_coverage_percent`、`covered_java`、`RUN_ID`/`RUN_DIR`/`BATCH_COUNT`/`BATCH_FILE_LIST_DIR`、`简要分批计划`）必须保持原样输出。
2. **Maven 多模块语义规划保留在 Java Adapter**：`phase11-plan-large-batches.sh` 的语义成本规划（`review_cost`、`context_roots`、`units`、`affinity_edges`、`module_dependency_edges`、按 package root 拆分）是 Java 专属能力，**不迁入 core**，原 spec 明确保留。
3. **共享内核不得含框架语义**：`scripts/core/` 不解析 Maven、`pom.xml`，不含 `src/main/java` 路径假设。
4. **契约测试随迁移同步更新**：`tests/test_contract_docs.sh` 有 20+ 条断言直接 grep `phase11`/`phase12` 的字面字符串（`52000 * CONTEXT_SCALE`、`semantic-cost-batching`、`context_roots`、`RUN_BATCH_IDS`、`[合并阻塞]`、`report_title`、`dedupe_issue_blocks` 等）。每迁移一项，对应断言同步迁移到新位置。
5. **不削弱现有大仓库能力**：Java 的跨会话恢复、`[阶段性]`/`[合并阻塞]` 门禁、确定性去重、模块维度状态表必须等价保留。

## 3. 现状契约差异（迁移张力来源）

侦察确认，两套实现的核心差异是 **JSON 字段命名**与**批次语义**：

| 维度 | Java 现状（phase11/12） | 共享内核（scripts/core） |
|---|---|---|
| 字段命名 | `total_java_loc`、`planned_java_loc`、`covered_java`、`java_file_coverage_percent` | `total_source_loc`、`planned_source_loc`、`covered_source_file_count`、`source_file_coverage_percent` |
| 文件级批次 source 收集 | 内部 `find -path '*/src/main/java/*'` | 外部传入 `SOURCE_MANIFEST` |
| 多模块语义规划 | `large-batches`：`units`/`scan_roots`/`context_roots`/`review_cost`/affinity | core 无（纯文件 token 打包） |
| 覆盖率展示名 | 固定「Java 文件覆盖率」 | 按 `language_id` 切换 |
| 入参 | `phase11-file`：3 参；`phase11-large`：7 参 | `plan-file-batches`：5 参（含 LANGUAGE_ID + manifest） |

**核心结论**：`scripts/core/plan-file-batches.sh` 能替代 `phase11-plan-file-batches.sh`（都是纯文件 token 打包），但**不能替代** `phase11-plan-large-batches.sh`（语义规划）。同理 `core/merge-batch-results.sh` 能服务文件级批次，但 `phase12-merge-large-batches.sh` 依赖 `units`/`scan_roots`/`context_roots` 做模块维度展示，两者不可直接合并。

## 4. 迁移范围与策略

### 4.1 迁移项（按顺序，每项独立可发布）

| # | 迁移项 | 来源 | 目标 | 风险 |
|---|---|---|---|---|
| M1 | Java source manifest 生成 | phase11-file 内部 `find` | 新建 `scripts/languages/java/collect-source-files.sh` | 低（新增） |
| M2 | Java 文件级批次 planner | `phase11-plan-file-batches.sh` | 改为薄包装：调 M1 manifest + `core/plan-file-batches.sh` | 中（改 Java 路径） |
| M3 | Java 文件级批次 merge | `phase12` 的文件级路径 | 文件级批次改用 `core/merge-batch-results.sh` | 中 |
| M4 | Java 预扫描输出 PROFILE_SCHEMA | `phase3`/`phase10` | 追加 PROFILE_SCHEMA v1 行（带 java 字段别名），不改原输出 | 低 |
| M5 | Java large-batches planner 字段对齐 | `phase11-plan-large-batches.sh` | 输出**追加** `source_*` 中立字段别名，保留 `java_*` 字段 | 中（改大仓库 planner） |
| M6 | large-batches merge 复用 core | `phase12` 语义路径 | 评估 core merge 能否服务 large-batches（依赖 units/scan_roots） | 高，**可能不做** |

### 4.2 不迁移项（明确保留）

- `phase11-plan-large-batches.sh` 的**语义规划逻辑**（`review_cost`/`context_roots`/`units`/affinity/module_dependency_edges/package root 拆分）保留在 Java adapter。
- `phase12-merge-large-batches.sh` 的**模块维度状态展示**（依赖 `units`/`scan_roots`）保留，除非 M6 评估证明 core merge 可等价覆盖。

### 4.3 兼容桥策略（字段命名）

Java 迁移后需要同时满足两个契约：
- **用户可见输出**保持 `java_*` 字段名（约束 1）。
- **内核消费**需要 `source_*` 中立字段名。

**方案**：planner 输出**双字段**（既有 `planned_java_loc` 又有 `planned_source_loc`，值相同）。core merge 读 `source_*`，Java 用户可见报告读 `java_*`。M5 让 large-batches 也追加 `source_*` 别名。这样 core merge 能统一服务两类批次，而 Java 报告字段不变。

> 备选方案（字段映射层）：在 core merge 入口做 `java_* → source_*` 归一化。**否决**：会让 core 隐式知道 Java 语义，违反约束 3（内核不含框架语义）。双字段由 adapter 主动产出，是 adapter 职责，符合 `language-adapter-contract.md`。

## 5. 各迁移项详细设计

### M1：Java source manifest 生成器

**目标**：把 phase11-file 内部的 `find -path '*/src/main/java/*'` 抽成独立脚本，供 core planner 消费。

**文件**：新建 `scripts/languages/java/collect-source-files.sh`

**契约**：
- 入参：`PROJECT_DIR`
- 输出：逐行绝对路径，仅 `src/main/java` 下的生产 `.java`，排除 `src/test/java`、`target/`、`build/`、`.git/`
- 实现：复刻 phase11-file 第 161 行的 find 逻辑（`-path '*/src/main/java/*' -name '*.java' -not -path '*/target/*'`）
- 必须含 `pwd -P` 规范化（与前端 collect-source-files.sh 一致）

**验收**：新建 `tests/languages/java/test_java_collect_source_files.sh`，断言生产源码包含、test/target 排除。

### M2：Java 文件级批次 planner 迁移

**目标**：`phase11-plan-file-batches.sh` 改为薄包装，消除文件级批次的两套实现。

**改造**：
1. `phase11-plan-file-batches.sh` 不再自己规划，改为：
   - 调 M1 生成 manifest
   - 调 `core/plan-file-batches.sh "$PROJECT_DIR" "$REVIEW_MODE" "$BRANCH_NAME" "java" "$MANIFEST"`
   - 把 core 输出的 `TOTAL_SOURCE_LOC`/`TOTAL_SOURCE_FILE_COUNT` **转译**回 `TOTAL_JAVA_LOC`/`TOTAL_JAVA_FILE_COUNT`（保用户可见契约）
2. core planner 产出的 batch.json 用 `planned_source_loc`；phase11-file 包装层**追加** `planned_java_loc` 别名（双字段策略 4.3）

**验收**：`tests/test_phase11_plan_file_batches.sh` 现有断言（`RUN_ID=`/`RUN_DIR=`/`TOTAL_JAVA_LOC`/`简要分批计划`）全部保持通过；`tests/test_contract_docs.sh` 中 phase11-file 相关断言迁移到包装层或 core。

### M3：Java 文件级批次 merge 迁移

**目标**：文件级批次的合并改用 `core/merge-batch-results.sh`。

**挑战**：core merge 读 `total_source_*`/`planned_source_*`，Java 文件级批次的 plan.json/batch.json 现在是 `total_java_*`/`planned_java_*`。靠 M2 的双字段策略（4.3）解决：包装层已追加 `source_*` 别名，core merge 能直接消费。

**改造**：SKILL.md 中 Java 文件级批次的 merge 调用从 `phase12-merge-large-batches.sh` 改为 `core/merge-batch-results.sh`。

**验收**：新建 `tests/core/test_core_merge_java_file_batches.sh`（Java 文件级批次 fixture + core merge，断言覆盖率字段、`[阶段性]`/`[合并阻塞]`、`report_title`）。

### M4：Java 预扫描输出 PROFILE_SCHEMA

**目标**：`phase3-project-scan.sh` 追加 PROFILE_SCHEMA v1 行，统一内核消费协议（不删原输出）。

**改造**：phase3 在现有输出末尾**追加**：
```
PROFILE_SCHEMA_VERSION=1
LANGUAGE_ID=java
SOURCE_FILE_COUNT=<同 Java文件总数>
SOURCE_LINE_COUNT=<同 代码总行数>
```
`phase10` 输出追加 `CODE_INTELLIGENCE_PROVIDER=`（已有 jdtls-lsp 检测，补 PROFILE 字段名）。

**验收**：`tests/java/test_java_baseline_contract.sh` 增加 PROFILE_SCHEMA 字段断言；原字段断言不变。

### M5：large-batches planner 追加中立字段

**目标**：`phase11-plan-large-batches.sh` 的 plan.json/batch.json 追加 `total_source_loc`/`planned_source_loc` 等 `source_*` 别名（值与 `java_*` 相同），为 M6 铺路。`java_*` 字段保留。

**风险**：改大仓库 planner，影响 Maven 多模块大仓库。必须靠 `tests/test_phase11_plan_large_batches.sh` 全量回归。

### M6（评估项）：large-batches merge 复用 core

**目标**：评估 `core/merge-batch-results.sh` 能否服务 large-batches。

**关键障碍**：phase12 依赖 batch.json 的 `units`/`scan_roots`/`context_roots` 做模块维度状态表，core merge 目前只读 `modules`（从 batch.json 退化读 `scan_roots`）。

**决策**：
- 若 core merge 的 `batch_modules()` 能等价覆盖 → M6 做，删 phase12
- 若不能（模块维度展示有 Java 专属语义）→ **M6 不做，phase12 保留**，只做 M5 字段对齐
- **倾向不强制做 M6**：phase12 的模块维度展示是大仓库核心 UX，与 core merge 的「语言中立」定位冲突。保留 phase12 服务 Java 大仓库、core merge 服务所有语言的文件级批次，是合理的职责划分。

## 6. 强制退出门判定（原 spec Phase 4 验收）

原 spec：「通用状态机、文件覆盖率和结果合并仍存在两套实现时，不进入 Vue」。

**迁移后的状态**：
- 通用文件覆盖率：M1+M2 后，文件级批次统一走 core（Java 与前端共享），**消除一套**。large-batches 的模块覆盖率保留（Java 专属，非「通用文件覆盖率」范畴）。
- 通用合并状态机：M3 后文件级 merge 统一；M6 不做则 large-batches merge 保留（语义专属）。
- 通用 source manifest：M1+M4 后 Java 与前端统一协议。

**退出门判定标准**（明确化，避免歧义）：
> 「两套实现」指**同一职责**存在两个可互相替代的实现。文件级批次/合并属于通用职责（所有语言都有文件级批次），必须收敛到 core。Maven 多模块语义规划/合并是 Java 专属职责（无对应通用实现），不属于「两套实现」，保留不违反退出门。

按此判定，**M1–M5 完成即满足退出门**（M6 视评估可选）。Vue 适配可启动。

## 7. 迁移顺序与里程碑

```
M1 (manifest 生成器)        ── 新增，零 Java 风险
   └─ M2 (文件级 planner)    ── 消除文件批次两套实现 ★退出门核心
        └─ M3 (文件级 merge) ── 消除文件合并两套实现 ★退出门核心
             └─ M4 (预扫描 PROFILE) ── 统一协议
                  └─ M5 (large-batches 字段对齐) ── 为 M6 铺路
                       └─ M6 (评估 large-batches merge) ── 可选
```

每个里程碑独立可发布、独立可回滚。M2+M3 是退出门的硬性要求，M4/M5/M6 是协议统一与可选项。

## 8. 风险控制

1. **每项迁移后跑 `tests/java/test_java_baseline_contract.sh` + `tests/test_phase11_*` + `tests/test_phase12_*`**：锁死 Java 可见契约。
2. **每项迁移后跑全量 `tests/run_all.sh`**：含 `git diff --check`。
3. **M5 改 large-batches 前，先在测试 fixture 验证 `source_*` 别名不破坏 phase12 读取**（phase12 仍读 `java_*`，别名是额外字段）。
4. **真实验证**：M2/M3 改 Java 文件级批次路径后，建议用一个真实 Maven 单模块项目跑一次端到端，确认无回归（子代理测试是合成 fixture，真实项目能发现 fixture 覆盖不到的问题）。
5. **回滚策略**：每个 M 项独立提交，若 M(n) 引入回归，单独 revert M(n) 不影响 M(n-1)。

## 9. 与原 spec 的一致性

- 原 spec 第 12 节 Phase 4「按语言探测、source manifest、通用文件批次、通用覆盖率、通用合并状态机、通用报告元数据的顺序逐项迁移」→ 本 spec M1（manifest）、M2（文件批次）、M3（合并）、M4（报告元数据 PROFILE）对应。
- 原 spec「Maven 多模块语义规划保留在 Java Adapter」→ 本 spec 4.2 不迁移项明确。
- 原 spec「每迁移一项就删除对应重复公共实现」→ M2 删 phase11-file 的规划逻辑（保留薄包装保字段契约）、M3 删 phase12 的文件级路径。
- 原 spec「Java 用户可见契约不变」→ 约束 1 + 双字段策略（4.3）保证。
- 原 spec「Phase 4 是双轨期强制退出门」→ 第 6 节明确化判定标准，M1–M5 满足退出门。

## 10. 未决问题（需在实施计划阶段确认）

1. **M2 包装层的字段转译**：core 输出 `TOTAL_SOURCE_LOC`，包装层转译为 `TOTAL_JAVA_LOC`。是包装层 `sed` 转译，还是 core planner 支持「输出字段名后缀」参数？倾向前者（core 保持中立，包装层负责 Java 契约）。
2. **M6 的最终决策**：需要实际对比 phase12 的模块维度状态表与 core merge 的 `batch_modules()` 输出，才能判定。建议在 M5 完成后做一次专门评估，结论写入实施计划。
3. **CONTEXT_SCALE 传递**：phase11-file 当前通过环境变量 `CC_REVIEW_CONTEXT_SCALE` 接收，core planner 也用同名环境变量。M2 包装层需确保环境变量透传。

## 11. 非目标

- 不在本 Phase 实现 Vue 适配（Phase 5）。
- 不重写 `phase11-plan-large-batches.sh` 的语义规划算法。
- 不合并 phase12 与 core merge 为单一脚本（除非 M6 评估通过）。
- 不改变 Java Fix 路径（Fix 不在 Phase 4 范围）。
