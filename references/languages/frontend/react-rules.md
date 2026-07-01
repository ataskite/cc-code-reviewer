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
