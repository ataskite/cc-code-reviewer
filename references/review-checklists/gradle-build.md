<!-- 适用: **/build.gradle **/build.gradle.kts -->
# Gradle 构建治理专项清单（build.gradle / build.gradle.kts）

- 检查依赖是否硬编码具体版本号而未用 version catalog（libs.versions.toml）或 platform/BOM 统一管理；散落版本导致升级遗漏
- 排查 CVE 高危组合：log4j-core < 2.17.1、fastjson < 1.2.83、commons-text < 1.10.0、snakeyaml < 2.0 及与所用 Spring Boot 插件默认拉入版本的已知漏洞；命中时给出安全修复版本建议
- 审视同一坐标多版本冲突：`configurations.all { resolutionStrategy }` 强制替换与自然仲裁不一致、未做 conflict resolution 声明时，确认实际生效版本并指出偏旧风险面
- 核对 `compileOnly` 与 `implementation` 误用：容器/代理运行期提供的库被 implementation 打进 fat-jar 造成类冲突；仅编译期处理（lombok）漏标 annotationProcessor 导致构建不稳定
- 确认 `implementation` 中混入仅测试需要的库（junit/mockito）扩大产物体积；测试配置是否使用独立 sourceSet 而非主配置泄漏
- 检查 repositories 是否包含不可信镜像源或启用 maven snapshot 渠道参与生产构建，存在解析到被篡改构件的风险
- 验证插件锁定：`id "x"` 缺版本声明或经 `apply plugin` 动态加载导致构建不可复现，指出应显式固定版本的插件
- 审视任务级敏感操作：构建脚本内嵌明文凭据（publishing/deployer password）、`System.getenv` 回退硬编码默认值即视作密钥入库候选
- 确认 kts 中来自网络/本地脚本的动态依赖来源（`from(url)`、反射拼 classpath）是否有供应链审计缺口
