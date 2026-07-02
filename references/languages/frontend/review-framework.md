# 前端代码审查框架

本手册定义前端族群（React、Vue 2、Vue 3、Node.js、TypeScript/JavaScript，B 端中后台聚焦）代码审查的 11 个维度。维度与 Java 的 15 维度结构完全独立，不编号、不映射。各模式的启用范围以"审查模式 × 维度覆盖矩阵"为准。

> 审查框架各语言独立。Java 框架见 `references/languages/java/review-framework.md`；本文件不引用任何 Java 公共维度编号。

---

## 审查模式 × 维度覆盖矩阵

| 维度 | fast | standard | deep | security |
|---|:---:|:---:|:---:|:---:|
| 1 正确性 | ✅ | ✅ | ✅ | ✅ |
| 2 类型安全 | ✅ 仅 any 逃逸+断言滥用 | ✅ | ✅ | — |
| 3 代码质量 | — | ✅ | ✅ | — |
| 4 框架规范 | ✅ 仅 React Hooks / Vue 响应式与生命周期 / Node 配置安全 | ✅ | ✅ | ✅ 仅配置安全子项 |
| 5 状态与数据请求 | — | ✅ | ✅ | ✅ 仅注入/越权子项 |
| 6 安全 | ✅ 仅 P0 级 | ✅ | ✅ | ✅ 全深度 |
| 7 性能 | — | ✅ | ✅ | — |
| 8 副作用与资源清理 | ✅ | ✅ | ✅ | — |
| 9 错误监控与可观测性 | — | ✅ | ✅ | ✅ 仅敏感信息泄露 |
| 10 测试质量 | — | ✅ 仅核心测试缺失 | ✅ | — |
| 11 接口与类型契约 | — | ✅ 仅 RESTful+错误处理 | ✅ | ✅ 仅鉴权/错误信息 |

---

## 模式说明

- **fast**（快速扫雷）：仅扫描会直接炸产线或造成明显安全/稳定性风险的问题，聚焦正确性、类型安全（any 逃逸+断言滥用）、React Hooks / Vue 响应式与生命周期 / Node 配置安全、副作用与资源清理、P0 级安全问题（XSS/危险 HTML/凭据/开放重定向）。适合 PR 合并前快速卡口。覆盖维度：1、2（部分）、4（部分）、6（P0）、8。
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

### 4. 框架规范
- **React**：Hooks 调用顺序、effect 依赖、memo/key、错误边界和配置安全
- **Vue 2**：Options API、响应式限制、watcher、生命周期清理、Vuex 3、Vue Router 3、class component/decorator、`.sync`、keep-alive；Vue2 legacy 项目必须优先检查响应式失效、守卫 `next`、事件总线、`$set`/数组变更、`$children/$parent` 与 `$refs/$nextTick` 时序风险
- **Vue 3**：Composition API、`<script setup>`、`ref`/`reactive` 解构、watch cleanup、Pinia、Vue Router 4、provide/inject、Suspense/Teleport、fallthrough attrs、template refs
- **Node.js**：`package.json` 的 `type`/`main`/`exports`/`engines.node`、启动脚本、HTTP 框架中间件顺序和运行时配置安全

### 5. 状态与数据请求
- **状态归属**：React 局部/全局状态、Vuex/Pinia、Node 请求上下文与缓存状态的选择是否合理
- **B 端组件状态**：Element UI / ant-design-vue 表单、表格 selection、弹窗/抽屉、页签缓存和权限按钮状态是否与真实业务状态一致
- **数据请求**：loading/error 状态处理、请求取消、竞态
- **缓存失效**：SWR/React Query、Vue Query、Pinia/Vuex 缓存、Node 服务端缓存的 key 与失效策略
- **乐观更新**：回滚与一致性

### 6. 安全
- **XSS**：dangerouslySetInnerHTML、Vue `v-html`、用户输入直接渲染
- **前端凭据**：token 写 localStorage、公共代码硬编码
- **开放重定向**：用户可控 URL 跳转
- **权限前置误判**：按钮隐藏、菜单过滤、路由 meta 只属于前端展示控制，不得当作后端授权证据
- **BFF/Node 鉴权透传**：接口鉴权、token 透传、401/403 处理、租户隔离
- **不安全 URL 拼接**：SSRF 向量（前端→BFF/Node）、开放重定向
- **依赖风险**：lockfile 版本漏洞结论规则见下

### 7. 性能（中后台聚焦）
- **大表虚拟化**：长列表/大表格未虚拟化（react-window/virtual）
- **接口串行/瀑布**：可并行的请求串行、未用 Promise.all
- **重复请求**：相同数据重复请求、未做请求缓存
- **不必要重渲染**：缺失 memo/useMemo、context 值未缓存、Vue 深层 watcher 或响应式大对象造成重复渲染
- **Node 稳定性**：同步阻塞 CPU 操作、无界并发、连接池耗尽、缺少超时/背压
- **节流防抖缺失**：高频事件（scroll/resize/input 搜索）未做 throttle/debounce
- **Bundle**：懒加载缺失、整包引入

### 8. 副作用与资源清理
- **Event listener**：addEventListener 未配对 removeEventListener；Vue mounted/onMounted 注册后未在 beforeDestroy/onUnmounted 清理
- **keep-alive**：Vue `activated` / `deactivated` 下的数据刷新、权限重校验和订阅清理
- **timer**：setInterval/setTimeout 未清理
- **订阅**：Observable/EventEmitter/事件总线未取消；Vue2 event bus 是 legacy 重点
- **请求取消**：AbortController 未使用导致 unmount 后 setState / watcher 旧响应覆盖新响应
- **Node 资源释放**：数据库连接、stream、队列消费者、HTTP client 未超时或未关闭

### 9. 错误监控与可观测性
- **错误边界**：React Error Boundary、Vue `errorCaptured`/全局 error handler、Node 统一错误处理中间件
- **关键错误上报**：用户可恢复错误的捕获与上报
- **敏感信息**：错误日志中是否泄露 token/PII

### 10. 测试质量
- **standard** 仅检查：核心逻辑是否有对应测试、关键路径（鉴权/异步/错误边界）测试是否缺失
- **deep** 存量审查：测试覆盖、核心逻辑、关键路径、Mock 使用、边界测试

### 11. 接口与类型契约
- **standard** 仅检查：RESTful 规范、错误处理、分页规范（中后台高频）、Node 路由入参契约
- **deep** 存量审查：RESTful、版本管理、错误处理、幂等、分页、接口文档、类型契约一致性（前后端类型对齐、响应类型与实际不符）

---

## P0 分级门槛

**P0 五项硬门槛**（与 Java 一致，必须全部满足）：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。五项必须同时满足；任一不满足都不得标为 P0。

- 证据成立但影响未达到事故级或已有有效缓解机制：P1。
- 事故级风险尚缺生产可达性、调用链、运行配置或防护状态证据：待确认。
- 其他问题继续按影响进入 P2/P3。
- standard、deep、security 模式不得静默丢弃未通过 P0 门槛的候选；fast 按纯 P0 模式边界只输出 P0。

### 性能问题分级边界

- 已证实会造成系统性不可用、生产关键路径可达、缺少超时/限流/隔离/降级并必须阻断发布的性能事故级问题：P0。
- 关键路径性能风险且已证实会显著影响稳定性：P1。示例：Node 关键接口同步阻塞 CPU、无界并发、连接池耗尽、缺少超时/背压，或前端关键页面副作用未清理导致明显内存泄漏。
- 普通性能问题或局部性能风险：P2。示例：大表未虚拟化、可并行请求串行、重复请求、未做请求缓存、Vue 深层 watcher 或响应式大对象造成重复渲染、Bundle 懒加载缺失或整包引入。
- 泛优化建议且缺少明确风险链路：P3。示例：建议懒加载、建议拆包、建议补充性能监控、建议优化渲染但没有明确生产影响证据。
- 怀疑很严重但缺少生产路径、调用频率、运行配置、表结构、索引或执行计划证据：待确认。不得仅凭“可能慢”“可能重复渲染很多”“可能打爆资源”的印象升级到 P1/P0。

## 依赖风险结论规则

依赖风险只有在 lockfile 版本明确且证据可靠时才能形成确定性漏洞结论；否则必须归为待确认或依赖扫描建议，不得仅凭"版本较旧"的印象下漏洞结论。

---

*本手册版本：前端 2.2（React + Vue2/Vue3 + Node，11 维度独立集）*
*最后更新：2026-07-02*
