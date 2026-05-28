#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
SEMANTIC_LEVEL="${4:-maven-static}"

TARGET_BATCH_LOC=25000
SOFT_MIN_BATCH_LOC=15000
SOFT_MAX_BATCH_LOC=30000
HARD_MAX_BATCH_LOC=35000

json_escape() {
  printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'
}

branch_slug() {
  local slug
  slug="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
  if [ -z "$slug" ]; then
    slug="no-branch"
  fi
  printf '%s' "$slug"
}

module_loc() {
  local dir="$1"
  find "$dir" -name '*.java' -not -path '*/target/*' -print0 2>/dev/null |
    xargs -0 wc -l 2>/dev/null |
    awk 'END {print $1 + 0}'
}

module_files() {
  local dir="$1"
  find "$dir" -name '*.java' -not -path '*/target/*' 2>/dev/null | wc -l | tr -d ' '
}

extract_modules() {
  perl -0ne 'while (/<module>\s*([^<]+?)\s*<\/module>/g) { print "$1\n" }' "$PROJECT_DIR/pom.xml"
}

artifact_id_for_pom() {
  perl -0ne '
    s/<parent>.*?<\/parent>//sg;
    if (/<artifactId>\s*([^<]+?)\s*<\/artifactId>/) { print $1; exit }
  ' "$1"
}

dependencies_for_pom() {
  perl -0ne '
    while (/<dependency>.*?<artifactId>\s*([^<]+?)\s*<\/artifactId>.*?<\/dependency>/sg) {
      print "$1\n";
    }
  ' "$1"
}

module_field() {
  local module="$1"
  local field="$2"
  awk -F '\t' -v module="$module" -v field="$field" '
    $1 == module {
      if (field == "path") print $2;
      else if (field == "artifact") print $3;
      else if (field == "loc") print $4;
      else if (field == "files") print $5;
      else if (field == "risk") print $6;
      exit
    }
  ' "$MODULES_TSV"
}

is_assigned() {
  case "$ASSIGNED_MODULES" in
    *"|$1|"*) return 0 ;;
    *) return 1 ;;
  esac
}

mark_assigned() {
  ASSIGNED_MODULES="$ASSIGNED_MODULES$1|"
}

batch_contains() {
  local candidate="$1"
  local module
  for module in "${CURRENT_BATCH[@]}"; do
    if [ "$module" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

add_to_batch() {
  local module="$1"
  local loc files
  loc="$(module_field "$module" loc)"
  files="$(module_field "$module" files)"
  CURRENT_BATCH+=("$module")
  CURRENT_LOC=$((CURRENT_LOC + loc))
  CURRENT_FILES=$((CURRENT_FILES + files))
  mark_assigned "$module"
}

next_unassigned_by_risk() {
  awk -F '\t' '{print $6 "\t" NR "\t" $1}' "$MODULES_TSV" | sort -rn -k1,1 -k2,2n |
    while IFS="$(printf '\t')" read -r _risk _line module; do
      if ! is_assigned "$module"; then
        printf '%s\n' "$module"
        break
      fi
    done
}

write_status() {
  local status_path="$1"
  local batch_id="$2"
  local planned_loc="$3"
  local planned_files="$4"
  cat > "$status_path.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$batch_id",
  "status": "pending",
  "planned_java_loc": $planned_loc,
  "planned_java_file_count": $planned_files,
  "attempt": 0,
  "started_at": null,
  "finished_at": null,
  "result_path": "results/$batch_id.md",
  "finding_count": 0,
  "error": null
}
JSON
  mv "$status_path.tmp" "$status_path"
}

write_json_string_array() {
  local indent="$1"
  shift
  local first=1
  local item
  printf '['
  for item in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '\n%s"%s"' "$indent" "$(json_escape "$item")"
    first=0
  done
  if [ "$first" -eq 0 ]; then
    printf '\n  '
  fi
  printf ']'
}

write_batch() {
  local batch_id="$1"
  local batch_path="$2"
  local status_rel="results/$batch_id.status.json"
  local result_rel="results/$batch_id.md"
  local large_batch="$3"
  local split_reason="$4"
  local scan_roots=()
  local module_entries=()
  local semantic_entries=()
  local edge_entries=("")
  local module path artifact loc files dep

  for module in "${CURRENT_BATCH[@]}"; do
    path="$(module_field "$module" path)"
    artifact="$(module_field "$module" artifact)"
    loc="$(module_field "$module" loc)"
    files="$(module_field "$module" files)"
    scan_roots+=("$path")
    module_entries+=("{\"name\":\"$(json_escape "$module")\",\"path\":\"$(json_escape "$path")\",\"artifact_id\":\"$(json_escape "$artifact")\",\"java_loc\":$loc,\"java_file_count\":$files}")
    semantic_entries+=("\"$(json_escape "$module")\":{\"artifact_id\":\"$(json_escape "$artifact")\",\"module_path\":\"$(json_escape "$path")\"}")
  done

  for module in "${CURRENT_BATCH[@]}"; do
    while IFS="$(printf '\t')" read -r _from_artifact dep dep_module; do
      [ -n "$dep_module" ] || continue
      if batch_contains "$dep_module"; then
        edge_entries+=("{\"from\": \"$(json_escape "$module")\", \"to\": \"$(json_escape "$dep_module")\"}")
      fi
    done < <(awk -F '\t' -v module="$module" '$1 == module {print $2 "\t" $3 "\t" $4}' "$EDGES_TSV")
  done

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "batch_id": "%s",\n' "$batch_id"
    printf '  "strategy": "maven-module-batching",\n'
    printf '  "semantic_level": "%s",\n' "$(json_escape "$SEMANTIC_LEVEL")"
    printf '  "planned_java_loc": %s,\n' "$CURRENT_LOC"
    printf '  "planned_java_file_count": %s,\n' "$CURRENT_FILES"
    printf '  "scan_roots": '
    write_json_string_array '    ' "${scan_roots[@]}"
    printf ',\n'
    printf '  "modules": ['
    local first=1 entry
    for entry in "${module_entries[@]}"; do
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    %s' "$entry"
      first=0
    done
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '],\n'
    printf '  "module_dependency_edges": ['
    first=1
    for entry in "${edge_entries[@]}"; do
      [ -n "$entry" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    %s' "$entry"
      first=0
    done
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '],\n'
    printf '  "semantic_lookup": {'
    first=1
    for entry in "${semantic_entries[@]}"; do
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    %s' "$entry"
      first=0
    done
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '},\n'
    printf '  "large_batch": %s,\n' "$large_batch"
    printf '  "split_reason": "%s",\n' "$(json_escape "$split_reason")"
    printf '  "result_path": "%s",\n' "$result_rel"
    printf '  "status_path": "%s"\n' "$status_rel"
    printf '}\n'
  } > "$batch_path.tmp"
  mv "$batch_path.tmp" "$batch_path"
}

if [ ! -d "$PROJECT_DIR" ]; then
  echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2
  exit 1
fi
if [ ! -f "$PROJECT_DIR/pom.xml" ]; then
  echo "ROOT_POM_NOT_FOUND=$PROJECT_DIR/pom.xml" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
RUN_TIMESTAMP="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE-full-large-maven"
RUNS_ROOT="${CC_CODE_REVIEWER_RUNS_ROOT:-$PROJECT_DIR/.cc-code-reviewer/runs}"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
MODULES_TSV="$RUN_DIR/modules.tsv"
EDGES_TSV="$RUN_DIR/module-edges.tsv"

mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"
: > "$MODULES_TSV"
: > "$EDGES_TSV"

while IFS= read -r module; do
  [ -n "$module" ] || continue
  module_dir="$PROJECT_DIR/$module"
  pom_path="$module_dir/pom.xml"
  if [ ! -f "$pom_path" ]; then
    continue
  fi
  artifact="$(artifact_id_for_pom "$pom_path")"
  if [ -z "$artifact" ]; then
    artifact="$module"
  fi
  loc="$(module_loc "$module_dir")"
  files="$(module_files "$module_dir")"
  printf '%s\t%s\t%s\t%s\t%s\t0\n' "$module" "$module" "$artifact" "$loc" "$files" >> "$MODULES_TSV"
done < <(extract_modules)

while IFS="$(printf '\t')" read -r module _path artifact _loc _files _risk; do
  pom_path="$PROJECT_DIR/$module/pom.xml"
  while IFS= read -r dep_artifact; do
    [ -n "$dep_artifact" ] || continue
    dep_module="$(awk -F '\t' -v artifact="$dep_artifact" '$3 == artifact {print $1; exit}' "$MODULES_TSV")"
    if [ -n "$dep_module" ]; then
      printf '%s\t%s\t%s\t%s\n' "$module" "$artifact" "$dep_artifact" "$dep_module" >> "$EDGES_TSV"
    fi
  done < <(dependencies_for_pom "$pom_path")
done < "$MODULES_TSV"

RISK_TSV="$RUN_DIR/modules.risk.tsv"
while IFS="$(printf '\t')" read -r module path artifact loc files _risk; do
  outgoing="$(awk -F '\t' -v module="$module" '$1 == module {count++} END {print count + 0}' "$EDGES_TSV")"
  incoming="$(awk -F '\t' -v module="$module" '$4 == module {count++} END {print count + 0}' "$EDGES_TSV")"
  name_risk=0
  case "$module" in
    *api*|*gateway*|*controller*) name_risk=$((name_risk + 100)) ;;
  esac
  case "$module" in
    *service*) name_risk=$((name_risk + 60)) ;;
  esac
  case "$module" in
    *dao*|*repository*) name_risk=$((name_risk + 30)) ;;
  esac
  risk=$((name_risk + outgoing * 20 + incoming * 5 + loc / 1000))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$module" "$path" "$artifact" "$loc" "$files" "$risk" >> "$RISK_TSV"
done < "$MODULES_TSV"
mv "$RISK_TSV" "$MODULES_TSV"

TOTAL_JAVA_LOC="$(awk -F '\t' '{sum += $4} END {print sum + 0}' "$MODULES_TSV")"
TOTAL_JAVA_FILE_COUNT="$(awk -F '\t' '{sum += $5} END {print sum + 0}' "$MODULES_TSV")"

ASSIGNED_MODULES="|"
BATCH_COUNT=0
while [ "$(awk 'END {print NR + 0}' "$MODULES_TSV")" -gt "$(printf '%s' "$ASSIGNED_MODULES" | awk -F '|' '{print NF - 2}')" ]; do
  seed="$(next_unassigned_by_risk)"
  [ -n "$seed" ] || break

  CURRENT_BATCH=()
  CURRENT_LOC=0
  CURRENT_FILES=0
  add_to_batch "$seed"

  if [ "$CURRENT_LOC" -le "$HARD_MAX_BATCH_LOC" ]; then
    changed=1
    while [ "$changed" -eq 1 ]; do
      changed=0
      for module in "${CURRENT_BATCH[@]}"; do
        while IFS="$(printf '\t')" read -r dep_module dep_loc; do
          [ -n "$dep_module" ] || continue
          if ! is_assigned "$dep_module" && [ $((CURRENT_LOC + dep_loc)) -le "$SOFT_MAX_BATCH_LOC" ]; then
            add_to_batch "$dep_module"
            changed=1
          fi
        done < <(awk -F '\t' -v module="$module" 'FNR == NR {loc[$1] = $4; next} $1 == module {print $4 "\t" loc[$4]}' "$MODULES_TSV" "$EDGES_TSV")
      done
    done
  fi

  if [ "$CURRENT_LOC" -lt "$SOFT_MIN_BATCH_LOC" ]; then
    nearest="$(awk -F '\t' '{print $6 "\t" NR "\t" $1 "\t" $4}' "$MODULES_TSV" | sort -rn -k1,1 -k2,2n |
      while IFS="$(printf '\t')" read -r _risk _line module loc; do
        if ! is_assigned "$module" && [ $((CURRENT_LOC + loc)) -le "$SOFT_MAX_BATCH_LOC" ]; then
          printf '%s\n' "$module"
          break
        fi
      done)"
    if [ -n "$nearest" ]; then
      add_to_batch "$nearest"
    fi
  fi

  BATCH_COUNT=$((BATCH_COUNT + 1))
  batch_id="$(printf 'batch-%03d' "$BATCH_COUNT")"
  large_batch=false
  split_reason="maven_module_dependency_group"
  if [ "$CURRENT_LOC" -gt "$HARD_MAX_BATCH_LOC" ]; then
    large_batch=true
    split_reason="oversized_module_needs_package_split"
  fi
  write_batch "$batch_id" "$RUN_DIR/batches/$batch_id.json" "$large_batch" "$split_reason"
  write_status "$RUN_DIR/results/$batch_id.status.json" "$batch_id" "$CURRENT_LOC" "$CURRENT_FILES"
done

CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RUN_DIR/plan.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "project_name": "$(json_escape "$PROJECT_NAME")",
  "project_dir": "$(json_escape "$PROJECT_DIR")",
  "review_mode": "$(json_escape "$REVIEW_MODE")",
  "review_scope": "全量代码",
  "branch": "$(json_escape "$BRANCH_NAME")",
  "strategy": "maven-module-batching",
  "semantic_level": "$(json_escape "$SEMANTIC_LEVEL")",
  "total_java_loc": $TOTAL_JAVA_LOC,
  "total_java_file_count": $TOTAL_JAVA_FILE_COUNT,
  "batch_count": $BATCH_COUNT,
  "budget": {
    "target_batch_loc": $TARGET_BATCH_LOC,
    "soft_min_batch_loc": $SOFT_MIN_BATCH_LOC,
    "soft_max_batch_loc": $SOFT_MAX_BATCH_LOC,
    "hard_max_batch_loc": $HARD_MAX_BATCH_LOC
  },
  "created_at": "$CREATED_AT"
}
JSON
mv "$RUN_DIR/plan.json.tmp" "$RUN_DIR/plan.json"

printf '{"event":"run_created","run_id":"%s","batch_count":%s,"created_at":"%s"}\n' \
  "$(json_escape "$RUN_ID")" "$BATCH_COUNT" "$CREATED_AT" > "$RUN_DIR/progress.jsonl"

rm -f "$MODULES_TSV" "$EDGES_TSV"

echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_JAVA_LOC=$TOTAL_JAVA_LOC"
