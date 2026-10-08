# 代码审查报告 - proxy-trust-topology-unproven

## ⚙️ 审查配置快照

- 生成时间：2026-10-08；隔离夹具存量审查，审查模式 security，模型档位 inherit。
- 审查基准路径：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/proxy-trust/topology-unproven
- 正式范围：冻结 source-manifest.txt / review-input.json；server.js 1/1 文件、8/8 行，覆盖率 100%；package.json 为独立配置 1/1。selected 2 / excluded 0。
- 审查输入清单：/tmp/cc-proxy-auth-eval.44sjAD/proxy-trust-topology-unproven/review-input.json；控制：/tmp/cc-proxy-auth-eval.44sjAD/proxy-trust-topology-unproven/controls.json；surface：/tmp/cc-proxy-auth-eval.44sjAD/proxy-trust-topology-unproven/surface.json。
- 技术栈：Node.js / Express；ignore 未配置。
- 启用维度：1、4（配置安全）、5（注入/越权）、6、9（泄露）、11（鉴权/错误）；跳过 2、3、7、8、10、12 及其余非安全子项。
- 语义增强：none；已降级静态逐文件/控制流审查，未声称 LSP 或运行态验证。surface 只用于导航，未按候选自动报错。

## 📊 执行摘要

单跳代理信任加来源 IP 白名单不足以证明安全，也不足以证明生产绕过。真实直接代理、各访问路径长度、直连限制与 XFF 清洗均未提供；保留外部证据缺失。

| P0 | P1 | P2 | P3 | 待确认 | 总计 |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 |

安全性 N/A（拓扑待验证）；性能/可维护性/技术债务 N/A（非本次扫描）。没有 lockfile 或部署配置；不据依赖名/范围版本断言漏洞。

## 🔍 覆盖限制与未审查范围

已逐文件阅读 server.js 和 package.json，并完成入口到响应、默认/异常分支、身份与来源可信性检查。该夹具的 exportAccepted 仅为 JSON 标记，未提供真实导出、数据库、业务资源或生产网关/防火墙，不扩大影响。完整文件覆盖不代表 OWASP 认证或 ASVS 全量合规。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0。
- 唯一入口 × 动作：GET /admin/export × 返回管理动作接受标记；最终 Sink 为 res.json。绑定结论：外部证据缺失。主体来源为连接来源/IP 判断；无对象 ID/tenant/属性参数。
- 已完成二次扫描：低权限高功能和替代路径已追踪到唯一注册的 GET handler；反例取决于待确认-1 的代理路径与清洗证据。
- 六类反例：同角色异对象、跨租户/组织、对象属性、批量/嵌套资源均无相关输入/资源操作；低权限高功能按 IP 门槛复核；替代执行路径没有其他 handler、任务/RPC/缓存/导出实现，非注册 method 无该 Sink。
- 未闭合入口与外部依赖：生产部署、真实数据导出效果均未提供；还缺真实直接代理、路径长度、直连限制及 forwarded 清洗。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：15
- 已发现问题：0
- 已检查无发现：14
- 外部证据缺失：1
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 15 = 0 + 14 + 1 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | server.js 未见会话主体/租户赋值覆盖；IP 来源风险归 PROXYTRUST/待确认-1。 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | server.js 全文没有 Session 中间件或 req.session 写入。 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | server.js 全文只有本地响应，没有外发 HTTP 客户端或目标构造。 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | server.js 全文无进程执行或 shell Sink。 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / ASVS v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | server.js 全文无文件路径输入、文件读取/下载 Sink。 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | server.js 全文无深合并、递归赋值或动态原型写入。 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | server.js 全文无 Mongo/NoSQL 查询。 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | server.js 全文未使用函数/任意类型反序列化；JWT JSON 解码不属于危险反序列化 Sink。 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 唯一 GET /admin/export 返回固定接受标记，未读取对象 ID 或数据资源；同角色异对象与跨租户无可替换资源。 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | server.js:5 有来源权限检查；其可信性待 PROXYTRUST/待确认-1 补拓扑证据，未另证实功能授权缺口。 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / ASVS v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 唯一接口为 GET 标记响应，未使用 Cookie/Session 或状态变更。 |
| CCR-NODE-HOSTROUTE-001 | 客户端控制出站 Host 或路由身份 | OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346 | taint | checked_no_finding | server.js 全文没有出站 HTTP/代理客户端，信号导航不能构成路由身份问题。 |
| CCR-NODE-PROXYCAP-001 | 客户端扩大代理目标、路径或方法能力 | OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441 | semantic | checked_no_finding | server.js 全文没有代理调用或可由用户选择的 service/path/method 能力。 |
| CCR-NODE-JWTAUTH-001 | JWT 身份接受路径缺少完整验证 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V9.1.1 / ASVS v5.0.0-V9.1.2 / ASVS v5.0.0-V9.1.3 / ASVS v5.0.0-V9.2.1 / ASVS v5.0.0-V9.2.3 / CWE-347 | semantic | checked_no_finding | server.js 全文身份门槛为连接来源，不存在 JWT 接受面。 |
| CCR-NODE-PROXYTRUST-001 | 代理来源及转发头被错误用于安全决策 | OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346 | config | external_evidence_missing | server.js:3-8；缺直接代理身份、各入口 hop 数、直连防火墙、XFF/XFH/XFP 清洗配置；详见待确认-1。 |
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

### 待确认-1 | [维度6-安全] 单跳代理信任依赖未提供的入口拓扑与转发头清洗

**位置**：server.js:3

**置信度**：低（部署风险） | **所属维度**：维度6-安全

**问题**：req.ip 是管理接口的权限依据，trust proxy=1 只表达跳数，未提供实际可信对端与全部入口链路证据。

**依据/证据**（server.js:3-8）：
```js
app.set('trust proxy', 1); // ← 可信跳数须与每条真实入口对应
app.get('/admin/export', (req, res) => {
  if (req.ip !== '192.0.2.10') return res.sendStatus(403); // ← 转发来源参与权限判断
  res.json({ exportAccepted: true });
});
app.listen(3000);
```

**待确认原因**：真实直接对端、全部入口长度、端口直连限制和 forwarded 头替换配置缺失。hop=1 本身既不证明攻击也不证明安全。

**影响**：若存在直连/短链旁路或代理保留客户端转发头，攻击者可能影响来源并获得接受标记；若所有入口强制可信代理且覆盖重建转发头，该反例可被阻断。未证实任一部署情况。

**建议**：补齐实际代理及防火墙配置，再按所有入口确定精确可信对端/拓扑策略；不要盲目调整为 false 或 hop=1。管理接口应同时绑定可信主体权限。

**建议的验证方式/验证方案**：先只读核验测试部署的代理地址、全部路由/旁路、防火墙及 XFF/XFH/XFP 替换策略；在授权隔离环境使用虚构请求测试直连、正常链、短链、多 hop 与伪造头，非授权来源均应 403，只有受信路径允许，停止临时环境回滚。

**证据状态**：待确认项；未执行请求或运行态验证。

**主体/资源/决策链**：连接对端/forwarded 链 → 单跳 req.ip 解析 → 192.0.2.10 白名单 → exportAccepted；可信来源绑定取决于范围外真实拓扑。 无 owner/tenant 对象参数。

**未授权路径与防护**：白名单不匹配返回 403；可信 hop-count 本身没有证明真实对端身份、路由长度一致或边缘清洗。 尚未证成未授权路径。

**安全规则 ID**：CCR-NODE-PROXYTRUST-001

**标准映射**：OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346

**检测方式**：config

## 🎯 修复优先级与总结

待确认：先补代理拓扑与清洗证据；再验证直连/短链/多 hop；据验证结果调整可信来源策略。 P0/P2/P3 无需据本夹具新增修复项。

审查人：cc-code-reviewer Agent；报告版本 5.7；审查模式 security；模型档位 inherit。
