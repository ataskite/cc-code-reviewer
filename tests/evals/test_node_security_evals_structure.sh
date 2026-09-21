#!/usr/bin/env bash
# tests/evals/test_node_security_evals_structure.sh
#
# Node Security 模型评测夹具结构校验。
# 只证明 fixture 结构完整（README/清单/目录/控制 ID/脱敏），不运行模型、
# 不产出任何召回率数字——模型召回率只能由 tests/evals/node-security/README.md
# 描述的协议实际运行并记录后产生。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_ROOT="$SCRIPT_DIR/node-security"
README="$EVAL_ROOT/README.md"
EXPECTED_JSON="$EVAL_ROOT/expected-controls.json"

# 当前已实现审查规则的 7 条控制（catalog 共 12 条，其余未实现不得出现在预期里）
ALLOWED_CONTROLS=(
  CCR-NODE-BFFHEADER-001
  CCR-NODE-SSRF-001
  CCR-NODE-SESSION-001
  CCR-NODE-CMD-001
  CCR-NODE-PATH-001
  CCR-NODE-BOLA-001
  CCR-NODE-BFLA-001
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

is_allowed_control() {
  local want="$1" allowed
  for allowed in "${ALLOWED_CONTROLS[@]}"; do
    [[ "$allowed" == "$want" ]] && return 0
  done
  return 1
}

# --- 1. README 与 expected-controls.json 存在，且 JSON 合法 -------------------
[[ -f "$README" ]] || fail "missing README: $README"
[[ -f "$EXPECTED_JSON" ]] || fail "missing expected-controls.json: $EXPECTED_JSON"

json_cases="$(
  perl -MJSON::PP -0777 -e '
    my $raw = scalar <STDIN>;
    my $data = eval { decode_json($raw) };
    die "invalid JSON: $@\n" if $@;
    die "root is not a JSON array\n" unless ref($data) eq "ARRAY";
    die "case array is empty\n" unless @$data;
    for my $item (@$data) {
      die "entry is not a JSON object\n" unless ref($item) eq "HASH";
      die "entry missing non-empty \"case\"\n"
        unless defined $item->{case} && $item->{case} !~ /^\s*$/;
      print $item->{case}, "\n";
    }
  ' <"$EXPECTED_JSON"
)" || fail "expected-controls.json is not valid JSON or has bad shape"

# 控制 ID / 状态枚举 / 期望一致性的机器检查
control_lines="$(
  perl -MJSON::PP -0777 -e '
    my $data = decode_json(scalar <STDIN>);
    my %valid_status = map { $_ => 1 } qw(
      finding_confirmed checked_no_finding external_evidence_missing
      static_unsupported not_applicable
    );
    for my $item (@$data) {
      my @expected = @{ $item->{expected_findings} || [] };
      my @forbidden = @{ $item->{forbidden_findings} || [] };
      my $st = $item->{expected_control_status};
      if (defined $st) {
        die "expected_control_status is not an object (case $item->{case})\n"
          unless ref($st) eq "HASH";
        for my $k (sort keys %$st) {
          die "invalid status \"$st->{$k}\" for $k (case $item->{case})\n"
            unless $valid_status{ $st->{$k} };
          die "status key $k not in expected/forbidden (case $item->{case})\n"
            unless grep { $_ eq $k } (@expected, @forbidden);
        }
      }
      my @confirmed = sort grep { ($st->{$_} || "") eq "finding_confirmed" } keys %{ $st || {} };
      die "finding_confirmed keys != expected_findings (case $item->{case})\n"
        unless join("\0", @confirmed) eq join("\0", sort @expected);
      print "ID\t$_\n" for (@expected, @forbidden, sort keys %{ $st || {} });
    }
  ' <"$EXPECTED_JSON"
)" || fail "expected-controls.json has invalid control ids, statuses, or inconsistent expectations"

while IFS=$'\t' read -r kind id; do
  [[ "$kind" == "ID" ]] || continue
  [[ "$id" =~ ^CCR-NODE-[A-Z0-9]+-[0-9]{3}$ ]] || fail "control id format invalid: $id"
  is_allowed_control "$id" || fail "control id not in implemented set: $id"
done <<<"$control_lines"

# --- 2/3. 磁盘 case 目录与 JSON case 集合双向一致 ------------------------------
disk_cases="$(cd "$EVAL_ROOT" && find . -mindepth 2 -maxdepth 2 -type d ! -name node_modules | sed 's|^\./||' | sort)"
[[ -n "$disk_cases" ]] || fail "no case directories under $EVAL_ROOT"

json_cases_sorted="$(printf '%s' "$json_cases" | sort)"

only_in_json="$(comm -23 <(printf '%s' "$json_cases_sorted") <(printf '%s' "$disk_cases"))"
only_on_disk="$(comm -13 <(printf '%s' "$json_cases_sorted") <(printf '%s' "$disk_cases"))"
[[ -z "$only_in_json" ]] || fail "cases in expected-controls.json but missing on disk: $(printf '%s' "$only_in_json" | tr '\n' ' ')"
[[ -z "$only_on_disk" ]] || fail "case directories on disk but missing from expected-controls.json: $(printf '%s' "$only_on_disk" | tr '\n' ' ')"

# --- 每个 case：package.json + 至少一个 .js，package 名唯一且 JSON 合法 -------
case_count=0
pkg_names=""
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  case_count=$((case_count + 1))
  dir="$EVAL_ROOT/$rel"
  [[ -f "$dir/package.json" ]] || fail "case $rel is missing package.json"
  if ! find "$dir" -type f -name '*.js' | grep -q .; then
    fail "case $rel has no .js server file"
  fi
  name="$(
    perl -MJSON::PP -0777 -e '
      my $d = decode_json(scalar <STDIN>);
      die "missing name\n" unless defined $d->{name} && $d->{name} ne "";
      print $d->{name}, "\n";
    ' <"$dir/package.json"
  )" || fail "case $rel: package.json is not valid JSON or missing name"
  pkg_names+="$name"
done <<<"$disk_cases"

dup_names="$(printf '%s' "$pkg_names" | sort | uniq -d)"
[[ -z "$dup_names" ]] || fail "duplicate package.json name across fixtures: $(printf '%s' "$dup_names" | tr '\n' ' ')"

# --- 5. 疑似真实凭据扫描 -------------------------------------------------------
cred_hits="$(grep -rEn -- '(sk|pk|tok)_live|AKIA[0-9A-Z]{16}|BEGIN (RSA|EC) PRIVATE KEY' "$EVAL_ROOT" || true)"
[[ -z "$cred_hits" ]] || fail "suspected real credentials leaked in fixtures: $cred_hits"

echo "PASS: node-security eval fixture structure verified (cases=$case_count, implemented_controls=${#ALLOWED_CONTROLS[@]})"
