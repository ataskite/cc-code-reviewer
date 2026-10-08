# Node/BFF 代理与身份专项（Security 模式必读）

本地审查规则补充，不是扫描器或 OWASP 认证。由 `node-rules.md` 路由到本文；适用控制、稳定 ID 和标准映射以冻结 controls 与 catalog 为准。以下要求也适用于独立 Node API，不依赖 node-bff 分类。纯浏览器项目不启用 Node 控制。

## 1. Host 路由身份：CCR-NODE-HOSTROUTE-001

```text
客户端 body.header.Host = service-b.example.test
                    |
                    v
BFF 固定 URL = http://ingress.example.test + path
    将客户端 header 交给实际 HTTP client
                    |
                    v
网络目标 = ingress.example.test
HTTP Host = service-b.example.test
                    |
                    v
共享 Ingress 按 Host 选择 service-b（需路由配置佐证）
```

- 分别追踪网络目标、HTTP 路由身份和授权身份，不能因为 URL 固定就关闭 SSRF/代理滥用候选。
- Source 不限 `req.headers`：body/query 中的 header/headers/options，跨文件封装、别名、合并后的最后写入均需追到真正客户端。审查 `Host`/`host`、大小写变体、重复键、HTTP/2 `:authority`、`hostRewrite`/`autoRewrite`、TLS `servername`；核对具体客户端如何解析，不假设所有库的合并优先级相同。
- 服务端绑定的内部 Host 可以与 TCP 目标不同，合法虚拟主机路由不是漏洞。确认客户端是否能覆盖服务端绑定；仅删除一个大小写的 Host 或默认对象后再 spread 客户端 options 不足以证明防护。
- 证据至少包括入口、可控值、每层传播、客户端调用/字段、防护缺口。确认客户端可以改出站 Host，可形成代码级发现；Ingress 是否实际按该值路由、能否触达敏感服务及其影响单独列证据，缺配置时标注外部证据缺失，不能声称攻击链已完整复现或直接定 P0。
- 修复：出站请求重构而非透传；路由身份由服务端 capability 定义，客户端覆盖应拒绝或不参与构造；网关按来源服务身份 × Host × 目的服务约束，后端仍校验调用者权限。
- 验证：仅在获授权的本地/测试环境发送伪造 Host（大小写、嵌套 options、封装入口），捕获出站请求确认仍绑定服务端值或拒绝；目标服务越界再用测试 Ingress 验证。

## 2. 服务端代理能力：CCR-NODE-PROXYCAP-001

```text
客户端业务参数 + capability 名称
             |
             v
可信主体 × capability 权限检查（默认拒绝）
             |
             v
服务端表：service + Host + path模板 + method + 参数schema
             |
             v
重构出站请求（客户端不能覆盖 transport options）
```

- 建立入口 × capability/action 台账，检查 service/origin/baseURL/port、Host、path、method 是否由服务端绑定；固定域名不等于固定能力，任意内部管理路径仍可越权。
- 业务参数与 transport options 必须分离。检查 path 拼接、绝对/协议相对 URL、路径归一化和编码、query 是否成为路由、最后写入覆盖；按具体库语义确认实际效果。
- caller 的主体来自可信会话或完整验证的 token，权限校验必须绑定本次能力/动作，不能仅登录就获得全部内部接口。BFF 自身服务身份不代表客户有权执行下游操作。
- capability 名来自客户端不是漏洞：确认是否查服务端固定表、逐能力授权、校验参数并拒绝未知能力。Host 白名单 + method 枚举本身不约束全部 path，不能作为完整能力边界。
- 修复以固定业务接口或能力映射替代万能 `/proxy`；先授权再构造，模板参数分别编码，允许字段显式赋值，默认拒绝而非默认放行。
- 验证同角色异对象、低权高功能、跨租户、未知能力、越界 path/method、options 覆盖和替代入口。对象级授权仍按 BOLA 控制检查，避免把功能权限当作对象权限。

## 3. JWT 接受链：CCR-NODE-JWTAUTH-001

| 检查 | 必须看到的代码或可信配置 |
|---|---|
| 接受位置 | 从 token 到主体，再到受保护动作的真实路径；decode 不是 verify |
| 签名与算法 | 签名/MAC 成功才用 claims；固定算法 allowlist，无 none/算法混淆 |
| 密钥 | 服务端可信 key/JWKS 来源；不能让 token 的 jku/x5u/jwk 选择任意信任根 |
| iss / aud | 校验预期签发者和本服务受众，不是只检查字段存在 |
| 时效 | 此应用策略要求有效 exp，并执行过期检查；如有 nbf 必须校验，不关闭时间验证 |
| 失败分支 | 异常/无 key/验证失败拒绝；不能回退 decode、缓存未验证主体或 next 放行 |
| 权限 | 已验证 claims 仍需主体—动作—对象授权，不等于业务鉴权完成 |

- 函数叫 `verifyToken` 或调用库的 `verify` 不足以证明以上条件；读取包装实现和实际参数。若 JWT 不在本范围使用，查明身份路径后可记 checked_no_finding 并说明无 JWT 接受面，不能仅凭正则未命中关闭。
- 若由外部认证网关完成验证，需可信来源约束和验证策略证据；没有这些只能 external_evidence_missing，不擅自认定本地未验签漏洞。
- 修复：可信库 + 固定算法/密钥来源 + 固定 iss/aud + 时效要求 + 验证失败拒绝；配置缺失应拒绝启动/请求。不得将 token、私钥或客户身份原值写入报告。
- 验证矩阵：坏签名、none/错误算法、不可信 key locator、错误 iss/aud、过期 exp、缺失 exp、未来 nbf、验证异常；每项均应拒绝且不触发受保护动作。

## 4. 代理信任：CCR-NODE-PROXYTRUST-001

```text
连接对端 socket.remoteAddress -> 是否可信代理？
                    |
                    v
按真实拓扑解析 Forwarded / X-Forwarded-* 链
                    |
                    v
client IP / hostname / protocol -> 安全决策
```

- 查 `trust proxy`、自定义 peer 谓词、真实代理网段、数值 hop-count、以及绕过框架直接读取 XFF/XFH/XFP 的代码。沿 `req.ip`/`req.hostname`/`req.protocol` 追到 IP 白名单、租户选择、Secure Cookie、限流键等安全敏感用途。
- `trust proxy=true`、hop-count 或宽泛网段本身不是已证实漏洞；确认是否能直连、是否有不同长度入口、最后可信代理是否覆盖而非追加不可信 XFF/XFH/XFP。配置看似严格但拓扑/清洗证据缺失时记 external_evidence_missing，明确所需部署证据。
- 代码在无可信对端约束下直接用攻击者可控 forwarded 值做权限判断，可以报告代码级缺陷；对外可达性/实际代理链另行取证。
- 修复绑定真实连接对端和拓扑；所有入口一致清洗重建 forwarded 头；无代理时不信任这些头。不能一律改 false（可能破坏合法代理后的 IP、TLS Cookie 判断），也不能盲目改成 hop=1。
- 验证直连、正常代理链、短链/旁路、多 hop、伪造头、边缘重复/追加，比较 IP/host/protocol 与安全决策；只在授权测试环境执行。

## 5. 报告与离线边界

- 上述四条适用控制均须进入既有 Security 控制覆盖台账。regex 和 surface 只导航，不自动产生漏洞；检查到真实缺陷才 finding_confirmed，完整检查到阻断证据才 checked_no_finding。
- 多控制指向同一根因时可以共用证据说明，但每个 finding_confirmed 控制仍须有携带其规则 ID 的正式问题块（既有校验契约）；关联说明共同根因，不能省略适用行或重复夸大攻击链影响。
- P0 仍须满足统一框架的全部硬门槛；缺外部证据不得以候选严重度替代证明。
- 本文离线自足；以下地址仅记录实现语义的维护来源，运行时禁止联网读取：
  - https://expressjs.com/en/guide/behind-proxies/ （可信代理、变长链与 forwarded 清洗）
  - https://github.com/auth0/node-jsonwebtoken/blob/master/README.md （decode/verify 与验证选项）
- 标准映射详见本地 catalog 与固定 OWASP 快照。本文不宣称等价于 ASVS 全量验收。
