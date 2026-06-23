# 前端正式审查范围

本文件定义前端（React/TS/JS）适配器的正式问题范围、只读上下文与默认排除，落地 spec 第 7 节。覆盖率口径与 Java 保持一致：报告只展示一个源码文件覆盖率。

## 正式问题范围（formal）

- `src` 及适配器确认的应用源码目录内的 `.ts`、`.tsx`、`.js`、`.jsx`
- React 组件、Hooks、状态管理、路由和数据请求代码
- 正式配置文件（`package.json`、`tsconfig.json`、`vite.config.*`、`webpack.config.*`、路由配置）：**可产生问题**，但单独计入 `FORMAL_CONFIG_FILE_COUNT`，**不进入源码文件覆盖率分母**

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

报告只展示一个「前端源码文件覆盖率」，分母为生产 `.ts/.tsx/.js/.jsx` 文件数（来自不可变 source manifest）。上述正式配置文件可产生问题，但单独计数，不进入该覆盖率分母——这与 Java 当前只统计生产 Java 文件覆盖率的口径一致。
