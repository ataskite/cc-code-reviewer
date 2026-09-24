# 安全审查报告

## ⚙️ 审查配置快照

| 项 | 值 |
|---|---|
| 生成时间 | 2026-09-24 |
| 审查类型 | 存量全量 |
| 审查模式 | security（维度 6 全深度 + 配置安全/注入越权/敏感泄露/鉴权与错误信息交叉子项） |
| 语言 / 项目类型 | frontend / Node.js（express） |
| Security profile | node-api |
| 审查范围 | 项目全部生产源码：server.js（唯一正式源文件，24 行，逐行全量阅读）；伴生配置 package.json 一并核对 |
| 冻结适用控制 | /tmp/cc-eval-20260923/artifacts/command-injection-execfile-bound.controls.json（适用 11 条 / 排除 1 条） |
| 攻击面索引（仅导航） | /tmp/cc-eval-20260923/artifacts/command-injection-execfile-bound.surface.json（sensitive_sinks：child-process；request-source：req.query.file；outbound_clients：空） |
| 冻结输入指纹 | review_input_sha256=95575e227db51111670c03489dc79b40c628ef1e1e02bce79098f7c6a83428a0 |
| 上游基线 | upstream_manifest_sha256=44601e08b8d9a036b9cea822aa57dd22757119b284874cedbf6f0cf5a9f6baea（离线本地快照，零网络访问） |
| 项目 ignore 规则 | 未配置 |
| 文件覆盖率 | 正式生产源码 1/1（100%） |

## 📊 执行摘要

- **整体结论**：**未发现正式问题**。各级别计数：P0：0 / P1：0 / P2：0 / P3：0；待确认项：2。
- **核心判断**：唯一用户输入 `req.query.file` 进入 `child_process` 前存在两层真实有效的防护——① `path.basename` + 等值校验（server.js:12-16）封死一切目录段（绝对路径、`../` 穿越、子目录一律 400 拒绝），文件名被约束为进程 CWD 内纯 basename；② `execFile` 以数组传参且未启用 shell（server.js:18），命令名硬编码、全程不经 shell 解释，`;`、`$()`、反引号、空格等元字符仅为单个 argv 字面量——**CCR-NODE-CMD-001 的命令注入面在语义上被消除，防护成立**。
- **最高风险点**：无正式问题。残余面集中在两处且均未闭合为正式发现（见待确认项）：固定输出路径 `/tmp/preview.png` 的并发竞态与符号链接覆盖（部署依赖）；用户值未置于 `--` 之后/无字符集白名单的参数语义残余（`-` 开头文件名可能被 convert 按选项解析）。
- **评分参考**：安全 4.5/5（扣 0.5 为待确认残余面）；性能/可维护性/技术债不在 security 模式评分范围。
- **问题汇总表**：无正式问题；待确认 2 条（见「⚪ 待确认项」）。

## 📊 审查范围与覆盖情况

- **项目类型**：Node.js / express 最小预览服务（package.json `main: server.js`，依赖仅 `express ^4.18.0`）。
- **审查基准路径**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/command-injection/execfile-bound
- **覆盖方式**：正式生产源码 server.js 逐行全量阅读（1/1，100%）；package.json 作为伴生配置核对依赖与入口一致性（`main: server.js` 与实际入口一致）。无测试源、无其他目录。
- **攻击面索引核对**：surface.json 所列 sensitive_sinks（server.js:5/18 child-process）与 request-source（server.js:11 req.query.file）均已在真实代码中逐一验证；索引仅作导航，不作为发现清单。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：命令执行链（execFile 参数构造、shell 选项、命令名可控性）；文件路径链（basename 收敛边界、响应是否回传文件内容）；11 条适用控制的全部 source/sink 是否存在（session、外发 HTTP 客户端、深合并、Mongo、反序列化、对象级/功能级授权面、Cookie 会话均逐一排除）。
- **未充分覆盖**：目标程序 ImageMagick `convert` 的选项解析行为与 policy.xml 配置（仓库外，无法静态闭合）；部署网络位置与多租户形态；依赖漏洞结论——仓库无 lockfile，按依赖风险结论规则只能给出依赖扫描建议，不形成漏洞结论。
- **限制说明**：本审查为纯静态语义审查（零网络、零 URL 访问）；语义工具未启用，攻击面结论以逐行阅读 + 冻结索引交叉验证为准。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 0 / 不适用 1（1 = 0 + 0 + 0 + 1）。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| GET /api/preview（server.js:10） | 无身份层：匿名可达，无 session/JWT/网关注入主体 | 调用 convert 生成缩略图（外部进程执行） | 文件名 req.query.file（server.js:11），经 basename+等值校验收敛为 CWD 内纯文件名 | 无：仓库内不存在任何身份/角色/租户决策点 | execFile('convert', …)（server.js:18）+ 写固定路径 /tmp/preview.png | 不适用：夹具无主体与对象归属模型，命令名与输出路径均固定，不存在对象级或功能级授权面 | 无：全仓库仅此一个路由，无批量/导出/下载/异步/消息/内部入口 |

- **已验证反例**：同角色异对象、低权限高功能、跨租户/组织、对象属性越权、批量/嵌套资源均**不适用**——代码证据：全仓库无角色/租户/对象归属概念，唯一动作即服务自身的公开功能（缩略图生成），且响应不返回任何对象内容（仅固定路径字符串 `{preview:'/tmp/preview.png'}` 或固定错误码）；替代执行路径已检查——除 `app.get('/api/preview')` 外无任何路由、定时任务、消息消费者或内部调用。
- **未闭合入口与外部依赖**：`app.listen(3000)`（server.js:24）绑定全部网络接口且无认证层——该服务的网络暴露面与是否需要认证由部署形态决定，仓库内不可闭合；无网关/策略中心/数据库 RLS 等外部授权依赖。
- **结论边界**：每个「入口 × 受保护动作」均已给出绑定结论且反例均记录理由，本仓库范围内可写「未发现越权问题」；该结论限于本夹具无身份/对象归属模型的事实，不构成对生产部署免认证的背书。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：0
- 已检查无发现：11
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 11 = 0 + 11 + 0 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | req.query.file（server.js:11）唯一去向是文件名变量（server.js:12）并进入 execFile 参数（server.js:18）；全文件无任何身份/租户上下文构造点（无 req.user/tenant/session/claims 写入），客户端字段无法覆盖服务端身份。 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 未引入 express-session/cookie-session 等会话中间件，全文件无 req.session 读写点，mass assignment 面不存在。 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 全文件无 http.request/https.request/fetch/axios/got 等外发客户端（攻击面索引 outbound_clients 为空，与代码一致）；req.query.file 唯一 sink 是 execFile 参数，不存在服务端外发请求目标。 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 防护成立，逐条举证：① execFile 数组传参且未设置 shell 选项（server.js:18）——`;`、`$()`、反引号、空格等 shell 元字符仅作为单个 argv 字面量传入，不经任何 shell 解释，元字符注入面消除；② 可执行文件名硬编码 'convert'（server.js:18），命令本身不可控；③ 文件名收敛（server.js:12-16）：path.basename 剥离目录段且要求 safeName === raw——含 `/` 的一切输入（绝对路径、`../` 穿越、子目录段）均被 400 拒绝，空串与含 NUL 拒绝；反斜杠在 POSIX basename 语义下非分隔符，仅作普通文件名字符，无目录效果。残余面（不构成控制发现，另见待确认-2）：用户值未置于 `--` 之后、无字符集白名单，`-` 开头文件名可能被 convert 按选项解析，但其余 argv 均为固定值（'-resize'/'300x300'/'/tmp/preview.png'），静态无法闭合为危险选项参数链。 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs.readFile/res.sendFile/res.download/fs.createReadStream；convert 虽以 safeName 为输入文件名，但 basename+等值校验使其被限制为进程 CWD 内纯文件名（任何含 `/` 的路径、绝对路径、`../` 序列因 safeName !== raw 被 400 拒绝，server.js:14）；且响应只返回固定路径字符串，不回传文件内容，任意文件读取链不成立。 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无 lodash.merge/deepmerge/递归 assign/extend 等深合并点；req.query.file 经 String() 归一为标量字符串（server.js:11），无对象键进入任何合并或原型链写入。 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 等数据库客户端，全文件不存在查询构造点；用户输入不进入任何数据查询。 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/serialize-javascript/yaml.load 等反序列化入口；请求参数仅作标量字符串消费，不存在对象/函数还原。 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 无数据库/对象 ID 查询与对象数据返回；唯一入口不响应对象内容（仅固定路径字符串），不存在主体—对象绑定面；授权面台账见「授权面覆盖」（1 行，结论：不适用，理由在案）。 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无管理/审批/配置/导出/删除等高权限动作分类；唯一动作即服务自身的公开功能（缩略图生成），命令名与输出路径固定，无角色判定层可绕过；匿名可达性的部署边界已在「授权面覆盖」披露。 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 Cookie 会话：未引入 express-session/cookie-parser，响应不 Set-Cookie，浏览器凭据无法被跨站自动携带，CSRF 前提（凭据携带型状态变更）不成立；当前为无凭据匿名 GET。 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | resolver 排除（激活 profile: node-api，非 node-bff，无上游代理层）；代码证据一致：无任何出站 HTTP 转发，req.headers 未被消费，未见可语义提升为 finding_confirmed 的风险。 |

## ✅ 最佳实践亮点

- **命令注入正解落地**：`execFile` + 数组传参 + 硬编码命令名（server.js:5、18），全程不经 shell 解释，与 node-rules「Node 服务端注入与危险 API 负面清单」命令注入正解完全一致。
- **basename 等值校验强于常规写法**：`safeName !== raw` 即拒绝（server.js:14），一次性封死绝对路径、`../` 穿越与子目录段，比"仅 join/resolve 前缀检查后仍接受"的实现更早失败；同时拒绝空串与 NUL。
- **错误响应最小化**：仅返回固定错误码字符串 `invalid_file_name` / `convert_failed`（server.js:15、19），不泄露内部路径、命令细节或堆栈。

## 🔴 正式问题（P0–P3）

本次未发现满足正式定级门槛的问题（P0：0 / P1：0 / P2：0 / P3：0）。两条残余面因证据链未闭合（依赖目标程序选项解析行为与部署形态）按框架规则归入待确认项，见下节。

## ⚪ 待确认项

---

### 待确认-1 | [维度6-安全] 固定输出路径 /tmp/preview.png 存在并发竞态与符号链接覆盖面（部署依赖）

**位置**：server.js:18

**置信度**：低 | **所属维度**：维度6-安全

**依据**：
```js
execFile('convert', [safeName, '-resize', '300x300', '/tmp/preview.png'], (err) => { // ← 输出路径硬编码于全局可写目录 /tmp，多请求共用同一文件
  if (err) return res.status(500).json({ error: 'convert_failed' });
  res.json({ preview: '/tmp/preview.png' });
});
```

**待确认原因**：经典不安全临时文件形态（CWE-377 类）——`/tmp` 为全局可写目录，输出文件名固定可预测。若部署在多用户主机且服务以较高权限运行，本地攻击者可预置 `/tmp/preview.png` 符号链接指向受害者文件，经 convert 输出实现越权覆盖；并发请求同写一个文件也会互相破坏。利用前提（同机本地账户、服务权限、共享目录）完全取决于部署形态，仓库内无法闭合。

**建议的验证方式**：在隔离测试环境以低权限账户预置 `/tmp/preview.png` → 指向自建哨兵文件的符号链接，调用一次 `/api/preview`，观察哨兵文件是否被覆盖；同时确认部署是否为单租户容器（容器内该面显著收敛）。

**证据状态**：待确认项（静态已识别形态，攻击效果依赖仓库外部署条件）

**主体/资源/决策链**：不适用（非授权类条目）

**未授权路径与防护**：不适用（非授权类条目）

**验证方案**：如上「建议的验证方式」，非破坏性、仅使用自建哨兵文件；修复建议：每次请求用 `fs.mkdtemp` 生成专属目录或随机后缀文件名承载输出，用后清理。

---

### 待确认-2 | [维度6-安全] 用户文件名未置于 `--` 之后且无字符集白名单，`-` 开头值存在被 convert 按选项解析的参数语义残余

**位置**：server.js:14-18

**置信度**：低 | **所属维度**：维度6-安全

**依据**：
```js
if (safeName !== raw || safeName === '' || safeName.includes('\0')) { // ← 校验拒绝目录段/空串/NUL，但未拒绝 "-" 前缀，也无字符集白名单
  return res.status(400).json({ error: 'invalid_file_name' });
}
execFile('convert', [safeName, '-resize', '300x300', '/tmp/preview.png'], (err) => { // ← 用户值位于 argv 首位，未置于 "--" 之后
```

**待确认原因**：命令注入（shell 元字符）主链已被 execFile 数组传参消除，CCR-NODE-CMD-001 控制结论不受影响；但 ImageMagick `convert` 对 `-` 开头的首参数可能按选项而非文件名解析（参数注入残余类）。由于 argv 其余三项均为固定值（`-resize`/`300x300`/`/tmp/preview.png`），静态分析无法把任何具体选项组合闭合为危险效果（如读/写任意文件或代码执行），且实际解析行为取决于仓库外的 convert 版本与 policy.xml，无法在本仓库内确认。

**建议的验证方式**：在隔离环境分别请求 `?file=-write`、`?file=-read`、`?file=-` 等取值，观察 convert 行为是否产生选项语义（进程错误码/产生的文件与按文件名处理时不同）；确认生产 convert 版本是否支持 `--` 终结符。

**证据状态**：待确认项（残余面识别，攻击链依赖仓库外目标程序行为）

**主体/资源/决策链**：不适用（非授权类条目）

**未授权路径与防护**：不适用（非授权类条目）

**验证方案**：如上「建议的验证方式」，非破坏性探测；修复建议：将用户值置于 `--` 终结符之后，或对文件名施加字符集白名单（如 `/^[A-Za-z0-9][A-Za-z0-9._-]*$/`，首字符排除 `-`）。

---

## 🎯 修复优先级

- P0 - 立即修复：无。
- P1 - 尽快修复：无。
- P2 - 计划修复：无。
- P3 - 可选优化：无（两条待确认项按验证结论决定是否升级或关闭）。
- 待确认项：优先在部署评审中闭合待确认-1（输出路径），并在依赖锁定时补充待确认-2（`--`/字符集白名单加固，成本极低）。

## 📝 总结

- **一句话整体判断**：一个以 execFile 数组传参 + basename 等值校验正确封死命令注入与路径穿越的 Node 预览服务最小实现，11 条适用安全控制全部检查无发现，无正式问题。
- **本次模式核心判断**：CCR-NODE-CMD-001 防护按真实语义成立——不经 shell 的数组传参使元字符仅是字面量，文件名被收敛为无目录段的纯 basename；残余面（`--`/字符集白名单、固定 /tmp 输出路径）证据链未闭合，按框架规则归待确认而非降级输出。
- **3 个关键行动项**：① 部署评审确认 /tmp/preview.png 的多用户/并发暴露并改用 mkdtemp 或随机后缀（待确认-1）；② 低成本加固：用户值置于 `--` 之后或加字符集白名单（待确认-2）；③ 提交 lockfile 并跑一次依赖扫描（当前 `express ^4.18.0` 无锁定版本，按依赖风险结论规则不形成漏洞结论）。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
