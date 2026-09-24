# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24 00:32
- 审查类型：存量全量（stock review）
- 审查范围：renamed-wrapped 项目全部生产源码（server.js，33 行）+ 伴随文件 package.json
- 审查模式：security（安全专项）
- 审查语言：frontend（Node.js / Express BFF 转发层）
- 审查模型：未注入（评测运行）
- 启用维度：1 正确性、4（仅配置安全子项）、5（仅注入/越权子项）、6 安全（全深度）、9（仅敏感信息泄露）、11（仅鉴权/错误信息）
- 跳过维度：2 类型安全、3 代码质量、7 性能、8 副作用与资源清理、10 测试质量、11 其余子项、12 设计系统一致性（security 模式矩阵）
- 模式说明：聚焦维度 6 全深度及安全强相关交叉维度；同时执行企业级 Security 框架（安全语义、取证、证据等级、授权面二次扫描与控制台账）
- 检测到的技术栈：Node.js + Express ^4.18.0 + axios ^1.6.0（无 lockfile）
- 语义增强：未注入（纯静态人工语义追踪并在此披露降级）。本项目符号经改名并存在两层 util 传播——路由层只见 `pipeToCoreSvc`，头集合语义经 `pickMeta` / `decorate` 逐行数据流核对得出，不依赖函数名词表命中
- 本轮冻结适用控制：/tmp/cc-eval-20260923/artifacts/bff-header-forwarding-renamed-wrapped.controls.json（11 条适用 / 1 条排除，review_input_sha256=58e4b5e0…）
- Node 攻击面索引（仅导航候选）：/tmp/cc-eval-20260923/artifacts/bff-header-forwarding-renamed-wrapped.surface.json（命中 outbound-http / request-headers / request-body / http-route / server-listen；仅导航，非发现清单）
- 项目 ignore 状态：未配置
- 文件覆盖率：生产源码 1/1（server.js）；伴随文件 package.json 已读
- 网络访问：零（全程离线，仅本地文件）

## 📊 审查范围说明

- **项目类型**：Node.js（Express）BFF 转发服务（package.json `main=server.js`）
- **审查范围**：全部生产源码 server.js（唯一源文件，33 行）；package.json 作为伴随配置读取
- **审查基准路径**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/bff-header-forwarding/renamed-wrapped
- **检测到的技术栈**：Express 4.18 + axios 1.6
- **启用的审查维度**：1、4（部分）、5（部分）、6、9（部分）、11（部分）
- **跳过的审查维度**：2、3、7、8、10、12
- **项目 ignore**：未配置
- **覆盖方式**：逐文件全量阅读 → 入口/身份/资源/汇点取证 → 授权面二次扫描（动作中心）→ 冻结控制逐条对账

## 📊 执行摘要

- **整体结论**：存在 1 条事故级安全问题。客户端可控的全部请求头经两层改名 util（`pickMeta` → `decorate`）传播后整体透传给内网核心服务 core-svc，无显式头白名单、无 hop-by-hop 剥离、无身份头服务端重生成，且唯一入口无任何认证。属 IMA 前端 BFF 事件同形态（BFF 中继层负面清单第 1/2 条）。
- **最高风险点**：任意客户端可携带任意身份/信任头（Authorization、X-User-Id、X-Tenant-Id、Cookie、X-Forwarded-For 等）直达内网 `core-svc:8080`，形成身份/租户伪造与内网信任域注入。
- **问题计数**：P0 = 1，P1 = 0，P2 = 0，P3 = 0，待确认 = 1
- **评分**：安全性：差（安全控制面为零）；性能：不适用（本模式跳过）；可维护性：一般（33 行但封装名不副实，`pickMeta` 恒等返回）；技术债务：低规模（无 lockfile、无错误处理中间件属次要）

## 🔍 覆盖限制与未审查范围

- **已重点检查**：唯一入口 `POST /api/orders` 的完整数据流（客户端头 → `pickMeta` → `decorate` → axios 出站头）；外发目标常量；请求体处理路径；依赖清单。
- **未充分覆盖**：上游 core-svc 的鉴权与头消费行为（范围外，见待确认-1）；BFF :3000 的网络暴露位置与前置网关（部署配置，范围外）。
- **限制说明**：仓库无 lockfile，axios ^1.6.0 / express ^4.18.0 的依赖漏洞结论按全局规则不落定，仅记录为依赖扫描建议（不构成正式问题）。语义增强未注入，本轮以静态语义追踪完成并披露降级。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0，1 = 0 + 0 + 1 + 0。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| app.post('/api/orders')（server.js:27） | 客户端自声明：转发的请求头（无服务端派生，无认证中间件） | 写（在 core-svc 创建订单） | 订单资源，标识与字段由 req.body 原样提供（server.js:28） | 仓库内不存在任何授权判断；决策完全位于范围外 core-svc | axios.post('http://core-svc:8080/v1/orders')（server.js:24），resp.data 原样回传（server.js:29） | 外部证据缺失（BFF 侧身份伪造使能缺陷已作为 P0-1 正式问题） | 无（唯一路由；无异步/任务/消息/RPC/旧版本入口） |

- **已验证反例**（六类逐一构造，非适用项写明证据）：
  1. 同角色异对象：仓库内无对象 ID 定位操作（创建型端点）；回传数据的归属过滤位于上游 → 外部证据缺失（并入待确认-1）。
  2. 低权限高功能：仓库内无管理/审批/配置/导出类高权限动作，唯一动作为普通业务写入 → 不适用（无高权限动作可差分；身份伪造对上游高权限面的暴露已并入 P0-1 影响）。
  3. 跨租户/组织：租户上下文 = 客户端可控头（可伪造 X-Tenant-Id 类头直达 Sink），BFF 侧零绑定 → 使能缺陷已正式化为 P0-1，采信效果依赖上游（待确认-1）。
  4. 对象属性越权：req.body 原样透传（server.js:28），字段白名单位于上游 → 外部证据缺失（并入待确认-1）。
  5. 批量与嵌套资源：无批量/嵌套端点 → 不适用。
  6. 替代执行路径：无其他路由、无异步任务、无消息消费、无内部 RPC 入口 → 不适用（唯一入口，server.js 全部路由仅 1 条）。
- **未闭合入口与外部依赖**：core-svc 的鉴权方式与身份头消费行为；BFF :3000 的部署网络位置与前置网关。
- **结论边界**：本仓库唯一「入口 × 受保护动作」的授权决策点在范围外上游，不能声明"未发现越权问题"——BFF 侧身份伪造使能路径已构成正式问题 P0-1，上游侧归属判定留待外部验证（待确认-1）。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：0
- 已检查无发现：10
- 外部证据缺失：1
- 静态不可验证：0
- 不适用：0
- 语义提升：1
- 对账：N = A + B + C + D → 11 = 0 + 10 + 1 + 0

口径说明：冻结 resolver 排除 1 条控制（CCR-NODE-BFFHEADER-001，理由"激活 profile: node-api，node-bff 未启用"）。代码语义证据确认本项目实为 BFF 中继形态并命中该控制描述的风险形态（客户端头整体透传内网上游，IMA 事故形态），按排除项注释允许的路径语义提升为 finding_confirmed 并单列计数：提升行不进入适用控制 N 的 A-D 对账，E = 冻结排除 1 − 语义提升 1 = 0。

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | finding_confirmed | 语义提升行。见 P0-1：req.headers 经 pickMeta（server.js:12-14 恒等返回）→ decorate（server.js:17-19 浅合并）→ axios.post 第三参 headers（server.js:24）整体透传内网 core-svc；无显式头白名单、无 hop-by-hop 剥离、无身份头重生成 |
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025、A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3、v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 仓库内无服务端身份/租户上下文构造点（无认证中间件，无 ctx.user/session/tenant 赋值，surface 索引 identity_sources 为空）；客户端身份注入经整体头透传体现，已由 BFFHEADER-001 语义提升行与 P0-1 承载，不在本控制重复计损 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全仓库无 session 使用：无 express-session/cookie-parser 依赖（package.json dependencies 仅 axios/express），req.session 零引用 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023、API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 外发目标为硬编码常量 CORE_SVC（server.js:9），URL/host/path 无任何用户输入进入；用户可控的 body 与头进入的是请求载荷与头集合（已由 BFFHEADER-001 覆盖），不构成目标可控 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全仓库无 child_process 引用（server.js 仅 require express/axios） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2、v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 全仓库无 fs/res.sendFile/res.download/createReadStream 路径操作 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 唯一合并原语 Object.assign（server.js:18）为浅合并且两个源均为固定键字面量（{timeout} 与 {headers}），req.body/req.headers 的键从未被展开进合并目标；无递归深合并消化请求对象，__proto__/constructor 键无进入路径（冻结信号 deep-merge 系对该浅合并的误报，语义复核后关闭） |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 客户端与查询构造（依赖仅 express/axios） |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化入口；跨边界仅 express.json() 的 JSON.parse 语义（server.js:7） |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2、v5.0.0-V8.3.3 / CWE-639 | semantic | external_evidence_missing | 本仓库为纯转发层：无对象 ID 解析与查询构造，订单对象归属/owner/tenant 过滤完全位于范围外 core-svc，无法在本仓库静态闭合主体—对象绑定。最小验证：同角色异对象差分请求（见待确认-1 验证方案） |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 仓库内无管理/审批/配置/导出/删除类高权限动作，唯一路由为普通业务写入（server.js:27）；"任意身份直达上游"的整体影响已在 P0-1 定级，不重复计损 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2、v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 仓库内无 cookie 会话基础设施（无 session 中间件、无 Set-Cookie，唯一中间件为 express.json()），状态变更端点在仓库证据内不依赖浏览器自动携带凭据；若部署层在 BFF 前引入 cookie 会话需另行评估（已在覆盖限制披露） |

## ✅ 最佳实践亮点

未发现足够稳定且值得单独表扬的最佳实践亮点（唯一正向事实是外发目标为硬编码常量，避免了 SSRF 目标可控，但这只是未引入风险而非防护实践）。

## 🔴 P0 严重问题

> P0 五项硬门槛：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布——逐项论证见条目内「P0 门槛论证」。

### P0-1 | [维度6-安全] 客户端请求头经两层改名 util 传播后整体透传内网核心服务，身份头可伪造（IMA 事故形态）

**位置**：server.js:22-24（代表处；完整传播链 server.js:12-14、17-19、22-24，入口 server.js:27）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：BFF 把客户端可控的全部请求头（含 Authorization、Cookie、X-User-Id、X-Tenant-Id、X-Forwarded-For 等身份/信任头）经 `pickMeta` → `decorate` 两层改名 util 原样传播后，整体作为出站请求头发给内网 core-svc——无显式头白名单、无 hop-by-hop 剥离、无身份头服务端重生成，且入口无任何认证。

**证据**（数据流逐行追踪：路由层只见 `pipeToCoreSvc`，头集合语义经两层 util 展开核对，非函数名词表命中）：
```js
const CORE_SVC = 'http://core-svc:8080/v1/orders';    // server.js:9 内网上游（目标为常量，头集合完全客户端可控）

function pickMeta(headers) {                           // server.js:12 第一层传播（改名包装）
  return headers;                                      // ← server.js:13 恒等返回：未做任何挑选/白名单，req.headers 全量原样通过
}

function decorate(outboundOpts) {                      // server.js:17 第二层传播（改名包装）
  return Object.assign({ timeout: 5000 }, outboundOpts); // ← server.js:18 仅补充 timeout；headers 键携带完整客户端头集合进入出站配置
}

async function pipeToCoreSvc(req, payload) {           // server.js:21
  const meta = pickMeta(req.headers);                  // ← server.js:22 Source：客户端可控的全部入站请求头
  const opts = decorate({ headers: meta });            // ← server.js:23 Propagation：白名单/剥离机会点为零
  return axios.post(CORE_SVC, payload, { headers: opts.headers, timeout: opts.timeout });
}                                                      // ← server.js:24 Sink：全部客户端头进入内网上游请求（hop-by-hop 与身份头均未剥离）

app.post('/api/orders', async (req, res) => {          // ← server.js:27 Entry：唯一入口，无认证/鉴权中间件
  const resp = await pipeToCoreSvc(req, req.body);     // ← server.js:28 请求体亦原样转发
  res.status(resp.status).json(resp.data);             // ← server.js:29 上游响应原样回传客户端
});
```

**安全规则 ID**：CCR-NODE-BFFHEADER-001（冻结 resolver 因 profile=node-api 将其排除，经代码语义证据按排除项注释允许的路径提升，见控制覆盖节「语义提升」）

**标准映射**：OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290

**检测方式**：taint

**证据状态**：静态已证实——入口（server.js:27 路由注册 + server.js:32 `app.listen(3000)` 装配）、来源（server.js:22 `req.headers` 整体）、传播（server.js:12-14 恒等包装、server.js:17-19 浅合并包装、server.js:23）、汇（server.js:24 `axios.post` 第三参 headers）、缺失控制（全文件无头白名单/剥离/重生成/认证，逐行可复核）在仓库内全部闭合；上游是否采信身份头属攻击效果问题，单列为待确认-1，不影响缺陷本身成立。

**主体/资源/决策链**：主体 = 客户端自声明身份（转发的请求头，无服务端派生）；受保护动作 = 在内网 core-svc 创建订单（内部写）；资源 = 订单资源，标识与字段由 req.body 原样提供；授权证据/决策点 = 仓库内不存在（无任何认证/鉴权中间件），完全位于范围外 core-svc；owner/tenant/org/role/scope 绑定结果 = BFF 侧未绑定（身份证据客户端可控）；最终 Sink = `axios.post('http://core-svc:8080/v1/orders')`（server.js:24）。

**未授权路径与防护**：最短路径 = 任意可达 BFF:3000 的客户端 `POST /api/orders` + 自设 `X-User-Id: <任意>`（或 Authorization / X-Tenant-Id / Cookie 变体）→ `pickMeta` 恒等返回全部头（server.js:13）→ `decorate` 仅加 timeout（server.js:18）→ axios 把全部客户端头发给内网 core-svc（server.js:24）→ 若上游按头鉴权即以伪造身份完成内部写入，并经 server.js:29 读取按该身份过滤的响应。现有防护：无——全文件 33 行内不存在任何头白名单、hop-by-hop 剥离、身份头重生成或认证中间件（无黑名单删除式过滤、无网关证据，不存在"半吊子防御"可讨论的残余面）。

**影响**：
1. 任意身份/租户伪造直达内网：core-svc 若按转发头识别主体（BFF 上游常见形态，IMA 事故实证），客户端可冒充任意用户/租户创建订单、读取按身份过滤的数据（API2:2023 认证失效形态）。
2. 内网可达性放大（框架定级规则：内网可达范围计事故级）：出站直达内网 `core-svc:8080`，客户端可把内网信任头（X-Internal、X-Forwarded-For、内部 token 头等）注入内网信任域，等于把 BFF 的客户端请求面延伸进内网。
3. hop-by-hop 头（host、content-length、connection、transfer-encoding 等）未剥离，与 axios 自生成头并存，存在上游解析差异/请求走私的次要风险。
4. 上游响应原样回传（server.js:29），与身份伪造叠加形成数据外泄通道。

**建议**：
1. 出站头改为**显式白名单逐键构造**（禁止在黑名单 delete 上打补丁），并剥离 hop-by-hop 头。
2. 身份头一律由 BFF 侧认证结果**重新生成**（服务端派生），不透传客户端值——键名白名单不等于值可控，值的来源才重要。
3. 入口增加认证中间件（401 拒绝匿名，缺失/异常时拒绝而非放行）。
修复示意：
```js
const HOP_BY_HOP = new Set(['connection', 'keep-alive', 'proxy-authenticate',
  'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'host', 'content-length']);
const FORWARD_ALLOWLIST = ['accept', 'content-type', 'accept-language', 'user-agent']; // 仅非身份、非信任语义头

function buildUpstreamHeaders(req, auth) {
  const out = {};
  for (const h of FORWARD_ALLOWLIST) {
    if (req.headers[h] != null && !HOP_BY_HOP.has(h)) out[h] = req.headers[h]; // 白名单键 + 剥离 hop-by-hop
  }
  out['x-user-id'] = auth.userId;              // 身份头服务端重生成，不取客户端值
  out['x-tenant-id'] = auth.tenantId;          // 租户头同理
  out.authorization = 'Bearer ' + serverToken; // 内部服务凭据由服务端注入（*** 脱敏示意）
  return out;
}
// pipeToCoreSvc 内改为：axios.post(CORE_SVC, payload, { headers: buildUpstreamHeaders(req, auth), timeout: 5000 })
```
4. 短期无法确认上游头消费行为时，也先在 BFF 侧完成上述收敛（防御与上游实现解耦），并按待确认-1 完成最小验证。

**P0 门槛论证**：生产可达（入口注册与监听装配在仓库闭合，server.js:27/32；客户端头到内网请求头的链路仓库内全程无阻断点）｜证据完整且置信度高（Source→Propagation→Sink→Missing Control 全链行号闭合）｜事故级影响（内网核心服务任意身份伪造，IMA 同形态，按内网可达性放大计级）｜缺少有效防护（零控制，无任何白名单/剥离/重生成/认证）｜必须阻断发布（是）。

**验证方案**（最小、非破坏，测试环境+测试账号）：(a) 向 /api/orders 发送带自定义 `X-User-Id: test-A` 的请求并在 BFF 出口抓包，确认上游收到全部客户端头（证实透传）；(b) 修复后重复同一请求，确认上游收到的头集合仅剩白名单键且身份头为服务端值。对照待确认-1 观察上游是否随头切换主体。

---

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 上游 core-svc 是否将转发的客户端头作为身份/租户来源（决定 P0-1 的实际攻击效果）

**位置**：server.js:9（上游地址；上游实现不在本仓库）

**置信度**：低 | **所属维度**：维度6-安全

**依据**：
```js
const CORE_SVC = 'http://core-svc:8080/v1/orders'; // ← 上游实现与鉴权方式范围外：是否消费 X-User-Id/X-Tenant-Id/Authorization 等转发头无法静态闭合
```

**待确认原因**：P0-1 的透传缺陷与缺失控制已在仓库内闭合；但"伪造头会被上游采信为身份"这一最终攻击效果依赖范围外 core-svc 的实现与部署（是否按头鉴权、是否处于内网信任域、BFF 前是否有网关认证）。按框架证据等级归入待确认项，不据此降低 P0-1 的定级（缺陷本身与上游实现解耦）。

**建议的验证方式**：测试环境构造最小差分用例（非破坏，测试账号与测试订单）：同一客户端分别以 `X-User-Id: user-A` 与 `X-User-Id: user-B`（及 Authorization / X-Tenant-Id 变体）POST /api/orders，观察 core-svc 落库主体与响应数据归属是否随头变化；若随头变化即证实任意身份伪造链路闭环。同时核验 BFF:3000 的网络暴露位置与前置网关是否提供独立认证。预期矩阵：同一低权限账号仅切换头中主体标识 → 上游数据归属跟随头变化 = 风险证实；上游拒绝或忽略该类头 = 仅剩信任域注入面。

---

## 🎯 修复优先级

- P0 - 立即修复：P0-1（出站头白名单 + hop-by-hop 剥离 + 身份头服务端重生成 + 入口认证）
- P1 - 尽快修复：无
- P2 - 计划修复：无
- P3 - 可选优化：无（依赖扫描建议见「覆盖限制与未审查范围」，不构成正式问题）
- 待确认：待确认-1（上游头消费行为与部署网络位置的差分验证）

## 📝 总结

- 一句话架构判断：一个 33 行的 Express BFF 纯转发层——路由层把请求体与全部请求头经两层改名 util 递交给内网 core-svc，自身不带任何安全控制。
- 本次模式核心判断：安全控制面为零；客户端头集合可整体注入内网信任域，属 IMA 事故同形态的事故级缺陷（P0-1，语义提升 CCR-NODE-BFFHEADER-001），上游采信行为待外部验证（待确认-1）。
- 3 个关键行动项：① 出站头白名单化并重生成身份头；② 入口补认证中间件（拒绝匿名）；③ 按待确认-1 完成上游差分验证并核验 BFF 部署网络位置。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
