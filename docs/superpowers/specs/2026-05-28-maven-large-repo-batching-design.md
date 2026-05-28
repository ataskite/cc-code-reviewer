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
- Keep each batch near a useful context size instead of blindly maximizing lines.
- Let users run a subset of batches per session and continue on another day.
- Never rerun completed batches unless the user explicitly asks to replan or rerun them.
- Keep runtime state simple, human-readable, and recoverable.
- Use jdtls when available to understand cross-directory call chains, without letting one batch expand its formal review boundary.
- Produce per-batch local reports and a final merged report when enough completed batches exist.

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

## Batch Size Budget

The current model context is about 200k tokens, and Claude Code can compact context during long tasks. Even with compaction, a batch should leave room for:

- skill and agent instructions
- review framework and report format
- Maven module graph
- optional jdtls summaries
- tool outputs
- local batch report output

The default `standard` budget is:

```text
TARGET_BATCH_LOC = 25000
SOFT_MIN_BATCH_LOC = 15000
SOFT_MAX_BATCH_LOC = 30000
HARD_MAX_BATCH_LOC = 35000
```

For a 500,000 LOC project:

```text
500000 / 25000 = 20 batches
expected practical range = 18-23 batches
```

If dependencies force slightly larger connected groups, a batch may enter the 30k-35k range. A batch above 35k must be split.

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

## Batch Planning Algorithm

The planner treats Maven modules/directories as the atomic unit for normal modules.

1. Build the Maven reactor graph.
2. Sort candidate root modules by risk score.
3. Start a batch from the highest-risk unassigned module.
4. Add strongly related reactor modules while the batch remains within `SOFT_MAX_BATCH_LOC`.
5. Prefer dependency-near modules over unrelated modules when filling a batch.
6. If a batch is below `SOFT_MIN_BATCH_LOC`, merge it with the nearest dependency neighbor when possible.
7. If a module or module group exceeds `HARD_MAX_BATCH_LOC`, split it by directory/package roots.
8. Emit a stable plan with batch ids and scan roots.

The planner optimizes for:

```text
relationship quality first
batch count second
line balance third
```

It should not create many tiny batches just to maintain perfect module boundaries.

## Oversized Modules

If one module exceeds `HARD_MAX_BATCH_LOC`, it is split by directory roots, not by individual files.

Preferred split order:

1. `src/main/java` package prefix
2. entrypoint areas such as controller, consumer, scheduler, job, gateway
3. major domain package
4. test/resource directories are kept as context roots when useful, but Java LOC budgeting is based on Java source roots

The batch records:

```json
{
  "split_reason": "oversized_module",
  "original_module": "risk-engine"
}
```

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
  "strategy": "maven-module-batching",
  "semantic_level": "jdtls-lsp",
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "scan_roots": [
    "order/order-api",
    "order/order-service",
    "order/order-dao"
  ],
  "modules": [
    {
      "name": "order-api",
      "path": "order/order-api",
      "java_loc": 6200,
      "java_file_count": 48,
      "role": "entrypoint"
    },
    {
      "name": "order-service",
      "path": "order/order-service",
      "java_loc": 12800,
      "java_file_count": 92,
      "role": "core"
    },
    {
      "name": "order-dao",
      "path": "order/order-dao",
      "java_loc": 5800,
      "java_file_count": 46,
      "role": "dependency"
    }
  ],
  "module_dependency_edges": [
    {"from": "order-api", "to": "order-service", "reason": "reactor dependency"},
    {"from": "order-service", "to": "order-dao", "reason": "reactor dependency"}
  ],
  "semantic_lookup": {
    "jdtls_cross_root_lookup": true,
    "formal_findings_must_be_inside_scan_roots": true
  },
  "split_reason": null,
  "result_path": "results/batch-001.md",
  "status_path": "results/batch-001.status.json"
}
```

There is no file manifest in v1. The batch agent scans files under `scan_roots`.

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
- Maven static dependency batching summary
- completed/failed/pending batch counts
- Java LOC coverage
- Java file count coverage
- per-batch summary
- merged findings from completed batch reports
- cross-batch leads

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
- Batch planning splits oversized modules above the hard max.
- Batch count for a synthetic 500k LOC repo lands near the expected range.
- jdtls unavailable path still plans with `semantic_level=maven-static`.
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

## Open Decisions

None. The design intentionally keeps v1 simple:

- batch is atomic
- module/directory roots define the batch
- jdtls is semantic lookup, not a hard dependency
- completed work is preserved across sessions
