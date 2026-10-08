# Node Security Control Catalog 使用说明

**Catalog 文件：** `references/security/catalog/node-security-controls.json`（唯一提交态事实来源）
**校验：** `bash scripts/core/validate-security-upstream.sh` → `bash scripts/core/validate-security-control-catalog.sh`
**绑定：** catalog 顶层 `upstream_manifest_sha256` 绑定离线上游快照 `references/security/upstream/manifest.json` 的字节哈希；上游快照或 catalog 任一漂移都会被校验器与恢复门禁 fail-closed 拒绝。

## 1. 定位与边界

- 本目录（catalog + upstream）让 `security` 专项的 Node/BFF 审查建立在**固定版本、可离线执行、可追溯**的标准映射上：OWASP Top 10:2025 是风险分类，OWASP API Security Top 10:2023 是 API 风险分类，OWASP ASVS 5.0.0 是控制基线，Node.js Security Cheat Sheet 是实现参考来源。
- **控制覆盖不是认证**：报告只能声明固定版本的控制映射与本轮覆盖状态，不得宣称 OWASP 认证或 ASVS 全量合规。
- catalog 与 `references/security/enterprise-security-framework.md` 的职责边界：统一安全框架仍是三语言 Agent 的安全语义权威（证据等级、P0 门槛、授权面二次扫描）；catalog 只为 Node/BFF 提供**稳定控制 ID 与标准映射**，供运行时适用性解析、报告台账、SARIF 规则 ID 与恢复门禁消费。
- 审查运行时**零网络依赖**：`upstream/**` 中的 `source_url` 只用于来源审计与显式维护升级（`scripts/maintenance/update-owasp-baseline.sh`），任何 Skill、Agent、脚本不得在审查时访问外部 URL。

## 2. 控制目录（16 条：首批 12 条 + 代理与身份专项 4 条）

| ID | 主题 | category | 检测主方式 | 候选级别 |
|---|---|---|---|---|
| CCR-NODE-BFFHEADER-001 | 客户端头批量透传到上游 | identity | taint | P0 |
| CCR-NODE-IDENTITY-001 | 客户端字段覆盖服务端身份/租户 | identity | taint | P0 |
| CCR-NODE-SESSION-001 | 请求对象批量写入 Session | authorization | pattern | P1 |
| CCR-NODE-SSRF-001 | 用户可控外发 URL/Host/重定向 | external-resource | taint | P0 |
| CCR-NODE-CMD-001 | 用户输入进入 child_process | injection | pattern | P0 |
| CCR-NODE-PATH-001 | 用户输入进入文件读取/下载路径 | file | taint | P0 |
| CCR-NODE-PROTO-001 | 原型污染危险键进入深合并 | injection | pattern | P0 |
| CCR-NODE-NOSQL-001 | 未过滤对象进入 NoSQL 查询 | injection | taint | P1 |
| CCR-NODE-DESER-001 | 不可信数据进入危险反序列化 | injection | pattern | P0 |
| CCR-NODE-BOLA-001 | 主体—对象绑定缺失（水平越权） | authorization | semantic | P0 |
| CCR-NODE-BFLA-001 | 低权限主体执行高权限动作（垂直越权） | authorization | semantic | P0 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | authorization | config | P1 |
| CCR-NODE-HOSTROUTE-001 | 固定网络目标下客户端覆盖路由身份 | external-resource | taint | P1 |
| CCR-NODE-PROXYCAP-001 | 服务端代理能力与调用者权限未绑定 | authorization | semantic | P1 |
| CCR-NODE-JWTAUTH-001 | JWT 接受链验证不完整或失败放行 | identity | semantic | P1 |
| CCR-NODE-PROXYTRUST-001 | forwarded 来源与代理拓扑信任不匹配 | configuration-supply-chain | config | P1 |

新增四条同时适用于 `node-api` 与 `node-bff`，独立 Node BFF 不会因未归类为混合前端而漏掉。详细离线取证、误报边界、修复与负向测试见 `references/languages/frontend/node-proxy-auth-rules.md`；Security Skill 显式注入并校验可读，单 Agent 与分批 Agent 均必须读取。

`severity_candidate` 只是候选级别，不替代 P0 五项硬门槛（见统一安全框架 §6）。每条控制的标准映射（Top10/API Top10/ASVS/CWE）均在上游快照中核验存在，校验器逐条复核——无占位 ID。

**ID 稳定性**：控制 ID 一经发布不可复用或改义；废弃控制保留 ID 并标注废弃，不得重定向到新语义。

## 3. 第二批候选（仅设计登记，未实现）

以下主题已在路线图中登记，**当前 catalog 未实现对应控制**，不得在报告台账中假装已覆盖：

- 弱算法/不安全随机（MD5/SHA-1/DES、`Math.random()` 生成安全值、`rejectUnauthorized:false`）——暂由前端框架 dim 6 规则覆盖
- 安全事件审计日志缺失（登录成败、401/403、敏感导出/管理操作无审计）——暂由 dim 9 规则覆盖
- 异常处理 fail-open（认证/鉴权路径异常默认放行）——暂由统一安全框架 §6 覆盖
- 依赖供应链（install 脚本、未锁定版本、typosquatting）
- 不受限资源消耗（ReDoS、昂贵查询、并发放大）
- 敏感业务流自动化滥用
- API 资产清单（影子/旧版本接口）

## 4. 信号词表（封闭，供审查导航与适用依据使用）

`review_signals` 记录 resolver 能识别的静态文本线索。命中时写入 `matched_signals`，并将控制标记为 `basis=signal-confirmed`；未命中时仍保留 profile 适用的控制，标记 `basis=profile-default`。词表未命中无法证明封装、别名、跨文件传播或动态路由不存在，因此不得据此提前排除控制。

| 信号 | 含义（resolver 的静态文本特征） |
|---|---|
| `http-server` | express/koa/fastify/nest/hapi/egg 引入、`express()`、`.listen(`、`createServer`、router/app 路由动词 |
| `request-source` | `req.body` / `req.query` / `req.params` / `req.headers` / `req.cookies` / 消息 payload 等入口数据 |
| `outbound-http-client` | `fetch(`/`axios`/`got(`/`http.request`/`https.request`/`superagent` 等外发客户端 |
| `session-usage` | `req.session` / `express-session` / `cookie-session` 等会话机制 |
| `child-process` | `child_process` / `exec(` / `execSync` / `spawn(` / `execFile` |
| `fs-path-ops` | `fs.readFile` / `sendFile` / `res.download` / `path.join` / `path.resolve` 等文件路径操作 |
| `deep-merge` | `merge(`/`extend(`/`defaults(`/lodash/deepmerge 等递归合并 |
| `nosql-client` | `mongodb` / `mongoose` / `MongoClient` |
| `deserialize-usage` | `node-serialize` / `unserialize(` / `yaml.load(` 等危险反序列化 |
| `worker-queue` | kafkajs/amqplib/bullmq/bee-queue/agenda/node-cron/`channel.consume(`/webhook 消费 |
| `proxy-routing` | Host/authority、hostRewrite/autoRewrite、servername、proxy/capability 路由线索 |
| `jwt-usage` | jsonwebtoken/jose、jwt.verify/decode/sign、jwtVerify/decodeJwt |
| `proxy-trust` | trust proxy、Forwarded/X-Forwarded-*、req.ip/hostname/protocol、socket.remoteAddress |

信号只决定「本轮要检查什么」（适用控制解析），**不能决定是否存在漏洞**；`pattern` 命中只是候选，必须由 Agent 回到实际代码闭合 Source→Propagation→Sink→Missing Control 证据链。

## 5. Profile 语义

- `node-api`：Node HTTP API / 服务端入口（PROJECT_TYPE=node 或检测到 http-server 信号）。
- `node-bff`：项目类型为受支持的 React/Vue 前端且发现 Node 服务端入口；即使当前增量只选择服务端文件，也按项目类型保留 BFF 控制。选中范围内的前端文件/依赖也可补充该 profile 线索。
- `node-worker`：队列/任务/Webhook/消息消费者（无 HTTP 入口，消息载荷仍是不可信输入）。

Profile 文件只引用控制 ID，不复制控制内容；同一控制可属于多个 profile。

## 6. 控制覆盖状态（报告台账封闭集）

报告中每个适用控制必须且只能出现一次，状态取值：

| 状态 | 中文展示 |
|---|---|
| `finding_confirmed` | 已发现问题 |
| `checked_no_finding` | 已检查无发现 |
| `external_evidence_missing` | 外部证据缺失 |
| `static_unsupported` | 静态不可验证 |
| `not_applicable` | 不适用 |

`static_unsupported` 不是通过——必须说明缺失证据与最小验证方式。profile 排除项通常标记 `not_applicable`；若正式代码证据证明项目分类/范围判断遗漏了真实风险，允许 `finding_confirmed` 语义提升，并单列计数。台账对账规则见 `references/report-format.md` 的「Security 控制覆盖」章节。

## 7. 运行时产物

- `validate-security-upstream.sh` 在安全审查运行时逐文件复核 manifest 与 SHA256SUMS 哈希；任一字节漂移则 fail closed。
- `resolve-security-controls.sh` → `security-controls.json`（本轮适用控制 + 排除原因；确定性输出，字节稳定）
- `prepare-security-surface.sh` → `security-surface.json`（入口/身份/Source/Sink/配置候选索引；只是导航，不是发现清单，不得直接生成正式结论或决定 P0）

两个产物在分批模式下于 RUN_DIR 冻结并记录哈希，恢复门禁（`validate-resume-input.sh --security`）校验任一漂移即拒绝续跑。

## 8. 上游升级

只能走显式维护流程：`scripts/maintenance/update-owasp-baseline.sh`（fetch → 人工核验许可证 → emit-manifest → verify-only），复制进仓库后重算 catalog 的 `upstream_manifest_sha256` 并全量测试。不自动联网更新，不回退第三方镜像。
