# Node Security 模型评测夹具

本目录是 Node/BFF 安全审查的模型评测协议与夹具集，对应控制目录
`references/security/catalog/node-security-controls.json`（共 12 条控制，其中 7 条
已实现审查规则，见下文「已实现控制 ID」）。

> **静态 fixture 的存在不等于模型能力已验证。** 本目录只定义「预期」：哪些 case
> 必须报、哪些 case 禁止报。任何召回率结论都只能来自按本协议用真实模型实际
> 运行并记录的结果。

## 1. 评测条件（什么才算一次有效 eval 证据）

一次有效的评测记录必须同时满足：

- 同一插件版本：记录插件仓库 commit（或 `VERSION`），一次评测集内不得混用版本；
- 同一模型档位：记录实际使用的模型 profile，跨档位结果不可合并统计；
- security 模式、全量范围：通过 `/cc-code-reviewer:cc-code-reviewer` 对单个夹具
  目录以 security 模式、全量代码范围实际执行审查；
- 实际运行并记录结果：留下本地 Markdown 报告路径与判定明细，才算 eval 证据。

只准备好 fixture 而未运行，或运行了但未记录，都不构成 eval 证据。

## 2. 判定规则

- 负面用例（`vulnerable` / `*-unbound` / `redirect-bypass`）：必须命中该 case 在
  `expected-controls.json` 中的 `expected_findings`；漏报即召回失败。
- 对照用例（`secure` / `*-bound`）：不得命中该 case 的 `forbidden_findings`；
  命中即误报。模型报告其他有独立证据的问题不受此限制。

## 3. renamed-wrapped 用例与语义泛化

`bff-header-forwarding/renamed-wrapped` 与 `command-injection/renamed-wrapped`
承载同一漏洞形态，但变量/函数已改名并增加 1-2 层传播（如
`pickMeta(headers)` → `decorate(outboundOpts)`、`runTransformTask(input)` →
`buildCmd(...)`）。它们必须照常命中对应控制的 `expected_findings`。

禁止作弊：不得为了通过这两个用例而在审查规则中加入专门名称词表（例如收录
`pipeToCoreSvc`、`runTransformTask` 等具体函数名或专门变量名）。检测必须依赖
数据流与语义（source → propagation → sink → 缺失控制），而非名称匹配。

## 4. 结果记录格式

每条评测记录至少包含：

| 字段 | 含义 |
| --- | --- |
| report path | 本次审查产出的本地 Markdown 报告路径（原始证据） |
| 模型档位 | 实际使用的模型 profile |
| commit | 被评测的插件仓库 commit |
| 实际规则 ID | 报告中命中的控制 ID 列表（对照 catalog 的稳定 ID） |
| 漏报/误报 | 对照 `expected-controls.json` 得出的 FN / FP 明细 |

`expected_control_status` 的状态枚举只允许：`finding_confirmed` /
`checked_no_finding` / `external_evidence_missing` / `static_unsupported` /
`not_applicable`。

## 5. 自动化测试的边界

`tests/evals/test_node_security_evals_structure.sh` 只校验 fixture 结构完整性：
README 与清单存在、`expected-controls.json` 是合法 JSON、case 集合与磁盘目录
双向一致、控制 ID 属于已实现集合、无疑似真实凭据。它不运行模型，也不伪造
任何模型召回率数字——结构 PASS 不代表模型召回率达标；召回率只能来自按第 1 节
协议实际运行后的记录。

## 6. 夹具内容约束（脱敏与泛化）

所有夹具为脱敏、泛化的最小项目：

- 不出现真实组织、真实域名、真实 token、客户数据或内部服务名；原事故已泛化为
  通用 BFF 形态，上游地址一律使用 `*-svc` 等虚构服务名；
- 不含任何真实凭据值（`express-session` 的 secret 等均为占位串）；
- 每个夹具是最小可读 Node 项目（package.json + 少量 .js），无需 npm install，
  仅供静态审查读取；文件内注释只说明作者意图，不标注答案。

## 已实现控制 ID（7 条）

CCR-NODE-BFFHEADER-001、CCR-NODE-SSRF-001、CCR-NODE-SESSION-001、
CCR-NODE-CMD-001、CCR-NODE-PATH-001、CCR-NODE-BOLA-001、CCR-NODE-BFLA-001

## 夹具清单（17 个 case）

| 组 | case | 类型 | 关联控制 |
| --- | --- | --- | --- |
| bff-header-forwarding | vulnerable | 负面 | CCR-NODE-BFFHEADER-001 |
| bff-header-forwarding | secure | 对照 | CCR-NODE-BFFHEADER-001 |
| bff-header-forwarding | renamed-wrapped | 语义泛化 | CCR-NODE-BFFHEADER-001 |
| ssrf | vulnerable | 负面 | CCR-NODE-SSRF-001 |
| ssrf | secure | 对照 | CCR-NODE-SSRF-001 |
| ssrf | redirect-bypass | 负面（重定向绕过） | CCR-NODE-SSRF-001 |
| session-mass-assignment | vulnerable | 负面 | CCR-NODE-SESSION-001 |
| session-mass-assignment | allowlist-bound | 对照 | CCR-NODE-SESSION-001 |
| command-injection | vulnerable | 负面 | CCR-NODE-CMD-001 |
| command-injection | execfile-bound | 对照 | CCR-NODE-CMD-001 |
| command-injection | renamed-wrapped | 语义泛化 | CCR-NODE-CMD-001 |
| path-traversal | vulnerable | 负面 | CCR-NODE-PATH-001 |
| path-traversal | root-bound | 对照 | CCR-NODE-PATH-001 |
| authorization | bola-unbound | 负面 | CCR-NODE-BOLA-001 |
| authorization | owner-bound | 对照 | CCR-NODE-BOLA-001 |
| authorization | bfla-unbound | 负面 | CCR-NODE-BFLA-001 |
| authorization | function-bound | 对照 | CCR-NODE-BFLA-001 |
