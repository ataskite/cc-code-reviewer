# FastAPI 审查专项规则

本文件补充 `review-framework.md`，定义 FastAPI 项目的专项审查规则。规则按审查维度组织，仅列出 FastAPI 特有的高风险点；通用 Python 问题见 `review-framework.md`。

> 未检测到 FastAPI 依赖时，本文件不启用。FastAPI 版本以 `pyproject.toml`/`requirements.txt` 中的 `fastapi>=X.Y` 为准。

---

## 维度 4 框架规范

### 路由与依赖注入
- `async def` vs `def`：`async def` 路由在事件循环中执行，内部调用同步阻塞函数会卡住整个循环；同步路由（`def`）会被放到线程池，适合调用同步 DB 驱动
- `Depends` 作用域：默认每次请求重新解析；`yield` 依赖的资源清理（如 DB session）在 `finally` 之外不保证执行
- 依赖嵌套过深：`Depends` 链超过 3 层应评估是否拆分
- `Depends` 缓存：同请求内同依赖默认只解析一次，副作用依赖（如计数器）会被意外去重

### Pydantic 模型
- `BaseModel` 字段校验：`validator`/`field_validator`（v2）异常未转为 `ValidationError`，返回原始异常
- v1 vs v2 混用：`pydantic v1` 的 `.dict()`/`.json()` 在 v2 已废弃（应用 `.model_dump()`/`.model_dump_json()`）
- `Config` 类：v1 用内部 `Config`，v2 用 `model_config = ConfigDict(...)`
- 可变默认值：`Field(default=[])` 共享可变对象，应用 `Field(default_factory=list)`
- `orm_mode`/`from_attributes`：v1 `Config.orm_mode=True` -> v2 `model_config = ConfigDict(from_attributes=True)`
- 嵌套模型序列化漂移：`response_model` 与实际返回类型不符，OpenAPI schema 与实现不一致

### OpenAPI / 文档
- `response_model` 缺失：OpenAPI schema 无响应类型，前端契约漂移
- `tags`/`summary`/`description` 缺失：文档不可读
- `response_model_exclude_none` 误用：掩盖真实可空字段
- 自定义 `OpenAPI` schema 覆写：手写 schema 与自动生成不一致

### BackgroundTasks
- `BackgroundTasks` 中跑长任务：阻塞响应返回后的 worker，应用 Celery 等外部队列
- `BackgroundTasks` 异常未处理：异常被吞，无监控
- `BackgroundTasks` vs `asyncio.create_task`：前者在响应后执行，后者立即并发，语义混淆

---

## 维度 5 数据访问与 ORM

### 异步 DB 驱动
- `async def` 路由内用同步 SQLAlchemy（`create_engine`/`Session`）：阻塞事件循环，应用 `create_async_engine`/`AsyncSession`
- `AsyncSession` 未 `async with`：连接泄漏
- `AsyncSession.execute()` 后未 `await session.commit()`：事务未提交

### SQLAlchemy 通用
- `Session` 生命周期：`Depends` 提供 session 应用 `yield` 确保关闭
- `text()` 参数化：`text(f"SELECT {user_input}")` SQL 注入；`text("SELECT :val").bind(val=user_input)` 安全
- `relationship` 懒加载：`lazy="select"` 在循环中触发 N+1，应用 `selectinload`/`joinedload`

---

## 维度 6 安全

### 认证授权
- `Depends(get_current_user)` 缺失：路由未保护
- OAuth2/JWT：`python-jose`/`PyJWT` 算法未显式指定（`algorithms=["HS256"]`），`none` 算法攻击
- OAuth2 scopes：`Security(scopes=["admin"])` 未校验，仅文档层
- CORS：`CORSMiddleware` 的 `allow_origins=["*"]` + `allow_credentials=True` 会被浏览器拒绝 credentialed CORS，通常属于配置/功能错误；真正的安全风险是反射任意 Origin 或过宽 Origin 白名单同时允许 credentials

### 输入校验
- `Path`/`Query` 参数：未限定类型与范围（`Path(..., ge=1)`/`Query(..., max_length=100)`）
- `Body` 原始 dict：绕过 Pydantic 校验，应用 `BaseModel`
- 文件上传：`UploadFile` 未校验大小/类型，内存耗尽或路径穿越

### SSRF
- `httpx.get(user_url)`/`httpx.AsyncClient` 请求用户可控 URL：未校验内网地址（169.254.0.0/16、10.0.0.0/8、127.0.0.1）

---

## 维度 7 性能

### 异步性能
- `async def` 内 `time.sleep`/`requests.get`：阻塞事件循环（P1 级）
- `await` 链过长：串行 await 可并行的请求，应 `asyncio.gather`
- 连接池：`httpx.AsyncClient` 每请求新建（应用全局 client 或 `Depends`）
- `AsyncSession` 每请求新建 engine：应用全局 `create_async_engine`

### 响应序列化
- `response_model` 嵌套过深：序列化开销大，应投影或用 `response_model_exclude`
- 大列表无分页：`List[Model]` 返回全量，应分页或流式

---

## 维度 8 异步与并发

### 事件循环
- `asyncio.run()` 嵌套：在已有事件循环内再调 `asyncio.run()` 报错
- `loop = asyncio.get_event_loop()`（已废弃）：应用 `asyncio.run()` 或 `asyncio.get_running_loop()`
- `asyncio.create_task` 未持有引用：task 被 GC 中断，应赋值给变量或 `TaskGroup`

### 取消与异常
- `asyncio.gather(return_exceptions=False)`：一个失败全部取消，可能不符合预期
- `asyncio.wait_for` 超时后任务未真正取消：底层 task 仍运行
- `CancelledError` 误吞：`except Exception` 不捕获 `CancelledError`（继承 `BaseException`），但 `except:` 会

### 并发模型混用
- `async def` 路由内 `threading.Thread`：线程内访问事件循环资源出错
- `asyncio` 与 `Celery` 边界：应在 Celery task 内用同步代码，不混入 `asyncio.run`
- `run_in_executor` 滥用：CPU 密集任务应用 `ProcessPoolExecutor` 而非 `ThreadPoolExecutor`（GIL）

---

## 维度 9 资源管理

### 异步资源
- `async with` 未用：`aiohttp.ClientSession`/`httpx.AsyncClient`/`AsyncSession` 必须用 `async with` 或显式 `await close()`
- `asyncio.Lock`/`asyncio.Semaphore`：跨事件循环复用报错，应每循环新建
- `asyncio.Queue`：生产者消费者未配对，队列积压内存泄漏

### 依赖清理
- `Depends` 用 `yield` 的资源：异常路径清理是否执行取决于异常类型，`HTTPException` 会执行但 `Exception` 默认不执行
- `BackgroundTasks` 资源：任务内打开的资源在任务结束后是否关闭

---

## 维度 10 错误处理与可观测性

### 异常处理
- `@app.exception_handler(Exception)` 过宽：吞掉所有异常，应用专用异常类
- `HTTPException` 状态码：`404`/`403`/`422` 语义误用
- 未处理异常返回 500 带堆栈：生产应 `exception_handler` 统一处理，屏蔽堆栈

### 中间件
- 自定义中间件异常未捕获：中间件内异常直接 500 无日志
- 中间件顺序：CORS/认证/日志顺序影响行为

### 结构化日志
- `print` 代替 `logging`/`structlog`：无级别、无结构化字段、无法聚合
- `uvicorn`/`gunicorn` 日志：access log 格式未定制，缺少 request_id/trace_id

---

## 维度 12 接口与类型契约

### OpenAPI 一致性
- `response_model` 与实际返回类型不符：schema 漂移，前端契约失效
- 手写 `openapi()` 覆写：与自动生成不一致
- `examples` 缺失：OpenAPI 文档无示例，前端难以对接

### 版本管理
- URL 版本（`/api/v1/`）vs Header 版本：未统一
- 废弃路由：无 `deprecated=True` 标记

### 错误信封
- 错误响应格式不统一：`{"error": "..."}` vs `{"detail": "..."}` vs `{"message": "..."}`
- 应统一为 `{"error": {"code": "...", "message": "...", "details": {...}}}`
