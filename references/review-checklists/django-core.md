<!-- 适用: **/{settings,urls}.py -->
# Django 核心（settings/urls）专项清单

- 排查 DEBUG 态残留：DEBUG 默认 True 或按 env 回退写死开发值时即候选；确认生产入口有显式关闭证据而非依赖环境继承
- 核对 ALLOWED_HOSTS：空列表靠调试兜底、通配 ["*"] 配合 DEBUG 组合是 Host 头注入与缓存投毒放大器；确认每个环境的收紧粒度
- 检查 SECRET_KEY：硬编码入库、缺省回退常量字符串、多环境共享同一 key 都按会话伪造/CSRF 签名绕过候选处理；确认轮换路径有 KEY.rotation 说明
- 确认数据库与中间件凭据落点：DATABASES/CACHES/CELERY broker URL 内嵌口令明文即列候选；区分「settings 引用 env」与「env 文件同仓库提交」两种伪修复
- 审视传输与 Cookie 安全组合：SECURE_SSL_REDIRECT、SESSION_COOKIE_SECURE、CSRF_COOKIE_SECURE、SECURE_HSTS_SECONDS/INCLUDE_SUBDOMAINS 生产缺省关闭的组合逐项指出并给等级
- 核对中间件顺序语义：SecurityMiddleware 被压缩/改写响应的自定义中间件吞掉导致安全头失效；自定义认证插在 AuthenticationMiddleware 错位的鉴权旁路面
- 检查 urls.py 路由侧风险：redirect()/HttpResponseRedirect 目标来自请求参数构成开放跳转；static()/media 仅应在 DEBUG 分支 serve 的守卫缺失即生产态处理器暴露候选
- 确认暴露面收敛：admin 自动发现开启而无访问门控说明、debug 工具栏/profiler 进 INSTALLED_APPS 的生产残留；文件上传对应 view 层约束在此记录联查线索不直接定级
- 验证时间与时区契约：USE_TZ=False 与 TIME_ZONE 混用导致的跨时区歧义作为低危提示列出，不占高危位
