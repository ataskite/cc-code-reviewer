<!-- 适用: **/{openapi,swagger}.{json,yml,yaml} -->
# OpenAPI/Swagger 规范专项清单（openapi.* / swagger.*）

- 检查写接口鉴权声明：POST/PUT/DELETE/PATCH 操作缺 security 或 securitySchemes 全局为空时，确认是文档缺失还是后端确实无鉴权；与实现代码对照后再定性
- 核对 securitySchemes 定义：apiKey 放 header/query 的暴露位置、http bearer 缺scopes 细化、oauth2 flows 回调地址是否内网明文
- 审视响应模型内部字段泄漏：实体直出带 passwordHash、salt、internalId、审计字段、堆栈 message 的即列候选，要求响应 DTO 白名单裁剪
- 排查路径设计缺陷：同资源 REST 动词混用、GET 承担状态变更、URL 携带 token/sessionId 等敏感参数
- 确认文件上传接口：requestBody 声明的类型/大小约束是否存在，缺失时后端任意文件上传风险关联说明
- 检查分页/导出类接口响应 schema：无 maxItems 上限的全量列表按性能候选标注
- 验证版本与废弃声明：deprecated 接口仍在响应示例中作为主路径引用、多版本共存时的迁移缺口
- 核对错误响应契约：4xx/5xx 是否有统一错误模型，error.message 直接透出异常细节的接口逐个指出
