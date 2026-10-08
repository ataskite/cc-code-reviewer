# 代码审查报告 - eval-host-routing-secure

## ⚙️ 审查配置快照

- 生成时间：2026-10-08T02:43:10Z
- 审查类型：隔离夹具全量正向测试；范围仅 source-manifest.txt，未读取预期清单。
- 审查模式：security；模型：当前继承模型；语义增强：none，使用静态调用链。
- 启用维度：1、4配置安全、5注入/越权、6安全、9敏感泄露、11鉴权/错误信息；跳过2、3、7、8、10、12。
- 技术栈：Express、Node.js、node:http；项目 ignore：未配置。
- 审查输入清单：/tmp/cc-proxy-auth-eval.44sjAD/host-routing-secure/review-input.json；selected=2，excluded=0。
- 生产源码覆盖：1/1，13 行；package.json 配置另计1；清单全部2文件均已读，全部21行。
- 本次非分批，运行覆盖清单不适用。未联网、安装依赖或向生产/测试服务发请求。

## 📊 审查范围说明

基准路径：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/host-routing/secure。正式输入为 /tmp/cc-proxy-auth-eval.44sjAD/host-routing-secure/source-manifest.txt；冻结控制 /tmp/cc-proxy-auth-eval.44sjAD/host-routing-secure/controls.json 与索引 /tmp/cc-proxy-auth-eval.44sjAD/host-routing-secure/surface.json 仅供导航和覆盖对账。已检查入口、真实 headers 构造、HTTP 调用、返回与异常路径及全部适用控制。

## 📊 执行摘要

固定网络地址、固定路由 Host 和固定预览动作形成可见边界；未发现本范围已证实的安全缺陷。
安全性：8/10（限静态输入）；性能、可维护性、技术债务：N/A（未作全量质量扫描）。

| P0 | P1 | P2 | P3 | 待确认 | 总数 |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 | 0 |

## 🔍 覆盖限制与未审查范围

未执行运行态测试；无 lockfile，不能下依赖 CVE 结论。Ingress、DNS、网关入口、上游认证/权限/响应内容与生产暴露均无范围内证据。这些部署事实未验证，不把服务端固定 Host 宣称为完整系统安全证明。

## 🔐 授权面覆盖

- 台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 0 / 不适用 1。
- 授权面二次扫描：六类反例均已静态复核。

| 入口 | 主体与来源 | 动作与资源 | 决策及 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|
| POST /preview | 匿名请求；没有本地主体消费 | 转发 query 到预览；固定预览 Host | 固定业务 tuple；不是已识别的受保护动作；http.request→pipe(res) | 不适用 | 全部正式源码无其他入口 |

同角色异对象、跨租户、对象属性、批量/嵌套：没有本地对象/租户/存储模型，不能凭 query 编造对象越权。低权高功能：只见固定 public/preview，无高权动作证据。替代执行路径：唯一 POST 入口；业务字段未进入 transport options。网关与上游部署授权证据未闭合。

## 🛡️ Security 控制覆盖

- 适用控制：15
- 已发现问题：0
- 已检查无发现：15
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 15 = 0 + 15 + 0 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / OWASP A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | server.js:6-11 仅接受并转发 query；忽略客户端 header/envelope，无主体或租户构造。 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全部代码无 session 构造或写入，不存在请求体批量写会话路径。 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | server.js:7-8 固定 http、连接主机、路径、method、Host；node:http 不自动跟随重定向，query 不参与目标拼接。DNS 运维事实未验证。 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全部代码无 child_process 或 shell 执行。 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / ASVS v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs/sendFile/download；请求值不进入文件路径。 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无递归合并或沿原型链写入；浅复制 headers 不证明全局原型污染。 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无数据库查询或 NoSQL 客户端。 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 仅 express.json 与 JSON.stringify，不还原函数/实例。 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / ASVS v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象 ID 查询/写入；query 为预览数据，未见对象归属 Sink；下游对象语义未在范围内。 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 唯一 POST /preview 调用固定 /public/preview；无管理/配置/导出动作证据，不因匿名入口推定垂直越权。 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / ASVS v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 cookie/session 身份消费或状态写入；本地仅预览转发，无法证明 Cookie 会话写接口。 |
| CCR-NODE-HOSTROUTE-001 | 客户端控制出站 Host 或路由身份 | OWASP A01:2025 / API7:2023 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V1.3.6 / CWE-918 / CWE-346 | taint | checked_no_finding | server.js:8 显式固定 Host=preview.example.test；无请求 options spread 或末尾覆盖。 |
| CCR-NODE-PROXYCAP-001 | 客户端扩大代理目标、路径或方法能力 | OWASP A01:2025 / API5:2023 / API10:2023 / ASVS v5.0.0-V8.2.1 / ASVS v5.0.0-V8.3.1 / ASVS v5.0.0-V8.3.3 / CWE-285 / CWE-441 | semantic | checked_no_finding | server.js:6-11 固定预览业务接口；query 必须字符串且≤100；无目标/path/method/headers 覆盖，无可见高权动作。 |
| CCR-NODE-JWTAUTH-001 | JWT 身份接受路径缺少完整验证 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V9.1.1 / ASVS v5.0.0-V9.1.2 / ASVS v5.0.0-V9.1.3 / ASVS v5.0.0-V9.2.1 / ASVS v5.0.0-V9.2.3 / CWE-347 | semantic | checked_no_finding | 无 token 到主体接受路径，未以 JWT claims 作认证；下游策略未作安全声明。 |
| CCR-NODE-PROXYTRUST-001 | 代理来源及转发头被错误用于安全决策 | OWASP A02:2025 / API8:2023 / ASVS v5.0.0-V4.1.3 / ASVS v5.0.0-V15.3.4 / CWE-346 | config | checked_no_finding | 无 trust proxy 配置，亦无 forwarded→IP/租户/protocol/Cookie/限流安全决策。 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | 冻结 node-api profile 排除此控制；没有客户端头转发。 |

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## ✅ 最佳实践亮点

服务端显式构造 headers，不扩展客户端传输对象；query 类型与长度受限。

## 🎯 修复优先级

P0：没有已证实条目。P1：无。P2：无。P3：无。本报告未执行任何修复。

## 📝 总结

固定预览路由在所给源码内拒绝了客户端传输覆盖。下一步：保留 Host/options 反例回归；核对部署路由边界；补 lockfile 依赖验证。

**审查人**：cc-code-reviewer 正向评估 Agent；**报告版本**：5.7；**审查模式**：security；**模型档位**：inherit。
