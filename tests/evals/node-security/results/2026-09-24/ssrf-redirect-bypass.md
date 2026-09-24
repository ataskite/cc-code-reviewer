# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24 10:13:35 CST
- 审查类型：存量全量
- 审查范围：项目全部生产源码（server.js）+ 构建描述符（package.json），文件覆盖率 2/2（100%）
- 审查模式：security（frontend 通道；冻结 security_profile = node-api, node-worker）
- 检测到的技术栈：Node.js（Express 4 + axios，DNS 校验），无框架前端代码
- 语义增强：未注入 LSP，本轮为静态逐文件精读（全量源码仅 1 个 JS 文件，精读等价覆盖）
- 冻结适用控制：/tmp/cc-eval-20260923/artifacts/ssrf-redirect-bypass.controls.json（适用 11 条，排除 1 条，review_input_sha256=1010d3f4…）
- Node 攻击面索引：/tmp/cc-eval-20260923/artifacts/ssrf-redirect-bypass.surface.json（仅导航候选：1 路由、1 出站 HTTP 客户端、1 个 req.body 源）
- 项目 ignore 状态：未配置
- 网络访问：无（全离线，仅依据本地文件）

## 📊 执行摘要

- **整体结论**：单一 webhook 通知服务，入口即出站请求的完整 SSRF 攻击链静态闭合——初始校验只作用于第一跳，`maxRedirects: 5` 自动跟随重定向且对后续每一跳不做任何复验，云元数据端点与内网服务均可经 302/307 触达；配套的 host 校验本身也是不完备前缀黑名单。
- **最高风险点**：P0-1（SSRF 重定向绕过——攻击者可控 webhookUrl 经公网跳板 302/307 转向 `169.254.169.254` 云元数据或内网 `10.x` 服务，初始 https + host 校验全部被绕过）。
- **安全性：差 / 性能稳定性：差（可被单请求打崩）/ 可维护性：一般（体量极小）/ 技术债务：低**。

| 级别 | 数量 |
|---|---|
| P0 严重 | 1 |
| P1 重要 | 2 |
| P2 一般 | 0 |
| P3 建议 | 0 |
| 待确认 | 1 |
| **正式问题总计（P0-P3）** | **3** |

- 项目 ignore 命中统计：未配置，无过滤。

## 🔴 P0 严重问题

### P0-1 | [维度6-安全] webhook SSRF：初始 scheme/host 校验不覆盖重定向每一跳，公网跳板 302/307 即可触达云元数据与内网服务

**位置**：tests/evals/node-security/ssrf/redirect-bypass/server.js:24（校验缺口形成于 19-22 与 24-25 的组合；同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：用户可控的 `webhookUrl` 只在首次外发前校验协议与主机（server.js:19-22），而出站客户端配置 `maxRedirects: 5` 自动跟随最多 5 跳重定向（server.js:25），重定向目标的协议、主机、IP 在后续每一跳均不重新校验——`redirect_revalidation` 控制缺失，SSRF 校验被重定向整体绕过。

**证据**（Source → Propagation → Sink → Missing Control 全链闭合）：

```js
// server.js
 2  // 首次请求前校验目标 host 是否为公网地址；为兼容部分 webhook 供应商的
 3  // 跳转登录流程，出站客户端允许跟随重定向。               // ← 设计意图即“允许重定向”，但校验只做了一次
16  app.post('/api/notify', async (req, res) => {            // ← Entry：唯一路由，匿名可达（见待确认-1）
17    const { webhookUrl } = req.body;                       // ← Source：URL 完全客户端可控（req.body）
19    const initial = new URL(webhookUrl);                   // ← Propagation：仅解析“初始” URL
20    if (initial.protocol !== 'https:' || !(await isPublicHost(initial.hostname))) {
21      return res.status(400).json({ error: 'webhook_host_not_allowed' });
22    }                                                      // ← 校验到此为止，只约束第一跳
24    const resp = await axios.post(webhookUrl, { event: 'order.created' }, {
25      maxRedirects: 5,                                     // ← Sink：自动跟随最多 5 跳，后续跳无 scheme/host/IP 复验
26      headers: { 'content-type': 'application/json' },
27    });
29    res.json({ delivered: true, status: resp.status });    // ← 最终跳状态码回显：内网探测 oracle
```

**安全规则 ID**：CCR-NODE-SSRF-001

**标准映射**：OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918

**检测方式**：taint

**证据状态**：静态已证实——入口（路由注册 + `app.listen(3000)`，server.js:16/32）、Source（req.body.webhookUrl，server.js:17）、传播（校验仅作用于 `initial`，server.js:19-22）、Sink（`axios.post` + `maxRedirects: 5`，server.js:24-25）、缺失控制（全文件无任何每跳复验钩子/拦截器）均在仓库内闭合；axios 的 `maxRedirects > 0` 在 Node 端由 follow-redirects 实现自动跨协议（https→http）跟随，属确定性库语义。

**主体/资源/决策链**：不适用（非授权/越权类；主体为任意调用方，资源为服务端出站网络位置）。

**未授权路径与防护**：不适用（非授权/越权类）。现有防护及其限制：`initial.protocol !== 'https:'` 与 `isPublicHost`（server.js:20）仅约束第一跳——攻击路径：`{"webhookUrl":"https://attacker.example/hook"}`（公网 + https，通过全部校验）→ 攻击机返回 `302/307 Location: http://169.254.169.254/latest/meta-data/` 或 `http://10.0.5.23:8081/...` → axios 直接跟随，scheme 降级为 http、目标为链路本地/内网地址，全程零复验。302/303 会降级为 GET（读取元数据/内网 GET 接口），307/308 保持 POST（向内网写接口投递 `{"event":"order.created"}` JSON body）；最终跳 `resp.status` 回显 + 异常路径行为差异（见 P1-2）构成探测侧信道。

**影响**：服务端伪造请求可达云元数据端点（169.254.169.254，AWS/Azure/GCP 凭据与配置泄露的行业标准入口）与任意内网 `10.x` 服务；按框架「内网可达性放大定级」，不得因「仅内网」降级——内网可达性正是 SSRF 的杀伤力来源（IMA BFF SSRF 事件同型）。该服务作为可信内网身份发起请求，可绕过面向外网的边界防护；状态码 oracle 支持内网端口/服务存活探测。事故级影响、生产可达（路由注册与监听均有仓库证据）、无有效防护，必须阻断发布。

**建议**：webhook 投递场景应直接关闭重定向跟随——`maxRedirects: 0`（需要「跳转登录流程」的供应商应改为在配置阶段人工解析出最终地址再登记）；若业务确需跟随，必须改为手工循环逐跳执行完整校验后再发起下一跳。校验本身按 CCR-NODE-SSRF-001 的 `redirect_revalidation` 控制补齐：

```js
const resp = await axios.post(webhookUrl, { event: 'order.created' }, {
  maxRedirects: 0,                       // ← 每跳复验或干脆不跟随
  headers: { 'content-type': 'application/json' },
});
```

并配合：解析后 IP 走**出口白名单**（正向 allowlist，而非 `10.`/`169.254.` 前缀黑名单，见 P1-1）；校验与连接使用同一次 DNS 解析结果（IP pin，防 rebinding）。

---

## 🟠 P1 重要问题

### P1-1 | [维度6-安全] isPublicHost 为不完备前缀黑名单：回环/0.0.0.0/192.168/172.16-31/IPv6/非 169.254 元数据 IP 直接放行，且校验与连接双重 DNS 解析存在 TOCTOU

**位置**：tests/evals/node-security/ssrf/redirect-bypass/server.js:13（同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：`isPublicHost` 仅以字符串前缀排除 `10.` 与 `169.254.` 两段，既非白名单也远未覆盖私网/保留地址全集；同时该函数的 `dns.lookup` 与 axios 连接时的内部解析是两次独立解析，存在 DNS rebinding 时间窗。

**证据**：

```js
// server.js
11  async function isPublicHost(hostname) {
12    const addrs = await dns.lookup(hostname, { all: true });
13    return addrs.every((a) => !a.address.startsWith('10.') && !a.address.startsWith('169.254.'));
    // ← 仅两个前缀：'127.0.0.1'、'0.0.0.0'、'192.168.x.x'、'172.16-31.x.x' 全部通过；
    //   IPv6（'::1'、'fe80::'、'fd00::'、'::ffff:10.0.0.1' 映射形式）均不以 '10.'/'169.254.' 开头同样通过；
    //   阿里云元数据 '100.100.100.200' 亦通过。L12 与 L24 是两次独立 DNS 解析（TOCTOU/rebinding）
14  }
```

**安全规则 ID**：CCR-NODE-SSRF-001

**标准映射**：OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918

**检测方式**：taint

**证据状态**：静态已证实——黑名单判定逻辑可直接复算（`'127.0.0.1'.startsWith('10.')` 与 `.startsWith('169.254.')` 均为 false → `isPublicHost` 返回 true → 通过 server.js:20 校验直达 sink）；两次独立解析由 L12 与 axios 自身解析行为决定。

**主体/资源/决策链**：不适用（非授权/越权类）。

**未授权路径与防护**：不适用（非授权/越权类）。现有防护及其限制：唯一防护即此前缀黑名单；对「https + 内网私网地址」目标（如本机/侧车容器的 https 管理面、内部 https 服务）构成直接放行，无需重定向即可触达；DNS rebinding 场景下首查返回公网地址、连接时解析为内网地址，校验同样失效（受 https 证书校验约束，实际利用面窄于 P0-1，故并入 P1 而非另立 P0）。

**影响**：与 P0-1 同属 SSRF 校验失效（同一控制 CCR-NODE-SSRF-001 的 `resolved_host_allowlist` 缺陷面），使「校验通过的 URL」集合显著大于预期公网集合，纵深防御缺失。

**建议**：改为**解析后 IP 出口白名单**（明确允许的目标域名/网段清单，deny by default）；至少完整封禁：127.0.0.0/8、0.0.0.0/8、10.0.0.0/8、172.16.0.0/12、192.168.0.0/16、169.254.0.0/16、100.64.0.0/10（含 100.100.100.200）、IPv6 `::1`/`fe80::/10`/`fc00::/7`/`::ffff:0:0/96`（先归一化 IPv4 映射地址再判定）；校验后使用同一次解析出的 IP 直接发起连接（IP pin）消除 rebinding 窗口。

---

### P1-2 | [维度6-安全] async 路由全程无错误处理：单次请求即可触发 unhandledRejection 导致进程崩溃（远程拒绝服务）

**位置**：tests/evals/node-security/ssrf/redirect-bypass/server.js:16（同类问题共 1 处，全文件唯一路由）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：唯一的路由处理器是 `async` 函数，内部两处 `await`（server.js:12 的 `dns.lookup` 与 server.js:24 的 `axios.post`）均无 try/catch，全文件也没有任何 Express 错误处理中间件；Express 4 不捕获 async 处理器的 rejection，任一 reject 都会成为 unhandledRejection，Node 15+ 默认策略下直接终止进程。

**证据**：

```js
// server.js
16  app.post('/api/notify', async (req, res) => {   // ← async 处理器；全文件无 try/catch、无 app.use(err) 错误中间件
20    if (initial.protocol !== 'https:' || !(await isPublicHost(initial.hostname))) {
        // ← 路径一：dns.lookup 对不存在主机 reject（ENOTFOUND）→ 未处理 rejection
24    const resp = await axios.post(webhookUrl, ...)   // ← 路径二：目标不可达/TLS 失败/任何 4xx-5xx（axios 默认 validateStatus 即 throw）
```

**证据状态**：静态已证实——`package.json` 锁定 `express ^4.18.0`（Express 4 async 语义确定）、代码中零错误处理结构；进程是否实际退出取决于部署的 `--unhandled-rejections` 运行配置（默认 throw），该项运行配置证据缺失故不定 P0。

**主体/资源/决策链**：不适用（可用性问题，无主体—资源关系）。

**未授权路径与防护**：不适用。最短路径：任意调用方 POST 一个域名无法解析或返回 ≥400 的 `webhookUrl`（正常 webhook 供应商偶发 5xx 同样触发）→ 进程崩溃/请求悬挂；与待确认-1（无认证）叠加即匿名单请求 DoS。

**影响**：单线程运行时上一次未捕获拒绝等于全服务拒绝服务；通知类服务的常态错误（下游 5xx、DNS 抖动）即可造成崩溃循环。

**建议**：路由内 try/catch 或添加统一错误中间件（Express 5 或 express-async-errors 亦可），对出站失败返回受控的 5xx（不泄露内部主机/堆栈）；同时为 `axios.post` 设置 `timeout` 与连接池上限，避免慢目标长时间占用 handler 与 socket。

---

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] /api/notify 无任何认证/鉴权且监听全部接口，是否受网关/网络边界保护依赖部署证据

**位置**：tests/evals/node-security/ssrf/redirect-bypass/server.js:9（同类问题共 1 处）

**置信度**：低 | **所属维度**：维度6-安全

**依据**：

```js
// server.js
 8  const app = express();
 9  app.use(express.json());        // ← 唯一中间件：仅 body 解析，无任何认证/鉴权/限流
16  app.post('/api/notify', ...)    // ← 唯一路由直接暴露写效果（触发服务端外发请求）
32  app.listen(3000);               // ← 未指定 host，默认监听 0.0.0.0:3000
```

**待确认原因**：代码内可闭合「无认证」事实，但该服务是否部署于内网网关/NetworkPolicy 之后（生产可达性与暴露面）无法从仓库证据判断；若直接暴露，匿名调用方即可任意驱动 P0-1/P1-1 的 SSRF 链与 P1-2 的崩溃链，攻击面显著放大。

**建议的验证方式**：核验部署清单（Ingress/Service/NetworkPolicy/网关鉴权配置）；从集群外或非信任网络向 `/api/notify` 发送未携带任何凭据的请求，预期应被网关 401/403 拒绝——若直达即证实匿名可达。若确认仅内网可达，也应对该端点补充服务间认证（mTLS/内部 token），因为它会代表服务身份向任意方向发起外发请求。

---

## 🟡 P2 一般问题

本次未发现满足 P2 定级的问题。

## 🔵 P3 建议

本次未发现满足 P3 定级的问题。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | req.body 仅解构 webhookUrl（server.js:17），全文件无身份/租户上下文构造点 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 未使用任何 session（无 express-session/cookie-session），无 session 写入点 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | finding_confirmed | 见 P0-1 / P1-1：req.body.webhookUrl → axios.post，maxRedirects:5 无每跳复验；host 前缀黑名单不完备 + 双重解析 TOCTOU |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 无 child_process 引用（server.js 仅 require express/axios/dns） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/res.sendFile/res.download 路径拼接面 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无递归 merge/extend/defaults 消化 req.body（仅 express.json 标准解析） |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 等 NoSQL 客户端 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 仅 JSON 语义（express.json），无 node-serialize/yaml.load 等危险反序列化 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象 ID 定位的 DB/对象读写；唯一敏感效果即 SSRF 外发链（已入 P0-1） |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无角色体系与管理/配置/导出类动作；端点匿名可达的部署边界见待确认-1 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 Cookie 会话（未使用任何 session 中间件），CSRF 控制前提在代码内可闭合为不成立 |

排除说明（不适用 E=1 的构成）：CCR-NODE-BFFHEADER-001（客户端请求头批量透传到上游服务）被冻结 resolver 以激活 profile（node-api、node-worker，未含 node-bff）排除；经语义复核，出站请求头为显式逐键构造（server.js:26 仅 `content-type`），未透传任何客户端头，无语义提升（finding_confirmed）必要。

## 🔐 授权面覆盖（仅 Security 模式强制）

授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0，且 1 = 0 + 0 + 1 + 0。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| POST /api/notify（server.js:16） | 匿名：无认证中间件，代码内无任何身份来源 | 触发服务端外发 webhook（网络位置效果） | webhookUrl（req.body，客户端可控，无对象/租户标识） | 无（deny-by-default 不存在；是否由网关兜底依赖部署证据） | axios.post 外发请求（server.js:24） | 外部证据缺失（→ 待确认-1） | 无：单一路由，无批量/导出/下载/异步任务/消息/缓存/旧版本入口（全文件精读确认） |

差分反例核验：同角色异对象、低权限高功能、跨租户/组织、对象属性越权、批量/嵌套资源——均**不适用**（代码内不存在对象存储、角色、租户或字段模型，无差分维度可构造）；替代执行路径——已检查，唯一路由且无子路径/变体入口。代码内可闭合的敏感效果缺口（SSRF 链）已作为 P0-1 正式问题输出，不重复计入台账计数。

未闭合入口与外部依赖：服务暴露边界（网关/NetworkPolicy/服务间认证）——见待确认-1；运行时 `--unhandled-rejections` 配置——影响 P1-2 的崩溃可达性判定。

## 🔍 覆盖限制与未审查范围

- 已重点检查：唯一入口 `/api/notify` 的完整 Source→Sink 链（req.body → URL 解析校验 → DNS 校验 → axios 外发/重定向语义）、冻结 controls 全部 11 条适用控制、授权面差分反例、依赖清单（package.json 仅 express/axios，无 lockfile，依赖漏洞无确定性结论依据）。
- 未充分覆盖：运行时部署形态（网关、网络策略、Node 启动参数）、上游 webhook 供应商实际行为——均已归入待确认项并给出最小验证方式。
- 限制说明：静态审查，未做任何网络访问；无 lockfile，依赖风险不形成确定性结论。

## 📝 总结

- 一句话架构判断：一个把客户端输入直接变成服务端出站请求的 webhook 通知服务，防护只有一次性的首跳前缀黑名单校验。
- 本模式核心判断：SSRF 证据链完整闭合（CCR-NODE-SSRF-001 finding_confirmed），根因是「校验一次、跟随多跳」的语义错配，叠加不完备黑名单与零错误处理。
- 关键行动项：① `maxRedirects: 0` 关闭重定向跟随（或逐跳全量复验）；② 校验改为解析后 IP 出口白名单 + 同次解析 pin；③ 补统一错误处理与超时，并核验端点的部署暴露边界。

**审查人**: cc-code-reviewer Agent（security 单 Agent）
**报告版本**: 5.7
**审查模式**: security
