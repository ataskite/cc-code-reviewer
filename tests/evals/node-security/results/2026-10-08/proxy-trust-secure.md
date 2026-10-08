# 代码审查报告 - proxy-trust-secure

## ⚙️ 审查配置快照

- 生成时间：2026-10-08；隔离夹具存量审查，审查模式 security，模型档位 inherit。
- 审查基准路径：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/proxy-trust/secure
- 正式范围：冻结 source-manifest.txt / review-input.json；server.js 1/1 文件、10/10 行，覆盖率 100%；package.json 为独立配置 1/1。selected 2 / excluded 0。
- 审查输入清单：/tmp/cc-proxy-auth-eval.44sjAD/proxy-trust-secure/review-input.json；控制：/tmp/cc-proxy-auth-eval.44sjAD/proxy-trust-secure/controls.json；surface：/tmp/cc-proxy-auth-eval.44sjAD/proxy-trust-secure/surface.json。
- 技术栈：Node.js / Express；ignore 未配置。
- 启用维度：1、4（配置安全）、5（注入/越权）、6、9（泄露）、11（鉴权/错误）；跳过 2、3、7、8、10、12 及其余非安全子项。
- 语义增强：none；已降级静态逐文件/控制流审查，未声称 LSP 或运行态验证。surface 只用于导航，未按候选自动报错。

## 📊 执行摘要

禁用代理信任，权限依据为真实 socket.remoteAddress，且只监听 loopback。伪造 forwarded 头不能改变该代码路径，未发现代理来源信任缺陷；本地主机使用者的业务授权策略不在此证据范围。

| P0 | P1 | P2 | P3 | 待确认 | 总计 |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 | 0 |

安全性 9/10；性能/可维护性/技术债务 N/A（非本次扫描）。没有 lockfile 或部署配置；不据依赖名/范围版本断言漏洞。

## 🔍 覆盖限制与未审查范围

已逐文件阅读 server.js 和 package.json，并完成入口到响应、默认/异常分支、身份与来源可信性检查。该夹具的 exportAccepted 仅为 JSON 标记，未提供真实导出、数据库、业务资源或生产网关/防火墙，不扩大影响。完整文件覆盖不代表 OWASP 认证或 ASVS 全量合规。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 台账：共 1 行；已绑定 1 / 未绑定 0 / 外部证据缺失 0 / 不适用 0。
- 唯一入口 × 动作：GET /admin/export × 返回管理动作接受标记；最终 Sink 为 res.json。绑定结论：已绑定。主体来源为连接来源/IP 判断；无对象 ID/tenant/属性参数。
- 已完成二次扫描：低权限高功能和替代路径已追踪到唯一注册的 GET handler；失败路径已在 Sink 前拒绝。
- 六类反例：同角色异对象、跨租户/组织、对象属性、批量/嵌套资源均无相关输入/资源操作；低权限高功能按 IP 门槛复核；替代执行路径没有其他 handler、任务/RPC/缓存/导出实现，非注册 method 无该 Sink。
- 未闭合入口与外部依赖：生产部署、真实数据导出效果均未提供，不据此假设另有攻击或防护。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：15
- 已发现问题：0
- 已检查无发现：15
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 15 = 0 + 15 + 0 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | server.js:5 可信来源为 socket 连接对端，无请求字段覆盖会话/主体/租户。 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | server.js 全文没有 Session 中间件或 req.session 写入。 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | server.js 全文只有本地响应，没有外发 HTTP 客户端或目标构造。 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | server.js 全文无进程执行或 shell Sink。 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / ASVS v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | server.js 全文无文件路径输入、文件读取/下载 Sink。 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | server.js 全文无深合并、递归赋值或动态原型写入。 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | server.js 全文无 Mongo/NoSQL 查询。 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | server.js 全文未使用函数/任意类型反序列化；JWT JSON 解码不属于危险反序列化 Sink。 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 唯一 GET /admin/export 返回固定接受标记，未读取对象 ID 或数据资源；同角色异对象与跨租户无可替换资源。 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | server.js:5-8 对非本地连接默认拒绝；此范围的显式授权策略是本地来源，未出现可由 forwarded 改写的功能权限。 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / ASVS v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 唯一接口为 GET 标记响应，未使用 Cookie/Session 或状态变更。 |
| CCR-NODE-HOSTROUTE-001 | 客户端控制出站 Host 或路由身份 | OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346 | taint | checked_no_finding | server.js 全文没有出站 HTTP/代理客户端，信号导航不能构成路由身份问题。 |
| CCR-NODE-PROXYCAP-001 | 客户端扩大代理目标、路径或方法能力 | OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441 | semantic | checked_no_finding | server.js 全文没有代理调用或可由用户选择的 service/path/method 能力。 |
| CCR-NODE-JWTAUTH-001 | JWT 身份接受路径缺少完整验证 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V9.1.1 / ASVS v5.0.0-V9.1.2 / ASVS v5.0.0-V9.1.3 / ASVS v5.0.0-V9.2.1 / ASVS v5.0.0-V9.2.3 / CWE-347 | semantic | checked_no_finding | server.js 全文身份门槛为连接来源，不存在 JWT 接受面。 |
| CCR-NODE-PROXYTRUST-001 | 代理来源及转发头被错误用于安全决策 | OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346 | config | checked_no_finding | server.js:3,5-10 trust proxy=false；socket.remoteAddress 必须为 IPv4/IPv6 loopback；监听 127.0.0.1。 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | profile 未启用（激活 profile: node-api）；如语义审查发现该控制风险，可在台账中以 finding_confirmed 语义提升；本范围无上游转发。 |

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## 🟠 P1 重要问题

无正式 P1 问题。

## 🟡 P2 一般问题

无。

## 🔵 P3 建议

无。

## ⚪ 待确认项

无独立待确认风险；上述部署及真实数据效果是定级边界，不另计重复问题。

## 🎯 修复优先级与总结

保留已证实的拒绝链；在授权环境执行相应负向矩阵；核验真实部署与实际业务授权策略。 P0/P2/P3 无需据本夹具新增修复项。

审查人：cc-code-reviewer Agent；报告版本 5.7；审查模式 security；模型档位 inherit。
