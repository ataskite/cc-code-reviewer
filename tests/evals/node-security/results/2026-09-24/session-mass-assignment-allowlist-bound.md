# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查范围：项目全部生产源码（正式源码 `server.js`；伴随文件 `package.json`）
- 审查模式：security（frontend/Node，激活 profile：node-api）
- 审查模型：单 Agent 静态审查；无语义 LSP 注入，已按框架披露降级为静态逐行检索
- 启用维度：1 正确性、4（配置安全子项）、5（注入/越权子项）、6 安全（全深度）、9（敏感信息泄露子项）、11（鉴权/错误信息子项）
- 跳过维度：2 类型安全、3 代码质量、7 性能、8 副作用清理、10 测试质量、12 设计系统
- 检测到的技术栈：Node.js + Express 4.18 + express-session 1.17 + joi 17（无构建链，无浏览器端 bundle 代码）
- 项目 ignore 状态：未配置（`.cc-code-reviewer/ignore/issues.yml` 不存在）
- 文件覆盖率：正式源码 1/1（100%）；伴随文件 1/1（package.json）
- 冻结适用控制：11 条（resolver 按 node-api profile 与信号确认）；排除 1 条（CCR-NODE-BFFHEADER-001，profile 未启用）
- 攻击面索引：files_scanned=1，与实际源码一致（仅导航候选，不作为发现清单）

## 📊 审查范围说明

- **项目类型**：Node.js API 服务（PROJECT_TYPE=node，security_profile=node-api）
- **审查范围**：`server.js` 全量 31 行逐行审阅；`package.json` 依赖与入口声明；冻结 controls 11 条逐条结论；Node 攻击面索引交叉核对（入站路由 2 条、会话写入 sink 2 处、无外发客户端）
- **审查基准路径**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/session-mass-assignment/allowlist-bound
- **覆盖方式**：全量阅读全部生产源码后，按「入口 × 受保护动作」完成授权面二次扫描与六类差分反例
- **未纳入范围**：无测试目录、无 CI/容器配置、无 lockfile（见覆盖限制）

## 📊 执行摘要

- **整体结论**：本服务的核心安全控制（会话 mass assignment 防护）成立——请求体先经 joi schema `unknown(false)` 白名单校验，会话字段再逐字段显式赋值，`isAdmin`/`role`/`userId` 等白名单外键无法进入会话；主要缺口为 Cookie 会话写端点缺少 CSRF 防护与会话签名密钥硬编码。
- **最高风险点**：POST /api/profile 可被第三方站点跨站触发（P1-1）。
- **评分**：安全性 B-（SESSION-001 防护成立；CSRF 与密钥管理缺口）/ 性能 不适用（security 模式）/ 可维护性 B / 技术债务 低。
- **问题汇总表**：

| 级别 | 数量 | 编号 |
|---|---|---|
| P0 | 0 | — |
| P1 | 1 | P1-1 |
| P2 | 1 | P2-1 |
| P3 | 0 | — |
| 待确认 | 1 | 待确认-1 |

- **总计正式问题数**：2（P0+P1+P2+P3）。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：全部正式源码逐行阅读（server.js 31 行）；两条路由的完整入口→身份→动作→资源→Sink 链；会话写入 sink（server.js:21-22）与 schema 校验生效点（server.js:12-15、18-19）；冻结 11 条控制逐条取证；授权面台账与六类差分反例。
- **未充分覆盖**：依赖版本漏洞——仓库无 lockfile，`express ^4.18.0`、`express-session ^1.17.0`、`joi ^17.9.0` 无法形成确定性漏洞结论，按依赖风险结论规则归为扫描建议（提交 lockfile 并以 `npm ci` + 审计验证）；部署拓扑与网关认证（见待确认-1）。
- **限制说明**：本次无语义 LSP，全部结论来自静态逐行阅读与冻结攻击面索引交叉核对；攻击面索引仅覆盖 1 个文件，与实际源码集合一致，无遗漏信号。

## 🔐 授权面覆盖（仅 Security 模式强制）

- **授权面台账**：共 2 行；已绑定 2 / 未绑定 0 / 外部证据缺失 0 / 不适用 0，且 2 = 2 + 0 + 0 + 0。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|------|----------------|------|---------------------|--------------------|-----------|----------|----------|
| POST /api/profile（server.js:17） | express-session Cookie 会话（匿名自助会话，server.js:10） | 写（会话资料字段 displayName/locale） | 当前请求自身会话对象；无外部资源标识，无 path/query/body 对象 ID | joi schema `unknown(false)` 字段白名单（server.js:12-15）在校验点 server.js:18-19 生效，拒绝一切白名单外键 | req.session.displayName / req.session.locale 写入（server.js:21-22） | 已绑定 | 无（仓库内无批量/导出/下载/异步/内部变体） |
| GET /api/me（server.js:27） | 同上 | 读（自身会话资料字段） | 当前请求自身会话字段；无外部资源标识 | 读取范围由 `req.session` 自身限定（server.js:28），无跨主体取数路径 | res.json 响应（server.js:28） | 已绑定 | 无 |

- **已验证反例**：
  1. 同角色异对象：不适用——不存在跨主体资源标识，读与写均限定在请求自身会话内。
  2. 低权限高功能：不适用——代码内不存在管理/审批/配置/导出/删除等高权限动作，两路由均为自助资料读写。
  3. 跨租户/组织：不适用——无租户/组织概念，无可被请求字段覆盖的受信上下文。
  4. 对象属性越权（mass assignment）：**已验证阻断**——构造 POST /api/profile 携带 `isAdmin`/`role`/`userId` 等额外键时，PROFILE_SCHEMA（`unknown(false)`，server.js:15）在 server.js:18-19 校验失败返回 400；会话写入点（server.js:21-22）仅显式接受 `displayName`、`locale` 两个白名单键，代码内无其他会话写入路径，绕过不成立。
  5. 批量与嵌套资源：不适用——无批量标识集合与父子资源换绑面。
  6. 替代执行路径：不适用——仓库内仅两个路由，无列表/导出/下载/缓存/异步任务/消息/内部 RPC 变体。
- **未闭合入口与外部依赖**：仓库内无任何认证中间件与网关配置证据；若生产形态以真实用户身份运行，认证边界依赖外部网关（对应待确认-1）。代码内部无其他未闭合入口。
- **结论边界**：本范围内每个「入口 × 受保护动作」均有绑定结论，且每个适用反例均有阻断证据或不适用理由；代码范围内未发现越权问题。

## 🔴 P0 严重问题 (Critical Issues)

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## 🟠 P1 重要问题 (Major Issues)

---

### P1-1 | [维度6-安全] Cookie 会话写接口 POST /api/profile 缺少 CSRF 防护（无 token、无 SameSite、无 Origin 校验）

**位置**：server.js:10、17-25（同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：依赖 express-session Cookie 会话的状态变更接口 POST /api/profile 没有 CSRF token、Origin/Sec-Fetch-Site 校验，会话 Cookie 也未设置 `sameSite` 属性，第三方站点可携带受害者浏览器凭据触发跨站写操作。

**证据**：
```js
app.use(session({ secret: '***', resave: false, saveUninitialized: false }));      // ← server.js:10 会话 Cookie 未配置 sameSite/secure
app.post('/api/profile', (req, res) => {                                          // ← server.js:17 状态变更端点（POST 写会话）
  const { value, error } = PROFILE_SCHEMA.validate(req.body);                     // ← server.js:18 仅字段白名单校验，无任何 CSRF 判定
  if (error) return res.status(400).json({ error: 'invalid_profile' });
  if (value.displayName !== undefined) req.session.displayName = value.displayName; // ← server.js:21 跨站可触发的会话写入（敏感效果）
```

**安全规则 ID**：CCR-NODE-CSRF-001

**标准映射**：OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2, v5.0.0-V3.5.2 / CWE-352

**检测方式**：config

**证据状态**：静态已证实——四项必需证据在仓库内闭合：入口（server.js:17 POST 路由）、认证方式（server.js:10 express-session Cookie 会话）、状态变更（server.js:21-22 会话字段写入）、控制缺失（全仓库无 csurf/CSRF token 校验/Origin 检查，session 选项无 `cookie.sameSite`）。

**主体/资源/决策链**：主体为持有会话 Cookie 的任意访客（本服务无登录概念，会话为匿名自助会话）；受保护动作为自身会话资料写入；资源为当前会话对象（无跨主体资源标识）；授权决策点不存在（端点无鉴权，属自助资料写，schema 仅约束字段集合而非请求来源）；最终 Sink 为 `req.session.displayName`/`req.session.locale` 写入。

**未授权路径与防护**：最短路径为第三方恶意页面以 form/fetch 携 Cookie 跨站 POST `/api/profile` 直达会话写入，全程无阻断点；现有防护仅有 joi 字段白名单（只限制可写字段集合，不限制请求来源）与浏览器默认 SameSite 策略（非服务端控制、跨浏览器不一致且存在 Lax 宽限例外），均不能证明阻断跨站提交。

**影响**：恶意页面可诱导已建立会话的浏览器静默改写受害者会话内 `displayName`（最长 64 字符）与 `locale`；displayName 常被下游展示/通讯消费，可被用于社会工程学内容投毒，locale 变更可影响后续内容呈现。影响限于白名单资料字段、未达事故级，按目录 severity_candidate 定 P1。

**建议**：为会话 Cookie 显式设置 `cookie: { sameSite: 'lax'|'strict', httpOnly: true, secure: true }`；或在该写端点增加 CSRF token 双重提交 / 校验 `Origin` 与 `Sec-Fetch-Site` 头；若迁移为纯 Authorization Bearer 头认证可豁免，但须在台账留存无 Cookie 会话的证据。

---

## 🟡 P2 一般问题 (Minor Issues)

---

### P2-1 | [维度6-安全] 会话签名密钥硬编码在源码中

**位置**：server.js:10（同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：express-session 的签名密钥以字符串字面量硬编码于源码（值呈占位样式，已按脱敏规则以 `***` 掩码），任何可读取仓库的人都能获得该密钥并用于伪造会话签名。

**证据**：
```js
app.use(session({ secret: '***', resave: false, saveUninitialized: false }));  // ← server.js:10 硬编码会话签名密钥（值以 *** 掩码，仅描述形态）
```

**证据状态**：静态已证实（源码字面量直接可见，无环境变量或配置注入）。

**主体/资源/决策链**：不适用（密钥管理类问题，不涉及主体—资源授权链）。

**未授权路径与防护**：不适用（同上）。

**影响**：密钥泄露后攻击者可离线伪造任意合法签名的会话 Cookie（会话固定/冒充）。本仓库内会话仅承载 `displayName`/`locale` 展示字段且端点本身无鉴权，提权影响链未闭合，故按配置加固定 P2；一旦会话未来引入身份或权限字段，该问题将升级为认证绕过级风险，应前置修复。

**建议**：密钥从环境变量或密钥管理系统注入（如 `secret: process.env.SESSION_SECRET`），仓库内不保留任何真实或占位密钥值；轮换密钥时同步使既有会话失效。

---

## ⚪ 待确认项

---

### 待确认-1 | [维度6-安全] 全部端点未见认证机制，生产身份边界依赖部署拓扑证据

**位置**：server.js:17、27（同类问题共 2 处）

**置信度**：低 | **所属维度**：维度6-安全

**依据**：
```js
app.post('/api/profile', (req, res) => {   // ← server.js:17 路由前无任何认证中间件
app.get('/api/me', (req, res) => {         // ← server.js:27 路由前无任何认证中间件
```

**证据状态**：待确认项——仓库内无认证中间件、网关配置或部署清单可闭合生产身份边界。

**待确认原因**：会话为匿名自助会话（读写均限于访客自身 displayName/locale），代码内不存在因缺认证而受害的跨主体资源，静态证据不足以构成正式越权发现；但若生产形态由网关注入真实用户身份、或将该服务挂接到用户数据面，缺失认证即成为入口级风险，该攻击效果依赖部署拓扑与网关配置，无法从当前仓库闭合。

**建议的验证方式**：确认生产部署拓扑与网关认证配置（该服务前置是否存在认证层）；若以真实用户运行，补充会话身份建立路径（登录/网关注入）后，对身份与越权类控制重新执行差分用例审查。

---

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025, A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3, v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 会话仅存 displayName/locale 展示字段（server.js:21-22）；schema unknown(false) 拒绝 userId/tenantId/role/isAdmin 等任意额外键（server.js:12-15、18-19）；代码内无身份/租户上下文由请求字段构造，也无授权判断消费会话字段 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 防护成立——防护位置：PROFILE_SCHEMA 白名单（server.js:12-15，unknown(false)）；生效点：server.js:18 校验失败即 400 拒绝；会话逐字段显式赋值仅 displayName/locale（server.js:21-22）。无 req.session = req.body、无 for-in 批量写入，全仓库无其他会话写入点 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023, API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 全仓库无外发 HTTP 客户端（require 仅 express/express-session/joi；攻击面索引 outbound_clients 为空；server.js 仅入站路由），不存在外发目标构造点 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 无 child_process 引用与任何命令拼接执行点（全仓库仅 server.js 31 行，require 清单封闭） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2, v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/res.sendFile/res.download 调用，不存在用户输入到文件路径的传播链 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无深合并/extend/defaults 消化 req.body；joi validate 返回净化副本（server.js:18），会话写入为标量逐字段赋值（server.js:21-22），无递归合并点 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/mongoose 等客户端与查询构造，req.body 不进入任何数据库查询条件 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 请求体仅经 express.json()（server.js:9，JSON.parse 语义，不还原函数/实例）；无 node-serialize/yaml.load 等危险反序列化入口 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无按对象 ID 定位的资源访问；GET /api/me 仅读取当前请求自身会话字段（server.js:27-29），POST /api/profile 仅写自身会话（server.js:21-22），无跨主体读取/写入路径，同角色异对象反例不成立 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 代码内不存在管理/审批/配置/导出/删除等高权限动作，两路由均为自助资料读写，低权限高功能反例无目标动作 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2, v5.0.0-V3.5.2 / CWE-352 | config | finding_confirmed | 见 P1-1：POST /api/profile 为 Cookie 会话写端点（server.js:17、21-22），全仓库无 CSRF token/Origin 校验，会话 Cookie 未设置 sameSite（server.js:10）；非纯 Bearer 认证，无豁免证据 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 resolver 判定 profile 未启用（激活 profile 为 node-api）；代码内无上游转发/代理路径（无 outbound 客户端、无请求头透传逻辑），无需语义提升 |

说明：CCR-NODE-SESSION-001 为本服务核心风险面，防护双要件（schema-validation + field-allowlist）均在代码内逐条举证成立；CCR-NODE-CSRF-001 的四项必需证据（entry/auth-mode/state-change/missing_control）全部闭合故确认发现。控制覆盖是覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明。

## ✅ 最佳实践亮点

- 会话写入采用「schema 白名单 + 逐字段显式赋值」双重约束（server.js:12-15、18-22）：`unknown(false)` 从入口拒绝一切白名单外键，会话写入点只接受 `displayName`/`locale`，且 `locale` 进一步用 `valid('zh-CN','en-US')` 枚举收敛——这是 mass assignment 防护的标准正解形态，权限类字段（isAdmin/role/userId）结构性不可达。

## 🎯 修复优先级

- P1 - 立即修复：P1-1 为 POST /api/profile 补 CSRF 防护（sameSite Cookie 或 token/Origin 校验）。
- P2 - 尽快修复：P2-1 会话签名密钥改为环境变量注入并轮换。
- 待确认 - 计划确认：待确认-1 与部署方核对生产认证边界；提交 lockfile 后补依赖确定性审计。

## 📝 总结

- **整体架构判断**：一个极简 Express 会话资料编辑服务，安全面集中在「请求体→会话」单条链路，核心 mass assignment 控制实现正确。
- **本次模式核心判断**：冻结 11 条适用控制中 10 条检查无发现、1 条（CSRF）确认发现；未发现越权与注入类问题，代码内授权面全部已绑定。
- **关键行动项**：1) 补齐 POST /api/profile 的 CSRF 防护与会话 Cookie 安全属性；2) 移除硬编码会话密钥并改环境变量注入；3) 确认生产认证拓扑并提交 lockfile 完成依赖审计。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
