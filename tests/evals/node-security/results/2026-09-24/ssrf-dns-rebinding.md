# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查模式：security（安全专项）
- 审查模型：inherit
- 语言/项目类型：frontend / Node.js（冻结 profile：node-api、node-worker）
- 审查范围：tests/evals/node-security/ssrf/dns-rebinding 全部生产源码
- 检测到的技术栈：Node.js + Express（package.json：express ^4.18.0，main: server.js）
- 启用维度：1 正确性、4（配置安全子项）、5（注入/越权子项）、6 安全全深度、9（敏感信息泄露子项）、11（鉴权/错误信息子项）
- 跳过维度：2、3、7、8、10、12（security 模式矩阵）
- 模式说明：聚焦维度 6 全深度及安全强相关交叉维度；同步执行企业级 Security 框架的授权面二次扫描与控制台账对账
- 语义增强：未注入（静态全文阅读；项目仅 1 个生产源码文件 37 行，等价全覆盖，无降级损失）
- 项目 ignore 状态：未配置
- 文件覆盖率：1/1（server.js 全量逐行阅读；package.json 作为伴随配置读取）
- 冻结适用控制：/tmp/cc-eval-20260923/artifacts/ssrf-dns-rebinding.controls.json（适用 11 条 / 排除 1 条）
- Node 攻击面索引：/tmp/cc-eval-20260923/artifacts/ssrf-dns-rebinding.surface.json（仅导航候选，非发现清单）

---

## 📊 执行摘要

- **整体结论**：单文件 Node 通知服务。SSRF 防护三要素中，scheme 白名单（仅 https）与重定向手动跟随（`redirect: 'manual'`）成立；但核心的「解析后地址校验」与「实际连接」脱节——校验用的 `dns.lookup` 结果并未约束 `fetch` 的连接目标，`fetch` 内部会再次解析 DNS，构成经典 DNS rebinding / TOCTOU 窗口，可直达内网与云元数据端点。同一校验函数还存在 IPv4-mapped IPv6 归一化缺口（次要旁路，一并修复）。
- **最高风险点**：P0-1（SSRF 校验与连接脱节，DNS rebinding 可绕过私网校验直达内网/云元数据）。
- **安全性评分**：差（存在证据闭合的事故级 SSRF，防护语义失效）；**性能**：security 模式未深入；**可维护性**：一般（单文件结构清晰，注释如实标注了缺陷）；**技术债务**：低。
- **问题汇总**：P0 × 1，P1 × 0，P2 × 0，P3 × 0，待确认 × 1；正式问题总计 1。
- **项目 ignore 命中统计**：未配置 ignore 规则，无过滤。

---

## 🔴 P0 严重问题

> P0 证据门槛：生产路径可达、证据完整且置信度高、后果达到事故级、缺少有效防护、必须阻断发布——本条五项全部满足（逐项见下）。

### P0-1 | [维度6-安全] webhook SSRF 校验与连接脱节：fetch 二次 DNS 解析可被 DNS rebinding 绕过私网校验，直达内网/云元数据

**位置**：server.js:27-30（校验于 server.js:27-28，Sink 于 server.js:30；次要旁路位于 server.js:19-20）

**置信度**：高 | **所属维度**：维度 6 安全（不安全 URL 拼接 / SSRF 向量；OWASP 2025 A01）

**问题**：`/api/notify` 对用户可控 `webhookUrl` 做了 scheme 白名单 + DNS 解析私网校验，但校验后仍按**域名**调用 `fetch`——`fetch`（undici）会重新解析 DNS，已校验的解析结果不约束实际连接目标，攻击者控制目标域权威解析时可先返回公网 IP 通过校验、正式连接时返回 169.254.169.254 等内网地址（校验与使用脱节的 TOCTOU / DNS rebinding）。

**证据**（Source → Propagation → Sink → Missing Control 全链闭合）：

```javascript
// server.js:23-31
app.post('/api/notify', async (req, res) => {            // 入口：无任何认证/授权中间件（匿名可达）
  try {
    const target = new URL(req.body.webhookUrl);         // Source：req.body.webhookUrl（客户端可控）
    if (target.protocol !== 'https:') throw new Error('scheme');   // scheme 白名单（该子项成立）
    const addrs = await dns.lookup(target.hostname, { all: true }); // ← 第一次 DNS：仅用于校验
    if (addrs.length === 0 || addrs.some((a) => isPrivateIp(a.address))) throw new Error('private');
    // 缺陷：连接仍按域名 → fetch 内部再次解析 DNS（校验与连接脱节）
    const resp = await fetch(target, { method: 'POST', redirect: 'manual' }); // ← Sink：第二次 DNS 未绑定已校验 IP（TOCTOU）
    res.json({ delivered: resp.ok, status: resp.status }); // 响应回传上游状态码（内网服务探测 oracle）
```

```javascript
// server.js:11-21（同一校验函数的次要旁路）
function isPrivateIp(ip) {
  if (net.isIPv4(ip)) { /* 10/8、127/8、0/8、172.16/12、192.168/16、169.254/16 —— IPv4 段覆盖尚可 */ }
  const lo = ip.toLowerCase();
  return lo === '::1' || lo.startsWith('fe80:') || lo.startsWith('fc') || lo.startsWith('fd');
  // ← 未归一化 IPv4-mapped IPv6：字面量 https://[::ffff:a9fe:a9fe]/（169.254.169.254 的映射形态，
  //    WHATWG URL 规范化为 ::ffff:a9fe:a9fe）四个分支均不命中 → 判为非私网直接放行
}
```

**防护是否成立的语义判断**：
1. `scheme_allowlist`（server.js:26，仅 https）——成立，但只约束协议，不约束解析目标。
2. `redirect_revalidation`（server.js:30，`redirect: 'manual'` 不跟随重定向）——成立，可阻断 302 类绕过。
3. `resolved_host_allowlist`（server.js:27-28）——**形在而语义失效**：校验用的 `dns.lookup` 结果与 `fetch` 的实际连接目标之间无绑定。校验（第 27 行）与使用（第 30 行）之间夹着一次不受控的重新解析，攻击者控制权威 DNS 即可在两个时刻返回不同答案（校验时公网 IP / 连接时内网 IP）。这正是「校验过的 DNS 结果未实际约束后续连接目标」的 TOCTOU 定义。

**安全规则 ID**：CCR-NODE-SSRF-001

**标准映射**：OWASP A01:2025 / API7:2023, API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918

**检测方式**：taint

**证据状态**：静态已证实——生产源码全量（1 文件 37 行）逐行阅读，入口（server.js:23 + server.js:37 `app.listen(3000)`）、Source（req.body.webhookUrl）、传播（URL 解析→scheme 校验→dns.lookup→isPrivateIp）、Sink（fetch）、缺失控制（解析结果未绑定连接目标）全部在仓库内闭合；DNS rebinding 的攻击前提（攻击者控制目标域权威解析）为该类攻击的公认模型，`isPrivateIp` 自身将 169.254/16 列入黑名单亦印证威胁模型。

**影响**：以内网可达性放大定级——攻击者可令服务端从其网络位置对内网任意 https 服务与云元数据端点发起 POST（169.254.169.254 链路本地段就在代码自身的拒绝清单中，说明该威胁被作者认知但防护失效）；响应回传 `{delivered, status}` 形成内网服务存活/状态码探测 oracle；入口完全匿名（无认证中间件），触发条件完全由攻击者控制；次要旁路（IPv4-mapped IPv6 字面量）甚至无需控制 DNS 即可确定性命中同一段链路本地网段。事故级影响 + 无有效防护 + 生产可达（listen + 路由注册均为仓库证据），须阻断发布。

**主体/资源/决策链**：主体=匿名客户端（全文件无认证/授权中间件，身份来源缺失）；受保护动作=以服务端网络位置发起外发 HTTPS 请求；资源=req.body.webhookUrl（客户端可控，无持久化对象）；授权决策点=无；owner/tenant/role 绑定=不适用（无对象存储与租户上下文）；最终 Sink=`fetch(target)`（server.js:30）。

**未授权路径与防护**：最短路径=匿名 `POST /api/notify` 携带攻击者控制的域名（或 mapped-IPv6 字面量）→ 校验通过 → `fetch` 二次解析命中内网 IP → 内网/云元数据请求。现有防护及其限制：scheme 白名单（有效但不足以阻断 rebinding）、redirect manual（有效但不阻断 rebinding）、私网 IP 校验（存在但语义失效——校验结果不约束连接目标）。

**建议**（解析一次 → 全地址校验 → 绑定已校验 IP 连接，消除第二次 DNS）：

```javascript
// 1) 归一化 IPv4-mapped IPv6 后再做段校验（修复次要旁路）：
//    '::ffff:a.b.c.d' 与 '::ffff:hex:hex' → 提取内嵌 IPv4；解析异常/未知形态按拒绝处理。
// 2) 校验通过后不用域名连接，改用已校验 IP 作为连接目标：
const pinnedIp = addrs[0].address;                 // 已通过全地址校验
https.request({
  host: pinnedIp,                                  // 连接目标 = 已校验 IP（DNS 不再二次解析，消除 TOCTOU）
  family: net.isIP(pinnedIp),
  port: 443,
  servername: net.isIP(dnsHost) ? undefined : dnsHost, // TLS SNI/证书校验绑定原始主机名
  path: target.pathname + target.search,
  method: 'POST',
}, /* ... */);
// 3) 保留 scheme 白名单与 redirect:'manual'；如未来需跟随重定向，每跳 Location 重新执行「解析→校验→绑定」。
// 4) 为外发请求增加超时；网络层补充出站目标白名单作为纵深防御。
```

**验证方案**（最小、非破坏性，测试环境执行）：A/B DNS 用例——自建权威解析，第一次解析返回公网 IP、短 TTL 后返回 169.254.169.254，调用 `/api/notify` 观察修复前是否仍发出外发请求（预期：修复前连通、修复后 400 拒绝）；对照用例——直接提交 `https://[::ffff:a9fe:a9fe]/` 验证 mapped 归一化修复（预期：修复后 400 拒绝）。

---

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 依赖未锁定（无 lockfile），无法形成确定性依赖漏洞结论

**位置**：package.json:5（`"dependencies": { "express": "^4.18.0" }`；项目目录内无 lockfile）

**置信度**：低 | **所属维度**：维度 6 安全（供应链，OWASP 2025 A03）

**依据**：
```
"dependencies": { "express": "^4.18.0" }   // ← 浮动版本区间，仓库内无 package-lock.json
```

**待确认原因**：依赖风险结论规则要求 lockfile 版本明确且证据可靠；当前无 lockfile，安装版本不可复现（`npm ci` 不可用），无法对 express 及其传递依赖做版本级漏洞结论，只能列为待确认/扫描建议。

**建议的验证方式**：提交 lockfile 并在 CI 使用 `npm ci` 安装；接入 `npm audit --package-lock-only` 或离线依赖扫描门禁；核查 express 及传递依赖（body-parser/qs 等）的锁定版本有无已知公告。

---

## 🔍 覆盖限制与未审查范围

- **已重点检查**：server.js 全量逐行（1/1 文件、37 行）——入口注册、中间件装配、URL 解析与校验链、外发 Sink、错误处理与响应字段；package.json 依赖与入口声明；冻结 controls 11 条逐条语义复核；攻击面索引条目与实际代码逐一对照。
- **未充分覆盖**：运行时部署拓扑（是否存在网关认证、出站网络策略、DNS 解析器配置）属仓库外证据；express/undici 依赖实现因无 lockfile 无法做版本级结论；Node `fetch` 的 DNS 行为按 Node ≥18 内置 undici 语义评审。
- **限制说明**：静态审查无法实测权威 DNS 切换行为，攻击前提采用 DNS rebinding 公认模型；语义工具未注入，但单文件 37 行的静态全文阅读在覆盖上等价、无降级损失。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 1 / 外部证据缺失 0 / 不适用 0 → 1 = 0 + 1 + 0 + 0。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| server.js:23 `POST /api/notify` | 无认证中间件，主体为匿名（身份来源缺失） | 以服务端网络位置向指定 URL 发起外发 HTTPS POST | `req.body.webhookUrl`（客户端可控，无持久化对象） | 无（代码中无任何认证/授权判定） | `fetch(target)` server.js:30 | 未绑定（匿名主体直达外发敏感效果，风险由 P0-1 承载并定级） | 无（37 行内仅此一个 HTTP 入口；无异步任务/消息/RPC/缓存/旧版本路径） |

- 已验证反例：同角色异对象=不适用（无对象 ID 定位的资源读写，无持久层）；低权限高功能=不适用（范围内不存在管理/审批/配置/导出/删除类高权限动作面，外发能力的匿名可达风险已按 SSRF 控制定级承载于 P0-1）；跨租户/组织=不适用（无租户上下文与多租户数据）；对象属性越权=不适用（无对象属性序列化 / mass assignment 面）；批量与嵌套资源=不适用（单一入口单一动作）；替代执行路径=不适用（全量代码内无并行入口）。
- 未闭合入口与外部依赖：生产部署是否经网关补充认证、是否存在出站网络白名单——属仓库外证据；最小验证为确认生产入口的网关认证配置与出站策略。
- 结论边界：动作中心二次扫描已完成 1/1 入口；「未绑定」结论已对应正式问题 P0-1，本范围不另作“未发现越权问题”的扩大声明。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025, A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3, v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 唯一入口仅消费 `req.body.webhookUrl` 作外发目标（server.js:25），无 userId/tenantId/role 等字段进入身份或租户上下文，无 `ctx.user`/`req.session` 类赋值 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全文无 `req.session` 使用；未装配 express-session/cookie 中间件（server.js:8-9 仅 `express.json()`，package.json 仅依赖 express） |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023, API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | finding_confirmed | 见 P0-1：`dns.lookup` 校验结果未绑定 `fetch` 实际连接目标（TOCTOU/DNS rebinding）；同函数另有 IPv4-mapped IPv6 归一化缺口 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全文无 child_process 引入或调用（server.js:4-6 仅 require express/dns/net） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2, v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 `fs.*`/`res.sendFile`/`res.download`/`createReadStream` 用法；`webhookUrl` 仅进入 URL 解析与 fetch |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无递归 merge/extend/defaults；`req.body` 仅点取 `webhookUrl` 单字段，未整对象并入其他对象 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 mongodb/mongoose 等客户端，无任何查询构造 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化入口；`req.body` 经 `express.json()`（JSON.parse 语义，无函数/实例还原） |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象 ID 定位的资源读写（无数据库/持久层），`webhookUrl` 非他人对象引用；授权面台账见「授权面覆盖」节 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 范围内不存在管理/审批/配置/导出/删除类高权限动作面；唯一动作（外发 webhook）的匿名可达风险已按 SSRF 控制承载于 P0-1 并定级 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2, v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 豁免证据：全服务无 Cookie/会话凭据（无 cookie-parser/express-session 装配，外发 fetch 亦不携带 Cookie），不存在可被浏览器跨站自动携带的环境凭据，CSRF 前提不成立 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | resolver 排除（激活 profile：node-api、node-worker，未启用 node-bff）；语义复核无提升——`fetch(target, { method: 'POST', redirect: 'manual' })` 未透传任何客户端请求头（server.js:30） |

说明：`不适用 E=1` 为冻结 resolver 排除的 CCR-NODE-BFFHEADER-001（无语义提升，语义提升计数 0）。控制覆盖是覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明；`static_unsupported` 不是通过（本轮为 0）。

## ✅ 最佳实践亮点

- scheme 白名单（仅 https）与 `redirect: 'manual'`（server.js:26、30）两项子控制语义成立，分别封堵了协议降级与 302 重定向绕过两个常见 SSRF 旁路面。
- `isPrivateIp` 对 IPv4 私网/链路本地段的覆盖（10/8、172.16/12、192.168/16、127/8、0/8、169.254/16，server.js:14-17）比常见实现更完整，且 `dns.lookup({all:true})` 逐地址校验避免了多地址漏检。

## 🎯 修复优先级

- **P0 - 立即修复（阻断发布）**：P0-1——校验结果绑定连接目标（pinned IP + servername），并归一化 IPv4-mapped IPv6。
- **待确认 - 计划确认**：待确认-1——提交 lockfile 并接入 `npm ci` + 依赖扫描门禁。

## 📝 总结

- 一句话架构判断：单文件 Node 通知服务，SSRF 三项子控制中两项成立、核心一项（解析结果约束连接）语义失效，防护链条断在最关键的一环。
- 本次模式核心判断：静态证据已闭合“校验与连接脱节”的 TOCTOU 证据链（server.js:27-30），叠加 mapped-IPv6 归一化缺口，按内网可达性放大定级 P0；其余 10 条适用控制经逐条语义复核无发现。
- 3 个关键行动项：1) 重构为「解析一次 → 全地址校验（含 mapped 归一化）→ 绑定已校验 IP 连接（servername 保持原域名）」；2) 测试环境用 A/B DNS 与 mapped 字面量两组用例回归验证；3) 提交 lockfile、`npm ci` 安装并纳入依赖扫描。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
