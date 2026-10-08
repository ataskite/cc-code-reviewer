# Node/BFF 代理与身份专项：独立 Agent 前向评测（2026-10-08）

新增四条控制的 11 个最小夹具全部按预期通过；原始报告保持审查 Agent 输出，不按预期改写。六个缺陷场景确认 P1，四个安全对照未确认目标控制缺陷，一个未知拓扑场景保留外部证据缺失。结论仅限这些静态输入，不代表真实项目检出率或业务风险已关闭。

## 条件与来源

- 工作分支 `feat/frontend-bff-security`，HEAD `1dea9ba4edff3775a2321ce5a6b4d4688db0ad31` + 本次未提交增强，VERSION 保持 1.7.1（未发布/安装）。评测的是工作区而不是该 HEAD 原版。
- 模型档位：Codex 当前会话 `inherit`，三个独立审查 Agent，同一继承配置；实际供应商模型名未独立取证，不猜测。不是历史 GLM-5.3 评测档位。
- 三组独立上下文：Host 三个 case、capability 两个 case、JWT/trust 六个 case；组内多个 case 共享 Agent 上下文，不宣称逐 case 全隔离。Agent 未收到预期答案，未读 expected-controls、历史结果或父会话。
- Security，全量读取各 fixture 全部 selected 文件，语义增强 none（模型静态跨文件追踪）。先生成 source manifest、review-input、controls、surface，再直接调度 frontend 审查 Agent及本地必读规则。属于隔离 Agent 前向评测，未跑 INTERACT/完整 Skill UI，不冒充交互端到端测试。
- 仅本地读取、生成 Markdown、确定性校验；没有联网、npm install 或发送实际攻击请求，未测试真实 Ingress/JWT 服务/代理部署。
- 每份报告 15 条适用控制 + 1 条排除控制；原始报告保存在本目录，包含取证位置、授权台账、控制台账及限制。独立审查均首轮通过格式校验。
- `baseline/catalog`、profiles、expected-controls 固定本次控制与预期；catalog 字节哈希 `e28ed8eb7f51c3fb9f2fce5d150a7d4224c1621f0966a5bdd1c433aaf048b50c`，与评测冻结 controls 记录一致。此快照保留评测时 JSON 格式，主 catalog 后续仅整理逗号排版，语义相同。
- `baseline/fixture-inputs.json` 保存实际审查 selected 路径及内容指纹；回放拒绝夹具内容/选中集合漂移。不依赖原 `/tmp/cc-proxy-auth-eval.44sjAD`，报告中的绝对路径仅记录执行上下文。

## 结果

| case | 目标控制状态 | 目标发现 / 预期比对 |
|---|---|---|
| host-routing/vulnerable | finding_confirmed | Host 从 body.header 进入 node:http；PASS |
| host-routing/secure | checked_no_finding | 服务端固定 Host，业务 query 不参与 transport；PASS |
| host-routing/renamed-wrapped | finding_confirmed | envelope → metadata → assemble → headers 跨文件传播；PASS |
| proxy-capability/vulnerable | finding_confirmed | 匿名调用任意内部 path，方法枚举不约束能力；PASS |
| proxy-capability/secure | checked_no_finding | 固定能力表 + 主体权限 + 参数/transport 分离；PASS |
| jwt-validation/decode-only | finding_confirmed | 未验证 claims 决定 admin 接受；PASS |
| jwt-validation/weak-verification | finding_confirmed | 忽略过期、失败回退 decode、缺接受约束；PASS |
| jwt-validation/secure | checked_no_finding | RS256/可信 key/issuer/audience/exp/nbf/异常拒绝；PASS |
| proxy-trust/vulnerable | finding_confirmed | 信任任意对端的 XFF，req.ip 驱动权限判断；PASS |
| proxy-trust/secure | checked_no_finding | 真实 socket 来源、loopback 监听、不消费转发头；PASS |
| proxy-trust/topology-unproven | external_evidence_missing | hop=1 但缺真实拓扑/头清洗，不猜测漏洞或安全；PASS |

目标控制：漏报 0、正式误报 0、严格状态漂移 0；其他控制的待确认风险仍保留在原报告，不以过滤它们来制造无风险结论。禁止将这个小样本数字外推成生产召回率。

## 可离线复核

```bash
bash tests/evals/node-security/replay-results.sh --results-dir tests/evals/node-security/results/2026-10-08
# EVAL_REPORTS_OK=11 PASS=11 FAIL=0
```

由报告校验器 + compare-eval-report.pl 对照已保存的真实模型报告，任一缺行、映射漂移、漏报、正式误报或严格状态漂移均非零退出；回放不是重新运行模型。篡改拒绝已纳入 tests/evals/test_node_security_results_replay.sh。

## 发现并修正的验收问题

1. 多控制聚合同一问题的文字曾与“每个 confirmed 控制有自身 ID 问题块”的校验契约矛盾。保持校验契约，修正规则：可共享证据，但每个 confirmed 控制各自落块，标注共同根因，不叠加夸大影响。
2. 比对器把待确认块也当成正式误报，曾把 topology-unproven 的正确待验证报告判 FAIL。比对器现分离 confirmed_found 与 pending_found；严格状态仍防止把缺证据伪装为安全对照通过。没有改写原模型报告或降低该 case 的 external_evidence_missing 预期。
3. 报告校验器注释与实现的 external_evidence_missing 口径漂移，只修正注释，不扩大判定放行。

历史 2026-09-24 的 19-case 结果使用旧 12 控制和另一模型，分目录独立回放；不能合并宣称“同模型 30/30”。实际四个 BFF 排查、Ingress/出站策略验证、生产修复关闭仍是另一个需真实代码与部署证据的工作。
