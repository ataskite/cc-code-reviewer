# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量（stock review）
- 审查范围：`/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/authorization/bola-unbound`（全部生产源码：`server.js`、`package.json`）
- 审查模式：security（安全专项）
- 语言 / 类型：frontend（Node.js；resolver 判定 `security_profile=node-api`）
- 必读依据：`references/languages/frontend/review-framework.md`、`references/languages/frontend/node-rules.md`、`references/security/enterprise-security-framework.md`、`references/security/catalog/node-security-controls.json`、`references/report-format.md`（均已读取）
- 本轮冻结适用控制：`/tmp/cc-eval-20260923/artifacts/authorization-bola-unbound.controls.json`（catalog_sha256=`ce6f7e7b1a6abb8e1a07728fce740faed7ebc2d58852a0a35ae8dd3610d7e21f`）
- Node 攻击面索引：`/tmp/cc-eval-20260923/artifacts/authorization-bola-unbound.surface.json`（仅导航候选，非发现清单；命中：http-middleware / http-route / server-listen / request-headers / request-params / db-query / owner-tenant-binding 模式信号）
- 启用维度（security 模式）：1 正确性、4（仅配置安全子项）、5（仅注入/越权子项）、6 安全（全深度）、9（仅敏感信息泄露）、11（仅鉴权/错误信息）
- 跳过维度：2、3、7、8、10、12
- 项目 ignore 状态：未配置
- 文件覆盖率：2/2（100%，`server.js` 30 行 + `package.json` 12 行，逐文件完整阅读）
- 网络访问：无（零 URL 访问，仅本地文件取证）

## 📊 审查范围说明

- **项目类型**：Node.js API 服务（Express 4 + Mongoose 7，`package.json` `main=server.js`，无构建/前端资源）
- **审查范围**：仓库全部生产源码；无测试目录、无配置目录、无 CI/容器文件
- **审查基准路径**：`/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/authorization/bola-unbound`
- **检测到的技术栈**：express@^4.18.0、mongoose@^7.0.0（无 lockfile，依赖漏洞结论按依赖风险规则不形成确定性结论）
- **覆盖方式**：逐文件全量阅读 + 授权面二次扫描（入口 × 受保护动作台账）+ 冻结控制逐条结论
- **覆盖限制**：仓库内无网关/部署配置可取证；`requireLogin` 为认证层示意桩（见授权面覆盖说明），按文件注释「假定认证层已解析出 req.user」采信登录态成立，不影响越权结论

## 📊 执行摘要

- **整体结论**：不通过。唯一业务端点 `GET /orders/:id` 仅校验登录态，查询条件不含主体（owner）绑定，构成证据链闭合的水平越权（BOLA/IDOR），任意登录用户替换订单 ID 即可读取任意他人订单，必须阻断发布修复后上线。
- **最高风险点**：P0-1 主体—对象绑定缺失（CCR-NODE-BOLA-001），数据模型已具备 `ownerId` 字段但查询从未使用，属「登录即放行」型对象级授权缺失。
- **问题计数**：P0：1；P1：0；P2：0；P3：0；待确认：0；总计：1。
- **安全性评分**：差（对象级授权完全缺失）；性能/可维护性/技术债：本模式不评（security 模式关闭对应维度）。
- **项目 ignore 命中统计**：未配置，无过滤。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：唯一 HTTP 入口 `GET /orders/:id` 的完整安全契约（入口 → 主体 → 决策点 → 资源 → Sink）；认证示意中间件的 fail-open/fail-closed 行为；Mongoose 查询构造（操作符注入面）；出站请求/子进程/文件系统/反序列化/深合并 sink 全量排查（均不存在）；冻结 11 条适用控制逐条结论。
- **未充分覆盖**：运行时部署形态（网关、真实认证服务、数据库行级策略）不在仓库内，无法取证——本报告所有「外部证据」缺失点已在台账中注明，且不影响 P0-1 的代码内闭环结论。
- **限制说明**：无 lockfile，依赖漏洞不形成确定性结论；`requireLogin` 为示意桩（Authorization 头仅判存在性、身份值固定），按注释采信为「认证已完成」，其自身实现不作为正式问题输出（见授权面覆盖·结论边界）。

## 🔐 授权面覆盖（仅 Security 模式强制）

**授权面台账**：共 1 行；已绑定 0 / 未绑定 1 / 外部证据缺失 0 / 不适用 0（1 = 0 + 1 + 0 + 0）。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| `GET /orders/:id`（server.js:23，`app.listen(3000)` 装配于 server.js:29，`package.json` main=server.js） | `req.user = { id: 'u_1001', role: 'member' }` 由 `requireLogin`（server.js:17-21）注入；示意桩按注释采信为登录态已解析，值非客户端输入 | 受限数据读取（订单详情，含 ownerId/items/total） | 订单对象，标识来自 `req.params.id`（路径参数，客户端可控） | `requireLogin` 仅校验 `req.headers.authorization` 存在性；无对象级/属主级授权判断 | `Order.findById(req.params.id)`（server.js:24）→ `res.json(order)`（server.js:26）整对象返回 | **未绑定**（schema 定义了 `ownerId`（server.js:10）但查询条件未并入任何主体绑定字段） | 无（仓库内无列表/搜索/批量/导出/下载/缓存/异步/旧版本等替代路径） |

**已验证反例**（六类差分）：

1. **同角色异对象**：成立（未绑定）——主体 B（同角色 member）将 `:id` 替换为主体 A 的订单 ID，`Order.findById` 无 ownerId 过滤，直接命中并整对象返回 → 正式问题 P0-1。攻击面索引的 `request-params`（line 24）与 `db-query`（line 24）信号与该链路一致。
2. **低权限高功能**：不适用——仓库内不存在管理/审批/配置/导出/删除等高权限动作路由，唯一动作为普通成员级读取（证据：全仓库仅 server.js:23 一个 `app.<method>` 注册）。
3. **跨租户/组织**：不适用——数据模型无 tenant/org 字段（schema 仅 ownerId/items/total），横向对象替换（反例 1）即为其等价形态且已判未绑定。
4. **对象属性越权**：并入 P0-1——对象本身已未绑定，`res.json(order)` 整对象返回（含 ownerId/items/total）无字段白名单，属性级最小化在 P0-1 建议中一并给出。
5. **批量与嵌套资源**：不适用——无批量标识入口与嵌套子资源路由（证据：仅 `app.get('/orders/:id')` 一条路由）。
6. **替代执行路径**：不适用——无列表/搜索/导出/下载/缓存/异步任务/消息消费/内部 RPC/旧版本接口（证据：全仓库扫描，出站客户端、child_process、fs、消息队列均不存在）。

**未闭合入口与外部依赖**：无（唯一入口已入台账）。

**结论边界**：本仓库每个「入口 × 受保护动作」均有绑定结论且每个适用反例均有阻断证据或缺口记录，因此越权结论成立（存在 1 项未绑定正式问题）。`requireLogin` 桩本身（Authorization 头值从不校验、身份硬编码）为文件注释明示的认证层示意，按采信口径不单列为认证绕过问题；但需声明：该桩若被原样部署即为认证缺失，采信依据仅为注释声明，上线前必须替换为真实认证实现（已并入 P0-1 建议的验证方案）。

## 🔴 P0 严重问题

> P0 五项硬门槛（生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布）逐项核验：本条入口注册与装配（路由注册 server.js:23 + `app.listen(3000)` server.js:29 + `package.json` `main=server.js`）均由仓库证据闭合，满足生产可达；入口/主体/资源/决策点/Sink/缺失控制六要素静态闭环；跨用户订单数据可被任意登录用户枚举读取，属事故级；决策点无任何对象级防护；必须阻断发布。五项全部满足。

---

### P0-1 | [维度6-安全] GET /orders/:id 查询无 ownerId 主体绑定，任意登录用户可横向读取他人订单（BOLA/IDOR）

**位置**：server.js:24（代表处；同类问题共 1 处，即该唯一查询点）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：`GET /orders/:id` 以客户端可控的路径参数 `req.params.id` 直接 `Order.findById` 定位订单，查询条件不含任何主体绑定字段（schema 已定义 `ownerId` 却从未参与查询），仅凭登录态即放行，同角色用户替换订单 ID 即可读取他人订单。

**证据**：

```javascript
// server.js:9-14 —— 数据模型具备主体绑定字段
const orderSchema = new mongoose.Schema({
  ownerId: String,      // ← 属主字段已存在，但下方查询从未使用
  items: [String],
  total: Number,
});
const Order = mongoose.model('Order', orderSchema);

// server.js:17-21 —— 认证层示意：仅校验登录态
function requireLogin(req, res, next) {
  if (!req.headers.authorization) return res.status(401).json({ error: 'login_required' });
  req.user = { id: 'u_1001', role: 'member' };   // ← 主体已解析，但从未参与资源定位
  next();
}

// server.js:23-27 —— 决策点与 Sink
app.get('/orders/:id', requireLogin, async (req, res) => {
  const order = await Order.findById(req.params.id);   // ← 仅按对象 ID 查询，无 { _id: req.params.id, ownerId: req.user.id } 主体绑定
  if (!order) return res.status(404).json({ error: 'not_found' });
  res.json(order);                                     // ← 整对象返回（含 ownerId/items/total），无字段白名单
});

// server.js:29 —— 装配与监听（生产可达证据）
app.listen(3000);
```

**安全规则 ID**：CCR-NODE-BOLA-001

**标准映射**：OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639

**检测方式**：semantic

**证据状态**：静态已证实——入口（路由注册 + listen 装配）、主体（`req.user`，server.js:19）、资源（`req.params.id`，server.js:24）、决策点（`requireLogin` 仅登录校验，server.js:17-21）、Sink（`Order.findById` + `res.json(order)`，server.js:24-26）、缺失控制（查询条件无 owner/tenant 绑定）在仓库内全部闭合，无依赖外部配置的未决环节。

**主体/资源/决策链**：
- 主体：`req.user`（id `u_1001`、role `member`），由 `requireLogin` 注入；值为服务端硬编码示意（非客户端输入），按注释采信认证层已完成——无论主体具体是谁，结论不变：任何通过登录校验的主体都命中同一无绑定查询。
- 受保护动作：订单详情读取（受限数据读取）。
- 资源与标识来源：Order 文档，标识 `_id` 来自 `req.params.id`（路径参数，客户端完全可控）。
- 授权证据与决策点：唯一授权证据是登录态存在性（Authorization 头非空，server.js:18）；不存在对象级、属主级、租户级或属性级判断。
- owner/tenant/org/role/scope 绑定结果：**未绑定**（ownerId 字段存在但未进入查询条件；无 tenant/org 概念；role 未参与任何判断）。
- 最终 Sink：`Order.findById(req.params.id)` 命中任意订单 → `res.json(order)` 整对象响应。

**未授权路径与防护**：最短路径——主体 B（同角色 member）携带任意非空 Authorization 头 `GET /orders/{A 的订单 _id}` → `requireLogin` 放行 → `Order.findById` 无主体过滤命中 A 的订单 → 整对象返回（200）。现有防护及限制：仅存在登录门槛（401），对对象级访问零约束；`_id` 为 Mongoose ObjectId，不可预测性不能作为授权证据（框架明确：不可预测 ID 不构成防护）；仓库内无网关/RLS/行级策略可依赖。404 分支仅覆盖对象不存在，不产生拒绝授权语义。

**影响**：任意登录用户可枚举/读取全部用户的订单数据（属主标识、商品明细、金额），构成系统性跨用户数据泄露（水平越权批量读取面）；订单金额与购买记录属敏感业务数据，泄露达事故级；同时整对象返回无字段最小化，属性级暴露随对象级失守一并成立。必须阻断发布。

**建议**：
1. 查询条件强制并入主体绑定（修复后示例）：

```javascript
app.get('/orders/:id', requireLogin, async (req, res) => {
  const order = await Order.findOne({ _id: req.params.id, ownerId: req.user.id }); // ← 属主绑定进入查询条件
  if (!order) return res.status(404).json({ error: 'not_found' }); // 未命中（含他人订单）统一 404，避免存在性枚举
  res.json(pickOrderFields(order)); // ← 响应字段白名单（如仅 items/total），不回显 ownerId
});
```

2. 每个对象级入口单独授权，不能因登录即放行；未来新增列表/批量/导出/嵌套资源入口时逐项复用同一绑定条件（批量逐项校验，不能用「其中一项有权」代表整批）。
3. 将示意 `requireLogin` 替换为真实认证实现（校验 Authorization 头凭据并解析真实主体），删除硬编码身份。
4. 增加鉴权拒绝（404/403）的安全审计日志（主体标识 + 资源 ID + 时间），满足可追责。
5. 验证方案（非破坏性权限矩阵，测试环境执行）：用户 A 创建订单 → 用户 B（同角色）以 A 的订单 ID 请求，预期 404/403、实际当前代码 200 即复现；修复后同用例应拒绝；补充「无 Authorization 头 → 401」回归项。

---

## 🟠 P1 重要问题

本次未发现满足立案条件的 P1 问题。

## 🟡 P2 一般问题

本次未发现满足立案条件的 P2 问题。

## 🔵 P3 建议

本次未发现满足立案条件的 P3 问题。

## ⚪ 待确认项

本次未发现需要外部证据才能定性的待确认项（P0-1 证据链在仓库内闭合；部署侧无未决依赖）。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3, v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 全仓库唯一身份赋值为 `req.user = { id: 'u_1001', role: 'member' }`（server.js:19，服务端常量，非 req.body/query/header 值）；Authorization 头仅判存在性（server.js:18），其值从未传播进身份/租户上下文；无任何客户端字段覆盖服务端身份的传播链 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 未使用任何会话机制（无 express-session/cookie-parser 依赖，无 `req.session` 读写）；不存在 session 写入 sink |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 无出站 HTTP 客户端（攻击面索引 outbound_clients 为空；server.js 无 fetch/axios/got/http.request 引用），不存在外发 sink |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全仓库无 child_process 引用，不存在 exec/execSync/spawn sink |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2, v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/res.sendFile/res.download/createReadStream 使用，不存在文件路径 sink |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无 lodash.merge/deepmerge/自写递归合并；`express.json()`（server.js:7）解析结果仅用于（不存在的）body 消费，无任何 merge/assign sink 消化请求对象 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 唯一查询 `Order.findById(req.params.id)`（server.js:24）：路径参数恒为字符串，findById 按 ObjectId cast，无法注入 `$ne`/`$gt`/`$where` 等对象操作符；无 `req.body`/`req.query` 整体作为查询条件的写法 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/serialize-javascript/yaml.load 等反序列化入口；跨边界仅 express.json()（JSON.parse 语义，无函数/实例还原） |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639 | semantic | finding_confirmed | 见 P0-1：`Order.findById(req.params.id)` 查询条件无 ownerId/主体绑定，schema 的 ownerId 字段（server.js:10）从未参与查询，同角色替换订单 ID 即达 `res.json(order)` Sink；决策点仅登录校验，未绑定结论由授权面台账差分反例（同角色异对象）证实 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 全仓库唯一路由为普通成员级读取 `app.get('/orders/:id')`（server.js:23），不存在管理/审批/配置/导出/删除等高权限动作 sink，低权限高功能差分反例不适用（无高功能可命中） |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2, v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 豁免证据成立：认证仅依赖 Authorization 请求头存在性（server.js:18），无 cookie 会话（无 cookie-parser/express-session，依赖清单见 package.json:7-10）；且唯一路由为 GET（server.js:23），无状态变更端点——纯头认证 + 无写接口，CSRF 向量不成立（非默认豁免，已给出代码证据） |

**排除控制披露（not_applicable，不进入 N 的 A-D 对账）**：

- CCR-NODE-BFFHEADER-001（客户端请求头批量透传到上游服务）：resolver 因激活 profile 为 `node-api`（非 node-bff）排除，排除数计入 E=1。代码复核无语义提升：仓库不存在出站 HTTP 客户端与请求头转发路径（见 SSRF 行证据），该控制风险在本仓库不可达，维持不适用。

**说明**：`static_unsupported` 为 0（所有适用控制均可在本仓库静态闭合结论）；`external_evidence_missing` 为 0（P0-1 的证据链完全闭合于仓库内，无依赖网关/策略中心/RLS 的未决项）。控制覆盖为覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明。

## 🎯 修复优先级

- **P0 - 立即修复**：P0-1（CCR-NODE-BOLA-001）——`GET /orders/:id` 查询并入 `ownerId: req.user.id` 绑定 + 未命中统一 404 + 响应字段白名单；同步替换示意认证桩并补鉴权拒绝审计日志。修复前阻断发布。
- **P1 - 尽快修复**：无。
- **P2 - 计划修复**：无。
- **P3 - 可选优化**：无（提交 lockfile 以支撑后续依赖审计可作为工程改进，但不构成本模式正式问题）。

## 📝 总结

- **一句话架构判断**：单路由 Express + Mongoose 订单查询服务，认证层为示意桩、授权层缺失对象级绑定，安全控制整体未建立。
- **本次模式核心判断**：唯一入口的安全契约中，登录态是全部授权证据——`Order.findById(req.params.id)` 无主体绑定即达整对象响应，水平越权（BOLA）证据链静态闭合，定 P0 且必须阻断发布；其余 10 条适用控制（注入/SSRF/命令/路径/反序列化/身份覆盖/会话/垂直越权/CSRF）经逐条排查均无发现，冻结控制对账 11 = 1 + 10 + 0 + 0。
- **3 个关键行动项**：
  1. `Order.findOne({ _id: req.params.id, ownerId: req.user.id })` 并对未命中统一返回 404（含他人订单），阻断存在性枚举。
  2. 以真实认证实现替换 `requireLogin` 示意桩（校验凭据、解析真实主体），并移除硬编码身份。
  3. 上线前在测试环境执行权限矩阵用例（同角色异对象必须拒绝、无凭据必须 401），并补齐鉴权拒绝审计日志后再发布。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit

## 📋 覆盖情况

- 已审文件：2/2（server.js 30 行、package.json 12 行），无跳过文件。
- 逐文件说明：`server.js`——完整阅读并完成授权面台账与 11 条控制结论；`package.json`——依赖与入口取证（main=server.js，express/mongoose，无 lockfile）。
- 审查输入对齐：本轮冻结 controls/surface 的 `review_input_sha256=11c378c40c97ea8c6a7a113f4b49d4724bba4c3515b51a628304b015146127d9` 与本报告覆盖范围一致。
