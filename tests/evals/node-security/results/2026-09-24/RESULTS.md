# Node Security 模型评测记录（2026-09-24）

按 README 协议执行的首轮完整模型评测：19/19 case 全部 PASS。

## 评测条件

- 插件版本/commit：工作分支 `feat/frontend-bff-security` @ 886c66a（评测基线含 R1-R5 验收修复）
- 模型档位：ZCode 会话模型继承（GLM-5.3），子 agent 逐 case 独立执行（无跨 case 上下文）
- 模式：security 全量（存量审查）；冻结产物逐 case 预生成（review-input → controls → surface，`/tmp/cc-eval-20260923/artifacts`）
- 报告路径：本目录 `<case>.md`（19 份原始模型报告）
- 判定工具：`validate-security-report.sh`（确定性校验）+ `compare-eval-report.pl`（预期比对；漏报/误报/状态漂移）

## 结果矩阵

```
authorization/bfla-unbound | validator-OK | PASS | findings=1
authorization/bola-unbound | validator-OK | PASS | findings=1
authorization/function-bound | validator-OK | PASS | findings=0
authorization/owner-bound | validator-OK | PASS | findings=0
bff-header-forwarding/renamed-wrapped | validator-OK | PASS | findings=1
bff-header-forwarding/secure | validator-OK | PASS | findings=0
bff-header-forwarding/vulnerable | validator-OK | PASS | findings=1
command-injection/execfile-bound | validator-OK | PASS | findings=0
command-injection/renamed-wrapped | validator-OK | PASS | findings=1
command-injection/vulnerable | validator-OK | PASS | findings=1
path-traversal/root-bound | validator-OK | PASS | findings=0
path-traversal/vulnerable | validator-OK | PASS | findings=1
session-mass-assignment/allowlist-bound | validator-OK | PASS | findings=1
session-mass-assignment/vulnerable | validator-OK | PASS | findings=3
ssrf/dns-rebinding | validator-OK | PASS | findings=1
ssrf/ipv6-mapped-bypass | validator-OK | PASS | findings=1
ssrf/redirect-bypass | validator-OK | PASS | findings=2
ssrf/secure | validator-OK | PASS | findings=0
ssrf/vulnerable | validator-OK | PASS | findings=1
```

**汇总：19 PASS / 0 FAIL；确定性校验 19/19 通过；漏报 0、误报 0、状态漂移 0。**

## 关键观察

1. **vulnerable/wrapped 命中率 11/11**：全部不安全样例按预期 `finding_confirmed`，renamed-wrapped 双层改名传播（BFFHEADER/CMD）被语义追踪命中，非名称词表。
2. **secure 对照零误报 7/7**：重写后的 ssrf/secure（IP pin + TLS servername + 逐跳复验）被逐项语义核验后判无发现——与 R5 修复前的"清单勾选式放行"形成对照；execfile-bound/root-bound/owner-bound/function-bound/allowlist-bound 均逐条举证防护生效点。
3. **R5 新增绕过样例全部命中**：dns-rebinding（校验与连接脱节）、ipv6-mapped-bypass（归一化缺口）、redirect-bypass（首跳校验不覆盖后续跳）均被识别并定级。
4. **语义提升链路实测有效**：bff 系夹具（纯 Node 项目，BFFHEADER 被 profile 排除）中 agent 凭代码证据将排除控制提升为 finding_confirmed 并保持对账（E=排除数−提升数）。
5. **超出预期的加分项**：多个 case 主动报出未涵盖的真实缺陷（async 路由未处理 rejection 导致单请求 DoS、管理操作无审计日志、示意认证桩 P0 待验证）——均按契约不携带规则 ID、单列待确认。

## 偏差与重试记录

- 首批并发 10 agent 触发提供方限流（1302/1308 配额上限），调整为 ≤3 并发波次 + 串行重试；3 个 case 各重试 1-2 次后成功，成功运行均为完整审查（无截断）。
- session/allowlist-bound 首轮台账行缺列被确定性校验器拒绝（按真实流程重跑，非修改报告）；重跑后通过。
- 评测过程中顺带发现并修复：比对器块收集 bug（字符串误当数组引用）与 UTF-8 解码缺失、采集器纯服务端项目 `${array[@]}` 未绑定崩溃、校验器计数行对模型尾注的容差（与对账行同策略）。

## 边界声明

本记录证明的是**当前模型档位在 19 个脱敏最小夹具上的召回/误报表现**，不等价于真实仓库检出率；四个 BFF 的统一排查仍需按验收意见单独执行（冻结版本、入口/代理/鉴权矩阵、Ingress/出站策略、负向测试证据）。
