# 前端代码审查框架

本手册定义前端族群（React、Vue 2、Vue 3、Node.js、TypeScript/JavaScript，B 端中后台聚焦）代码审查的 12 个维度。维度与 Java 的 15 维度结构完全独立，不编号、不映射。各模式的启用范围以"审查模式 × 维度覆盖矩阵"为准。

> 维度 12「设计系统一致性」为 deep 专项，其余 11 维度为标准审查面。维度 1-11 的覆盖范围在所有模式下保持稳定；维度 12 只在 deep 模式启用，避免对日常迭代引入额外噪音。

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
| 12 设计系统一致性 | — | — | ✅ | — |

---

## 模式说明

- **fast**（快速扫雷）：仅扫描会直接炸产线或造成明显安全/稳定性风险的问题，聚焦正确性、类型安全（any 逃逸+断言滥用）、React Hooks / Vue 响应式与生命周期 / Node 配置安全、副作用与资源清理、P0 级安全问题（XSS/危险 HTML/凭据/开放重定向）。适合 PR 合并前快速卡口。覆盖维度：1、2（部分）、4（部分）、6（P0）、8。
- **standard**（标准审查）：日常迭代推荐模式，覆盖维度 1-11，但 10 只查核心测试缺失、11 只查 RESTful+错误处理+分页。适合迭代上线前的常规质量门禁。（10/11 部分启用；维度 12 设计系统一致性不启用。）
- **deep**（深度审查）：全量 12 维度，含测试质量、技术债深挖和设计系统一致性。适合大版本上线前或重要模块的系统性审查，耗时较长。覆盖维度：1-12 全开。
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
- **断言滥用**：as any、as unknown as、非空断言 ! 滥用；`satisfies` 能解决的不应用 `as`
- **类型逃逸**：@ts-ignore / @ts-expect-error 无注释、三方库无类型直接 any 化
- **泛型边界**：泛型约束缺失、any 透传导致类型保护形同虚设
- **三方库类型**：缺失 .d.ts、import 无类型模块未声明
- **可空/联合类型**：未窄化、null/undefined 未区分处理
- **联合类型穷尽性**：switch over union/enum 未用 `never` default 做穷尽检查，漏分支无编译保护
- **branded/opaque 类型**：业务 ID（如 UserId/OrderId/TenantId）混用未用 branded 类型隔离，ID 串用导致真 bug
- **索引访问安全**：未启用 `noUncheckedIndexedAccess` 时，`arr[i]`/`obj[key]` 的 undefined 风险被静默吞掉
- **契约对齐**：公共 API/导出函数缺类型导出；前后端类型手动维护而非 OpenAPI/GraphQL codegen，易漂移

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
- **XSS**：`dangerouslySetInnerHTML`、Vue `v-html`、用户输入直接渲染；**间接 sink 同样需查**：`el.innerHTML =`（含 ref 操作）、第三方富文本组件（Quill/TinyMCE setContent）、模板字符串/`format()` 拼 HTML 字符串——不得只盯 `dangerouslySetInnerHTML`/`v-html` 两个 API 名
- **前端凭据**：token 写 localStorage、公共代码硬编码
- **客户端打包泄露**：任何会被打进浏览器包的客户端可见变量都可能泄露——典型是 `NEXT_PUBLIC_*`/`VITE_*`/`REACT_APP_*` 前缀 env，但也包括自定义 define 插件注入、`webpack.DefinePlugin`、无列举前缀的变量（如 `GATEWAY_KEY`/`DB_DSN`）误注入客户端 bundle；BFF token、第三方 API key、服务端 secret 误入即等于公开；source map 上线到 CDN 也会泄露原始代码。**不得仅凭"无列举前缀"判定安全**
- **开放重定向**：用户可控 URL 跳转
- **权限前置误判**：按钮隐藏、菜单过滤、路由 meta 只属于前端展示控制，不得当作后端授权证据
- **BFF/Node 鉴权透传**：接口鉴权、token 透传、401/403 处理、租户隔离
- **不安全 URL 拼接**：SSRF 向量（前端→BFF/Node）、开放重定向
- **内容安全策略**：CSP 是否部署（`script-src 'self'` + nonce/hash，禁用 `unsafe-inline`/`unsafe-eval`）；跨域脚本是否有 SRI `integrity`；Trusted Types 策略
- **供应链（OWASP 2025 A03）**：lockfile 是否提交并用 `npm ci` 校验；`postinstall` 脚本来源；高危依赖的 provenance/Sigstore 签名；typosquatting 依赖
- **依赖风险**：lockfile 版本漏洞结论规则见下

### 7. 性能（中后台聚焦）
- **大表虚拟化**：长列表/大表格未虚拟化（react-window/virtual）
- **接口串行/瀑布**：可并行的请求串行、未用 Promise.all
- **重复请求**：相同数据重复请求、未做请求缓存
- **不必要重渲染**：缺失 memo/useMemo、context 值未缓存、Vue 深层 watcher 或响应式大对象造成重复渲染
- **React Compiler 感知**：启用 React Compiler（自动 memoize）后，手写 `useMemo`/`useCallback` 多数冗余，应作为冗余代码标记；未启用时反过来看手写 memoize 是否对廉价计算过度优化（开销大于收益）
- **Vue 响应式成本**：大对象用 `reactive()`/`ref()` 全深响应，应改 `shallowRef`/`shallowReactive`；`computed` 含副作用；`watch`/`watchEffect` 未返回 cleanup；`KeepAlive` 缺 `max` 导致缓存膨胀
- **Node 稳定性**：同步阻塞 CPU 操作、无界并发、连接池耗尽、缺少超时/背压
- **节流防抖缺失**：高频事件（scroll/resize/input 搜索）未做 throttle/debounce
- **Bundle**：懒加载缺失、整包引入、首包体积超预算无门禁

### 8. 副作用与资源清理
- **Event listener**：addEventListener 未配对 removeEventListener；Vue mounted/onMounted 注册后未在 beforeDestroy/onUnmounted 清理
- **keep-alive**：Vue `activated` / `deactivated` 下的数据刷新、权限重校验和订阅清理
- **timer**：setInterval/setTimeout 未清理
- **订阅**：Observable/EventEmitter/事件总线未取消；Vue2 event bus 是 legacy 重点
- **请求取消**：AbortController 未使用导致 unmount 后 setState / watcher 旧响应覆盖新响应
- **Node 资源释放**：数据库连接、stream、队列消费者、HTTP client 未超时或未关闭

### 9. 错误处理、韧性与可观测性
- **错误边界**：React Error Boundary、Vue `errorCaptured`/全局 error handler、Node 统一错误处理中间件；风险子树/路由级是否包裹
- **异步错误**：effect/handler 中的异步错误是否 try/catch；未处理 promise rejection 是否有全局兜底并接观测性
- **三态完整性**：异步 UI 的 loading/error/empty 三态是否齐全（中后台表格最常缺 empty 和 error 态，只画了 loading）
- **网络失败 UX**：失败是否提供重试、乐观更新回滚、SWR/Query 的 stale-data fallback；表单提交是否区分 field-level 和 form-level 错误
- **观测性**：关键错误是否上报到 Sentry 等平台且 source map 已上传；全局错误是否泄露 token/PII；**间接泄露**：含敏感字段（token/PII/表单值）的对象进入 `console.log`/`console.error`（生产构建未剥离）、错误上报把整个 error/state 对象塞进 Sentry `extra`/`contexts`、埋点 payload 携带含 token 的 URL query 或整页 state——不得只查显式打印 token 的语句，任何日志/上报/埋点边界消费含敏感字段的对象都算（与 Java 5.3、Python 维度 10 的间接泄露检查点对齐）

### 10. 测试质量
- **standard** 仅检查：核心逻辑是否有对应测试、关键路径（鉴权/异步/错误边界）测试是否缺失
- **deep** 存量审查：测试覆盖、核心逻辑、关键路径、Mock 使用、边界测试

### 11. 接口与类型契约
- **standard** 仅检查：RESTful 规范、错误处理、分页规范（中后台高频）、Node 路由入参契约
- **deep** 存量审查：RESTful、版本管理、错误处理、幂等、分页、接口文档、类型契约一致性（前后端类型对齐、响应类型与实际不符）

### 12. 设计系统一致性（仅 deep）
> 本维度只在 deep 模式启用。standard/fast/security 不启用，避免对日常迭代引入与业务正确性无关的噪音。聚焦中后台共享设计系统（Element / Ant Design / 自研 token 体系）的遵循度，属于技术债与一致性审查，问题统一归 P2/P3。

- **token 使用**：颜色、间距、圆角、字号是否走设计 token；硬编码 `#fff`/`12px`/`1px solid #ccc` 散落（应改 CSS variable / theme token）
- **组件库复用**：是否从共享组件库取组件，而非就地重复实现一个简版 Modal/Drawer/Select；本地 props 是否与库的 API 漂移
- **主题与暗色模式**：暗色模式是否走 token 体系（而非临时 `dark:` 一堆类）；主题切换是否真覆盖到所有自定义样式
- **间距与栅格**：间距是否落在设计系统栅格（通常 4px/8px 刻度），错位/魔数间距
- **图标来源统一**：是否混用多套图标库，而非用约定的单一图标集

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

*本手册版本：前端 2.5（React + Vue2/Vue3 + Node，12 维度独立集；维度 12 仅 deep 启用）*
*最后更新：2026-08-15*
