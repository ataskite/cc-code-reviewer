#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
SEMANTIC_LEVEL="${4:-maven-static}"
REVIEW_SCOPE_INPUT="${5:-全量代码}"
PLANNING_STRATEGY="${6:-semantic-cost-batching}"

TARGET_BATCH_COST=52000
SOFT_MIN_BATCH_COST=32000
SOFT_MAX_BATCH_COST=60000
HARD_MAX_BATCH_COST=65000
TINY_BATCH_LOC=5000
TINY_BATCH_COST=8000
CONTEXT_COST_RATIO_PERCENT=25

HARD_MAX_BATCH_LOC=50000
TARGET_BATCH_LOC=50000
SOFT_MIN_BATCH_LOC=30000
SOFT_MAX_BATCH_LOC=50000

SELECTED_MODULES=()
SELECTED_MODULES_RAW=()

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

java_loc() {
  local dir="$1"
  local total=0
  local file lines
  while IFS= read -r -d '' file; do
    lines="$(wc -l < "$file" | tr -d ' ')"
    total=$((total + lines))
  done < <(find "$dir" -path '*/src/main/java/*' -name '*.java' -not -path '*/target/*' -print0 2>/dev/null)
  printf '%s\n' "$total"
}

java_files() {
  local dir="$1"
  find "$dir" -path '*/src/main/java/*' -name '*.java' -not -path '*/target/*' -print0 2>/dev/null | tr '\0' '\n' | wc -l | tr -d ' '
}

review_cost() {
  local loc="$1"
  local files="$2"
  printf '%s\n' $((loc + files * 25))
}

extract_modules_from_pom() {
  local pom_path="$1"
  perl -0ne '
    while (/<module>\s*([^<]+?)\s*<\/module>/g) {
      my $module = $1;
      $module =~ s/&amp;/&/g;
      $module =~ s/&lt;/</g;
      $module =~ s/&gt;/>/g;
      $module =~ s/&quot;/"/g;
      $module =~ s/&apos;/'\''/g;
      print "$module\n";
    }
  ' "$pom_path"
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

path_join() {
  local parent="$1"
  local child="$2"
  if [ -z "$parent" ]; then
    printf '%s\n' "$child"
  else
    printf '%s/%s\n' "$parent" "$child"
  fi
}

basename_path() {
  local path="$1"
  printf '%s\n' "${path##*/}"
}

is_support_context() {
  local name="$1"
  local loc="$2"
  local path="${3:-$1}"
  local lower
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  if [ "$loc" -eq 0 ]; then
    return 0
  fi
  if [ "$loc" -lt "$TINY_BATCH_LOC" ]; then
    case "$lower" in
      *dependencies*|*dependency*|*bom*) return 0 ;;
    esac
    case "$lower" in
      *server*) case "$path" in */*) ;; *) return 0 ;; esac ;;
    esac
  fi
  return 1
}

append_unit() {
  local unit_id="$1"
  local display_name="$2"
  local path="$3"
  local kind="$4"
  local artifact="$5"
  local loc="$6"
  local files="$7"
  local cost="$8"
  local split_reason="$9"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$unit_id" "$display_name" "$path" "$kind" "$artifact" "$loc" "$files" "$cost" "$split_reason" >> "$UNITS_TSV"
}

append_context() {
  local unit_id="$1"
  local display_name="$2"
  local path="$3"
  local kind="$4"
  local artifact="$5"
  local loc="$6"
  local files="$7"
  local cost="$8"
  local split_reason="$9"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$unit_id" "$display_name" "$path" "$kind" "$artifact" "$loc" "$files" "$cost" "$split_reason" >> "$CONTEXT_TSV"
}

append_legacy_unit() {
  local name="$1"
  local path="$2"
  local kind="$3"
  local artifact="$4"
  local loc="$5"
  local files="$6"
  local cost="$7"
  local split_reason="$8"
  local unit_id="$kind:$path"
  append_unit "$unit_id" "$name" "$path" "$kind" "$artifact" "$loc" "$files" "$cost" "$split_reason"
}

top_segment() {
  local path="$1"
  printf '%s\n' "${path%%/*}"
}

scope_is_full() {
  case "$REVIEW_SCOPE_INPUT" in
    ""|"全量代码"|"全量审查"|"all"|"ALL") return 0 ;;
    *) return 1 ;;
  esac
}

normalize_strategy() {
  case "$PLANNING_STRATEGY" in
    module-sequential|module-sequential-batching|按模块依次审查)
      printf 'module-sequential-batching\n'
      ;;
    ai-planned|semantic-cost-batching|AI智能规划分批|"AI 智能规划分批"|"")
      printf 'semantic-cost-batching\n'
      ;;
    *)
      echo "UNKNOWN_PLANNING_STRATEGY=$PLANNING_STRATEGY" >&2
      exit 1
      ;;
  esac
}

module_already_selected() {
  local candidate="$1"
  local selected
  if [ "${#SELECTED_MODULES[@]}" -eq 0 ]; then
    return 1
  fi
  for selected in "${SELECTED_MODULES[@]}"; do
    if [ "$selected" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

add_selected_module() {
  local module="$1"
  [ -n "$module" ] || return 0
  if module_already_selected "$module"; then
    return 0
  fi
  SELECTED_MODULES+=("$module")
}

parse_selected_modules() {
  local normalized module
  SELECTED_MODULES=()
  if scope_is_full; then
    while IFS= read -r module; do
      [ -n "$module" ] || continue
      add_selected_module "$module"
    done < <(extract_modules_from_pom "$PROJECT_DIR/pom.xml")
    return
  fi

  normalized="$(printf '%s' "$REVIEW_SCOPE_INPUT" | perl -CS -Mutf8 -pe 's/[，、\s]+/,/g; s/^,+//; s/,+$//')"
  IFS=',' read -r -a SELECTED_MODULES_RAW <<< "$normalized"
  for module in "${SELECTED_MODULES_RAW[@]}"; do
    module="$(printf '%s' "$module" | sed 's#^\./##; s#//*#/#g; s#/$##')"
    [ -n "$module" ] || continue
    add_selected_module "$module"
  done
}

validate_selected_modules() {
  local module module_abs
  if [ "${#SELECTED_MODULES[@]}" -eq 0 ]; then
    echo "NO_SELECTED_MODULES=$REVIEW_SCOPE_INPUT" >&2
    exit 1
  fi
  for module in "${SELECTED_MODULES[@]}"; do
    case "$module" in
      /*|..|../*|*/..|*/../*|.)
        echo "SELECTED_MODULE_OUTSIDE_PROJECT=$module" >&2
        exit 1
        ;;
    esac
    if [ -e "$PROJECT_DIR/$module" ]; then
      module_abs="$(cd "$PROJECT_DIR/$module" 2>/dev/null && pwd || true)"
      case "$module_abs" in
        "$PROJECT_DIR"/*) ;;
        *)
          echo "SELECTED_MODULE_OUTSIDE_PROJECT=$module" >&2
          exit 1
          ;;
      esac
    fi
  done
  if scope_is_full; then
    return
  fi
  for module in "${SELECTED_MODULES[@]}"; do
    if [ ! -f "$PROJECT_DIR/$module/pom.xml" ]; then
      echo "SELECTED_MODULE_NOT_FOUND=$module" >&2
      exit 1
    fi
  done
}

is_selected_module() {
  local candidate="$1"
  module_already_selected "$candidate"
}

child_module_count() {
  local dir="$1"
  if [ ! -f "$dir/pom.xml" ]; then
    printf '0\n'
    return
  fi
  extract_modules_from_pom "$dir/pom.xml" | awk 'NF {count++} END {print count + 0}'
}

java_child_dirs() {
  local dir="$1"
  find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null |
    while IFS= read -r -d '' child; do
      if [ "$(java_loc "$child")" -gt 0 ]; then
        printf '%s\n' "$(basename "$child")"
      fi
    done | sort
}

split_package_dir() {
  local module_rel="$1"
  local top_name="$2"
  local artifact="$3"
  local package_rel="$4"
  local src_root="$PROJECT_DIR/$module_rel/src/main/java"
  local abs_dir="$src_root"
  local unit_path="$module_rel/src/main/java"
  if [ -n "$package_rel" ]; then
    abs_dir="$src_root/$package_rel"
    unit_path="$module_rel/src/main/java/$package_rel"
  fi

  local loc files cost children
  loc="$(java_loc "$abs_dir")"
  [ "$loc" -gt 0 ] || return
  files="$(java_files "$abs_dir")"
  cost="$(review_cost "$loc" "$files")"
  children="$(java_child_dirs "$abs_dir")"

  if [ "$loc" -le "$HARD_MAX_BATCH_LOC" ] && [ "$cost" -le "$HARD_MAX_BATCH_COST" ]; then
    local display_name="$top_name"
    if [ -n "$package_rel" ]; then
      display_name="$top_name:$package_rel"
    fi
    append_unit "java-package:$unit_path" "$display_name" "$unit_path" "java-package" "$artifact" "$loc" "$files" "$cost" "oversized_module_package_split"
    return
  fi

  if [ -n "$children" ]; then
    while IFS= read -r child; do
      [ -n "$child" ] || continue
      if [ -n "$package_rel" ]; then
        split_package_dir "$module_rel" "$top_name" "$artifact" "$package_rel/$child"
      else
        split_package_dir "$module_rel" "$top_name" "$artifact" "$child"
      fi
    done <<< "$children"
    return
  fi

  append_unit "java-package:$unit_path" "$top_name:$package_rel" "$unit_path" "java-package" "$artifact" "$loc" "$files" "$cost" "oversized_package_no_smaller_directory"
}

split_package_units() {
  local module_rel="$1"
  local top_name="$2"
  local artifact="$3"
  local src_root="$PROJECT_DIR/$module_rel/src/main/java"
  if [ -d "$src_root" ]; then
    split_package_dir "$module_rel" "$top_name" "$artifact" ""
  else
    local loc files cost
    loc="$(java_loc "$PROJECT_DIR/$module_rel")"
    files="$(java_files "$PROJECT_DIR/$module_rel")"
    cost="$(review_cost "$loc" "$files")"
    append_unit "maven-module:$module_rel" "$top_name" "$module_rel" "maven-module" "$artifact" "$loc" "$files" "$cost" "oversized_module_without_java_package_root"
  fi
}

generate_work_units() {
  local module_rel="$1"
  local top_name="$2"
  local force_scan="${3:-false}"
  local module_dir="$PROJECT_DIR/$module_rel"
  local pom_path="$module_dir/pom.xml"
  [ -f "$pom_path" ] || return

  local artifact name loc files cost child_count
  artifact="$(artifact_id_for_pom "$pom_path")"
  if [ -z "$artifact" ]; then
    artifact="$(basename_path "$module_rel")"
  fi
  name="$(basename_path "$module_rel")"
  loc="$(java_loc "$module_dir")"
  files="$(java_files "$module_dir")"
  cost="$(review_cost "$loc" "$files")"
  child_count="$(child_module_count "$module_dir")"

  if [ "$force_scan" != "true" ] && is_support_context "$name" "$loc" "$module_rel"; then
    append_context "context-module:$module_rel" "$name" "$module_rel" "context-module" "$artifact" "$loc" "$files" "$cost" "tiny_or_zero_support_context"
    return
  fi

  if [ "$loc" -gt "$HARD_MAX_BATCH_LOC" ] || [ "$cost" -gt "$HARD_MAX_BATCH_COST" ]; then
    if [ "$child_count" -gt 0 ]; then
      while IFS= read -r child; do
        [ -n "$child" ] || continue
        generate_work_units "$(path_join "$module_rel" "$child")" "$top_name" "false"
      done < <(extract_modules_from_pom "$pom_path")
      return
    fi
    split_package_units "$module_rel" "$top_name" "$artifact"
    return
  fi

  append_unit "maven-module:$module_rel" "$name" "$module_rel" "maven-module" "$artifact" "$loc" "$files" "$cost" "maven_module"
}

generate_module_sequential_unit() {
  local module_rel="$1"
  local module_dir="$PROJECT_DIR/$module_rel"
  local pom_path="$module_dir/pom.xml"
  [ -f "$pom_path" ] || return

  local artifact name loc files cost
  artifact="$(artifact_id_for_pom "$pom_path")"
  if [ -z "$artifact" ]; then
    artifact="$(basename_path "$module_rel")"
  fi
  name="$module_rel"
  loc="$(java_loc "$module_dir")"
  files="$(java_files "$module_dir")"
  cost="$(review_cost "$loc" "$files")"

  if [ "$loc" -eq 0 ]; then
    append_context "context-module:$module_rel" "$name" "$module_rel" "context-module" "$artifact" "$loc" "$files" "$cost" "zero_loc_selected_module_context"
    return
  fi

  append_unit "maven-module:$module_rel" "$name" "$module_rel" "maven-module" "$artifact" "$loc" "$files" "$cost" "module_sequential_user_selected"
}

collect_support_context_candidate() {
  local module_rel="$1"
  local module_dir="$PROJECT_DIR/$module_rel"
  local pom_path="$module_dir/pom.xml"
  [ -f "$pom_path" ] || return
  is_selected_module "$module_rel" && return

  local artifact name loc files cost
  artifact="$(artifact_id_for_pom "$pom_path")"
  if [ -z "$artifact" ]; then
    artifact="$(basename_path "$module_rel")"
  fi
  name="$(basename_path "$module_rel")"
  loc="$(java_loc "$module_dir")"
  files="$(java_files "$module_dir")"
  cost="$(review_cost "$loc" "$files")"
  if is_support_context "$name" "$loc" "$module_rel"; then
    append_context "context-module:$module_rel" "$name" "$module_rel" "context-module" "$artifact" "$loc" "$files" "$cost" "tiny_or_zero_support_context"
  fi
}

unit_field() {
  local unit="$1"
  local field="$2"
  awk -F '\t' -v unit="$unit" -v field="$field" '
    $1 == unit {
      if (field == "name") print $2;
      else if (field == "path") print $3;
      else if (field == "kind") print $4;
      else if (field == "artifact") print $5;
      else if (field == "loc") print $6;
      else if (field == "files") print $7;
      else if (field == "cost") print $8;
      else if (field == "split_reason") print $9;
      exit
    }
  ' "$UNITS_TSV"
}

is_assigned() {
  case "$ASSIGNED_UNITS" in
    *"|$1|"*) return 0 ;;
    *) return 1 ;;
  esac
}

mark_assigned() {
  ASSIGNED_UNITS="$ASSIGNED_UNITS$1|"
}

batch_has_unit() {
  local batch_file="$1"
  local unit="$2"
  awk -F '\t' -v unit="$unit" '$1 == unit {found=1} END {exit found ? 0 : 1}' "$batch_file"
}

batch_sum_field() {
  local batch_file="$1"
  local field="$2"
  awk -F '\t' -v field="$field" '
    {
      if (field == "loc") sum += $6;
      else if (field == "files") sum += $7;
      else if (field == "cost") sum += $8;
    }
    END {print sum + 0}
  ' "$batch_file"
}

add_unit_to_draft() {
  local unit="$1"
  local draft_file="$2"
  awk -F '\t' -v unit="$unit" '$1 == unit {print; exit}' "$UNITS_TSV" >> "$draft_file"
  mark_assigned "$unit"
}

next_unassigned_unit() {
  while IFS="$(printf '\t')" read -r _cost _line unit; do
    [ -n "$unit" ] || continue
    if ! is_assigned "$unit"; then
      printf '%s\n' "$unit"
      return
    fi
  done < "$SORTED_UNITS_TSV"
}

try_fill_draft() {
  local draft_file="$1"
  local max_cost="$2"
  local changed=1
  local current_loc current_cost unit loc cost
  while [ "$changed" -eq 1 ]; do
    changed=0
    current_loc="$(batch_sum_field "$draft_file" loc)"
    current_cost="$(batch_sum_field "$draft_file" cost)"
    while IFS="$(printf '\t')" read -r _sort_cost _line unit; do
      [ -n "$unit" ] || continue
      if is_assigned "$unit"; then
        continue
      fi
      loc="$(unit_field "$unit" loc)"
      cost="$(unit_field "$unit" cost)"
      if [ $((current_loc + loc)) -le "$HARD_MAX_BATCH_LOC" ] && [ $((current_cost + cost)) -le "$max_cost" ]; then
        add_unit_to_draft "$unit" "$draft_file"
        changed=1
        break
      fi
    done < "$SORTED_UNITS_TSV"
  done
}

rebalance_tiny_batches() {
  local draft tiny_loc tiny_cost other other_loc other_cost unit path kind artifact files
  for draft in "$DRAFT_DIR"/draft-*.tsv; do
    [ -s "$draft" ] || continue
    tiny_loc="$(batch_sum_field "$draft" loc)"
    tiny_cost="$(batch_sum_field "$draft" cost)"
    if [ "$tiny_loc" -ge "$TINY_BATCH_LOC" ] || [ "$tiny_cost" -ge "$TINY_BATCH_COST" ]; then
      continue
    fi

    for other in "$DRAFT_DIR"/draft-*.tsv; do
      [ "$other" != "$draft" ] || continue
      [ -s "$other" ] || continue
      other_loc="$(batch_sum_field "$other" loc)"
      other_cost="$(batch_sum_field "$other" cost)"
      if [ $((other_loc + tiny_loc)) -le "$HARD_MAX_BATCH_LOC" ] && [ $((other_cost + tiny_cost)) -le "$HARD_MAX_BATCH_COST" ]; then
        cat "$draft" >> "$other"
        : > "$draft"
        break
      fi
    done

    if [ -s "$draft" ]; then
      while IFS="$(printf '\t')" read -r unit name path kind artifact tiny_loc files tiny_cost _split_reason; do
        append_context "tiny-context:$path" "$name" "$path" "tiny-context-unit" "$artifact" "$tiny_loc" "$files" "$tiny_cost" "tiny_tail_context"
      done < "$draft"
      : > "$draft"
    fi
  done
}

write_json_string_array() {
  local item
  local first=1
  printf '['
  for item in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '\n    "%s"' "$(json_escape "$item")"
    first=0
  done
  if [ "$first" -eq 0 ]; then
    printf '\n  '
  fi
  printf ']'
}

context_affinity() {
  local context_name="$1"
  local context_path="$2"
  local batch_file="$3"
  local unit_id unit_name unit_path _rest
  local score=0
  while IFS="$(printf '\t')" read -r unit_id unit_name unit_path _rest; do
    case "$unit_name:$unit_path" in
      *"$context_name"*|*"$context_path"*) score=$((score + 60)) ;;
    esac
    case "$context_name" in
      *dependencies*|*dependency*|*bom*) score=$((score + 20)) ;;
    esac
    case "$context_name" in
      *server*) score=$((score + 15)) ;;
    esac
  done < "$batch_file"
  printf '%s\n' "$score"
}

context_roots_args() {
  local batch_file="$1"
  local batch_cost="$2"
  local context_limit=$((batch_cost * CONTEXT_COST_RATIO_PERCENT / 100))
  local selected_cost=0
  local candidates="$RUN_DIR/context-candidates.tmp"

  [ -s "$CONTEXT_TSV" ] || return 0
  : > "$candidates"
  while IFS="$(printf '\t')" read -r _unit_id name path kind artifact loc files cost split_reason; do
    [ -n "$path" ] || continue
    [ "$cost" -le "$context_limit" ] || continue
    affinity="$(context_affinity "$name" "$path" "$batch_file")"
    [ "$affinity" -gt 0 ] || continue
    printf '%s\t%s\t%s\n' "$affinity" "$cost" "$path" >> "$candidates"
  done < "$CONTEXT_TSV"

  sort -rn -k1,1 -k2,2n "$candidates" | while IFS="$(printf '\t')" read -r _affinity cost path; do
    if [ $((selected_cost + cost)) -le "$context_limit" ]; then
      printf '%s\n' "$path"
      selected_cost=$((selected_cost + cost))
    fi
  done
}

write_status() {
  local status_path="$1"
  local batch_id="$2"
  local planned_loc="$3"
  local planned_files="$4"
  local planned_cost="$5"
  cat > "$status_path.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$batch_id",
  "status": "pending",
  "planned_java_loc": $planned_loc,
  "planned_java_file_count": $planned_files,
  "planned_review_cost": $planned_cost,
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

write_batch() {
  local batch_id="$1"
  local batch_path="$2"
  local batch_file="$3"
  local planned_loc planned_files planned_cost status_rel result_rel
  planned_loc="$(batch_sum_field "$batch_file" loc)"
  planned_files="$(batch_sum_field "$batch_file" files)"
  planned_cost="$(batch_sum_field "$batch_file" cost)"
  status_rel="results/$batch_id.status.json"
  result_rel="results/$batch_id.md"

  local scan_roots=()
  local context_roots=()
  local unit_id name path kind artifact loc files cost split_reason entry first
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    context_roots+=("$path")
  done < <(context_roots_args "$batch_file" "$planned_cost")
  while IFS="$(printf '\t')" read -r unit_id name path kind artifact loc files cost split_reason; do
    scan_roots+=("$path")
  done < "$batch_file"

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "batch_id": "%s",\n' "$batch_id"
    printf '  "strategy": "%s",\n' "$(json_escape "$PLAN_STRATEGY")"
    printf '  "semantic_level": "%s",\n' "$(json_escape "$SEMANTIC_LEVEL")"
    printf '  "review_scope": "%s",\n' "$(json_escape "$REVIEW_SCOPE_INPUT")"
    printf '  "selected_modules": '
    write_json_string_array "${SELECTED_MODULES[@]}"
    printf ',\n'
    printf '  "planned_java_loc": %s,\n' "$planned_loc"
    printf '  "planned_java_file_count": %s,\n' "$planned_files"
    printf '  "planned_review_cost": %s,\n' "$planned_cost"
    printf '  "scan_roots": '
    write_json_string_array "${scan_roots[@]}"
    printf ',\n'
    printf '  "context_roots": '
    write_json_string_array ${context_roots[@]+"${context_roots[@]}"}
    printf ',\n'
    printf '  "units": ['
    first=1
    while IFS="$(printf '\t')" read -r unit_id name path kind artifact loc files cost split_reason; do
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    {"name":"%s","path":"%s","kind":"%s","java_loc":%s,"java_file_count":%s,"review_cost":%s}' \
        "$(json_escape "$name")" "$(json_escape "$path")" "$(json_escape "$kind")" "$loc" "$files" "$cost"
      first=0
    done < "$batch_file"
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '],\n'
    printf '  "modules": ['
    first=1
    while IFS="$(printf '\t')" read -r unit_id name path kind artifact loc files cost split_reason; do
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    {"name":"%s","path":"%s","artifact_id":"%s","java_loc":%s,"java_file_count":%s,"review_cost":%s}' \
        "$(json_escape "$name")" "$(json_escape "$path")" "$(json_escape "$artifact")" "$loc" "$files" "$cost"
      first=0
    done < "$batch_file"
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '],\n'
    printf '  "affinity_edges": [],\n'
    printf '  "module_dependency_edges": ['
    first=1
    while IFS="$(printf '\t')" read -r from to dep; do
      [ -n "$from" ] || continue
      if batch_has_unit "$batch_file" "$from" && batch_has_unit "$batch_file" "$to"; then
        if [ "$first" -eq 0 ]; then
          printf ','
        fi
        printf '\n    {"from": "%s", "to": "%s", "artifact_id": "%s"}' \
          "$(json_escape "$from")" "$(json_escape "$to")" "$(json_escape "$dep")"
        first=0
      fi
    done < "$EDGES_TSV"
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '],\n'
    printf '  "semantic_lookup": {'
    first=1
    while IFS="$(printf '\t')" read -r unit_id name path kind artifact loc files cost split_reason; do
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    "%s":{"artifact_id":"%s","module_path":"%s","kind":"%s","review_cost":%s}' \
        "$(json_escape "$name")" "$(json_escape "$artifact")" "$(json_escape "$path")" "$(json_escape "$kind")" "$cost"
      first=0
    done < "$batch_file"
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf '},\n'
    if [ "$planned_loc" -gt "$SOFT_MAX_BATCH_LOC" ] || [ "$planned_cost" -gt "$SOFT_MAX_BATCH_COST" ]; then
      printf '  "large_batch": true,\n'
    else
      printf '  "large_batch": false,\n'
    fi
    split_reason="$(awk -F '\t' 'NR == 1 {print $9}' "$batch_file")"
    printf '  "split_reason": "%s",\n' "$(json_escape "$split_reason")"
    printf '  "result_path": "%s",\n' "$result_rel"
    printf '  "status_path": "%s"\n' "$status_rel"
    printf '}\n'
  } > "$batch_path.tmp"
  mv "$batch_path.tmp" "$batch_path"

  write_status "$RUN_DIR/results/$batch_id.status.json" "$batch_id" "$planned_loc" "$planned_files" "$planned_cost"
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
PLAN_STRATEGY="$(normalize_strategy)"
parse_selected_modules
validate_selected_modules
RUN_TIMESTAMP="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"
RUNS_ROOT="${CC_CODE_REVIEWER_RUNS_ROOT:-$PROJECT_DIR/.cc-code-reviewer/runs}"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
UNITS_TSV="$RUN_DIR/work-units.tsv"
CONTEXT_TSV="$RUN_DIR/context-units.tsv"
SORTED_UNITS_TSV="$RUN_DIR/work-units.sorted.tsv"
EDGES_TSV="$RUN_DIR/module-edges.tsv"
DRAFT_DIR="$RUN_DIR/drafts"

mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results" "$DRAFT_DIR"
: > "$UNITS_TSV"
: > "$CONTEXT_TSV"
: > "$EDGES_TSV"

TOTAL_JAVA_LOC=0
TOTAL_JAVA_FILE_COUNT=0
if ! scope_is_full; then
  while IFS= read -r module; do
    [ -n "$module" ] || continue
    collect_support_context_candidate "$module"
  done < <(extract_modules_from_pom "$PROJECT_DIR/pom.xml")
fi

for module in "${SELECTED_MODULES[@]}"; do
  module_dir="$PROJECT_DIR/$module"
  pom_path="$module_dir/pom.xml"
  if [ ! -f "$pom_path" ]; then
    continue
  fi
  module_loc="$(java_loc "$module_dir")"
  module_files="$(java_files "$module_dir")"
  TOTAL_JAVA_LOC=$((TOTAL_JAVA_LOC + module_loc))
  TOTAL_JAVA_FILE_COUNT=$((TOTAL_JAVA_FILE_COUNT + module_files))
  if [ "$PLAN_STRATEGY" = "module-sequential-batching" ]; then
    generate_module_sequential_unit "$module"
  else
    force_scan="false"
    if ! scope_is_full; then
      force_scan="true"
    fi
    generate_work_units "$module" "$(top_segment "$module")" "$force_scan"
  fi
done

if [ ! -s "$UNITS_TSV" ] && [ ! -s "$CONTEXT_TSV" ]; then
  echo "NO_MAVEN_MODULES=$PROJECT_DIR" >&2
  rm -f "$UNITS_TSV" "$CONTEXT_TSV" "$EDGES_TSV" "$SORTED_UNITS_TSV"
  rm -rf "$DRAFT_DIR"
  exit 1
fi

if [ ! -s "$UNITS_TSV" ]; then
  echo "NO_MAVEN_MODULES=$PROJECT_DIR" >&2
  rm -f "$UNITS_TSV" "$CONTEXT_TSV" "$EDGES_TSV" "$SORTED_UNITS_TSV"
  rm -rf "$DRAFT_DIR"
  exit 1
fi

while IFS="$(printf '\t')" read -r unit name path kind artifact _loc _files _cost _split_reason; do
  if [ "$kind" != "maven-module" ] && [ "$kind" != "context-module" ]; then
    continue
  fi
  pom_path="$PROJECT_DIR/$path/pom.xml"
  [ -f "$pom_path" ] || continue
  while IFS= read -r dep_artifact; do
    [ -n "$dep_artifact" ] || continue
    dep_unit="$(awk -F '\t' -v artifact="$dep_artifact" '$5 == artifact {print $1; exit}' "$UNITS_TSV")"
    if [ -n "$dep_unit" ]; then
      printf '%s\t%s\t%s\n' "$unit" "$dep_unit" "$dep_artifact" >> "$EDGES_TSV"
    fi
  done < <(dependencies_for_pom "$pom_path")
done < <(cat "$UNITS_TSV" "$CONTEXT_TSV")

awk -F '\t' '{print $8 "\t" NR "\t" $1}' "$UNITS_TSV" | sort -rn -k1,1 -k2,2n > "$SORTED_UNITS_TSV"

ASSIGNED_UNITS="|"
DRAFT_COUNT=0
if [ "$PLAN_STRATEGY" = "module-sequential-batching" ]; then
  while IFS="$(printf '\t')" read -r unit _name _path _kind _artifact _loc _files _cost _split_reason; do
    [ -n "$unit" ] || continue
    DRAFT_COUNT=$((DRAFT_COUNT + 1))
    draft_file="$DRAFT_DIR/draft-$(printf '%03d' "$DRAFT_COUNT").tsv"
    : > "$draft_file"
    awk -F '\t' -v unit="$unit" '$1 == unit {print; exit}' "$UNITS_TSV" >> "$draft_file"
  done < "$UNITS_TSV"
else
  while [ "$(awk 'END {print NR + 0}' "$UNITS_TSV")" -gt "$(printf '%s' "$ASSIGNED_UNITS" | awk -F '|' '{print NF - 2}')" ]; do
    seed="$(next_unassigned_unit)"
    [ -n "$seed" ] || break
    DRAFT_COUNT=$((DRAFT_COUNT + 1))
    draft_file="$DRAFT_DIR/draft-$(printf '%03d' "$DRAFT_COUNT").tsv"
    : > "$draft_file"
    add_unit_to_draft "$seed" "$draft_file"
    try_fill_draft "$draft_file" "$TARGET_BATCH_COST"
    if [ "$(batch_sum_field "$draft_file" cost)" -lt "$SOFT_MIN_BATCH_COST" ]; then
      try_fill_draft "$draft_file" "$SOFT_MAX_BATCH_COST"
    fi
  done

  rebalance_tiny_batches
fi

BATCH_COUNT=0
for draft_file in "$DRAFT_DIR"/draft-*.tsv; do
  [ -s "$draft_file" ] || continue
  BATCH_COUNT=$((BATCH_COUNT + 1))
  batch_id="$(printf 'batch-%03d' "$BATCH_COUNT")"
  write_batch "$batch_id" "$RUN_DIR/batches/$batch_id.json" "$draft_file"
done

CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RUN_DIR/plan.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "project_name": "$(json_escape "$PROJECT_NAME")",
  "project_dir": "$(json_escape "$PROJECT_DIR")",
  "review_mode": "$(json_escape "$REVIEW_MODE")",
  "review_scope": "$(json_escape "$REVIEW_SCOPE_INPUT")",
  "selected_modules": $(write_json_string_array "${SELECTED_MODULES[@]}"),
  "branch": "$(json_escape "$BRANCH_NAME")",
  "strategy": "$(json_escape "$PLAN_STRATEGY")",
  "semantic_level": "$(json_escape "$SEMANTIC_LEVEL")",
  "total_java_loc": $TOTAL_JAVA_LOC,
  "total_java_file_count": $TOTAL_JAVA_FILE_COUNT,
  "batch_count": $BATCH_COUNT,
  "budget": {
    "target_batch_cost": $TARGET_BATCH_COST,
    "soft_min_batch_cost": $SOFT_MIN_BATCH_COST,
    "soft_max_batch_cost": $SOFT_MAX_BATCH_COST,
    "hard_max_batch_cost": $HARD_MAX_BATCH_COST,
    "tiny_batch_loc": $TINY_BATCH_LOC,
    "tiny_batch_cost": $TINY_BATCH_COST,
    "context_cost_ratio_percent": $CONTEXT_COST_RATIO_PERCENT,
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

rm -f "$UNITS_TSV" "$CONTEXT_TSV" "$EDGES_TSV" "$SORTED_UNITS_TSV"
rm -rf "$DRAFT_DIR"

echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_JAVA_LOC=$TOTAL_JAVA_LOC"
