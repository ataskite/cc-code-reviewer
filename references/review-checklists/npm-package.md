<!-- 适用: **/package.json -->
# npm 依赖治理专项清单（package.json）

- 检查运行时依赖版本固定度：`^`/`~`/`*`/`latest` 让构建不可复现，核心服务端依赖建议锁定到 lockfile 并注明升级策略；纯前端构建期依赖可放宽但需说明理由
- 排查已知漏洞版本快照：lodash < 4.17.21（原型污染）、minimist < 1.2.6、node-fetch < 2.6.7 / < 3.x 对应修复线、axios < 1.8.x（SSRF 与重定向处理）等；命中时给出安全修复版本建议并核对 lockfile 实际解析版本
- 核对 dependencies 与 devDependencies 归位：构建工具、测试框架、类型声明混入 dependencies 会扩大生产安装面；库类型项目把运行依赖漏进 devDependencies 会让消费方安装失败
- 检查生命周期脚本钩子：preinstall/postinstall/prepare 中出现 `curl|sh`、动态拼接 URL 下载执行即供应链候选；确认每个钩子的网络行为可审计
- 审视 overrides/resolutions 压制传递依赖：强制指回低于安全线的旧版本时逐条指出目标漏洞面；无法追溯来源的压制仅列提示不占高危位
- 确认直接依赖来源形态：git+https 可变 ref（main/HEAD）、http(s) tarball 绕过 registry 审计链路；要求固定 commit/tag 并说明维护责任
- 核对发布配置边界：library 缺 `"private": true` 且 publishConfig 携带 registry token 相关字段即密钥入库候选；files 白名单是否会把 `.env`/日志/内网配置打进包
- 验证 engines 与 peerDependencies 声明：node 下限与 CI/容器实际运行版本不一致、peer 范围与主库大版本互斥的组合逐项指出
- 检查 workspaces monorepo 一致性：workspace:* 泄入待发布包版本字段、跨包同名依赖多版本漂移未收敛的面
