# CONTEXT.md — 领域词汇表

cc-code-reviewer 的领域语言。架构讨论、代码与测试评审统一使用下列术语；新概念先入表再进代码。

## 审查域

- **发现（finding）**：一次审查产出的一条结构化问题记录，位于报告中以 `### P0|P1|P2|P3|待确认` 开头的发现块内。
- **发现块（finding block）**：从 `### P0…待确认` 表头行起、到下一个 `##`/`###` 标题行为止的 Markdown 块；边界判定与解析的唯一实现在发现内核。
- **维度（dimension）**：发现表头 `[...]` 内层文本（空白折叠），参与发现身份。
- **证据（evidence）**：发现块内第一个闭合围栏代码块的内容；参与身份前先做证据行归一化。
- **证据行归一化（evidence-line normalization）**：去 CR → trim → 剥一个 +/- diff 前缀 → 再 trim → 去尾空白、空行全弃的确定性序列。
- **发现指纹（finding fingerprint）**：sha256(文件路径 ␀ 维度标签 ␀ 归一化证据)；跨批次去重、SARIF partialFingerprints 与跨轮对比共用的身份，行号不入键。
- **路径口径（path policy）**：同轮口径只剥结尾一个点锚（merge / SARIF）；跨轮口径点锚与区间锚全剥（compare）。两种口径并存是有意设计，不得互相替换。
- **上轮已报标记（repeat marking）**：按 路径 + 维度 + 行区间 IoU 判定的增量标记，命中在表头追加「（上轮已报）」；与发现指纹是两套独立身份。
- **轮次对比（cross-round compare）**：按指纹把两轮报告分入 new / persisting / resolved / not_reviewed 四桶（多重集 min(N,M)）。

## 结构域

- **发现内核（finding kernel）**：`scripts/core/lib/`（common.sh + CCR/Findings.pm）——发现块边界、证据行归一化、维度/路径提取、发现指纹与 sha256 回退链的唯一实现；relocate / merge / mark-repeat / compare / export-sarif 五个报告后处理脚本是它的 adapter。
- **快照哈希（snapshot hash）**：冻结输入与 review-rules.json 的字节级 sha256，服务于续跑准入门禁；计算走发现内核 common.sh 的回退链。
