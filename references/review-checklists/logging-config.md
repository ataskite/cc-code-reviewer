<!-- 适用: **/{logback*,log4j2*}.xml -->
# 日志配置专项清单（logback*.xml / log4j2*.xml）

- 检查 pattern 是否打印请求头/请求体/响应体类字段：authorization、cookie、token、password、身份证、手机号经 MDC 或 %msg 直接进日志按敏感数据泄漏候选处理
- 核对 SQL 日志通道：mybatis/hibernate 的 DEBUG 输出会把绑定参数（含敏感业务值）写进生产日志，确认生产 profile 下级别收敛
- 排查日志落盘位置与权限：日志文件写入全局可读目录或 filePermissions 过宽时指出；容器内固定路径与卷挂载权限一并审视
- 确认 remote appender（SocketAppender/Syslog）传输是否明文且目标地址硬编码内网信息
- 审视 log4j2 高危点：确认 log4j-core 版本 >= 2.17.1（JNDI 注入），pattern/layout 中不再出现 `${jndi:}` 相关 lookup 能力被触达的配置形态
- 检查 `.layout` 类自定义 layout 与 message lookup：应用数据可流入 `%m` 的转换链时评估 lookup 触发面并给出升级建议
- 核对异步 appender 队列设置：AsyncAppender/RingBuffer 缓冲无界或 neverBlock=true 时静默丢日志；blocking 语义与队列大小给出明确权衡建议（低危级不占高危位）
- 确认 root logger 未把业务库设为 ALL/TRACE，含 sifting 按用户分文件时文件数量增长无上限
- 检查多环境差异：dev 配置的细粒度 TRACE 经 profile 复制到生产配置的残留项逐个指出
