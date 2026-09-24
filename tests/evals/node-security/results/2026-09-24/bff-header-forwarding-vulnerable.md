# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24 00:29:40 +0800
- 审查类型：存量全量（stock review）
- 审查范围：项目目录全部生产文件（server.js 正式源码 + package.json 伴随文件）
- 审查模式：security（安全专项，前端/Node 路径）
- 审查模型：inherit（未注入，会话默认档位）
- 启用维度：1 正确性、4 框架规范（仅配置安全子项）、5 状态与数据请求（仅注入/越权子项）、6 安全（全深度）、9 错误监控与可观测性（仅敏感信息泄露）、11 接口与类型契约（仅鉴权/错误信息）
- 跳过维度：2 类型安全、3 代码质量、7 性能、8 副作用与资源清理、10 测试质量、12 设计系统一致性
- 模式说明：聚焦维度 6 全深度及安全强相关交叉维度；同时执行企业级 Security 框架的静态取证流程与授权面二次扫描
- 语义增强：未注入 LSP 工具，本轮为纯静态逐文件审查 + 攻击面索引导航（surface.json 仅导航候选，非发现清单）
- 检测到的技术栈：Node.js（Express 4 + axios，CommonJS；BFF 中继形态：浏览器侧入口 → 内网 orders-svc 上游）
- 项目 ignore 状态：未配置（项目内无 `.cc-code-reviewer/ignore/issues.yml`）
- 文件覆盖率：正式源码 server.js 1/1（100%）；伴随文件 package.json 1/1；合计 2/2，无跳过文件
- 审查输入清单：本轮未注入 review-input.json（评测运行）；冻结适用控制 `/tmp/cc-eval-20260923/artifacts/bff-header-forwarding-vulnerable.controls.json`（11 条适用 / 1 条排除，review_input_sha256 与攻击面索引一致）
- 运行覆盖清单：未注入 run-manifest.json（单 Agent 全量路径）

## 📊 审查范围说明

- **项目类型**：Node.js（Express BFF 中继层，`PROJECT_TYPE=node`，激活 security profile：`node-api`）
- **审查范围**：项目目录全量生产文件
- **审查时间**：2026-09-24 00:29:40 +0800
- **审查基准路径**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/bff-header-forwarding/vulnerable
- **检测到的技术栈**：Express ^4.18.0、axios ^1.6.0；无 lockfile、无测试、无其他中间件
- **启用的审查维度**：见审查配置快照
- **跳过的审查维度**：见审查配置快照
- **项目 ignore**：未配置
- **覆盖方式**：逐文件全量阅读（server.js 17 行 + package.json），逐条对照冻结 controls 形成结论；攻击面索引用于交叉验证点位（server.js:13 同时命中 request-headers / request-body / outbound-http）

## 📊 执行摘要

- **整体结论**：该 BFF 转发层没有任何信任边界处理——客户端完全可控的请求头与请求体被原样整体透传给内网订单服务，且无任何认证、鉴权或头过滤控制，构成身份伪造/认证绕过的直通路径，必须阻断发布。
- **最高风险点**：`server.js:13` 将 `req.headers` 整体作为出站请求头转发内网上游（P0-1，CCR-NODE-BFFHEADER-001）。
- **各级别计数**：P0：1；P1：0；P2：0；P3：0；待确认：1。总计正式问题：1。
- **评分**：安全性：差（P0 身份信任边界缺陷）；性能：本规模无可评性能面；可维护性：一般（单文件直转，无结构负担）；技术债务：规模极小，核心债务即信任边界缺失。
- **问题汇总表**：

| 编号 | 级别 | 维度 | 标题 | 安全规则 ID |
|---|---|---|---|---|
| P0-1 | P0 | 维度6-安全 | BFF 将客户端请求头整体透传内网上游，身份头可被伪造实现认证绕过与跨租户访问 | CCR-NODE-BFFHEADER-001 |
| 待确认-1 | 待确认 | 维度6-安全 | 上游订单服务的主体—对象绑定无法从本仓库闭合（授权面外部证据缺失） | CCR-NODE-BOLA-001 |

## 🔍 覆盖限制与未审查范围

- **已重点检查**：唯一路由 `POST /api/orders` 的完整污点链（入口、source、propagation、sink、缺失控制）；出站目标常量性（SSRF 面）；全部注入类 sink（child_process / fs / 深合并 / NoSQL / 反序列化）的存在性；session 与 CSRF 面；授权面台账与六类差分反例。
- **未充分覆盖**：上游 `orders-svc` 的认证/授权/绑定行为（范围外服务）；网关与部署拓扑（3000 端口暴露面、上游是否处于公网可达）；整体链路的认证模式（Cookie 会话还是 Bearer）；运行时依赖版本（package.json 无 lockfile，axios/express 未形成确定性依赖漏洞结论，仅作依赖扫描建议）。
- **限制说明**：本报告为静态审查结论，"未发现问题"不等于"系统安全"；上游侧行为以最小验证用例（见待确认-1）方式闭合。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0，`1 = 0 + 0 + 1 + 0`。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| POST /api/orders（server.js:12，app.listen(3000) @ server.js:17） | 无服务端认证；身份证据完全来自客户端请求头（req.headers）与请求体（req.body）的整体透传 | 创建订单（上游写入） | 上游请求体与头部，全部客户端可控；无对象 ID 参数 | 本仓库不存在（无认证/角色/租户中间件）；由范围外 orders-svc 决策 | axios.post(UPSTREAM) → 内网订单服务写入 → resp.data 回传客户端 | 外部证据缺失 | 无（全仓库仅此 1 条路由与 1 处出站调用） |

- **已验证反例**：
  - 同角色异对象：不适用——本仓库无对象 ID 定位的读/改/删入口（唯一路由无 `:id` 参数、无数据访问层）；上游对象绑定归待确认-1。
  - 低权限高功能：不适用——仓库内仅业务下单动作，无管理/审批/配置/导出类高权限动作；上游侧高权限面属外部范围。
  - 跨租户/组织：外部证据缺失——客户端可伪造 `X-Tenant-Id` 等租户头并经 P0-1 透传上游，上游是否校验租户上下文无法静态核验。
  - 对象属性越权（mass assignment）：外部证据缺失——`req.body` 整体透传（server.js:13），字段级白名单/schema 约束不在本仓库，是否构成属性越权取决于上游校验。
  - 批量与嵌套资源：不适用——无批量/嵌套资源入口（仅单一 POST 路由，无集合与父子资源参数）。
  - 替代执行路径：已检查无发现——全仓库仅 1 条 `app.post` 路由、1 处 axios 出站调用，无 router 挂载、无中间件旁路、无异步/消息/缓存入口。
- **未闭合入口与外部依赖**：上游 orders-svc 的认证/授权/主体绑定行为；网关与会话基础设施；部署网络拓扑（3000 端口与内网可达范围）。
- **结论边界**：台账存在"外部证据缺失"行，不能声明"未发现越权问题"。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：0
- 已检查无发现：9
- 外部证据缺失：2
- 静态不可验证：0
- 不适用：0
- 语义提升：1
- 对账：N = A + B + C + D → 11 = 0 + 9 + 2 + 0

口径说明：冻结 resolver 排除 1 条控制（CCR-NODE-BFFHEADER-001，激活 profile=node-api 未启用其所属 node-bff profile）。语义审查证实该控制的风险证据链在本仓库完全闭合，按控制目录与报告契约以 `finding_confirmed` 语义提升入台账并单列计数（不进入 N 的 A-D 对账），因此不适用 E = 排除数 1 − 语义提升 1 = 0。

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3、v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 全仓库无服务端身份/租户上下文构造（无 ctx.user/session/claims 类赋值），identity-context sink 不存在；经转发头形成的身份伪造风险由 CCR-NODE-BFFHEADER-001（P0-1）承接，不重复计数 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | package.json 无 express-session/cookie-parser 依赖，源码无 req.session 读写，session-write sink 不存在 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 唯一出站目标为常量 UPSTREAM（server.js:10）；用户仅可控 body 与 headers，URL/host/path/重定向目标不接收任何用户可控字段，无用户可控外发目标入口 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全仓库无 child_process 引用（require 仅 express/axios），命令执行 sink 不存在 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2、v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/res.sendFile/res.download 调用，且唯一路由无路径参数（req.params 不存在），文件 sink 不存在 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | express.json 解析结果仅作为 axios data 直传，无 merge/extend/defaults/自写递归合并 sink 消化 req.body |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 mongodb/mongoose 依赖与任何查询构造，NoSQL sink 不存在 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化入口，跨边界数据仅经 JSON 语义（express.json） |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2、v5.0.0-V8.3.3 / CWE-639 | semantic | external_evidence_missing | 本仓库无对象 ID 定位入口与数据访问层；订单主体—对象绑定完全由范围外 orders-svc 决策，且 BFF 未派生可信主体（身份头透传，见 P0-1）——上游绑定有效性无法静态核验，缺口与最小验证见待确认-1 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 唯一路由为业务下单动作（POST /api/orders），仓库内无管理/审批/配置/导出类高权限 sink；上游侧高权限面属外部范围（关联待确认-1） |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2、v5.0.0-V3.5.2 / CWE-352 | config | external_evidence_missing | 缺口：本仓库无 Cookie 会话建立逻辑（无 express-session/Set-Cookie/Cookie 读取）无法确认认证模式；但 Cookie 头随 req.headers 整体透传上游（P0-1），若整体链路依赖 Cookie 会话则该写接口在仓库内无 Origin 校验/CSRF token/SameSite 任何证据——认证模式需运行态确认（可与待确认-1 的矩阵一并验证） |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | finding_confirmed | 语义提升（resolver 因激活 profile=node-api 排除；代码证据闭合 req.headers → axios 内网上游整体透传链，按目录规则提升）；证据链与修复方案见 P0-1 |

## ✅ 最佳实践亮点

未发现足够稳定且值得单独表扬的安全最佳实践亮点（本仓库无任何认证、过滤或最小化处理）。

## 🔴 P0 严重问题

> P0 五项硬门槛（生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布）逐项核验见各条目内说明。

### P0-1 | [维度6-安全] BFF 将客户端请求头整体透传内网上游，身份头可被伪造实现认证绕过与跨租户访问

**位置**：server.js:13（同类问题共 1 处；入口注册 server.js:12，上游目标常量 server.js:10，监听 server.js:17）

**置信度**：高 | **所属维度**：维度6-安全

**安全规则 ID**：CCR-NODE-BFFHEADER-001

**标准映射**：OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290

**检测方式**：taint

**证据状态**：静态已证实（Source→Propagation→Sink→Missing Control 四段证据链全部由仓库内代码闭合；上游对转发身份头的消费行为另附最小运行态验证方案）

**问题**：`POST /api/orders` 把客户端完全可控的 `req.headers` 原样整体作为出站请求头转发给内网订单服务，未做显式头白名单、hop-by-hop 剥离或身份头服务端重生成，客户端可直接伪造 `Authorization` / `X-User-Id` / `X-Tenant-Id` / `Cookie` 等身份头直达内网受信边界。

**证据**：

```js
// server.js:10  Sink 目标：内网上游（虚构服务名）
const UPSTREAM = 'http://orders-svc:8080/api/orders';

// server.js:12  Entry：公开 HTTP 入口（app.listen(3000) @ server.js:17）
app.post('/api/orders', async (req, res) => {
  // Source(req.headers 客户端全量可控) → Propagation(零过滤) → Sink(axios 内网上游)
  const resp = await axios.post(UPSTREAM, req.body, { headers: req.headers }); // ← req.headers 整体透传
  res.status(resp.status).json(resp.data);
});
```

证据链逐段闭合：

- **Entry**：server.js:12 路由注册 + server.js:17 `app.listen(3000)`；package.json `main: server.js`——入口装配与启动均由仓库证据闭合（生产可达）。
- **Source**：`req.headers` 为客户端全量可控对象，可携带 `Authorization`、`Cookie`、`X-User-Id`、`X-Tenant-Id`、`X-Internal-*` 等任意信任头；文件头注释（server.js:1-2）自述设计意图「客户端请求头整体携带在出站请求上」。
- **Propagation**：`{ headers: req.headers }` 未经任何键筛选、删除或服务端重生成直接进入 axios 请求配置——比 node-rules「BFF 中继层负面清单」第 1 条的黑名单式过滤更弱，本例连黑名单都没有。
- **Sink**：`axios.post(UPSTREAM, ...)` 外发内网 `orders-svc:8080`；攻击面索引同点位命中（surface.json：server.js:13 outbound-http + request-headers + request-body）。
- **Missing Control**：全文件无 explicit-header-allowlist、无 strip-hop-by-hop（host/content-length/connection/transfer-encoding 等同样未处理）、无 identity-header-regeneration；亦无任何认证中间件。

**主体/资源/决策链**：主体 = 无服务端认证的匿名调用方，身份证据完全来自客户端透传的请求头与请求体；受保护动作 = 在内网订单服务上创建订单（上游写入）；资源与标识来源 = 上游请求体与头部，全部客户端可控；授权证据/决策点 = 本仓库不存在（无认证中间件、无 session、无角色/租户判断）；owner/tenant/org/role/scope 绑定结果 = 未绑定（身份头可任意伪造）；最终 Sink = 内网 orders-svc 写入 + `resp.data` 回传客户端。

**未授权路径与防护**：最短路径 = 任意调用方 → `POST /api/orders`（无认证）→ 携带伪造 `X-User-Id: <受害者>` / `X-Tenant-Id: <他租户>` / `Authorization: ***` 头 → BFF 原样转发 → 内网订单服务按伪造身份执行写入。现有防护：无——仓库内未发现任何头过滤、认证中间件或出口白名单；不得以「上游是内网服务」作为缓解——按「内网可达性放大定级」原则（IMA BFF 事件实证），BFF 中继触达内网服务正是该形态的杀伤力来源。

**影响**：上游若信任这些转发头作为身份/租户来源（本控制的典型事故形态），客户端可冒充任意用户/租户创建订单、绕过认证直达内网受信服务，构成认证绕过与跨租户越权，事故级影响成立；同时真实凭据头（Cookie/Authorization）被中继放大暴露面，hop-by-hop 头与内部信任头（如 X-Internal 类）一并送达上游，BFF 的信任边界作用完全失效。缺少有效防护成立；必须阻断发布成立（该透传是系统身份链的根入口，无法靠下游兜底）。

**建议**：

1. 按显式白名单逐头构造出站请求头（仅放行业务必需的非身份头），禁止 `headers: req.headers` 整体透传，也禁止在黑名单删除少数键上打补丁：

```js
// 修复示意：显式白名单 + 身份头服务端重生成
const OUTBOUND_HEADER_ALLOWLIST = ['accept', 'content-type', 'x-request-id']; // 仅非身份头
const headers = {};
for (const k of OUTBOUND_HEADER_ALLOWLIST) { if (req.headers[k] != null) headers[k] = req.headers[k]; }
headers['content-type'] = 'application/json';
headers['x-user-id'] = String(req.user.id);      // 来自服务端认证结果，绝不取自 req.headers
headers['x-tenant-id'] = String(req.user.tenantId);
const resp = await axios.post(UPSTREAM, req.body, { headers }); // hop-by-hop 头天然不会进入
```

2. 转发前剥离 hop-by-hop 头与全部客户端可控身份头；身份头（X-User-Id/X-Tenant-Id/Authorization）必须由 BFF 侧认证结果（session/JWT 校验）在服务端重新生成。
3. 先为该路由补服务端认证中间件，再建立上游对服务端派生身份的信任。
4. 无法确认上游是否消费身份头时，按控制 remediation 以最小验证用例先行确认（见验证方案）。

**验证方案**（最小、非破坏性，测试环境）：主体 A（合法）与匿名主体 B 分别携带 `X-User-Id: A` 调用 `POST /api/orders`，对比上游落单归属与响应差异——预期修复后 B 的伪造头被剥离/重生成，订单仅归属真实认证主体；同时在上游侧抓包确认 hop-by-hop 头与客户端身份头不再出现。只读验证，测试数据用后清理。

---

## 🟠 P1 重要问题

本次未发现 P1 级问题。

## 🟡 P2 一般问题

本次未发现 P2 级问题。

## 🔵 P3 建议

本次未发现 P3 级问题。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 上游订单服务的主体—对象绑定无法从本仓库闭合（授权面外部证据缺失）

**位置**：server.js:13（关联范围外上游 `http://orders-svc:8080/api/orders`）

**置信度**：低 | **所属维度**：维度6-安全

**安全规则 ID**：CCR-NODE-BOLA-001

**标准映射**：OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2、v5.0.0-V8.3.3 / CWE-639

**检测方式**：semantic

**证据状态**：待确认项（依赖范围外服务行为，静态无法闭合）

**依据**：

```js
// server.js:13  BFF 不派生任何可信主体；订单创建的主体绑定完全由上游决策
const resp = await axios.post(UPSTREAM, req.body, { headers: req.headers }); // ← 主体证据全由客户端透传
```

**主体/资源/决策链**：主体 = 匿名调用方（无服务端认证）；受保护动作 = 订单创建/查询（上游）；资源与标识来源 = 客户端可控的 body 与头部；授权决策点 = 范围外 orders-svc；owner/tenant 绑定结果 = 仓库内不可见；最终 Sink = 上游订单数据写入与返回。

**未授权路径与防护**：未授权主体 → 伪造身份头/请求体（经 P0-1 透传）→ 上游按客户端自述身份落单。现有防护：本仓库内无；上游是否存在绑定逻辑未知，不能以上游"内部服务"标签当作授权证据。

**待确认原因**：本仓库无数据访问层、无对象 ID 定位的读/改/删入口，订单与调用主体的绑定关系完全由范围外的 orders-svc 决策；且由于 P0-1 的身份头整体透传，上游即便存在绑定逻辑，其收到的主体证据也全部客户端可控——上游是否执行 owner/tenant 绑定、是否消费转发身份头，均无法从当前仓库静态闭合。

**建议的验证方式**：测试环境按权限矩阵最小验证：主体 B（同角色）携带指向主体 A 的身份头/对象参数调用下单与订单查询路径，预期上游拒绝或仅返回 B 可见数据；修复 P0-1（身份头服务端重生成）后复测同一矩阵，确认绑定基于可信主体生效。同时确认整体链路认证模式（Cookie 会话还是 Bearer），一并闭合 CCR-NODE-CSRF-001 的外部证据缺口。

---

## 🎯 修复优先级

- **P0 - 立即修复**：P0-1（请求头整体透传内网上游，身份伪造直通）。
- **P1 - 尽快修复**：无。
- **P2 - 计划修复**：无。
- **P3 - 可选优化**：无。
- **待确认**：待确认-1（上游主体绑定与整体链路认证模式，随 P0-1 修复一并验证）。

## 📝 总结

- **整体架构判断**：这是一个零信任边界处理的单路由 BFF 中继层——入口无认证、出口无头白名单，客户端上下文被原样搬进内网，身份链完全由客户端自述。
- **本次模式核心判断**：security 模式下最严重的风险不是注入类 sink（均不存在），而是身份信任边界缺陷——CCR-NODE-BFFHEADER-001 的污点链在仓库内完整闭合（P0-1），且该控制被 resolver 按 profile 误排除后经语义审查提升确认；上游授权面（BOLA/CSRF）留有外部证据缺口（待确认-1）。
- **关键行动项**：
  1. 以显式头白名单 + hop-by-hop 剥离 + 身份头服务端重生成替换 `headers: req.headers` 整体透传（P0-1）。
  2. 为 `POST /api/orders` 补服务端认证（session/JWT），使上游身份来源唯一化为服务端派生。
  3. 按待确认-1 的权限矩阵在测试环境核验上游主体绑定与整体链路认证模式（含 CSRF 面）。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
