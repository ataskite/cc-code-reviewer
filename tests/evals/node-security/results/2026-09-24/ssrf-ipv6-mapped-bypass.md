# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查范围：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/ssrf/ipv6-mapped-bypass（全部生产源码）
- 审查模式：security
- 语言 / 项目类型：frontend / node（Express 4.18，package.json `main=server.js`）
- 审查模型：未注入（单 Agent，继承会话档位）
- 启用维度：1、4（仅配置安全）、5（仅注入/越权）、6（全深度）、9（仅敏感信息泄露）、11（仅鉴权/错误信息）
- 跳过维度：2、3、7、8、10、12
- 检测到的技术栈：Node.js + Express（`express.json()` 解析 body，全局 `fetch` 外发）
- 语义增强：未注入 LSP；已降级为静态逐文件精读 + 冻结攻击面索引导航（surface.json 命中 server.js:13 request-body、server.js:16 outbound-http，与本轮发现链一致）
- 冻结适用控制：/tmp/cc-eval-20260923/artifacts/ssrf-ipv6-mapped-bypass.controls.json（11 条适用 / 1 条排除；catalog_sha256 已绑定）
- Node 攻击面索引：/tmp/cc-eval-20260923/artifacts/ssrf-ipv6-mapped-bypass.surface.json（仅导航候选，非发现清单，未作为问题依据）
- 项目 ignore 状态：未配置
- 文件覆盖率：2/2（server.js、package.json 全文精读）
- 运行覆盖清单：不适用（单 Agent 路线，无 RUN_DIR）
- 脱敏声明：项目内未发现密钥/口令/令牌值；证据引用不含敏感值，无需掩码项

## 📊 审查范围说明

- **项目类型**：Node.js HTTP 服务（Express 单文件）
- **审查范围**：`server.js`（24 行，唯一生产源码）+ `package.json`；无其他目录、无配置文件、无 CI/容器清单
- **审查基准路径**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/ssrf/ipv6-mapped-bypass
- **入口枚举**：HTTP 1 个（`POST /api/notify`，server.js:11）；无 RPC/消息/任务/回调/文件 URL/WebSocket/GraphQL 入口
- **项目 ignore**：未配置（.cc-code-reviewer/ignore/issues.yml 不存在，未启用任何跳过规则）
- **覆盖方式**：逐文件全量精读 + 控制台账逐条结论 + 授权面二次扫描

## 📊 执行摘要

- **整体结论**：该服务把客户端可控的 `webhookUrl` 直接作为服务端外发目标，唯一防护是一个 IPv4 文本前缀黑名单；该黑名单对 IPv6 形态（含 IPv4-mapped IPv6 loopback、link-local、unique-local、纯 IPv6 loopback）以及未解析的域名全部漏检，构成证据链闭合的 SSRF（P0）。
- **最高风险点**：匿名调用方即可让服务端直连 loopback / 内网 / 链路本地目标，且接口把内网目标的响应状态回显给调用方，形成内网枚举 oracle。
- **安全性 / 性能 / 可维护性 / 技术债务评分**：安全性 差（核心外发控制缺失）；性能 一般（无明确缺陷，外发无显式超时/并发上限，属加固项未定级）；可维护性 一般（单文件结构清晰）；技术债务 低（规模极小）。
- **问题汇总表**：

| 级别 | 数量 |
|---|---|
| P0 | 1 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |
| 待确认 | 0 |
| 总计 | 1 |

- **项目 ignore 命中统计**：未配置，无过滤。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：唯一入口 `/api/notify` 的 Source→Sink 全链路；冻结 controls 全部 11 条适用控制的逐条语义结论；授权面二次扫描（6 类差分反例）；错误响应泄露面；`express.json()` 默认 100kb body 上限。
- **未充分覆盖**：运行时部署形态（3000 端口是否公网直曝、是否存在仓库外出网管控/网关）不在仓库证据内；P0 定级依据仓库内 `app.listen(3000)` 的自足装配证据成立，若部署侧存在出向白名单属外部缓解、不改变仓库内结论。
- **限制说明**：无 lockfile（仅 package.json 声明 `express ^4.18.0`），按依赖风险结论规则不形成确定性漏洞结论；外发 `fetch` 未显式设置超时与并发上限（undici 有默认 300s 头/体超时兜底），属加固建议、未达正式定级门槛，在此披露不静默丢弃。
- **语义工具降级披露**：typescript-lsp 未注入，本轮为静态精读，未执行语义查询。

## 🔐 授权面覆盖（仅 Security 模式强制）

- **授权面台账**：共 1 行；已绑定 0 / 未绑定 1 / 外部证据缺失 0 / 不适用 0，`1 = 0 + 1 + 0 + 0`。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| `POST /api/notify`（server.js:11） | 无认证中间件（server.js:7 仅 `express.json()`），主体为任意匿名请求方 | 服务端外发 HTTPS POST（外部特权调用）+ 回显投递状态 | 目标 URL 来自 `req.body.webhookUrl`（客户端完全可控） | 无身份决策点；仅有 scheme 检查 + IPv4 前缀黑名单的目标校验（server.js:14-15），且可被 IPv6 形态绕过 | `fetch(target)`（server.js:16） | 未绑定（对应正式问题 P0-1） | 无（全仓唯一路由，无消息/任务/内部入口） |

- **已验证反例**：
  1. 同角色异对象：不适用——无对象 ID 定位的读写面（资源仅为用户指定 URL，非存储对象）。
  2. 低权限高功能：成立——匿名主体直达"以服务端网络位外发请求"的特权动作，反例路径即 P0-1。
  3. 跨租户/组织：不适用——代码内无租户/组织上下文。
  4. 对象属性越权：不适用——`req.body` 仅消费 `webhookUrl` 标量，无 mass assignment / 字段选择面。
  5. 批量与嵌套资源：不适用——无批量或嵌套资源入口。
  6. 替代执行路径：不适用——全仓唯一入口，无列表/导出/缓存/异步/旧版本变体。
- **未闭合入口与外部依赖**：无（除上述部署形态说明外）。
- **结论边界**：台账唯一行结论为"未绑定"，其对应正式问题即 P0-1；本节计数不计入问题总数。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | `req.body` 仅消费 `webhookUrl` 标量且只进入 `new URL()`（server.js:13）；全仓无身份/租户上下文构造点，source→identity sink 链不存在 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全仓无 `req.session` 读写与会话中间件（server.js:7 仅 `express.json()`），session-write sink 不存在 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | finding_confirmed | 见 P0-1：IPv4 文本前缀黑名单不覆盖 IPv4-mapped IPv6（`[::ffff:127.0.0.1]` / `[::ffff:7f00:1]`）、`::1`、link-local（fe80::/10）与 unique-local（fd00::/8），且不做 DNS 解析后 IP 校验 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 无 `child_process` 引入或调用（require 仅 express，server.js:4） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 `fs`/`res.sendFile`/`res.download` 路径操作；`webhookUrl` 仅进 URL 解析与 fetch |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无递归 merge/extend/set 消化 `req.body`；JSON 解析结果仅读取 `webhookUrl` 标量（server.js:13），不进入任何对象合并 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 客户端与查询构造（依赖仅 express） |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化；`express.json()` 为 JSON.parse 语义，无函数/实例还原 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无按对象 ID 定位的资源读写；唯一动作为外发通知（见授权面台账），主体—对象绑定面不存在 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无管理/审批/配置/导出/删除类高权限路由；"服务端外发"能力的滥用风险已由 CCR-NODE-SSRF-001 承接（P0-1），不重复计数 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 全仓无 cookie 会话机制（无 cookie-parser/session 中间件，无 Set-Cookie）；浏览器无会话凭据可被跨站自动携带，CSRF 前提不成立 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 resolver 排除（激活 profile 为 node-api/node-worker，未启用 node-bff）；语义复核未发现请求头透传路径，无需语义提升 |

说明：控制覆盖为覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明；本轮无 `static_unsupported`（五状态封闭集内其余状态均未出现）。

## 🔴 P0 严重问题

> P0 五项硬门槛核对：生产可达（`app.listen(3000)` + 路由注册均在仓库内闭合）；证据完整且置信度高（Source→Sink 链逐行闭合）；事故级影响（内网可达范围计）；缺少有效防护（黑名单可绕过）；必须阻断发布。五项全部满足。

---

### P0-1 | [维度6-安全] webhook 目标仅按 IPv4 文本前缀黑名单校验，IPv4-mapped IPv6 与 IPv6 loopback/link-local 形态可绕过直连内网（SSRF）

**位置**：server.js:15（代表性位置；Source server.js:13，Sink server.js:16）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：`POST /api/notify` 将 `req.body.webhookUrl` 解析后仅做 https scheme 检查与 IPv4 私网文本前缀黑名单匹配即交给 `fetch` 外发；黑名单不覆盖 IPv6 归一化形态，也不对域名做解析后 IP 校验，`[::ffff:127.0.0.1]`、`[::ffff:7f00:1]`、`[::1]`、`[fe80::1]`、`fd00::1`、`localhost` 等目标全部漏检。

**证据**：
```js
const PRIVATE_V4_PREFIX = /^(127\.|10\.|0\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)/;  // ← 仅 IPv4 文本前缀黑名单，非解析后 IP 校验

app.post('/api/notify', async (req, res) => {
  try {
    const target = new URL(req.body.webhookUrl);   // ← Source：请求体可控 URL（server.js:13）
    if (target.protocol !== 'https:') throw new Error('scheme');              // scheme_allowlist 已具备（https 单项）
    if (PRIVATE_V4_PREFIX.test(target.hostname)) throw new Error('private');  // ← 对 IPv6 hostname 恒不命中（server.js:15）
    const resp = await fetch(target, { method: 'POST', redirect: 'manual' }); // ← Sink：服务端外发（server.js:16）
    res.json({ delivered: resp.ok, status: resp.status });  // ← 将内网目标响应状态回显给调用方（server.js:17）
```

**Source→Propagation→Sink→Missing Control 证据链**：
- Entry：`POST /api/notify`（server.js:11；匿名可达，无任何认证中间件）
- Source：`req.body.webhookUrl`（server.js:13，客户端完全可控）
- Propagation：`new URL(...)` 解析 → `protocol !== 'https:'` 检查 → `PRIVATE_V4_PREFIX.test(target.hostname)`（server.js:14-15）
- Sink：`fetch(target, { method: 'POST', redirect: 'manual' })` 服务端外发（server.js:16）
- Missing Control：`resolved_host_allowlist` 缺失。控制要求的三个必备项中，`scheme_allowlist`（https 单项）与 `redirect_revalidation`（`redirect: 'manual'` 不自动跟随）已具备；唯独核心的"解析后真实 IP 属于出口白名单"被一个字符串前缀黑名单替代，且该黑名单形态学不成立（见下）。

**绕过形态（按真实语义验证）**：
1. IPv4-mapped IPv6 点分形态：`https://[::ffff:127.0.0.1]/` — WHATWG URL 对 IPv6 字面量的 `hostname` 返回 `[::ffff:127.0.0.1]`（含方括号），正则以前缀 `127\.` 等起始锚定永不命中；操作系统在 connect 阶段把 IPv4-mapped 地址归一为 127.0.0.1，实际连到 loopback。
2. IPv4-mapped IPv6 十六进制形态：`https://[::ffff:7f00:1]/` — `7f00:1` 即 127.0.0.1 的 32 位十六进制写法，同样漏检。
3. 纯 IPv6 loopback：`https://[::1]/` — 监听 IPv6 loopback 的内网服务可直接触达。
4. IPv6 link-local / unique-local：`https://[fe80::1]/`、`https://[fd00::1]/` — 前缀表完全没有 IPv6 网段条目（夹具声明的漏检面），链路本地与唯一本地内网可达。
5. 域名不解析校验：`https://localhost/`（getaddrinfo 解析到 127.0.0.1）或任何解析到 RFC1918 地址的域名直接放行——黑名单只看文本 hostname，从不做 DNS 解析后的 IP 判定。

**安全规则 ID**：CCR-NODE-SSRF-001

**标准映射**：OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918

**检测方式**：taint

**证据状态**：静态已证实——入口注册（`app.listen(3000)`，server.js:23）、路由注册、Source→Sink 传播链与控制缺失全部在当前仓库内闭合，不依赖外部运行配置即可得出判定。

**主体/资源/决策链**：主体为任意匿名请求方（server.js:7 仅 `express.json()`，无认证）；受保护动作为"以服务端网络位发起外发 HTTPS"（外部特权调用）；资源为客户端指定 URL（`req.body.webhookUrl`）；决策点仅有 scheme 检查 + 前缀黑名单（server.js:14-15）；最终 Sink 为 `fetch`（server.js:16）。本条为外部资源类（SSRF），不涉及对象级主体—对象绑定（授权面台账唯一行已按"未绑定"登记，反例即本条）。

**影响**：匿名攻击者可令服务端直连 loopback 与内网——对内网服务探活、向仅内网可达的接口投递 POST（可触发无认证内部接口的副作用）、经 `[::ffff:169.254.169.254]` 触达云元数据端点（IPv4 文本形态 `169.254.169.254` 被前缀挡住，映射 IPv6 形态放行）；且 server.js:17 将内网目标的 `resp.ok` / `resp.status` 回显，构成内网状态枚举 oracle。按"内网可达性放大定级"，影响以内网可达范围计，达到事故级。

**未授权路径与防护**：最短路径 = 匿名 `POST /api/notify`，body 为 `{"webhookUrl":"https://[::ffff:127.0.0.1]:<内网端口>/"}` → 前缀黑名单不命中（hostname 以 `[` 起始）→ `fetch` 直连 loopback。现有防护及限制：https scheme 限制（不阻断内网 https 服务）；IPv4 文本前缀黑名单（WHATWG URL 会把十进制/十六进制 IPv4 简写如 `https://2130706433/` 规范化为 `127.0.0.1` 从而被挡住，属附带的部分缓解，但不覆盖任何 IPv6 形态与域名）；`redirect: 'manual'`（阻断重定向跟随，不阻断直连）。三者均不构成对上述形态的有效阻断。

**建议**：
1. 用"解析后 IP + 封闭网段表"替代前缀黑名单：剥离 IPv6 方括号取 host；非字面 IP 先 `dns.lookup(host, { all: true })`；对每个地址做归一化——IPv4-mapped IPv6（`::ffff:a.b.c.d` 点分与 32 位十六进制两种写法）折回 IPv4 再判定；拒绝 loopback（127.0.0.0/8、::1）、RFC1918、fe80::/10、fd00::/8、169.254.169.254 及其映射形态。
2. 优先改为正向目标主机白名单（webhook 目标域名注册制），黑名单仅作兜底。
3. 保留 `redirect: 'manual'`；若未来改为自动跟随，必须每一跳重新执行第 1 步校验，并考虑用校验过的 IP 建立连接、保留 TLS hostname 校验以缓解 DNS rebinding。
4. 修复示意：
```js
const { isIP } = require('net');
const dns = require('dns').promises;

function isBlockedIp(rawAddr) {
  const raw = rawAddr.replace(/^\[|\]$/g, '');            // 剥 IPv6 方括号
  const ip = v4mappedNormalize(raw);                      // ::ffff:127.0.0.1 / ::ffff:7f00:1 → 127.0.0.1
  return BLOCKLIST_covers(ip);                            // 127/8、::1、10/8、172.16/12、192.168/16、fe80::/10、fd00::/8、169.254.169.254
}

async function assertPublicTarget(u) {
  const host = u.hostname.replace(/^\[(.*)\]$/, '$1');
  const addrs = isIP(host) ? [host] : (await dns.lookup(host, { all: true })).map((r) => r.address); // 域名必须解析后校验
  if (addrs.length === 0 || addrs.some(isBlockedIp)) throw new Error('private');
}
```

---

## 🟠 P1 重要问题

本次未发现满足定级门槛的 P1 问题。

## 🟡 P2 一般问题

本次未发现满足定级门槛的 P2 问题。

## 🔵 P3 建议

本次未发现值得单列的 P3 问题；外发请求超时/并发上限等加固观察已在「覆盖限制与未审查范围」披露（undici 默认 300s 头/体超时兜底，未达正式定级门槛）。

## ⚪ 待确认项

本次无待确认项：唯一正式问题的证据链已在仓库内闭合，无依赖网关/策略中心/数据库策略/运行配置的未闭合结论。

## ✅ 最佳实践亮点

- 错误响应统一为 `webhook_target_rejected`（server.js:19），不回显内部异常细节，无信息泄露。
- `redirect: 'manual'`（server.js:16）阻止了重定向跟随，封死了"公网 302 跳内网"这一常见 SSRF 变体。
- WHATWG URL 解析顺带挡住了十进制/十六进制 IPv4 简写形态（自动规范化为点分 IPv4 后命中前缀）。

## 🎯 修复优先级

- P0 - 立即修复：P0-1（resolved_host_allowlist 缺失导致 IPv6 形态 SSRF 绕过），修复并补 IPv6 形态与域名解析回归用例后再发布。
- P1 - 尽快修复：无。
- P2 - 计划修复：无。
- P3 - 可选优化：外发 fetch 显式超时与并发上限（见覆盖限制披露）。

## 📝 总结

- **一句话架构判断**：一个把客户端 URL 直接变为服务端外发目标的 Express 单入口服务，防护层仅有一层可绕过的文本前缀黑名单。
- **本次模式核心判断**：Security 控制台账 11 条适用控制中 1 条 finding_confirmed（CCR-NODE-SSRF-001，P0），10 条 checked_no_finding；控制要求的三个必备控制里 scheme 与 redirect 两项已具备，缺失的恰是核心的解析后主机校验。
- **3 个关键行动项**：1）以"解析后 IP + IPv4-mapped IPv6 归一化 + 封闭网段表"替换前缀黑名单；2）为 webhook 目标建立正向域名白名单；3）补充 IPv6 形态与域名解析的 SSRF 回归用例后再上线。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
