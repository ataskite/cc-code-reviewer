# 脚本目录重构设计

> 日期: 2026-06-28
> 状态: 设计待评审
> 关联: `2026-06-23-multi-language-reviewer-design.md`（多语言内核）、`2026-06-27-frontend-review-framework-redesign-design.md`（前端框架）

## 一、背景与问题

当前 `scripts/` 下平铺 26 个脚本，存在三类问题：

1. **脚本重复**：`phase11-plan-file-batches.sh` 与 `core/plan-file-batches.sh`、`phase12-merge-large-batches.sh` 与 `core/merge-batch-results.sh` 是同一算法的两份副本（后者是前者的语言中立重构版）。算法改一处要改两遍。

2. **混合体**：`phase13-show-large-batch-status.sh` 的耗时/调度/展示逻辑是语言中立的（已 source `core/estimate-review-minutes.sh`），但字段读取层硬编码 `total_java_loc`/`planned_java_loc`/"Java 行覆盖"。前端分批跑完后无法用 phase13 展示批次状态。

3. **语言归属不清**：`phase3-project-scan.sh`、`phase10-detect-code-intelligence.sh`、`phase11-plan-large-batches.sh`、`phase11-plan-file-batches.sh` 是 Java 专属，但命名上看不出语言归属，与 `core/`（语言中立）和 `languages/frontend/`（前端专属）混在同一层。

4. **phase 编号已成负担**：通用脚本（phase1/2/4/5/6-9/14）被抽到 core/ 后，语言目录里只剩稀疏的专属脚本，硬套全局编号必然断号；phase 编号本表达「执行顺序」，但执行顺序是流程编排，应写在 SKILL.md，而非编码进文件名。

## 二、目标

- `core/` 放语言中立的公共能力，按功能名命名（不编号），被 `languages/*` 单向引用。
- `languages/java/` 和 `languages/frontend/` 各放语言专属脚本，按功能名命名（不编号）。
- 消除两对重复脚本：Java 改为复用 `core/` 版本。
- 提取 phase13 的中立展示逻辑到 `core/show-batch-status.sh`，前端可复用。
- 去掉 phase 编号；执行顺序统一以编号列表写进各 SKILL.md 的流程编排段。
- 保留旧路径作为兼容转发 wrapper，分批迁移、全程可回滚、测试始终全绿。

## 三、目标目录结构

```
scripts/
├── core/                              # 语言中立公共能力库（按需被引用，无执行顺序语义）
│   ├── detect-project.sh              # ← scripts/phase1-detect-project.sh
│   ├── detect-branches.sh             # ← scripts/phase2-detect-branches.sh
│   ├── switch-branch.sh               # ← scripts/phase2-switch-branch.sh
│   ├── detect-lark-plugin.sh          # ← scripts/phase4-detect-lark-plugin.sh
│   ├── preview-recent-commits.sh      # ← scripts/phase5-preview-recent-commits.sh
│   ├── prepare-incremental.sh         # ← scripts/phase5-prepare-incremental.sh
│   ├── detect-fix-input.sh            # ← scripts/phase6-detect-fix-input.sh
│   ├── detect-superpowers.sh          # ← scripts/phase7-detect-superpowers.sh
│   ├── prepare-fix-workspace.sh       # ← scripts/phase8-prepare-fix-workspace.sh
│   ├── collect-fix-metadata.sh        # ← scripts/phase9-collect-fix-metadata.sh
│   ├── detect-model-context.sh        # ← scripts/phase14-detect-model-context.sh
│   ├── detect-language.sh             # （已存在）语言探测调度器
│   ├── estimate-review-minutes.sh     # （已存在）耗时模型
│   ├── validate-scope.sh              # （已存在）范围边界校验
│   ├── plan-file-batches.sh           # （已存在）语言中立分批，Java+前端共用
│   ├── merge-batch-results.sh         # （已存在）语言中立合并，Java+前端共用
│   └── show-batch-status.sh           # ★新增 从 phase13 提取，字段层按 language_id 切换
│
├── languages/
│   ├── java/
│   │   ├── project-scan.sh            # ← scripts/phase3-project-scan.sh
│   │   ├── detect-code-intelligence.sh# ← scripts/phase10-detect-code-intelligence.sh
│   │   ├── plan-large-batches.sh      # ← scripts/phase11-plan-large-batches.sh
│   │   └── plan-file-batches.sh       # ← scripts/phase11-plan-file-batches.sh（瘦身为调用 core/ 的 wrapper）
│   │
│   └── frontend/
│       ├── scan-project.sh            # （已存在，原 languages/frontend/scan-project.sh）
│       ├── detect-code-intelligence.sh# （已存在）
│       ├── collect-source-files.sh    # （已存在，scan-project 内部依赖）
│       └── detect-project.sh          # （已存在，scan-project 内部依赖）
│
└── phase1..phase14-*.sh               # 旧路径：降级为转发 wrapper，source/调用新路径
```

### 命名约定

1. **`core/` 与 `languages/*/` 全部用功能名，不带 phase 编号**。文件名只描述「做什么」，不描述「在第几步执行」。
2. **引用方向单向**：`languages/* → core/*`。`core/` 不得反向依赖任何语言目录。
3. **内部依赖不编号**：`collect-source-files.sh`、`detect-project.sh` 是 `scan-project.sh` 的内部辅助，保持功能名。
4. **同名同义跨语言**：Java 与前端都有 `detect-code-intelligence.sh`（jdtls vs typescript-lsp），各自实现，文件名相同可直观对比。

### 依赖关系

```
languages/java/        languages/frontend/        core/
   │                        │                      │
   │ ┌──────────────────────┼──────────────────────┘
   │ │                      │ (单向引用)
   ▼ ▼                      ▼
project-scan.sh         scan-project.sh            detect-project.sh (core)
detect-code-intel.sh    detect-code-intel.sh       detect-branches.sh
plan-large-batches.sh                              switch-branch.sh
plan-file-batches.sh ──► core/plan-file-batches.sh detect-lark-plugin.sh
                       (瘦身为转发)                 preview-recent-commits.sh
                                                   prepare-incremental.sh
                                                   detect-model-context.sh
                                                   estimate-review-minutes.sh
                                                   show-batch-status.sh ★
                                                   plan-file-batches.sh
                                                   merge-batch-results.sh
                                                   ...
```

## 四、迁移映射表

### 4.1 core/ 通用脚本迁移（11 个 + 1 新增）

| 旧路径 | 新路径 | 迁移方式 |
|--------|--------|----------|
| `scripts/phase1-detect-project.sh` | `scripts/core/detect-project.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase2-detect-branches.sh` | `scripts/core/detect-branches.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase2-switch-branch.sh` | `scripts/core/switch-branch.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase4-detect-lark-plugin.sh` | `scripts/core/detect-lark-plugin.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase5-preview-recent-commits.sh` | `scripts/core/preview-recent-commits.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase5-prepare-incremental.sh` | `scripts/core/prepare-incremental.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase6-detect-fix-input.sh` | `scripts/core/detect-fix-input.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase7-detect-superpowers.sh` | `scripts/core/detect-superpowers.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase8-prepare-fix-workspace.sh` | `scripts/core/prepare-fix-workspace.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase9-collect-fix-metadata.sh` | `scripts/core/collect-fix-metadata.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase14-detect-model-context.sh` | `scripts/core/detect-model-context.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase13-show-large-batch-status.sh` | `scripts/core/show-batch-status.sh` | **拆分提取**（见 4.4） |

### 4.2 Java 专属脚本迁移（4 个）

| 旧路径 | 新路径 | 迁移方式 |
|--------|--------|----------|
| `scripts/phase3-project-scan.sh` | `scripts/languages/java/project-scan.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase10-detect-code-intelligence.sh` | `scripts/languages/java/detect-code-intelligence.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase11-plan-large-batches.sh` | `scripts/languages/java/plan-large-batches.sh` | 移动 + 旧路径转 wrapper |
| `scripts/phase11-plan-file-batches.sh` | `scripts/languages/java/plan-file-batches.sh` | **瘦身为 wrapper**（见 4.3） |

### 4.3 消除重复：Java 复用 core/

`phase11-plan-file-batches.sh` 和 `phase12-merge-large-batches.sh` 与 `core/` 版本重复。处理方式：

**`plan-file-batches.sh`（Java 文件级分批）**：
- `core/plan-file-batches.sh` 已支持 `LANGUAGE_ID` 参数（第 4 参）+ 外部 `SOURCE_MANIFEST`（第 5 参）。
- `languages/java/plan-file-batches.sh` 瘦身为薄 wrapper：
  1. 用 `find ... -path '*/src/main/java/*' -name '*.java'` 生成 Java 文件 manifest（Java 专属的文件发现逻辑，保留在 Java 目录）。
  2. 调用 `core/plan-file-batches.sh`，传入 `LANGUAGE_ID=java` + manifest 路径。
- `phase12-merge-large-batches.sh` 同理：Java 的合并直接调用 `core/merge-batch-results.sh`，旧路径降为转发 wrapper（`core/` 版本已按 `language_id` 切换覆盖率标签）。

**结果**：分批算法与合并去重逻辑只剩 `core/` 一份实现，Java 与前端共享。

### 4.4 phase13 拆分提取

`phase13-show-large-batch-status.sh` 整体提取到 `core/show-batch-status.sh`，字段读取层按 `plan.json.language_id` 自动切换，**不需要 Java 专属 wrapper**：

| 部分 | 归属 | 内容 |
|------|------|------|
| **展示逻辑 + 字段切换** | `core/show-batch-status.sh`（唯一实现） | 状态表渲染、`display_plan_row`、`estimate_minutes`（多 lane 贪心调度）、`format_number`、`status_label`、`markdown_cell`。字段读取按 `plan.json.language_id` 切换：`java` 读 `total_java_loc`/`planned_java_loc`，`frontend` 读 `total_source_loc`/`planned_source_loc`。覆盖率标签同理切换（"Java 行覆盖" vs "前端源码行覆盖"）。 |

`phase13-show-large-batch-status.sh` 旧路径降为转发 `core/show-batch-status.sh` 的 wrapper。第三节目录结构中 `languages/java/` **不包含** `show-batch-status.sh`——它纯粹由 core/ 按 language_id 处理。

### 4.5 前端脚本（已就位，仅补充 show-batch-status 接入）

`languages/frontend/` 下 4 个脚本已存在，无需移动。**唯一新增接入**：前端分批流程增加调用 `core/show-batch-status.sh` 展示批次状态（此前前端缺这一环）。

### 4.6 validate-scope.sh 处理

`core/validate-scope.sh` 当前无运行时调用点（仅 `test_contract_docs.sh` 断言其存在）。处理决定：**本次迁移中标记为预留脚本**——在文件头注释明确标注「预留脚本，当前未接入运行时流程，计划在后续 scope 校验增强中接入」，避免后续误判为死代码。不在本次迁移中强行接入（避免扩大范围）。保持 `test_contract_docs.sh` 的存在性断言不变。

## 五、兼容转发 wrapper 规范

每个旧路径降级为 wrapper，规范如下：

```bash
#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/<new-name>.sh
# 本文件仅为向后兼容旧调用路径，新代码请直接引用新路径。
# 待所有调用点迁移完成后可删除。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/<new-name>.sh" "$@"
```

对 Java 专属脚本，wrapper 转发到 `languages/java/`：

```bash
exec "$SCRIPT_DIR/languages/java/<new-name>.sh" "$@"
```

**要求**：
- 每个 wrapper 必须 `exec` 新路径并透传 `"$@"`，输出与退出码与新路径完全一致。
- wrapper 顶部注释标注迁移目标，便于后续清理。
- 所有旧测试（`tests/test_phaseN_*.sh`）在 wrapper 存在期间必须继续通过，**逐字节不变**。

## 六、执行顺序写进 SKILL.md

去掉 phase 编号后，脚本调用顺序以编号列表形式明文写在 SKILL.md 的流程编排段。

### 6.1 扫描主流程（Java 分支）

```markdown
## Java 扫描流程（脚本调用顺序）
1. core/detect-project.sh                          → 识别项目路径
2. core/detect-branches.sh                         → 列出分支（多分支则 AskUserQuestion 选）
3. core/switch-branch.sh                           → 切换到选定分支（按需）
4. core/detect-language.sh                         → 探测语言（固定 java）
5. languages/java/project-scan.sh                  → Java 预扫描（Maven/技术栈）
6. languages/java/detect-code-intelligence.sh      → jdtls 探测
7. core/detect-lark-plugin.sh                      → lark-cli 检测
8. core/detect-model-context.sh                    → 模型窗口 → CONTEXT_SCALE
9. 读 ignore 规则 → 输出预扫描摘要
10. AskUserQuestion 交互（模式/报告/入口/范围…）
11. core/estimate-review-minutes.sh               → 计算预估耗时（单 agent 模式）
12. [分批] languages/java/plan-large-batches.sh 或 plan-file-batches.sh
13. [分批] core/show-batch-status.sh              → 展示批次状态
14. [分批] 启动 agent → core/merge-batch-results.sh 合并
15. [增量] core/preview-recent-commits.sh + core/prepare-incremental.sh
```

### 6.2 扫描主流程（前端分支）

```markdown
## 前端扫描流程（脚本调用顺序）
1. core/detect-project.sh                          → 识别项目路径
2. core/detect-branches.sh                         → 列出分支（多分支则 AskUserQuestion 选）
3. core/switch-branch.sh                           → 切换到选定分支（按需）
4. core/detect-language.sh                         → 探测语言（固定 frontend）
5. languages/frontend/scan-project.sh              → 前端预扫描（PROFILE_SCHEMA）
6. languages/frontend/detect-code-intelligence.sh  → typescript-lsp 探测
7. core/detect-lark-plugin.sh                      → lark-cli 检测
8. core/detect-model-context.sh                    → 模型窗口 → CONTEXT_SCALE
9. 读 ignore 规则 → 输出预扫描摘要
10. AskUserQuestion 交互（模式/报告/入口/范围…）
11. core/estimate-review-minutes.sh               → 计算预估耗时（单 agent 模式）
12. [分批] core/plan-file-batches.sh              → 前端文件级分批
13. [分批] core/show-batch-status.sh              → 展示批次状态
14. [分批] 启动 agent → core/merge-batch-results.sh 合并
15. [增量] core/preview-recent-commits.sh + core/prepare-incremental.sh
```

### 6.3 修复流程（cc-code-fixer）

```markdown
## 修复流程（脚本调用顺序）
1. core/detect-project.sh                          → 识别项目路径
2. core/detect-branches.sh                         → 列出分支
3. languages/java/project-scan.sh                  → 预扫描（修复只支持 Java）
4. core/detect-lark-plugin.sh                      → lark-cli 检测
5. core/detect-superpowers.sh                      → Superpowers 探测
6. core/detect-fix-input.sh                        → 修复输入校验
7. AskUserQuestion 收集确认问题清单与输出目标
8. core/prepare-fix-workspace.sh                   → 修复工作区准备
9. 执行修复 → core/collect-fix-metadata.sh        → 收集修复元数据
```

## 七、SKILL.md / agent.md 路径引用更新

迁移完成后，SKILL.md 和 agent.md 中的脚本引用从旧路径逐步改为新路径。由于保留了兼容 wrapper，**这不是阻断性改动**——可以：

1. **优先**：新增/修改的调用点直接用新路径。
2. **逐步**：存量调用点分批替换为新路径，每次替换后跑测试验证。
3. **最终**：所有调用点迁移完毕后，删除旧 wrapper。

### 调用点清单（需更新的位置）

**`skills/cc-code-reviewer/SKILL.md`**（17 处 + 前端分批接入点）：
- L39 phase1 → `core/detect-project.sh`
- L42 phase2-detect → `core/detect-branches.sh`
- L58 phase2-switch → `core/switch-branch.sh`
- L68 phase3 → `languages/java/project-scan.sh`
- L71 phase10 → `languages/java/detect-code-intelligence.sh`
- L74/L117 phase4 → `core/detect-lark-plugin.sh`
- L219 phase14 → `core/detect-model-context.sh`
- L337/L883 phase11-large → `languages/java/plan-large-batches.sh`
- L338/L690 phase13 → `core/show-batch-status.sh`
- L590 phase5-preview → `core/preview-recent-commits.sh`
- L909 phase11-file → `languages/java/plan-file-batches.sh`
- L1036 phase5-prepare → `core/prepare-incremental.sh`
- L1051 phase12-merge → `core/merge-batch-results.sh`
- **前端分批接入点（L933-L942 附近）**：前端分批流程需新增调用 `core/show-batch-status.sh`（此前缺失）；前端合并 `core/merge-batch-results.sh` 已在 L942 接入，保持不变

**`skills/cc-code-fixer/SKILL.md`**（9 处）：
- L61 phase1 → `core/detect-project.sh`
- L64 phase2-detect → `core/detect-branches.sh`
- L67 phase3 → `languages/java/project-scan.sh`
- L70 phase4 → `core/detect-lark-plugin.sh`
- L73 phase7 → `core/detect-superpowers.sh`
- L126 phase6 → `core/detect-fix-input.sh`
- L284/L356 phase8 → `core/prepare-fix-workspace.sh`
- L332 phase9 → `core/collect-fix-metadata.sh`

**`agents/cc-code-reviewer.md` / `agents/cc-code-reviewer-frontend.md`**：检查内部脚本引用，同步更新。

## 八、测试策略

### 8.1 现有测试保持全绿（最高优先级）

迁移期间，所有 `tests/test_phaseN_*.sh` 和 `tests/core/test_*.sh` 必须始终通过。wrapper 的存在保证了这一点——旧测试通过 wrapper 调用，行为不变。

### 8.2 新增测试

| 测试文件 | 断言内容 |
|----------|----------|
| `tests/core/test_core_detect_project.sh` | wrapper 转发后输出与旧 phase1 一致（回归） |
| `tests/core/test_core_show_batch_status.sh` | Java plan.json 与前端 plan.json 都能正确渲染状态表（字段按 language_id 切换） |
| `tests/core/test_java_plan_file_batches_uses_core.sh` | `languages/java/plan-file-batches.sh` 实际调用了 `core/plan-file-batches.sh`（验证合并） |
| 更新 `tests/test_contract_docs.sh` | SKILL.md 包含「脚本调用顺序」编号列表段；不再出现 `phaseN-` 字样（防回退）；wrapper 文件全部存在 |

### 8.3 迁移验证清单

每迁移一个脚本：
1. 确认新路径文件存在且可执行。
2. 确认旧路径 wrapper 正确转发（`exec` 透传 `"$@"`）。
3. 跑对应 `test_phaseN_*.sh` 通过。
4. 跑 `tests/run_all.sh` 全绿。

## 九、分阶段迁移计划

### 阶段 1：充实 core/（低风险，立即交付价值）

**目标**：完成 core/ 的中立能力提取，消除重复，前端补齐状态展示。不触碰语言目录。

1. 新增 `core/show-batch-status.sh`：从 phase13 提取中立展示逻辑 + language_id 字段切换。
2. `phase13-show-large-batch-status.sh` 改为 source/转发 `core/show-batch-status.sh`。
3. `phase11-plan-file-batches.sh` 瘦身：文件发现保留，分批算法调用 `core/plan-file-batches.sh`。
4. `phase12-merge-large-batches.sh` 改为调用 `core/merge-batch-results.sh`。
5. 前端分批流程接入 `core/show-batch-status.sh`。
6. 新增对应测试，跑全量测试。

**验证**：Java 全流程不变；前端分批获得状态展示；两对重复脚本消除。

### 阶段 2：建语言目录 + 移动专属脚本（中风险）

**目标**：建立 `languages/java/`，移动 Java 专属脚本。

1. 创建 `scripts/languages/java/`。
2. 移动 `phase3-project-scan.sh` → `languages/java/project-scan.sh`。
3. 移动 `phase10-detect-code-intelligence.sh` → `languages/java/detect-code-intelligence.sh`。
4. 移动 `phase11-plan-large-batches.sh` → `languages/java/plan-large-batches.sh`。
5. `phase11-plan-file-batches.sh` 的瘦身结果移入 `languages/java/plan-file-batches.sh`。
6. 每个旧路径留 wrapper 转发到 `languages/java/`。
7. 跑全量测试。

**验证**：Java 全流程不变（经 wrapper）。

### 阶段 3：迁移通用脚本到 core/（中风险）

**目标**：把 11 个通用脚本移入 `core/`。

1. 逐个移动 `phaseN-xxx.sh` → `core/xxx.sh`（11 个）。
2. 每个旧路径留 wrapper 转发到 `core/`。
3. 跑全量测试。

**验证**：所有旧测试经 wrapper 通过。

### 阶段 4：更新 SKILL.md / agent.md 路径引用（低风险）

**目标**：把文档中的脚本引用从旧路径改为新路径，补写「脚本调用顺序」编排段。

1. 在 `skills/cc-code-reviewer/SKILL.md` 新增 Java/前端两段「脚本调用顺序」编号列表（见第六节）。
2. 在 `skills/cc-code-fixer/SKILL.md` 新增修复流程「脚本调用顺序」。
3. 逐批替换调用点为新路径（17 + 9 处），每批跑测试。
4. 更新 `AGENTS.md`、`CLAUDE.md` 的文件结构树。
5. 更新 `references/examples.md` 中的脚本路径引用。
6. 更新 `test_contract_docs.sh`：新增「调用顺序段存在」断言 + 「不含 phaseN-」防回退断言。

**验证**：文档一致；新路径引用可用；防回退断言通过。

### 阶段 5：清理（可选，迁移稳定后）

1. 确认所有调用点已用新路径。
2. 删除旧 wrapper。
3. 更新测试：`test_phaseN_*.sh` 改为指向新路径（或保留 wrapper 测试 wrapper 本身）。
4. 跑全量测试。

## 十、不在本次范围

- 不改任何脚本的内部算法逻辑（只移动位置 + 消除重复 + 提取共享）。
- 不改 SKILL.md 的交互流程（AskUserQuestion 步骤不变）。
- 不改报告格式、飞书集成、ignore 规则、修复契约。
- 不动 `references/` 的内容结构（仅更新其中引用的脚本路径）。
- 前端 React 审查框架本身（见 `2026-06-27-frontend-review-framework-redesign-design.md`）。

## 十一、成功标准

1. `scripts/core/` 全部为语言中立脚本，不依赖 `languages/`。
2. `scripts/languages/java/` 和 `scripts/languages/frontend/` 各自只有语言专属脚本。
3. 分批算法（`plan-file-batches`）与合并逻辑（`merge-batch-results`）各只剩一份实现（在 core/），Java 与前端共享。
4. `core/show-batch-status.sh` 能同时渲染 Java 和前端的批次状态表。
5. 没有任何脚本文件名带 phase 编号。
6. 每个 SKILL.md 有明确的「脚本调用顺序」编号列表段。
7. `tests/run_all.sh` 全程全绿。
8. 旧路径 wrapper 存在期间，所有旧测试逐字节不变。
