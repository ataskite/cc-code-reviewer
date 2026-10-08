# 代码审查报告 - proxy-capability-vulnerable

## ⚙️ 审查配置快照

生成时间：2026-10-08 02:43 UTC；隔离夹具全量 Security 审查；模型档位 inherit；语义增强 none（实际为静态调用链分析）。项目 node / Express / 原生 node:http。启用维度 1、4 配置、5 注入/越权、6 安全、9 敏感泄露、11 鉴权/错误信息；其余未扫描。ignore 未配置。输入：/tmp/cc-proxy-auth-eval.44sjAD/proxy-capability-vulnerable/review-input.json，selected 2 / excluded 0；源码 server.js 1/1（17 行），配置 package.json 1/1（8 行），全部冻结 selected 文件 2/2，共 25 行，指纹已逐项核对。非批次，没有 run-manifest。

## 📊 执行摘要

代码明确允许匿名请求选择任意内部 HTTP path 和 GET/POST，缺少服务端能力映射与调用者授权；固定连接地址和固定 Host 只约束目标服务，不能约束动作。正式发现 1，待确认 1（P0 0 / P1 1 / P2 0 / P3 0）。安全性 5/10；性能、可维护性、技术债务 N/A（未完整扫描）。未证明真实管理动作或生产数据可达，不定 P0。

## 🔍 覆盖限制与未审查范围

已审 package.json、server.js 的全部选中内容及冻结 surface。无跳过文件。未联网、未运行服务、未安装依赖；无 lockfile，无法定依赖漏洞。真实 Ingress 路由、上游 API/数据权限和公网暴露策略未提供。原生 HTTP 调用不自动跟随响应重定向，不能把 path 字符串宣称成任意主机 SSRF。未见本地 shell、文件、数据库、危险反序列化、日志凭据泄露 Sink。

## 🔐 授权面覆盖

台账共 1 行：已绑定 0 / 未绑定 1 / 外部证据缺失 0 / 不适用 0。

| 入口 | 主体与可信来源 | 动作 | 资源来源 | 决策/执行点 | Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| POST /invoke | 无身份验证；匿名调用者 | orders 虚拟主机全部可选 GET/POST 路径调用 | body.path、body.method、body.data | 仅类型与 startsWith 检查，没有主体×动作拒绝 | http.request / call.end / upstream.pipe(res) | 未绑定：P1-1 | 仅此路由；body.method 是下游方法替代面 |

二次扫描：低权限高功能和 method 变化在本地无能力阻断；同角色异对象、跨租户、对象属性、批量/嵌套反例都能任意携入 body.data，但实际对象和授权效果需要上游实现，不能当作已证实 BOLA；GET/POST 下游替代执行路径同样无逐动作控制。安全契约默认行为：合格 path/method 即外发，缺身份状态不影响执行。

## 🛡️ Security 控制覆盖

- 适用控制：15
- 已发现问题：1
- 已检查无发现：12
- 外部证据缺失：2
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 15 = 1 + 12 + 2 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 profile 排除；实际出站只构造固定 Host，未批量透传客户端头 |
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 未把请求字段赋为主体或租户；只向上游发送业务数据 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 无请求对象到 session 的写入 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | http.request 的 hostname/port/Host 固定，原生客户端不自动跟随重定向；path 权限缺口另见 PROXYCAP |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全部输入仅进入原生 HTTP 客户端，无 shell/child_process Sink |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / ASVS v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/sendFile/download 文件 Sink；HTTP path 不等于文件路径 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无深合并、动态属性赋值或原型写入 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 NoSQL 查询；范围外上游查询实现不可据此断言 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | express.json 解析普通 JSON，无函数或任意类型恢复 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639 | semantic | external_evidence_missing | 上游对象、响应字段、owner/tenant 过滤均未提供；需测试服务资源授权矩阵 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | external_evidence_missing | 上游管理动作与授权策略未提供；需下游路由及普通主体访问矩阵，见待确认-1 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / ASVS v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 本地没有 Cookie 会话或隐式浏览器凭据；匿名代理缺口不是 CSRF |
| CCR-NODE-HOSTROUTE-001 | 客户端控制出站 Host 或路由身份 | OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346 | taint | checked_no_finding | server.js:11-12 固定连接 ingress 与 orders Host，无客户端 headers/options 合并 |
| CCR-NODE-PROXYCAP-001 | 客户端扩大代理目标、路径或方法能力 | OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441 | semantic | finding_confirmed | 见 P1-1：匿名调用者可选择全部斜杠起始路径及 GET/POST，缺逐能力授权 |
| CCR-NODE-JWTAUTH-001 | JWT 身份接受路径缺少完整验证 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V9.1.1 / ASVS v5.0.0-V9.1.2 / ASVS v5.0.0-V9.1.3 / ASVS v5.0.0-V9.2.1 / ASVS v5.0.0-V9.2.3 / CWE-347 | semantic | checked_no_finding | 读取全部身份路径，无 JWT 接收、decode、verify 或 claims 消费 |
| CCR-NODE-PROXYTRUST-001 | 代理来源及转发头被错误用于安全决策 | OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346 | config | checked_no_finding | 无 trust proxy 配置，亦无 forwarded/ip/hostname/protocol 安全决策 |

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## 🟠 P1 重要问题

### P1-1 | [维度6-安全] 匿名调用者可扩大固定内部服务的路径与方法能力

**位置**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/proxy-capability/vulnerable/server.js:7

**置信度**：高 | **所属维度**：维度6-安全

**问题**：任意匿名请求均能调用固定 orders Host 下任意斜杠开头的路径，且自行选择 GET/POST 与请求数据，没有能力表或调用者授权。

**证据**（server.js:5-15）：
```js
app.post('/invoke', (req, res) => {
  const rb = req.body;
  if (!['GET', 'POST'].includes(rb.method) || typeof rb.path !== 'string' || !rb.path.startsWith('/')) {
    return res.sendStatus(400);
  }
  const call = http.request({
    hostname: 'ingress.example.test', port: 80, path: rb.path, // ← 客户端选择全部路径
    method: rb.method, headers: { Host: 'orders.example.test' } // ← 方法集合不是逐能力授权
  }, upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify(rb.data));
```

**影响**：应用代理的动作边界缺失；如上游存在内部管理/导出接口，调用者可借该代理触达。该高危下游效果尚未被夹具证明。

**建议**：由服务端固定能力表绑定 service、Host、path 模板、method 和参数 schema；在外发之前验证可信主体有本次能力权限，未知能力默认拒绝。

**证据状态**：静态已证实；路由注册、listen 与 http.request 已闭合本地代理能力缺口，没有证明真实生产管理 API。

**主体/资源/决策链**：匿名主体 → body 的路径/方法/数据 → 只检查形式 → 固定 ingress/orders 下游调用；无 owner/tenant/role/scope 决策。

**未授权路径与防护**：POST /invoke → 校验合格 → http.request；固定 Host 与两种方法限制阻止任意服务/其他方法，但不阻止未获授权路径。

**验证方案**：只在授权的本地测试环境用捕获请求的 stub 上游，无生产凭据；匿名请求传 GET /unlisted-probe，当前代码应发出该请求，修复后须 401/403；未知能力、客户端 path/method/options 覆盖均应拒绝或不影响固定能力。全部只读，不用真实管理路径，无持久化清理需求。

**安全规则 ID**：CCR-NODE-PROXYCAP-001
**标准映射**：OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441
**检测方式**：semantic

## 🟡 P2 一般问题

无。

## 🔵 P3 建议

无。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 下游对象与高权限动作的实际越权效果缺少证据

**位置**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/proxy-capability/vulnerable/server.js:11
**置信度**：低 | **所属维度**：维度6-安全
**依据**：
```js
hostname: 'ingress.example.test', port: 80, path: rb.path, // ← 上游对象/动作由请求决定
method: rb.method, headers: { Host: 'orders.example.test' }
```
**待确认原因**：没有 Ingress 映射、orders API 实现、对象/租户关系或服务身份信任策略，无法证明特定 BOLA/BFLA 或事故级泄露（若闭合高危影响则 P0 待验证）。
**建议的验证方式**：测试 Ingress + 只读上游种子资源；主体 A/B、租户 A/B、普通/管理权限分别访问自有/他人资源及模拟管理探针，越界必须 403 且无 Sink。当前报告未执行这些用例。
**证据状态**：待确认项。
**主体/资源/决策链**：匿名代理主体，资源与动作可携入 body；最终上游授权与真实资源归属未知。
**未授权路径与防护**：代理调用无本地能力绑定；上游可能实施有效授权，需读取其实现。
**验证方案**：同上述只读权限矩阵；无生产数据和破坏性操作。
**安全规则 ID**：CCR-NODE-BOLA-001
**标准映射**：OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639
**检测方式**：semantic

## 🎯 修复优先级

P1：先收敛服务端能力和主体授权；待确认：补 Ingress/下游权限矩阵。P0/P2/P3：无对应项。

## 📝 总结

正式路径和方法边界缺失已证实；Host 控制和任意主机 SSRF 不应混算。三个行动：固定能力表、拒绝无权限主体、用 stub 与上游只读矩阵验证。行号回抽与证伪复核完成，未更改发现位置或级别。
