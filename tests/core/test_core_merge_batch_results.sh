#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-merge.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run"; mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
cat > "$RUN_DIR/plan.json" <<'JSON'
{"schema_version":1,"run_id":"r1","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b"}]}
JSON
cat > "$RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/batch-001.md","finding_count":1}
JSON
cat > "$RUN_DIR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度4-状态与数据请求] 示例
- 文件：src/a/x.tsx:10
- 证据：示例
- 建议：示例
MD

# batch-002 未完成 → 合并阻塞
MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
        bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" 2>&1 || true)"
grep -q "MERGE_BLOCKED=true" <<< "$MOUT"

# 仅 batch-001（未纳入 batch-002）→ 阶段性报告标题
MOUT2="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" || true)"
SUMM="$(printf '%s\n' "$MOUT2" | sed -n 's/^SUMMARY_PATH=//p')"
grep -q '"source_file_coverage_percent"' "$SUMM"
grep -q '"report_title"' "$SUMM"
grep -q '"finding_count": 1' "$SUMM"
REPORT="$(printf '%s\n' "$MOUT2" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT" | grep -q '\[阶段性\]'

# 两批都 completed 且都纳入 → 完整报告（无 [阶段性] / [合并阻塞]）
cat > "$RUN_DIR/results/batch-002.status.json" <<JSON
{"batch_id":"batch-002","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/batch-002.md","finding_count":0}
JSON
cat > "$RUN_DIR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
MD
MOUT3="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" 2>&1 || true)"
REPORT3="$(printf '%s\n' "$MOUT3" | sed -n 's/^FINAL_REPORT_PATH=//p')"
head -n1 "$REPORT3" | grep -qv '\[阶段性\]'
head -n1 "$REPORT3" | grep -qv '\[合并阻塞\]'

# ---- partial（部分完成）状态：目标批次有结果 → 发现纳入合并，覆盖保守不计 ----
# 场景 1：2 批计划，本轮只调度 batch-001，其状态为 partial 且结果文件存在
PRUN="$TMP_DIR/partial-run"; mkdir -p "$PRUN/batches" "$PRUN/results"
cat > "$PRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"pr1","project_name":"demo partial","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$PRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$PRUN/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b"}]}
JSON
cat > "$PRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"partial","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$PRUN/results/batch-001.md","finding_count":1,"error":"中断"}
JSON
cat > "$PRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度4-状态与数据请求] 部分完成示例
- 文件：src/a/x.tsx:10
- 证据：示例
- 建议：示例

## 覆盖情况
- 中断前已覆盖 src/a/x.tsx
MD
PMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PRUN" || true)"
PSUMM="$(printf '%s\n' "$PMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
PREPORT="$(printf '%s\n' "$PMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '"partial_batches": 1' "$PSUMM"
grep -qF '"partial_batch_ids": ["batch-001"]' "$PSUMM"
grep -qF '"merged_batch_ids": ["batch-001"]' "$PSUMM"
grep -qF '"included_batches": 0' "$PSUMM"
grep -q '"finding_count": 1' "$PSUMM"
grep -q '"covered_source_file_count": 0' "$PSUMM"
grep -q '"merge_blocked": false' "$PSUMM"
grep -q '"report_title": "\[阶段性\] 代码审查报告 - demo partial"' "$PSUMM"
head -n1 "$PREPORT" | grep -q '\[阶段性\]'
grep -qF '| batch-001 | 部分完成待重跑 | 是 | 部分完成已纳入 | 1 | 250 | a | [输出中断] 中断 |' "$PREPORT"
grep -q '^### batch-001 - a$' "$PREPORT"
grep -q '中断前已覆盖 src/a/x.tsx' "$PREPORT"

# 对比：同一场景补上 batch-002 completed → 只有它的文件计入覆盖（partial 批次仍不计）
cat > "$PRUN/results/batch-002.status.json" <<JSON
{"batch_id":"batch-002","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$PRUN/results/batch-002.md","finding_count":0}
JSON
cat > "$PRUN/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
MD
PMOUT2="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
          bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PRUN" || true)"
PSUMM2="$(printf '%s\n' "$PMOUT2" | sed -n 's/^SUMMARY_PATH=//p')"
PREPORT2="$(printf '%s\n' "$PMOUT2" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"completed_batches": 1' "$PSUMM2"
grep -qF '"partial_batches": 1' "$PSUMM2"
grep -qF '"included_batches": 1' "$PSUMM2"
grep -q '"covered_source_file_count": 1' "$PSUMM2"
grep -q '"finding_count": 1' "$PSUMM2"
# 全部批次到达终态但存在 partial → 仍保持阶段性报告
head -n1 "$PREPORT2" | grep -q '\[阶段性\]'

# 场景 2：非目标 partial（RUN_BATCH_IDS=batch-001）→ 遗留，不纳入本轮
NPRUN="$TMP_DIR/partial-nontarget"; mkdir -p "$NPRUN/batches" "$NPRUN/results"
cat > "$NPRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"pr2","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$NPRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$NPRUN/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b"}]}
JSON
cat > "$NPRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$NPRUN/results/batch-001.md","finding_count":1}
JSON
cat > "$NPRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度4-状态与数据请求] 已完成示例
- 文件：src/a/x.tsx:10
- 证据：示例
- 建议：示例
MD
cat > "$NPRUN/results/batch-002.status.json" <<JSON
{"batch_id":"batch-002","status":"partial","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$NPRUN/results/batch-002.md","finding_count":1,"error":"中断"}
JSON
cat > "$NPRUN/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
### P1 | [维度4-状态与数据请求] 未纳入发现
- 文件：src/b/x.tsx:10
- 证据：示例
- 建议：示例
MD
NMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$NPRUN" || true)"
NSUMM="$(printf '%s\n' "$NMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
NREPORT="$(printf '%s\n' "$NMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '"partial_batches": 1' "$NSUMM"
grep -qF '"partial_batch_ids": ["batch-002"]' "$NSUMM"
grep -qF '"leftover_batch_ids": ["batch-002"]' "$NSUMM"
grep -q '"finding_count": 1' "$NSUMM"
grep -q '"merge_blocked": false' "$NSUMM"
grep -q 'batch-002.*部分完成未纳入本轮，遗留' "$NREPORT"
if grep -q '未纳入发现' "$NREPORT"; then
  echo "FAIL: 非目标 partial 批次的结果不得进入合并报告" >&2
  exit 1
fi

# 场景 3：目标 partial 但结果文件缺失 → 与 failed 同等阻塞（exit 2）
MPRUN="$TMP_DIR/partial-missing"; mkdir -p "$MPRUN/batches" "$MPRUN/results"
cat > "$MPRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"pr3","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$MPRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$MPRUN/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b"}]}
JSON
cat > "$MPRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"partial","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$MPRUN/results/batch-001.md","finding_count":1,"error":"中断"}
JSON
set +e
MMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$MPRUN" 2>&1)"
MSTATUS=$?
set -e
test "$MSTATUS" -eq 2
MSUMM="$(printf '%s\n' "$MMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
MREPORT="$(printf '%s\n' "$MMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"merge_blocked": true' "$MSUMM"
head -n1 "$MREPORT" | grep -q '\[合并阻塞\]'
grep -q '部分完成结果缺失遗留' "$MREPORT"

# 场景 3b：partial 声称有结果但没有正式发现 → 必须阻塞，不能把零产出当作成功
ZPRUN="$TMP_DIR/partial-zero-findings"; mkdir -p "$ZPRUN/batches" "$ZPRUN/results"
cat > "$ZPRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"pr3b","project_name":"demo","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":250,"total_source_file_count":1,"batch_count":1}
JSON
cat > "$ZPRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a"}]}
JSON
cat > "$ZPRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"partial","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$ZPRUN/results/batch-001.md","finding_count":0,"error":"中断但无发现"}
JSON
cat > "$ZPRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
（无正式发现）
MD
set +e
ZMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001 \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$ZPRUN" 2>&1)"
ZMSTATUS=$?
set -e
test "$ZMSTATUS" -eq 2
ZMSUMM="$(printf '%s\n' "$ZMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
grep -q '"merge_blocked": true' "$ZMSUMM"

# 场景 4：证据重归档钩子随合并执行（跨文件唯一命中 → 重归档到 src/b.js）
RPROJ="$TMP_DIR/reloc-proj"; mkdir -p "$RPROJ/src"
printf 'export const alpha = 1;\nexport const beta = 2;\n' > "$RPROJ/src/a.js"
cat > "$RPROJ/src/b.js" <<'JS'
export function trackEvent(name) {
  analytics.send(name);
}
JS
RRUN="$TMP_DIR/reloc-run"; mkdir -p "$RRUN/batches" "$RRUN/results"
cat > "$RRUN/plan.json" <<JSON
{"schema_version":1,"run_id":"rr1","project_name":"reloc-demo","project_dir":"$RPROJ",
 "review_mode":"standard","review_scope":"全量代码","language_id":"frontend",
 "review_input_path":"$RRUN/review-input.json",
 "total_source_loc":5,"total_source_file_count":2,"batch_count":1}
JSON
cat > "$RRUN/review-input.json" <<'JSON'
{"schema_version":1,"selection_mode":"workspace","items":[
 {"path":"src/a.js","change":"M","old_path":"","selected":true,"exclude_reason":"","insertions":2,"deletions":0,"fingerprint":"fa"},
 {"path":"src/b.js","change":"M","old_path":"","selected":true,"exclude_reason":"","insertions":3,"deletions":0,"fingerprint":"fb"}]}
JSON
cat > "$RRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":5,"planned_source_file_count":2,
 "scan_roots":["src"],"modules":[{"name":"src"}]}
JSON
cat > "$RRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":5,
 "planned_source_file_count":2,"result_path":"$RRUN/results/batch-001.md","finding_count":1}
JSON
cat > "$RRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度5-安全] 埋点泄露
- 文件：src/a.js:5
- 证据：
  ```js
  export function trackEvent(name) {
    analytics.send(name);
  }
  ```
- 建议：脱敏
MD
RMOUT="$(bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RRUN")"
RSUMM="$(printf '%s\n' "$RMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
RREPORT="$(printf '%s\n' "$RMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '"relocation": {"enabled": true, "same_file_fixed": 0, "refiled": 1, "unresolved": 0}' "$RSUMM"
perl -MJSON::PP -0777 -e 'decode_json(<>)' "$RSUMM" >/dev/null
grep -q '^- 文件：src/b.js:1$' "$RREPORT"
grep -qF -- '- 位置修正：原 src/a.js:5，证据代码实际位于本文件（跨文件重归档）' "$RREPORT"
grep -qF '跨文件重归档：修正行号 0 处、迁移发现 1 条（证据代码位于其他文件）。' "$RREPORT"
if grep -q '^- 文件：src/a.js:5$' "$RREPORT"; then
  echo "FAIL: 重归档后旧位置行必须被重写" >&2
  exit 1
fi

# 场景 4b：缺少冻结审查输入 → fail-open 跳过重归档（summary 无 relocation 键，报告披露跳过原因）
NRRUN="$TMP_DIR/reloc-noinput"; mkdir -p "$NRRUN/batches" "$NRRUN/results"
cat > "$NRRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"rr2","project_name":"reloc-demo",
 "review_mode":"standard","review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":5,"total_source_file_count":2,"batch_count":1}
JSON
cat > "$NRRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":5,"planned_source_file_count":2,
 "scan_roots":["src"],"modules":[{"name":"src"}]}
JSON
cat > "$NRRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":5,
 "planned_source_file_count":2,"result_path":"$NRRUN/results/batch-001.md","finding_count":1}
JSON
cat > "$NRRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度5-安全] 埋点泄露
- 文件：src/a.js:5
- 证据：
  ```js
  export function trackEvent(name) {
    analytics.send(name);
  }
  ```
- 建议：脱敏
MD
NRMOUT="$(bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$NRRUN")"
NRSUMM="$(printf '%s\n' "$NRMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
NRREPORT="$(printf '%s\n' "$NRMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
if grep -q '"relocation"' "$NRSUMM"; then
  echo "FAIL: 缺少冻结审查输入时 summary 不得包含 relocation 键" >&2
  exit 1
fi
perl -MJSON::PP -0777 -e 'decode_json(<>)' "$NRSUMM" >/dev/null
grep -qF '# 跨文件重归档：跳过（缺少冻结审查输入）' "$NRREPORT"
grep -q '^- 文件：src/a.js:5$' "$NRREPORT"

# ---- 内容指纹去重（确定性、零 LLM）：身份锚定 文件路径 × 维度标签 × 归一化证据代码，
# 不锚定标题/建议散文与行号；块既缺「文件行」又缺「围栏证据」时退回整块空白折叠键。
# 披露契约：summary.json 仅在 N>0 时含 dedup 对象（N 进入数/M 合并重复数/K 输出数，
# 且置于 report_title 之前）；报告“覆盖说明”区仅在 M>0 时追加“跨批次去重”一行。 ----
FP_PROJ="$TMP_DIR/fp-proj"; mkdir -p "$FP_PROJ/src"
printf 'export const seed = 1;\n' > "$FP_PROJ/src/a.js"
printf 'export const other = 2;\n' > "$FP_PROJ/src/b.js"
printf 'export const third = 3;\n' > "$FP_PROJ/src/c.js"

setup_fp_run() {
  local name="$1" nbatch="${2:-2}" bid i
  FP_RUN="$TMP_DIR/fp-runs/$name"; mkdir -p "$FP_RUN/batches" "$FP_RUN/results"
  # 故意不提供 project_dir/review_input_path：重归档钩子按“缺少冻结审查输入”跳过，
  # 与去重场景完全隔离。
  cat > "$FP_RUN/plan.json" <<JSON
{"schema_version":1,"run_id":"fp-$name","project_name":"fp","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":30,"total_source_file_count":3,"batch_count":$nbatch}
JSON
  for ((i = 1; i <= nbatch; i++)); do
    bid="$(printf 'batch-%03d' "$i")"
    cat > "$FP_RUN/batches/$bid.json" <<JSON
{"batch_id":"$bid","planned_source_loc":15,"planned_source_file_count":1,
 "scan_roots":["src"],"modules":[{"name":"src"}]}
JSON
    cat > "$FP_RUN/results/$bid.status.json" <<JSON
{"batch_id":"$bid","status":"completed","planned_source_loc":15,
 "planned_source_file_count":1,"result_path":"$FP_RUN/results/$bid.md","finding_count":1}
JSON
  done
}

merge_fp_run() {
  FP_OUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$FP_RUN")"
  FP_SUMM="$(printf '%s\n' "$FP_OUT" | sed -n 's/^SUMMARY_PATH=//p')"
  FP_REPORT="$(printf '%s\n' "$FP_OUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
  perl -MJSON::PP -0777 -e 'decode_json(<>)' "$FP_SUMM" >/dev/null
}

# 用例 1（改写合并）：同一缺陷两个批次 —— 标题改写、严重级别字母不同、标点不同、
# 建议句序交换、行号漂移、围栏缩进 + 围栏内空行全部不同，但 文件×维度×证据代码
# 相同 → 合并为一条，保留首现块的原文。
setup_fp_run "fp-paraphrase"
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

### P1 [维度5-安全] 存在SQL拼接风险
- 文件：src/a.js:10
- 置信度：高
- 证据：
  ```js
  db.query("select * from t where id="+id);
  ```
- 建议：先校验参数；再改为参数化查询
MD
cat > "$FP_RUN/results/batch-002.md" <<'MD'
## 发现列表

### P0 [维度5-安全] 拼接SQL导致注入！！
- 文件：src/a.js:88
- 证据：
    ```js
      db.query("select * from t where id="+id);

    ```
- 建议：再改为参数化查询；先校验参数
MD
merge_fp_run
grep -q '"finding_count": 1' "$FP_SUMM"
grep -qF '"dedup": {"input_findings": 2, "merged_duplicates": 1, "output_findings": 1}' "$FP_SUMM"
grep -qF '跨批次去重：2 条发现中合并重复 1 条（按文件 × 维度 × 证据代码指纹），保留 1 条。' "$FP_REPORT"
grep -q '存在SQL拼接风险' "$FP_REPORT"
if grep -q '拼接SQL导致注入' "$FP_REPORT"; then
  echo "FAIL: 同指纹改写块必须整块丢弃，只保留首现批次内容" >&2
  exit 1
fi

# 用例 2（维度入键）：同文件同证据但维度标签不同 → 必须两条都保留；M=0 时既不合并
# 也不出现“跨批次去重”披露行（dedup 对象本身仍存在并以 0 披露）。
setup_fp_run "fp-dim-guard"
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

### P1 [维度2-性能] 串行等待外部接口超时
- 文件：src/a.js:17
- 证据：
  ```js
  await fetch(url, { timeoutMs: 60000 });
  ```
MD
cat > "$FP_RUN/results/batch-002.md" <<'MD'
## 发现列表

### P1 [维度5-安全] 接口响应未校验来源
- 文件：src/a.js:41
- 证据：
  ```js
  await fetch(url, { timeoutMs: 60000 });
  ```
MD
merge_fp_run
grep -q '"finding_count": 2' "$FP_SUMM"
grep -qF '"dedup": {"input_findings": 2, "merged_duplicates": 0, "output_findings": 2}' "$FP_SUMM"
grep -q '串行等待外部接口超时' "$FP_REPORT"
grep -q '接口响应未校验来源' "$FP_REPORT"
if grep -q '跨批次去重' "$FP_REPORT"; then
  echo "FAIL: M=0 时报告不得出现跨批次去重披露行" >&2
  exit 1
fi

# 用例 3（防误并）：维度、标题完全相同但文件与证据代码不同 → 都保留（标题不参与身份；
# 同时证明仅凭“同文件”或“同维度”绝不触发合并）。子场景 3b：连文件都相同、仅证据代码
# 不同 → 仍都必须保留（证据代码在身份内）。
setup_fp_run "fp-nomerge-files"
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

### P1 [维度5-安全] 明文输出敏感字段
- 文件：src/a.js:14
- 证据：
  ```js
  console.log(req.headers.authorization);
  ```
MD
cat > "$FP_RUN/results/batch-002.md" <<'MD'
## 发现列表

### P1 [维度5-安全] 明文输出敏感字段
- 文件：src/b.js:14
- 证据：
  ```js
  console.log(user.profile.email);
  ```
MD
merge_fp_run
grep -q '"finding_count": 2' "$FP_SUMM"
test "$(grep -c '^### P1 \[维度5-安全\] 明文输出敏感字段$' "$FP_REPORT")" = "2"

setup_fp_run "fp-nomerge-evidence"
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

### P1 [维度2-性能] 大集合全量序列化
- 文件：src/a.js:23
- 证据：
  ```js
  cache.set(key, JSON.stringify(rows));
  ```
MD
cat > "$FP_RUN/results/batch-002.md" <<'MD'
## 发现列表

### P1 [维度2-性能] 大集合全量序列化
- 文件：src/a.js:23
- 证据：
  ```js
  res.write(JSON.stringify(chunk));
  ```
MD
merge_fp_run
grep -q '"finding_count": 2' "$FP_SUMM"
test "$(grep -c '^### P1 \[维度2-性能\] 大集合全量序列化$' "$FP_REPORT")" = "2"

# 用例 4（归一化证明）：证据行仅在 缩进 / 一个 +/- diff 前缀 / 行尾空白 / 中间空行 /
# CRLF 行尾 上不同 → 指纹相同必须合并（relocate-findings.sh norm_line 同口径）。
setup_fp_run "fp-normalize"
{
  printf '## 发现列表\r\n\r\n'
  printf '### P2 [维度2-性能] 循环内重复取值\r\n'
  printf -- '- 文件：src/a.js:21\r\n'
  printf -- '- 证据：\r\n'
  printf '  ```js\r\n'
  printf '  for (let i = 0; i < arr.length; i++) {\r\n'
  printf '    total += priceOf(items[i]);\r\n'
  printf '  }\r\n'
  printf '  ```\r\n'
} > "$FP_RUN/results/batch-001.md"
{
  printf '## 发现列表\r\n'
  printf '\r\n'
  printf '### P2 [维度2-性能] 迭代期间反复计算代价\r\n'
  printf -- '- 文件：src/a.js:57\r\n'
  printf -- '- 证据：\r\n'
  printf '    ```js\r\n'
  printf 'for (let i = 0; i < arr.length; i++) {\r\n'
  printf '+  total += priceOf(items[i]);   \r\n'
  printf '}\r\n'
  printf '\r\n'
  printf '  ```\r\n'
} > "$FP_RUN/results/batch-002.md"
merge_fp_run
grep -q '"finding_count": 1' "$FP_SUMM"
grep -qF '"dedup": {"input_findings": 2, "merged_duplicates": 1, "output_findings": 1}' "$FP_SUMM"
grep -qF '跨批次去重：2 条发现中合并重复 1 条（按文件 × 维度 × 证据代码指纹），保留 1 条。' "$FP_REPORT"
grep -q '循环内重复取值' "$FP_REPORT"
if grep -q '迭代期间反复计算代价' "$FP_REPORT"; then
  echo "FAIL: 归一化等价的证据块必须按指纹合并" >&2
  exit 1
fi

# 用例 5（legacy 兜底 + 统计口径）：无「文件行」也无「围栏证据」的裸散文块退回旧的
# 整块空白折叠键 —— 仅空白差异的副本仍被旧语义合并；正文不同的异文块保持存活；
# 只有「文件行」没有围栏的定位块按指纹（路径×维度×空证据）合并。三种键的输入全部
# 计入 dedup 统计。
setup_fp_run "fp-legacy-mixed"
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

### 待确认 [维度11-可观测性] 补充手动核对清单项
- 依据：需要人工巡检后的结论回填
- 影响面：观测指标缺口暂无法量化

### 待确认 [维度11-可观测性] 巡检项需要运维补充结论
- 依据：同类缺口另见后续运维反馈清单

### P2 [维度9-错误处理] 缺少事务回滚分支
- 文件：src/c.js
- 置信度：低
MD
cat > "$FP_RUN/results/batch-002.md" <<'MD'
## 发现列表

### 待确认 [维度11-可观测性] 补充手动核对清单项

- 依据：需要人工巡检后的结论回填
- 影响面：观测指标缺口暂无法量化

### 待确认 [维度11-可观测性] 巡检口径需引入灰度比对样本
- 依据：第二批次对同一维度的另一种散文表述（应存活）

### P2 [维度9-错误处理] 回滚调用点核对占位
- 文件：src/c.js
- 复核人：后端组
MD
merge_fp_run
grep -q '"finding_count": 4' "$FP_SUMM"
grep -qF '"dedup": {"input_findings": 6, "merged_duplicates": 2, "output_findings": 4}' "$FP_SUMM"
test "$(grep -c '^### 待确认 \[维度11-可观测性\]$' "$FP_REPORT")" = "0"
test "$(grep -c '补充手动核对清单项' "$FP_REPORT")" = "1"
grep -q '巡检项需要运维补充结论' "$FP_REPORT"
grep -q '巡检口径需引入灰度比对样本' "$FP_REPORT"
test "$(grep -c '^### P2 \[维度9-错误处理\]' "$FP_REPORT")" = "1"
grep -q '缺少事务回滚分支' "$FP_REPORT"
if grep -q '回滚调用点核对占位' "$FP_REPORT"; then
  echo "FAIL: 定位块（无围栏）同路径同维度的重复必须按指纹合并" >&2
  exit 1
fi

# 用例 6（待确认同权）：待确认表头与 P0-P3 一样参与指纹身份；除标题与置信度行外
# 完全相同的两批 发现 → 合并，第三个不同文件的对照块存活。
setup_fp_run "fp-todo-parity"
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

### 待确认 [维度12-测试盲区] 缺少空集合边界用例
- 文件：src/a.js:33
- 证据：
  ```js
  render({ items });
  ```
MD
cat > "$FP_RUN/results/batch-002.md" <<'MD'
## 发现列表

### 待确认 [维度12-测试盲区] 集合判空逻辑待复核
- 置信度：中
- 文件：src/a.js:33
- 证据：
  ```js
  render({ items });
  ```

### P0 [维度13-资源管理] 句柄未显式关闭
- 文件：src/b.js:8
- 证据：
  ```js
  file.readToEnd();
  ```
MD
merge_fp_run
grep -q '"finding_count": 2' "$FP_SUMM"
grep -qF '"dedup": {"input_findings": 3, "merged_duplicates": 1, "output_findings": 2}' "$FP_SUMM"
grep -qF '跨批次去重：3 条发现中合并重复 1 条（按文件 × 维度 × 证据代码指纹），保留 2 条。' "$FP_REPORT"
grep -q '缺少空集合边界用例' "$FP_REPORT"
if grep -q '集合判空逻辑待复核' "$FP_REPORT"; then
  echo "FAIL: 待确认块也必须按指纹参与合并" >&2
  exit 1
fi
grep -q '句柄未显式关闭' "$FP_REPORT"

# 用例 7（零发现省略）：全程零正式发现的完整合并 → summary 必须完全没有 dedup 键，
# 报告不得出现跨批次去重行；JSON 仍然合法（字节兼容旧单批小输出）。
setup_fp_run "fp-zero-findings" 1
cat > "$FP_RUN/results/batch-001.md" <<'MD'
## 发现列表

本批次未发现正式问题。
MD
merge_fp_run
grep -q '"finding_count": 0' "$FP_SUMM"
if grep -q '"dedup"' "$FP_SUMM"; then
  echo "FAIL: N=0 时 summary 不得包含 dedup 对象" >&2
  exit 1
fi
if grep -q '跨批次去重' "$FP_REPORT"; then
  echo "FAIL: N=0 时报告不得包含跨批次去重行" >&2
  exit 1
fi
# 全绿运行（无任何 failed 批次）：failed_by_class 对象必须整体省略（字节兼容 pin）。
if grep -q '"failed_by_class"' "$FP_SUMM"; then
  echo "FAIL: 无 failed 批次时 summary 不得包含 failed_by_class 对象" >&2
  exit 1
fi

# 用例 8（分隔行相邻回归）：`### batch-XXX - 模块` 分隔行紧贴闭合围栏（上游文件以
# 围栏收尾无换行）、且另一个结果文件首行就是伪造的 `### batch-999 - ...` 并与真实
# 表头零空行相邻时，解析不得混淆 —— 分隔行原样透传，三个互相不同的发现各自保留。
setup_fp_run "fp-separator-adjacent"
{
  printf '## 发现列表\n\n'
  printf '### P1 [维度6-并发控制] 未加锁自增共享计数\n'
  printf -- '- 文件：src/a.js:20\n'
  printf -- '- 证据：\n'
  printf '  ```js\n'
  printf '  counter += 1;\n'
  printf '  ```'
} > "$FP_RUN/results/batch-001.md"
{
  printf '### batch-999 - 合成检查行\n'
  printf '### P0 [维度13-资源管理] 连接未显式关闭\n'
  printf -- '- 文件：src/b.js:31\n'
  printf -- '- 证据：\n'
  printf '  ```js\n'
  printf '  connection.close();\n'
  printf '  ```\n'
  printf '### P1 [维度6-并发控制] 双写竞态窗口待收敛\n'
  printf -- '- 文件：src/c.js:44\n'
  printf -- '- 证据：\n'
  printf '  ```js\n'
  printf '  counter += 2;\n'
  printf '  ```\n'
} > "$FP_RUN/results/batch-002.md"
merge_fp_run
grep -q '"finding_count": 3' "$FP_SUMM"
grep -qF '"dedup": {"input_findings": 3, "merged_duplicates": 0, "output_findings": 3}' "$FP_SUMM"
grep -q '^### batch-002 - src$' "$FP_REPORT"
test "$(grep -c '^### batch-999 - 合成检查行$' "$FP_REPORT")" = "1"
test "$(grep -c '^### P0 \[维度13-资源管理\] 连接未显式关闭$' "$FP_REPORT")" = "1"
test "$(grep -c '^### P1 \[维度6-并发控制\] 未加锁自增共享计数$' "$FP_REPORT")" = "1"
test "$(grep -c '^### P1 \[维度6-并发控制\] 双写竞态窗口待收敛$' "$FP_REPORT")" = "1"

# ---- 批次失败归因（failure_class）：封闭枚举 context_exhausted / tool_budget_exhausted /
# output_truncated / cancelled / unknown。解析顺序：状态文件显式声明（含 unknown）→
# error 文本关键词回退（上下文/context；工具/轮次/tool；中断/截断/truncat；
# 取消/cancel/interrupt(ctrl)；其余一律 unknown；大小写不敏感、顺序首个命中）→ unknown。
# failed 与 partial 同一解析顺序（partial 不再用字面量 "partial" 兜底）；错误列统一加
# 「[中文短标签] 」前缀。summary 的 failed_by_class 只统计 FAILED 批次：有失败时五键
# 齐全（含 0），无任何 failed 批次时整个对象省略。 ----
FCRUN="$TMP_DIR/failure-class-run"; mkdir -p "$FCRUN/batches" "$FCRUN/results"
cat > "$FCRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"fc1","project_name":"demo fc","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cat > "$FCRUN/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/a"],"modules":[{"name":"a1"}]}
JSON
cat > "$FCRUN/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_source_loc":250,"planned_source_file_count":1,
 "scan_roots":["src/b"],"modules":[{"name":"b2"}]}
JSON
# 冻结审查输入：覆盖台账（run-manifest）按 selected 路径 × scan_roots 回填逐文件状态。
cat > "$FCRUN/review-input.json" <<'JSON'
{"schema_version":1,"selection_mode":"workspace","items":[
 {"path":"src/a/x.tsx","change":"M","old_path":"","selected":true,"exclude_reason":"","insertions":1,"deletions":0,"fingerprint":""},
 {"path":"src/b/y.tsx","change":"M","old_path":"","selected":true,"exclude_reason":"","insertions":2,"deletions":0,"fingerprint":""}]}
JSON
cat > "$FCRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$FCRUN/results/batch-001.md","finding_count":0}
JSON
cat > "$FCRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
（无正式发现）
MD
run_fc_merge() {
  FCMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
           bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$FCRUN" 2>&1 || true)"
}
# expected_failed_by_class <ctx> <tool> <trunc> <cancel> <unknown> <summary路径>
expected_failed_by_class() {
  jq -e ".failed_by_class == {\"context_exhausted\": $1, \"tool_budget_exhausted\": $2, \"output_truncated\": $3, \"cancelled\": $4, \"unknown\": $5}" "$6" >/dev/null
}

# 用例 a：显式 canonical 枚举（context_exhausted）端到端生效并压过关键词回退
# （error 含「中断」本会落到 output_truncated）；manifest + 表格前缀 + 计数对象同步。
cat > "$FCRUN/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed",
 "failure_class":"context_exhausted","error":"上次执行中断，需要整批重跑"}
JSON
run_fc_merge
jq -e '.coverage_sets.failed[0].failure_class == "context_exhausted"' "$FCRUN/run-manifest.json" >/dev/null
jq -e '.coverage_sets.failed[0].reason == "上次执行中断，需要整批重跑"' "$FCRUN/run-manifest.json" >/dev/null
jq -e '.coverage[] | select(.batch_id == "batch-002" and .status == "failed" and .failure_class == "context_exhausted")' "$FCRUN/run-manifest.json" >/dev/null
expected_failed_by_class 1 0 0 0 0 "$FCRUN/summary.json"
FCREPORT="$(printf '%s\n' "$FCMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '| batch-002 | 失败 | 是 | 失败遗留 | 1 | 250 | b2 | [上下文耗尽] 上次执行中断，需要整批重跑 |' "$FCREPORT"
if grep -q '\[工具预算耗尽\]\|\[输出中断\]\|\[已取消\]\|\[未知\]' "$FCREPORT"; then
  echo "FAIL: 错误列前缀只允许出现解析命中的那一个中文短标签" >&2
  exit 1
fi

# 用例 b：发明枚举外值（server_overload）→ 视为未填写，走关键词回退；
# 「timed out」不属于任何回退词族 → unknown，错误列加 [未知] 前缀。
cat > "$FCRUN/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed",
 "failure_class":"server_overload","error":"review timed out before writing result"}
JSON
run_fc_merge
jq -e '.coverage_sets.failed[0].failure_class == "unknown"' "$FCRUN/run-manifest.json" >/dev/null
expected_failed_by_class 0 0 0 0 1 "$FCRUN/summary.json"
FCREPORT="$(printf '%s\n' "$FCMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '| batch-002 | 失败 | 是 | 失败遗留 | 1 | 250 | b2 | [未知] review timed out before writing result |' "$FCREPORT"

# 用例 c：missing field 的 legacy status json 走关键词回退（无命中 → unknown）。
cat > "$FCRUN/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed","error":"subagent failed"}
JSON
run_fc_merge
jq -e '.coverage_sets.failed[0].failure_class == "unknown"' "$FCRUN/run-manifest.json" >/dev/null
FCREPORT="$(printf '%s\n' "$FCMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -qF '| batch-002 | 失败 | 是 | 失败遗留 | 1 | 250 | b2 | [未知] subagent failed |' "$FCREPORT"

# 用例 d：关键词回退矩阵 —— 每个封闭枚举值的中英文代表词各一条 + 大小写混排 +
# 空错误文本兜底 unknown；全部为 failed 且未显式声明 failure_class。
# 参数：状态JSON尾段 预期枚举 fbc五键计数（ctx tool trunc cancel unknown）。
fc_matrix() {
  printf '{"batch_id":"batch-002","status":"failed"%s}\n' "$1" > "$FCRUN/results/batch-002.status.json"
  run_fc_merge
  jq -e ".coverage_sets.failed[0].failure_class == \"$2\"" "$FCRUN/run-manifest.json" >/dev/null
  expected_failed_by_class "$3" "$4" "$5" "$6" "$7" "$FCRUN/summary.json"
}
fc_matrix ',"error":"上下文窗口不足以完成整批"'     context_exhausted     1 0 0 0 0
fc_matrix ',"error":"Context window overflow"'      context_exhausted     1 0 0 0 0
fc_matrix ',"error":"工具调用轮次预算耗尽"'         tool_budget_exhausted 0 1 0 0 0
fc_matrix ',"error":"TOOL rounds exhausted"'        tool_budget_exhausted 0 1 0 0 0
fc_matrix ',"error":"输出被中断"'                   output_truncated      0 0 1 0 0
fc_matrix ',"error":"response TRUNCATED mid-write"' output_truncated      0 0 1 0 0
fc_matrix ',"error":"用户取消执行"'                 cancelled             0 0 0 1 0
fc_matrix ',"error":"user pressed Ctrl-C"'          cancelled             0 0 0 1 0
fc_matrix ''                                        unknown               0 0 0 0 1

# 用例 e：partial 显式归因（tool_budget_exhausted）→ manifest 记录枚举值；错误列加
# [工具预算耗尽] 前缀；本轮无任何 failed 批次 → failed_by_class 必须整体省略
# （partial 不计入该计数对象）。
PFCRUN="$TMP_DIR/partial-fc-run"; mkdir -p "$PFCRUN/batches" "$PFCRUN/results"
cat > "$PFCRUN/plan.json" <<'JSON'
{"schema_version":1,"run_id":"fc2","project_name":"demo fc partial","review_mode":"standard",
 "review_scope":"全量代码","language_id":"frontend",
 "total_source_loc":500,"total_source_file_count":2,"batch_count":2}
JSON
cp "$FCRUN/batches/batch-001.json" "$PFCRUN/batches/batch-001.json"
cp "$FCRUN/batches/batch-002.json" "$PFCRUN/batches/batch-002.json"
cp "$FCRUN/review-input.json" "$PFCRUN/review-input.json"
cat > "$PFCRUN/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":250,
 "planned_source_file_count":1,"result_path":"$PFCRUN/results/batch-001.md","finding_count":0}
JSON
cat > "$PFCRUN/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
（无正式发现）
MD
write_partial_status() {
  printf '{"batch_id":"batch-002","status":"partial","finding_count":1%s,"result_path":"%s"}\n' \
    "$1" "$PFCRUN/results/batch-002.md" > "$PFCRUN/results/batch-002.status.json"
}
cat > "$PFCRUN/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
### P1 | [维度4-状态与数据请求] partial 归因示例
- 文件：src/b/x.tsx:10
- 证据：示例
- 建议：示例

## 覆盖情况
- 中断前已覆盖 src/b/x.tsx
MD
run_pfc_merge() {
  PFMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
            bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$PFCRUN" 2>&1 || true)"
  PSUMM="$(printf '%s\n' "$PFMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
  PFREPORT="$(printf '%s\n' "$PFMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
}
write_partial_status ',"failure_class":"tool_budget_exhausted","error":"工具调用轮次预算耗尽"'
run_pfc_merge
grep -q '"merge_blocked": false' "$PSUMM"
jq -e '.coverage_sets.selected[] | select(.batch_id == "batch-002" and .failure_class == "tool_budget_exhausted")' "$PFCRUN/run-manifest.json" >/dev/null
jq -e '.coverage[] | select(.batch_id == "batch-002" and .status == "partial" and .failure_class == "tool_budget_exhausted")' "$PFCRUN/run-manifest.json" >/dev/null
grep -qF '| batch-002 | 部分完成待重跑 | 是 | 部分完成已纳入 | 1 | 250 | b2 | [工具预算耗尽] 工具调用轮次预算耗尽 |' "$PFREPORT"
if grep -q '"failed_by_class"' "$PSUMM"; then
  echo "FAIL: 只有 partial 无 failed 时 summary 不得包含 failed_by_class 对象" >&2
  exit 1
fi

# 用例 f：partial 未显式声明归因 → 与 failed 相同的关键词回退（不再回落字面量
# "partial"）；「输出被中断」→ output_truncated。
write_partial_status ',"error":"输出被中断"'
run_pfc_merge
grep -q '"partial_batches": 1' "$PSUMM"
jq -e '.coverage[] | select(.batch_id == "batch-002" and .status == "partial" and .failure_class == "output_truncated")' "$PFCRUN/run-manifest.json" >/dev/null
grep -qF '| batch-002 | 部分完成待重跑 | 是 | 部分完成已纳入 | 1 | 250 | b2 | [输出中断] 输出被中断 |' "$PFREPORT"

echo "PASS: core merge-batch-results"
