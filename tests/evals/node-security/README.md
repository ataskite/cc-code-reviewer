# Node Security 模型评测夹具

本目录是 Node/BFF 安全审查的模型评测协议与夹具集，对应控制目录
`references/security/catalog/node-security-controls.json`（共 16 条控制，其中 11 条
有专门评测夹具，见下文；其余控制不宣称具备已验证的模型表现）。

> **静态 fixture 的存在不等于模型能力已验证。** 本目录只定义「预期」：哪些 case
> 必须报、哪些 case 禁止报。任何召回率结论都只能来自按本协议用真实模型实际
> 运行并记录的结果。

## 1. 评测条件（什么才算一次有效 eval 证据）

一次有效的评测记录必须同时满足：

- 同一插件版本：记录插件仓库 commit（或 `VERSION`），一次评测集内不得混用版本；
- 同一模型档位：记录实际使用的模型 profile，跨档位结果不可合并统计；
- security 模式、全量范围：通过完整 Skill，或隔离评测工具按同一冻结输入、控制目录、必读参考直接调度同一审查 Agent，对单个夹具全部 selected 文件实际执行审查。直接调度必须标为 Agent 前向评测，不宣称已验证交互入口端到端；
- 实际运行并记录结果：留下本地 Markdown 报告路径与判定明细，才算 eval 证据。

只准备好 fixture 而未运行，或运行了但未记录，都不构成 eval 证据。

## 2. 判定规则

- 负面用例（`vulnerable` / `*-unbound` / `redirect-bypass`）：必须命中该 case 在
  `expected-controls.json` 中的 `expected_findings`；漏报即召回失败。
- 对照用例（`secure` / `*-bound`）：不得命中该 case 的 `forbidden_findings`；
  命中即误报。模型报告其他有独立证据的问题不受此限制。

`expected_findings` / `forbidden_findings` 指 P0-P3 正式确认的问题块；待确认风险另列 pending_found，不误算成已确认漏洞。严格状态检查仍会拒绝把缺证据用于替代安全对照的 checked_no_finding；topology-unproven 则必须维持 external_evidence_missing，不能猜测通过或确认漏洞。

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
`not_applicable`。新增 case 设置 `strict_control_status=true`，无发现必须明确为 checked_no_finding，不能用缺证据代替通过；topology-unproven 要求 external_evidence_missing。旧基线保留原有宽松无发现判定，不能混为同一口径。

## 5. 自动化测试的边界

`tests/evals/test_node_security_evals_structure.sh` 只校验 fixture 结构完整性：
README 与清单存在、`expected-controls.json` 是合法 JSON、case 集合与磁盘目录
双向一致、控制 ID 属于已实现集合、无疑似真实凭据。它不运行模型，也不伪造
任何模型召回率数字——结构 PASS 不代表模型召回率达标；召回率只能来自按第 1 节
协议实际运行后的记录。

2026-09-24 的模型报告保存在 `results/2026-09-24/`。在任意离线 checkout 中可运行：

```bash
bash tests/evals/node-security/replay-results.sh
```

回放脚本使用结果目录 `baseline/` 中冻结的 catalog/profiles/expected-controls（缺少即拒绝），逐 case 从仓库 fixture 重新采集源码、冻结 review-input、解析 controls，
再调用报告校验器和 `compare-eval-report.pl` 比对已保存的模型报告与预期。
它不依赖评测时的 `/tmp` 产物，也不重新运行模型。末行应为
`EVAL_REPORTS_OK=19 PASS=19 FAIL=0`；任一报告校验、漏报、误报或状态漂移
均返回非零。需要保留中间 controls 供审计时，可传 `--work-dir <目录>`；
脚本只在该目录下创建独立 `replay.*` 子目录，不覆盖现有文件。比对器单独调用
时必须提供 `--controls <本 case 的 controls.json>`（或 `CCR_CONTROLS_JSON`）。

`tests/evals/test_node_security_results_replay.sh` 将上述离线回放和篡改拒绝纳入
全量测试；这验证的是**已提交评测证据的可复核性**，不是一次新的模型能力测量。

2026-10-08 新增四控制的 11-case 独立 Agent 前向评测证据保存在 `results/2026-10-08/`。运行 `bash tests/evals/node-security/replay-results.sh --results-dir tests/evals/node-security/results/2026-10-08`，应为 `EVAL_REPORTS_OK=11 PASS=11 FAIL=0`。这是不同模型档位/不同基线的单独结果，不能与历史 19-case 结果合并成同模型 30-case 召回率。条件、原始报告和限制见该目录 RESULTS.md。

## 6. 夹具内容约束（脱敏与泛化）

所有夹具为脱敏、泛化的最小项目：

- 不出现真实组织、真实域名、真实 token、客户数据或内部服务名；原事故已泛化为
  通用 BFF 形态，上游地址一律使用 `*-svc` 等虚构服务名；
- 不含任何真实凭据值（`express-session` 的 secret 等均为占位串）；
- 每个夹具是最小可读 Node 项目（package.json + 少量 .js），无需 npm install，
  仅供静态审查读取；文件内注释只说明作者意图，不标注答案。

## 有专门评测夹具的控制 ID（11 条）

CCR-NODE-BFFHEADER-001、CCR-NODE-SSRF-001、CCR-NODE-SESSION-001、
CCR-NODE-CMD-001、CCR-NODE-PATH-001、CCR-NODE-BOLA-001、CCR-NODE-BFLA-001、
CCR-NODE-HOSTROUTE-001、CCR-NODE-PROXYCAP-001、CCR-NODE-JWTAUTH-001、CCR-NODE-PROXYTRUST-001

## 夹具清单（30 个 case）

| 组 | case | 类型 | 关联控制 |
| --- | --- | --- | --- |
| bff-header-forwarding | vulnerable | 负面 | CCR-NODE-BFFHEADER-001 |
| bff-header-forwarding | secure | 对照 | CCR-NODE-BFFHEADER-001 |
| bff-header-forwarding | renamed-wrapped | 语义泛化 | CCR-NODE-BFFHEADER-001 |
| ssrf | vulnerable | 负面 | CCR-NODE-SSRF-001 |
| ssrf | secure | 对照 | CCR-NODE-SSRF-001 |
| ssrf | redirect-bypass | 负面（重定向绕过） | CCR-NODE-SSRF-001 |
| ssrf | dns-rebinding | 负面（校验与连接脱节） | CCR-NODE-SSRF-001 |
| ssrf | ipv6-mapped-bypass | 负面（地址归一化绕过） | CCR-NODE-SSRF-001 |
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
| host-routing | vulnerable / secure / renamed-wrapped | 固定目标 Host 路由正反/封装 | CCR-NODE-HOSTROUTE-001 |
| proxy-capability | vulnerable / secure | 代理能力授权正反 | CCR-NODE-PROXYCAP-001 |
| jwt-validation | decode-only / weak-verification / secure | decode/失败回退/完整校验 | CCR-NODE-JWTAUTH-001 |
| proxy-trust | vulnerable / secure / topology-unproven | 来源伪造/可信连接/缺部署证据 | CCR-NODE-PROXYTRUST-001 |
