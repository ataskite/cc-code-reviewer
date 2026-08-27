#!/bin/bash
set -euo pipefail
# 文件类型专项清单映射（filetype-rule-map.json）完整性与端到端契约测试。
#
# 覆盖八类回归面：
#   [1] map schema：字段形状、重复字面量/展开等价拒绝
#   [2] map→磁盘一致性：slug 必须有文档、无孤儿文档、文档首行必须为
#       `<!-- 适用: ... -->` 且声明了引用它的每个 pattern（死映射防线）
#   [3] first-match-wins：重叠模式下首个 pattern 独占文件；禁用条目不参与
#   [4] 大小写不敏感：POM.XML 命中 pom 规则、大写 mapper 形态命中（纯 glob 单元）
#   [5] resolver 端到端：mini fixture 分组正确、plain 文件不进组、content 与磁盘一致
#   [6] 遗留字段保持：新增 filetype_checklists 纯增量，旧键语义与逐文件键集不变
#   [7] 伴随文件扩展：java 模块产出 pom+resources 进 manifest；300 合成资源被
#       200 上限截断并 stderr 说明；两次运行逐字节确定
#   [8] 零命中字节稳定：无命中时字段整体缺省，顶层键集合与遗留形态完全一致
#   另附跨采集器可达性交叉核对（任一 slug 必须能被真实 collector 输出命中，
#   否则即 OCR 式「永远触达不了的死规则」）。

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-ftmap.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

MAP="$ROOT_DIR/scripts/core/filetype-rule-map.json"
CHECKLISTS="$ROOT_DIR/references/review-checklists"
RESOLVER="$ROOT_DIR/scripts/core/resolve-review-rules.sh"
JAVA_COLLECT="$ROOT_DIR/scripts/languages/java/collect-source-files.sh"
FE_COLLECT="$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh"
PY_COLLECT="$ROOT_DIR/scripts/languages/python/collect-source-files.sh"

fail() { echo "FAIL: core filetype-rule-map: $*" >&2; exit 1; }
test -r "$MAP" || fail "map missing"
test -d "$CHECKLISTS" || fail "checklists dir missing"

# ============ [1] map schema ============
perl -MJSON::PP -e '
  local $/; my $m=decode_json(<STDIN>);
  die "schema_version != 1\n" unless ($m->{schema_version}//0) == 1;
  die "match semantics must be first\n" unless ($m->{match}//"") eq "first";
  my $pats=$m->{patterns} or die "patterns missing\n";
  @$pats or die "patterns empty\n";
  sub expand_braces { my ($p)=@_; if ($p =~ /^([^{}]*)\{([^{}]+)\}(.*)$/s) { my @out; for my $alt (split /,/,$2) { push @out,@{expand_braces("$1$alt$3")}; } return \@out; } return [$p]; }
  my %seen_lit; my %seen_alt;
  for my $e (@$pats) {
    ref($e) eq "HASH" or die "non-object entry\n";
    my ($pat,$cl)=($e->{pattern}//"", $e->{checklist}//"");
    length($pat) && length($cl) or die "entry needs pattern+checklist\n";
    die "duplicate literal pattern $pat\n" if $seen_lit{$pat}++;
    for my $alt (@{expand_braces($pat)}) {
      die "expanded duplicate of $alt\n" if $seen_alt{$alt}++;
    }
    push @{$main::slugs{$cl}}, $pat;
  }
' < "$MAP"

# ============ [2] map→disk 一致性 + 适用头匹配 ============
perl -MJSON::PP -e '
  use strict; use warnings;
  my ($map,$cldir)=@ARGV;
  local $/; open my $mf,"<",$map or die; my $m=decode_json(<$mf>); close $mf;
  my %used; my %pat_by_slug;
  for my $e (@{$m->{patterns}}) {
    $used{$e->{checklist}}=1;
    push @{$pat_by_slug{$e->{checklist}}}, $e->{pattern};
  }
  opendir my $dh,$cldir or die "opendir $cldir: $!";
  while (my $f=readdir $dh) {
    next unless $f =~ /\.md$/;
    my $slug=$f; $slug =~ s/\.md$//;
    my $path="$cldir/$f";
    die "orphan checklist doc: $f not referenced by any map pattern\n" unless $used{$slug};
    open my $cf,"<",$path or die; binmode $cf; local $/; my $raw=<$cf>; close $cf;
    die "empty checklist doc: $f\n" unless length $raw;
    die "checklist oversize: $f (".length($raw)." bytes > 8192)\n" if length($raw) > 8192;
    delete $used{$slug};
    # 文档必须以 <!-- 适用: ... --> 开头，且列出引用该 slug 的每个 pattern。
    my @heads = ($raw =~ /<!--\s*适用:(.*?)-->/sg);
    die "doc $f missing first-line 适用 comment\n" unless $raw =~ /\A<!--\s*适用:/;
    my $declared = join("|", @heads);
    for my $pat (@{$pat_by_slug{$slug}}) {
      index($declared, $pat) >= 0 or die "doc $f 适用 comment lacks its own pattern: $pat\n";
    }
    # 中文标题 + 动作句底线
    die "doc $f missing H1 title\n" unless $raw =~ /^# /m;
    die "doc $f bullets must start with action verbs\n" unless $raw =~ /^- (核对|检查|排查|审视|确认|验证)/m;
  }
  closedir $dh;
  die "map references missing docs: ".join(",", sort keys %used)."\n" if %used;
' "$MAP" "$CHECKLISTS"

# ============ 可达性 fixture（镜像各 collector 发现口径）============
REPO="$TMP_DIR/repo"
mkdir -p \
  "$REPO/app/src/main/java/demo" \
  "$REPO/app/src/main/resources/mapper" \
  "$REPO/app/src/test/resources" \
  "$REPO/target/stub" \
  "$REPO/.github/workflows" \
  "$REPO/sub/gsvc/src/main/java/pkg" \
  "$REPO/sub/gsvc/src/main/resources"

printf 'class Demo {}\n'      > "$REPO/app/src/main/java/demo/Demo.java"
printf 'class Svc {}\n'       > "$REPO/sub/gsvc/src/main/java/pkg/Gsvc.java"

printf '<project/>\n'          > "$REPO/pom.xml"
printf '<project/>\n'          > "$REPO/app/pom.xml"
printf '<project/>\n'          > "$REPO/target/stub/pom.xml"        # 必须被剪枝
printf "plugins {}\n"          > "$REPO/app/build.gradle.kts"
printf "plugins {}\n"          > "$REPO/sub/gsvc/build.gradle"

printf 'a: 1\n'                > "$REPO/app/src/main/resources/application.yml"
printf 'b: 2\n'                > "$REPO/app/src/main/resources/application.yaml"
printf 'c: 3\n'                > "$REPO/app/src/main/resources/application-prod.properties"
printf 'boot\n'                > "$REPO/app/src/main/resources/bootstrap.yml"
printf '<config/>\n'           > "$REPO/app/src/main/resources/logback-spring.xml"
printf '<log4j/>\n'            > "$REPO/app/src/main/resources/log4j2.xml"
printf '<mapper ns="u"/>\n'    > "$REPO/app/src/main/resources/UserMapper.xml"
# 大小写金丝雀放独立目录：macOS APFS 大小写不敏感，同目录两份仅大小写不同的
# 文件名会互相覆盖，无法共存。
printf '<mapper ns="l"/>\n'    > "$REPO/sub/gsvc/src/main/resources/usermapper.xml"
printf '<mapper ns="d"/>\n'    > "$REPO/app/src/main/resources/user_dao.xml"
printf '{"openapi":"3"}\n'     > "$REPO/app/src/main/resources/openapi.json"
printf 'openapi: 3\n'          > "$REPO/app/src/main/resources/openapi.yml"
printf 'openapi: "3"\n'        > "$REPO/app/src/main/resources/openapi.yaml"
printf '{"swagger":"2"}\n'     > "$REPO/app/src/main/resources/swagger.json"
printf 'swagger: "2"\n'        > "$REPO/app/src/main/resources/swagger.yml"
printf 'swagger: "2.0"\n'      > "$REPO/app/src/main/resources/swagger.yaml"
printf '<random/>\n'           > "$REPO/app/src/main/java/demo/notes.xml"        # 非 mapper 命名不得进清单
printf 't\n'                   > "$REPO/app/src/test/resources/application.yml"  # test resources 排除

printf 'CI\n'                  > "$REPO/.github/workflows/ci.yml"
printf 'CD\n'                  > "$REPO/.github/workflows/deploy.yaml"
printf 'pipeline {}\n'         > "$REPO/Jenkinsfile"
printf 'gitlab ci\n'           > "$REPO/.gitlab-ci.yml"
printf 'FROM alpine\n'         > "$REPO/Dockerfile"
printf 'FROM node\n'           > "$REPO/sub/Dockerfile.builder"

JAVA_OUT="$(bash "$JAVA_COLLECT" "$REPO")"
[ -n "$JAVA_OUT" ] || fail "java collector emitted nothing"
printf '%s\n' "$JAVA_OUT" > "$TMP_DIR/java.manifest"

if printf '%s\n' "$JAVA_OUT" | grep -q '/target/stub/pom\.xml'; then fail "target pruning broken"; fi
if printf '%s\n' "$JAVA_OUT" | grep -q '/app/src/test/resources/application\.yml'; then fail "src/test resources leaked"; fi
if printf '%s\n' "$JAVA_OUT" | grep -q '/demo/notes\.xml'; then fail "random xml leaked into companions"; fi

assert_in_manifest() {
  local needle="$1" label="$2"
  printf '%s\n' "$JAVA_OUT" | grep -Fq -- "$needle" || fail "canary not collected ($label): $needle"
}
assert_in_manifest "/pom.xml"               "maven-pom root"
assert_in_manifest "/app/build.gradle.kts"  "gradle kts"
assert_in_manifest "/sub/gsvc/build.gradle" "gradle groovy"
assert_in_manifest "UserMapper.xml"         "mapper camelcase"
assert_in_manifest "usermapper.xml"         "mapper lowercase"
assert_in_manifest "user_dao.xml"           "mapper dao"
assert_in_manifest "application.yml"        "spring yml"
assert_in_manifest "application.yaml"       "spring yaml"
assert_in_manifest "application-prod.properties" "spring properties"
assert_in_manifest "bootstrap.yml"          "spring bootstrap"
assert_in_manifest "logback-spring.xml"     "logging logback"
assert_in_manifest "log4j2.xml"             "logging log4j2"
assert_in_manifest "/.github/workflows/ci.yml"      "ci gh yml"
assert_in_manifest "/.github/workflows/deploy.yaml" "ci gh yaml"
assert_in_manifest "/Jenkinsfile"           "ci jenkins"
assert_in_manifest "/.gitlab-ci.yml"        "ci gitlab"
assert_in_manifest "/Dockerfile"            "docker primary"
assert_in_manifest "/sub/Dockerfile.builder" "docker variant"
for ext in json yml yaml; do
  assert_in_manifest "openapi.$ext" "openapi $ext"
  assert_in_manifest "swagger.$ext" "swagger $ext"
done

python_fixture() {
  # python collector 口径最小镜像：flat 包布局 + Django 核心 + 根级依赖描述符
  mkdir -p "$1/app_pkg" "$1/tests"
  printf 'VALUE = 1\n' > "$1/app_pkg/core.py"
  printf ''            > "$1/app_pkg/__init__.py"
  printf 'DEBUG = True\n'                    > "$1/app_pkg/settings.py"
  printf 'from app_pkg import views\n'       > "$1/app_pkg/urls.py"
  printf 'def test_x():\n    pass\n' > "$1/tests/test_core.py"
  printf 'django>=4.0\n'             > "$1/requirements.txt"
  printf '[project]\nname="app"\n'   > "$1/pyproject.toml"
}
fe_fixture() {
  # frontend collector 口径最小镜像：react package + src 生产源码 + 根级配置脚本
  mkdir -p "$1/web/src"
  cat > "$1/web/package.json" <<'JSON'
{"name":"web","dependencies":{"react":"^18.0.0"}}
JSON
  printf 'export const x = 1;\n' > "$1/web/src/index.tsx"
  printf 'export default {};\n' > "$1/web/vite.config.ts"   # 根级配置脚本必须保持排除
}

PYSRC="$TMP_DIR/pyrepo"; python_fixture "$PYSRC"
bash "$PY_COLLECT" "$PYSRC" > "$TMP_DIR/python.mini.manifest"
grep -q 'app_pkg/core.py' "$TMP_DIR/python.mini.manifest" || fail "python collector smoke broken"
grep -q 'app_pkg/settings.py' "$TMP_DIR/python.mini.manifest" || fail "django settings.py unreachable"
grep -q 'app_pkg/urls.py' "$TMP_DIR/python.mini.manifest" || fail "urls.py unreachable"
grep -q '/pyproject.toml' "$TMP_DIR/python.mini.manifest" || fail "pyproject.toml companion missing"
grep -q '/requirements.txt' "$TMP_DIR/python.mini.manifest" || fail "requirements.txt companion missing"

FESRC="$TMP_DIR/ferepo"; fe_fixture "$FESRC"
bash "$FE_COLLECT" "$FESRC" > "$TMP_DIR/frontend.mini.manifest"
grep -q 'src/index.tsx' "$TMP_DIR/frontend.mini.manifest" || fail "frontend collector smoke broken"
grep -q '/web/package.json' "$TMP_DIR/frontend.mini.manifest" || fail "package.json companion missing"
if grep -q 'vite.config.ts' "$TMP_DIR/frontend.mini.manifest"; then fail "fe root config leaked into manifest"; fi

# ============ 跨采集器可达性交叉核对（与 resolver 同口径：先剥各自项目前缀再匹配）============
perl -MJSON::PP -e '
  use strict; use warnings;
  # 参数形如 MAP ROOT1 MANIFEST1 ROOT2 MANIFEST2 ...：每个 manifest 配自己的
  # 项目根（三份 fixture 根目录互不相同，统一按各自根剥前缀成仓库相对路径）。
  my ($map,@pairs)=@ARGV;
  die "pairs must be ROOT MANIFEST alternating\n" if @pairs % 2;
  my $doc;
  { local $/; open my $mf,"<",$map or die "read map: $!"; $doc=decode_json(<$mf>); close $mf; }
  # 注意：上面的大文件 slurp 必须用裸块限定作用域，否则后续逐行读 manifest 会塌缩成单行。

  sub expand_braces {
    my ($p)=@_;
    if ($p =~ /^([^{}]*)\{([^{}]+)\}(.*)$/s) {
      my @out; for my $alt (split /,/,$2) { push @out,@{expand_braces("$1$alt$3")}; }
      return \@out;
    }
    return [$p];
  }
  sub compile_ft_globs {
    my ($p)=@_; my @rx;
    for my $alt (@{expand_braces($p)}) {
      my $q=quotemeta($alt);
      $q =~ s{\\\*\\\*\\/}{(?:[^\/]+\/)*}g;
      $q =~ s{\\\*\\\*}{.*}g;
      $q =~ s{\\\*}{[^\/]*}g;
      $q =~ s{\\\?}{[^\/]}g;
      push @rx, qr/^$q$/i;
    }
    return \@rx;
  }

  my %emitted_by_slug; my %compiled;
  for my $e (@{$doc->{patterns}}) {
    next if defined $e->{enabled} && !$e->{enabled};
    $compiled{$e->{pattern}} = { res => compile_ft_globs($e->{pattern}), checklist => $e->{checklist} };
  }
  while (@pairs >= 2) {
    my $mroot=shift @pairs;
    my $mfile=shift @pairs;
    next unless -s $mfile;
    open my $fh,"<",$mfile or die "read $mfile: $!"; chomp(my @lines=<$fh>); close $fh;
    my %uniq; for my $line (@lines) { next unless length $line; $uniq{$line}=1; }
    LINE: for my $line (sort keys %uniq) {
      # 与 resolver 口径一致：先按各自项目前缀归一为仓库相对路径再参与模式匹配。
      (my $rel=$line) =~ s{^\Q$mroot\E\/}{};
      next LINE if $rel =~ m!^/!;
      for my $entry (values %compiled) {
        for my $r (@{$entry->{res}}) {
          if ($rel =~ $r) { push @{$emitted_by_slug{$entry->{checklist}}}, $rel; next LINE; }
        }
      }
    }
  }
  my %seen_slugs;
  for my $e (@{$doc->{patterns}}) { $seen_slugs{$e->{checklist}}=1 unless defined $e->{enabled} && !$e->{enabled}; }
  for my $slug (sort keys %seen_slugs) {
    unless ($emitted_by_slug{$slug}) {
      die "UNREACHABLE checklist [$slug]: no map pattern matches any file emitted by any collector"
        . " (hit slugs: ".join(",", sort keys %emitted_by_slug).")\n";
    }
  }
  print "reachability ok for slugs: ", join(",", sort keys %emitted_by_slug), "\n";
' "$MAP" \
  "$(cd "$REPO" && pwd -P)"   "$TMP_DIR/java.manifest" \
  "$(cd "$PYSRC" && pwd -P)"  "$TMP_DIR/python.mini.manifest" \
  "$(cd "$FESRC" && pwd -P)"  "$TMP_DIR/frontend.mini.manifest"

# ============ resolver 端到端 mini 项目 ============
APP="$TMP_DIR/app"
mkdir -p "$APP/src/main/java/demo" "$APP/src/main/resources" "$APP/.cc-code-reviewer"
printf 'class Demo {}\n' > "$APP/src/main/java/demo/Demo.java"
printf '<project/>' > "$APP/pom.xml"
printf 'a: 1\n' > "$APP/src/main/resources/application.yml"
printf 'b: 2\n' > "$APP/src/main/resources/application-prod.properties"
printf '<mapper ns="u"/>' > "$APP/src/main/resources/UserMapper.xml"
printf '{"openapi":"3.0"}\n' > "$APP/src/main/resources/openapi.yaml"
MANIFEST="$TMP_DIR/manifest.txt"
printf '%s\n' \
  "$APP/src/main/java/demo/Demo.java" \
  "$APP/pom.xml" \
  "$APP/src/main/resources/application.yml" \
  "$APP/src/main/resources/application-prod.properties" \
  "$APP/src/main/resources/UserMapper.xml" \
  "$APP/src/main/resources/openapi.yaml" > "$MANIFEST"

# ---- [5] 分组正确 + content 内嵌与磁盘一致；[6] 遗留键并行输出 ----
OUT="$(bash "$RESOLVER" "$APP" "$MANIFEST" "$TMP_DIR/rules.json")"
grep -q '^REVIEW_RULES_RESOLVED_PATH=' <<< "$OUT" || fail "stdout contract lost"
grep -q '^REVIEW_RULES_COUNT=0$' <<< "$OUT" || fail "rule count contract lost"
perl -MJSON::PP -MEncode -e '
  local $/; my $d=decode_json(<STDIN>);
  my $g=$d->{filetype_checklists} or die "missing filetype_checklists\n";
  my %by; $by{$_->{checklist}}=$_ for @$g;
  die "maven-pom group missing\n" unless $by{"maven-pom"};
  die "spring-config group missing\n" unless $by{"spring-config"};
  die "mapper-xml group missing\n" unless $by{"mapper-xml"};
  die "openapi-spec group missing\n" unless $by{"openapi-spec"};
  die "maven-pom files wrong\n" unless join("|",@{$by{"maven-pom"}{files}}) eq "pom.xml";
  die "spring files wrong\n" unless join("|",@{$by{"spring-config"}{files}}) eq "src/main/resources/application-prod.properties|src/main/resources/application.yml";
  die "mapper files wrong\n" unless join("|",@{$by{"mapper-xml"}{files}}) eq "src/main/resources/UserMapper.xml";
  die "doc path not absolute\n" unless $by{"maven-pom"}{doc} =~ m!^/.*/references/review-checklists/maven-pom\.md$!;
  for my $k (keys %by) {
    my $bytes=Encode::encode("UTF-8", $by{$k}{content}//"");
    die "content empty for $k\n" if length($bytes) == 0;
    die "content oversize for $k (".length($bytes)." bytes)\n" if length($bytes) > 8192;
    open my $cf,"<",$by{$k}{doc} or die; binmode $cf; local $/; my $raw=<$cf>; close $cf;
    die "content mismatch vs disk for $k\n" unless $raw eq $bytes;
  }
  for my $grp (@$g) { die "java source leaked into checklist group\n" if grep { $_ =~ m!Demo\.java! } @{$grp->{files}}; }
' < "$TMP_DIR/rules.json"
jq -e '.schema_version == 1 and .rule_count == 0 and .rules_path == "" and (.files | length) == 6' "$TMP_DIR/rules.json" >/dev/null || fail "legacy keys altered (no rules)"
# 逐文件遗留键集不变（path/absolute_path/rules），rules 数组元素键集不变。
perl -MJSON::PP -e '
  local $/; my $d=decode_json(<STDIN>);
  for my $f (@{$d->{files}}) {
    my %keys = map { $_ => 1 } keys %$f;
    die "per-file keys changed\n" unless join("|", sort keys %keys) eq "absolute_path|path|rules";
    for my $r (@{$f->{rules}}) {
      my %rk = map { $_ => 1 } keys %$r;
      die "per-rule keys changed\n" unless join("|", sort keys %rk) eq "instruction|merge_language_rule|name";
    }
  }
' < "$TMP_DIR/rules.json"

# review-input 模式：selected=false 的命中文件不得进入分组。
cat > "$TMP_DIR/scope-input.json" <<'JSON'
{"schema_version":1,"items":[
  {"path":"src/main/resources/application.yml","selected":true,"fingerprint":"f"},
  {"path":"src/main/resources/UserMapper.xml","selected":false,"exclude_reason":"out-of-scope"}
]}
JSON
bash "$RESOLVER" "$APP" "$TMP_DIR/scope-input.json" "$TMP_DIR/rules-scope.json" "$APP/.cc-code-reviewer/review-rules.yml" review-input >/dev/null
perl -MJSON::PP -e '
  local $/; my $d=decode_json(<STDIN>);
  die "review-input mode must honor selected=true only\n"
    if grep { $_->{checklist} eq "mapper-xml" } @{$d->{filetype_checklists}};
  my @spring=grep { $_->{checklist} eq "spring-config" } @{$d->{filetype_checklists}};
  die "selected yml must stay mapped\n" unless @spring == 1;
' < "$TMP_DIR/rules-scope.json"

# ---- [3] first-match-wins ----
cat > "$TMP_DIR/map-first.json" <<'JSON'
{"schema_version":1,"match":"first","patterns":[
  {"pattern":"**/*.yml","checklist":"spring-config","enabled":true},
  {"pattern":"**/application.yml","checklist":"logging-config","enabled":true},
  {"pattern":"**/*disabled*","checklist":"openapi-spec","enabled":false},
  {"pattern":"**/*.json","checklist":"dockerfile","enabled":true}
]}
JSON
CC_CODE_REVIEWER_FILETYPE_MAP_PATH="$TMP_DIR/map-first.json" \
  bash "$RESOLVER" "$APP" "$MANIFEST" "$TMP_DIR/rules-first.json" >/dev/null
perl -MJSON::PP -e '
  local $/; my $d=decode_json(<STDIN>); my $g=$d->{filetype_checklists};
  die "expected exactly one group (first-match wins, disabled skipped)\n" unless @$g == 1;
  die "winner must be the first pattern\n" unless $g->[0]{checklist} eq "spring-config";
  die "loser patterns must be reported\n" if grep { $_->{checklist} ne "spring-config" } @$g;
' < "$TMP_DIR/rules-first.json"

# ---- [8] 零命中字节稳定（字段缺省而非空数组）----
printf 'placeholder\n' > "$APP/plain.txt"
printf '%s\n' "$APP/plain.txt" > "$TMP_DIR/nohit-manifest.txt"
bash "$RESOLVER" "$APP" "$TMP_DIR/nohit-manifest.txt" "$TMP_DIR/rules-nohit.json" >/dev/null
jq -e 'has("filetype_checklists") | not' "$TMP_DIR/rules-nohit.json" >/dev/null || fail "no-hit run must omit filetype_checklists"
keys_now="$(jq -c 'keys | sort' "$TMP_DIR/rules-nohit.json")"
test "$keys_now" = '["files","rule_count","rules_path","schema_version"]' || fail "unexpected top-level keys on no-hit run: $keys_now"
test "$(cat "$TMP_DIR/rules-nohit.json")" = '{"schema_version":1,"rules_path":"","rule_count":0,"files":[]}' || fail "legacy compact bytes changed"

# 空项目路径兜底口径：缺失 PROJECT_DIR 必须以非零退出（不产出含新键的产物）。
MISSING="$TMP_DIR/not-a-project"
if MOUT="$(bash "$RESOLVER" "$MISSING" "$TMP_DIR/nohit-manifest.txt" "$TMP_DIR/rules-missing.json" 2>/dev/null)"; then
  fail "missing project must exit non-zero"
fi

# map 缺失覆盖 → 字段省略、exit 0。
CC_CODE_REVIEWER_FILETYPE_MAP_PATH="$TMP_DIR/absent-map.json" \
  bash "$RESOLVER" "$APP" "$MANIFEST" "$TMP_DIR/rules-absent.json" >/dev/null
jq -e 'has("filetype_checklists") | not' "$TMP_DIR/rules-absent.json" >/dev/null || fail "missing override map must omit field"

# 损坏 map → 字段省略且 exit 0。
printf '{broken json' > "$TMP_DIR/map-broken.json"
if ! OUT="$(CC_CODE_REVIEWER_FILETYPE_MAP_PATH="$TMP_DIR/map-broken.json" \
  bash "$RESOLVER" "$APP" "$MANIFEST" "$TMP_DIR/rules-broken.json")"; then
  fail "broken map must still exit 0"
fi
jq -e 'has("filetype_checklists") | not' "$TMP_DIR/rules-broken.json" >/dev/null || fail "broken map must omit filetype_checklists"
cmp -s "$TMP_DIR/rules-broken.json" "$TMP_DIR/rules-absent.json" || fail "broken vs absent map outputs must match"

# ---- [6+确定性] 同一输入连跑两次输出逐字节一致 ----
bash "$RESOLVER" "$APP" "$MANIFEST" "$TMP_DIR/rules-run1.json" >/dev/null
bash "$RESOLVER" "$APP" "$MANIFEST" "$TMP_DIR/rules-run2.json" >/dev/null
cmp -s "$TMP_DIR/rules-run1.json" "$TMP_DIR/rules-run2.json" || fail "resolver output must be deterministic across runs"

# 空 manifest → 不产出该字段。
: > "$TMP_DIR/empty-manifest.txt"
bash "$RESOLVER" "$APP" "$TMP_DIR/empty-manifest.txt" "$TMP_DIR/rules-empty.json" >/dev/null
jq -e '((has("filetype_checklists")) | not) and ((.files | length) == 0)' "$TMP_DIR/rules-empty.json" >/dev/null || fail "empty manifest must omit field with zero files"

# ---- [4] 大小写不敏感（纯 glob 单元，不依赖文件系统大小写行为）----
perl -MJSON::PP -e '
  my ($map)=@ARGV;
  local $/; open my $fh,"<",$map or die; my $m=decode_json(<$fh>); close $fh;
  sub expand_braces { my ($p)=@_; if ($p =~ /^([^{}]*)\{([^{}]+)\}(.*)$/s) { my @out; for my $alt (split /,/,$2) { push @out,@{expand_braces("$1$alt$3")}; } return \@out; } return [$p]; }
  sub compile_ft_globs {
    my ($p)=@_; my @rx;
    for my $alt (@{expand_braces($p)}) {
      my $q=quotemeta($alt);
      $q =~ s{\\\*\\\*\\/}{(?:[^\/]+\/)*}g;
      $q =~ s{\\\*\\\*}{.*}g;
      $q =~ s{\\\*}{[^\/]*}g;
      $q =~ s{\\\?}{[^\/]}g;
      push @rx, qr/^$q$/i;
    }
    return \@rx;
  }
  my %comp;
  for my $e (@{$m->{patterns}}) { next if defined $e->{enabled} && !$e->{enabled}; push @{$comp{$e->{checklist}}}, @{compile_ft_globs($e->{pattern})}; }
  my $hit = sub { my ($cls,$path)=@_; for my $r (@{$comp{$cls}}) { return 1 if $path =~ $r; } return 0; };
  $hit->("maven-pom","POM.XML")           or die "POM.XML must hit maven-pom\n";
  $hit->("maven-pom","app/POM.xml")       or die "mixed case nested pom must hit\n";
  $hit->("mapper-xml","resources/USERMAPPER.XML") or die "uppercase mapper must hit\n";
  $hit->("spring-config","a/APPLICATION.PROPERTIES") or die "uppercase properties must hit\n";
  $hit->("maven-pom","x/pomx.xml")        and die "near-miss must not hit\n";
' "$MAP"

# ---- [7] 伴随扩展：cap 截断 + stderr 说明 + 两次运行确定 ----
CAPREPO="$TMP_DIR/caprepo"
mkdir -p "$CAPREPO/mod/src/main/java/x" "$CAPREPO/mod/src/main/resources"
printf 'class X {}\n' > "$CAPREPO/mod/src/main/java/x/X.java"
printf '<project/>' > "$CAPREPO/pom.xml"
for i in $(seq 1 300); do printf "k%d: v\n" "$i" > "$CAPREPO/mod/src/main/resources/application$i.yml"; done

CAP_ERR="$TMP_DIR/cap.stderr"
bash "$JAVA_COLLECT" "$CAPREPO" > "$TMP_DIR/cap.run1.manifest" 2> "$CAP_ERR"
CAP_COUNT="$(grep -c . "$TMP_DIR/cap.run1.manifest")"
test "$CAP_COUNT" -le 201 || fail "companion cap exceeded: $CAP_COUNT lines (java source + <=200 companions)"
grep -q '^COMPANION_FILES_ADDED=200' "$CAP_ERR" || fail "cap log line missing: $(cat "$CAP_ERR")"
grep -q '已达上限 200' "$CAP_ERR" || fail "cap truncation note missing"

bash "$JAVA_COLLECT" "$CAPREPO" > "$TMP_DIR/cap.run2.manifest" 2>/dev/null
cmp -s "$TMP_DIR/cap.run1.manifest" "$TMP_DIR/cap.run2.manifest" || fail "collector output must be deterministic across runs"

echo "PASS: core filetype-rule-map"
