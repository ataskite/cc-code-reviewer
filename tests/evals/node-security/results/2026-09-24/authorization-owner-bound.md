# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量（单 Agent）
- 审查模式：security（frontend / Node.js API，激活 security profile：node-api）
- 审查范围：`tests/evals/node-security/authorization/owner-bound` 全部生产源码与伴随配置（server.js、package.json），文件覆盖率 2/2（生产源码 1/1）
- 语义增强：未启用（本轮未使用 LSP 语义查询，逐文件静态精读；Node 攻击面索引仅作导航候选，非发现清单）
- 冻结适用控制：`/tmp/cc-eval-20260923/artifacts/authorization-owner-bound.controls.json`（11 条适用 / 1 条排除，与 review_input_sha256=5d8831a5… 绑定）
- 攻击面索引：`/tmp/cc-eval-20260923/artifacts/authorization-owner-bound.surface.json`（entries=1 路由、sensitive_sinks=1 db-query、outbound_clients=[]、identity_sources=[]）
- 启用维度：1、4（仅配置安全）、5（仅注入/越权）、6、9（仅敏感信息泄露）、11（仅鉴权/错误信息）
- 跳过维度：2、3、7、8、10、12
- 检测到的技术栈：Node.js + Express ^4.18.0 + Mongoose ^7.0.0（无 lockfile、无 engines.node 声明、无测试代码）
- 项目 ignore 状态：未配置
- 网络访问：零（仅本地文件审查）

## 📊 执行摘要

- **整体结论**：未发现正式问题。本仓唯一受保护动作（`GET /orders/:id` 读取订单详情）的主体—对象绑定在授权决策点（Mongo 查询条件）生效：`ownerId = 当前登录主体` 与 `_id` 同时并入查询，非本人订单与不存在订单统一按 404 返回，四类核心授权差分反例均被阻断；注入（命令/路径/原型/NoSQL 操作符/反序列化）、SSRF、会话 mass assignment 与 CSRF 面在本仓代码中均不存在可达 sink。另有 2 个待确认项（认证层示意桩、无效 ObjectId 触发未处理 Promise 拒绝），其定级依赖仓库外运行配置证据，按证据规则单列，不计入正式问题。
- **最高风险点**：待确认-1（认证层为存在性桩 + 硬编码登录主体，真实凭据校验在仓库外——若按当前代码原样部署即构成认证绕过，P0 待验证）。
- **各级别计数**：

| 级别 | 数量 |
|---|---|
| P0（严重） | 0 |
| P1（重要） | 0 |
| P2（一般） | 0 |
| P3（建议） | 0 |
| 待确认项 | 2 |
| **正式问题总计** | **0** |

- 评分（5 分制，基于本仓静态证据）：安全性 4 / 性能 4 / 可维护性 3 / 技术债务 3。扣分点均在待确认项与覆盖限制中披露（示意认证桩、错误处理缺口、无 lockfile）。

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认完成全部排查：授权绑定、注入、SSRF、路径穿越、会话写入、CSRF 等 11 条冻结适用控制逐一取证后均未成立正式发现；两项高危候选因缺运行配置/仓库外证据降为待确认项（见下）。

## 🟠 P1 重要问题

未发现 P1 问题。

## 🟡 P2 一般问题

未发现 P2 问题。

## 🔵 P3 建议

未发现 P3 问题。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 认证层为示意桩：仅校验 Authorization 头存在性并硬编码登录主体（P0 待验证）

**位置**：server.js:18-22（同类仅此一处）

**置信度**：低（部署相关） | **所属维度**：维度6-安全

**依据**：
```js
// server.js:17-22 —— 注释自述「认证层示意：解析登录态」
function requireLogin(req, res, next) {
  if (!req.headers.authorization) return res.status(401).json({ error: 'login_required' }); // ← 仅校验头存在性，不校验凭据内容/签名/有效期
  req.user = { id: 'u_1001', role: 'member' };                                               // ← 登录主体硬编码，与所携凭据无任何绑定
  next();
}
```

**证据状态**：待确认项——真实凭据校验（JWT 签名验证 / session 存储查找等）与部署装配证据在仓库之外，静态无法闭合。

**主体/资源/决策链**：主体 `req.user.id`（值为硬编码 `u_1001`，来源是服务端示意桩而非凭据校验结果）；受保护动作：读取订单详情；资源：`req.params.id` 指向的 Order 文档；授权决策点：server.js:25 查询条件 `ownerId: req.user.id`；最终 Sink：Mongo `Order.findOne` → `res.json(order)`。授权决策本身绑定正确（见 BOLA 台账行），本项质疑的是「主体」的成色。

**未授权路径与防护**：最短路径——无凭据客户端对 `GET /orders/{任意订单号}` 携带任意非空 `Authorization` 头值 → `requireLogin` 放行并以 `u_1001` 身份执行查询 → 可读取 u_1001 的全部订单。现有防护：无（桩不做任何凭据验证）。注意：夹具注释「认证层示意」表明这是脚手架，但仓库内没有任何证据证明生产装配了真实认证层。

**待确认原因**：凭据校验实现、入口装配与部署配置（网关/认证服务）均不在本仓，无法按框架要求闭合「生产可达性 + 防护状态」证据；同时它不是冻结 11 条控制中任何一条的违反（IDENTITY-001 针对客户端字段覆盖身份，此处不存在覆盖路径），故不入正式计数。

**建议的验证方式**：最小权限矩阵用例（非破坏性，仅在测试环境）：① 无 `Authorization` 头 → 预期 401；② 携带伪造/过期令牌 → 预期 401（当前代码预期失败：均放行为 u_1001）；③ 合法用户 A 读取用户 B 订单 → 预期 404（当前代码预期通过，验证绑定不受影响）。同时核对部署配置中真实认证中间件的装配位置。修复方向：以 JWT 签名校验或 session 查找替换桩，保持 `ownerId` 绑定逻辑不变。

---

### 待确认-2 | [维度6-安全] 无效订单号触发 CastError 未处理拒绝：请求无响应，现代 Node 默认策略下进程崩溃（P0 待验证）

**位置**：server.js:24-28（同类仅此一处）

**置信度**：低（运行时相关） | **所属维度**：维度6-安全（可用性/DoS 向）

**依据**：
```js
// server.js:24-28 —— async 路由无 try/catch，全仓亦无统一错误中间件
app.get('/orders/:id', requireLogin, async (req, res) => {
  const order = await Order.findOne({ _id: req.params.id, ownerId: req.user.id }); // ← 非法 ObjectId（如 "zz"）触发 mongoose 7 CastError，await 抛出的拒绝无人捕获
  if (!order) return res.status(404).json({ error: 'not_found' });
  res.json(order);
});
// package.json:8-9 —— "express": "^4.18.0"（4.x 不自动捕获 async 拒绝）、"mongoose": "^7.0.0"；无 engines.node 声明
```

**证据状态**：待确认项——崩溃放大效果依赖运行时配置（Node 主版本 / `--unhandled-rejections` 策略 / 进程守护），仓库无 `engines.node` 与部署证据，静态无法闭合。仓库内可静态确证的部分：Express 4 下该请求永远得不到响应（连接挂起直至超时），且每个畸形请求廉价地占用一个 socket。

**主体/资源/决策链**：不适用（本项不是授权/越权缺陷，而是可用性缺陷；资源为服务进程自身与连接资源）。

**未授权路径与防护**：最短路径——任意客户端（授权头任意值即可通过示意桩）请求 `GET /orders/zz` → mongoose 对 `_id` 做 ObjectId cast 失败 → `findOne` 返回被拒绝的 Promise → async 处理器拒绝未被 Express 4 捕获 → Node ≥15 默认 `unhandled-rejections=throw` 导致进程退出（Node <15 仅告警）。现有防护：无（无 try/catch、无错误中间件、无 `:id` 格式预校验、无 engines 约束）。

**待确认原因**：事故级定级（进程崩溃 = 全站不可用）所需的运行配置证据缺失；按框架规则「事故级风险尚缺运行配置证据：待确认并标注 P0 待验证」。

**建议的验证方式**：测试环境发送 `GET /orders/zz`（携带任意 `Authorization` 头），观察：① 请求是否长期无响应；② Node ≥15 环境进程是否以 unhandledRejection 退出。修复方案不依赖验证结论，建议直接实施：入口预校验 `mongoose.isValidObjectId(req.params.id)` 不通过即返回 400，并为 async 路由补 try/catch 或统一错误中间件（或升级 Express 5）；同时在 package.json 固定 `engines.node`。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 1 / 未绑定 0 / 外部证据缺失 0 / 不适用 0，`1 = 1 + 0 + 0 + 0`。
- 本仓入口枚举：HTTP 路由 1 个（GET /orders/:id）；无消息/任务/回调/GraphQL/WebSocket/文件 URL/内部 RPC 入口（surface entries 与逐文件精读一致）。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| `app.get('/orders/:id', requireLogin, …)` server.js:24 | `req.user.id` 由服务端 `requireLogin` 派生（示意桩：仅校验 Authorization 头存在性，硬编码 u_1001——真实凭据校验在仓库外，见待确认-1） | 读订单详情（受限数据读取） | `req.params.id`（URL 路径段，恒为字符串） | server.js:25 查询条件并入 `ownerId: req.user.id`，决策点即 Mongo 查询本身；非本人订单 → null → 404 | `Order.findOne` → `res.json(order)` | 已绑定 | 无（服务仅此一路由，无列表/批量/导出/下载/异步/旧版本路径） |

已执行的动作中心差分反例（每行阻断证据或书面不适用理由）：

1. **同角色异对象**：用户 B 携带用户 A 的订单号 → 查询 `{ _id: A订单, ownerId: B }` 无命中 → 404，且与「订单不存在」不可区分（server.js:25-26，不泄露存在性）。**已阻断**。
2. **低权限高功能**：服务无管理/审批/配置/导出/删除等高权限动作，唯一动作为 member 级读取本人订单；HTTP method 变体无其他注册路由可绕。**不适用（无高权限 sink）**。
3. **跨租户/组织**：schema（server.js:10-14）无独立租户/组织字段，`ownerId` 即唯一归属隔离维度且已并入查询；无可替换的第二隔离维度。**不适用（无独立租户维度）**。
4. **对象属性越权**：响应返回文档全字段（`res.json(order)`），但对象已属主隔离且字段（ownerId/items/total/_id）不含跨主体敏感属性或凭据；无写端点，无 mass assignment 面。**阻断成立**。
5. **批量与嵌套资源**：无列表/搜索/批量/导出/嵌套子资源入口。**不适用（无此类入口）**。
6. **替代执行路径**：无异步任务、消息消费、缓存命中、内部/RPC、旧版本或补偿路径；攻击面索引与代码一致。**不适用（无替代路径）**。

- 未闭合入口与外部依赖：① 真实认证与凭据校验实现（示意桩，见待确认-1）；除此之外无——本仓无网关、策略中心、数据库 RLS 或范围外服务的调用依赖。
- 结论边界：唯一「入口 × 受保护动作」已有绑定结论，六类适用反例均有阻断证据或书面不适用理由，**在本仓代码语义内未发现越权问题**；该结论不外推到示意认证层之外的真实身份强度（身份成色由待确认-1 单独跟踪）。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：0
- 已检查无发现：11
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 11 = 0 + 11 + 0 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 身份仅由服务端 requireLogin 派生（server.js:18-22）；req.body/query/header 无任何字段进入 req.user 或租户上下文（surface identity_sources=[]），req.params.id 仅作资源定位不作身份。桩本身凭据强度问题见待确认-1（非本控制的覆盖路径） |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全仓无会话机制：依赖仅 express+mongoose（package.json:7-10），无 express-session/req.session 读写路径，不存在会话批量写入 sink |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 全仓无 fetch/axios/got/http.request 等外发客户端（surface outbound_clients=[]），不存在用户可控外发目标 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全仓无 child_process 引用，无 exec/execSync/spawn 调用，无命令执行 sink |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 全仓无 fs/res.sendFile/res/download 调用与静态目录服务，无文件路径拼接入口 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | express.json() 解析结果（server.js:8）未进入任何递归合并/extend/lodash.merge，__proto__/constructor 键无传播链 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 查询条件逐字段显式构造（server.js:25）：_id 取自 req.params 路径段（恒为字符串，无法携带 $ 前缀操作符对象），ownerId 取自服务端身份；无 req.body/query 对象整体入查询 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化入口；请求体仅经 express.json()（JSON.parse 语义，不还原函数/实例） |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 防护成立并逐条举证：唯一受保护动作 GET /orders/:id 的查询条件并入 ownerId=req.user.id（server.js:25，生效点即 Mongo 查询本身）；同角色异对象差分反例返回 404 且与不存在订单不可区分（server.js:26）；授权面台账结论=已绑定（见「授权面覆盖」） |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 服务仅 1 个 member 级只读路由（server.js:24），无管理/审批/配置/导出/删除等高权限动作 sink，垂直越权反例不适用（无更高权限功能可达） |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 豁免证据可见：认证仅读 req.headers.authorization（server.js:19，Bearer 式头），依赖中无 cookie-parser/express-session 即无 cookie 会话；且唯一路由为 GET 只读，无状态变更端点 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | resolver 排除（激活 profile=node-api，node-bff 未启用）；本仓亦无外发 HTTP 客户端，不存在请求头透传面 |

## 🔍 覆盖限制与未审查范围

- **已重点检查**：唯一路由的完整安全契约（入口 → 主体 → 动作 → 资源 → 决策点 → Sink → 默认行为）；11 条冻结适用控制逐一取证并举证防护位置与生效点；授权面二次扫描（动作中心台账 + 六类差分反例）已完成。
- **未充分覆盖**：依赖漏洞无法形成确定性结论——仓库未提交 lockfile，按依赖风险结论规则仅作披露，不下「版本有/无漏洞」结论；无测试代码可核；未做任何运行时/网络验证（纯静态审查）。
- **限制说明**：本轮未启用 LSP 语义查询，语义类结论（BOLA/BFLA/IDENTITY）基于逐文件精读并与冻结攻击面索引交叉核对（索引 entries/sensitive_sinks 与代码一致）；攻击面索引仅导航，未作为发现清单使用。

## ✅ 最佳实践亮点

- 属主绑定下沉到查询条件（`{ _id, ownerId }` 一体过滤），非本人订单与不存在订单统一 404，避免对象存在性枚举 oracle（server.js:25-26）。

## 📝 总结

- 一句话架构判断：极简单路由 Node API，授权模型为「登录 + 属主并入查询」的资源级绑定，绑定实现正确。
- 本次模式核心判断：11 条冻结适用控制全部 checked_no_finding（防护成立处均已举证位置与生效点），0 正式问题、2 待确认项；「未发现越权问题」仅在本仓代码语义内成立，不外推到示意认证层的真实身份强度。
- 关键行动项：① 以真实凭据校验替换 requireLogin 示意桩，保持 ownerId 绑定不变（待确认-1，P0 待验证）；② 为 `:id` 增加 ObjectId 预校验或 async 错误捕获，消除 CastError 未处理拒绝（待确认-2，P0 待验证）；③ 提交 lockfile 并固定 engines.node，使依赖与运行时结论可确定性复检。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
