<!-- 适用: **/application*.{yml,yaml,properties} **/bootstrap*.{yml,yaml,properties} -->
# Spring 配置专项清单（application*/bootstrap* .yml/.yaml/.properties）

- 排查明文密钥口令：datasource.password、redis/spring.data.redis.password、rabbitmq/kafka/mongodb 凭据、api-token/access-key/secret 出现明文即列候选；确认是否有环境变量/Jasypt/Vault 替代方案
- 检查 management.endpoints.web.exposure.include 是否暴露 `*` 或包含 env、heapdump、threaddump、loggers、restart；确认是否配套独立管理端口与鉴权
- 核对 Druid 监控面：stat-view-servlet.enabled=true 时 login-username/password 是否缺失或弱默认，allow/deny 白名单是否放行 0.0.0.0
- 确认 JMX 远程暴露（spring.jmx.enabled / com.sun.management.jmxremote）在生产配置中关闭或加鉴权，无鉴权 JMX 可远程执行代码
- 检查 debug 开关与开发态残留：debug=true、spring.jpa.show-sql=true、mybatis log-impl=STDOUT、swagger/knife4j 生产启用均列为收敛候选
- 审视日志级别：root/特定包设为 DEBUG 且打印请求体、SQL 参数、token 的组合按敏感数据入日志候选处理
- 核对连接池参数合理性：hikari maximum-pool-size/druid initialSize-maxActive 与实例规格匹配、缺 max-lifetime 导致的连接僵死
- 检查 bootstrap/Nacos/Apollo 配置中心地址与凭据是否硬编码内网明文且缺传输加密说明
- 验证 session/cookie 与 CORS 配置：cookie 缺 HttpOnly/Secure、allowedOrigins="*" 与 allowCredentials=true 并存的高危组合
