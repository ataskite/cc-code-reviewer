# 前端审查框架重新设计 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将前端审查框架从 Java 15 维度结构解耦为独立的 11 维度集（B 端中后台聚焦），Java 框架平级搬入 `languages/java/`，删除 `shared-review-framework.md`，新增反注水契约测试断言。

**Architecture:** 纯文档 + 测试断言改动，0 脚本逻辑改动。TDD 表现为"先写反注水测试断言（先红），再改文档让它绿"。改动机械化、边界清晰，单次 `git revert` 可回滚。

**Tech Stack:** Bash 契约测试、Markdown 文档、git mv。

**Spec:** `docs/superpowers/specs/2026-06-27-frontend-review-framework-redesign-design.md`

## Global Constraints

- 前端维度集与 Java D01–D15 **完全解耦**，不编号、不映射。
- 前端 **11 维度**（硬断言），不得引用 `D01_CORRECTNESS` 等 Java 公共 ID 字面量。
- Java 框架**只搬路径，内容不动**（15 维度原样保留）。
- **干净切换，不留旧路径兼容**（同仓库内部路径，测试兜底）。
- **0 脚本逻辑改动**：`scripts/core/*`、`scripts/phase*.sh`、`references/report-format.md`、`references/ignore-workflow.md` 不动。
- `shared-review-framework.md` **必须删除**。
- 完成后 `bash tests/run_all.sh` 全绿。

---

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `tests/test_contract_docs.sh` | 契约测试，断言文档结构一致 | 改：Java 路径断言、删 shared 行、新增前端反注水断言 |
| `references/languages/java/review-framework.md` | Java 15 维度框架 | git mv 搬入，内容不动 |
| `references/languages/frontend/review-framework.md` | 前端 11 维度框架 | 重写 |
| `references/languages/frontend/react-rules.md` | 前端规则细则 | 重写 |
| `references/shared-review-framework.md` | （待删除） | 删除 |
| `skills/cc-code-reviewer/SKILL.md` | 主 skill，Java 路径注入 | 改 2 处路径 |
| `agents/cc-code-reviewer.md` | Java agent 回退路径 | 改 1 处路径 |
| `README.md` / `AGENTS.md` / `CLAUDE.md` | 文档说明 | 改路径引用 |

---

### Task 1: 先写反注水契约测试断言（TDD — 先红）

**Files:**
- Modify: `tests/test_contract_docs.sh:152`（Java P0 门槛断言路径）
- Modify: `tests/test_contract_docs.sh:93-94`（REVIEW_FRAMEWORK_PATH 断言）
- Modify: `tests/test_contract_docs.sh:686-703`（前端文件存在性断言块）

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: 失败的测试，驱动后续文档改动使其变绿

**说明：** 本任务的测试改动后运行会失败（红），因为文档还没改。这是 TDD 的"红"阶段。Task 2-7 改文档使其逐项变绿。Task 8 跑全量验证。

- [ ] **Step 1: 修改 Java 路径断言（:93）**

将 `tests/test_contract_docs.sh:93`：

```bash
grep -q 'REVIEW_FRAMEWORK_PATH=.*references/review-framework.md' "$SKILL_FILE"
```

改为：

```bash
grep -q 'REVIEW_FRAMEWORK_PATH=.*references/languages/java/review-framework.md' "$SKILL_FILE"
```

- [ ] **Step 2: 修改 Java P0 门槛断言（:152）**

将 `tests/test_contract_docs.sh:152`：

```bash
require_literal "$ROOT_DIR/references/review-framework.md" "P0 五项硬门槛" "review framework must share the strict P0 contract"
```

改为：

```bash
require_literal "$ROOT_DIR/references/languages/java/review-framework.md" "P0 五项硬门槛" "review framework must share the strict P0 contract"
```

- [ ] **Step 3: 修改前端文件存在性断言块（:686-703），删除 shared 行并新增反注水断言**

将 `tests/test_contract_docs.sh:686-703` 的前端文件清单循环：

```bash
# === 前端多语言文档同步断言 ===
for f in \
  "scripts/core/detect-language.sh" \
  "scripts/core/validate-scope.sh" \
  "scripts/core/plan-file-batches.sh" \
  "scripts/core/merge-batch-results.sh" \
  "scripts/languages/frontend/detect-project.sh" \
  "scripts/languages/frontend/scan-project.sh" \
  "scripts/languages/frontend/collect-source-files.sh" \
  "scripts/languages/frontend/detect-code-intelligence.sh" \
  "agents/cc-code-reviewer-frontend.md" \
  "references/language-adapter-contract.md" \
  "references/shared-review-framework.md" \
  "references/languages/frontend/source-scope.md" \
  "references/languages/frontend/review-framework.md" \
  "references/languages/frontend/react-rules.md"; do
  [ -f "$ROOT_DIR/$f" ] || { echo "MISSING: $f" >&2; exit 1; }
done
```

改为（删除 shared 行，新增 Java 框架新路径 + 反注水断言）：

```bash
# === 前端多语言文档同步断言 ===
for f in \
  "scripts/core/detect-language.sh" \
  "scripts/core/validate-scope.sh" \
  "scripts/core/plan-file-batches.sh" \
  "scripts/core/merge-batch-results.sh" \
  "scripts/languages/frontend/detect-project.sh" \
  "scripts/languages/frontend/scan-project.sh" \
  "scripts/languages/frontend/collect-source-files.sh" \
  "scripts/languages/frontend/detect-code-intelligence.sh" \
  "agents/cc-code-reviewer-frontend.md" \
  "references/language-adapter-contract.md" \
  "references/languages/java/review-framework.md" \
  "references/languages/frontend/source-scope.md" \
  "references/languages/frontend/review-framework.md" \
  "references/languages/frontend/react-rules.md"; do
  [ -f "$ROOT_DIR/$f" ] || { echo "MISSING: $f" >&2; exit 1; }
done

# shared-review-framework.md 必须已删除（过度设计，不再维护公共维度分类法）
if [ -f "$ROOT_DIR/references/shared-review-framework.md" ]; then
  echo "FAIL: shared-review-framework.md 应已删除，审查框架各语言独立" >&2
  exit 1
fi

# 前端审查框架必须使用独立维度集，不得引用 Java 公共维度 ID（D01_CORRECTNESS 等）
FE_FRAMEWORK="$ROOT_DIR/references/languages/frontend/review-framework.md"
if grep -qE 'D(0[1-9]|1[0-5])_[A-Z_]+' "$FE_FRAMEWORK"; then
  echo "FAIL: 前端框架不得引用 Java 公共维度 ID" >&2
  exit 1
fi
# 正向断言：必须包含类型安全维度（中后台 P0 级）
grep -q "类型安全" "$FE_FRAMEWORK" || { echo "FAIL: 前端框架必须包含类型安全维度" >&2; exit 1; }
# 正向断言：必须声明 11 维度（硬断言，防止再次注水膨胀）
FE_DIM_COUNT=$(grep -cE '^## [0-9]+\. ' "$FE_FRAMEWORK")
if [ "$FE_DIM_COUNT" -ne 11 ]; then
  echo "FAIL: 前端框架必须声明 11 维度，当前 $FE_DIM_COUNT" >&2
  exit 1
fi
```

- [ ] **Step 4: 运行测试，确认它失败（红）**

Run: `bash tests/test_contract_docs.sh`
Expected: FAIL —— 因为 Java 框架还没搬、shared 还没删、前端框架还是 15 维度旧版。

这是预期的红，不要在此处修复。

- [ ] **Step 5: Commit**

```bash
git add tests/test_contract_docs.sh
git commit -m "test(contract): add anti-padded-dimension assertions for frontend framework redesign"
```

---

### Task 2: Java 框架搬路径（git mv，内容不动）

**Files:**
- Create: `references/languages/java/review-framework.md`（git mv 产生）
- Delete: `references/review-framework.md`（git mv 产生）

**Interfaces:**
- Consumes: 无
- Produces: `references/languages/java/review-framework.md`（15 维度内容原样）

- [ ] **Step 1: 确认 Java 目录存在，不存在则创建**

Run: `mkdir -p references/languages/java`
Expected: 无输出（目录已存在或创建成功）

- [ ] **Step 2: git mv 搬迁 Java 框架**

Run: `git mv references/review-framework.md references/languages/java/review-framework.md`
Expected: 无输出，文件已移动。

- [ ] **Step 3: 确认内容未被改动（应与搬前一致）**

Run: `git show HEAD:references/review-framework.md | diff - references/languages/java/review-framework.md`
Expected: 无输出（内容完全一致）。

- [ ] **Step 4: 暂不提交，与 Task 3-7 合并提交（避免中间态 Java 审查断链）**

**说明：** 单独提交 Java 路径搬迁但未改 SKILL/Agent/测试会导致中间 commit Java 审查断链。Java 搬迁 + SKILL/Agent/文档路径同步合并到 Task 6 一起提交，保证每个 commit 都是自洽的。

---

### Task 3: 重写前端审查框架（11 维度 + 模式矩阵）

**Files:**
- Modify: `references/languages/frontend/review-framework.md`（整体重写）

**Interfaces:**
- Consumes: spec §6 维度清单、§7 模式矩阵
- Produces: 11 维度定义文档，满足 Task 1 的反注水断言

- [ ] **Step 1: 重写 `references/languages/frontend/review-framework.md`**

将整个文件替换为以下内容：

```markdown
# 前端代码审查框架

本手册定义前端（React/TypeScript/JavaScript，B 端中后台聚焦）代码审查的 11 个维度。维度与 Java 的 15 维度结构完全独立，不编号、不映射。各模式的启用范围以"审查模式 × 维度覆盖矩阵"为准。

> 审查框架各语言独立。Java 框架见 `references/languages/java/review-framework.md`；本文件不引用任何 Java 公共维度编号。

---

## 审查模式 × 维度覆盖矩阵

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
| 9 错误监控与可观测性 | — | ✅ | ✅ | ✅ 仅敏感信息泄露 |
| 10 测试质量 | — | ✅ 仅核心测试缺失 | ✅ | — |
| 11 接口与类型契约 | — | ✅ 仅 RESTful+错误处理 | ✅ | ✅ 仅鉴权/错误信息 |

---

## 模式说明

- **fast**（快速扫雷）：仅扫描会直接炸产线或造成明显安全/稳定性风险的问题，聚焦正确性、类型安全（any 逃逸+断言滥用）、Hooks 依赖与配置安全、副作用与资源清理、P0 级安全问题（XSS/危险 HTML/凭据/开放重定向）。适合 PR 合并前快速卡口。覆盖维度：1、2（部分）、4（部分）、6（P0）、8。
- **standard**（标准审查）：日常迭代推荐模式，覆盖全部 11 维度，但 10 只查核心测试缺失、11 只查 RESTful+错误处理+分页。适合迭代上线前的常规质量门禁。覆盖维度：1-11（10/11 部分启用）。
- **deep**（深度审查）：全量 11 维度，含测试质量和技术债深挖。适合大版本上线前或重要模块的系统性审查，耗时较长。覆盖维度：1-11 全开。
- **security**（安全专项）：聚焦安全核心（维度 6 全深度）及与安全强相关的交叉维度（配置安全、注入/越权、敏感信息泄露、接口鉴权/错误信息）。类型安全在 security 关闭——类型问题是质量问题不是安全问题，不污染安全报告。覆盖维度：1、4（部分）、5（部分）、6、9（部分）、11（部分）。

---

## 各维度详细审查标准

### 1. 正确性
- **Hooks 依赖**：useEffect/useMemo/useCallback 依赖数组遗漏/多余导致陈旧闭包或错误缓存
- **异步竞态**：effect 中未取消的请求、Promise 未处理、竞态写入
- **空值/类型逃逸边界**：`as any`、非空断言滥用、可选链缺失导致的运行时崩溃
- **边界条件**：空数组、undefined、极值、NaN

### 2. 类型安全
- **any 污染**：any 逃逸到组件 props/函数返回值/状态，污染调用链
- **断言滥用**：as any、as unknown as、非空断言 ! 滥用
- **类型逃逸**：@ts-ignore / @ts-expect-error 无注释、三方库无类型直接 any 化
- **泛型边界**：泛型约束缺失、any 透传导致类型保护形同虚设
- **三方库类型**：缺失 .d.ts、import 无类型模块未声明
- **可空/联合类型**：未窄化、null/undefined 未区分处理

### 3. 代码质量
- **单一职责**：组件/函数是否职责单一
- **DRY**：是否存在重复逻辑（中后台常见表格/表单模板重复）
- **复杂度**：函数/组件是否过长或嵌套过深
- **命名规范**：组件、props、hooks 命名是否清晰
- **公共组件滥用**：pro-components 滥用、通用组件被到处乱用
- **循环依赖/跨层引用**：组件/hooks 循环引用、UI 组件直接依赖数据层
- **过时依赖/临时代码**：技术债识别

### 4. React 规范
- **Hooks 规则**：不在条件/循环中调用 Hooks
- **依赖正确性**：effect 依赖完整且最小
- **重渲染**：缺失 memo、内联对象/函数 props 导致不必要重渲染
- **key 使用**：列表用 index 作 key 的风险

### 5. 状态与数据请求
- **状态归属**：局部 vs 提升 vs 全局的选择是否合理
- **数据请求**：loading/error 状态处理、请求取消、竞态
- **缓存失效**：SWR/React Query 的 key 与失效策略
- **乐观更新**：回滚与一致性

### 6. 安全
- **XSS**：dangerouslySetInnerHTML、用户输入直接渲染
- **前端凭据**：token 写 localStorage、公共代码硬编码
- **开放重定向**：用户可控 URL 跳转
- **BFF 鉴权透传**：接口鉴权、token 透传、401/403 处理
- **不安全 URL 拼接**：SSRF 向量（前端→BFF）
- **依赖风险**：lockfile 版本漏洞结论规则见下

### 7. 性能（中后台聚焦）
- **大表虚拟化**：长列表/大表格未虚拟化（react-window/virtual）
- **接口串行/瀑布**：可并行的请求串行、未用 Promise.all
- **重复请求**：相同数据重复请求、未做请求缓存
- **不必要重渲染**：缺失 memo/useMemo、context 值未缓存
- **节流防抖缺失**：高频事件（scroll/resize/input 搜索）未做 throttle/debounce
- **Bundle**：懒加载缺失、整包引入

### 8. 副作用与资源清理
- **Event listener**：addEventListener 未配对 removeEventListener
- **timer**：setInterval/setTimeout 未清理
- **订阅**：Observable/EventEmitter/事件总线未取消
- **请求取消**：AbortController 未使用导致 unmount 后 setState

### 9. 错误监控与可观测性
- **Error Boundary**：关键路由是否被 Error Boundary 包裹
- **关键错误上报**：用户可恢复错误的捕获与上报
- **敏感信息**：错误日志中是否泄露 token/PII

### 10. 测试质量
- **standard** 仅检查：核心逻辑是否有对应测试、关键路径（鉴权/异步/错误边界）测试是否缺失
- **deep** 存量审查：测试覆盖、核心逻辑、关键路径、Mock 使用、边界测试

### 11. 接口与类型契约
- **standard** 仅检查：RESTful 规范、错误处理、分页规范（中后台高频）
- **deep** 存量审查：RESTful、版本管理、错误处理、幂等、分页、接口文档、类型契约一致性（前后端类型对齐、响应类型与实际不符）

---

## P0 分级门槛

**P0 五项硬门槛**（与 Java 一致，必须全部满足）：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。五项必须同时满足；任一不满足都不得标为 P0。

- 证据成立但影响未达到事故级或已有有效缓解机制：P1。
- 事故级风险尚缺生产可达性、调用链、运行配置或防护状态证据：待确认。
- 其他问题继续按影响进入 P2/P3。
- standard、deep、security 模式不得静默丢弃未通过 P0 门槛的候选；fast 按纯 P0 模式边界只输出 P0。

## 依赖风险结论规则

依赖风险只有在 lockfile 版本明确且证据可靠时才能形成确定性漏洞结论；否则必须归为待确认或依赖扫描建议，不得仅凭"版本较旧"的印象下漏洞结论。

---

*本手册版本：前端 2.0（11 维度独立集）*
*最后更新：2026-06-27*
```

- [ ] **Step 2: 验证维度数和反注水断言可满足**

Run: `grep -cE '^### [0-9]+\. ' references/languages/frontend/review-framework.md`
Expected: `11`

Run: `grep -E 'D(0[1-9]|1[0-5])_[A-Z_]+' references/languages/frontend/review-framework.md`
Expected: 无输出（不含 Java 公共 ID）。

Run: `grep "类型安全" references/languages/frontend/review-framework.md`
Expected: 命中多行。

- [ ] **Step 3: 暂不提交，与 Task 2/4-7 合并**

---

### Task 4: 重写 react-rules.md（按新维度名）

**Files:**
- Modify: `references/languages/frontend/react-rules.md`（整体重写）

**Interfaces:**
- Consumes: Task 3 的 11 维度名
- Produces: 按新维度名组织的规则细则，不再用 D01/D03 编号

- [ ] **Step 1: 重写 `references/languages/frontend/react-rules.md`**

将整个文件替换为以下内容：

```markdown
# React 审查规则细则

本文件按前端审查框架（`review-framework.md`）的 11 维度组织具体规则。维度名与框架一致，不使用 Java 公共维度编号。规则与模式 × 维度矩阵配合使用；组件/路径示例仅作说明，正式结论必须基于实际代码证据。

---

## 正确性

- **Hooks 依赖数组**：useEffect/useMemo/useCallback 依赖遗漏（陈旧闭包）或多余（无谓重执行）。
  - 证据示例：`useEffect(() => { fetch(id) }, [])` 而 `id` 来自 props（遗漏依赖 → 陈旧数据）。
- **异步竞态**：effect 中发起的请求未取消，快速切换时旧响应覆盖新响应。
- **类型逃逸边界**：`as any`、非空断言 `!` 绕过类型检查，运行时仍可能 undefined。
- **空值边界**：可选链 `?.` 缺失导致 `Cannot read property of undefined`。

## 类型安全

- **any 污染**：any 逃逸到组件 props、函数返回值、状态，沿调用链扩散。
  - 证据示例：`function useData(): any` 返回 any，消费方无类型保护。
- **断言滥用**：`as any`、`as unknown as T`、非空断言 `!` 用于掩盖类型错误而非合法窄化。
- **类型逃逸**：`@ts-ignore`/`@ts-expect-error` 未注释原因；三方库无类型直接 `declare module` 成 any。
- **泛型边界**：泛型约束缺失（`<T>` 无 `extends`），或 any 透传使类型保护形同虚设。
- **三方库类型**：缺失 `.d.ts`、import 无类型模块未声明。
- **可空/联合类型**：未窄化、null 与 undefined 未区分处理。

## 代码质量

- **单一职责**：组件/函数承担过多职责。
- **DRY**：中后台常见表格/表单模板重复，应抽取。
- **复杂度**：函数/组件过长或嵌套过深。
- **命名**：组件、props、hooks 命名不清晰。
- **公共组件滥用**：pro-components 被到处乱用、通用组件被单一场景污染 props。
- **循环依赖/跨层引用**：组件/hooks 循环引用；UI 组件直接依赖数据层。

## React 规范

- **Hooks 规则**：不在条件/循环/嵌套函数中调用 Hooks（违反 Hooks 调用顺序）。
- **useEffect 清理**：订阅、timer、listener、请求必须在 cleanup 返回函数中清理。
  - 证据示例：`useEffect(() => { window.addEventListener('resize', handler) }, [])` 无 cleanup → 内存泄漏。
- **不必要重渲染**：缺失 React.memo、内联对象/函数作为 props（每次渲染新引用）。
- **key 使用**：列表用数组 index 作 key，在增删/排序时导致状态错位。

## 状态与数据请求

- **状态归属**：局部 state vs 提升 vs 全局 store 的选择是否合理（过度提升或过度局部化）。
- **loading/error 状态**：数据请求是否处理 pending/error，是否有用户可感知的加载/错误态。
- **缓存失效**：SWR/React Query 的 cache key 与 mutate 时机。
- **乐观更新**：失败回滚与最终一致性。

## 安全

- **XSS**：`dangerouslySetInnerHTML` 渲染用户可控内容；用户输入未经转义直接注入 DOM。
  - 证据示例：`<div dangerouslySetInnerHTML={{ __html: userInput }} />`。
- **前端凭据**：token/密钥写入 localStorage、sessionStorage 或硬编码在公共 bundle 中。
- **开放重定向**：用户可控 `window.location` / `<a href>` 跳转，未做白名单校验。
- **BFF 鉴权透传**：接口请求是否携带鉴权、401/403 是否正确处理而非静默失败。
- **不安全 URL 拼接**：用户可控 URL 直接作为请求目标（SSRF 向量经前端透传到 BFF）。

## 性能（中后台聚焦）

- **大表虚拟化**：长列表/大表格未用 react-window/virtual，一次性渲染上千 DOM 节点。
- **接口串行/瀑布**：可并行的请求串行、未用 Promise.all。
- **重复请求**：相同数据重复请求、未做请求缓存。
- **不必要重渲染**：缺失 memo/useMemo、context 值未缓存导致全树重渲染。
- **节流防抖缺失**：scroll/resize/input 搜索等高频事件未 throttle/debounce。
- **Bundle**：整包引入（`import _ from 'lodash'`）、懒加载缺失导致首屏过大。

## 副作用与资源清理

- **Event listener**：`addEventListener` 未在 unmount 时 `removeEventListener`。
- **timer**：`setInterval`/`setTimeout` 未清理 → 卸载后仍执行 setState（告警 + 内存泄漏）。
- **订阅**：Observable/EventEmitter/Redux store.subscribe 未取消订阅。
- **请求取消**：未用 AbortController，卸载后请求完成触发 setState。

## 错误监控与可观测性

- **Error Boundary**：关键路由/顶层组件是否被 Error Boundary 包裹，避免白屏。
- **关键错误上报**：可恢复错误的捕获与上报链路是否完整。
- **敏感信息**：上报内容/错误日志是否泄露 token、PII、堆栈中的内部路径。

## 测试质量

- **standard** 仅检查：核心逻辑是否有对应测试、关键路径（鉴权/异步/错误边界）测试缺失。
- **deep** 存量审查：测试覆盖、核心逻辑、关键路径、Mock 使用、边界测试。

## 接口与类型契约

- **RESTful 规范**：URL 设计、HTTP 方法语义。
- **错误处理**：错误响应结构与状态码。
- **分页规范**：中后台高频，分页参数与响应结构一致性。
- **类型契约一致性**（deep）：前后端类型对齐、响应类型与实际不符。

---

## 依赖风险结论规则

- **只有当 lockfile 版本明确且证据可靠时**（如 lockfile 锁定版本 + 公开漏洞编号/公告），才能下"存在漏洞风险"的确定性结论。
- 如果只有"版本较旧"或"框架较老"的印象，没有明确依据，只能写为"升级建议"或"建议补充依赖扫描"。
- 不得仅凭依赖名推测漏洞。
```

- [ ] **Step 2: 暂不提交，与 Task 2/3/5-7 合并**

---

### Task 5: 删除 shared-review-framework.md

**Files:**
- Delete: `references/shared-review-framework.md`

**Interfaces:**
- Consumes: 无
- Produces: 文件删除，满足 Task 1 的"必须已删除"断言

- [ ] **Step 1: 删除文件**

Run: `git rm references/shared-review-framework.md`
Expected: 输出 `rm 'references/shared-review-framework.md'`。

- [ ] **Step 2: 暂不提交，与 Task 2-4/6-7 合并**

---

### Task 6: 同步 Java 路径引用（SKILL.md + Java agent + 文档）

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md:348`
- Modify: `skills/cc-code-reviewer/SKILL.md:1001`
- Modify: `agents/cc-code-reviewer.md:105`
- Modify: `README.md:119`
- Modify: `AGENTS.md:117,199,202`
- Modify: `CLAUDE.md:117,199,202`

**Interfaces:**
- Consumes: Task 2 的 Java 框架新路径
- Produces: 所有 Java 框架路径引用同步到 `references/languages/java/review-framework.md`

- [ ] **Step 1: 改 SKILL.md:348 的 REVIEW_FRAMEWORK_PATH**

将 `skills/cc-code-reviewer/SKILL.md:348`：

```bash
REVIEW_FRAMEWORK_PATH="${CLAUDE_PLUGIN_ROOT}/references/review-framework.md"
```

改为：

```bash
REVIEW_FRAMEWORK_PATH="${CLAUDE_PLUGIN_ROOT}/references/languages/java/review-framework.md"
```

- [ ] **Step 2: 改 SKILL.md:1001 参数表示例值**

将 `skills/cc-code-reviewer/SKILL.md:1001` 行：

```
| `REVIEW_FRAMEWORK_PATH` | `${CLAUDE_PLUGIN_ROOT}/references/review-framework.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/review-framework.md` |
```

改为：

```
| `REVIEW_FRAMEWORK_PATH` | `${CLAUDE_PLUGIN_ROOT}/references/languages/java/review-framework.md`，启动子 agent 前必须校验可读 | `/path/to/plugin/references/languages/java/review-framework.md` |
```

- [ ] **Step 3: 改 agents/cc-code-reviewer.md:105 回退路径**

将 `agents/cc-code-reviewer.md:105`：

```
- 只有在主 agent 未注入这些字段的历史兼容场景，才允许回退读取当前 agent 文件相邻的 `../references/review-framework.md` 和 `../references/report-format.md`。
```

改为：

```
- 只有在主 agent 未注入这些字段的历史兼容场景，才允许回退读取当前 agent 文件相邻的 `../references/languages/java/review-framework.md` 和 `../references/report-format.md`。
```

- [ ] **Step 4: 改 README.md:119**

将 `README.md:119`：

```
| [审查维度与模式矩阵](references/review-framework.md) | 15 维度定义、技术栈匹配规则、模式 × 维度启用矩阵 |
```

改为：

```
| [审查维度与模式矩阵](references/languages/java/review-framework.md) | 15 维度定义、技术栈匹配规则、模式 × 维度启用矩阵 |
```

- [ ] **Step 5: 改 AGENTS.md（3 处）**

将 `AGENTS.md:117`：

```
  ├── review-framework.md             # 15 dimensions definition + mode matrix
```

改为：

```
  ├── languages/
  │   ├── java/
  │   │   └── review-framework.md     # 15 dimensions definition + mode matrix
  │   └── frontend/
  │       └── review-framework.md     # frontend 11 dimensions
```

将 `AGENTS.md:199`：

```
3. **Review dimensions**: Edit `references/review-framework.md`
```

改为：

```
3. **Review dimensions**: Edit `references/languages/java/review-framework.md`
```

将 `AGENTS.md:202`：

```
**Critical**: Keep mode × dimension matrix consistent between `review-framework.md` and `cc-code-reviewer.md`.
```

改为：

```
**Critical**: Keep mode × dimension matrix consistent between `references/languages/java/review-framework.md` and `cc-code-reviewer.md`.
```

- [ ] **Step 6: 改 CLAUDE.md（与 AGENTS.md 同样 3 处）**

对 `CLAUDE.md` 的 `:117`、`:199`、`:202` 做与 Step 5 完全相同的替换。

- [ ] **Step 7: 暂不提交，与 Task 2-5/7 合并为单次自洽提交**

---

### Task 7: 合并提交所有文档改动（保证自洽）

**Files:**
- 无新文件，合并 Task 2-6 的改动

**Interfaces:**
- Consumes: Task 2-6 的所有未提交改动
- Produces: 单次自洽 commit，Java 路径搬迁 + 文档同步 + 前端重写 + shared 删除同时完成

- [ ] **Step 1: 检查暂存区状态**

Run: `git status`
Expected: 看到 Task 2-6 的改动（review-framework.md 移动、shared 删除、前端两个文件修改、SKILL/agent/README/AGENTS/CLAUDE 修改）。

- [ ] **Step 2: 一次性提交所有文档改动**

```bash
git add -A
git commit -m "refactor(review): decouple frontend framework to 11 B-end dimensions, move Java to languages/java/, drop shared dimension table

- Rewrite frontend/review-framework.md: 11 independent dimensions (no D01-D15 mapping),
  B-end mid/back-office focused, new 'type safety' dimension (P0-level)
- Rewrite frontend/react-rules.md: reorganize by new dimension names
- git mv Java review-framework.md -> languages/java/ (content unchanged, 15 dims)
- Delete shared-review-framework.md (zero code consumers, over-design)
- Sync Java framework path in SKILL.md, agents/cc-code-reviewer.md, README/AGENTS/CLAUDE
- Contract tests: hard-assert 11 frontend dims, ban D01-D15 literals, assert shared deleted"
```

---

### Task 8: 全量验证

**Files:**
- 无

**Interfaces:**
- Consumes: Task 1-7 全部完成
- Produces: 绿色测试套件

- [ ] **Step 1: 运行契约测试**

Run: `bash tests/test_contract_docs.sh`
Expected: 退出码 0，无 FAIL 输出。

如有失败，根据失败信息定位：通常是漏改某处路径引用。用 `grep -rn "references/review-framework" .` 排查残留旧路径（排除 `.superpowers/` 和 `docs/superpowers/` 历史归档）。

- [ ] **Step 2: 运行完整测试套件**

Run: `bash tests/run_all.sh`
Expected: 全绿。

- [ ] **Step 3: 确认无残留旧路径引用（排除历史归档）**

Run: `grep -rn "references/review-framework\.md" --include="*.md" --include="*.sh" . | grep -v ".superpowers/" | grep -v "docs/superpowers/"`
Expected: 无输出（所有运行时引用已迁移到 `languages/java/` 路径）。

- [ ] **Step 4: 确认 shared 文件已删除**

Run: `test ! -f references/shared-review-framework.md && echo "OK: deleted"`
Expected: `OK: deleted`

- [ ] **Step 5: 确认目录结构对称**

Run: `ls references/languages/java/review-framework.md references/languages/frontend/review-framework.md`
Expected: 两个文件都存在。

---

## Self-Review

**1. Spec 覆盖检查：**

| Spec 要求 | 对应 Task |
|---|---|
| §5.1 Java 搬 languages/java/ | Task 2 |
| §5.1 前端重写 11 维度 | Task 3 |
| §5.1 react-rules 重写 | Task 4 |
| §5.1 删除 shared | Task 5 |
| §8.1 SKILL.md 路径 | Task 6 Step 1-2 |
| §8.1 agent 路径 | Task 6 Step 3 |
| §8.1 README/AGENTS/CLAUDE | Task 6 Step 4-6 |
| §8.2 反注水测试断言 | Task 1 |
| §8.3 不改脚本/report-format/ignore | Global Constraints + 未列入任何 Task |
| §9.3 验收 run_all.sh 全绿 | Task 8 |

无遗漏。

**2. 占位符扫描：** 无 TBD/TODO，所有代码块完整。✅

**3. 类型一致性：** 路径字符串 `references/languages/java/review-framework.md` 在 Task 1（断言）、Task 6（引用）、Task 8（验证）中一致。前端维度名在 Task 3（框架）、Task 4（规则）中一致。✅
