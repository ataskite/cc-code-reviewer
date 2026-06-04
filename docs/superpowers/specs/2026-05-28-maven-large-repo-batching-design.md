# Maven Large Repository Batch Review Design

## Purpose

Add a reliable large-repository review mode for Maven multi-module Java projects.
The first version covers only:

- Maven multi-module projects
- Stock review
- Full-code review scope
- Repositories large enough that one review agent cannot complete the full scan in a practical context/time budget

Incremental review, Gradle projects, single-module projects, and partial module review keep the current flow.

The design starts from `master` and does not reuse the previous `feat/large-repo-and-pattern-support` implementation.

## Goals

- Split large Maven repositories into review batches that preserve module relationships.
- Keep each batch near a useful review cost and context size instead of blindly maximizing lines.
- Let users run a subset of batches per session and continue on another day.
- Never rerun completed batches unless the user explicitly asks to replan or rerun them.
- Keep runtime state simple, human-readable, and recoverable.
- Use jdtls when available to understand cross-directory call chains, without letting one batch expand its formal review boundary.
- Produce per-batch local reports and a final merged report when enough completed batches exist.
- Split oversized top-level modules recursively instead of emitting a giant batch.
- Rebalance tiny tail units so small Maven modules such as bootstrap or BOM modules do not become standalone review batches.

## Non-Goals

- No file-level checkpointing.
- No partial batch resume.
- No per-file reviewed state.
- No mandatory jdtls dependency.
- No attempt to classify findings outside a batch's review roots as formal findings for that batch.
- No Gradle or incremental large-review flow in the first version.

## Trigger

Large-repository mode is considered after the user confirms:

1. Review type: stock review.
2. Review scope: full code.
3. Project type: Maven multi-module.

The scan computes total Java LOC and Java file count from Maven modules. The default trigger is:

```text
PROJECT_TYPE = maven-multi
REVIEW_TYPE = stock
REVIEW_SCOPE = full
TOTAL_JAVA_LOC >= 120000
```

The threshold is intentionally LOC-based because the user-facing concern is whether one review can finish within context/time limits. The threshold can later become configurable, but v1 keeps it fixed.

## Batch Cost Budget

The current model context is about 200k tokens, and Claude Code can compact context during long tasks. Even with compaction, a batch should leave room for:

- skill and agent instructions
- review framework and report format
- Maven module graph
- optional jdtls summaries
- tool outputs
- local batch report output

The planner keeps the user-facing LOC thresholds for compatibility, but the internal packing target is review cost rather than raw LOC. Raw LOC remains a useful display and guardrail metric, but two modules with the same LOC can have very different review cost when one contains many controllers, mappers, message consumers, or public APIs.

The initial review cost formula is deliberately simple and deterministic:

```text
review_cost = java_loc + java_file_count * 25
```

Later versions may add stable static signals such as API count, Mapper XML count, or dependency degree. The first implementation should avoid adding jdtls-only terms to the mandatory budget formula because jdtls is optional and must not be a planning single point of failure.

The default `standard` LOC guardrails are:

```text
TARGET_BATCH_LOC = 25000
SOFT_MIN_BATCH_LOC = 15000
SOFT_MAX_BATCH_LOC = 30000
HARD_MAX_BATCH_LOC = 35000
```

The equivalent review-cost guardrails are derived from the same intended scale:

```text
TARGET_BATCH_COST = 32000
SOFT_MIN_BATCH_COST = 18000
SOFT_MAX_BATCH_COST = 38000
HARD_MAX_BATCH_COST = 45000
```

For a 500,000 LOC project:

```text
500000 / 25000 = 20 batches
expected practical range = 18-23 batches
```

If dependencies force slightly larger connected groups, a batch may enter the soft max to hard max range. A batch above either hard max must be split before it is emitted.

## Maven Module Graph

The planner builds a Maven reactor graph without running network-dependent Maven commands.

Inputs:

- root `pom.xml`
- child module `pom.xml` files
- module path
- groupId, artifactId, packaging
- Java LOC and Java file count per module
- reactor-local dependencies between modules

The graph records directed edges:

```text
module-a -> module-b
```

where `module-a` depends on `module-b`.

The planner uses static XML parsing. `mvn dependency:tree` is not required for v1 because it can be slow, environment-sensitive, or require dependency resolution.

## Module Risk Score

Modules are sorted by a simple risk score before grouping:

```text
risk_score =
  loc_score
  + dependency_degree_score
  + entrypoint_name_score
  + domain_risk_name_score
```

Name signals include:

```text
api, web, gateway, controller, service, core, domain,
auth, user, order, payment, trade, account, billing,
risk, security, admin, job, scheduler, consumer
```

The score is only used to choose planning order. It is not a finding and must not appear as a code quality conclusion.

## Work Units

The planner does not treat top-level Maven modules as the only atomic planning unit. It first normalizes the repository into work units.

Work unit kinds:

```text
module
submodule
package
entrypoint_cluster
context_only
```

Rules:

1. A top-level module at or below the soft max can become a `module` unit.
2. A top-level module above the hard max must be expanded.
3. If the oversized module has nested Maven modules, nested modules become `submodule` units.
4. If a nested module is still above the hard max, split it by stable Java package roots.
5. If a package root is still above the hard max, split by entrypoint and role clusters such as controller, service, mapper, consumer, scheduler, job, config, domain, and infrastructure.
6. A zero-LOC or tiny BOM/dependency module becomes `context_only` unless another unit has a direct relationship requiring it as a scan root.
7. Bootstrap modules such as an application server module are not emitted as standalone tiny batches. They are attached as context to the most related batch, usually the batch that reviews application assembly, framework, or cross-module wiring.

Each work unit stores:

```text
unit_id
kind
display_name
scan_roots
context_roots
java_loc
java_file_count
review_cost
risk_score
affinity_edges
```

`scan_roots` define formal finding boundaries. `context_roots` are read-only support material and do not count as reviewed coverage.

## Affinity Graph

The planner builds a weighted graph between work units. Higher weight means the units should stay in the same batch when budget allows.

Static affinity signals:

- Maven reactor dependency edge.
- Parent-child module relationship.
- Same top-level module.
- Same major package prefix or domain name.
- Bootstrap module references to server submodules.
- Shared names such as `trade`, `payment`, `mes`, `iot`, `system`, or `infra`.

jdtls affinity signals, when available:

- references
- implementations
- call hierarchy
- workspace symbols that connect entrypoints to services or mappers

jdtls signals increase edge weight but do not create mandatory dependencies. If jdtls is unavailable or slow, planning falls back to Maven and package affinity.

## Batch Planning Algorithm

The planner uses semantic-cost batching:

1. Build the Maven reactor graph.
2. Recursively build work units until no scan unit exceeds the hard LOC or review-cost max.
3. Mark zero-LOC and tiny support units as `context_only` unless they must be scanned.
4. Build the weighted affinity graph across work units.
5. Sort unassigned scan units by risk score.
6. Start a batch from the highest-risk unassigned unit.
7. Add the strongest related unassigned unit while the batch remains within the soft max.
8. If the batch remains below the soft min, fill it with the nearest compatible low-cost unit.
9. Emit the batch only after it passes hard-max validation.
10. After the first pass, run tail rebalancing for tiny batches.
11. Attach bounded `context_roots` to each batch.
12. Emit a stable plan with batch ids, scan roots, context roots, units, costs, and split reasons.

The planner optimizes for:

```text
relationship quality first
hard-max safety second
batch count third
cost balance fourth
```

It should not create many tiny batches just to maintain perfect module boundaries.

## Tail Rebalancing

Tiny tail batches waste user time and underuse the review context. After initial planning, any batch below both thresholds should be rebalanced:

```text
planned_java_loc < 5000
planned_review_cost < 8000
```

Rebalancing order:

1. Merge into the strongest-affinity batch if the target remains under the hard max.
2. Otherwise merge into the lowest-cost compatible batch under the hard max.
3. Otherwise convert the tiny unit to `context_only` if it has no meaningful Java scan surface.
4. Only keep a tiny standalone batch if no legal merge exists and it contains real Java scan roots.

This rule exists specifically to avoid batches such as a 151-line bootstrap module or a zero-LOC dependency module becoming standalone work.

## Oversized Modules

If one module exceeds `HARD_MAX_BATCH_LOC`, it is split by directory roots, not by individual files.

Preferred split order:

1. Nested Maven modules under the oversized module.
2. Major domain package under `src/main/java`.
3. Entrypoint and role clusters such as controller, consumer, scheduler, job, gateway, service, mapper, domain, and config.
4. Stable package directories that keep related controller-service-mapper flows together where possible.
5. Test/resource directories are kept as context roots when useful, but Java LOC budgeting is based on Java source roots.

The batch records:

```json
{
  "split_reason": "oversized_module_package_split",
  "original_module": "risk-engine",
  "unit_kind": "package"
}
```

The planner must not emit an oversized top-level module as a batch merely because it detected that the module should be split. Detection and actual split are part of the same contract.

## Context Roots

Context roots help an agent understand a batch without expanding formal review coverage. They must be bounded.

Rules:

- `context_roots` are never counted as reviewed files.
- Formal findings must stay inside `scan_roots`.
- Per-batch context cost should stay below 25% of the batch scan cost.
- Shared framework or bootstrap context should be summarized or attached selectively, not repeated in every batch.
- If a context root is large, attach only the closest package or module summary where possible.

This prevents a small scan batch from silently becoming a huge context-reading task.

## jdtls Role

jdtls is recommended but not required.

When available, jdtls is used to improve understanding:

- definitions
- references
- implementations
- call hierarchy
- diagnostics

When unavailable, the planner and agents continue with Maven static dependency batching.

The design separates formal review boundaries from semantic lookup boundaries:

```text
formal review boundary = scan_roots
semantic lookup boundary = whole workspace via jdtls
```

Batch agents may use jdtls to inspect code outside `scan_roots` to understand cross-module call chains. However:

- Formal findings must point to locations inside the batch `scan_roots`.
- Code outside `scan_roots` can be cited only as external context.
- If the likely issue location is outside `scan_roots`, the batch report records it as a cross-batch review lead, not as a formal finding.

This keeps batch boundaries stable while preserving the value of LSP-based semantic navigation.

## Run Directory

Each large review creates a persistent run directory:

```text
.cc-code-reviewer/runs/{RUN_ID}/
├── plan.json
├── batches/
│   ├── batch-001.json
│   └── batch-002.json
├── results/
│   ├── batch-001.status.json
│   ├── batch-001.md
│   └── batch-002.status.json
├── progress.jsonl
└── final/
```

`RUN_ID` format:

```text
{YYYYMMDD-HHmmss}-{BRANCH_SLUG}-{REVIEW_MODE}-full-large-maven
```

`plan.json` is immutable by default. Resuming a run does not replan. Replanning requires explicit user confirmation and creates a new run directory.

## Batch Plan Schema

`batches/batch-001.json` stores a directory-level plan, not a full file manifest.

Example:

```json
{
  "schema_version": 1,
  "run_id": "20260528-143000-master-standard-full-large-maven",
  "batch_id": "batch-001",
  "batch_index": 1,
  "batch_count": 20,
  "strategy": "semantic-cost-batching",
  "semantic_level": "jdtls-lsp",
  "planned_review_cost": 31250,
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "scan_roots": [
    "order/order-api",
    "order/order-service",
    "order/order-dao"
  ],
  "context_roots": [
    "server/bootstrap"
  ],
  "units": [
    {
      "unit_id": "module:order/order-api",
      "kind": "module",
      "name": "order-api",
      "path": "order/order-api",
      "java_loc": 6200,
      "java_file_count": 48,
      "review_cost": 7400,
      "role": "entrypoint"
    },
    {
      "unit_id": "module:order/order-service",
      "kind": "module",
      "name": "order-service",
      "path": "order/order-service",
      "java_loc": 12800,
      "java_file_count": 92,
      "review_cost": 15100,
      "role": "core"
    },
    {
      "unit_id": "module:order/order-dao",
      "kind": "module",
      "name": "order-dao",
      "path": "order/order-dao",
      "java_loc": 5800,
      "java_file_count": 46,
      "review_cost": 6950,
      "role": "dependency"
    }
  ],
  "affinity_edges": [
    {"from": "order-api", "to": "order-service", "reason": "reactor dependency"},
    {"from": "order-service", "to": "order-dao", "reason": "reactor dependency"}
  ],
  "semantic_lookup": {
    "jdtls_cross_root_lookup": true,
    "formal_findings_must_be_inside_scan_roots": true
  },
  "split_reason": "dependency_affinity_group",
  "result_path": "results/batch-001.md",
  "status_path": "results/batch-001.status.json"
}
```

There is no file manifest in v1. The batch agent scans files under `scan_roots`.

The schema may keep `modules` as a compatibility alias during migration, but `units` is the canonical planning field for the refined algorithm.

## Batch Status

Batches are atomic. A batch is either fully completed or must be rerun.

Internal states:

```text
pending
running
completed
failed
```

User-facing states:

```text
pending   -> 待执行
running   -> 执行中
completed -> 已完成
failed    -> 失败待重试
```

If a previous session ended while a batch was `running`, resume reconciliation changes it to `failed` with an error such as:

```text
上次执行中断，需要整批重跑
```

No `partial`, `stale`, `skipped`, or file-level status exists in v1.

`results/batch-001.status.json` example:

```json
{
  "schema_version": 1,
  "run_id": "20260528-143000-master-standard-full-large-maven",
  "batch_id": "batch-001",
  "status": "completed",
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "attempt": 1,
  "started_at": "2026-05-28T14:30:00Z",
  "finished_at": "2026-05-28T15:05:00Z",
  "result_path": "results/batch-001.md",
  "finding_count": 12,
  "error": null
}
```

## Atomic Writes

Status files and plan files are written atomically:

```text
write file.tmp
validate where practical
mv file.tmp file
```

`progress.jsonl` is append-only. It records coarse events:

```json
{"event":"run_created","run_id":"...","time":"..."}
{"event":"batch_started","batch_id":"batch-001","attempt":1,"time":"..."}
{"event":"batch_completed","batch_id":"batch-001","finding_count":12,"time":"..."}
{"event":"batch_failed","batch_id":"batch-003","error":"subagent failed","time":"..."}
```

## Resume Rules

On resume:

1. Find the latest compatible unfinished run for the project, branch, review mode, and full scope.
2. Read `plan.json`.
3. Reconcile all status files.
4. Convert old `running` statuses to `failed`.
5. Skip `completed` batches.
6. Offer to execute `pending` and/or `failed` batches.

The user can choose:

```text
继续待执行批次
先重试失败批次
执行全部未完成批次
重新规划
退出
```

Completed batches are not rerun unless the user explicitly chooses to replan or force rerun.

## Per-Run Execution Limit

Because a 500k LOC project may produce around 20 batches, each invocation can execute a bounded number of batches.

The interaction asks:

```text
请选择本轮执行批次
- 执行 3 批
- 执行 5 批（推荐）
- 执行 10 批
- 执行全部未完成批次
```

This lets users spend a daily quota on part of the run and continue later.

## Status Console

Add a script:

```text
scripts/phase13-show-large-batch-status.sh
```

It prints the latest compatible run and a Chinese status table.

Example:

```text
大仓库审查任务

Run ID: 20260528-143000-master-standard-full-large-maven
项目: demo-large-repo
模式: standard
范围: 全量代码
语义增强: jdtls-lsp
总规模: 500,000 行
批次: 20
完成: 6 / 20
Java 行覆盖: 148,200 / 500,000 (29%)
最近更新: 2026-05-28 16:40

批次  状态        行数     文件  模块
001   已完成      24,800   186   user-api,user-service
002   已完成      26,100   201   order-core,order-dao
003   失败待重试  21,700   144   payment
004   待执行      25,200   190   inventory

建议:
- 下一批: 004-008
- 可重试失败批次: 003
```

The status table intentionally uses Chinese labels. English enum values stay internal.

## Batch Agent Contract

For batch mode, the parent skill injects:

- `RUN_DIR`
- `BATCH_PLAN_PATH`
- `BATCH_STATUS_PATH`
- `BATCH_RESULT_PATH`
- `PROJECT_DIR`
- `scan_roots`
- Maven module graph summary
- jdtls capability summary

The batch agent must:

1. Read `BATCH_PLAN_PATH`.
2. Treat `scan_roots` as formal review boundaries.
3. Scan files under `scan_roots`.
4. Use jdtls outside `scan_roots` only for semantic lookup.
5. Write formal findings only for locations inside `scan_roots`.
6. Write `BATCH_RESULT_PATH` as the local batch report.
7. Write `BATCH_STATUS_PATH` as `completed` only after the batch report is fully written.
8. Write `failed` if it cannot complete the batch.

The parent skill sets a batch to `running` before launching the child agent. The child agent completes or fails it.

## Cross-Batch Leads

If jdtls reveals that a risk likely belongs outside the current `scan_roots`, the batch report records:

```text
跨批依赖待复核
```

These leads are not counted as formal findings unless the location is inside the batch roots. The final merge can list them in a separate section:

```text
跨批依赖线索
```

This prevents one batch from overclaiming issues in another batch while preserving useful navigation signals.

## Merge Rules

The merge script reads only completed batches by default.

Add a script:

```text
scripts/phase12-merge-large-batches.sh
```

It creates:

```text
final/code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md
summary.json
```

The report can be:

- staged report: some batches completed
- full report: all batches completed

Staged reports must be titled with `[阶段性]` and clearly show coverage.

Full reports require:

```text
completed_batch_count == batch_count
```

The report includes:

- Run ID
- review branch
- review mode
- jdtls status
- semantic-cost batching summary
- completed/failed/pending batch counts
- Java file count coverage
- per-batch summary
- merged findings from completed batch reports
- cross-batch leads

Java file coverage remains the primary coverage metric:

```text
Java 文件覆盖率 = reviewed_java_file_count / selected_java_file_count
```

LOC and review cost are planning metrics, not coverage metrics.

## Feishu Upload

Batch agents never upload to Feishu.

Only the parent skill uploads:

- staged merged report if the user requests it
- full merged report after all batches complete

Feishu report titles include `[阶段性]` when not all batches are complete.

If writing to Feishu Base, each finding includes:

- `run_id`
- `batch_id`
- `batch_status=已完成`
- `coverage_scope=阶段性/完整`

## Error Handling

| Scenario | Handling |
| --- | --- |
| jdtls unavailable | Continue with Maven static dependency batching and show recommendation |
| batch agent fails | Mark batch `failed`; keep other batches running |
| session ends while batch running | On resume, convert `running` to `failed` and rerun whole batch if selected |
| completed result missing | Treat as `failed` during reconcile |
| plan exists but branch/scope/mode differs | Do not reuse; create or ask for a compatible run |
| all batches fail | Do not merge; show status table and retry options |
| some batches complete | Allow staged report with explicit coverage |

## Testing

Add focused Bash tests:

- Maven reactor graph parsing with local inter-module dependencies.
- Batch planning keeps related modules together when under the soft max.
- Batch planning recursively splits oversized top-level modules above the hard max.
- Batch planning recursively splits oversized nested modules by package roots.
- Batch planning never emits a batch above `HARD_MAX_BATCH_LOC` or `HARD_MAX_BATCH_COST`.
- Batch planning does not create standalone zero-LOC dependency batches.
- Batch planning rebalances tiny tail batches when a legal merge exists.
- Bootstrap modules such as server modules become bounded context roots instead of tiny standalone batches when they have negligible Java LOC.
- Context root cost stays bounded and is not counted as coverage.
- Batch count for a synthetic 500k LOC repo lands near the expected range.
- jdtls unavailable path still plans with `semantic_level=maven-static`.
- jdtls available path adds affinity metadata but does not change formal findings boundaries.
- Status console renders Chinese labels.
- Resume converts `running` to `failed`.
- Completed batches are skipped on resume.
- Merge only reads completed batch reports.
- Staged report is marked `[阶段性]`.
- Full report requires all batches completed.

Update contract tests to ensure:

- large mode is Maven multi-module stock full-scope only
- batch status states are only pending/running/completed/failed
- no file-level reviewed manifest is required
- batch agents may use jdtls outside scan roots for understanding
- formal findings must be inside scan roots
- oversized modules are split before plan emission rather than only marked as needing split
- tiny tail batches are merged, converted to context, or explicitly justified

## Open Decisions

None. The design intentionally keeps the first refined version practical:

- batch is atomic
- work units define the batch
- jdtls is semantic lookup, not a hard dependency
- completed work is preserved across sessions
- Java file coverage remains the only coverage metric
