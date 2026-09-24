# 安全审查报告

## ⚙️ 审查配置快照

- **生成时间**：2026-09-24
- **审查类型**：存量全量（单 Agent）
- **审查范围**：项目全部生产源码与伴随清单（`server.js` + `package.json`）
- **审查模式**：security（安全专项）
- **审查模型**：未注入（默认 inherit）
- **启用维度**：1 正确性、4 框架规范（仅配置安全子项）、5 状态与数据请求（仅注入/越权子项）、6 安全（全深度）、9 错误监控与可观测性（仅敏感信息泄露）、11 接口与类型契约（仅鉴权/错误信息）
- **跳过维度**：2 类型安全、3 代码质量、7 性能、8 副作用与资源清理、10 测试质量、12 设计系统一致性（security 模式边界）
- **模式说明**：security 模式同时执行 `references/security/enterprise-security-framework.md`（安全语义、取证、证据等级与分级权威依据）与 `references/languages/frontend/node-rules.md`（Node 注入面负面清单）
- **检测到的技术栈**：Node.js（CommonJS）+ Express 4 HTTP 服务；无前端框架、无构建链、无数据库、无 lockfile
- **项目 ignore 状态**：未配置（项目内无 `.cc-code-reviewer/ignore/issues.yml`）
- **文件覆盖率**：生产源码 1/1（`server.js`，100%）；伴随清单 1/1（`package.json`）
- **审查输入清单**：单 Agent 评测路径，未注入 `review-input.json`；冻结 controls 与 surface 均绑定 `review_input_sha256=84b9…c1c`（两者一致）
- **语义增强**：未注入 typescript-lsp；纯 JS 两文件全量静态精读，全部调用链在仓库内闭合，无降级损失

## 📊 审查范围说明

- **项目类型**：frontend / Node.js（`PROJECT_TYPE` 信号：`package.json` `main: server.js` + `express` 依赖；激活 security profile：node-api）
- **审查范围**：`/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/path-traversal/vulnerable` 下全部文件
- **审查基准路径**：上述项目根目录
- **启用的审查维度**：见审查配置快照
- **跳过的审查维度**：见审查配置快照
- **项目 ignore**：未配置
- **覆盖方式**：逐文件全量精读（生产源码 1 个 15 行文件 + 伴随 package.json），冻结 11 条适用控制逐条取证；攻击面索引（surface）3 处信号（http-route / request-params / fs-access）与人工阅读相互印证

## 📊 执行摘要

- **整体结论**：发现 1 个满足 P0 五项硬门槛的路径穿越任意文件读取（注入直通定级），必须阻断发布；冻结 11 条适用控制中 1 条 finding_confirmed、10 条 checked_no_finding；另有无认证暴露面待确认 1 项、加固建议 2 项。
- **最高风险点**：`server.js:10-11`——`req.params.name` 未做任何校验直接经 `path.join` 拼接进入 `fs.readFileSync`，`../` 序列可穿越 `/data` 根目录读取服务器任意文件，且端点完全匿名可达。
- **评分**：安全性：1/10（1 条 P0 直通级注入面 + 零认证零防护）；性能：未评（security 模式不启用维度 7）；可维护性：未评（security 模式不启用维度 3）；技术债务：规模极小（15 行单文件）但无测试、无 lockfile、无错误处理。
- **问题汇总表**：

| 级别 | 数量 | 编号 |
|---|---|---|
| P0 | 1 | P0-1 |
| P1 | 0 | — |
| P2 | 0 | — |
| P3 | 2 | P3-1、P3-2 |
| 待确认 | 1 | 待确认-1 |

- **总计正式问题数**：3（P0-P3）；待确认项 1（不计入正式问题数）。
- **项目 ignore 命中统计**：未配置 ignore 规则，无过滤。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：唯一 HTTP 路由 `/files/:name` 完整安全契约取证（入口→主体→资源→决策→Sink）；冻结 11 条适用控制逐条形成结论；授权面台账与六类差分反例；依赖面（`package.json`）。
- **未充分覆盖**：
  - 依赖漏洞确定性结论：仓库无 lockfile（仅 `package.json` 声明 `express ^4.18.0`），按依赖风险结论规则无法形成确定性漏洞结论，仅给供应链加固建议（P3-1）；
  - 运行时环境证据：部署网络位置（内网/公网）、生产 `NODE_ENV`、`/data` 实际内容与权限均无法从仓库闭合（对应待确认-1、P3-2）；
  - 维度 7 性能在 security 模式不启用：`fs.readFileSync` 同步阻塞事件循环、无并发/请求大小限制未作为正式问题输出，此处仅披露。
- **限制说明**：未访问任何网络（离线审查）；未注入语义工具，全部结论基于静态精读，`server.js` 全文 15 行均已读取，调用链 100% 闭合。

## 🔐 授权面覆盖（仅 Security 模式强制）

- **授权面台账**：共 1 行；已绑定 0 / 未绑定 1 / 外部证据缺失 0 / 不适用 0，对账：1 = 0 + 1 + 0 + 0。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| `GET /files/:name`（server.js:9，`app.listen(3000)` server.js:15 装配闭合） | 无主体：未挂载任何认证中间件，匿名可达（无 session/token/网关注入身份） | 读取文件（读，含穿越后越出 `/data` 根的任意路径） | `/data` 目录下文件；标识 = `req.params.name`（客户端可控字符串，可含 `../`） | 不存在任何授权决策点（无认证、无授权、无字段白名单） | `fs.readFileSync(full)`（server.js:11）+ `res.send(content)` 返回全文（server.js:12） | 未绑定（对应正式问题 P0-1） | 无：全仓库仅此 1 个路由与 1 个 listen 入口，无批量/导出/下载变体、无异步任务、无消息消费、无内部 RPC、无旧版本接口 |

- **已验证反例**：
  1. 同角色异对象：不适用——服务无主体/角色模型（全文无认证与角色概念），且 server.js:1 注释表明文件为「共享附件」，无按主体归属的对象模型；匿名全量可达风险由 P0-1 与待确认-1 覆盖；
  2. 低权限高功能：不适用——唯一动作为只读文件读取，无管理/审批/配置/导出类高权限动作；
  3. 跨租户/组织：不适用——无租户/组织上下文概念；
  4. 对象属性越权：不适用——GET 只读，未挂 body 解析器，无对象属性更新/序列化字段；
  5. 批量与嵌套资源：不适用——无批量标识与嵌套资源路由；
  6. 替代执行路径：已检查——全仓库仅 1 个 HTTP 路由 + 1 个 `listen` 入口（与攻击面索引一致），无中间件链、异步任务、消息消费、内部 RPC 或旧版本变体可绕过。
- **未闭合入口与外部依赖**：① 服务预期网络暴露面（公网/内网）与 `/data` 附件敏感性无法从仓库闭合（→ 待确认-1）；② 生产 `NODE_ENV` 未知，影响默认错误页是否泄露堆栈（→ P3-2）；③ 无其他网关/策略中心/数据库 RLS 依赖（代码未引用任何外部授权系统）。
- **结论边界**：台账唯一行结论为「未绑定」，对应正式问题 P0-1；本范围不能声明「未发现越权问题」。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 全仓库无身份/租户上下文构造：仅 server.js 一个路由，无身份字段赋值路径，req.* 未进入任何 identity/tenant/session claims（server.js:9-13 全文精读） |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 未挂载任何 session/cookie 中间件，无 req.session 写入点（server.js 全文无 session 引用） |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 无外发 HTTP 客户端：无 axios/got/fetch/http.request 引用；攻击面索引 outbound_clients 为空 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 未引入 child_process（server.js:2-4 仅 require express/fs/path），无 exec/execSync/spawn 调用 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | finding_confirmed | 见 P0-1：server.js:10 req.params.name 经 path.join 拼接后进入 server.js:11 fs.readFileSync；无 path.resolve 根前缀校验、无 basename 归一、无目录白名单 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无深合并/递归 assign：未挂 body 解析器（无 express.json/urlencoded，req.body 不存在），无 lodash.merge 类调用 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 客户端与查询构造（全文无 mongo 引用，依赖仅 express） |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化入口；依赖仅 express（package.json:7-9） |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 服务为匿名共享附件读取（server.js:1 注释「共享附件」），无用户/租户主体与对象归属模型，同角色异对象反例不成立；匿名可达暴露面另列待确认-1 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 无管理/审批/配置/导出等高权限动作；唯一路由为只读 GET（server.js:9），无角色模型与特权写 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 cookie 会话（未使用 session/cookie-parser），唯一端点为 GET 只读、无状态变更，CSRF 前置条件（cookie 会话 + 状态变更端点）不成立 |

排除控制说明：`CCR-NODE-BFFHEADER-001`（客户端请求头批量透传到上游服务）被本轮 resolver 按激活 profile（node-api）排除，计入「不适用 E = 1」；本服务无任何代理/转发行为（无上游外发请求、无请求头透传代码），未做语义提升（F = 0）。

## ✅ 最佳实践亮点

未发现足够稳定且值得单独表扬的最佳实践亮点：代码为最小可运行示例，无任何防护措施，亦无测试、错误处理与依赖锁定。

## 🔴 P0 严重问题 (Critical Issues)

> P0 五项硬门槛（生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布）必须全部满足，任一不满足不得标为 P0。

---

### P0-1 | [维度6-安全] 文件名参数未校验直接拼接进 fs.readFileSync，路径穿越可匿名读取服务器任意文件

**位置**：server.js:10（拼接点；传播至 server.js:11 sink，同类问题共 1 处）

**置信度**：高 | **所属维度**：维度6-安全

**问题**：`req.params.name`（客户端可控）未经 `path.resolve` 根前缀校验、`basename` 归一或目录白名单，直接经 `path.join` 拼接进入 `fs.readFileSync`，`../` 序列可穿越 `/data` 根目录读取服务器上任意文件并原样返回。

**证据**（Source→Propagation→Sink→Missing Control 全链闭合，代码+行号）：

```javascript
// server.js
const DATA_ROOT = '/data';                              // ← 行7：指定根目录（硬编码绝对路径）

app.get('/files/:name', (req, res) => {                 // ← 行9：入口（Source：req.params.name 客户端可控；Express 匹配后对参数做 decodeURIComponent）
  const full = path.join(DATA_ROOT, req.params.name);   // ← 行10：Propagation：path.join 只做拼接，不消除 ../
  const content = fs.readFileSync(full, 'utf8');        // ← 行11：Sink：按拼接路径同步读取任意文件
  res.type('text/plain').send(content);                 // ← 行12：文件内容原样返回调用方
});

app.listen(3000);                                       // ← 行15：入口装配在仓库内闭合（生产可达）
```

最短攻击路径（静态构造）：`GET /files/..%2f..%2f..%2fetc%2fpasswd` → 路由参数解码为 `../../../etc/passwd` → `path.join('/data', '../../../etc/passwd')` 归一化为 `/etc/passwd`（越出 `/data` 根）→ `fs.readFileSync` 读取 → 响应返回全文。Missing Control：无 `path.resolve` + 根前缀校验、无 `basename` 剥离目录段、无目录白名单、无认证/授权（三项要求的必要控制 `path.resolve-root-check` / `basename-normalization` / `allowlist-dir` 全部缺失）。

**安全规则 ID**：CCR-NODE-PATH-001

**标准映射**：OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22

**检测方式**：taint

**证据状态**：静态已证实——入口注册（server.js:9）与监听装配（server.js:15）均在仓库内闭合，Source→Propagation→Sink→Missing Control 四段证据全部由当前仓库闭合，无外部依赖。

**主体/资源/决策链**：主体 = 匿名调用者（无任何认证中间件，身份来源不存在）；受保护动作 = 读取 `/data` 目录文件；资源与标识来源 = `req.params.name`（客户端可控字符串，可穿越出根）；授权证据/决策点 = 不存在；owner/tenant/org/role/scope 绑定结果 = 未绑定；最终 Sink = `fs.readFileSync(full)`（server.js:11）+ `res.send` 返回内容（server.js:12）。

**未授权路径与防护**：最短路径 = 匿名 `GET /files/..%2f..%2f..%2fetc%2fpasswd` → 解码 `../../../etc/passwd` → `path.join` 得 `/etc/passwd` → 同步读取 → 响应返回全文。现有防护 = 无（无路径校验、无认证、无授权、无速率限制；`express` 未启用任何相关中间件，也未使用 `res.sendFile` 的 `root` 选项）。

**影响**：任意文件读取——可读取应用源码、系统配置（如 `/etc/passwd`）、部署凭据文件（可达路径内的 `.env`、密钥文件等），造成机密性全面失守；端点匿名可达，攻击无任何前置条件；`readFileSync` 同步读取攻击者指定路径同时放大拒绝服务效果。按框架「注入与 RCE 直通定级」（路径穿越越出指定根目录、生产可达且传播链证据闭合）必须定为 P0。

**建议**：文件名先取 `basename` 剥离目录段，`path.resolve` 后强制校验结果仍以根目录为前缀（含边界分隔符），并改异步读取、补错误处理：

```javascript
const DATA_ROOT_ABS = path.resolve('/data');

app.get('/files/:name', (req, res) => {
  const name = path.basename(req.params.name);            // ① 剥离任何目录段（拒绝 ../）
  const full = path.resolve(DATA_ROOT_ABS, name);         // ② 解析绝对路径
  if (!full.startsWith(DATA_ROOT_ABS + path.sep)) {       // ③ 根前缀校验（含边界分隔符，fail closed）
    return res.status(400).send('invalid file name');
  }
  fs.readFile(full, 'utf8', (err, content) => {           // ④ 异步读取，错误走显式语义
    if (err) { return res.status(404).send('not found'); }
    res.type('text/plain').send(content);
  });
});
```

如需限定可下载范围，再叠加目录/扩展名白名单（`allowlist-dir`）。

**P0 五项硬门槛复核**：生产可达（路由 + listen 仓库内闭合，唯一入口直达 sink）✓；证据完整且置信度高（四段证据全闭合）✓；事故级影响（任意文件读取 + 匿名可达）✓；缺少有效防护（无任何校验/认证）✓；必须阻断发布（注入直通定级）✓。

**验证方案**（回归用，只读、非破坏性）：测试环境分别请求 `curl http://<host>:3000/files/..%2f..%2f..%2fetc%2fpasswd`（预期修复前 200 + 文件内容，修复后 400）与 `curl http://<host>:3000/files/<正常附件名>`（预期修复前后均 200），验证穿越被阻断且正常读取不受影响。

---

## 🟠 P1 重要问题 (Major Issues)

本次未发现 P1 级问题。

## 🟡 P2 一般问题 (Minor Issues)

本次未发现 P2 级问题。

## 🔵 P3 建议 (Suggestions)

---

### P3-1 | [维度6-安全] 供应链：未提交 lockfile，依赖无法确定性校验

**位置**：package.json:7-9（依赖声明处；全仓库仅 server.js 与 package.json 两个文件）

**说明**：`express ^4.18.0` 使用浮动版本范围且无 `package-lock.json` / `npm-shrinkwrap.json`，构建不可复现，也无法按「lockfile 版本明确」规则形成任何依赖漏洞确定性结论（是否存在已知漏洞取决于实际解析版本）。

**证据**：

```
package.json
  "dependencies": {
    "express": "^4.18.0"        // ← 浮动版本范围；仓库内无任何 lockfile
  }
```

**建议**：提交 lockfile 并在 CI 使用 `npm ci` 安装；接入 `npm audit` / OSV 扫描作为依赖门禁（OWASP 2025 A03 供应链方向）。

---

### P3-2 | [维度11-接口与类型契约] 文件读取失败无错误处理，默认 500 响应可能泄露堆栈并构成存在性探测

**位置**：server.js:11

**说明**：`fs.readFileSync` 对不存在/无权限文件抛出的异常没有 try/catch，也没有统一错误中间件；Express 默认错误处理器在 `NODE_ENV ≠ production` 时会在 500 响应中返回完整堆栈与内部路径（是否泄露取决于部署环境变量，外部证据）。同时 200/500 的差异形成文件存在性探测 oracle。

**证据**：

```javascript
const content = fs.readFileSync(full, 'utf8');   // ← 抛出的异常无任何捕获/转换，直接进 Express 默认错误处理
```

**建议**：改用异步 `fs.readFile` 并显式返回 404/400 语义（见 P0-1 修复片段④）；挂载统一错误处理中间件，生产环境设置 `NODE_ENV=production`。

---

## ⚪ 待确认项

---

### 待确认-1 | [维度6-安全] 文件服务无任何认证与授权，匿名可读取全部共享附件

**位置**：server.js:9、server.js:15

**置信度**：低 | **所属维度**：维度6-安全

**依据**：

```javascript
app.get('/files/:name', (req, res) => {   // ← 无任何认证/授权中间件
  ...
});
app.listen(3000);                          // ← 默认绑定 0.0.0.0:3000，暴露面取决于部署
```

**待确认原因**：服务的预期网络暴露面（公网/内网/容器内）与 `/data` 附件的数据敏感性分级无法从仓库闭合。若面向公网或附件含敏感数据，「匿名全量读取全部共享附件」构成认证缺失级风险（可能升级为 P0/P1）；若为刻意公开的只读共享服务且 `/data` 无敏感内容，则该暴露可接受。代码层面「无认证」本身是仓库内事实，仅影响定级依赖外部证据。

**建议的验证方式**：确认部署拓扑（3000 端口可达范围）与 `/data` 内容分级；如需受限访问，增加认证中间件（如 Bearer token 校验，注意纯 Bearer 头认证可豁免 CSRF）并按需增加文件级授权；以「匿名请求 `/files/<附件名>`」验证预期拒绝是否生效。

---

## 🎯 修复优先级

- **P0 - 立即修复**：P0-1（路径穿越任意文件读取，阻断发布）
- **P1 - 尽快修复**：无
- **P2 - 计划修复**：无
- **P3 - 可选优化**：P3-1（提交 lockfile）、P3-2（错误处理与 NODE_ENV）
- **待确认**：待确认-1（确认暴露面与数据敏感性后可能升级）

## 📝 总结

- **一句话架构判断**：单路由 Express 文件服务在零认证、零路径校验状态下把客户端可控路径直接送入文件读取，安全性不达标，修复 P0 前不得发布。
- **本次模式核心判断**：注入直通类（路径穿越越出 `/data` 根）证据链完全闭合，按框架直通定级 P0；冻结 11 条适用控制逐条取证，除 CCR-NODE-PATH-001 外均未命中；授权面台账唯一行「未绑定」对应 P0-1。
- **3 个关键行动项**：① 立即实施 `basename` + `path.resolve` + 根前缀校验（含边界分隔符）并回归穿越用例；② 明确服务暴露面与认证要求（待确认-1）；③ 提交 lockfile、补最小错误处理与生产 `NODE_ENV`（P3-1/P3-2）。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit（未注入）
