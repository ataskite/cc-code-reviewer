#!/bin/bash
# Validate the Claude Code, Codex, and ZCode distribution manifests as one release.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

die() { echo "MANIFEST VALIDATION FAIL: $*" >&2; exit 1; }

VERSION_FILE="$PLUGIN_ROOT/VERSION"
CLAUDE_PLUGIN="$PLUGIN_ROOT/.claude-plugin/plugin.json"
CLAUDE_MARKET="$PLUGIN_ROOT/.claude-plugin/marketplace.json"
CODEX_PLUGIN="$PLUGIN_ROOT/.codex-plugin/plugin.json"
CODEX_MARKET="$PLUGIN_ROOT/.agents/plugins/marketplace.json"
ZCODE_PLUGIN="$PLUGIN_ROOT/.zcode-plugin/plugin.json"

[ -s "$VERSION_FILE" ] || die "VERSION 单一真相源缺失或为空"
TRUTH_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

for manifest in "$CLAUDE_PLUGIN" "$CLAUDE_MARKET" "$CODEX_PLUGIN" "$CODEX_MARKET" "$ZCODE_PLUGIN"; do
  [ -f "$manifest" ] || die "清单缺失: $manifest"
  perl -MJSON::PP -e 'decode_json(do { local $/; open my $fh, "<", $ARGV[0] or die $!; <$fh> })' "$manifest" \
    >/dev/null 2>&1 || die "JSON 不可解析: $manifest"
done

perl -MJSON::PP -e '
  use strict; use warnings;
  my ($root, $version, $claude_plugin, $claude_market, $codex_plugin, $codex_market, $zcode_plugin) = @ARGV;
  sub load_json {
    my ($file) = @_;
    open my $fh, "<", $file or die "cannot open $file: $!";
    local $/;
    return decode_json(<$fh>);
  }
  sub require_value {
    my ($ok, $message) = @_;
    die "$message\n" unless $ok;
  }

  my $expected_name = "cc-code-reviewer";
  my $expected_repo = "https://github.com/ataskite/cc-code-reviewer";
  my $claude = load_json($claude_plugin);
  my $claude_catalog = load_json($claude_market);
  my $codex = load_json($codex_plugin);
  my $codex_catalog = load_json($codex_market);
  my $zcode = load_json($zcode_plugin);

  for my $pair ([$claude, $claude_plugin], [$codex, $codex_plugin], [$zcode, $zcode_plugin]) {
    my ($manifest, $file) = @$pair;
    require_value(($manifest->{name} // "") eq $expected_name, "$file name 不一致");
    require_value(($manifest->{version} // "") eq $version, "$file version 与 VERSION 不一致");
    require_value(($manifest->{repository} // "") eq $expected_repo, "$file repository 不一致");
    my %keywords = map { $_ => 1 } @{ $manifest->{keywords} // [] };
    require_value($keywords{"code-fix"}, "$file 未声明 code-fix keyword");
  }

  require_value(($claude_catalog->{version} // "") eq $version, "$claude_market version 与 VERSION 不一致");
  for my $entry (@{ $claude_catalog->{plugins} // [] }) {
    require_value(($entry->{version} // "") eq $version, "$claude_market plugin entry version 与 VERSION 不一致");
  }

  require_value(($codex->{skills} // "") eq "./skills/", "$codex_plugin skills 路径错误");
  require_value(($zcode->{skills} // "") eq "skills", "$zcode_plugin skills 路径错误");

  my $entries = $codex_catalog->{plugins};
  require_value(ref($entries) eq "ARRAY" && @$entries == 1, "$codex_market 必须包含唯一插件条目");
  my $entry = $entries->[0];
  require_value(($entry->{name} // "") eq $expected_name, "$codex_market plugin name 不一致");
  require_value(ref($entry->{source}) eq "HASH", "$codex_market source 必须是对象");
  require_value(($entry->{source}{source} // "") eq "local", "$codex_market source.source 必须为 local");
  require_value(($entry->{source}{path} // "") eq "./", "$codex_market source.path 必须指向仓库插件根");
  require_value(($entry->{policy}{installation} // "") eq "AVAILABLE", "$codex_market 缺少 policy.installation=AVAILABLE");
  require_value(($entry->{policy}{authentication} // "") eq "ON_INSTALL", "$codex_market 缺少 policy.authentication=ON_INSTALL");
  require_value(length($entry->{category} // "") > 0, "$codex_market 缺少 category");

  for my $skill ("cc-code-reviewer", "cc-code-ignore", "cc-code-fixer") {
    my $shared = "$root/skills/$skill/SKILL.md";
    require_value(-f $shared, "$shared 共享 Skill 缺失");
    open my $fh, "<", $shared or die "cannot open $shared: $!";
    local $/; my $body = <$fh>;
    require_value(index($body, "PLUGIN_ROOT") >= 0, "$shared 未声明 PLUGIN_ROOT");
    require_value(index($body, "INTERACT") >= 0, "$shared 未声明逻辑交互动作 INTERACT");
    require_value(index($body, "\${CLAUDE_PLUGIN_ROOT}") < 0, "$shared 残留 CLAUDE_PLUGIN_ROOT");
  }
' "$PLUGIN_ROOT" "$TRUTH_VERSION" "$CLAUDE_PLUGIN" "$CLAUDE_MARKET" "$CODEX_PLUGIN" "$CODEX_MARKET" "$ZCODE_PLUGIN" \
  || die "三端清单或共享 Skill 契约不满足"

echo "✅ 三端插件清单校验通过（version=${TRUTH_VERSION}）"
