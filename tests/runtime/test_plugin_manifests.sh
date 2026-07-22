#!/bin/bash
# Native manifest and marketplace contract for Claude Code, Codex, and ZCode.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/core/validate-plugin-manifests.sh"

fail() { echo "FAIL test_plugin_manifests: $*" >&2; exit 1; }

[ -s "$ROOT_DIR/VERSION" ] || fail "VERSION 文件缺失或为空"

for manifest in \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  .codex-plugin/plugin.json \
  .agents/plugins/marketplace.json \
  .zcode-plugin/plugin.json; do
  [ -f "$ROOT_DIR/$manifest" ] || fail "清单缺失: $manifest"
done

bash "$VALIDATOR" >/dev/null || fail "真实三端清单校验失败"

# Negative gate: Codex manifest without skills must fail.
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
cp -R "$ROOT_DIR/.claude-plugin" "$FIXTURE_DIR/.claude-plugin"
cp -R "$ROOT_DIR/.codex-plugin" "$FIXTURE_DIR/.codex-plugin"
cp -R "$ROOT_DIR/.zcode-plugin" "$FIXTURE_DIR/.zcode-plugin"
mkdir -p "$FIXTURE_DIR/.agents/plugins" "$FIXTURE_DIR/scripts/core" "$FIXTURE_DIR/skills"
cp "$ROOT_DIR/.agents/plugins/marketplace.json" "$FIXTURE_DIR/.agents/plugins/marketplace.json"
cp "$ROOT_DIR/VERSION" "$FIXTURE_DIR/VERSION"
cp -R "$ROOT_DIR/skills/." "$FIXTURE_DIR/skills/"

perl -MJSON::PP -e '
  binmode STDOUT, ":encoding(UTF-8)";
  my $f = $ARGV[0]; open my $in, "<", $f or die; local $/; my $j = decode_json(<$in>); close $in;
  delete $j->{skills}; open my $out, ">:encoding(UTF-8)", $f or die; print {$out} JSON::PP->new->canonical->pretty->encode($j);
' "$FIXTURE_DIR/.codex-plugin/plugin.json"

if bash "$VALIDATOR" "$FIXTURE_DIR" >/dev/null 2>&1; then
  fail "Codex manifest 缺少 skills 时校验器仍通过"
fi

# Negative gate: marketplace policy is mandatory.
cp "$ROOT_DIR/.codex-plugin/plugin.json" "$FIXTURE_DIR/.codex-plugin/plugin.json"
perl -MJSON::PP -e '
  binmode STDOUT, ":encoding(UTF-8)";
  my $f = $ARGV[0]; open my $in, "<", $f or die; local $/; my $j = decode_json(<$in>); close $in;
  delete $j->{plugins}[0]{policy}; open my $out, ">:encoding(UTF-8)", $f or die; print {$out} JSON::PP->new->canonical->pretty->encode($j);
' "$FIXTURE_DIR/.agents/plugins/marketplace.json"

if bash "$VALIDATOR" "$FIXTURE_DIR" >/dev/null 2>&1; then
  fail "Codex marketplace 缺少 policy 时校验器仍通过"
fi

echo "✅ 三端插件清单契约测试通过"
