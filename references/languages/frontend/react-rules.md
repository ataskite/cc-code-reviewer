# React MVP 审查规则

本文件落地 spec 第 9 节的 React MVP 审查重点，按维度组织。规则与 `review-framework.md` 的维度编号对应；维度是否启用由模式 × 维度矩阵决定。组件/路径示例仅作说明，正式结论必须基于实际代码证据。

---

## D01 正确性

- **Hooks 依赖数组**：useEffect/useMemo/useCallback 依赖遗漏（陈旧闭包）或多余（无谓重执行）。
  - 证据示例：`useEffect(() => { fetch(id) }, [])` 而 `id` 来自 props（遗漏依赖 → 陈旧数据）。
- **异步竞态**：effect 中发起的请求未取消，快速切换时旧响应覆盖新响应。
- **类型逃逸**：`as any`、非空断言 `!.` 绕过类型检查，运行时仍可能 undefined。
- **空值边界**：可选链 `?.` 缺失导致 `Cannot read property of undefined`。

## D03 React Hooks/渲染/组件规范

- **Hooks 规则**：不在条件/循环/嵌套函数中调用 Hooks（违反 Hooks 调用顺序）。
- **useEffect 清理**：订阅、timer、listener、请求必须在 cleanup 返回函数中清理。
  - 证据示例：`useEffect(() => { window.addEventListener('resize', handler) }, [])` 无 cleanup → 内存泄漏。
- **不必要重渲染**：缺失 React.memo、内联对象/函数作为 props（每次渲染新引用）。
- **key 使用**：列表用数组 index 作 key，在增删/排序时导致状态错位。

## D04 状态管理与数据请求

- **状态归属**：局部 state vs 提升 vs 全局 store 的选择是否合理（过度提升或过度局部化）。
- **loading/error 状态**：数据请求是否处理 pending/error，是否有用户可感知的加载/错误态。
- **缓存失效**：SWR/React Query 的 cache key 与 mutate 时机。
- **乐观更新**：失败回滚与最终一致性。

## D05 安全

- **XSS**：`dangerouslySetInnerHTML` 渲染用户可控内容；用户输入未经转义直接注入 DOM。
  - 证据示例：`<div dangerouslySetInnerHTML={{ __html: userInput }} />`。
- **前端凭据**：token/密钥写入 localStorage、sessionStorage 或硬编码在公共 bundle 中。
- **开放重定向**：用户可控 `window.location` / `<a href>` 跳转，未做白名单校验。
- **不安全 URL 拼接**：用户可控 URL 直接作为请求目标（SSRF 向量经前端透传到 BFF）。

## D06 性能

- **Bundle 体积**：整包引入（`import _ from 'lodash'`）、懒加载缺失导致首屏过大。
- **列表渲染**：大列表未虚拟化（react-window/virtual），一次性渲染上千 DOM 节点。
- **重计算**：循环内重计算未用 useMemo；或对稳定值滥用 useMemo 反增开销。
- **阻塞渲染**：同步大计算未用 Web Worker 或时间切片。

## D07 副作用与资源清理

- **Event listener**：`addEventListener` 未在 unmount 时 `removeEventListener`。
- **timer**：`setInterval`/`setTimeout` 未清理 → 卸载后仍执行 setState（告警 + 内存泄漏）。
- **订阅**：Observable/EventEmitter/Redux store.subscribe 未取消订阅。
- **请求取消**：未用 AbortController，卸载后请求完成触发 setState。

## D08 错误监控与可观测性

- **Error Boundary**：关键路由/顶层组件是否被 Error Boundary 包裹，避免白屏。
- **关键错误上报**：可恢复错误的捕获与上报链路是否完整。
- **敏感信息**：上报内容/错误日志是否泄露 token、PII、堆栈中的内部路径。

## D11 组件边界与架构

- **循环依赖**：组件/hooks 之间循环引用。
- **跨层引用**：UI 组件直接依赖数据层、绕过分层。
- **公共组件滥用**：为单一场景污染通用组件 props。

## 可访问性（并入相关维度）

- 表单是否有 `<label>` 关联、键盘可达性、语义化结构（`<button>` 而非 `<div onClick>`）、ARIA 正确使用。主要归入 D02/D11，安全相关归入 D05。

---

## 依赖风险结论规则

- **只有当 lockfile 版本明确且证据可靠时**（如 lockfile 锁定版本 + 公开漏洞编号/公告），才能下"存在漏洞风险"的确定性结论。
- 如果只有"版本较旧"或"框架较老"的印象，没有明确依据，只能写为"升级建议"或"建议补充依赖扫描"。
- 不得仅凭依赖名推测漏洞。
