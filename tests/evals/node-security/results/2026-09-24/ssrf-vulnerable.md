# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查范围：tests/evals/node-security/ssrf/vulnerable（生产源码 server.js 全文，package.json 作为伴随配置一并审阅）
- 审查模式：security
- 审查模型：inherit（未注入，随主会话）
- 语言 / 项目类型：frontend / Node.js（Express 4、CommonJS、Node 18+ 全局 fetch）
- 启用维度：1、4（仅配置安全）、5（仅注入/越权）、6（全深度）、9（仅敏感信息泄露）、11（仅鉴权/错误信息）
- 跳过维度：2、3、7、8、10、12
- 语义增强：未注入（纯静态文本审查，未使用 LSP 语义查询）
- Node 攻击面索引：/tmp/cc-eval-20260923/artifacts/ssrf-vulnerable.surface.json（仅导航候选：request-body server.js:9、outbound-http server.js:11，与实际审查命中一致，无偏差披露）
- 冻结适用控制：/tmp/cc-eval-20260923/artifacts/ssrf-vulnerable.controls.json（11 条适用 / 1 条排除；激活 profile：node-api、node-worker；review_input_sha256=6021ada7…）
- 项目 ignore 状态：未配置
- 文件覆盖率：1/1（100%）

## 📊 执行摘要

- 整体结论：单路由 Express 通知服务将客户端完全可控的 URL 直通服务端 fetch，且端点零认证、零校验、零异常兜底。存在 1 条证据链完全闭合的 P0 级 SSRF（CCR-NODE-SSRF-001）与 2 条 P1（认证缺失、进程级崩溃），必须阻断发布。
- 最高风险点：`POST /api/notify` 的 `req.body.webhookUrl`（server.js:9）无协议/解析后主机/重定向校验直达 `fetch`（server.js:11），服务端网络位置可被任意匿名调用方驱使探测内网与云元数据端点。
- 评分参考：安全性 1/10（P0 SSRF + 零认证）；韧性 2/10（单请求可崩进程）；可观测性 1/10（无日志、无健康检查）。
- 问题汇总表：

| 级别 | 数量 |
|---|---|
| P0 | 1 |
| P1 | 2 |
| P2 | 0 |
| P3 | 0 |
| 待确认 | 1 |

- 总计正式问题数：3（另有待确认 1 项）
- 项目 ignore 命中统计：未配置（过滤前候选 3 = 过滤后输出 3）

## 🔴 P0 严重问题

> P0 五项硬门槛：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。以下条目逐项满足。

---

### P0-1 | [维度6-安全] 未认证 SSRF：req.body.webhookUrl 无协议/主机/重定向校验直达服务端 fetch，可探测内网与云元数据

**位置**：server.js:11（证据链覆盖 server.js:6-20，同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：请求体中的 webhookUrl 未经任何协议白名单、解析后主机/IP 白名单与重定向复验，直接作为服务端外发请求目标，构成完整 SSRF。

**证据**：

```js
// server.js:1-2（设计意图：URL 应来自租户控制台配置）
// 通知服务：向租户配置的 webhook 地址投递事件。
// webhook 地址由租户在控制台自助填写，服务端按原值投递（Node 18+ 全局 fetch）。

// server.js:6-17（节选）
app.use(express.json());                          // ← 唯一中间件是 body 解析：无认证、无校验
app.post('/api/notify', async (req, res) => {     // ← 入口（server.js:20 app.listen(3000) 已注册监听）
  const { webhookUrl } = req.body;                // ← Source：目标 URL 完全客户端可控，无任何净化
  const resp = await fetch(webhookUrl, {          // ← Sink：服务端外发；无 scheme/host/IP 白名单，
    method: 'POST',                               //    fetch 默认 redirect:'follow'（最多 20 跳），
    headers: { 'content-type': 'application/json' }, //  重定向目标不复验；未设超时
    body: JSON.stringify({ event: 'order.created' }),
  });
  res.json({ delivered: resp.ok, status: resp.status }); // ← 回显上游 HTTP 状态码：内网探测 oracle
});
```

**安全规则 ID**：CCR-NODE-SSRF-001

**标准映射**：OWASP A01:2025 / API7:2023、API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918

**检测方式**：taint

**证据状态**：静态已证实——Source（server.js:9，req.body.webhookUrl）→ Propagation（无任何校验/归一化，直接传参）→ Sink（server.js:11，服务端 fetch 外发）→ Missing Control（scheme_allowlist / resolved_host_allowlist / redirect_revalidation 三项控制全部缺失）在仓库内闭合；入口注册与监听为仓库证据（server.js:8、server.js:20，package.json main=server.js）。

**主体/资源/决策链**：主体为任意匿名调用方（无认证中间件，服务端身份来源不存在）；受保护动作为"以服务端网络位置外发 HTTP（webhook 投递）"；资源与标识来源为目标 URL，完全取自 req.body（server.js:9）；授权证据/决策点不存在（server.js:5-8 之间无任何拦截层）；owner/tenant 绑定结果：无绑定——server.js:1-2 注释声明 webhook 应为"租户控制台自配"，实现未建模任何租户上下文；最终 Sink 为 `fetch(webhookUrl)`（server.js:11）。

**未授权路径与防护**：最短路径：匿名 `POST /api/notify`，body 为 `{"webhookUrl":"http://169.254.169.254/latest/meta-data/"}` → express.json 解析（server.js:6）→ 直达 fetch（server.js:11）→ 以服务端网络位置外发并回显状态码（server.js:17）。现有防护：无——无 scheme/host/IP 白名单、无重定向复验、无认证、无限流；固定载荷 `{event:'order.created'}` 与 POST 方法不构成任何阻断。

**影响**：
- 内网可达性放大定级：SSRF 攻击效果按服务端内网可达范围计——可探测内网服务、云元数据端点 169.254.169.254、链路本地/私网网段及互信内部接口；不得因"仅内网"降级。
- 状态码 oracle：响应回显 `resp.status` 与 `delivered`（server.js:17），攻击者可据此对内网主机做端口扫描与服务指纹。
- 重定向二跳：fetch 默认跟随重定向，公网可控 URL 经 302 即可跳转内网/元数据地址，即使未来仅在初始 URL 字符串上做校验也会被绕过（redirect_revalidation 缺失）。
- 与 P1-1 叠加后零前置条件：任意未认证请求即可触发。

**建议**：
1. 解析并做 scheme 白名单：`new URL(webhookUrl)`，仅允许 https（或 http+https），拒绝含 userinfo（`@`）的 URL。
2. 解析后主机校验：对 DNS 全部 A/AAAA 结果（含 IPv4-mapped IPv6 形态）校验属于出口白名单，拒绝私网/环回/链路本地网段（127/8、10/8、172.16/12、192.168/16、169.254/16、::1、fe80::/10、云元数据地址）；使用校验过的 IP 建立实际连接（防 DNS rebinding）并保留 TLS 主机名校验。
3. 关闭或复验重定向：`redirect: 'manual'`（等价 maxRedirects=0），确需跟随时每一跳重新执行 1-2 校验。
4. 回归设计意图：按 server.js:1-2 注释，webhook 地址应从租户控制台配置中服务端读取并做 host 白名单，请求体至多携带事件类型，绝不接受客户端提交的目标 URL。
5. 外发设置超时（如 `signal: AbortSignal.timeout(5000)`），响应不回显上游状态码细节。

```js
// 修复示意（骨架）
const u = new URL(webhookUrl);                       // 1) 解析
if (!['https:'].includes(u.protocol)) throw new Err('scheme');  // 2) scheme 白名单
if (u.username || u.password) throw new Err('userinfo');
const ips = await dnsResolveAll(u.hostname);         // 3) 全量解析结果校验（含 IPv4-mapped）
assertAllPublicOrAllowlisted(ips);
const resp = await fetch(fixIpUrl(u, ips), { redirect: 'manual', signal: AbortSignal.timeout(5000) }); // 4) 校验 IP 连接 + 禁自动重定向
```

**验证方案**（最小、非破坏性，仅测试环境执行）：

| 主体 | webhookUrl | 动作 | 预期 |
|---|---|---|---|
| 匿名 | https://allowlisted-webhook.example.com | POST /api/notify | 放行投递 |
| 匿名 | http://169.254.169.254/latest/meta-data/ | POST /api/notify | 拒绝（4xx，无外发） |
| 匿名 | http://10.0.0.5:8080、http://[::ffff:127.0.0.1]/ | POST /api/notify | 拒绝 |
| 匿名 | 公网 URL 302 → 169.254.169.254 | POST /api/notify | 拒绝（重定向不复发） |
| 匿名 | file:///etc/passwd、ftp://x | POST /api/notify | 拒绝（解析期报错） |

---

## 🟠 P1 重要问题

---

### P1-1 | [维度6-安全] 状态变更端点完全无认证/授权：匿名调用方即可驱动服务端外发投递

**位置**：server.js:8（同类问题共 1 处，证据覆盖 server.js:5-8、server.js:20）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：唯一的业务端点 `POST /api/notify` 没有任何认证与授权决策点，任意匿名主体可触发服务端外发投递动作。

**证据**：

```js
// server.js:5-8, 20
const app = express();
app.use(express.json());                 // ← 唯一中间件是 body 解析：无认证、无授权、无限流
app.post('/api/notify', async (req, res) => {   // ← 状态变更型业务动作，任何调用方直达
// ...
app.listen(3000);                        // ← 默认绑定 0.0.0.0:3000，监听全部网卡
```

**证据状态**：静态已证实——范围内不存在任何认证/授权逻辑，匿名主体从入口到外发 Sink 的路径在代码内闭合（入口注册与监听均为仓库证据）。部署侧若存在网关统一认证属仓库外证据，无法据此改写代码内结论，需以运行配置核实。

**主体/资源/决策链**：主体为任意匿名调用方；受保护动作为服务端外发投递；资源与标识来源为 req.body（完全客户端可控）；授权证据/决策点不存在；owner/tenant/role 绑定结果：无绑定；最终 Sink 为 fetch 外发（server.js:11）。

**未授权路径与防护**：最短路径：匿名 POST /api/notify → 直达投递动作，无任何阻断点；现有防护：无。

**影响**：
- 使 P0-1 的 SSRF 零前置条件（未认证即可驱动服务端网络位置）。
- 即使修复 SSRF（目标改由租户配置决定），匿名调用方仍可冒充任意来源触发通知投递（事件伪造、对租户 webhook 的骚扰/轰炸），且无任何日志可追责（安全事件审计基线同样缺失）。

**建议**：为该端点增加认证（API key / mTLS / 网关注入并校验的身份，配合限流与审计日志：记录调用方标识、目标 webhook 归属与结果）；若认证由网关承担，须在部署边界文档化并验证绕过路径；通知类端点建议同时做幂等键防重放。

---

### P1-2 | [维度1-正确性] async 路由未捕获 fetch 拒绝：单个畸形 webhookUrl 请求即可打崩整个进程（匿名远程 DoS）

**位置**：server.js:11（同类问题共 1 处）

**置信度**：高 | **所属维度**：维度1-正确性（安全模式启用维度；可用性影响）

**问题**：async 路由处理器内的 `await fetch(webhookUrl)` 无 try/catch，webhookUrl 非法（如非 URL 字符串、DNS 失败、网络不可达）时 Promise 拒绝无人接管，Express 4 不路由被拒绝的 Promise，Node 18+ 默认将未处理拒绝按 throw 终止进程——单个匿名请求即可造成全站拒绝服务。

**证据**：

```js
// server.js:8-18（节选）
app.post('/api/notify', async (req, res) => {   // ← async 路由：Express 4（^4.18.0）不会捕获其 Promise 拒绝
  const { webhookUrl } = req.body;
  const resp = await fetch(webhookUrl, { ... }); // ← 无 try/catch："webhookUrl":"not-a-url" 即抛 TypeError
  res.json({ delivered: resp.ok, status: resp.status });
});
// 范围内无 process.on('unhandledRejection') 兜底，也无统一错误中间件 → 进程默认崩溃退出
```

```json
// package.json:8-9
"dependencies": { "express": "^4.18.0" }   // ← Express 4 系列：无 async handler 错误路由（Express 5 才引入）
```

**证据状态**：静态已证实——handler 无异常捕获、范围无进程级兜底、依赖固定于 Express 4 语义、server.js:2 注释自证运行时为 Node 18+（未处理拒绝默认终止进程）。

**主体/资源/决策链**：不适用（非授权/越权类条目；攻击入口与 P0-1 同为未认证端点）。

**未授权路径与防护**：不适用（可用性类条目；匿名 POST 畸形 URL 即触发，无任何防护）。

**影响**：攻击者可用单个请求体 `{"webhookUrl":1}` 或不可解析字符串使服务进程崩溃退出，配合无认证与无限流即可持续打挂服务（全站 DoS）；崩溃同时中断所有在途投递。

**建议**：路由内 try/catch 并返回 4xx/5xx；补充 Express 统一错误处理中间件与 `process.on('unhandledRejection')` 兜底日志；入口对 webhookUrl 做 schema 校验（必须是 string 且先过 P0-1 的 URL 白名单校验再外发）。

---

## 🟡 P2 一般问题

本次未发现满足门槛的 P2 问题。

## 🔵 P3 建议

本次未发现满足门槛的 P3 问题。

## ⚪ 待确认项

---

### 待确认-1 | [维度6-安全] 依赖未锁定（无 lockfile），无法形成确定性依赖漏洞结论

**位置**：项目根目录（同类问题共 1 处）

**置信度**：低 | **所属维度**：维度6-安全（供应链，OWASP 2025 A03）

**依据**：

```text
tests/evals/node-security/ssrf/vulnerable/
├── package.json        # dependencies: express ^4.18.0
└── server.js           # ← 无 package-lock.json / yarn.lock / pnpm-lock.yaml
```

**待确认原因**：仓库未提交任何 lockfile，依赖解析结果不可复现；依据全局依赖风险结论规则，没有 lockfile 与可信公告时只能给待确认或扫描建议，不得凭"版本较旧"下漏洞结论。express ^4.18.0 具体落在哪个补丁版本、是否携带已知 CVE，静态无法确定。

**建议的验证方式**：在干净环境 `npm install` 生成 package-lock.json 并提交，CI 使用 `npm ci`；随后以 `npm audit` / OSV-Scanner（离线库）对锁定版本做依赖漏洞扫描并出结论。

---

## 🔍 覆盖限制与未审查范围

- 已重点检查：生产源码 server.js 全文逐行（含注释声明的业务意图）；攻击面索引命中的 request-body（server.js:9）与 outbound-http（server.js:11）均已核实；11 条冻结适用控制逐一形成结论；授权面二次扫描（单入口台账，见下节）；package.json 运行时/依赖配置。
- 未充分覆盖：部署拓扑（是否存在网关统一认证、网络出口策略）——仓库内无部署证据；租户控制台侧 webhook 配置存储与归属校验——范围外系统；动态行为（未执行任何运行时验证，全程离线静态）。
- 限制说明：fetch 默认重定向行为按 WHATWG fetch/undici 默认（follow、最多 20 跳）判定；Express 4 async 错误语义按框架文档语义判定；未使用语义查询工具（LSP 未启用），全部基于静态文本与人工传播链追踪。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 1 / 外部证据缺失 0 / 不适用 0，且 1 = 0 + 1 + 0 + 0。
- 台账（入口 × 受保护动作）：

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| POST /api/notify（server.js:8） | 无认证中间件，主体为任意匿名调用方 | 触发服务端外发 HTTP 投递 | webhookUrl 完全来自 req.body（server.js:9） | 不存在（无任何认证/授权判断） | fetch 外发 + 状态码回显（server.js:11、17） | 未绑定（由 P0-1、P1-1 承接） | 无并行入口；fetch 自动重定向构成二跳路径（并入 P0-1 缓解要求） |

- 已验证反例（六类差分）：
  1. 同角色异对象：不适用——范围内无按对象 ID 定位的资源读写（无数据存取层）。
  2. 低权限高功能：成立——无任何权限判断，匿名主体直达服务端外发动作（并入 P1-1；/api/notify 非 admin/配置/导出动作类，BFLA 控制本身记 checked_no_finding）。
  3. 跨租户/组织：成立（绑定缺失形态）——server.js:1-2 注释声明 webhook 为租户控制台自配，实现未建模任何租户上下文，URL 完全取自请求体（并入 P0-1、P1-1 证据链）。
  4. 对象属性越权：不适用——无对象序列化与字段暴露（响应仅 delivered/status 两个字段，均为本次外发结果）。
  5. 批量与嵌套资源：不适用——无批量/嵌套入口。
  6. 替代执行路径：部分成立——唯一路由即主路径；fetch 默认跟随重定向构成"第二跳"执行路径（并入 P0-1 的 redirect_revalidation 要求）；无异步任务/消息/RPC/旧版本入口。
- 未闭合入口与外部依赖：部署侧网关认证（仓库无证据，须以运行配置核实）；租户 webhook 配置存储与归属校验（控制台侧系统，范围外）。
- 结论边界：本范围不能声明"未发现越权问题"——台账存在 1 行未绑定，已由正式问题 P0-1、P1-1 承接。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025、A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3、v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 唯一路由（server.js:8-18）未构造任何身份/租户上下文；req.body 仅解构 webhookUrl 用于外发 URL（server.js:9），不进入 identity/session claims；整体认证缺失另报 P1-1（非控制条目） |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 范围内无 session 中间件与会话写入（server.js 全文仅 express.json 一个中间件，依赖仅 express） |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023、API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | finding_confirmed | 见 P0-1：req.body.webhookUrl（server.js:9）直达 fetch（server.js:11），scheme/解析后 host/重定向白名单三项控制全部缺失 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 范围内无 child_process 引用（server.js 全文无 exec/execSync/spawn） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2、v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 范围内无 fs/res.sendFile/res.download 路径操作（server.js 全文无文件路径 sink） |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 范围内无递归 merge/extend/defaults；req.body 仅解构读取单字段（server.js:9），未进入任何合并 sink |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 范围内无 MongoDB/Mongoose 等 NoSQL 客户端与查询构造 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 范围内无 node-serialize/yaml.load 等；入站仅 express.json()（JSON.parse 语义，server.js:6），出站 JSON.stringify，无函数/实例还原能力 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2、v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 范围内无按对象 ID 定位的资源读写（无数据存取层）；注释声明的"租户 webhook 配置"未在代码中建模，其绑定缺失已并入 P0-1、P1-1 证据链 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 范围内无管理/审批/配置/导出类高权限动作与角色模型；/api/notify 为业务投递动作，其无门槛匿名可达已按认证缺失另报 P1-1（非控制条目） |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2、v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 范围内无 cookie/session 认证（无 cookie-session 依赖与 session 中间件），浏览器凭据不参与认证，CSRF 攻击面不存在；根因是认证整体缺失（见 P1-1），非 CSRF 防护缺口 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 resolver 排除（profile 未启用 node-bff；激活 profile：node-api、node-worker）；复核代码：外发请求头为硬编码 content-type（server.js:13），无任何客户端头透传，无语义提升证据 |

说明：控制覆盖是覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明；`static_unsupported` 不是通过（本轮为 0）。`不适用 E = 1` 等于冻结排除控制数（1 条）减语义提升数（0）。

## ✅ 最佳实践亮点

未发现足够稳定且值得单独表扬的最佳实践亮点。

## 🎯 修复优先级

- P0 - 立即修复：P0-1（SSRF：scheme 白名单 + 解析后主机/IP 校验 + 重定向复验，并回归"租户配置服务端取 URL"的设计意图）
- P1 - 尽快修复：P1-1（端点认证 + 限流 + 审计日志）、P1-2（async 异常捕获 + 统一错误中间件 + 入口 schema 校验）
- P2 / P3 - 无
- 待确认 - 补证后关闭：待确认-1（提交 lockfile 并做依赖扫描）

## 📝 总结

- 一句话架构判断：这是一个单文件、单路由的 Express 通知服务，把"租户自配 webhook"的设计意图实现成了"客户端任意指定 URL 直通服务端 fetch"，且全程零认证、零校验、零异常兜底。
- 本次模式核心判断：security 模式下 CCR-NODE-SSRF-001 证据链闭合确认为 P0（内网可达性放大定级）；其余 10 条适用控制检查无发现；1 条控制因 profile 排除不适用；另确认认证缺失与进程崩溃两条 P1、依赖未锁定一项待确认。
- 3 个关键行动项：
  1. 落地 SSRF 三件套（scheme 白名单、解析后 IP 校验并用校验 IP 建连、redirect:'manual'），webhook 目标改为服务端按租户配置读取。
  2. 为 /api/notify 增加认证、限流与安全审计日志（调用方标识 + 目标归属 + 结果）。
  3. 补 async 错误处理与 webhookUrl schema 校验，提交 lockfile 并接入 npm ci + 依赖扫描。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
