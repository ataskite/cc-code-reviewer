#!/bin/bash
set -euo pipefail

# OWASP 离线基线显式维护升级脚本（非运行时；仅维护者显式调用）。
#
# 用法：
#   bash scripts/maintenance/update-owasp-baseline.sh \
#     --fetch <owasp-asvs|owasp-top10|owasp-api-top10|owasp-nodejs-cheat-sheet> \
#     --version <版本号> --revision <tag-or-commit-sha> --staging <dir>
#   bash scripts/maintenance/update-owasp-baseline.sh --emit-manifest --staging <dir>
#   bash scripts/maintenance/update-owasp-baseline.sh --verify-only <staging-dir>
#
# 约束（docs/superpowers/plans/2026-09-21-offline-owasp-node-security-controls.md §15）：
# - 本脚本绝不写入仓库：--fetch/--emit-manifest 只在显式 staging 目录内落盘；
#   复制进 references/security/upstream/ 由维护者人工执行并走正常 code review。
# - Skill、Agent、测试主流程绝不自动调用本脚本；审查运行时零网络依赖。
# - 只从 OWASP 官方域名/官方 GitHub 组织下载；网络失败保留清晰错误，不回退第三方镜像。
# - 不自动修改 catalog 映射、不自动提交、不 bump VERSION。
# - --emit-manifest 拒绝 license=UNVERIFIED 的来源：许可证标识必须由维护者依据上游
#   LICENSE 原文核验后写入 staging/.source-meta/<id>.json，不得凭记忆自动填写。
# - --verify-only 复用 tests/security/test_security_upstream.sh 的完整契约
#   （经 CC_CODE_REVIEWER_UPSTREAM_DIR 参数化），无网络环境同样可核验。

USAGE="用法: bash scripts/maintenance/update-owasp-baseline.sh (--fetch <source-id> --version <ver> --revision <rev> --staging <dir> | --emit-manifest --staging <dir> | --verify-only <staging-dir>)"

MODE=""
SRC_ID=""
VERSION=""
REVISION=""
STAGING=""

err() { echo "ERROR_OWASP_BASELINE=$*" >&2; echo "$USAGE" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch) [ $# -ge 2 ] || err "--fetch 缺少取值"; MODE=fetch; SRC_ID="$2"; shift 2 ;;
    --emit-manifest) MODE=emit-manifest; shift ;;
    --verify-only) [ $# -ge 2 ] || err "--verify-only 缺少取值"; MODE=verify-only; STAGING="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || err "--version 缺少取值"; VERSION="$2"; shift 2 ;;
    --revision) [ $# -ge 2 ] || err "--revision 缺少取值"; REVISION="$2"; shift 2 ;;
    --staging) [ $# -ge 2 ] || err "--staging 缺少取值"; STAGING="$2"; shift 2 ;;
    *) err "未知参数 $1" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../core/lib/common.sh"   # sha256_file / sha256_text 三级回退链

[ -n "$MODE" ] || err "必须指定 --fetch / --emit-manifest / --verify-only 之一"
command -v curl >/dev/null 2>&1 || err "维护态需要 curl（仅本脚本使用；审查运行时不需要）"

fetch_to() { # <url> <dest-file>
  local url="$1" dest="$2"
  case "$url" in
    https://github.com/OWASP/*|https://raw.githubusercontent.com/OWASP/*|https://owasp.org/*|https://www.owasp.org/*) ;;
    *) echo "ERROR_OWASP_BASELINE=非 OWASP 官方来源，拒绝下载: $url" >&2; exit 1 ;;
  esac
  if ! curl -fsSL --max-time 120 -o "$dest" "$url"; then
    echo "ERROR_OWASP_BASELINE=下载失败（不回退第三方镜像）: $url" >&2
    exit 1
  fi
}

TOP10_FILES=(introduction.md A01.md A02.md A03.md A04.md A05.md A06.md A07.md A08.md A09.md A10.md)
TOP10_UPSTREAM=(0x00_2025-Introduction.md A01_2025-Broken_Access_Control.md A02_2025-Security_Misconfiguration.md A03_2025-Software_Supply_Chain_Failures.md A04_2025-Cryptographic_Failures.md A05_2025-Injection.md A06_2025-Insecure_Design.md A07_2025-Authentication_Failures.md A08_2025-Software_or_Data_Integrity_Failures.md A09_2025-Security_Logging_and_Alerting_Failures.md A10_2025-Mishandling_of_Exceptional_Conditions.md)
API10_FILES=(introduction.md API1.md API2.md API3.md API4.md API5.md API6.md API7.md API8.md API9.md API10.md)
API10_UPSTREAM=(0x03-introduction.md 0xa1-broken-object-level-authorization.md 0xa2-broken-authentication.md 0xa3-broken-object-property-level-authorization.md 0xa4-unrestricted-resource-consumption.md 0xa5-broken-function-level-authorization.md 0xa6-unrestricted-access-to-sensitive-business-flows.md 0xa7-server-side-request-forgery.md 0xa8-security-misconfiguration.md 0xa9-improper-inventory-management.md 0xaa-unsafe-consumption-of-apis.md)

case "$MODE" in
  fetch)
    [ -n "$SRC_ID" ] || err "--fetch 缺少来源 ID"
    [ -n "$VERSION" ] || err "--fetch 需要 --version"
    [ -n "$REVISION" ] || err "--fetch 需要 --revision（release tag 或 commit SHA）"
    [ -n "$STAGING" ] || err "--fetch 需要 --staging"
    mkdir -p "$STAGING/.source-meta"
    META="$STAGING/.source-meta/$SRC_ID.json"
    if [ -f "$META" ]; then
      echo "ERROR_OWASP_BASELINE=staging 已含 $SRC_ID 元数据，拒绝覆盖（换新目录或人工清理）: $META" >&2
      exit 1
    fi
    case "$SRC_ID" in
      owasp-asvs)
        DEST_REL="asvs/$VERSION"
        mkdir -p "$STAGING/$DEST_REL"
        fetch_to "https://github.com/OWASP/ASVS/releases/download/$REVISION/OWASP_Application_Security_Verification_Standard_${VERSION}_en.json" \
          "$STAGING/$DEST_REL/OWASP_Application_Security_Verification_Standard_${VERSION}_en.json"
        URL="https://github.com/OWASP/ASVS/releases/download/$REVISION/OWASP_Application_Security_Verification_Standard_${VERSION}_en.json"
        ;;
      owasp-top10)
        DEST_REL="top10/$VERSION"
        mkdir -p "$STAGING/$DEST_REL"
        for idx in "${!TOP10_FILES[@]}"; do
          fetch_to "https://raw.githubusercontent.com/OWASP/Top10/$REVISION/$VERSION/docs/en/${TOP10_UPSTREAM[$idx]}" \
            "$STAGING/$DEST_REL/${TOP10_FILES[$idx]}"
        done
        URL="https://github.com/OWASP/Top10/tree/$REVISION/$VERSION/docs/en"
        ;;
      owasp-api-top10)
        DEST_REL="api-top10/$VERSION"
        mkdir -p "$STAGING/$DEST_REL"
        for idx in "${!API10_FILES[@]}"; do
          fetch_to "https://raw.githubusercontent.com/OWASP/API-Security/$REVISION/editions/$VERSION/en/${API10_UPSTREAM[$idx]}" \
            "$STAGING/$DEST_REL/${API10_FILES[$idx]}"
        done
        URL="https://github.com/OWASP/API-Security/tree/$REVISION/editions/$VERSION/en"
        ;;
      owasp-nodejs-cheat-sheet)
        SHA12="$(printf '%s' "$REVISION" | cut -c1-12)"
        DEST_REL="nodejs-cheat-sheet/$SHA12"
        mkdir -p "$STAGING/$DEST_REL"
        fetch_to "https://raw.githubusercontent.com/OWASP/CheatSheetSeries/$REVISION/cheatsheets/Nodejs_Security_Cheat_Sheet.md" \
          "$STAGING/$DEST_REL/Nodejs_Security_Cheat_Sheet.md"
        URL="https://github.com/OWASP/CheatSheetSeries/blob/$REVISION/cheatsheets/Nodejs_Security_Cheat_Sheet.md"
        ;;
      *) err "未知来源 ID: $SRC_ID" ;;
    esac
    # 许可证恒置 UNVERIFIED：维护者必须依据上游 LICENSE 原文人工核验后改写。
    printf '{\n  "id": "%s",\n  "version": "%s",\n  "source_url": "%s",\n  "source_revision": "%s",\n  "license": "UNVERIFIED"\n}\n' \
      "$SRC_ID" "$VERSION" "$URL" "$REVISION" > "$META"
    echo "FETCHED=$SRC_ID DEST=$STAGING/$DEST_REL"
    echo "NEXT=人工核验上游许可证后，将 $META 的 license 改为 SPDX 标识；为每个目录补 NOTICE.md（来源/版本/revision/抓取日期/许可证/原样保存声明），再运行 --emit-manifest"
    ;;
  emit-manifest)
    [ -n "$STAGING" ] || err "--emit-manifest 需要 --staging"
    [ -d "$STAGING" ] || err "staging 目录不存在: $STAGING"
    [ -f "$STAGING/.source-meta/owasp-asvs.json" ] && [ -f "$STAGING/.source-meta/owasp-top10.json" ] \
      && [ -f "$STAGING/.source-meta/owasp-api-top10.json" ] && [ -f "$STAGING/.source-meta/owasp-nodejs-cheat-sheet.json" ] \
      || err "staging 缺少四源 .source-meta（先逐源 --fetch）"
    for m in "$STAGING"/.source-meta/*.json; do
      grep -q '"license": "UNVERIFIED"' "$m" && err "$(basename "$m") 许可证未核验（license=UNVERIFIED）——依据上游 LICENSE 原文人工核验后再 --emit-manifest"
    done
    perl -MJSON::PP -MDigest::SHA -e '
      use strict; use warnings;
      my ($staging, $now) = @ARGV;
      my @order = qw(owasp-asvs owasp-top10 owasp-api-top10 owasp-nodejs-cheat-sheet);
      my @sources;
      for my $id (@order) {
        my $mtxt; { local $/; open my $f, "<", "$staging/.source-meta/$id.json" or die "ERROR_META_READ=$id\n"; $mtxt = <$f>; }
        my $meta = eval { decode_json($mtxt) }; die "ERROR_META_JSON=$id\n" if $@ || ref($meta) ne "HASH";
        my $root = $id eq "owasp-asvs" ? "asvs/$meta->{version}"
                 : $id eq "owasp-top10" ? "top10/$meta->{version}"
                 : $id eq "owasp-api-top10" ? "api-top10/$meta->{version}"
                 : "nodejs-cheat-sheet/" . substr($meta->{source_revision}, 0, 12);
        my $abs = "$staging/$root";
        die "ERROR_STAGING_LAYOUT=缺少目录 $root\n" unless -d $abs;
        die "ERROR_NOTICE_MISSING=$root（NOTICE.md 必须先人工补齐）\n" unless -f "$abs/NOTICE.md";
        opendir(my $dh, $abs) or die "ERROR_STAGING_READ=$root\n";
        my @content = sort grep { !/^\./ && !/^(SHA256SUMS|NOTICE\.md)$/ } readdir($dh);
        closedir($dh);
        die "ERROR_STAGING_EMPTY=$root\n" unless @content;
        my @files;
        my @sums_lines;
        for my $name (@content) {
          my $p = "$abs/$name";
          die "ERROR_STAGING_FILE=$root/$name\n" unless -f $p;
          my $d = Digest::SHA->new(256); $d->addfile($p, "b");
          my $h = $d->hexdigest;
          push @files, { path => "$root/$name", sha256 => $h };
          push @sums_lines, "$h  $name";
        }
        { open my $sf, ">", "$abs/SHA256SUMS" or die "ERROR_SUMS_WRITE=$root\n"; print $sf map { "$_\n" } @sums_lines; close $sf; }
        push @sources, {
          id => $id, version => $meta->{version}, source_url => $meta->{source_url},
          source_revision => $meta->{source_revision}, license => $meta->{license},
          local_root => $root, files => \@files,
        };
      }
      my $manifest = { schema_version => 1, generated_at => $now, sources => \@sources };
      my $json = JSON::PP->new->canonical->pretty->indent_length(2)->encode($manifest);
      $json =~ s/\n?\z/\n/;
      open my $mf, ">", "$staging/manifest.json" or die "ERROR_MANIFEST_WRITE\n";
      print $mf $json; close $mf;
      my $total = 0; $total += scalar @{ $_->{files} } for @sources;
      print "MANIFEST_EMITTED=$staging/manifest.json SOURCES=4 FILES=$total\n";
    ' "$STAGING" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || exit 1
    REPO_UPSTREAM="$REPO_ROOT/references/security/upstream"
    if [ -f "$REPO_UPSTREAM/manifest.json" ]; then
      echo "---- 与仓库现状的差异摘要 ----"
      diff -rq "$REPO_UPSTREAM" "$STAGING" --exclude .source-meta 2>/dev/null | sed -n '1,40p' || true
    fi
    echo "NEXT=人工审阅差异后复制 staging 内容覆盖 references/security/upstream/，重算 catalog 的 upstream_manifest_sha256，并跑 bash tests/security/test_security_upstream.sh"
    ;;
  verify-only)
    [ -d "$STAGING" ] || err "staging 目录不存在: $STAGING"
    STAGING_ABS="$(cd "$STAGING" && pwd -P)"
    CC_CODE_REVIEWER_UPSTREAM_DIR="$STAGING_ABS" bash "$REPO_ROOT/tests/security/test_security_upstream.sh" \
      || err "staging 未通过离线基线完整性契约: $STAGING_ABS"
    echo "VERIFY_ONLY_OK=$STAGING_ABS"
    ;;
esac
