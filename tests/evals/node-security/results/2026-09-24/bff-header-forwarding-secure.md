# 安全审查报告

## ⚙️ 审查配置快照

- 生成时间：2026-09-24
- 审查类型：存量全量
- 审查范围：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/bff-header-forwarding/secure（全部生产源码）
- 审查模式：security；语言：frontend；激活 profile：node-api
- 启用维度：1、4（配置安全子项）、5（注入/越权子项）、6（全深度）、9（敏感信息泄露子项）、11（鉴权/错误信息子项）
- 跳过维度：2、3、7、8、10、12
- 语义增强：静态全量逐行阅读（未使用 LSP，按框架披露已降级为静态检索；Node 攻击面索引仅作导航候选，不作为发现清单）
- 检测到的技术栈：Node.js + Express 4 + axios（BFF 转发层，上游 http://orders-svc:8080/api/orders）
- 项目 ignore 状态：未配置
- 文件覆盖率：生产源码 1/1（server.js）；伴随清单 1/1（package.json）
- 冻结输入：/tmp/cc-eval-20260923/artifacts/bff-header-forwarding-secure.controls.json（review_input_sha256=5d1b6c99…ca7；11 条适用控制 / 1 条排除）
- 网络约束：零网络审查，全部结论仅来自本地文件

## 📊 审查范围说明

- **项目类型**：Node.js BFF 转发层（express，单一 POST 路由，axios 外发）
- **审查范围**：项目目录全部生产源码（server.js 43 行）与 package.json
- **审查时间**：2026-09-24
- **审查基准路径**：/Users/jiangkun/Documents/workspace/cc-code-reviewer/tests/evals/node-security/bff-header-forwarding/secure
- **覆盖方式**：逐文件全量阅读 + 11 条冻结适用控制逐条结论 + 授权面二次扫描（入口 × 受保护动作台账与六类差分反例）

## 📊 执行摘要

- **整体结论**：未发现正式问题。P0=0、P1=0、P2=0、P3=0；待确认 2 项（均因关键证据位于范围外，不满足定级门槛）。
- **最高风险点**：无正式风险。核心边界在上游订单服务的对象级/字段级授权（待确认-1）与真实认证载体（待确认-2）。
- **评分**：安全性：优（本仓库范围内，出口头构造链防护成立，1 条控制为外部证据缺失）；性能/可维护性/技术债：security 模式未评估。
- **问题汇总表**：

| 级别 | 数量 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |
| 待确认 | 2 |
| 总计（正式问题） | 0 |

- **项目 ignore 命中统计**：未配置 ignore 规则，无过滤。

## 🔍 覆盖限制与未审查范围

- **已重点检查**：出口请求头构造链（server.js:29-36，白名单、逐跳头剥离、身份头派生）、外发目标常量（server.js:10、38）、req.body 传播路径、全部 11 条适用控制、被排除控制的语义复核。
- **未充分覆盖**：上游 orders-svc 内部授权策略、真实认证/会话载体、部署网关——均在本仓库范围外。
- **限制说明**：
  1. `loadSession()` 为示意存根（固定返回 userId，不消费任何请求凭据，server.js:22-24），真实认证机制以范围外部署为准（见待确认-2）。
  2. 项目无 lockfile（仅 package.json 声明 express ^4.18.0、axios ^1.6.0）；按依赖风险结论规则，无锁定版本不下确定性漏洞结论，仅建议接入依赖扫描并提交 lockfile。
  3. 非安全维度观察（security 模式未启用对应维度，不计入正式问题，仅披露不丢弃）：axios 外发未配置 timeout；路由 async 处理器未捕获异常（Express 4 不自动捕获 async 错误，上游失败时该请求将得不到响应）——属稳定性/错误处理范围。
  4. 语义工具未使用：本轮为静态检索口径，未执行 definition/references 语义查询。

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 1 行；已绑定 0 / 未绑定 0 / 外部证据缺失 1 / 不适用 0（1 = 0 + 0 + 1 + 0）。

| 入口 | 主体与可信来源 | 动作 | 资源/属性与标识来源 | 授权决策及执行点 | 最终 Sink | 绑定结论 | 替代入口 |
|---|---|---|---|---|---|---|---|
| POST /api/orders（server.js:26） | session.userId，由服务端 loadSession 存根派生（server.js:22-24、36） | 订单创建/提交（写） | 订单数据全部来自 req.body（客户端），本仓库无对象 ID 消费点 | 本仓库无授权判断；注入 x-user-id 后由上游 orders-svc 决策 | axios.post → http://orders-svc:8080/api/orders（server.js:38） | 外部证据缺失 | 无（单一路由；无批量/导出/下载/异步/消息/旧版本入口） |

**已验证反例（六类差分）**：

1. 同角色异对象 → 外部证据缺失：对象标识仅存在于 body 内并由上游解释，本仓库无对象 ID sink（→ 待确认-1）。
2. 低权限高功能 → 不适用：唯一路由为普通业务提交，代码证据表明无管理/配置/导出/删除动作（server.js:26-40）。
3. 跨租户/组织 → 外部证据缺失：租户上下文本仓库未建模，body 原样转发（→ 待确认-1）。
4. 对象属性越权 → 外部证据缺失：body 无字段白名单直传上游，字段级授权依赖上游 schema（→ 待确认-1）。
5. 批量与嵌套资源 → 不适用：无批量/嵌套资源路由。
6. 替代执行路径 → 不适用：无异步任务、消息消费、缓存命中、内部 RPC 或旧版本入口；axios 为唯一外发通道。

**未闭合入口与外部依赖**：上游 orders-svc 授权策略；真实会话/认证载体；部署网关（如有）。

**结论边界**：唯一"入口 × 受保护动作"的绑定结论为外部证据缺失，故本报告不声明"未发现越权问题"，以待确认-1 给出最小验证方式。

## 🔴 正式问题（P0–P3）

未发现正式问题。

P0=0、P1=0、P2=0、P3=0。11 条冻结适用控制均未形成"入口 → Source → Propagation → Sink → 缺失控制"闭合的问题证据链：出口请求头按显式白名单逐键构造、身份头由服务端认证结果重新生成、外发目标为硬编码常量（防护举证见「Security 控制覆盖」与「最佳实践亮点」）。2 项边界事项的关键证据位于范围外，按分级规则归入待确认项，单列于下。

## ⚪ 待确认项

### 待确认-1 | [维度6-安全] 上游订单服务的对象级与字段级授权无法从本仓库证据闭合

**位置**：server.js:38（外发调用，body 原样转发）；server.js:36（身份头注入）

**置信度**：低 | **所属维度**：维度6-安全

**依据**：
```js
// server.js:29-38
const upstreamHeaders = {};
for (const name of HEADER_ALLOWLIST) {            // 白名单仅 accept-language / x-request-id
  if (req.headers[name] !== undefined) upstreamHeaders[name] = req.headers[name];
}
for (const name of HOP_BY_HOP) delete upstreamHeaders[name];
upstreamHeaders['x-user-id'] = session.userId;    // 身份头服务端派生（本仓库侧防护成立）
const resp = await axios.post(UPSTREAM, req.body, { headers: upstreamHeaders }); // ← req.body 整体转发：字段级过滤/对象级授权在本仓库不存在，决策点位于范围外上游
```

**待确认原因**：BFF 侧已确保身份头不可被客户端覆盖，但订单对象/字段级授权决策完全发生在范围外上游服务：其是否以 x-user-id 做 owner/tenant 绑定、是否信任 body 内对象/归属/租户字段（如以 body.userId 替代头部身份），本仓库证据无法闭合；静态结论只能停在"外部证据缺失"，不构成正式越权发现。

**建议的验证方式**：在测试环境向上游构造最小权限矩阵差分：①用户 A 会话 + body 携带用户 B 的对象/归属字段 → 预期上游拒绝；②同会话 body 携带他租户字段 → 预期拒绝；③仅变更 HTTP 方法或经网关直连上游复测同一 Sink。任一用例被放行即回溯为正式越权问题。

**安全规则 ID**：CCR-NODE-BOLA-001

**标准映射**：OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639

**检测方式**：semantic

**证据状态**：待确认项（授权决策点位于范围外上游服务，仓库证据无法闭合）

**主体/资源/决策链**：主体 session.userId（服务端派生，server.js:22-24、36）；受保护动作：订单创建/提交（写）；资源与标识来源：req.body 客户端字段（本仓库无对象 ID 消费点）；授权证据/决策点：本仓库无，上游 orders-svc 解释 x-user-id；owner/tenant 绑定结果：外部证据缺失；最终 Sink：axios.post → http://orders-svc:8080/api/orders。

**未授权路径与防护**：最短反例路径：客户端提交含他人对象/租户字段的 body → BFF 原样转发（仅附本会话 x-user-id）→ 上游若信任 body 字段则越权生效。现有防护及限制：出口头白名单 + 身份头服务端重生成（server.js:13、30-36）阻断"头部身份伪造"通道，但不约束 body 字段语义。

**验证方案**：见"建议的验证方式"权限矩阵；指定测试环境与凭据来源、种子数据只读优先、验证后清理回滚，不对生产系统发起攻击。

---

### 待确认-2 | [维度6-安全] 认证会话为示意存根，真实认证载体无法从仓库证据确认

**位置**：server.js:22-24

**置信度**：低 | **所属维度**：维度6-安全

**依据**：
```js
// server.js:21-24
// 服务端 session（示意实现，客户端不可伪造）
async function loadSession() {
  return { userId: 'u_1001' };                    // ← 固定返回、不消费任何请求凭据；真实认证机制在范围外
}
```

**待确认原因**：本仓库唯一身份来源是固定返回的存根：依赖清单既无 cookie 会话（无 express-session/cookie-parser，package.json:7-10），也无 Bearer/签名校验代码。本报告对 CSRF-001 的豁免、IDENTITY-001 的"服务端派生"结论均以此为边界——生产替换为真实会话实现后需重评（若为 cookie 会话，POST /api/orders 属状态变更端点，需补 SameSite 或 CSRF token）。

**建议的验证方式**：核对部署形态确认会话载体（cookie / Authorization 头 / 网关注入）；若为 cookie 会话，验证 SameSite 属性与写接口 Origin/CSRF 校验；确认 loadSession 的替换实现读取的是服务端可信来源而非任何请求字段。

**证据状态**：待确认项（认证机制属部署/范围外证据，仓库内不可闭合）

**主体/资源/决策链**：主体来源为 loadSession() 固定存根（不消费请求凭据）；其余不适用（本条为认证载体层边界，不涉及具体对象资源）。

**未授权路径与防护**：不适用（无法在存根上构造具体未授权路径；风险在于认证未在本仓库实现，注释"客户端不可伪造"不构成代码证据）。

**验证方案**：见"建议的验证方式"；仅在测试环境做会话载体探测，不做生产攻击。

---

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：11
- 已发现问题：0
- 已检查无发现：10
- 外部证据缺失：1
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D → 11 = 0 + 10 + 1 + 0

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份或租户上下文 | OWASP A01:2025, A07:2025 / API3:2023 / ASVS v5.0.0-V4.1.3, v5.0.0-V8.4.1 / CWE-285 | taint | checked_no_finding | 身份头 x-user-id 由服务端 session 派生（server.js:22-24、36）；出口头仅白名单 accept-language、x-request-id（server.js:13、30-32）；无任何 body/query/header 字段写入身份或租户上下文，req.body 仅作载荷转发（server.js:38） |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session（mass assignment） | OWASP A08:2025 / API3:2023 / ASVS v5.0.0-V8.2.3 / CWE-915 | pattern | checked_no_finding | 全文件无 req.session 写入点与 for-in 批量赋值；loadSession 为服务端只读存根（server.js:22-24） |
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023, API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918 | taint | checked_no_finding | 外发目标为硬编码常量 UPSTREAM（server.js:10、38）；URL/host/path 无用户可控输入，未配置重定向跟随 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process 命令执行 | OWASP A05:2025 / API10:2023 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | checked_no_finding | 全量核查无 child_process 引用或调用（server.js:1-43） |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V5.3.2, v5.0.0-V5.4.1 / CWE-22 | taint | checked_no_finding | 无 fs、res.sendFile、res.download、createReadStream 用法，不存在文件路径 sink |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | OWASP A05:2025 / API3:2023 / ASVS v5.0.0-V1.3.3 / CWE-1321 | pattern | checked_no_finding | req.body 不进入任何递归合并/extend；upstreamHeaders 为新建对象字面量、仅从 2 项白名单逐键填充（server.js:29-33），无 __proto__/constructor 消化路径 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | OWASP A05:2025 / ASVS v5.0.0-V1.2.4 / CWE-943 | taint | checked_no_finding | 无 mongodb/mongoose 等 NoSQL 客户端依赖（package.json:7-10）与查询构造点 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | OWASP A08:2025 / API8:2023 / ASVS v5.0.0-V1.5.2 / CWE-502 | pattern | checked_no_finding | 请求体仅经 express.json() 解析（JSON.parse 语义、无函数还原，server.js:8）；无 node-serialize、yaml.load |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权/BOLA） | OWASP A01:2025 / API1:2023 / ASVS v5.0.0-V8.2.2, v5.0.0-V8.3.3 / CWE-639 | semantic | external_evidence_missing | 本仓库无对象级数据访问 sink；对象/字段级授权决策在范围外上游 orders-svc：其是否按 x-user-id 做 owner/tenant 绑定、body 字段是否经字段级授权，无法从本仓库证据闭合；最小权限矩阵验证见待确认-1 |
| CCR-NODE-BFLA-001 | 低权限主体可执行高权限动作（垂直越权/BFLA） | OWASP A01:2025 / API5:2023 / ASVS v5.0.0-V8.2.1 / CWE-285 | semantic | checked_no_finding | 唯一入口 POST /api/orders 为普通业务提交（server.js:26），转发目标为固定上游路径（server.js:10）；无管理/配置/导出/删除等高权限动作与角色模型 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2, v5.0.0-V3.5.2 / CWE-352 | config | checked_no_finding | 无 cookie 会话的仓库证据成立：依赖仅 express、axios（package.json:7-10），无 express-session/cookie-parser，全文件无 cookie 读写，loadSession 不消费请求（server.js:22-24）；CSRF 以浏览器自动携带凭据为前置的条件不成立。边界：生产引入 cookie 会话后需重评（见待确认-2） |

- 排除控制语义复核：CCR-NODE-BFFHEADER-001（客户端请求头批量透传到上游服务）因激活 profile 为 node-api 被 resolver 排除（即上方"不适用"计数来源）。按排除说明完成语义复核——出口头按显式白名单逐头构造（server.js:13、30-32）、RFC 逐跳头剥离（server.js:16-19、33）、身份头由服务端认证结果重新生成而非透传客户端值（server.js:36），三项 required_controls（explicit-header-allowlist、strip-hop-by-hop、identity-header-regeneration）均已落实，风险不成立，故不做 finding_confirmed 语义提升。
- 控制覆盖是覆盖状态披露，不是 OWASP 认证或 ASVS 合规声明；static_unsupported 不是通过（本轮 D=0）。

## ✅ 最佳实践亮点

1. 出口请求头白名单逐键构造（server.js:13、29-32）：仅放行 accept-language、x-request-id 两类与身份无关的展示/关联头，从构造面杜绝"黑名单漏删"反模式（node-rules.md「BFF 中继层负面清单」第 1 条的正解形态）。
2. 身份头服务端重新生成（server.js:35-36）：x-user-id 取自服务端会话而非任何客户端头或 body 字段，阻断身份注入（负面清单第 2、3 条的风险在此不成立）。
3. RFC 逐跳头防御性剥离（server.js:16-19、33）：白名单之外的纵深防御层，双保险且不引入过度复杂度。

## 🎯 修复优先级

- P0 - 立即修复：无。
- P1 - 尽快修复：无。
- P2 - 计划修复：无。
- P3 - 可选优化：无正式问题；稳定性观察项（axios timeout、async 异常捕获）见「覆盖限制与未审查范围」第 3 条，建议在非 security 模式迭代中处理。
- 待确认跟进：待确认-1（上游对象/字段级授权闭合）优先；待确认-2（认证载体确认）次之。

## 📝 总结

- **一句话架构判断**：一个最小 Express BFF 转发层，"出口头白名单 + 服务端身份重生成 + 逐跳头剥离"的安全形态正确，本仓库范围内未发现问题，风险边界全部落在范围外上游与真实认证载体。
- **本次模式核心判断**：11 条冻结适用控制 0 发现、9 条已检查无发现、1 条外部证据缺失（BOLA，决策点在上游）；被 resolver 排除的头部透传控制经语义复核确认防护成立，未做语义提升。
- **3 个关键行动项**：①用权限矩阵差分闭合上游对象/字段级授权（待确认-1）；②确认生产会话载体并复核 CSRF 豁免前提（待确认-2）；③提交 lockfile 并接入依赖扫描（当前无锁定版本，无法下依赖漏洞结论）。

**审查人**: cc-code-reviewer Agent
**报告版本**: 5.7
**审查模式**: security
**模型档位**: inherit
