# 代码审查报告 - eval-host-routing-vulnerable

## ⚙️ 审查配置快照

- 生成时间：2026-10-08T02:43:10Z
- 审查类型：隔离夹具全量正向测试；范围仅 source-manifest.txt，未读取预期清单。
- 审查模式：security；模型：当前继承模型；语义增强：none，使用静态调用链。
- 启用维度：1、4配置安全、5注入/越权、6安全、9敏感泄露、11鉴权/错误信息；跳过2、3、7、8、10、12。
- 技术栈：Express、Node.js、node:http；项目 ignore：未配置。
- 审查输入清单：/tmp/cc-proxy-auth-eval.44sjAD/host-routing-vulnerable/review-input.json；selected=2，excluded=0。
- 生产源码覆盖：1/1，13 行；package.json 配置另计1；清单全部2文件均已读，全部21行。
- 本次非分批，运行覆盖清单不适用。未联网、安装依赖或向生产/测试服务发请求。

## 📊 审查范围说明

基准路径：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/host-routing/vulnerable。正式输入为 /tmp/cc-proxy-auth-eval.44sjAD/host-routing-vulnerable/source-manifest.txt；冻结控制 /tmp/cc-proxy-auth-eval.44sjAD/host-routing-vulnerable/controls.json 与索引 /tmp/cc-proxy-auth-eval.44sjAD/host-routing-vulnerable/surface.json 仅供导航和覆盖对账。已检查入口、真实 headers 构造、HTTP 调用、返回与异常路径及全部适用控制。

## 📊 执行摘要

已证实客户端能设置出站 Host，形成一条 P1 代码缺陷。未知 Ingress 是否路由到其他服务、这些服务是否接受身份头或执行高权动作；不声称完成 SSRF、越权或数据泄露复现。
安全性：5/10（限静态输入）；性能、可维护性、技术债务：N/A（未作全量质量扫描）。

| P0 | P1 | P2 | P3 | 待确认 | 总数 |
|---|---|---|---|---|---|
| 0 | 1 | 0 | 0 | 1 | 2 |

## 🔍 覆盖限制与未审查范围

未执行运行态测试；无 lockfile，不能下依赖 CVE 结论。Ingress、DNS、网关入口、上游认证/权限/响应内容与生产暴露均无范围内证据。Host 字段可控是代码结论；跨服务路由、敏感结果和生产可达性是待验证事实。

## 🔐 授权面覆盖

- 台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0。
- 授权面二次扫描：六类反例均已静态复核。

| 入口 | 主体与来源 | 动作与资源 | 决策及 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|
| POST /preview | 匿名请求；没有本地主体消费 | 转发 query 到预览；Host 为客户端头 | 无 Host 拒绝点；下游权限语义未知；http.request→pipe(res) | 外部证据缺失，见待确认-1 | 全部正式源码无其他入口 |

同角色异对象、跨租户、对象属性、批量/嵌套：没有本地对象/租户/存储模型，不能凭 query 编造对象越权。低权高功能：可控 Host 路由到何种功能需下游证据，保留缺口。替代执行路径：唯一 POST 入口；直传/封装传递均没有 Host 阻断点。网关与上游部署授权证据未闭合。

## 🛡️ Security 控制覆盖

- 适用控制：15
- 已发现问题：1
- 已检查无发现：10
- 外部证据缺失：4
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 15 = 1 + 10 + 4 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285 | taint | external_evidence_missing | 客户端可提供身份头，但本地无身份上下文 Sink；缺上游 header 清洗/身份验证/信任策略，无法证明接受任意主体；见待确认-1。 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全部代码无 session 构造或写入，不存在请求体批量写会话路径。 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | external_evidence_missing | 网络 URL/path/method 固定且 node:http 不自动跟随重定向；Host 可控见 P1-1，缺 Ingress Host→服务映射与目标可达性，不能证明任意网络请求。 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全部代码无 child_process 或 shell 执行。 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / ASVS v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/sendFile/download；请求值不进入文件路径。 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无递归合并或沿原型链写入；浅复制 headers 不证明全局原型污染。 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无数据库查询或 NoSQL 客户端。 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 仅 express.json 与 JSON.stringify，不还原函数/实例。 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象 ID 查询/写入；query 为预览数据，未见对象归属 Sink；下游对象语义未在范围内。 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | external_evidence_missing | 本地仅 /preview；缺路由到的实际服务、权限需求与上游拒绝证据，无法证明普通用户执行高权动作；见待确认-1。 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / ASVS v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 cookie/session 身份消费或状态写入；本地仅预览转发，无法证明 Cookie 会话写接口。 |
| CCR-NODE-HOSTROUTE-001 | 客户端控制出站 Host 或路由身份 | OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346 | taint | finding_confirmed | server.js:6-8 请求 body.header 直接成为 node:http headers，可覆盖出站 Host；见 P1-1。 |
| CCR-NODE-PROXYCAP-001 | 客户端扩大代理目标、路径或方法能力 | OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441 | semantic | external_evidence_missing | 网络目标/path/method 固定，但客户端 Host 可更换路由身份；缺对应能力是否受限及来源×Host×服务授权策略；见待确认-1。 |
| CCR-NODE-JWTAUTH-001 | JWT 身份接受路径缺少完整验证 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V9.1.1 / ASVS v5.0.0-V9.1.2 / ASVS v5.0.0-V9.1.3 / ASVS v5.0.0-V9.2.1 / ASVS v5.0.0-V9.2.3 / CWE-347 | semantic | checked_no_finding | 无 token 到主体接受路径，未以 JWT claims 作认证；下游策略未作安全声明。 |
| CCR-NODE-PROXYTRUST-001 | 代理来源及转发头被错误用于安全决策 | OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346 | config | checked_no_finding | 无 trust proxy 配置，亦无 forwarded→IP/租户/protocol/Cookie/限流安全决策。 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 node-api profile 排除此控制；确有批量头传播，已由 HOSTROUTE 登记；缺下游身份头信任证据，不能确认此身份绕过控制并语义提升。 |

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## 🟠 P1 重要问题

### P1-1 | [维度6-安全] 客户端可覆盖固定网络目标的出站 Host

**位置**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/host-routing/vulnerable/server.js:8

**置信度**：高；**所属维度**：维度6-安全。

**问题**：固定 URL 的请求仍以客户端提供的 headers 设置 HTTP 路由身份，没有服务端 Host 绑定或拒绝点。

**证据**：
```js
// server.js:5-11
app.post('/preview', (req, res) => {
  const rb = req.body;
  const call = http.request('http://ingress.example.test/public/preview', {
    method: 'POST', headers: rb.header // ← 客户端可设置 Host
  }, upstream => upstream.pipe(res));
  call.on('error', () => res.sendStatus(502));
  call.end(JSON.stringify({ query: rb.query }));
```

**影响**：客户端可让出站请求携带与连接目标不同的 Host。这突破代码侧路由身份边界；实际 Ingress 切换服务与敏感访问未证实，不定 P0。

**建议**：固定服务端 Host 和必要 Content-Type；忽略/拒绝客户端传输选项，业务数据单独 schema 校验；按能力绑定服务、Host、路径、method。

**证据状态**：静态已证实，仅证明 Host 值到 node:http 调用的传播链；未做运行复现。

**主体/资源/决策链**：匿名 POST 请求→body header→rb.header→http.request headers；目标为固定 Ingress 与 /public/preview；本地无身份/权限消费，实际资源权限需上游证据。

**未授权路径与防护**：入口→客户端 headers→外发 Sink；固定连接 URL/path/method 能收敛网络与动作，但不阻止 Host 覆盖；是否构成业务未授权尚待证据。

**验证方案**：授权本地环境以假的 node:http 客户端捕获 options，无真实网络：分别提供 Host/host 大小写和额外身份头，预期拒绝或仍为服务端 Host；修复前静态结果是这些键进入 headers。全部使用虚构数据，无状态变更和清理需求。

**安全规则 ID**：CCR-NODE-HOSTROUTE-001
**标准映射**：OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346
**检测方式**：taint

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 出站 Host 可控是否扩大上游能力及身份权限

**位置**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/host-routing/vulnerable/server.js:8

**置信度**：低（影响链）；**所属维度**：维度6-安全。

**依据**：P1-1 的精确代码片段及调用链。网络目的地、path、method 固定；上游响应直接 pipe(res)，Host 与其他头却来自客户端。

**待确认原因**：缺 Ingress vhost 配置、来源×Host×目标服务约束、上游身份头清洗/认证和实际受保护动作。不能证明任意 TCP 目标或高权资源可达，也不能认定匿名 public/preview 必須鉴权；若测试证明敏感服务及无授权防护，需重评 P0。

**建议的验证方式**：仅授权本地/测试 Ingress，以虚构 preview 服务和拒绝访问的测试服务为种子；匿名与低权测试用户替换 Host/身份头，请求只读假预览。预期拒绝服务切换、身份不由客户端头生成；记录实际路由与响应，禁用真实业务写入。删除测试服务和虚构账户完成清理。

**证据状态**：待确认项；外部配置未提供。
**主体/资源/决策链**：匿名/低权请求→可控 Host/身份头→共享 Ingress→实际服务与动作未知→pipe(res)；主体到能力/role/tenant 绑定未知。
**未授权路径与防护**：候选路径以外部路由和上游信任为前提；已见固定 URL/path/method，未见客户端 Host 拒绝；外部网关防护未知。
**验证方案**：上述非生产只读权限矩阵；生产入口及敏感数据均不作为本次验证目标。
**安全规则 ID**：CCR-NODE-PROXYCAP-001
**标准映射**：OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441
**检测方式**：semantic

## ✅ 最佳实践亮点

网络目标、路径和 method 固定；HTTP 出错返回502，但这些控制无法阻断 Host 覆盖。

## 🎯 修复优先级

P0：没有已证实条目。P1：尽快绑定出站 Host。P2：无。P3：无。本报告未执行任何修复。

## 📝 总结

路由身份与网络目的地的安全边界分离；静态确认证据不等于完整攻击链。下一步：重构出站 headers；补 Ingress/上游权限证据；运行授权测试环境中的只读差分回归。

**审查人**：cc-code-reviewer 正向评估 Agent；**报告版本**：5.7；**审查模式**：security；**模型档位**：inherit。
