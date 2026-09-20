#!/bin/bash
set -euo pipefail

# BFF server-root 发现契约（v1.7.0）：
# 老式 BFF 脚手架的服务端代码位于包根与一级子目录，src-only 口径会静默漏掉
# 中继/鉴权/会话等漏洞主体文件。server 层按信号门控发现（入口信号 OR 强服务端
# 信号），根级散文件过配置 basename 黑名单，一级非噪声目录全深度收弱模块信号
# 文件；.ts 不入 server 层；上限 CC_CODE_REVIEWER_SERVER_ROOT_LIMIT（默认 200，
# 0=禁用）；并入数以 stderr SERVER_ROOTS_ADDED=N 披露。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COLLECTOR="$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-server-root.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---- fixture 1：bot 形态（入口信号 + thinkJS 大写 RequestMapping 强信号）----
D1="$TMP_DIR/bot-like"
mkdir -p "$D1/src/views" "$D1/application/controllers" "$D1/tpl/x" "$D1/static/s" "$D1/sdk/y" "$D1/vite/z"
cat > "$D1/package.json" <<'JSON'
{
  "name": "bot-like",
  "main": "app.js",
  "dependencies": { "vue": "^2.6.10" }
}
JSON
echo "new Vue({})" > "$D1/src/views/Home.vue"
# 根 app.js 无强信号（只 require 私有模块）——必须靠 main 入口信号合格
printf "require('./application/boot');\nconsole.log('no express here');\n" > "$D1/app.js"
# thinkJS 大写变体路由注解：强信号（覆盖 this.RequestMapping 形态）
cat > "$D1/application/controllers/ApiController.js" <<'JS'
module.exports = class ApiController {
  constructor() { this.RequestMapping('/api'); }
};
JS
# 弱信号 server 文件（含密钥类内容，security 审查目标）
printf "module.exports.request = function (url, data, req, setHeader) {\n  const token = data.LOCAL_TOKEN ? data.LOCAL_TOKEN : req.session['authorization'];\n};\n" > "$D1/application/request.js"
# 噪声与黑名单：不得入清单
printf "const express = require('express');\nmodule.exports = express();\n" > "$D1/dev.webpack.js"
printf "module.exports = {};\n" > "$D1/webpack.config.js"
printf "module.exports = {};\n" > "$D1/postcss.config.js"
printf "module.exports = {};\n" > "$D1/tpl/x/t.js"
printf "module.exports = {};\n" > "$D1/static/s/s.js"
printf "module.exports = {};\n" > "$D1/sdk/y/sdk.js"
printf "module.exports = {};\n" > "$D1/vite/z/v.js"

OUT1="$(bash "$COLLECTOR" "$D1" 2>"$TMP_DIR/err1.txt")"
printf '%s\n' "$OUT1" | grep -q '/bot-like/app\.js$'
printf '%s\n' "$OUT1" | grep -q '/bot-like/application/controllers/ApiController\.js$'
printf '%s\n' "$OUT1" | grep -q '/bot-like/application/request\.js$'
! printf '%s\n' "$OUT1" | grep -q 'dev\.webpack\.js'
! printf '%s\n' "$OUT1" | grep -q 'webpack\.config\.js'
! printf '%s\n' "$OUT1" | grep -q 'postcss\.config\.js'
! printf '%s\n' "$OUT1" | grep -q '/tpl/'
! printf '%s\n' "$OUT1" | grep -q '/static/'
! printf '%s\n' "$OUT1" | grep -q '/sdk/'
! printf '%s\n' "$OUT1" | grep -q '/vite/'
grep -q 'SERVER_ROOTS_ADDED=' "$TMP_DIR/err1.txt"

# ---- fixture 2：im-chat 形态（scripts.dev 的 node 入口 + 根 app.js express 强信号）----
D2="$TMP_DIR/im-like"
mkdir -p "$D2/src/components" "$D2/controllers/src" "$D2/middleware/redis" "$D2/mock/m"
cat > "$D2/package.json" <<'JSON'
{
  "name": "im-like",
  "scripts": { "dev": "cross-env NODE_PROFILE=stest node app.js" },
  "dependencies": { "vue": "^2.6.10", "express": "^4.16.0" }
}
JSON
echo "<template><div/></template>" > "$D2/src/components/C.vue"
printf "const express = require('express');\nexpress().listen(3000);\n" > "$D2/app.js"
# 嵌套 server 目录（controllers/src/ 全深度收集）
cat > "$D2/controllers/src/index.js" <<'JS'
module.exports = function (router) {
  router.post('/updateRedis', function (req, res) {
    for (let x in req.body) { req.session[x] = req.body[x]; }
  });
};
JS
printf "module.exports = {};\n" > "$D2/middleware/redis/index.js"
printf "module.exports = {};\n" > "$D2/mock/m/mock.js"

OUT2="$(bash "$COLLECTOR" "$D2" 2>/dev/null)"
printf '%s\n' "$OUT2" | grep -q '/im-like/app\.js$'
printf '%s\n' "$OUT2" | grep -q '/im-like/controllers/src/index\.js$'
printf '%s\n' "$OUT2" | grep -q '/im-like/middleware/redis/index\.js$'
! printf '%s\n' "$OUT2" | grep -q '/mock/'

# ---- fixture 3：help/crm 形态（入口无扩展名 + 关键弱信号文件，验收核心）----
D3="$TMP_DIR/help-like"
mkdir -p "$D3/src/js" "$D3/bin" "$D3/common" "$D3/controllers"
cat > "$D3/package.json" <<'JSON'
{
  "name": "help-like",
  "scripts": { "start": "cross-env NODE_ENV=dev node ./bin/www" },
  "dependencies": { "vue": "^2.6.10" }
}
JSON
echo "var compiled = 1;" > "$D3/src/js/a.js"
# ./bin/www 无扩展名：入口回退 bin/www.js 命中
printf "module.exports = {};\n" > "$D3/bin/www.js"
# common/api.js 仅弱模块信号（无 express/router）——漏洞主体文件必须被收集
cat > "$D3/common/api.js" <<'JS'
var util = require('./util');
var getOptions = function (req) {
    var headers = util.extend({ 'content-type': 'ct' }, req.headers || {});
    delete headers.host;
    return headers;
};
module.exports = { request: getOptions };
JS
printf "exports.MD5 = function (s) { return s; };\n" > "$D3/common/util.js"
cat > "$D3/controllers/common.js" <<'JS'
var router = { get: function () {} };
router.get('/generate', function (req, res) { res.send('md5'); });
exports.router = router;
JS

OUT3="$(bash "$COLLECTOR" "$D3" 2>/dev/null)"
printf '%s\n' "$OUT3" | grep -q '/help-like/bin/www\.js$'
printf '%s\n' "$OUT3" | grep -q '/help-like/common/api\.js$'
printf '%s\n' "$OUT3" | grep -q '/help-like/common/util\.js$'
printf '%s\n' "$OUT3" | grep -q '/help-like/controllers/common\.js$'

# ---- fixture 4：纯前端对照组（无入口信号 + 根级弱信号工具脚本 → 不触发 server 层）----
D4="$TMP_DIR/pure-fe"
mkdir -p "$D4/src" "$D4/tools"
cat > "$D4/package.json" <<'JSON'
{"dependencies":{"react":"^18.2.0"}}
JSON
echo 'export const A = 1;' > "$D4/src/a.ts"
printf "module.exports = function codegen() {};\n" > "$D4/tools/codegen.js"

OUT4="$(bash "$COLLECTOR" "$D4" 2>"$TMP_DIR/err4.txt")"
printf '%s\n' "$OUT4" | grep -q '/src/a\.ts$'
! printf '%s\n' "$OUT4" | grep -q 'codegen\.js'
! grep -q 'SERVER_ROOTS_ADDED' "$TMP_DIR/err4.txt"

# ---- fixture 5：上限与披露（LIMIT=3 截断 + LIMIT=0 禁用）----
D5="$TMP_DIR/limit-case"
mkdir -p "$D5/src" "$D5/svc1" "$D5/svc2" "$D5/svc3"
cat > "$D5/package.json" <<'JSON'
{
  "name": "limit-case",
  "main": "app.js",
  "dependencies": { "vue": "^2.6.10" }
}
JSON
echo "<template><div/></template>" > "$D5/src/A.vue"
printf "const express = require('express');\nexpress().listen(1);\n" > "$D5/app.js"
printf "module.exports = {};\n" > "$D5/svc1/a.js"
printf "module.exports = {};\n" > "$D5/svc2/b.js"
printf "module.exports = {};\n" > "$D5/svc3/c.js"

ERR5="$TMP_DIR/err5.txt"
bash "$COLLECTOR" "$D5" 2>"$ERR5" >/dev/null
grep -q 'SERVER_ROOTS_ADDED=4' "$ERR5"
ERR5L="$TMP_DIR/err5l.txt"
CC_CODE_REVIEWER_SERVER_ROOT_LIMIT=3 bash "$COLLECTOR" "$D5" 2>"$ERR5L" >"$TMP_DIR/out5l.txt"
grep -q 'SERVER_ROOTS_ADDED=3' "$ERR5L"
grep -q '已达上限 3' "$ERR5L"
test "$(grep -cE '/(app|svc1/a|svc2/b|svc3/c)\.js$' "$TMP_DIR/out5l.txt")" = 3
OUT5Z="$(CC_CODE_REVIEWER_SERVER_ROOT_LIMIT=0 bash "$COLLECTOR" "$D5" 2>"$TMP_DIR/err5z.txt")"
printf '%s\n' "$OUT5Z" | grep -q '/src/A\.vue$'
! printf '%s\n' "$OUT5Z" | grep -q '/app\.js$'
! grep -q 'SERVER_ROOTS_ADDED' "$TMP_DIR/err5z.txt"

echo "PASS: frontend collect-source-files server-root"
