# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量（frontend / Node.js，Express）
- 审查模式：security（维度 6 全深度 + 维度 1、4/5/9/11 安全子项）
- Security profile：node-api, node-worker（冻结 controls 解析结果）
- 审查输入指纹：review_input_sha256=51698f959b4eb34965b0f891c3651e7d317915b4d3a18cf00c6dfc810116dda6
- 冻结适用控制：/tmp/cc-eval-20260923/artifacts/ssrf-secure.controls.json（适用 11 条，排除 1 条）
- 攻击面索引：/tmp/cc-eval-20260923/artifacts/ssrf-secure.surface.json（仅导航）
- 项目 ignore 状态：未配置（项目内无 .cc-code-reviewer/ignore/issues.yml）
- 文件覆盖率：2/2（server.js 139 行、package.json 10 行，全部逐行精读）
- 语义增强：未运行 LSP，静态精读降级披露（依据框架第 4 节要求）

## 📊 执行摘要

- 整体结论：本服务的核心风险面——「用户可控 webhookUrl 进入服务端外发请求」——存在完整且绑定到实际连接的 SSRF 防护链（scheme 白名单 + 全地址私网校验 + IP pin + 逐跳重定向复验），按真实语义逐项核验后防护成立，未发现可成立的绕过路径。
- 各级别计数：P0 = 0，P1 = 0，P2 = 0，P3 = 0，待确认 = 1。
- 正式问题总数：**0**。
- 最高风险点：无正式问题；唯一待确认项为 `/api/notify` 端点在仓库内无任何认证/授权控制，其暴露程度依赖部署层（网关认证或网络隔离）证据。
- 安全性评分：A（SSRF 防护设计达到 OWASP SSRF Prevention Cheat Sheet 应用层控制水准）；可维护性：B+（防护逻辑集中、注释完整）；可观测性：C（无安全事件日志，属 security 模式范围外的加固建议）；性能/技术债：无事故级风险。

## 🔴 正式问题（P0/P1/P2/P3）

**未发现正式问题**（P0/P1/P2/P3 均为 0）。已按 P0 → P1 → P2 → P3 → 待确认完成全部排查：11 条冻结适用控制逐一形成结论（见「🛡️ Security 控制覆盖」台账），SSRF 防护逐项举证见台账后小节；仅有 1 项依赖部署证据的待确认项单独列出，不计入正式问题。

补充说明（不构成问题）：仓库无 lockfile，按依赖风险结论规则不形成任何确定性漏洞结论；express `^4.18.0` 版本范围无 lockfile 锚定，建议以 `npm ci` + 提交 lockfile 收敛（供应链加固建议，非漏洞结论）。

## 🔍 覆盖限制与未审查范围

- 已重点检查：唯一入口 `POST /api/notify` 的完整污点链（req.body.webhookUrl → URL 解析 → scheme/port/userinfo 校验 → DNS lookup(all) → 私网段校验 → IP pin 连接 → 重定向逐跳复验 → 响应丢弃）；TLS servername 语义；IPv4-mapped IPv6 归一化的两种形态（点分 / 16 进制）；6to4、NAT64、ULA、link-local、云元数据段；TOCTOU/DNS rebinding 窗口；超时与响应体丢弃。
- 未充分覆盖：部署拓扑（网关认证、网络隔离）、真实 DNS 环境（TTL/rebinding 实测）、上游 webhook 服务的响应行为——均为仓库外证据，对应待确认-1。
- 限制说明：攻击面索引中 `sensitive_sinks` 标记 server.js:30 为 `child-process-exec`，实际为正则 `RegExp.prototype.exec`（导航层误报，非 child_process 调用），已按真实代码语义核验；全文件无 `child_process` 引入。

## 🔐 授权面覆盖

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 0 / 不适用 1 → 1 = 0 + 0 + 0 + 1。
- 台账唯一行：入口 `POST /api/notify`（server.js:128）× 受保护动作「外发 webhook 投递」；主体：无认证主体（未认证调用方）；资源：调用方自行提供的 webhook URL（自属资源，无共享对象存储）；授权决策点：仓库内不存在（无认证/授权中间件）；最终 Sink：`https.request`（server.js:92）→ 已由 SSRF 防护链约束为「校验过的公网 IP + 原始主机名 TLS 校验」。
- 差分反例执行情况：同角色异对象（不适用：无对象 ID 定位的资源存储）；低权限高功能（不适用：无角色/高权限动作面，但「任何未认证方可调用」记录为待确认-1）；跨租户/组织（不适用：无租户概念）；对象属性越权（不适用：无 mass assignment 面，body 仅消费 webhookUrl 单字段）；批量/嵌套资源（不适用：无批量与嵌套入口）；替代执行路径（不适用：单一路由，无异步/内部/旧版本变体）。
- 未闭合入口与外部依赖：网关认证/网络隔离是否覆盖 `/api/notify`（对应待确认-1）；除此之外无。
- 结论边界：本范围不存在对象级/功能级授权判断面，故不声明「未发现越权问题」于授权语义之外的场景；端点可达性证据依赖部署层。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] `/api/notify` 端点无认证与频率限制，滥用面依赖部署层证据

**位置**：server.js:128（入口注册）、server.js:16（仅 express.json，无任何认证中间件）

**置信度**：低（部署依赖） | **所属维度**：维度6-安全

**依据**：
```js
const app = express();
app.use(express.json());            // ← 全部中间件仅 body 解析，无认证/授权/限流
...
app.post('/api/notify', (req, res) => {   // ← 未认证即可触发服务端外发请求
  let target;
  try {
    target = new URL(req.body.webhookUrl); // ← 调用方自选目标（SSRF 面已由防护链闭合）
```

**证据状态**：待确认项（入口注册与中间件装配在仓库内已闭合，但「生产可达」需部署/网关配置证据）。

**主体/资源/决策链**：主体 = 任意未认证调用方；受保护动作 = 服务端外发 webhook 投递（固定载荷 `{"event":"order.created"}`，server.js:123）；资源 = 调用方自选的公网 https 目标；授权证据/决策点 = 仓库内不存在；owner/tenant 绑定 = 不适用（无共享资源）；最终 Sink = https.request 至已校验公网 IP。

**未授权路径与防护**：最短路径 = 未认证方直接 POST /api/notify 使服务向任意公网 https 地址投递通知。现有防护及其限制：SSRF 防护链已阻断内网/元数据/私网目标（有效，见台账 CCR-NODE-SSRF-001），但不约束「合法公网目标」的滥用——服务可被用作外发通知中继（垃圾通知/信誉损耗）与消耗出站连接资源；无速率限制。

**待确认原因**：该服务是否位于认证网关之后、或仅暴露于隔离内网，无法从当前仓库闭合；缺少部署/运行配置证据时按框架规则不得直接定为越权/滥用漏洞。

**建议的验证方式**：在测试环境确认（1）调用 `/api/notify`（无凭据）是否经网关 401/403 拦截；（2）网关/网络层是否存在出站频率限制；（3）若确认为公网直连，补充 API key/签名认证 + 每租户投递频率上限。最小验证为只读探测，无需生产攻击。

---

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：0
- 已检查无发现：11
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 11 = 0 + 11 + 0 + 0

说明：不适用 1 = 冻结排除控制 CCR-NODE-BFFHEADER-001（profile 未启用：激活 profile 为 node-api,node-worker；本服务为单一出站通知服务，无 BFF 上游头转发面，代码证据与排除结论一致，无语义提升）。

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025, A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3, v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | req.body 唯一被消费字段为 webhookUrl（server.js:131），仅流向 URL 解析与出站请求目标；全程无 identity/tenant/session 上下文构造，无客户端字段成为身份来源。 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 未引入任何会话机制（无 express-session、无 req.session 读写、无 Set-Cookie），控制前置条件不存在。 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023, API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 污点链存在（req.body.webhookUrl → https.request）但防护链完整成立，逐项举证见下方「SSRF 防护逐项举证」11 条（server.js:18-137）；未发现 scheme/端口/userinfo/IPv4-mapped/6to4/NAT64/DNS rebinding/重定向任一维度的可成立绕过。 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全文件无 child_process 引入/require；surface 索引 server.js:30 的 child-process-exec 标记为正则 `.exec()` 误报（导航层噪声，已按代码语义核验）。 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2, v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/res.sendFile/res.download/createReadStream 使用；webhookUrl 仅进入 URL 解析，不进入文件路径。 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无递归 merge/extend/defaults 消化 req.body（express.json 的 JSON.parse 不产生原型链写入）；body 仅单字段属性读取。 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 mongodb/mongoose/任何数据库客户端；无查询构造面。 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load/自定义反序列化；跨边界仅 JSON.parse（express.json）。 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象 ID 定位的资源存储与读改删导出面；唯一「资源」是调用方自选的 webhook 目标（自属），不存在跨主体对象访问路径；台账见「授权面覆盖」。 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无角色/高权限动作面（无管理、审批、配置、导出、删除动作）；「端点整体未认证」不构成垂直越权（无权限层级可越），其部署依赖风险单独记录为待确认-1。 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2, v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 控制前置条件不成立：服务不使用 Cookie 会话（无会话中间件、无 Set-Cookie），浏览器无自动携带的服务端凭据，CSRF 攻击面依赖的凭据形态在代码内可闭合为不存在。 |

### SSRF 防护逐项举证（CCR-NODE-SSRF-001 → checked_no_finding 的防护位置清单）

1. **scheme 白名单（仅 https）**：`ALLOWED_SCHEMES = new Set(['https:'])`（server.js:18）；入口预检（server.js:135）与连接前复核（server.js:83）双重校验，重定向跳再次校验（server.js:113）——`http://`、协议相对及任意非 https scheme 均被拒。
2. **端口收敛**：显式非 443 端口一律拒绝（server.js:83，WHATWG URL 已归一化前导零等形态），实际连接端口硬编码 443（server.js:96），无非常规端口绕过。
3. **userinfo 拒绝**：`parsed.username || parsed.password` 即拒（server.js:83），封堵 `https://expected-host@evil.com/` 的 `@` userinfo 绕过向量。
4. **DNS 单次解析 + 全地址校验**：`dns.lookup(host, { all: true })`（server.js:86）后逐地址过 `isPrivateIp`，任一私网/特殊地址整体拒绝（server.js:88-90），不允许「多地址中挑一个」的部分放行。
5. **IP 归一化覆盖 IPv4-mapped IPv6 双形态**：`normalizeIp`（server.js:23-37）经 WHATWG URL 规范化（server.js:29）后用正则提取 `::ffff:hex:hex` 内嵌 IPv4（server.js:30-35），`::ffff:a.b.c.d` 点分形态经规范化后同样落入 IPv4 校验分支——mapped 形态无法绕过 IPv4 段校验；解析异常与畸形地址按拒绝处理（server.js:41、server.js:44）。
6. **IPv4 特殊段拒绝清单**：0/8、10/8、127/8、100.64/10 CGNAT、169.254/16（含云元数据 169.254.169.254）、172.16/12、192.0.0/24、192.0.2/24、192.88.99/24、192.168/16、198.18/15、198.51.100/24、203.0.113/24 及 ≥224 组播/保留/广播（server.js:46-61）。
7. **IPv6 白名单式收敛**：仅放行 2000::/3 全局单播，显式拒绝 2001 协议分配段/文档段（second ≤ 0x01ff）、2001:20 ORCHID、2001:db8 文档段与 2002::/16 6to4（内嵌 IPv4 目标，server.js:63-71）；loopback ::1、ULA fc00::/7、link-local fe80::/10、组播 ff00::/8、NAT64 64:ff9b::/96 均因落在 2000::/3 之外被拒。
8. **校验—使用绑定（TOCTOU / DNS rebinding 消除）**：连接目标直接使用已校验 IP——`host: pinnedIp` + `family: net.isIP(pinnedIp)`（server.js:91-96），`https.request` 收到 IP 字面量不再做 DNS 二次解析，校验与连接之间不存在再次解析窗口；DNS 返回多地址时 pin 的是已通过全量校验集合中的首个地址。
9. **TLS 主机校验保留**：`servername: net.isIP(dnsHost) ? undefined : dnsHost`（server.js:97）——域名目标 SNI 与证书主机校验绑定原始主机名，不受 IP 直连影响；IP 字面量目标时 servername 为 undefined，Node 对连接地址执行 checkServerIdentity（证书 SAN-IP 校验），不因 IP 连接放水。
10. **重定向逐跳复验**：Node https 不自动跟随重定向，代码手动处理 3xx Location（server.js:103-114）：`new URL(location, parsed)` 解析后重新进入 `requestPinned`，完整重跑「scheme/端口/userinfo → DNS 解析 → 全地址校验 → IP pin 绑定」流程；跳数上限 HOP_LIMIT=3（server.js:19、server.js:106），无逐跳复验缺口。
11. **资源与稳定性辅助控制**：上游 5 秒超时并销毁连接（server.js:121）、响应体 `resume()` 丢弃防无界缓冲（server.js:117）、全程错误统一 400 拒绝且已发送响应后不再重复写（server.js:74-77）、`express.json()` 默认 100kb 体积上限。

以上 11 项防护在唯一入口 `POST /api/notify`（server.js:128-137）到最终 Sink `https.request`（server.js:92）的完整路径上闭合，未见「校验与使用脱节」「DNS 二次解析」「TLS 校验降级」「重定向跳过复验」任一失效形态。

## 📝 总结

- 一句话架构判断：这是一个单入口 webhook 通知微服务，SSRF 防护以「解析一次 → 全地址私网校验 → 校验 IP 绑定连接 → 重定向逐跳复验」的完整链条实现，属于应用层 SSRF 控制的正确实现形态。
- 本次模式核心判断：CCR-NODE-SSRF-001 按真实语义判定防护成立（checked_no_finding），未发现正式问题；其余 10 条适用控制的前置面在本服务均不存在，同为 checked_no_finding；1 条待确认项指向部署层认证证据缺失。
- 关键行动项：（1）补齐 /api/notify 的认证与出站频率限制（或提供网关认证证据关闭待确认-1）；（2）提交 lockfile 并以 npm ci 锁定依赖（供应链加固建议）；（3）可选：对被拒绝的 webhook 目标增加脱敏审计日志，便于安全事件追责（security 模式范围外的一般加固建议）。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
