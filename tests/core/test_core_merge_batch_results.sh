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
grep -qF '| batch-001 | 部分完成待重跑 | 是 | 部分完成已纳入 | 1 | 250 | a | 中断 |' "$PREPORT"
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

echo "PASS: core merge-batch-results"
