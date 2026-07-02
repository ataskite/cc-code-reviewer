# Node.js 审查规则细则

本文件按前端族群适配器的 11 个维度组织 Node.js 项目专项规则。Node 项目通过 `PROJECT_TYPE=node` 进入同一审查入口，但正式问题范围仍来自不可变 source manifest。

## Runtime 与模块系统

- **版本边界**：读取 `engines.node`、lockfile 和运行脚本，确认语法/API 与目标 Node 版本一致。
- **模块系统**：检查 `package.json` 的 `type`、`main`、`exports` 与源码中的 ESM/CJS 用法是否一致，避免双包入口、默认导入和动态 require 兼容问题。
- **启动脚本**：`scripts.start`、`main`、部署入口和实际 server 文件需一致；不可只凭本地 dev 脚本推断生产行为。

## HTTP / BFF / API

- **输入校验**：请求参数、body、headers、cookies、文件上传必须在入口边界校验和净化。
- **鉴权与越权**：路由、中间件和 service 层都要确认认证、授权、租户隔离、资源归属校验。
- **错误处理**：Express/Koa/Fastify 异步错误必须进入统一错误处理中间件；错误响应不得泄露 token、SQL、内部路径或堆栈。
- **开放重定向与 SSRF**：用户可控 URL 用于跳转、代理、回调、webhook、文件下载时必须有白名单。

## 异步、资源与稳定性

- Promise 链必须处理 reject；定时任务、队列消费者、数据库连接、HTTP client、stream 需要超时、取消和释放。
- 数据库事务、缓存更新、消息发布和外部 API 调用要检查一致性、重试幂等和部分失败补偿。
- 高并发路径需检查连接池、限流、背压、请求体大小限制和同步阻塞 CPU 操作。

## 依赖与配置

- `.env`、配置默认值、日志级别、CORS、cookie/session、安全 headers 必须按生产环境审查。
- 依赖风险结论遵守全局规则：没有 lockfile 和可信公告时，只能给待确认或扫描建议。
