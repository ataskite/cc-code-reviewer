# 前端正式审查范围

本文件定义前端族群（React / Vue 2 / Vue 3 / Node.js / TS / JS）适配器的正式问题范围、只读上下文与默认排除，落地 spec 第 7 节。覆盖率口径与 Java 保持一致：报告只展示一个源码文件覆盖率。

## 正式问题范围（formal）

- `src` 及适配器确认的应用源码目录内的 `.ts`、`.tsx`、`.js`、`.jsx`、`.vue`、`.mjs`、`.cjs`
- **BFF server-root 层**（v1.7.0）：受支持 package 包根与一级非噪声目录内的服务端 `.js`、`.mjs`、`.cjs`。老式 BFF 脚手架（express/superagent 时代）的服务端代码位于项目根（`app.js`/`server.js`）与 `controllers/`、`common/`、`core/`、`middleware/`、`application/` 等一级目录，src-only 口径会静默漏掉中继/鉴权/会话等漏洞主体文件。server 层按信号门控发现（`collect-source-files.sh`）：包级合格 = `package.json` 的 `main`/`scripts.{start,dev}` 入口指向 src 外真实 JS，或包根存在强服务端信号（express/koa/fastify 依赖、`.listen(`、`createServer`、router 动词、`RequestMapping` 变体）；收集 = 根级文件（排除构建/测试配置 basename）+ 一级非噪声目录（排除 `mock*`/`test*`/`*shell`/`sdk*`/`tpl*`/`static*`/`vite*`/`webpack*` 等）全深度内带模块信号（`require(`/`module.exports`/`exports.`）的文件；`.ts` 不入 server 层（现代 TS BFF 位于 src，由 src 管线覆盖）。上限 `CC_CODE_REVIEWER_SERVER_ROOT_LIMIT`（默认 200，0=禁用），stderr 以 `SERVER_ROOTS_ADDED=N` 披露
- React 组件/Hooks、Vue SFC/状态管理/路由、Node server/routes/middleware/service/data-access 和数据请求代码
- 正式配置文件（`package.json`、`tsconfig.json`、`vite.config.*`、`webpack.config.*`、`vue.config.*`、`babel.config.*`、路由配置）：**可产生问题**，但单独计入 `FORMAL_CONFIG_FILE_COUNT`，**不进入源码文件覆盖率分母**

## 只读上下文（context）

- 单元测试、组件测试、端到端测试：只用于判断核心逻辑或关键路径是否缺少测试，**不输出正式问题**，不计入正式覆盖率
- 类型声明文件 `.d.ts`
- lockfile：仅作依赖版本证据
- 生成代码：仅在理解调用关系确有必要时读取

## 默认排除（excluded）

- `node_modules`、`dist`、`build`、`coverage`、`.next`、`.nuxt`
- 压缩（`.min.js`）、bundle（`.bundle.js`）、vendor、自动生成文件
- 经项目 Ignore 或适配器规则确认的生成目录

## 覆盖率口径

报告只展示一个「前端源码文件覆盖率」，分母为生产 `.ts/.tsx/.js/.jsx/.vue/.mjs/.cjs` 文件数（来自不可变 source manifest）。上述正式配置文件可产生问题，但单独计数，不进入该覆盖率分母——这与 Java 当前只统计生产 Java 文件覆盖率的口径一致。
