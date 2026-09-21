# Node.js 审查规则细则

本文件按前端族群适配器的 12 个维度组织 Node.js 项目专项规则。Node 项目通过 `PROJECT_TYPE=node` 进入同一审查入口，但正式问题范围仍来自不可变 source manifest。

## Runtime 与模块系统

- **版本边界**：读取 `engines.node`、lockfile 和运行脚本，确认语法/API 与目标 Node 版本一致。
- **模块系统**：检查 `package.json` 的 `type`、`main`、`exports` 与源码中的 ESM/CJS 用法是否一致，避免双包入口、默认导入和动态 require 兼容问题。
- **启动脚本**：`scripts.start`、`main`、部署入口和实际 server 文件需一致；不可只凭本地 dev 脚本推断生产行为。

## HTTP / BFF / API

- **输入校验**：请求参数、body、headers、cookies、文件上传必须在入口边界校验和净化。
- **鉴权与越权**：路由、中间件和 service 层都要确认认证、授权、租户隔离、资源归属校验。
- **安全审计日志缺失（OWASP 2025 A09）**：鉴权失败（401/403）、越权拒绝、敏感数据导出/批量查询、配置与管理操作无审计日志，或日志缺主体标识（user id/租户）无法追责——安全事件必须可回答「谁、何时、对什么资源做了什么」。
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

### Node 服务端注入与危险 API 负面清单（v1.7.1，OWASP Top 10:2025 A05 注入对齐）

以下类别在 Node 安全审计实践中高频命中且危害直达 RCE/任意文件读写，命中任意一条即构成安全问题候选，必须追到实际输入边界/白名单/净化点才能关闭：

1. **原型污染**：`lodash.merge`/`lodash.set`/`deepmerge`/自写递归 merge 直接消化 `req.body`/`req.query` 对象，或 `JSON.parse` 后未过滤 `__proto__`/`constructor`/`prototype` 键——攻击者污染 `Object.prototype` 即影响全应用所有对象（改写 `isAdmin`/`role` 绕鉴权；污染值配合模板引擎或 `child_process` 可达 RCE，lodash CVE-2019-10744、minimist CVE-2020-7598 同类）。必须递归剔除危险键（或用 `Object.create(null)` 承载查询对象），入口以 schema 校验（zod/joi/ajv）拒绝意外键。
2. **命令注入（child_process）**：`exec()`/`execSync()`/`spawn(cmd, { shell: true })` 的命令串由模板字符串拼接用户输入——`exec` 系走 `/bin/sh`，注入即任意命令执行。必须改 `execFile()` 或无 `shell` 选项的 `spawn()`，参数走数组、用户值置于 `--` 之后、可执行文件名硬编码或白名单。
3. **路径穿越**：`res.sendFile`/`res.download`/`fs.readFile`/`createReadStream` 的路径来自 `req.params`/`req.query`——**`path.join()` 不消除 `../`**。必须 `path.resolve()` 得到绝对路径后校验仍以指定根目录为前缀；`sendFile` 固定 `root` 选项并拒绝 dotfiles。
4. **SSTI 模板注入**：用户可控字符串或模板路径直接进 `res.render`/模板引擎 `compile`（ejs/pug 等）——服务端把用户串当模板代码执行。模板名必须白名单、数据与模板分离，不得接受用户提供的模板内容或按用户输入拼模板路径。
5. **HTTP 参数污染（HPP）**：`?role=user&role=admin` 时 express 取末值而部分中间件/下游服务取首值；`req.query.x` 未做类型归一（可能是数组）直接进下游调用或鉴权判断可造成校验绕过。入口必须显式取单值并做类型归一。
6. **NoSQL 操作符注入**：`req.body`/`req.query` 对象未过滤直接进 Mongo 查询——`$gt`/`$ne`/`$regex`/`$where` 等 `$` 前缀键可构造恒真条件（`{"user": {"$ne": ""}}` 拉全表）。查询构造前必须校验键（拒绝 `$` 前缀）或经 mongo-sanitize/白名单 schema。
7. **不安全反序列化**：`node-serialize`/`serialize-javascript` 或自写序列化从不可信来源（缓存、消息、请求体）还原函数/类实例——`node-serialize` 的 IIFE 载荷即 RCE。不可信数据只用 `JSON.parse` 并做形状校验，禁止使用能还原函数/实例的库。


## 异步、资源与稳定性

- Promise 链必须处理 reject；定时任务、队列消费者、数据库连接、HTTP client、stream 需要超时、取消和释放。
- 数据库事务、缓存更新、消息发布和外部 API 调用要检查一致性、重试幂等和部分失败补偿。
- 高并发路径需检查连接池、限流、背压、请求体大小限制和同步阻塞 CPU 操作。
- **ReDoS**：用户输入进入含嵌套量词/重叠交替分组的正则（`^(([a-z])+.)+[A-Z]([a-z])+$` 类形态）可触发灾难性回溯，单个请求即可冻结整个事件循环；处理用户输入的正则必须核查回溯风险。
- **事件循环阻塞（DoS）**：请求处理器内同步 IO（`fs.readFileSync` 等无异步替代的调用）、无大小上限的 `JSON.parse`、未设 `limit` 的 `express.json`——单线程运行时上同步阻塞等于全站拒绝服务。

## 依赖与配置

- `.env`、配置默认值、日志级别、CORS、cookie/session、安全 headers 必须按生产环境审查。
- **弱算法与不安全随机（OWASP 2025 A04）**：`crypto.createHash('md5')`/`('sha1')`、DES/3DES、`Math.random()` 生成 token/密钥/验证码等安全相关值、`rejectUnauthorized: false` 关闭 TLS 证书校验——安全用途必须换 SHA-256+/HMAC 与 `crypto.randomBytes`，不得以「内部用途」豁免。
- 依赖风险结论遵守全局规则：没有 lockfile 和可信公告时，只能给待确认或扫描建议。
