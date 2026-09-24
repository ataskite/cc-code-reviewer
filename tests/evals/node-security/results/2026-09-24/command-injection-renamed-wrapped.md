# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24 10:51
- 审查类型：存量全量
- 审查范围：项目全部生产源码（`server.js`、`tasks/resize.js`）+ 伴随文件 `package.json`
- 审查模式：security（安全专项）
- 审查模型：inherit（会话模型）
- 启用维度：1 正确性、4（仅配置安全子项）、5（仅注入/越权子项）、6 安全（全深度）、9（仅敏感信息泄露）、11（仅鉴权/错误信息）
- 跳过维度：2 类型安全、3 代码质量、7 性能、8 副作用与资源清理、10 测试质量、11 其余子项、12 设计系统一致性
- 检测到的技术栈：Node.js（Express ^4.18.0，CommonJS，HTTP 服务端口 3000）
- 项目 ignore 状态：未配置（`.cc-code-reviewer/ignore/issues.yml` 不存在）
- 文件覆盖率：生产源码 2/2 = 100%（另读伴随文件 `package.json`）
- 冻结适用控制：`/tmp/cc-eval-20260923/artifacts/command-injection-renamed-wrapped.controls.json`（security_profile=node-api，适用 11 条、排除 1 条）
- Node 攻击面索引：`/tmp/cc-eval-20260923/artifacts/command-injection-renamed-wrapped.surface.json`（仅导航候选，非发现清单；命中条目：http-route server.js:8、request-query server.js:10、child-process-exec tasks/resize.js:2/10）
- 语义增强：未注入 LSP 语义层，本轮已按框架披露降级为逐文件静态精读 + 跨模块人工数据流追踪（符号经改名与多层封装，全部传播链已逐一闭合验证，不依赖符号名猜测）

## 📊 审查范围说明

- **项目类型**：Node.js（frontend 族群，node-api profile）
- **审查范围**：`/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/command-injection/renamed-wrapped` 下全部生产源码，含子目录模块 `tasks/`
- **审查基准路径**：上述项目根目录
- **检测到的技术栈**：Express 4.x HTTP 服务（`app.listen(3000)`），CommonJS 模块，`child_process.exec` 外部命令
- **覆盖方式**：逐文件全文精读（含子目录），以入口 → 数据流 → 敏感效果为主线追踪；攻击面索引仅用于导航交叉验证
- **项目 ignore**：未配置

## 📊 执行摘要

- **整体结论**：存在 1 条证据完全闭合的 P0 命令注入（RCE）——用户可控 query 参数经改名封装的跨模块调用链传播后，以字符串拼接进入 `child_process.exec` 的 shell 命令行，且全链路无任何净化/白名单/数组传参控制。
- **最高风险点**：`GET /api/preview?file=...` 任意访问者可通过 `;`、`&&`、反引号、`$()` 等 shell 元字符逃逸参数，在服务器上执行任意命令（OWASP Top 10:2025 A05）。
- **评分**：安全性 1/10（存在直通 RCE）；可维护性 5/10（封装清晰但无任何输入校验）；性能与技术债本轮安全模式不下结论。
- **问题汇总表**：

| 级别 | 数量 |
|---|---|
| P0 | 1 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |
| 待确认 | 2 |

- **总计正式问题数**：1
- **项目 ignore 命中统计**：未配置 ignore，无过滤。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：HTTP 入口与中间件链、query 输入边界、跨模块数据流（server.js → tasks/resize.js）、`child_process` 汇聚点、错误响应信息泄露、依赖清单（express 单依赖，无 lockfile，无 `postinstall` 脚本）。
- **未充分覆盖**：运行时部署拓扑（端口 3000 是否公网可达、是否有网关/外层鉴权）无法从仓库闭合，归入待确认-1；`/tmp/preview.png` 固定输出路径的后续消费方式在仓库内无证据，归入待确认-2。
- **限制说明**：语义 LSP 未启用，已降级为静态精读；本项目符号经过改名且多层封装，本轮按真实数据流（用户输入 → 中间函数 → 命令构造）逐跳验证，未凭名称判断。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0（1 = 0 + 0 + 1 + 0）。
- **台账**：

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| `app.get('/api/preview')`（server.js:8） | 无任何主体概念：无 session/JWT/网关注入头，未挂任何认证中间件 | 触发服务端 shell 命令执行（图片转换） | `req.query.file`（客户端可控，server.js:10） | 无（整条链不存在授权决策点） | `child_process.exec`（tasks/resize.js:10） | 外部证据缺失：该端点是否应当鉴权取决于部署/网关配置，仓库内无法闭合（关联待确认-1） | 无其他入口（单一 HTTP 路由，无 RPC/消息/任务/内部变体） |

- **已验证反例**：同角色异对象、低权限高功能、跨租户/组织、对象属性、批量/嵌套资源、替代执行路径——本项目无主体、角色、租户、对象级资源与批量入口概念，六类差分反例均因前提不存在而不成立（不适用，理由如台账）；唯一可达敏感效果（未认证主体 → shell 执行）已由注入链 P0-1 与待确认-1 承接。
- **未闭合入口与外部依赖**：端口 3000 的网络暴露面、是否存在网关统一鉴权——依赖部署配置，仓库内无证据。
- **结论边界**：授权面 1 行均有绑定结论；注入类风险见 P0-1，鉴权暴露面缺口见待确认-1，不声明"系统安全"。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 全仓无身份/租户/角色上下文构造（无 ctx.user/tenant 赋值）；req.query.file 仅流入命令构造（server.js:8-15） |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 无 session 使用：未引入 express-session，无 req.session 读写（server.js 全文） |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 无外发 HTTP 客户端：全仓无 axios/fetch/got/http.request/https.request 调用 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | finding_confirmed | 见 P0-1：req.query.file（server.js:10）→ runTransformTask 跨模块传播（tasks/resize.js:8）→ buildCmd 字符串拼接（tasks/resize.js:5）→ exec 汇聚（tasks/resize.js:10），全链无净化/白名单/数组传参 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs 路径操作汇聚点：全仓无 fs.readFile/sendFile/download/createReadStream；文件参数只流入命令串（该路径风险由 CCR-NODE-CMD-001 覆盖） |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无深合并/递归 assign/lodash.merge；req.query.file 入口即 String() 标量化（server.js:10），无对象键传播 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 等查询构造（package.json 仅 express 依赖） |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等反序列化入口；仅 JSON 响应序列化输出 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无对象级资源与主体身份：单一无状态转换端点，无按 ID 定位的资源读写/列表/导出（授权面台账见上） |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无角色/权限模型与管理类业务动作；命令滥用风险已由 CCR-NODE-CMD-001 正式发现承接，入口无鉴权的暴露面归待确认-1 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 cookie 会话（未引入 session/cookie 中间件），不存在可被跨站骑劫的登录态写接口 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | resolver 排除（激活 profile=node-api，无 BFF 出站转发链路）；全仓亦无上游 HTTP 转发证据，无需语义提升 |

> 说明：控制覆盖是覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明；本轮无 `static_unsupported` / `external_evidence_missing` 状态控制。

## ✅ 最佳实践亮点

- 错误响应收敛：`/api/preview` 的 catch 分支返回固定文案 `transform_failed`（server.js:13），未向客户端泄露堆栈、命令行或内部路径。

## 🔴 P0 严重问题 (Critical Issues)

> P0 证据门槛：生产路径可达、证据完整且置信度高、后果达到事故级、没有足以阻断事故的有效防护、必须阻断发布。以下问题逐项满足。

---

### P0-1 | [维度6-安全] 用户可控 file 参数经改名封装跨模块传播后拼接进 child_process.exec，构成命令注入任意命令执行（RCE）

**位置**：tasks/resize.js:10（命令字符串拼接 tasks/resize.js:5；污点起点 server.js:10；HTTP 入口 server.js:8）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：`GET /api/preview` 的 `req.query.file` 参数（经改名函数 `runTransformTask` 跨子目录模块传播、再经 `buildCmd` 二次封装）以原始字符串拼接进入 `child_process.exec` 的 shell 命令行，攻击者用 shell 元字符即可逃逸参数执行任意命令。

**证据**（Source → Propagation → Sink → Missing Control 全链闭合，符号已改名，按真实数据流追踪而非名称判断）：

```
// server.js
 8  app.get('/api/preview', async (req, res) => {            // ← 入口：无任何认证/鉴权/输入校验中间件
10    const output = await runTransformTask(String(req.query.file || '')); // ← Source：req.query.file 客户端可控；String() 仅类型归一，不过滤任何 shell 元字符
 4  const { runTransformTask } = require('./tasks/resize');   // ← Propagation：跨子目录模块导入（改名封装层 1）

// tasks/resize.js
 4  function buildCmd(input) {                                // ← Propagation：改名封装层 2，input 即污点参数
 5    return 'convert ' + input + ' -resize 300x300 /tmp/preview.png'; // ← 命令构造：裸字符串拼接，无引号/转义/白名单/长度约束
10    exec(buildCmd(input), (err) => {                        // ← Sink：exec 经 /bin/sh -c 执行整条命令串；;、&&、`、$() 即可逃逸
```

攻击示例：`GET /api/preview?file=a.png;id` → 实际执行 `convert a.png;id -resize 300x300 /tmp/preview.png`，`id` 以 convert 进程权限运行；同理可执行反弹 shell、读取凭据文件（注意输出通道为命令自身副作用，响应仅回传固定路径）。

**安全规则 ID**：CCR-NODE-CMD-001

**标准映射**：OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78

**检测方式**：pattern

**证据状态**：静态已证实——入口（server.js:8）、Source（server.js:10）、Propagation（server.js:4 + tasks/resize.js:4/8）、Sink（tasks/resize.js:10，拼接于 :5）、控制缺失（两文件全文无任何 execFile/数组传参/shell 关闭/argv 白名单/输入净化）全部由当前仓库闭合，置信度高。

**主体/资源/决策链**：不适用（注入类发现，无主体—资源授权关系）。补充披露：该入口完全无认证，任意未认证主体均可触达 Sink。

**未授权路径与防护**：不适用（注入类发现）。现有"防护"仅为 `String()` 类型归一（server.js:10），对 shell 元字符零拦截；无任何有效缓解。

**影响**：服务以 `app.listen(3000)` 常驻（server.js:17），端点无认证即生产可达；命中即服务器任意命令执行——数据窃取、植入持久化载荷、以内网可达范围为杀伤力的横向移动（与 SSRF 同口径不因"仅内网"降级）。按「注入与 RCE 直通定级」规则，证据闭合的命令注入必为 P0、必须阻断发布。

**建议**：改用 `execFile`/无 `shell` 选项的 `spawn` 数组传参（不经 shell），文件名先取 `basename` 剥离目录段并做扩展名白名单，可执行文件名硬编码；同时使用唯一输出路径避免并发互踩（见待确认-2）：

```js
const { execFile } = require('child_process');
const path = require('path');

function runTransformTask(input) {
  const safeName = path.basename(String(input || ''));        // 剥离目录段，仅保留文件名
  if (!/^[A-Za-z0-9._-]+\.(png|jpe?g|webp)$/i.test(safeName)) {
    return Promise.reject(new Error('invalid_file'));
  }
  const out = `/tmp/preview-${process.pid}-${Date.now()}.png`; // 唯一输出路径
  return new Promise((resolve, reject) => {
    execFile('convert', ['-resize', '300x300', safeName, out], (err) => { // 数组传参、不经 shell、命令名硬编码
      if (err) reject(err); else resolve(out);
    });
  });
}
```

---

## 🟠 P1 重要问题 (Major Issues)

本级别未发现问题。

## 🟡 P2 一般问题 (Minor Issues)

本级别未发现问题。

## 🔵 P3 建议 (Suggestions)

本级别未发现问题。

## ⚪ 待确认项

---

### 待确认-1 | [维度6-安全] 预览端点无任何认证与限流，公网暴露后果依赖部署配置

**位置**：server.js:8（服务监听 server.js:17）

**置信度**：低 | **所属维度**：维度6-安全

**依据**：

```
 8  app.get('/api/preview', async (req, res) => {   // ← 全部中间件仅 express() 默认，无认证/鉴权/限流
17  app.listen(3000);                                // ← 直接监听 3000，暴露面取决于部署拓扑
```

**待确认原因**：仓库内无网关路由、部署清单、网络策略证据，无法静态闭合"该端口是否公网可达/是否由外层网关统一鉴权"；且图片预览类工具端点是否本应要求登录属业务决策，不能仅凭"无认证"定为越权漏洞（授权面台账结论：外部证据缺失）。

**建议的验证方式**：核查部署清单与网关配置确认 3000 端口暴露面；若公网/跨信任域可达，补认证（session 或 Bearer）+ 限流后复测。

**证据状态**：待确认项——依赖运行配置与部署证据。

**主体/资源/决策链**：主体为任意匿名访问者（无身份来源）；动作为触发服务端命令执行；资源为 `req.query.file` 指定输入；无授权决策点；Sink 为 `child_process.exec`。

**未授权路径与防护**：最短路径为任意客户端直接 `GET /api/preview`（无阻断点）；现有防护无，唯一实质风险已由 P0-1 承接，本条仅登记暴露面缺口。

**验证方案**：测试环境向该端点发起无凭据请求，预期（加固后）应 401/403；记录环境、请求、预期与实际结果，仅只读验证。

---

### 待确认-2 | [维度6-安全] 固定输出路径 /tmp/preview.png 被所有请求共享，存在并发互踩/跨用户内容串读风险

**位置**：tasks/resize.js:5（输出路径写死）/ tasks/resize.js:12（响应回传该固定路径）

**置信度**：低 | **所属维度**：维度6-安全

**依据**：

```
 5    return 'convert ' + input + ' -resize 300x300 /tmp/preview.png'; // ← 所有请求写同一个固定文件
12      else resolve('/tmp/preview.png');                              // ← 响应向所有客户端回传同一物理路径
```

**待确认原因**：仓库内没有任何读取/下发 `/tmp/preview.png` 的代码（无静态目录、无下载路由），串读是否可利用取决于仓库外的文件消费方式，静态证据无法闭合。

**建议的验证方式**：确认部署侧该文件的访问通道；修复上直接改用每次请求唯一输出文件名（见 P0-1 建议代码）并校验文件权限。

**证据状态**：待确认项——影响链依赖范围外文件消费方式。

**主体/资源/决策链**：不适用（非授权类发现；属共享资源竞争面的信息串读候选）。

**未授权路径与防护**：不适用（非授权类发现）。

**验证方案**：测试环境并发发起两个不同输入的转换请求后检查输出文件内容归属；预期唯一路径方案下各自独立。

---

## 🎯 修复优先级

- **P0 - 立即修复**：P0-1 命令注入（execFile 数组传参 + basename + 扩展名白名单），修复前阻断发布。
- **P1 - 尽快修复**：无。
- **P2 - 计划修复**：无。
- **P3 - 可选优化**：无（待确认-1/待确认-2 随 P0-1 修复与部署核查一并处理；P0-1 建议代码已覆盖唯一输出路径）。

## 📝 总结

- **整体架构判断**：一个极简 Express 预览服务，入口 → 封装任务模块 → 外部命令的单向链路；改名与多层封装未改变污点传播事实，全链无输入校验与安全控制。
- **本次模式核心判断**：security 模式下确认 1 条证据完全闭合的 P0 命令注入（CCR-NODE-CMD-001），11 条适用控制中 10 条已检查无发现、1 条命中；另有 2 条部署/范围外依赖的待确认项。
- **关键行动项**：1) 立即将 exec 拼接改为 execFile 数组传参并加文件名白名单（阻断发布级）；2) 核查 3000 端口暴露面并补认证与限流；3) 输出路径改为每请求唯一文件，消除共享写互踩。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
