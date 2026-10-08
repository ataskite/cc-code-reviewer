# 代码审查报告 - proxy-capability-secure

## ⚙️ 审查配置快照

生成时间：2026-10-08 02:43 UTC；隔离夹具全量 Security 审查；模型档位 inherit；语义增强 none（静态调用链分析）。项目 node / Express / express-session / node:http。启用维度 1、4 配置、5 注入/越权、6 安全、9 敏感泄露、11 鉴权/错误信息；其余未扫描。ignore 未配置。输入：/tmp/cc-proxy-auth-eval.44sjAD/proxy-capability-secure/review-input.json，selected 2 / excluded 0；源码 server.js 1/1（28 行），配置 package.json 1/1（9 行），全部 selected 文件 2/2，共 37 行，逐项指纹一致。非批次，没有 run-manifest。

## 📊 执行摘要

本地能力边界成立：调用者仅选择服务器已有 capability 名称，服务、Host、路径、方法及出口头由表和代码固定；逐能力权限判断在外发之前拒绝未知或无权请求，query 不得覆盖 transport。正式发现 0，待确认 1（P0/P1/P2/P3 均 0）；不能据此证明会话主体签发及下游对象权限已安全。安全性 8/10（外部身份/上游证据有限）；性能、可维护性、技术债务 N/A（未完整扫描）。

## 🔍 覆盖限制与未审查范围

已读 package.json、server.js 全部选中内容及冻结 surface，无跳过项。未联网、未运行服务、未安装依赖，没有 lockfile 漏洞结论。会话主体赋值/登录流程、真实 Ingress、上游 search 实现、Cookie 部署策略不在输入中。不能凭 public/search 命名认定上游一定公开或一定无副作用，故保留外部覆盖缺口而非伪造发现。没有本地 shell、文件、数据库、危险反序列化或显式凭据日志 Sink。

## 🔐 授权面覆盖

台账共 1 行：已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0。本地动作权限和 capability 绑定已成立；完整主体信任来源尚缺签发链。

| 入口 | 主体与可信来源 | 动作 | 资源来源 | 决策/执行点 | Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| POST /invoke | req.session.subject；会话中间件已装配，签发链缺失 | catalog-search | 客户端 capability 名+字符串 query；transport 来自固定表 | 缺主体/权限 401，未知能力 400，缺 cap.permission 403 | 固定 HTTP request → pipe | 外部证据缺失：待确认-1；本地能力授权未丢失 | 仅一个路由，未见备用 Sink |

二次扫描：低权限高功能由 includes(cap.permission) 阻断；未知能力由 Object.hasOwn 阻断，包括原型名；客户端 path/method/headers/options、大小写 Host 和重复头均不被消费。同角色异对象、跨租户、敏感属性和批量/嵌套在本地没有 ID 或字段操作；query 字符串可能由下游解释，需其数据权限证据。method 变化、列表/导出等替代路径不能改变固定 /public/search POST；全量 selected 输入无其他路由。安全契约默认行为：无主体、无权限、未知能力或参数非法均终止，只有权限匹配后外发。

## 🛡️ Security 控制覆盖

- 适用控制：15
- 已发现问题：0
- 已检查无发现：12
- 外部证据缺失：3
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 15 = 0 + 12 + 3 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 node-api 排除；仍核实请求头仅使用服务端 Host 与固定 Content-Type |
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285 | taint | external_evidence_missing | server.js:15 只从 req.session.subject 取主体、不读请求身份；主体签发、会话生命周期实现缺失，见待确认-1 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 仅读取 session.subject；没有请求对象批量写 session；缺 SECRET 时停止启动 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | server.js:8-12,21-26 固定 hostname/port/path，客户端只提供字符串 query；原生 http 不自动跟随重定向 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全部选中代码无 child_process/shell 执行 Sink |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / ASVS v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 没有文件读取/下载 Sink；出站 HTTP path 固定 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 没有深合并/动态属性写入；Object.hasOwn 拒绝继承属性作为 capability |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 没有本地数据库查询；仅显式构造字符串 query，未在本地传播查询对象 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 只有 express.json 和 JSON.stringify，没有函数或任意类型反序列化 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639 | semantic | external_evidence_missing | search 上游数据、对象与租户过滤实现缺失，无法证实返回资源归属；需上游只读权限矩阵，非已发现越权 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | server.js:16-19 主体/权限缺失 401；未知能力 400；缺 catalog:read 403；动作固定后外发 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / ASVS v5.0.0-V3.5.2 / CWE-352 | config | external_evidence_missing | 只见 public search POST，未见写动作；上游是否产生状态改变及实际 Cookie SameSite/入口策略缺失，需核实再定 CSRF |
| CCR-NODE-HOSTROUTE-001 | 客户端控制出站 Host 或路由身份 | OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346 | taint | checked_no_finding | cap.host 固定 catalog.example.test；出站头逐键构造，无客户端头或 options 覆盖 |
| CCR-NODE-PROXYCAP-001 | 客户端扩大代理目标、路径或方法能力 | OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441 | semantic | checked_no_finding | server.js:8-26 固定能力表+逐能力权限检查+query 长度/类型校验；业务参数不进入 transport 选项 |
| CCR-NODE-JWTAUTH-001 | JWT 身份接受路径缺少完整验证 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V9.1.1 / ASVS v5.0.0-V9.1.2 / ASVS v5.0.0-V9.1.3 / ASVS v5.0.0-V9.2.1 / ASVS v5.0.0-V9.2.3 / CWE-347 | semantic | checked_no_finding | 全部 selected 文件无 JWT 接受；主体只从 session 获取，不把 bearer/claims 作为身份 |
| CCR-NODE-PROXYTRUST-001 | 代理来源及转发头被错误用于安全决策 | OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346 | config | checked_no_finding | 无 trust proxy 配置，无 forwarded 值或 req.ip/hostname/protocol 的权限判断 |

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## 🟠 P1 重要问题

无。

## 🟡 P2 一般问题

无。

## 🔵 P3 建议

无。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 会话主体签发与权限来源未在冻结输入中闭合

**位置**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/proxy-capability/secure/server.js:15
**置信度**：低 | **所属维度**：维度6-安全
**依据**（server.js:14-20）：
```js
app.post('/invoke', (req, res) => {
  const subject = req.session.subject; // ← 范围内没有主体与 permissions 的签发代码
  if (!subject || !Array.isArray(subject.permissions)) return res.sendStatus(401);
  if (!Object.hasOwn(capabilities, req.body.capability)) return res.sendStatus(400);
  const cap = capabilities[req.body.capability];
  if (!subject.permissions.includes(cap.permission)) return res.sendStatus(403);
  if (typeof req.body.query !== 'string' || req.body.query.length > 100) return res.sendStatus(400);
```
**待确认原因**：缺可信登录/主体绑定、permissions 发放与撤销代码；没有证据证明可伪造身份，也没有证据证明外部会话供应链安全。不存在 req.body→session 的可见覆盖，因此不形成正式认证绕过发现。
**建议的验证方式**：读取生产实际会话签发/生命周期实现；授权测试环境发放合法会话、无会话、普通权限、撤销权限，catalog-search 分别应按权限允许或 401/403。
**证据状态**：待确认项。
**主体/资源/决策链**：会话 subject.permissions → 固定能力的 catalog:read → HTTP request；能力授权实现已读，主体签发信任根缺失。
**未授权路径与防护**：当前可见路径无已证实绕过；会话 secret 缺失拒绝启动、主体/权限缺失拒绝请求、capability 逐能力判断都构成有效本地防护，不能以缺外围代码否定它们。
**验证方案**：本地 stub search 上游+测试会话签发，测试种子权限仅有/没有 catalog:read；恶意 body 的 role/userId/permissions/transport/options 不应改变会话或出站请求。仅只读搜索，不用生产凭据，测试会话结束时销毁。
**安全规则 ID**：CCR-NODE-IDENTITY-001
**标准映射**：OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285
**检测方式**：taint

## ✅ 最佳实践亮点

Object.hasOwn 与逐能力权限校验拒绝未知能力和未授权动作；请求构造忽略全部客户端 transport 输入，字符串 query 单独校验并显式序列化。

## 🎯 修复优先级

正式 P0/P1/P2/P3：无。优先补主体签发链，其次核实上游对象过滤与写副作用/CSRF 需求；不把证据缺失计成已发现漏洞。

## 📝 总结

固定能力表在本地有效，不能用 capability 名来自客户端判为漏洞。三个后续行动：核查会话签发、核查上游权限、执行只读权限与 transport 覆盖矩阵。行号回抽与证伪复核完成，无位置修正或误报删除。
