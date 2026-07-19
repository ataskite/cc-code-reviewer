# 固定 1M 上下文与前端批次收敛设计

## 背景

当前扫描流程通过 `scripts/core/detect-model-context.sh` 读取 Claude Code 模型映射，动态生成 `CONTEXT_WINDOW_TOKENS` 与 `CONTEXT_SCALE`。侦测未命中时回退 200k（`CONTEXT_SCALE=1`），文件级 planner 因此使用 100k 输入预算。前端复用该 planner，一旦回退就会产生约为 1M 预算下五倍的批次。

后续支持模型统一按 1M 上下文使用，不再维护小窗口兼容路径。本次同时收敛文件级 planner 的装箱效率，减少前端大小不均文件造成的额外批次。

## 目标

- 删除模型上下文侦测及其白名单、后缀和环境映射判断。
- Java 与前端扫描统一使用固定的 1M 上下文口径。
- 文件级 planner 默认使用 500k token 批次预算。
- 在不突破单批预算的前提下，提高文件批次填充率，保证新算法批次数不多于现有顺序装箱算法。
- 保留 `CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET`，用于人工调整单批输入预算。
- 保持现有扫描交互、覆盖率、恢复、合并和报告契约不变。

## 非目标

- 不引入真实 tokenizer。
- 不实现 import graph 或语义聚类分批。
- 不改变 Maven 多模块的 work-unit 拆分与依赖上下文规则。
- 不调整并发数、批次选择或合并门禁。

## 设计

### 固定上下文契约

删除 `scripts/core/detect-model-context.sh` 和对应专项测试。模型选择仍发生在分批前，但不再读取底层模型映射，也不再按上下文大小动态推荐模型；三个模型角色都按 1M 上下文展示，默认推荐 `opus`。

扫描流程统一采用：

```text
CONTEXT_WINDOW_TOKENS = 1000000
CONTEXT_SCALE = 5
CONTEXT_TIER = large
```

`CONTEXT_SCALE` 仅作为计划元数据和既有公式中的固定常量保留，不再由模型、位置参数或 `CC_REVIEW_CONTEXT_SCALE` 改写。文件级 planner 的默认预算固定为 500000；Maven 多模块 planner 的成本与行数阈值固定为原 200k 基准的五倍。

### 文件批次装箱

`scripts/core/plan-file-batches.sh` 继续按现有风险优先级、文件成本降序生成稳定输入序列，但从 Next-Fit 改为 First-Fit Decreasing：

1. 依次处理排序后的文件。
2. 将文件放入第一个仍有足够剩余预算的已有批次。
3. 若所有已有批次都无法容纳，再创建新批次。
4. 单个文件成本超过预算时允许独占一个超限批次，保持现有可审查性，不丢文件。
5. 最终批次顺序按首次创建顺序保持稳定。

该算法会用后续较小文件填补前面批次的空隙，特别适合前端仓库中大页面、大组件和大量小 hooks/util 文件并存的情况。它属于语言中立共享 kernel，因此 Maven 单模块、Gradle 和未知 Java 项目也会得到相同的装箱改进；Maven 多模块 planner 不受影响。

### 输出与兼容性

`plan.json` 继续输出以下字段，供状态展示和耗时估算使用：

```json
{
  "budget": {
    "batch_token_budget": 500000,
    "target_batch_cost": 500000,
    "context_scale": 5,
    "context_window_tokens": 1000000
  }
}
```

删除动态侦测来源、底层模型名和 200k/1M 分支说明。Agent 只接收固定上下文信息。已有 `CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET` 覆盖仍写入 `batch_token_budget` 与 `target_batch_cost`，但上下文元数据保持 1M。

## 测试策略

按 TDD 增加或调整以下回归测试：

- 契约测试先断言侦测脚本、侦测步骤、200k 回退和动态 scale 说明已删除。
- 文件级 planner 在未设置任何上下文环境变量时，必须生成 `context_scale=5`、`context_window_tokens=1000000` 和 `batch_token_budget=500000`。
- 即使设置旧的 `CC_REVIEW_CONTEXT_SCALE=1`，planner 仍按固定 1M 生成计划，防止旧环境把预算降回 200k。
- 构造大小不均的前端文件集合，证明 First-Fit Decreasing 的批次数少于旧 Next-Fit 可达到的批次数，并校验每个文件只出现一次。
- 验证显式 `CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET` 仍生效。
- 更新并运行 Java 文件 planner、前端 smoke、状态展示、耗时估算和文档契约测试。
- 最后执行 `bash tests/run_all.sh` 与 `git diff --check`。

## 文档同步范围

同步 `README.md`、`AGENTS.md`、`CLAUDE.md`、`skills/cc-code-reviewer/SKILL.md`、Java/前端 agent 提示和受影响的历史有效契约说明。历史归档计划只保留历史事实，不做机械重写。
