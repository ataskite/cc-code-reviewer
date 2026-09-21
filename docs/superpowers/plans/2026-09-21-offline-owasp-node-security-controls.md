# OWASP 离线基线与 Node Security Control Catalog 实施计划

> **执行对象：ZCode。** 按 Task 顺序逐项实施并勾选复核。本文是自包含实施计划，不依赖外部对话。除 Task 2 的维护态上游抓取外，任何运行时、测试态和审查态路径都不得访问外部网络。

**Goal：** 将当前 `security` 专项中分散的 OWASP/Node 规则升级为可离线执行、版本固定、可追溯、可恢复、可校验、可回归的 Security Control Catalog；首期交付 Node/BFF 纵切面，同时保持 Java/Python 既有安全流程不回归。

**Architecture：** OWASP 官方材料以不可变快照进入 `references/security/upstream/`；cc-code-reviewer 自有控制以稳定 `CCR-NODE-*` ID 进入 `references/security/catalog/`；Security 运行时从冻结审查输入解析适用控制和 Node 攻击面，单 Agent 与文件级分批均注入同一份本地产物；报告、SARIF、恢复门禁和模型评测统一消费稳定规则 ID。外部 URL 只用于来源审计和显式维护升级，不参与实际审查。

**Tech Stack：** Bash、系统 Perl（`JSON::PP`、`Digest::SHA`）、Markdown、JSON、现有 `scripts/core/lib/common.sh`；macOS/Linux。首期不新增 npm/pip/Java 运行时依赖，不要求 Semgrep/CodeQL，不在运行时调用 `curl`、`wget`、`git fetch`、`npx` 或浏览器。

**Current Baseline：** `v1.7.1` 已有 Node/BFF SSRF 真实事故负面清单、Node 注入/RCE 规则、Security 统一框架、授权面二次扫描、证据状态与 SARIF 导出。本计划是在这些契约上新增标准工程化层，不重写既有安全判断。

---

## 0. 全局约束

### 0.1 必须保持的现有契约

- 主入口仍是 `skills/cc-code-reviewer/SKILL.md`，不得新增第二个 Security Skill。
- `security` 仍是 `REVIEW_MODE` 的一个枚举，不新增绕过现有 INTERACT 状态机的命令行参数。
- 预扫描先于交互、摘要先于问题、最终确认单独存在；本计划不增加新的用户交互步骤。
- 正式范围继续以冻结 `review-input.json` 中 `selected=true` 为唯一事实来源；攻击面索引不得扩大正式问题范围。
- Java / Frontend / Python 三个 Agent 仍以 `references/security/enterprise-security-framework.md` 为统一安全语义权威。
- P0 五项硬门槛、证据状态、敏感值脱敏、授权面二次扫描和飞书上传责任边界不变。
- Bash + 系统 Perl 技术栈不变；不得为 JSON 校验引入 Python、Node 包或 jq 硬依赖。
- 每个新脚本必须 `set -euo pipefail`，stdout 为稳定机器契约，诊断写 stderr，文件原子落盘。
- 完成后必须运行 `bash tests/run_all.sh`，禁止通过管道接 `head`/`tail` 吞掉退出码。

### 0.2 首期目标

1. 本地固化 OWASP ASVS 5.0.0、OWASP Top 10:2025、OWASP API Security Top 10:2023 与 Node.js Security Cheat Sheet 的运行所需内容。
2. 建立稳定、机器可读的 Node Security Control Catalog。
3. Security 模式根据当前项目与冻结输入生成：
   - `security-controls.json`：本轮适用控制；
   - `security-surface.json`：入口、身份、Source、Sink、配置和外部资源候选索引。
4. 单 Agent、Frontend 文件级分批、恢复门禁、合并报告和 SARIF 全部消费同一稳定规则 ID。
5. 建立 Node vulnerable / secure / renamed-wrapped 评测夹具与离线运行测试。
6. 修复 Node/BFF `server-root` 层排除生产 TypeScript 的覆盖缺口。

### 0.3 明确非目标

- 不宣称“OWASP 认证”或“ASVS 全量合规”。只能声明固定版本的控制映射与本轮覆盖状态。
- 不把 ASVS 全部要求直接转换为静态扫描规则；首期只选择与 Node/BFF 静态、配置和语义审查相关的控制。
- 不自研完整 JavaScript AST、跨函数污点分析或符号执行引擎。
- 不把 `typescript-lsp` 描述为污点分析；它只提供 definition/reference/diagnostics 等代码智能。
- 不在本期启用 Next.js、Nuxt 或通用未支持框架；保留现有拒绝边界。
- 不自动联网更新 OWASP 内容。
- 不在实现提交中直接修改 `VERSION` 或创建 release；版本发布在 Codex 审核通过后另行决定。

### 0.4 失败原则

- 上游原文无法从官方来源获取或无法确认许可证时：停止 Task 2，报告阻塞；不得根据模型记忆伪造内容。
- 上游文件 hash、版本或结构不符：fail closed，不生成 catalog。
- Security Catalog、适用控制或攻击面冻结文件缺失/被改写：批次恢复失败，必须新建 RUN_DIR。
- 控制无法静态验证：标记 `static_unsupported` 或 `external_evidence_missing`，不得写成通过。
- 候选索引只用于定向取证，不得直接生成正式漏洞结论或决定 P0。

---

## 1. 目标目录结构

```text
references/security/
├── enterprise-security-framework.md                 # 已有，补控制覆盖契约
├── upstream/                                        # 新增：不可变上游快照
│   ├── manifest.json                                # 唯一上游清单
│   ├── asvs/5.0.0/
│   │   ├── OWASP_Application_Security_Verification_Standard_5.0.0_en.json
│   │   ├── SHA256SUMS
│   │   └── NOTICE.md
│   ├── top10/2025/
│   │   ├── introduction.md
│   │   ├── A01.md ... A10.md
│   │   ├── SHA256SUMS
│   │   └── NOTICE.md
│   ├── api-top10/2023/
│   │   ├── introduction.md
│   │   ├── API1.md ... API10.md
│   │   ├── SHA256SUMS
│   │   └── NOTICE.md
│   └── nodejs-cheat-sheet/<pinned-commit>/
│       ├── Nodejs_Security_Cheat_Sheet.md
│       ├── SHA256SUMS
│       └── NOTICE.md
├── catalog/
│   ├── security-control.schema.json                 # 新增：结构说明
│   ├── node-security-controls.json                  # 新增：唯一控制映射事实
│   └── profiles/
│       ├── node-api.json
│       ├── node-bff.json
│       └── node-worker.json
└── control-catalog.md                               # 新增：人类可读使用说明

scripts/core/
├── validate-security-upstream.sh                    # 新增
├── validate-security-control-catalog.sh             # 新增
├── resolve-security-controls.sh                     # 新增
├── validate-security-report.sh                      # 新增
├── validate-resume-input.sh                         # 修改：增加 Security 快照门禁
└── export-sarif.sh                                  # 修改：稳定 Security ruleId

scripts/languages/frontend/
├── collect-source-files.sh                          # 修改：server-root TypeScript
├── scan-project.sh                                  # 修改：范围披露一致
└── prepare-security-surface.sh                      # 新增

tests/security/
├── test_security_upstream.sh
├── test_security_control_catalog.sh
├── test_resolve_security_controls.sh
├── test_prepare_node_security_surface.sh
├── test_validate_security_report.sh
├── test_security_resume_gate.sh
└── test_offline_security_runtime.sh

tests/evals/node-security/
├── README.md
├── expected-controls.json
├── bff-header-forwarding/{vulnerable,secure,renamed-wrapped}/
├── ssrf/{vulnerable,secure,redirect-bypass}/
├── session-mass-assignment/{vulnerable,allowlist-bound}/
├── command-injection/{vulnerable,execfile-bound,renamed-wrapped}/
├── path-traversal/{vulnerable,root-bound}/
└── authorization/{bola-unbound,owner-bound,bfla-unbound,function-bound}/
```

### 1.1 单一事实来源

- `upstream/**`：上游原文，不修改正文。
- `catalog/node-security-controls.json`：内部规则、OWASP/ASVS/CWE 映射的唯一提交态事实来源。
- 不另行提交一套手写 `mappings/*.json`，避免映射双写漂移；需要的反向索引由校验脚本或运行时产物生成。
- `node-rules.md`：人类与 Agent 可读说明，不承担机器 ID 映射事实。

---

## 2. 数据契约

### 2.1 `upstream/manifest.json`

至少包含：

```json
{
  "schema_version": 1,
  "generated_at": "ISO-8601 UTC",
  "sources": [
    {
      "id": "owasp-asvs",
      "version": "5.0.0",
      "source_url": "官方 HTTPS URL",
      "source_revision": "release tag 或 commit SHA",
      "license": "从上游原文核验后的 SPDX/文本标识",
      "local_root": "asvs/5.0.0",
      "files": [
        {
          "path": "相对 upstream 的路径",
          "sha256": "64 位小写十六进制"
        }
      ]
    }
  ]
}
```

约束：

- `source_url` 只作溯源，运行时不得访问。
- `files[].path` 必须位于 `references/security/upstream/` 内，拒绝绝对路径与 `..`。
- 文件列表完整且无重复；SHA-256 对文件原始字节计算。
- `NOTICE.md` 必须记录标题、版本、来源、revision、抓取日期、许可证、是否原样保存。
- `generated_at` 仅由维护脚本写入；运行时输出不得依赖当前时间。

### 2.2 `node-security-controls.json`

顶层：

```json
{
  "schema_version": 1,
  "catalog_id": "cc-code-reviewer-node-security",
  "catalog_version": "0.1.0",
  "upstream_manifest_sha256": "...",
  "controls": []
}
```

每条控制必填：

```json
{
  "id": "CCR-NODE-SSRF-001",
  "title_zh": "用户可控数据进入服务端外发请求目标",
  "category": "external-resource",
  "profiles": ["node-api", "node-bff"],
  "applicability": {
    "requires_any_signals": ["outbound-http-client"],
    "excludes_project_types": []
  },
  "standards": {
    "owasp_top10": ["A01:2025"],
    "owasp_api_top10": ["API7:2023", "API10:2023"],
    "asvs": ["v5.0.0-<verified-control-id>"],
    "cwe": ["CWE-918"]
  },
  "detectability": {
    "primary": "taint",
    "requires_semantic_review": true,
    "runtime_verification_possible": true
  },
  "sources": ["request.body", "request.query", "request.params", "request.headers"],
  "sinks": ["fetch", "axios", "got", "http.request", "https.request"],
  "required_controls": ["scheme_allowlist", "resolved_host_allowlist", "redirect_revalidation"],
  "required_evidence": ["entry", "source", "propagation", "sink", "missing_control"],
  "severity_candidate": "P0",
  "description_zh": "...",
  "remediation_zh": "..."
}
```

封闭枚举：

- `category`：`identity` / `authorization` / `injection` / `external-resource` / `file` / `data-secret` / `business-abuse` / `logging-exception` / `configuration-supply-chain`。
- `detectability.primary`：`pattern` / `taint` / `semantic` / `config` / `dependency` / `runtime`。
- `severity_candidate`：`P0` / `P1` / `P2` / `P3` / `none`；它只是候选级别，不替代 P0 五项硬门槛。
- 控制 ID 正则：`^CCR-NODE-[A-Z0-9]+-[0-9]{3}$`。
- ASVS ID 必须带完整版本前缀 `v5.0.0-`，并能在本地 ASVS JSON 中找到；不得编造占位 ID进入最终文件。
- Top 10/API Top 10 ID 必须能在对应本地快照中找到。
- CWE 只校验格式与去重；首期不额外固化 MITRE CWE 全库。

### 2.3 首批控制

至少实现以下 12 条；ID 一经发布不可复用或改义：

| ID | 主题 | 主要检测类型 |
|---|---|---|
| `CCR-NODE-BFFHEADER-001` | 客户端头批量透传到上游 | taint + semantic |
| `CCR-NODE-IDENTITY-001` | 客户端字段覆盖服务端身份/租户 | taint + semantic |
| `CCR-NODE-SESSION-001` | 请求对象批量写入 Session | pattern + semantic |
| `CCR-NODE-SSRF-001` | 用户控制外发 URL/Host/Path/重定向 | taint + semantic |
| `CCR-NODE-CMD-001` | 用户输入进入 `child_process` | pattern + taint |
| `CCR-NODE-PATH-001` | 用户输入进入文件读取/下载路径 | taint |
| `CCR-NODE-PROTO-001` | 原型污染危险键进入深合并 | pattern + taint |
| `CCR-NODE-NOSQL-001` | 未过滤对象进入 NoSQL 查询 | taint |
| `CCR-NODE-DESER-001` | 不可信数据进入危险反序列化 | pattern + taint |
| `CCR-NODE-BOLA-001` | 主体—对象绑定缺失 | semantic |
| `CCR-NODE-BFLA-001` | 低权限主体执行高权限动作 | semantic |
| `CCR-NODE-CSRF-001` | Cookie 会话写接口缺少 CSRF 控制 | config + semantic |

第二批候选（本期可以只在设计说明中登记，不得假装已实现）：弱算法/随机、审计日志、异常 fail-open、依赖供应链、资源消耗、敏感业务流、API Inventory。

### 2.4 `security-controls.json` 运行时产物

```json
{
  "schema_version": 1,
  "language_id": "frontend",
  "security_profile": ["node-bff"],
  "project_type": "frontend-vue2",
  "catalog_path": "绝对路径",
  "catalog_sha256": "...",
  "upstream_manifest_sha256": "...",
  "review_input_sha256": "...",
  "controls": [
    {
      "id": "CCR-NODE-SSRF-001",
      "applicability": "applicable",
      "matched_signals": ["outbound-http-client", "request-source"]
    }
  ],
  "excluded_controls": [
    {
      "id": "...",
      "reason": "明确、可复核的非适用原因"
    }
  ]
}
```

适用性解析只决定“本轮要检查什么”，不能决定是否存在漏洞。

### 2.5 `security-surface.json` 运行时产物

必须只读取 `review-input.json` 中 `selected=true` 的文件，输出候选索引：

```json
{
  "schema_version": 1,
  "review_input_sha256": "...",
  "files_scanned": 10,
  "entries": [],
  "identity_sources": [],
  "request_sources": [],
  "sensitive_sinks": [],
  "outbound_clients": [],
  "config_signals": [],
  "limitations": []
}
```

每个索引项至少包含 `file`、`line`、`kind`、`symbol_or_excerpt`；excerpt 最多一行、最多 200 字符，不得包含 token、口令、私钥或连接串原值。该文件是候选导航，不是发现清单。

### 2.6 控制覆盖状态

报告中每个适用控制必须且只能出现一次，状态为以下封闭集合之一：

```text
finding_confirmed
checked_no_finding
external_evidence_missing
static_unsupported
not_applicable
```

中文展示分别为：已发现问题、已检查无发现、外部证据缺失、静态不可验证、不适用。

---

## 3. Task 1：先写目录、Schema 和上游完整性契约测试（TDD 红）

**Files：**

- Create: `tests/security/test_security_upstream.sh`
- Create: `tests/security/test_security_control_catalog.sh`
- Modify: `tests/run_all.sh`（仅当现有自动发现不能覆盖 `tests/security/` 时）
- Modify: `tests/test_contract_docs.sh`

### Steps

- [ ] 1. 在测试中断言目标目录和文件全部存在。
- [ ] 2. 用 Perl `JSON::PP` 校验 `manifest.json`、schema、catalog、profiles 均为合法 JSON 对象。
- [ ] 3. 断言 manifest 文件路径无绝对路径、无 `..`、无重复，hash 为 64 位小写十六进制。
- [ ] 4. 逐文件重新计算 SHA-256 并与 manifest、各目录 `SHA256SUMS` 对比。
- [ ] 5. 断言每个上游目录都有 `NOTICE.md`，并包含 source URL、version/revision、license。
- [ ] 6. 断言 catalog ID 唯一、格式正确、控制字段完整、封闭枚举合法、数组无重复。
- [ ] 7. 解析本地 ASVS JSON，断言每个 `standards.asvs` ID 真实存在且带 `v5.0.0-`。
- [ ] 8. 解析本地 Top 10/API Top 10 快照的 ID 清单，断言 catalog 映射真实存在。
- [ ] 9. 断言首批 12 个控制全部存在。
- [ ] 10. 在 `tests/test_contract_docs.sh` 增加本地离线基线、Control Catalog、禁止运行时联网的文档契约断言。
- [ ] 11. 运行两个新测试，确认因文件尚不存在而失败；记录预期失败原因。

**Expected red：** 缺少 `references/security/upstream` 与 `catalog`。

---

## 4. Task 2：固化官方 OWASP 上游材料

**Files：** 创建 `references/security/upstream/**`。

### 官方来源要求

- ASVS：OWASP/ASVS 官方仓库 `v5.0.0` release 或 tag 中的英文 JSON；优先使用官方发布资产，不使用第三方镜像。
- Top 10：OWASP Top 10:2025 官方仓库/站点对应的英文 Markdown 源文件，固化 Introduction 与 A01-A10。
- API Top 10：OWASP API Security Top 10:2023 官方仓库/站点对应的英文 Markdown 源文件，固化 Introduction 与 API1-API10。
- Node.js Cheat Sheet：OWASP Cheat Sheet Series 官方仓库的 `Nodejs_Security_Cheat_Sheet.md`，固定到不可变 commit SHA，目录名使用完整 SHA 或至少 12 位前缀且 manifest 保存完整 SHA。

### Steps

- [ ] 1. 只在本任务的维护态允许联网；先把文件下载到 `mktemp -d`，不得直接覆盖仓库内快照。
- [ ] 2. 核验下载地址最终归属 OWASP 官方域名或 OWASP 官方 GitHub 组织。
- [ ] 3. 核验内容标题、声明版本和预期结构；ASVS JSON 顶层版本必须为 `5.0.0`。
- [ ] 4. 核验每个项目的许可证原文；不要凭记忆填写许可证标识。
- [ ] 5. 使用 `apply_patch` 或安全复制把已核验文本加入仓库；不得改写上游正文、翻译正文或删除段落。
- [ ] 6. 生成 `SHA256SUMS` 与总 `manifest.json`；hash 对原始字节计算。
- [ ] 7. 每个 `NOTICE.md` 记录：作品名、项目名、官方 URL、tag/commit、下载日期、许可证、文件是否原样保存。
- [ ] 8. 运行 `bash tests/security/test_security_upstream.sh`，应通过。

**阻塞处理：** 如果 ZCode 环境无法联网，停止本 Task 并向用户索要官方文件或授权的下载方式；不要从对话文本、搜索摘要或模型记忆重建上游正文。

---

## 5. Task 3：实现 Security Control Catalog 与 Profiles

**Files：**

- Create: `references/security/catalog/security-control.schema.json`
- Create: `references/security/catalog/node-security-controls.json`
- Create: `references/security/catalog/profiles/node-api.json`
- Create: `references/security/catalog/profiles/node-bff.json`
- Create: `references/security/catalog/profiles/node-worker.json`
- Create: `references/security/control-catalog.md`
- Create: `scripts/core/validate-security-control-catalog.sh`

### Steps

- [ ] 1. 按 §2.2 建 schema；schema 用作说明与 IDE 支持，真正 fail-closed 校验由 Bash+Perl 脚本执行。
- [ ] 2. 从本地上游快照逐条核验 12 个控制的 ASVS/Top10/API Top10 ID；把核验依据写入 catalog，不复制大段上游正文。
- [ ] 3. 为每个控制填写 detectability、sources、sinks、required_controls、required_evidence、候选级别和中文修复建议。
- [ ] 4. Profile 只引用 control ID，不复制控制内容；同一控制可属于多个 profile。
- [ ] 5. `validate-security-control-catalog.sh` 读取固定路径或显式参数，stdout 成功只输出：

```text
SECURITY_CATALOG_OK=<catalog_version> CONTROLS=<n> ASVS=<n> TOP10=<n> API_TOP10=<n>
```

- [ ] 6. 失败时 exit 1，stderr 输出稳定 `ERROR_SECURITY_CATALOG_*=` 标签。
- [ ] 7. 校验 catalog 顶层 `upstream_manifest_sha256` 等于当前 manifest 文件字节 hash。
- [ ] 8. 运行 `test_security_control_catalog.sh`，应通过。

---

## 6. Task 4：实现适用控制解析器

**Files：**

- Create: `scripts/core/resolve-security-controls.sh`
- Create: `tests/security/test_resolve_security_controls.sh`

### CLI 契约

```bash
bash scripts/core/resolve-security-controls.sh \
  <PROJECT_DIR> <PROJECT_TYPE> <REVIEW_INPUT_JSON> <OUTPUT_JSON>
```

成功 stdout 单行：

```text
SECURITY_CONTROLS_PATH=<abs> SECURITY_PROFILES=<csv> CONTROLS=<n> CATALOG_SHA256=<sha256>
```

### 解析规则

- `PROJECT_TYPE=node`：至少启用 `node-api`。
- 有 BFF/server-root 信号、外发 HTTP client、代理/中继路由：叠加 `node-bff`。
- 有队列、任务、Webhook、消息消费信号：叠加 `node-worker`。
- React/Vue 项目只要冻结输入含 BFF server-root 文件，也可启用 Node profile；不能因为 PROJECT_TYPE 是 Vue/React 就跳过 BFF 控制。
- 只使用 `PROJECT_DIR` 内配置和 `REVIEW_INPUT_JSON selected=true` 文件；不得联网，不得读取 secret-path 排除文件。
- 信号只决定适用控制，不得输出漏洞。
- 输出原子落盘、canonical JSON、固定 key 顺序或 `JSON::PP->canonical`、恰好一个结尾换行。

### Tests

- [ ] 1. 纯浏览器 React：不启用 Node profile。
- [ ] 2. Express Node API：启用 `node-api`。
- [ ] 3. Vue + 根级 BFF：启用 `node-bff`。
- [ ] 4. MQ worker：启用 `node-worker`。
- [ ] 5. 同输入运行两次字节完全一致。
- [ ] 6. 输出路径越界、输入 JSON 非法、catalog 非法时 fail closed。
- [ ] 7. 所有输出控制都来自 catalog 且无重复。

---

## 7. Task 5：实现 Node Security Surface 生成器

**Files：**

- Create: `scripts/languages/frontend/prepare-security-surface.sh`
- Create: `tests/security/test_prepare_node_security_surface.sh`

### CLI 契约

```bash
bash scripts/languages/frontend/prepare-security-surface.sh \
  <PROJECT_DIR> <REVIEW_INPUT_JSON> <SECURITY_CONTROLS_JSON> <OUTPUT_JSON>
```

成功 stdout 单行：

```text
SECURITY_SURFACE_PATH=<abs> FILES=<n> ENTRIES=<n> SOURCES=<n> SINKS=<n> LIMITATIONS=<n>
```

### 候选索引范围

- Entry：Express/Koa/Fastify route、middleware、HTTP server、GraphQL/WebSocket、Webhook、消息/任务消费者。
- Identity：session、cookie、Authorization、自定义身份/租户 header、JWT middleware、服务账号。
- Source：request body/query/params/headers/cookies/files、消息 payload、Webhook payload、环境/配置输入。
- Sink：DB read/write、文件、child_process、模板、反序列化、HTTP client、redirect、session 写入、敏感响应/导出。
- Control signal：schema 校验、allowlist、owner/tenant 条件、权限中间件、CSRF、SameSite、安全 header。

### 强制边界

- 只读 selected 文件；正式范围外只可记录为 limitation，不得扫描整个仓库。
- 不做 Source→Sink 结论；只建立候选位置。
- 不把函数名/字段名命中直接当授权成立或漏洞成立。
- 所有 excerpt 脱敏；疑似密钥只保留键名和 `***`。
- 文件、行号和 kind 排序稳定；两次运行字节一致。
- 大文件或无法解析内容应写 limitation，不得静默跳过。

### Tests

- [ ] 1. 识别 Express route、`req.body`、axios、child_process、fs、session。
- [ ] 2. secure 与 vulnerable 代码都可以产生候选索引，但不会直接出现 finding/severity 字段。
- [ ] 3. secret 值不会进入 JSON。
- [ ] 4. selected=false 文件完全不出现。
- [ ] 5. 同输入字节稳定。

---

## 8. Task 6：补齐 BFF server-root TypeScript 正式范围

**Files：**

- Modify: `scripts/languages/frontend/collect-source-files.sh`
- Modify: `scripts/languages/frontend/scan-project.sh`
- Modify: `references/languages/frontend/source-scope.md`
- Modify: `agents/cc-code-reviewer-frontend.md`
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `tests/frontend/test_frontend_collect_server_root.sh`
- Modify: `tests/frontend/test_frontend_scan_project.sh`
- Modify: `tests/test_contract_docs.sh`

### Rules

- server-root 允许 `.ts`，但继续排除 `.d.ts`、测试、fixture、生成代码、构建配置、`scripts/`、`tools/`、静态资源和产物。
- TypeScript server-root 必须有包级服务端信号或明确运行入口，例如 `tsx`/`ts-node`/Node loader/Nest/Express/Koa/Fastify/server listen；不能把普通根级 TS 工具文件全部纳入。
- 支持 `server/**/*.ts`、`api/**/*.ts`、`controllers/**/*.ts`、`apps/*/server/**/*.ts` 等实际生产目录，但仍服从现有 `SERVER_ROOT_LIMIT`。
- `SOURCE_SCOPE:formal`、`SERVER_ROOT:formal`、COMPONENT 统计、source manifest 与 Agent 文字必须完全一致。
- 本 Task 不改变 Next.js/Nuxt 拒绝策略。

### Tests

- [ ] 1. 根级 `server.ts` 被纳入。
- [ ] 2. `controllers/user.ts` 在服务端包中被纳入。
- [ ] 3. `vite.config.ts`、`jest.config.ts`、`scripts/build.ts` 不被纳入。
- [ ] 4. `.test.ts`、`.spec.ts`、`.d.ts` 不被纳入。
- [ ] 5. 纯前端包中的普通根级 helper.ts 不被误收。
- [ ] 6. server-root 上限、禁用开关和 stderr 披露保持兼容。

---

## 9. Task 7：接入单 Agent Security 流程

**Files：**

- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `runtime/contract.md`
- Modify: `runtime/claude-code.md`
- Modify: `runtime/codex.md`
- Modify: `runtime/zcode.md`
- Modify: `agents/cc-code-reviewer-frontend.md`
- Modify: `tests/test_contract_docs.sh`

### 接入时机

在单 Agent 路径中：

```text
prepare-review-input
→ prepare-review-context
→ resolve-review-rules
→ [Security + frontend] resolve-security-controls
→ [Security + Node profile] prepare-security-surface
→ DISPATCH_AGENT
```

### 运行时变量

新增并注入：

```text
SECURITY_UPSTREAM_MANIFEST_PATH
SECURITY_CONTROL_CATALOG_PATH
SECURITY_CONTROLS_PATH
SECURITY_SURFACE_PATH
```

非 Security 或无 Node profile 时：

```text
SECURITY_CONTROLS_PATH=未启用
SECURITY_SURFACE_PATH=未生成
```

### Agent 义务

- 必须读取本地 catalog、适用控制与 surface；禁止访问 URL 补资料。
- surface 只是导航，Agent 必须回到实际代码闭合 Source→Propagation→Sink→Missing Control。
- 每个适用控制最终写入控制覆盖台账。
- `pattern` 命中仍是候选，必须检查输入是否可控、生产可达和有效防护。
- `semantic` 控制与现有授权面台账联动，不重复计算问题数量。
- `static_unsupported` / `external_evidence_missing` 必须说明缺失证据和最小验证方式。
- 现有授权面二次扫描继续强制执行。

### Tests

- [ ] 契约测试断言四个路径在 DISPATCH 前准备、校验可读并注入。
- [ ] 三端 runtime adapter 都声明本地产物，不引入平台专属路径或网络工具。
- [ ] 非 security 模式不生成 Security 产物，原有执行计划和 prompt 字节尽可能保持稳定。

---

## 10. Task 8：接入 Frontend 文件级分批与恢复门禁

**Files：**

- Modify: `scripts/core/plan-file-batches.sh`
- Modify: `scripts/core/validate-resume-input.sh`
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `tests/core/test_core_plan_file_batches.sh`
- Modify: `tests/core/test_core_validate_resume_input.sh`
- Create: `tests/security/test_security_resume_gate.sh`

### Planner 行为

仅当 `language_id=frontend` 且 `review_mode=security`：

1. `RUN_DIR/review-input.json` 生成后，解析适用控制。
2. 生成：
   - `RUN_DIR/security-controls.json`
   - `RUN_DIR/security-surface.json`
3. `plan.json` 新增：

```json
{
  "security_controls_path": "...",
  "security_controls_sha256": "...",
  "security_surface_path": "...",
  "security_surface_sha256": "...",
  "security_catalog_path": "...",
  "security_catalog_sha256": "...",
  "security_upstream_manifest_sha256": "..."
}
```

4. 每个 batch agent 注入同一份 frozen controls/surface；Agent 只对本批正式文件形成问题，但可用 surface 判断跨批依赖并写“跨批依赖待复核”。

### Resume Gate

扩展 CLI：

```bash
bash scripts/core/validate-resume-input.sh \
  <RUN_DIR> <PROJECT_DIR> --rules --security
```

新增 exit 5：

```text
SECURITY_SNAPSHOT_CHANGED=<detail>
```

检查：

- Security controls/surface 文件仍在 RUN_DIR 内、存在、可读、字节 hash 匹配。
- 当前插件 catalog 与 plan 记录 hash 匹配。
- 当前 upstream manifest 与 plan 记录 hash 匹配。
- 非 Security 计划即使传 `--security` 也应给出明确的不适用结果；推荐 Skill 只在 Security 模式传该 flag。
- 旧 Security RUN_DIR 缺上述字段时 fail closed，要求重新规划；非 Security legacy run 保持兼容。

### Tests

- [ ] controls 文件篡改 → exit 5。
- [ ] surface 文件篡改 → exit 5。
- [ ] catalog 修改 → exit 5。
- [ ] upstream manifest 修改 → exit 5。
- [ ] 文件路径指向 RUN_DIR 外 → exit 5。
- [ ] 正常 Security run → `GATE_OK=`。
- [ ] 原有 exit 0/1/2/3/4 契约不回归。

---

## 11. Task 9：扩展报告格式与确定性校验器

**Files：**

- Modify: `references/report-format.md`
- Modify: `references/security/enterprise-security-framework.md`
- Modify: `agents/cc-code-reviewer-frontend.md`
- Create: `scripts/core/validate-security-report.sh`
- Create: `tests/security/test_validate_security_report.sh`
- Modify: `skills/cc-code-reviewer/SKILL.md`

### 报告新增章节

在授权面覆盖之后新增：

```markdown
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：{N}
- 已发现问题：{A}
- 已检查无发现：{B}
- 外部证据缺失：{C}
- 静态不可验证：{D}
- 不适用：{E}
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
```

说明：`not_applicable` 控制属于 catalog 总集而不属于“适用控制 N”，因此单独披露 E，不进入 N 对账。

### 每条 Security 问题新增字段

```markdown
**安全规则 ID**：CCR-NODE-...
**标准映射**：OWASP ... / API... / ASVS... / CWE...
**检测方式**：pattern / taint / semantic / config / dependency / runtime
```

授权问题继续保留现有“主体/资源/决策链”和“未授权路径与防护”。

### 校验脚本 CLI

```bash
bash scripts/core/validate-security-report.sh \
  <REPORT_MD> <SECURITY_CONTROLS_JSON>
```

成功 stdout：

```text
SECURITY_REPORT_OK=<abs> CONTROLS=<n> FINDINGS=<n> PENDING=<n>
```

校验内容：

- 每个适用控制恰好一行，状态属于封闭集合。
- 控制 ID 存在于 frozen controls；报告不得引用范围外控制。
- 对账数字一致。
- `finding_confirmed` 至少有一个对应正式问题块。
- `external_evidence_missing` 至少有一个对应待确认块或明确聚合引用。
- 每个安全问题块都有规则 ID、标准映射、检测方式和证据状态。
- 报告中的标准映射必须与 catalog 一致，顺序可规范化但内容不可漂移。
- 非 Security 报告不调用本脚本。

### 流程门禁

- 单 Agent：报告落盘后、上轮对比/SARIF/飞书上传前执行。
- Batch：合并报告落盘并通过标题校验后、SARIF/飞书上传前执行。
- 校验失败时不得上传飞书或导出 SARIF；保留本地报告并明确报告结构无效。

---

## 12. Task 10：让合并与 SARIF 使用稳定控制 ID

**Files：**

- Modify: `scripts/core/merge-batch-results.sh`
- Modify: `scripts/core/export-sarif.sh`
- Modify: `scripts/core/lib/CCR/Findings.pm`（仅在需要共享字段解析时）
- Modify: `tests/core/test_core_merge_batch_results.sh`
- Modify: `tests/core/test_core_export_sarif.sh`

### Merge

- 合并发现时保留 `安全规则 ID`、标准映射和检测方式。
- Security 控制覆盖表不能简单拼接批次表：按 control ID 聚合，优先级为：

```text
finding_confirmed
> external_evidence_missing
> static_unsupported
> checked_no_finding
```

- 一个批次 `finding_confirmed`，其他批次 `checked_no_finding`，最终必须是 `finding_confirmed`。
- 只有所有覆盖该控制的已完成批次均给出结论后，才可输出全局 `checked_no_finding`；阶段性报告必须披露未完成控制，不能假装通过。
- 既有 findings 指纹暂不加入 rule ID，以避免改变跨批/跨轮身份语义；如果确需改变，必须单独设计迁移并更新所有指纹测试。本期默认不改。

### SARIF

- Security 问题存在 `安全规则 ID` 时：`ruleId=CCR-NODE-*`。
- 非 Security 或历史报告缺字段时：继续回退现有维度标签，保持兼容。
- `rules[].shortDescription.text` 使用问题/控制标题。
- `rules[].properties` 至少写入 standards、detectability、security category。
- `results[].properties` 写入 evidence status；不得把密钥等证据值带进 SARIF。
- partialFingerprint 仍使用现有发现指纹，保持 merge/compare/mark-repeat 一致。

---

## 13. Task 11：建立 Node Security 模型评测夹具

**Files：** 创建 `tests/evals/node-security/**`。

### Fixture 原则

- 每个目录是最小、可读、无真实凭据的 Node 项目。
- vulnerable 与 secure 只改变控制是否成立，尽量保持其他结构一致。
- renamed-wrapped 改名并增加一层或两层传播，防止模型仅凭字段名背题。
- IMA 事故 fixture 必须脱敏、泛化，不出现真实组织、域名、token、客户数据或内部服务名。
- 静态 fixture 存在不等于模型能力已验证；README 必须明确只有实际以同模型档位执行并记录结果，才算 eval 证据。

### `expected-controls.json`

每个 case 记录：

```json
{
  "case": "ssrf/vulnerable",
  "expected_findings": ["CCR-NODE-SSRF-001"],
  "forbidden_findings": [],
  "expected_control_status": {
    "CCR-NODE-SSRF-001": "finding_confirmed"
  },
  "notes": "预期证据链"
}
```

### 必须覆盖

- BFF header forwarding：vulnerable / secure / renamed-wrapped。
- SSRF：直接 URL、Host/header 变体、redirect bypass、严格 allowlist 对照。
- Session mass assignment：任意字段写入与字段白名单。
- Command injection：exec shell 与 execFile argv。
- Path traversal：path.join 误用与 resolve+root boundary。
- Authorization：BOLA/BFLA vulnerable/control。

### 评测协议

README 写清：

1. 同一插件版本、同一模型档位、security 模式、全量范围。
2. vulnerable 必须命中 expected；secure 不得命中 forbidden。
3. renamed-wrapped 用于测语义泛化，不允许加入专门名称词表作弊。
4. 记录 report path、模型档位、commit、实际规则 ID、漏报/误报。
5. 自动 Shell 测试只校验 fixture 结构，不伪造模型召回率。

---

## 14. Task 12：增加断网运行测试

**Files：**

- Create: `tests/security/test_offline_security_runtime.sh`
- Modify: `tests/test_contract_docs.sh`

### Test 方法

- 创建临时 `PATH` 前缀，放置会立即失败的 `curl`、`wget`、`npx`、`git` 网络子命令替身，并设置不可达 HTTP(S) proxy。
- 在该环境下运行：
  - validate upstream；
  - validate catalog；
  - resolve controls；
  - prepare surface；
  - validate security report；
  - export SARIF。
- 所有步骤必须成功且外部网络替身调用次数为 0。
- 静态扫描 active runtime 文件，禁止出现运行时 `curl http`、`wget http`、`open URL` 等路径；NOTICE 和上游来源文件中的 URL 不在禁止范围。
- `scripts/maintenance/update-owasp-baseline.sh` 如实现，必须明确排除在 runtime 测试之外。

---

## 15. Task 13：实现显式维护升级脚本（非运行时）

**Files：**

- Create: `scripts/maintenance/update-owasp-baseline.sh`
- Create: `references/security/upstream/README.md`
- Create: `tests/security/test_update_owasp_baseline_contract.sh`

### 约束

- 该脚本只供维护者显式调用，Skill、Agent、测试主流程绝不能自动调用。
- CLI 必须要求版本/commit 和输出 staging 目录；默认不覆盖仓库文件。
- 下载到 `mktemp -d` 或显式 staging 目录，验证后输出差异摘要和建议复制路径。
- 不自动修改 catalog 映射、不自动提交、不自动 bump VERSION。
- 网络失败保留清晰错误，不回退第三方镜像。
- 支持 `--verify-only <staging-dir>`，使无网络环境也可核验用户提供的官方文件。
- 测试只覆盖参数、staging、hash、拒绝覆盖和 verify-only；不得在 `run_all.sh` 中真实联网。

---

## 16. Task 14：同步文档与三端契约

**Files：**

- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `references/examples.md`
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `runtime/contract.md`
- Modify: `runtime/claude-code.md`
- Modify: `runtime/codex.md`
- Modify: `runtime/zcode.md`
- Modify: `tests/test_contract_docs.sh`

### 必须说明

- OWASP 基线随插件离线分发，审查运行时零网络依赖。
- Top 10 是风险分类，ASVS 是控制基线，CWE 是漏洞分类，Node Cheat Sheet 是实现来源。
- 控制覆盖不是认证；`static_unsupported` 不是通过。
- Node Security Catalog 与现有统一 Security 框架的职责边界。
- 单 Agent / batch 生成和冻结的文件路径。
- Security 报告校验失败时禁止上传。
- 上游升级只能走显式维护流程。
- `README.md` 只写稳定能力和使用边界，不写动态测试数字、当轮进度或下一步；这些留在本计划或 release notes。

---

## 17. Task 15：全量验证与手工 Smoke

### 自动测试

```bash
bash tests/run_all.sh > /tmp/cc-reviewer-owasp-plan-test.log 2>&1
test_status=$?
tail -80 /tmp/cc-reviewer-owasp-plan-test.log
exit "$test_status"
```

必须为 0，且包含 `git diff --check` 通过。

单独运行：

```bash
bash tests/security/test_security_upstream.sh
bash tests/security/test_security_control_catalog.sh
bash tests/security/test_resolve_security_controls.sh
bash tests/security/test_prepare_node_security_surface.sh
bash tests/security/test_validate_security_report.sh
bash tests/security/test_security_resume_gate.sh
bash tests/security/test_offline_security_runtime.sh
bash tests/core/test_core_export_sarif.sh
bash tests/frontend/test_frontend_collect_server_root.sh
```

### 手工 Smoke

至少选择两个本地 fixture：

1. `ssrf/vulnerable`：运行 security 全量审查，预期 `CCR-NODE-SSRF-001` 为 `finding_confirmed`。
2. `ssrf/secure`：预期不产生 SSRF 正式发现，控制表为 `checked_no_finding`。
3. `bff-header-forwarding/renamed-wrapped`：确认不是仅靠固定字段名命中。
4. 创建一次 Frontend security 文件级 batch plan，检查 plan hash、恢复门禁、批次注入和合并控制表。
5. 在断网条件下重复 resolver/surface/report/SARIF 路径。

手工 Smoke 不能攻击生产系统，不需要真实凭据或真实网关。

---

## 18. 建议提交拆分

每个 commit 必须自洽；不要把所有内容压成一个巨型提交。

1. `test(security): define offline OWASP baseline and catalog contracts`
2. `chore(security): vendor pinned OWASP baseline snapshots`
3. `feat(security): add Node security control catalog and resolver`
4. `feat(frontend): build frozen Node security surface and include server-root TypeScript`
5. `feat(review): inject security controls into single and batch review flows`
6. `feat(report): validate security coverage and export stable SARIF rule IDs`
7. `test(security): add Node vulnerable-control eval fixtures and offline runtime coverage`
8. `docs(security): document offline OWASP governance and upgrade workflow`

在 Codex 审核之前：

- 不修改 `VERSION`。
- 不创建 release commit/tag。
- 不上传真实审查报告或内部事故材料。
- 不改写无关用户变更。

---

## 19. 完成定义（Definition of Done）

全部满足才可声称实施完成：

- [ ] OWASP 四类来源均已本地固化，manifest、NOTICE、hash 完整且测试通过。
- [ ] 运行时在断网环境不尝试访问外部 URL。
- [ ] 12 条首批控制的标准映射都由本地上游快照验证，无占位 ID。
- [ ] 单 Agent Security 路径生成并注入 controls/surface。
- [ ] Frontend 文件级 batch 冻结 controls/surface/catalog/upstream hash。
- [ ] Security 恢复门禁能拒绝任一快照或 catalog 漂移。
- [ ] Security 报告包含授权面覆盖与控制覆盖，两套台账均对账。
- [ ] Security 报告校验失败时不上传、不导出 SARIF。
- [ ] SARIF Security `ruleId` 使用 `CCR-NODE-*`，历史/非 Security 报告保持兼容。
- [ ] Node server-root TypeScript 正式范围有正反测试。
- [ ] vulnerable/secure/renamed-wrapped fixtures 齐备，README 明确模型评测边界。
- [ ] 三端 runtime 文档与 Skill/Agent 参数同步。
- [ ] `bash tests/run_all.sh` 全绿，`git diff --check` 通过。
- [ ] 未修改 `VERSION`，未发布 release。

---

## 20. 交给 Codex 审核的证据包

ZCode 完成后必须提供以下内容，Codex 才开始正式审核：

```text
1. 工作分支名与 HEAD commit
2. git status --short
3. git log --oneline --decorate -10
4. git diff --stat <base>...HEAD
5. /tmp/cc-reviewer-owasp-plan-test.log 路径与退出码
6. upstream manifest 摘要：来源、版本/commit、文件数、hash
7. catalog 摘要：控制总数、各 detectability 数量、12 条首批 ID
8. offline runtime 测试输出
9. 单 Agent smoke 报告路径
10. batch smoke 的 RUN_DIR、plan.json 与恢复门禁输出
11. SARIF 样例路径
12. 未完成项、已知限制和任何偏离本计划的决策
```

不得只说“测试都通过”；必须给出命令、退出码和可读取产物路径。

---

## 21. 给 ZCode 的启动提示词

可直接把下面这段和本文件路径一起交给 ZCode：

```text
请在 /Users/jiangkun/Documents/workspace/cc-code-reviewer 中严格执行
docs/superpowers/plans/2026-09-21-offline-owasp-node-security-controls.md。

要求：
1. 按 Task 顺序实施，先测试后实现；不要跳过红灯验证。
2. 审查运行时必须完全离线，只有“固化官方上游材料”任务允许显式联网。
3. 如果无法取得或验证 OWASP 官方原文，停止并报告阻塞，禁止凭模型记忆生成上游文件。
4. 不新增 npm/pip/Java 运行时依赖，不实现重型 SAST，不扩大到 Next.js/Nuxt。
5. 保持单 Agent、文件级分批、恢复门禁、报告、SARIF 和三端契约一致。
6. 分阶段提交，不修改 VERSION，不发布 release。
7. 完成后按计划第 20 节提供完整审核证据包，交给 Codex 审核。
```

