# Vue 审查规则细则

本文件按前端审查框架的 11 个独立维度组织 Vue 专项规则。Vue 2 是 legacy 重点支持对象；Vue 3 按 Composition API、`<script setup>`、Pinia 等现代栈补充专项检查。

## Vue 2 legacy 重点

- **Options API 数据边界**：`data` 必须返回新对象；`props` 默认值为对象/数组时必须用工厂函数；`computed` 不应产生副作用。
- **响应式限制**：Vue 2 对新增对象属性、数组索引赋值、直接改 `length` 的响应式限制必须用 `Vue.set` / `$set` / 不可变替换规避。
- **Watcher 风险**：深度 watcher、立即执行 watcher 和异步 watcher 必须检查竞态、重复请求、未取消订阅和性能放大。
- **生命周期清理**：`created`/`mounted` 注册的 timer、DOM listener、事件总线、WebSocket、订阅必须在 `beforeDestroy`/`destroyed` 中清理。
- **Vuex 3 状态流**：mutation/action 边界清晰，避免组件绕过 mutation 直接改 store；异步 action 要有错误处理和并发保护。
- **Vue Router 3**：导航守卫不得遗漏 `next` 或重复调用 `next`；权限守卫和重定向必须避免开放跳转。
- **模板安全**：`v-html` 只允许渲染可信或已净化内容；动态组件、动态 class/style、URL 绑定需检查注入与开放跳转。
- **mixin 全局污染**：全局 `Vue.mixin()` 注入的选项会与所有组件合并，必须检查 data/methods/computed 命名冲突、与业务组件选项的意外覆盖、以及全局 mixin 滥用导致的来源不可追溯。
- **filter 废弃迁移债**：Vue 3 已移除 `filter`，Vue 2 项目中重度使用 `filters`（尤其管道串联、全局 filter）是升级阻塞点与技术债信号，应标记为可计划重构项。
- **vue-class-component / vue-property-decorator**：类组件写法需要检查装饰器元数据、`@Prop` 默认值工厂、`@Watch` 深度监听、继承链隐式副作用，以及与 Options API / Composition API 混写导致的生命周期顺序不清。
- **@vue/composition-api**：Vue2 composition plugin 下要重点检查插件是否全局安装、`setup()` 与 Options API 的 this 边界、ref/reactive 解构、watch cleanup，以及与 Vue2 响应式限制叠加后的状态失效。
- **`.sync` 双向绑定**：`.sync` / `v-bind.sync` 会让子组件通过 `update:*` 反向改父状态，必须检查是否绕过表单校验、权限校验或状态归属边界；复杂对象 `.sync` 是中后台表单状态错乱高发点。
- **`$children/$parent` 旧式跨层访问**：直接依赖组件层级会被插槽、条件渲染、异步组件和重构破坏；正式问题重点看跨层读取权限、表单实例、表格选择态和弹窗状态。
- **`$refs/$nextTick` DOM 时序**：`$refs` 只在渲染后可用，`v-if`、异步组件、弹窗/抽屉懒渲染、表格列动态渲染都可能导致空引用；依赖 `$nextTick` 串联业务流程时要检查竞态和异常兜底。
- **keep-alive 缓存页**：被 `<keep-alive>` 缓存的组件不会按普通销毁流程释放资源，必须检查 `activated` / `deactivated` 中的数据刷新、timer/listener/subscription 清理、表单脏状态和权限变化后的缓存失效。
- **旧 slot / scopedSlots**：`slot-scope`、`this.$scopedSlots`、动态插槽名在复杂表格/表单中容易造成渲染上下文不清、类型缺失和升级 Vue3 阻塞，应标记为迁移债或可维护性风险。

## Vue 3 重点

- **Composition API**：`ref`/`reactive` 解构不得破坏响应式；`watch`/`watchEffect` 依赖、清理函数和 flush 时机要可解释。
- **`<script setup>`**：`defineProps` / `defineEmits` / `defineExpose` 的类型与运行时边界一致；避免把副作用写在顶层且不可取消。
- **生命周期清理**：`onMounted` 注册的 listener、timer、订阅、请求应在 `onUnmounted` 或 `watch` cleanup 中释放。
- **Pinia**：action 错误处理、并发请求、持久化敏感数据、跨 store 循环依赖需要重点检查。
- **Vue Router 4**：异步守卫必须返回明确结果；鉴权、动态路由、跳转参数需有白名单或权限校验。
- **模板性能**：大列表 `v-for` 必须有稳定 key；高频渲染路径避免重计算、深层响应式和无界 watcher。
- **provide/inject 响应性**：`provide` 注入的值若未用 `ref`/`reactive` 包裹（直接 provide 原始值/对象），消费方 `inject` 拿不到更新；必须检查 provide 的是响应式引用还是静态值，跨层传递的状态变更是否真能触达孙组件。
- **`<script setup>` 顶层 await**：顶层 `await` 会使该组件成为异步依赖，必须外层包 `<Suspense>` 并提供 `fallback`；缺失 Suspense 边界会导致异步态渲染崩溃或组件树卡在 pending。
- **Suspense / Teleport 误用**：`<Teleport :to="target">` 的目标元素不存在或未挂载时会报错；`<Suspense>` 缺失 fallback、嵌套 Suspense 的回退顺序混乱需检查。
- **Pinia setup-store 与 option-store 混用**：同一项目混用 `defineStore('id', { state })`（option）与 `defineStore('id', () => {})`（setup）两种写法会导致风格不一致、类型推断丢失、`$reset`/`$subscribe` 行为差异，应识别混用边界与迁移方向。
- **`useAttrs`/`useSlots` 类型**：`<script setup>` 下未用 `defineSlots<>()`/泛型声明 `useAttrs<T>()` 时，`attrs`/`slots` 类型退化为 `any`，破坏类型安全链。
- **fallthrough attrs / inheritAttrs**：多根组件或包装组件若未显式处理 `$attrs`，class/style/listener 可能落到错误 DOM；需要检查 `defineOptions({ inheritAttrs: false })` 后是否手工透传关键属性和事件。
- **readonly provide**：跨层提供可变状态时，优先在 provider 侧集中 mutation；若 inject 方可直接改祖先状态，应检查是否需要 `readonly()`、action 包装或明确的写入边界。
- **template refs 类型与空值**：`useTemplateRef` / `ref<HTMLElement | null>` 必须处理未挂载、条件渲染、Teleport 和异步组件导致的 null；直接 `ref.value!` 在弹窗、表格、权限组件中风险较高。

## 通用 Vue Router 4 与安全补充

- **history 模式 base 路径**：`createWebHistory('/sub-app/')` 的 base 必须与实际部署子路径一致；base 缺失或不匹配会导致生产环境资源 404、刷新白屏、路由解析错位（中后台微前端 / 子路径部署高频）。
- **动态路由权限时序**：`router.addRoute()` 在导航守卫中调用存在时序竞态——守卫首次触发时路由表尚未注入，需 `next(to.fullPath)` 重定向触发二次匹配；权限路由注入时机与首次导航的竞态是 Vue Router 4 高频 bug 源。

## B 端组件库与权限场景

- **Element UI / ant-design-vue 表单**：校验规则、异步 validator、动态表单项、弹窗关闭重置、`destroy-on-close` / `forceRender` 等行为要和提交链路一致；不得只依赖前端必填校验保护关键业务。
- **表格批量操作**：分页、筛选、排序、跨页勾选、虚拟滚动、行 key 与 selection 状态必须一致；删除/刷新后旧 selection 复用会造成批量误操作。
- **弹窗 / 抽屉 / 页签缓存**：关闭时是否释放 timer、请求、表单状态、上传任务和权限态；keep-alive 页签切回时是否重新校验权限和刷新关键数据。
- **权限按钮与路由 meta**：权限按钮只隐藏不等于授权，必须核查接口权限、路由守卫、菜单权限、按钮权限和后端资源归属校验是否一致；仅靠 `v-if="hasPermission"` 的关键操作应至少归为待确认。
- **微前端 / 子应用部署**：base 路径、静态资源 publicPath、路由模式、跨应用通信、全局样式污染和 shared dependency 版本漂移需要在配置和入口文件中交叉检查。

## 通用 Vue 安全与质量规则

- `v-html`、用户可控 URL、动态组件名、`window.location`、`target="_blank"` 链接必须按安全维度审查。
- `.vue` SFC 中 `<template>`、`<script>`、`<style scoped>` 的职责边界要清晰，避免单文件过长、跨层直接访问请求层或全局对象。
- 表单、表格、权限按钮、路由入口和请求层是 B 端中后台的高风险扫描优先级。
- 依赖风险仍遵守全局规则：只有 lockfile 版本明确且证据可靠时才能下确定性漏洞结论。

---

*本手册版本：Vue 规则 2.3（Vue2 legacy + Vue3 + B 端组件库补强）*
*最后更新：2026-07-02*
