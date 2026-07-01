# 前端审查框架重新设计

**日期**：2026-06-27
**状态**：待批准
**作者**：brainstorming 会话产出
**前置**：`docs/superpowers/specs/2026-06-23-multi-language-reviewer-design.md`（多语言扩展一期）

---

## 1. 背景与问题

`2026-06-23-multi-language-reviewer-design.md` 一期为前端引入了审查能力，但前端审查框架沿用了 Java 的 15 维度结构（D01–D15）。复盘发现 **3 个维度是注水硬凑**，且**前端企业项目真正高频的痛点没有专属维度**：

### 1.1 注水维度证据

| 维度 | 判定 | 证据 |
|---|---|---|
| D12 跨端集成 | 硬凑 | 内容薄，standard 模式被关闭，spec 自述"首期弱化" |
| D13 异步与事件 | 硬凑 | 与 D1 竞态、D6 性能重复 |
| D14 客户端缓存一致性 | 最强凑数证据 | 把服务端"穿透/击穿/雪崩"生搬到前端——这三个概念在前端 SWR/React Query 场景几乎不存在 |

### 1.2 缺失的高价值维度

| 前端企业项目真实痛点 | 现状 |
|---|---|
| **类型安全边界**（any 污染/ts-ignore/三方库无类型/泛型逃逸） | 拆进 D1+D15，无专属维度，易被弱化 |
| **构建与依赖供应链** | 仅 D6 性能顺带 |
| **a11y / i18n** | 完全缺失（spec 第 9 节列了 a11y 但无独立维度） |

### 1.3 凑数的根因

设计一期定义了 `shared-review-framework.md`，规定 15 个稳定公共 ID（D01–D15），语言适配器负责"映射"为语言专属名称。为了让前端复用共享执行内核（批次状态机/去重合并/Ignore/报告字段），强制前端也填满 15 个格子。**代价是 D12/D13/D14 被注水，真实痛点无处安放。**

> 根本判断：**审查框架没必要抽公共。** 维度是语言特定的，强行抽一张跨语言对照表，既不指导审查（前端 agent 读自己的 framework），也不指导合并（去重按文本哈希），纯粹是给自己制造维护同步负担。共享执行内核（`scripts/core/`）有真价值，留；共享维度分类法无价值，删。

---

## 2. 决策记录

本设计经 brainstorming 会话逐项确认：

| 决策点 | 选择 | 理由 |
|---|---|---|
| 维度模型 | **彻底解耦**：前端独立维度集，不用 D01–D15 编号 | 维度本质语言特定，不抽公共 |
| 项目场景 | **B 端中后台管理系统** | 收敛 a11y/i18n/出海合规等非高频痛点 |
| 性能维度 | **保留，聚焦中后台** | 大表虚拟化/接口串行/重复请求是高频痛点 |
| 类型安全 | **独立维度（P0 级）** | 中后台 TS 重度使用，any 逃逸是事故源 |
| 注水维度处理 | **归位**（不丢内容） | D12→安全/契约，D13→副作用，D14→状态管理 |
| 维度集方案 | **方案 A：扁平 11 维度** | 全部硬价值，无注水空间 |
| Java 框架位置 | **平级搬入 `languages/java/`** | 目录结构对称，Java 不特殊待在根目录 |
| 共享维度表 | **删除** `shared-review-framework.md` | 零代码消费，纯过渡设计 |
| fast 开类型安全 | **是** | PR 卡口拦截 any 逃逸 |
| 路径切换 | **干净切换，不留旧路径兼容** | 同仓库内部路径，测试兜底 |
| 维度数断言 | **硬断言 11** | 防止再次注水膨胀 |

---

## 3. 目标与非目标

### 3.1 目标

- 前端定义自己的 11 维度审查框架，与 Java 的 15 维度完全解耦，不编号、不映射。
- 把注水维度的真实内容归位到合适的维度，不丢审查覆盖。
- 为"类型安全"建立独立维度，覆盖中后台高频类型系统问题。
- 目录结构对称：Java/前端/未来 Python 各自独立框架，平级存放。
- 删除 `shared-review-framework.md`，消除维护同步负担。
- 新增契约测试断言，防止退回注水结构。

### 3.2 非目标

- 不改动共享执行内核（`scripts/core/`、`scripts/phase*.sh`）的任何逻辑。
- 不改动报告格式（`report-format.md`）、Ignore 机制（`ignore-workflow.md`）——它们本就语言无关。
- 不改动 Java 框架的 15 维度内容（只搬路径）。
- 不为 C 端/出海场景引入 a11y/i18n 维度（B 端中后台非高频；未来按场景扩展）。
- 不引入报告驱动 Fix（保持一期范围：只完成 Scan 闭环）。

---

## 4. 技术可行性分析

### 4.1 15 维度 ID 的真实消费面（探查结论）

经仓库全量搜索，D01–D15 这 15 个 ID 字面量：

| 消费方 | 依赖程度 | 证据 |
|---|---|---|
| 合并去重 | **无依赖** | `scripts/core/merge-batch-results.sh:58-84` 按问题块整段文本哈希 + `^### (P0-3\|待确认)` 标题正则 |
| Ignore | **无依赖** | `ignore-workflow.md:31-53` YAML schema 无"所属维度"字段，匹配是语义匹配 |
| 报告格式 | **无依赖** | `report-format.md:7` 明确"不按维度分组"，维度是自由文本标签 |
| 契约测试 | **无依赖** | 零测试断言维度数量或范围 |
| Agent 维度启用 | **数据驱动** | 运行时读框架文件矩阵，不硬编码 |

**结论：15 个 D-ID 是纯文档约定，零运行时代码消费。** 前端只声明部分/独立维度在技术上无阻力。

### 4.2 Java 框架路径搬迁的影响面

`references/review-framework.md` 有真实运行时消费者：

| 引用位置 | 类型 | 搬迁需改动 |
|---|---|---|
| `skills/cc-code-reviewer/SKILL.md:348` | `REVIEW_FRAMEWORK_PATH` 硬编码 | 改路径 |
| `agents/cc-code-reviewer.md:105` | 回退相对路径 | 改路径 |
| `tests/test_contract_docs.sh:93,152` | 路径断言 | 改断言 |
| `README.md:119` / `AGENTS.md:199` / `CLAUDE.md:199` | 文档说明 | 改路径 |

其余命中全在 `.superpowers/`（历史归档）和 `docs/`（设计记录），非运行时。无 Java 代码消费（Phase 4 Java 迁移尚在设计阶段）。

---

## 5. 架构设计

### 5.1 目标目录结构（对称）

```
references/
├── report-format.md                         # 语言无关，不动
├── ignore-workflow.md                       # 语言无关，不动
└── languages/
    ├── java/
    │   └── review-framework.md              # 从 references/ 根目录搬入，内容不动（15 维度）
    └── frontend/
        ├── review-framework.md              # 重写：11 维度 + 模式矩阵
        ├── react-rules.md                   # 重写：按新维度名
        └── source-scope.md                  # 不动

[删除] references/shared-review-framework.md  # 过度设计，零代码消费
```

### 5.2 共享层分家（明确边界）

| 层 | 职责 | 命运 |
|---|---|---|
| **共享执行内核** `scripts/core/` | 批次状态机/去重合并/覆盖率/路径校验/语言探测 | **留**——与"审查什么"无关，只管"怎么执行"，是合理的语言无关层 |
| **共享审查框架** `shared-review-framework.md` | 15 维度跨语言分类法 | **删**——维度是语言特定的，抽公共无价值 |

`report-format.md` 的"所属维度"字段本就是自由文本标签，各语言填自己的维度名；`ignore-workflow.md` 的 schema 无维度字段。两者天然语言无关，不动。

### 5.3 未来扩展（Python）

未来加 Python 时，只需新建 `references/languages/python/review-framework.md`，**不用动任何共享层**。各语言框架完全独立、互不映射。

---

## 6. 前端 11 维度清单

聚焦 B 端中后台真实痛点。每个维度标注来源（新建/吸收/保留），保证归位可追溯。

### 1. 正确性 `[保留]`
- **Hooks 依赖**：useEffect/useMemo/useCallback 依赖数组遗漏/多余 → 陈旧闭包
- **异步竞态**：effect 中未取消的请求、竞态写入
- **空值/类型逃逸边界**：可选链缺失、非空断言滥用导致的运行时崩溃
- **边界条件**：空数组、undefined、极值、NaN

### 2. 类型安全 ★`[新建 — 中后台 P0 级痛点]`
- **any 污染**：any 逃逸到组件 props/函数返回值/状态，污染调用链
- **断言滥用**：as any、as unknown as、非空断言 ! 滥用
- **类型逃逸**：@ts-ignore / @ts-expect-error 无注释、三方库无类型直接 any 化
- **泛型边界**：泛型约束缺失、any 透传导致类型保护形同虚设
- **三方库类型**：缺失 .d.ts、import 无类型模块未声明
- **可空/联合类型**：未窄化、null/undefined 未区分处理

### 3. 代码质量 `[保留，吸收技术债/架构]`
- **单一职责**：组件/函数职责是否单一
- **DRY**：重复逻辑（中后台常见表格/表单模板重复）
- **复杂度**：函数/组件过长或嵌套过深
- **命名规范**：组件、props、hooks 命名是否清晰
- **公共组件滥用**（吸收原架构 D11）：pro-components 滥用、通用组件被到处乱用
- **循环依赖/跨层引用**（吸收原架构 D11）
- **过时依赖/临时代码**（吸收原技术债 D10）

### 4. React 规范 `[保留，聚焦 Hooks/渲染]`
- **Hooks 规则**：不在条件/循环中调用
- **依赖正确性**：effect 依赖完整且最小
- **重渲染**：缺失 memo、内联对象/函数 props 导致不必要重渲染
- **key 使用**：列表用 index 作 key 的风险

### 5. 状态与数据请求 `[保留 + 吸收 D14]`
- **状态归属**：局部 vs 提升 vs 全局的选择是否合理
- **数据请求**：loading/error 状态处理、请求取消、竞态
- **缓存失效**（吸收原 D14）：SWR/React Query 的 key 与失效策略
- **乐观更新**：回滚与一致性

### 6. 安全 `[保留 + 吸收 D12 的 BFF 部分]`
- **XSS**：dangerouslySetInnerHTML、用户输入直接渲染
- **前端凭据**：token 写 localStorage、公共代码硬编码
- **开放重定向**：用户可控 URL 跳转
- **BFF 鉴权透传**（吸收原 D12）：接口鉴权、token 透传、401/403 处理
- **依赖风险**：lockfile 版本漏洞结论规则

### 7. 性能（中后台聚焦）`[保留，内容重写]`
- **大表虚拟化**：长列表/大表格未虚拟化（中后台最高频性能问题）
- **接口串行/瀑布**：可并行的请求串行、未用 Promise.all
- **重复请求**：相同数据重复请求、未做请求缓存
- **不必要重渲染**：缺失 memo/useMemo、context 值未缓存
- **节流防抖缺失**（吸收原 D13）：高频事件（scroll/resize/input 搜索）未做 throttle/debounce
- **Bundle**：懒加载缺失、整包引入

### 8. 副作用与资源清理 `[保留 + 吸收 D13]`
- **Event listener**：addEventListener 未配对 removeEventListener
- **timer**：setInterval/setTimeout 未清理
- **订阅**：Observable/EventEmitter/事件总线（吸收原 D13）未取消
- **请求取消**：AbortController 未使用导致 unmount 后 setState

### 9. 错误监控与可观测性 `[保留]`
- **Error Boundary**：关键路由是否被 Error Boundary 包裹
- **关键错误上报**：用户可恢复错误的捕获与上报
- **敏感信息**：错误日志中是否泄露 token/PII

### 10. 测试质量 `[保留，standard 精简]`
- **standard** 仅检查：核心逻辑是否有对应测试、关键路径（鉴权/异步/错误边界）测试是否缺失
- **deep** 存量审查：测试覆盖、核心逻辑、关键路径、Mock 使用、边界测试

### 11. 接口与类型契约 `[保留 + 吸收 D12 接口部分]`
- **standard** 仅检查：RESTful 规范、错误处理、分页规范（中后台高频）
- **deep** 存量审查：RESTful、版本管理、错误处理、幂等、分页、接口文档、**类型契约一致性**（前后端类型对齐、响应类型与实际不符）

### 6.1 关键设计说明

**类型安全为何独立（§2）**：中后台 TS 重度使用，一个 `any` 逃逸会沿 props 链污染整个组件树，生产表现为"明明写了 TS 却运行时崩"。拆进正确性（只看 NPE 类崩溃）和契约（只看 API 对齐）会漏掉"三方库无类型""泛型约束缺失"这类纯类型系统问题。独立维度才能完整覆盖。

**技术债/架构为何融入代码质量（§3）**：中后台架构问题多是 pro-components 滥用、循环依赖、通用组件乱用，归代码质量更自然，避免与"单一职责/复杂度"重复。

### 6.2 归位对照（可追溯性）

| 原维度 | 去向 | 说明 |
|---|---|---|
| D1 正确性 | → §1 | |
| D2 代码质量 | → §3 | |
| D3 React 规范 | → §4 | |
| D4 状态管理 | → §5 | |
| D5 安全 | → §6 | |
| D6 性能 | → §7 | 内容重写聚焦中后台 |
| D7 副作用清理 | → §8 | |
| D8 错误监控 | → §9 | |
| D9 测试 | → §10 | |
| D10 技术债 | → 融入 §3 代码质量 | |
| D11 架构 | → 融入 §3 代码质量 | |
| **D12 跨端** | → §6 安全（鉴权）+ §11 契约 | |
| **D13 异步事件** | → §8 副作用（订阅）；节流防抖由 §7 覆盖 | |
| **D14 缓存一致性** | → §5 状态（缓存失效）；**丢弃穿透/击穿/雪崩类比**（前端不存在的服务端概念） | |
| D15 接口契约 | → §11 | |
| **类型安全** | → §2 ★新增 | |

---

## 7. 模式矩阵（fast/standard/deep/security × 11 维度）

继承现有 Java 矩阵的模式语义（fast 只扫会炸产线的、standard 日常门禁、deep 全量、security 安全核心+强相关交叉），映射到前端真实风险。

| 维度 | fast | standard | deep | security |
|---|:---:|:---:|:---:|:---:|
| 1 正确性 | ✅ | ✅ | ✅ | ✅ |
| 2 类型安全 | ✅ 仅 any 逃逸+断言滥用 | ✅ | ✅ | — |
| 3 代码质量 | — | ✅ | ✅ | — |
| 4 React 规范 | ✅ 仅 Hooks 依赖+配置安全 | ✅ | ✅ | ✅ 仅配置安全子项 |
| 5 状态与数据请求 | — | ✅ | ✅ | ✅ 仅注入/越权子项 |
| 6 安全 | ✅ 仅 P0 级 | ✅ | ✅ | ✅ 全深度 |
| 7 性能 | — | ✅ | ✅ | — |
| 8 副作用与资源清理 | ✅ | ✅ | ✅ | — |
| 9 错误监控 | — | ✅ | ✅ | ✅ 仅敏感信息泄露 |
| 10 测试质量 | — | ✅ 仅核心测试缺失 | ✅ | — |
| 11 接口与类型契约 | — | ✅ 仅 RESTful+错误处理 | ✅ | ✅ 仅鉴权/错误信息 |

### 模式覆盖说明

- **fast**（快速扫雷，PR 卡口）：维度 1、2（部分）、4（部分）、6（P0）、8。聚焦会直接炸产线的：Hooks 依赖导致的陈旧闭包/竞态、any 逃逸导致运行时崩、副作用未清理（内存泄漏/unmount setState）、P0 级安全（XSS/凭据/开放重定向）。**类型安全进 fast 是关键差异**——中后台 any 污染是高频事故源，值得 PR 卡口拦截。
- **standard**（日常迭代门禁）：1-11 全覆盖，但 10 只查核心测试缺失、11 只查 RESTful+错误处理+分页。
- **deep**（全量，大版本上线）：11 维度全开，含测试质量深挖、契约一致性、状态缓存失效完整策略。
- **security**（安全合规）：6 全深度 + 与安全强相关交叉维度（4 配置安全、5 注入/越权、9 敏感信息、11 鉴权/错误信息）。**类型安全在 security 关闭**——类型问题是质量问题不是安全问题，不污染安全报告。

### P0 分级门槛（不变，语言无关契约）

**P0 五项硬门槛**：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。五项必须同时满足；任一不满足都不得标为 P0。

- 证据成立但影响未达到事故级或已有有效缓解机制：P1。
- 事故级风险尚缺生产可达性、调用链、运行配置或防护状态证据：待确认。
- 其他问题继续按影响进入 P2/P3。
- standard、deep、security 模式不得静默丢弃未通过 P0 门槛的候选；fast 按纯 P0 模式边界只输出 P0。

### 依赖风险结论规则

依赖风险只有在 lockfile 版本明确且证据可靠时才能形成确定性漏洞结论；否则必须归为待确认或依赖扫描建议，不得仅凭"版本较旧"的印象下漏洞结论。

---

## 8. 文件改动清单

### 8.1 改动总表（10 个文件，0 脚本逻辑改动）

| # | 文件 | 动作 | 细节 |
|---|---|---|---|
| 1 | `references/languages/java/review-framework.md` | **git mv** | 从 `references/review-framework.md` 搬入，内容不动 |
| 2 | `references/languages/frontend/review-framework.md` | **重写** | 11 维度清单（§6）+ 模式矩阵（§7）+ P0 门槛 + 依赖规则 |
| 3 | `references/languages/frontend/react-rules.md` | **重写** | 按新 11 维度名组织规则章节（原 D01/D03… 改为中文名） |
| 4 | `references/shared-review-framework.md` | **删除** | 过度设计，零代码消费 |
| 5 | `skills/cc-code-reviewer/SKILL.md` | **改 Java 路径（2 处）** | `:348` 的 `REVIEW_FRAMEWORK_PATH` 变量 + `:1001` 参数表示例值，均 → `references/languages/java/review-framework.md`，干净切换不留兼容 |
| 6 | `agents/cc-code-reviewer.md` | **改回退路径** | `:105` 相对路径同步改 |
| 7 | `tests/test_contract_docs.sh` | **改断言** | Java 路径断言同步；删 shared 文件行；新增前端反注水断言（见 §8.2） |
| 8 | `README.md` | **改路径** | Java 框架路径说明同步 |
| 9 | `AGENTS.md` | **改路径+目录树** | Java 框架路径说明同步；文件结构树补 `languages/java/`、`languages/frontend/` 层级 |
| 10 | `CLAUDE.md` | **改路径+目录树** | 同 AGENTS.md |

### 8.2 新增契约测试断言（`tests/test_contract_docs.sh` 前端断言块）

防止退回注水结构：

```bash
# 前端审查框架必须使用独立维度集，不得引用 D01-D15 编号体系
FE_FRAMEWORK="$ROOT_DIR/references/languages/frontend/review-framework.md"
# 反向断言:不得出现 "D01_CORRECTNESS" 等公共 ID 字面量
if grep -qE 'D(0[1-9]|1[0-5])_[A-Z_]+' "$FE_FRAMEWORK"; then
  echo "FAIL: 前端框架不得引用 Java 公共维度 ID" >&2; exit 1
fi
# 正向断言:必须包含类型安全维度(中后台 P0 级)
grep -q "类型安全" "$FE_FRAMEWORK" || { echo "FAIL: 前端框架必须包含类型安全维度" >&2; exit 1; }
# 正向断言:必须声明 11 维度(硬断言,防止再次注水膨胀)
FE_DIM_COUNT=$(grep -cE '^### [0-9]+\. ' "$FE_FRAMEWORK")
if [ "$FE_DIM_COUNT" -ne 11 ]; then
  echo "FAIL: 前端框架必须声明 11 维度，当前 $FE_DIM_COUNT" >&2; exit 1
fi
# shared-review-framework.md 必须已删除
if [ -f "$ROOT_DIR/references/shared-review-framework.md" ]; then
  echo "FAIL: shared-review-framework.md 应已删除，审查框架各语言独立" >&2; exit 1
fi
```

同时修改原断言块：
- Java 路径断言 `:93,152` 由 `references/review-framework.md` → `references/languages/java/review-framework.md`
- 删除 `:698` 的 `shared-review-framework.md` 文件存在性断言

### 8.3 明确不改动的文件（边界保护）

- `scripts/core/*` 和 `scripts/phase*.sh`：**0 改动**（合并去重按文本哈希，Ignore 无维度字段，全部语言无关）
- `references/report-format.md`、`ignore-workflow.md`：**0 改动**（报告不按维度分组，维度是自由文本标签）
- `agents/cc-code-reviewer-frontend.md`：**仅 REACT_RULES_PATH 指向的文件内容变，agent 文件本身不改**（agent 数据驱动读框架文件）
- Java 框架内容：**0 改动**（只搬路径，15 维度原样保留）

---

## 9. 风险与回滚

### 9.1 风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| Java 路径搬迁漏改一处 → Java 审查找不到框架 | 低 | 高（Java 流程断） | 改动机械化（8 文件），契约测试 `:93,152` 捕获路径断言失败，`bash tests/run_all.sh` 前置验证 |
| `react-rules.md` 重写遗漏原规则 | 中 | 中（审查覆盖下降） | 归位对照表（§6.2）逐条核对，重写后 diff review |
| 前端维度名与 Java 维度名重名导致跨语言报告混淆 | 低 | 低 | 报告本就不按维度分组、不跨语言合并；各语言报告独立 |

### 9.2 回滚

`git revert` 单次提交即可，无数据迁移、无破坏性操作。

### 9.3 验收

- `bash tests/run_all.sh` 全绿，含新增反注水断言。
- Java 审查流程无回归（路径搬迁后正常读取框架）。
- 前端审查流程读取新 11 维度框架，不再引用 D01–D15。
- `shared-review-framework.md` 不存在。
- 目录结构对称：`languages/java/` 与 `languages/frontend/` 平级。

---

## 10. 开放问题

无。所有决策点已在 brainstorming 会话中确认（见 §2 决策记录）。

---

*本设计为 brainstorming 产出，待用户审阅批准后转 writing-plans 生成实施计划。*
