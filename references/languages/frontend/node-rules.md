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

### BFF 中继层负面清单（2026-09-18 IMA 前端 BFF SSRF 事件实证）

以下反模式来自真实事件取证（通用中继接口 + 客户端可控请求头 → 内网 SSRF 数据泄露），命中任意一条即构成安全问题候选，必须追到实际白名单/阻断点才能关闭：

1. **出口头黑名单 = 半吊子防御**：`Object.assign/extend(headers, req.headers)` 后仅 `delete` 少数键（host/content-length/x-requested-with 等）仍是客户端可控头透传——信任头（X-Internal、XFF、内部 token 头等）全部可穿过过滤器。BFF 外发请求头必须按**白名单**逐键构造；禁止在现有黑名单上打补丁。
2. **白名单键名但值取自客户端头**：逐键构造出口头时，值来自 `req.headers`（如 `Authorization: req.headers.atoken`、`CmcToken`、`X-Product-Code`、`x-forwarded-for`）同样是身份注入——键名可控性不重要的地方，值的来源才重要。
3. **body 参数优先于 session 成身份**：`token = data.LOCAL_TOKEN ? data.LOCAL_TOKEN : req.session.authorization` 一类写法允许任意客户端伪造任意用户身份外发；来自 body/query 的身份证据不得覆盖服务端会话来源。
4. **session 任意字段写入（mass assignment）**：`for (let x in req.body) { req.session[x] = req.body[x] }`（`/updateBaseConfig`、`/updateRedis` 同款）允许向会话注入任意身份/配置字段；session 写入必须有字段白名单。
5. **匿名端点返回 secret 派生值**：无鉴权接口返回 `MD5(secretKey.replace(/-/g, req.query.pwd))` 一类口令密文，等于把任意账号口令生成能力挂在公网（供应链级风险）。
6. **XHR 头 / 无密钥签名当鉴权**：仅凭 `X-Requested-With` 或自定义头（`isAjaxRequest` 类）判定请求合法；无密钥 MD5 拼接签名（`MD5([channel, code, id].join(';')) == sign`）客户端可自行计算——两者都不是授权证据。
7. **SSRF 缓解绕过变体**：只挡 Host 头不够（`@` userinfo、协议相对 URL、重定向均可绕过）；`rb.origin ? rb.url : host + rb.url` 的任意 origin 分支是 SSRF 直通。**目标 host 白名单**（解析后校验 host）才是有效缓解，URL 必须强制以 `/` 开头且拒绝 `@`。


## 异步、资源与稳定性

- Promise 链必须处理 reject；定时任务、队列消费者、数据库连接、HTTP client、stream 需要超时、取消和释放。
- 数据库事务、缓存更新、消息发布和外部 API 调用要检查一致性、重试幂等和部分失败补偿。
- 高并发路径需检查连接池、限流、背压、请求体大小限制和同步阻塞 CPU 操作。

## 依赖与配置

- `.env`、配置默认值、日志级别、CORS、cookie/session、安全 headers 必须按生产环境审查。
- 依赖风险结论遵守全局规则：没有 lockfile 和可信公告时，只能给待确认或扫描建议。
