# Django 审查专项规则

本文件补充 `review-framework.md`，定义 Django 项目的专项审查规则。规则按审查维度组织，仅列出 Django 特有的高风险点；通用 Python 问题见 `review-framework.md`。

> 未检测到 Django 依赖时，本文件不启用。Django 版本以 `pyproject.toml`/`requirements.txt` 中的 `django>=X.Y` 为准。

---

## 维度 4 框架规范

### ORM 模型设计
- `on_delete` 缺失：`models.ForeignKey`/`OneToOneField` 必须指定 `on_delete`（Django 2.0+ 强制），`on_delete=models.CASCADE`/`PROTECT`/`SET_NULL` 需符合业务语义
- `null=True` + `blank=True` 语义混淆：`null` 是 DB 层，`blank` 是表单层；字符串字段不应同时设 `null=True`（Django 约定用空字符串）
- `null=True` 对 `CharField`/`TextField`：应避免，Django 惯例存空字符串而非 NULL
- `default` 可变对象：`default={}`/`default=[]` 会被所有实例共享，应用 `default=dict`/`default=list`（可调用对象）
- `related_name` 冲突：反向关系命名冲突导致 migration 失败
- `db_index` 滥用：索引过多影响写入性能，需结合查询模式评估

### Middleware
- 中间件顺序：`SecurityMiddleware` 必须靠前、`AuthenticationMiddleware` 在 session 之后、自定义中间件的位置影响认证/权限链
- `process_request` vs `process_view` vs `process_response`：副作用时机错误（如 `process_response` 改 DB）
- 中间件阻塞：同步中间件在 ASGI 下阻塞事件循环，应用 `async def`/`sync_to_async`

### Signals
- `post_save`/`pre_delete` 副作用：信号触发顺序不可控、信号内 DB 操作导致额外查询或递归
- 信号 vs 覆写 `save()`：简单逻辑应覆写模型方法，跨模型解耦才用信号
- `@receiver` 连接泄漏：`connect` 未配对 `disconnect`，测试间信号残留

### Admin
- `ModelAdmin.list_display` 暴露敏感字段（如 `password`/`token`）
- `search_fields` 对无索引字段做 `LIKE` 查询导致全表扫描
- `raw_id_fields`/`autocomplete_fields` 未用导致外键下拉加载 N+1
- `actions` 批量操作未评估性能（批量 `save()`）

### Template
- `mark_safe` 渲染用户输入：XSS（CWE-79）
- `|safe` 过滤器误用：同上
- `autoescape` 关闭：`{% autoescape off %}` 块内渲染用户输入

### Settings
- `DEBUG=True` 生产配置（P0 候选，须通过五项硬门槛核验）：泄露源码、堆栈、配置
- `SECRET_KEY` 硬编码或提交到版本库（P0 候选，须通过五项硬门槛核验）
- `ALLOWED_HOSTS = ['*']` 生产配置
- `DATABASES` 密码硬编码
- 分环境配置：`settings/` 目录拆分 `base.py`/`dev.py`/`prod.py`，环境变量注入

---

## 维度 5 数据访问与 ORM

### QuerySet 懒加载与 N+1
- 循环访问外键/多对多关系未 `select_related`/`prefetch_related`：N+1 查询
- `prefetch_related` 后再 filter 产生额外查询：`Prefetch(queryset=...)` 应带 filter
- `queryset.count()` 后再 `list(queryset)`：两次查询，应缓存或用 `len(list(queryset))`

### Raw SQL
- `Model.objects.extra(where=[...])` 拼接用户输入：SQL 注入（CWE-89）
- `Model.objects.raw(f"SELECT ... {user_input}")`：SQL 注入
- `cursor.execute("SELECT ... %s" % user_input)`：SQL 注入
- 正确：`cursor.execute("SELECT ... WHERE id = %s", [user_input])` 参数化

### 事务
- `@transaction.atomic` 作用域：过大的 atomic 块持锁过久、嵌套 atomic 的 savepoint 语义
- `transaction.on_commit()` 未用：事务内触发的副作用（如发通知）在回滚后仍执行
- 长事务：HTTP 请求内开事务跨网络调用，持锁导致死锁

### Migration
- `RunPython` 无反向函数：migration 不可回滚
- 数据迁移与 schema 迁移混用：数据迁移应在 schema 迁移后单独 migration
- `migrations.SeparateDatabaseAndState`：DB 层与 model 层不一致
- migration 文件手动编辑导致历史断裂

---

## 维度 6 安全

### CSRF
- `@csrf_exempt` 误用：非 API 视图关闭 CSRF 保护
- API 视图未用 DRF `SessionAuthentication`（自带 CSRF）或 token 认证

### 认证授权
- `@login_required` 缺失：视图未保护
- `@permission_required` 粒度过粗：应用对象级权限（`has_object_permission`）
- DRF `permission_classes` 缺失：默认 `AllowAny`

### 文件上传
- 用户上传文件名直接用作存储路径：路径穿越
- 文件类型校验仅靠扩展名：应校验 MIME/魔数
- 上传文件存到 web 可访问目录无权限控制

### Session
- `SESSION_COOKIE_SECURE`/`CSRF_COOKIE_SECURE` 生产未设 True
- `SESSION_COOKIE_HTTPONLY` 未设 True

---

## 维度 7 性能

### QuerySet 性能
- `len(queryset)` 触发全量加载：应 `.count()` 只查数量
- `queryset[0]` 触发全量加载：应 `.first()` 或 `[:1]`
- `bool(queryset)` 触发查询：应 `.exists()`
- 批量 `save()`：用 `bulk_create`/`bulk_update`
- `iterator()` 未用：大 queryset 一次性加载到内存

### 缓存
- `cache.set` 无过期：内存泄漏
- 缓存击穿：热点 key 失效瞬间并发回源，应加锁或 `cache.get_or_set`
- 缓存键含用户输入未校验：键注入

---

## 维度 10 错误处理与可观测性

### 错误响应
- `DEBUG=True` 时 Django 返回堆栈页：生产泄露
- 自定义 `handler500`/`handler404` 缺失：默认错误页无品牌一致性
- DRF 异常处理：`EXCEPTION_HANDLER` 未定制，敏感信息泄露

### 日志
- `LOGGING` 配置缺失：默认 Django 不记录请求日志
- 日志含 `SECRET_KEY`/DB 密码：`LOGGING` 的 `formatters` 未过滤敏感字段
- `ADMINS` 邮件通知：生产 500 错误邮件泄露堆栈到外部邮箱

---

## 维度 12 接口与类型契约

### DRF Serializer
- `Serializer` 与 `Model` 字段漂移：model 加字段后 serializer 未同步
- `SerializerMethodField` 滥用：简单字段用 method 导致 N+1
- `depth` 选项：嵌套序列化导致 N+1，应显式 `select_related`

### URL 设计
- `urls.py` 的 `urlpatterns` 顺序：先具体后通配
- `name` 参数缺失：反向解析依赖硬编码 URL
- `namespace` 缺失：多 app URL 冲突
