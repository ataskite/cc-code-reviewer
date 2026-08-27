<!-- 适用: **/pom.xml -->
# Maven POM 依赖治理专项清单（pom.xml）

- 检查直接依赖是否硬编码具体版本号而非经 `dependencyManagement` / `${revision}` 统一收敛；版本散落会导致升级遗漏与冲突漂移
- 排查 CVE 高危组合：log4j-core < 2.17.1、fastjson < 1.2.83、commons-text < 1.10.0、shiro < 1.11、snakeyaml < 2.0 及与所用 Spring 版本相关的 RCE 版本；命中时给出安全修复版本建议并评估可达性
- 审视同一 `groupId:artifactId` 经多条传递路径以不同版本进入依赖树却未收敛/未 exclusion 的冲突：确认实际生效版本，指出因版本仲裁偏旧引入的兼容或漏洞面
- 核对 provided 与 compile 作用域混用：容器自带的 servlet-api/jsp-api、仅编译期的 lombok 等被打进 war/jar 产物会造成类冲突与体积膨胀；测试库（junit/mockito）误入 compile 同样指出
- 确认敏感能力是否随默认依赖进入生产构建：actuator/druid 未配套鉴权即暴露管理端点，spring-boot-devtools 进生产包开放远程调试面
- 检查 `<repositories>` / `<pluginRepositories>` 是否指向不可信镜像源或在生产构建中启用 snapshot 源，存在解析到被篡改构件的风险
- 验证插件版本锁定：maven 插件缺 `<version>` 或引用 LATEST/RELEASE 导致构建不可复现，指出应固定的插件坐标
- 审视 BOM 与显式 `<version>` 并存时的覆盖关系：显式版本压过 BOM 受管版本往往让 BOM 形同虚设，指出应删除的显式声明
- 检查依赖引入的系统级副作用面：被传递引入的 xxl-job/quartz/nacos-client 等若未在代码使用却在 classpath 中，提示收窄依赖减小攻击面
