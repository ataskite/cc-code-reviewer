# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查范围：`/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/path-traversal/root-bound`（生产源码 `server.js` 1 个文件，共 24 行；`package.json` 作为伴随依赖/入口证据读取）
- 审查模式：security（语言 frontend / Node.js）
- 审查模型：冻结注入参数（security 单 Agent）
- 启用维度：维度 1、4（配置安全子项）、5（注入/越权子项）、6（全深度）、9（敏感信息泄露子项）、11（鉴权/错误信息子项）
- 跳过维度：2、3、7、8、10、12（security 模式矩阵外）
- 语义增强：未注入（本报告为静态逐文件精读，未使用语义索引查询，不作语义查询声明）
- 冻结适用控制：`/tmp/cc-eval-20260923/artifacts/path-traversal-root-bound.controls.json`（适用 11 条 / 排除 1 条；激活 profile：node-api；review_input_sha256 与 surface 一致）
- Node 攻击面索引（仅导航候选）：`/tmp/cc-eval-20260923/artifacts/path-traversal/root-bound` 同目录 `path-traversal-root-bound.surface.json`（1 个 http-route、1 个 request-params 源、1 个 fs-access sink）
- 项目 ignore 状态：未配置
- 文件覆盖率：正式生产源码 1/1（100%）

## 📊 审查范围说明

- **项目类型**：Node.js 最小文件服务（express ^4.18.0，无构建层、无前端 bundle）
- **审查范围**：仓库全部生产源码；`src/test` 类目录不存在
- **审查基准路径**：`/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/path-traversal/root-bound`
- **检测到的技术栈**：Node.js + express 4.x（`package.json` dependencies 仅 express，`main: server.js`）
- **启用的审查维度**：见审查配置快照
- **跳过的审查维度**：见审查配置快照
- **项目 ignore**：未配置（未发现 `.cc-code-reviewer/ignore/issues.yml`）
- **覆盖方式**：逐文件全量精读（`server.js` 24 行全部读取）+ 11 条冻结适用控制逐条结论 + 授权面二次扫描（入口 × 受保护动作台账）

## 📊 执行摘要

- **整体结论**：本服务的唯一攻击面是 `GET /files/:name` 文件读取端点。核心路径穿越防护成立（basename 收敛 + `path.resolve` 根锚定 + 含边界分隔符的根前缀校验，校验与读取同一目标），未发现正式问题。
- **最高风险点**：无正式问题；1 条待确认项——端点本身无认证中间件，部署层（网关/内网边界）是否强制鉴权无法从仓库闭合。
- **各级别计数**：P0：0 条 / P1：0 条 / P2：0 条 / P3：0 条 / 待确认：1 条；**正式问题共 0 条（未发现正式问题）**。
- **控制台账**：适用控制 11 条，全部 checked_no_finding；排除控制 1 条（CCR-NODE-BFFHEADER-001，profile 未启用且无语义提升证据）以 not_applicable 披露。
- **安全性评分**：路径穿越维度防护成立（三层防御闭合）；授权/认证维度存在外部不可见项，已按待确认披露。

## 🔴 P0 严重问题

本次未发现满足 P0 五项硬门槛的问题。已按 P0 → P1 → P2 → P3 → 待确认继续输出其余风险。

## 🟠 P1 重要问题

未发现 P1 问题。

## 🟡 P2 一般问题

未发现 P2 问题。

## 🔵 P3 建议

未发现 P3 问题。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 无认证的共享文件读取端点，部署层鉴权状态仓库内不可闭合

**位置**：server.js:11（同类问题共 1 处）

**置信度**：低 | **所属维度**：维度6-安全

**证据状态**：待确认项（依赖网关/部署配置等仓库外证据）

**依据**：
```
const app = express();
...
app.get('/files/:name', (req, res) => {   // ← 无任何认证/授权中间件
  ...
});
app.listen(3000);                          // ← 直接监听 3000，未见入口收敛
```

**待确认原因**：代码内无身份来源、无认证中间件；`server.js:1` 注释表明 `/data` 为「共享附件」（按名称读取返回给调用方），即资源本身无对象级归属，匿名可达是否为设计预期取决于部署拓扑（是否置于网关/内网边界之后、`/data` 内容是否含敏感文件）——这些均为运行配置证据，静态审查不可闭合，不构成正式问题。

**建议的验证方式**：确认部署拓扑与入口清单：1) 该端口是否仅内网/网关后可达（curl 直连 `GET /files/<name>` 不带凭据验证实际可达性）；2) 核对 `/data` 实际内容清单确认是否含敏感文件；3) 若需收敛，增加认证中间件或将服务置于统一鉴权网关之后。

---

## 🔐 授权面覆盖（仅 Security 模式强制）

- **授权面台账**：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 0 / 不适用 1，且 1 = 0 + 0 + 0 + 1。
- **台账**：

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|------|----------------|------|---------------------|--------------------|-----------|----------|----------|
| `GET /files/:name`（server.js:11） | 代码内无身份来源（无认证中间件，匿名调用方） | 读取共享文件 | `req.params.name`（路径参数），经 basename+resolve 收敛到 `/data` 下 | 无对象级授权决策点；边界防护为路径根校验（server.js:13-16） | `fs.readFileSync`（server.js:17）→ `res.send` | 不适用：资源为共享附件（server.js:1 业务证据），无主体—资源归属模型，同角色异对象/跨租户/属性越权反例均无对象边界可越 | 无（单一路由，无批量/导出/异步/旧版本变体） |

- **已验证反例**：同角色异对象（不适用——无对象归属模型，资源按设计共享）、低权限高功能（不适用——无管理/审批/配置/导出等高权限动作，唯一路由为只读 GET）、跨租户/组织（不适用——无租户上下文）、对象属性越权（不适用——无可变对象/mass assignment 写入面）、批量与嵌套资源（不适用——无批量/嵌套入口）、替代执行路径（无——单文件单路由，`app.listen(3000)` 为唯一监听）。
- **未闭合入口与外部依赖**：部署层认证/入口收敛（网关配置）与 `/data` 内容治理为仓库外证据——对应待确认-1。
- **结论边界**：本范围内每个「入口 × 受保护动作」均有绑定结论；唯一动作为共享资源读取且无归属模型，故未发现越权问题；匿名可达性的部署侧证据缺口已按待确认披露，不据此宣称整体安全。

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
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025 / A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3 / v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 全文件无身份/租户上下文构造（无 userId/tenantId/role/isAdmin 进入 ctx/session/claims 类 sink）；req 派生值仅 `req.params.name` 一处（server.js:13），且只流入受根校验保护的文件路径 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 无会话面：依赖仅 express（package.json:8-9），未引入 express-session，全文无 req.session 读写 |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 无服务端外发 HTTP 客户端（无 fetch/axios/got/http.request/https.request；攻击面索引 outbound_clients 为空） |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 无 child_process 引用（server.js:4-6 仅 require express/fs/path），无 exec/execSync/spawn |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2 / v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 防护成立（server.js:13-17）：① `path.basename(req.params.name)` 剥离全部目录段——任何 `../` 载荷只剩末段；② `path.resolve(DATA_ROOT, base)` 锚定根目录得到绝对路径；③ `full.startsWith(DATA_ROOT + path.sep)` 即 `/data/` 前缀校验含边界分隔符（杜绝 `/data-evil` 型前缀碰撞），越界即 throw → 403；④ 校验目标与 `fs.readFileSync(full)` 读取目标为同一变量 full，无 TOCTOU。边界用例逐一核验：输入 `..` → resolve 为 `/` 被拒；全斜杠输入 → basename 返回 `/` → resolve 为 `/` 被拒；空名 → resolve 为 `/data`（无尾分隔符）被拒；POSIX 上反斜杠不构成路径分隔符，`..\` 载荷停留在 `/data` 内字面文件名，不产生逃逸 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | 无深合并/递归 assign/lodash.merge；GET 路由未挂任何 body 解析器，req.body 不存在，`__proto__`/`constructor` 键无入口 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 MongoDB/Mongoose 客户端与查询构造（无 db 连接、无 find/findOne） |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 无 node-serialize/yaml.load 等危险反序列化入口；代码仅按 utf8 文本读取 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2 / v5.0.0-V8.3.3 / CWE-639 | semantic | checked_no_finding | 资源为 `/data` 共享附件（server.js:1 业务证据：按名称读取共享附件返回调用方），无对象级归属模型，不存在「他人对象 ID」可替换；授权面台账该行结论为不适用；部署层鉴权缺口见待确认-1 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 唯一入口为只读 GET（server.js:11），无管理/审批/配置/导出/删除等高权限动作，无角色/等级分层可垂直跨越 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 控制前提不成立（非默认豁免，代码证据闭合）：无 Cookie 会话（无 session 中间件、无 Set-Cookie）且无状态变更端点——唯一路由为只读 GET，无写/删/配置操作可被跨站触发 |
| CCR-NODE-BFFHEADER-001 | 客户端请求头批量透传到上游服务 | OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290 | taint | not_applicable | resolver 排除（激活 profile 为 node-api，node-bff 未启用）；代码内无出口代理/上游转发（无 axios/http 转发面），无语义提升证据 |

说明：`不适用 E` = 冻结排除控制数 1 − 语义提升 0；控制覆盖是覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：`server.js` 全部 24 行（唯一生产源码文件）；`package.json` 依赖与入口；11 条冻结适用控制逐条台账结论；授权面二次扫描（1 行台账 + 六类差分反例）。
- **未充分覆盖**：`/data` 目录内容治理属运行时内容（如目录内符号链接指向根外的 symlink 逃逸取决于实际文件系统状态，静态不可见——按共享附件设计，该目录内容应为受控清单）；部署层认证/网络边界见待确认-1。
- **限制说明**：本报告为静态审查结论，「未发现正式问题」不等于「系统安全」；`fs.readFileSync` 同步读取的性能/事件循环影响属维度 7（security 模式未启用），不在本报告结论内。

## 🎯 修复优先级

- P0 - 立即修复：无
- P1 - 尽快修复：无
- P2 - 计划修复：无
- P3 - 可选优化：无
- 待确认-1 - 建议闭环：确认部署拓扑（网关/内网边界）与 `/data` 内容清单，决定是否为 `GET /files/:name` 增加认证中间件

## 📝 总结

- **一句话架构判断**：单路由 Express 共享文件服务，路径穿越防护（basename 收敛 + resolve 根锚定 + 含分隔符根前缀校验 + 校验/读取同目标）真实成立。
- **本次模式核心判断**：security 模式下 11 条适用控制全部 checked_no_finding，核心控制 CCR-NODE-PATH-001 防护位置与生效点已逐条举证；无正式问题，1 条部署侧待确认项待闭环。
- **3 个关键行动项**：1) 闭环待确认-1（部署层鉴权与端口暴露面）；2) 核对 `/data` 内容清单与符号链接治理，保持共享附件受控；3) 维持现有路径防护形态，后续若新增路由（写接口/下载/参数化查询）须复用同一根校验模式并纳入台账复审。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
