# Node Security Control Catalog 使用说明

**Catalog 文件：** `references/security/catalog/node-security-controls.json`（唯一提交态事实来源）
**校验：** `bash scripts/core/validate-security-control-catalog.sh`
**绑定：** catalog 顶层 `upstream_manifest_sha256` 绑定离线上游快照 `references/security/upstream/manifest.json` 的字节哈希；上游快照或 catalog 任一漂移都会被校验器与恢复门禁 fail-closed 拒绝。

## 1. 定位与边界

- 本目录（catalog + upstream）让 `security` 专项的 Node/BFF 审查建立在**固定版本、可离线执行、可追溯**的标准映射上：OWASP Top 10:2025 是风险分类，OWASP API Security Top 10:2023 是 API 风险分类，OWASP ASVS 5.0.0 是控制基线，Node.js Security Cheat Sheet 是实现参考来源。
- **控制覆盖不是认证**：报告只能声明固定版本的控制映射与本轮覆盖状态，不得宣称 OWASP 认证或 ASVS 全量合规。
- catalog 与 `references/security/enterprise-security-framework.md` 的职责边界：统一安全框架仍是三语言 Agent 的安全语义权威（证据等级、P0 门槛、授权面二次扫描）；catalog 只为 Node/BFF 提供**稳定控制 ID 与标准映射**，供运行时适用性解析、报告台账、SARIF 规则 ID 与恢复门禁消费。
- 审查运行时**零网络依赖**：`upstream/**` 中的 `source_url` 只用于来源审计与显式维护升级（`scripts/maintenance/update-owasp-baseline.sh`），任何 Skill、Agent、脚本不得在审查时访问外部 URL。

## 2. 首批控制（12 条）

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

## 4. 信号词表（封闭，供 applicability 与 resolver 共用）

`requires_any_signals` 为空表示 profile 启用即适用；非空表示命中任一信号才适用。

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

信号只决定「本轮要检查什么」（适用控制解析），**不能决定是否存在漏洞**；`pattern` 命中只是候选，必须由 Agent 回到实际代码闭合 Source→Propagation→Sink→Missing Control 证据链。

## 5. Profile 语义

- `node-api`：Node HTTP API / 服务端入口（PROJECT_TYPE=node 或检测到 http-server 信号）。
- `node-bff`：前端项目内的 BFF/中继层（前端信号 + server-root 服务端代码，或 API + 外发客户端 + 请求源的中继形态）；在 node-api 基础上叠加 BFFHEADER 等特有控制。
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

`static_unsupported` 不是通过——必须说明缺失证据与最小验证方式。台账对账规则见 `references/report-format.md` 的「Security 控制覆盖」章节。

## 7. 运行时产物

- `resolve-security-controls.sh` → `security-controls.json`（本轮适用控制 + 排除原因；确定性输出，字节稳定）
- `prepare-security-surface.sh` → `security-surface.json`（入口/身份/Source/Sink/配置候选索引；只是导航，不是发现清单，不得直接生成正式结论或决定 P0）

两个产物在分批模式下于 RUN_DIR 冻结并记录哈希，恢复门禁（`validate-resume-input.sh --security`）校验任一漂移即拒绝续跑。

## 8. 上游升级

只能走显式维护流程：`scripts/maintenance/update-owasp-baseline.sh`（fetch → 人工核验许可证 → emit-manifest → verify-only），复制进仓库后重算 catalog 的 `upstream_manifest_sha256` 并全量测试。不自动联网更新，不回退第三方镜像。
