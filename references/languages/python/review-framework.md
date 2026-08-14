# Python 代码审查框架

本手册定义 Python 项目（Django / FastAPI / 通用 Python，服务端聚焦）代码审查的 12 个维度。维度与 Java 的 15 维度、前端的 12 维度结构完全独立，不编号、不映射。各模式的启用范围以"审查模式 × 维度覆盖矩阵"为准。

> 审查框架各语言独立。Java 框架见 `references/languages/java/review-framework.md`；前端框架见 `references/languages/frontend/review-framework.md`；本文件不引用任何其他语言的维度编号。

---

## 审查模式 × 维度覆盖矩阵

| 维度 | fast | standard | deep | security |
|---|:---:|:---:|:---:|:---:|
| 1 正确性 | ✅ | ✅ | ✅ | ✅ |
| 2 类型安全 | ✅ 仅 Any 逃逸+type:ignore 无注释 | ✅ | ✅ | - |
| 3 代码质量 | - | ✅ | ✅ | - |
| 4 框架规范 | ✅ 仅 Django/FastAPI 配置安全 | ✅ | ✅ | ✅ 仅配置安全子项 |
| 5 数据访问与 ORM | - | ✅ | ✅ | ✅ 仅 SQL 注入子项 |
| 6 安全 | ✅ 仅 P0 级 | ✅ | ✅ | ✅ 全深度 |
| 7 性能 | - | ✅ | ✅ | - |
| 8 异步与并发 | ✅ 仅阻塞调用+资源清理 | ✅ | ✅ | - |
| 9 资源管理 | ✅ | ✅ | ✅ | - |
| 10 错误处理与可观测性 | - | ✅ | ✅ | ✅ 仅敏感信息泄露 |
| 11 测试质量 | - | ✅ 仅核心测试缺失 | ✅ | - |
| 12 接口与类型契约 | - | ✅ 仅 RESTful+错误处理 | ✅ | ✅ 仅鉴权/错误信息 |

---

## 模式说明

- **fast**（快速扫雷）：仅扫描会直接炸产线或造成明显安全/稳定性风险的问题，聚焦正确性、类型安全（Any 逃逸+`type: ignore` 无注释）、Django/FastAPI 配置安全、异步阻塞调用与资源清理、P0 级安全问题（反序列化 RCE/eval/subprocess 注入/SQL 注入/secrets 硬编码）。适合 PR 合并前快速卡口。覆盖维度：1、2（部分）、4（部分）、6（P0）、8（部分）、9。
- **standard**（标准审查）：日常迭代推荐模式，覆盖维度 1-12，但 11 只查核心测试缺失、12 只查 RESTful+错误处理。适合迭代上线前的常规质量门禁。（11/12 部分启用。）
- **deep**（深度审查）：全量 12 维度，含测试质量和技术债深挖。适合大版本上线前或重要模块的系统性审查，耗时较长。覆盖维度：1-12 全开。
- **security**（安全专项）：聚焦安全核心（维度 6 全深度）及与安全强相关的交叉维度（配置安全、SQL 注入、敏感信息泄露、接口鉴权/错误信息）。类型安全在 security 关闭--类型问题是质量问题不是安全问题，不污染安全报告。覆盖维度：1、4（部分）、5（部分）、6、10（部分）、12（部分）。

---

## 技术栈识别与维度启用规则

| 技术栈 | 依赖指纹示例 | 建议启用维度 | 专项规则 |
|---|---|---|---|
| Django | `django` in pyproject.toml/setup.py/requirements.txt | 1, 4, 5, 6, 7, 10, 12 | ORM/middleware/signals/admin/CSRF/template/migration，见 `django-rules.md` |
| FastAPI | `fastapi` in dependencies | 1, 4, 5, 6, 8, 12 | DI/Pydantic/async/OpenAPI，见 `fastapi-rules.md` |
| SQLAlchemy | `sqlalchemy` in dependencies | 5, 6, 7 | Session 生命周期、ORM N+1、raw SQL 注入、连接池 |
| Django ORM | `django` + `models.Model` | 5, 6, 7 | queryset 懒加载、select_related/prefetch_related、事务 `atomic` |
| Celery | `celery` in dependencies | 8, 10 | 任务幂等、重试、超时、死信队列、broker 连接 |
| Redis | `redis`/`redis-py` in dependencies | 5, 7 | 连接池、pipeline、键过期、缓存击穿 |
| Pydantic | `pydantic` in dependencies | 2, 12 | 模型校验、v1/v2 差异、序列化漂移 |
| pytest | `pytest` in dev dependencies | 11 | fixture 设计、参数化、mock、async 测试 |
| mypy/Pyright | `[tool.mypy]`/`[tool.pyright]` in pyproject.toml | 2 | strict 模式、Any 收敛、泛型标注 |
| Ruff | `[tool.ruff]` in pyproject.toml | 3 | 规则集选择、 noqa 审计 |
| uv/poetry | `uv.lock`/`poetry.lock` | 6 | lockfile 提交、依赖审计 |
| pip | `requirements.txt` | 6 | 依赖锁定、pip-audit |

---

## 各维度详细审查标准

### 1. 正确性
- **可变默认参数**：`def f(items=[])` / `def f(config={})`--默认值在函数定义时求值一次，跨调用共享可变对象（Python 最高频陷阱之一）
- **异常吞咽**：`except: pass` / `except Exception: pass` 未记录或重新抛出
- **None/边界条件**：None 未检查、空序列、除零、索引越界、NaN
- **迭代器耗尽**：同一迭代器二次消费、`zip` 不等长未用 `strict`（Python 3.10+）
- **浅拷贝陷阱**：`copy.copy` 对嵌套对象共享引用、`list()` 浅拷贝字典值
- **闭包变量绑定**：lambda/闭包捕获循环变量延迟绑定（`for i in ...: lambda: i`）
- **整数除法**：`/` vs `//` 语义混淆、Python 2 残留 `from __future__ import division`
- **布尔陷阱**：`if x == None`（应 `is None`）、`if len(x)` 对 None 误判、`0`/`[]`/`{}` 的 falsy 歧义

### 2. 类型安全
- **Any 污染**：`Any` 逃逸到函数签名/返回值/Pydantic 模型字段，污染调用链
- **type: ignore 滥用**：`# type: ignore` 无注释说明、无 issue 链接、批量忽略未限定规则码
- **Optional 未窄化**：`Optional[X]` 返回值未做 None 检查直接解引用
- **泛型缺失**：`list`/`dict` 裸用而非 `list[int]`/`dict[str, Any]`、`Callable` 未标注签名
- **Protocol/TypedDict 误用**：Protocol 运行时检查 `isinstance` 误用、TypedDict 作为普通 dict 传递丢类型
- **类型断言**：`cast()` 滥用、`# type: ignore` 替代类型守卫
- **契约对齐**：公共 API 缺类型标注、前后端/服务间类型手动维护而非 codegen（OpenAPI/Pydantic schema）、响应类型与实际不符
- **mypy/Pyright 配置**：未启用 `strict` 或 `disallow_any_*`、`warn_unused_ignores` 未开

### 3. 代码质量
- **复杂度**：函数圈复杂度过高（`radon cc`）、嵌套超过 3 层、单函数超 80 行
- **命名规范**：函数/变量/类命名是否符合 PEP 8、是否使用模糊命名（`data`/`info`/`temp`）
- **DRY**：重复逻辑（Django view/DRF serializer 常见模板重复）
- **dataclass/attrs 滥用**：纯数据容器用 dataclass 合理，但行为丰富的类硬塞 dataclass 导致 `__post_init__` 膨胀
- **魔数**：硬编码数字/字符串未提取常量
- **PEP 8 偏离**：linter 之上的判断--过长行、不一致的引号、import 顺序混乱
- **循环依赖/跨层引用**：模块循环 import、view 层直接操作 DB、model 层依赖 view
- **过时依赖/临时代码**：Python 2 残留语法（`print` 语句、`xrange`）、`# TODO` 无期限

### 4. 框架规范
- **Django**：ORM 模型设计（`null=True`/`blank=True` 语义、`on_delete` 缺失）、middleware 顺序、signals 副作用、admin 配置暴露、CSRF 中间件、template 自动转义与 `mark_safe`、migration 质量与可回滚、`settings.py` 分环境配置
- **FastAPI**：依赖注入生命周期（`Depends` 作用域）、Pydantic 模型设计（`BaseModel` 字段校验、v1/v2 差异）、async 路由正确性（`async def` vs `def` 的线程池行为）、OpenAPI schema 生成与文档漂移、`BackgroundTasks` 误用
- **通用**：`pyproject.toml` 的 `requires-python`/`dependencies`/`[project.scripts]`、包结构（src layout vs flat）、`__init__.py` 滥用、`if __name__ == "__main__"` 入口

### 5. 数据访问与 ORM
- **SQL 注入**：f-string/`%`/`+` 拼接 SQL（`cursor.execute(f"SELECT ... {user_input}")`）、Django `extra()`/`raw()` 误用、SQLAlchemy `text()` 参数化缺失
- **N+1 查询**：Django queryset 懒加载导致循环查询、缺 `select_related`/`prefetch_related`；SQLAlchemy 关系懒加载在循环中触发
- **事务边界**：Django `@atomic` 作用域、SQLAlchemy session flush 时机、长事务持锁
- **连接泄漏**：SQLAlchemy session 未关闭、Django DB 连接未释放、`close_old_connections()` 缺失
- **迁移质量**：Django migration 可回滚性、数据迁移 vs schema 迁移混用、RunPython 无反向操作
- **批量操作**：循环 `save()` 而非 `bulk_create`/`bulk_update`、`delete()` 级联未评估

### 6. 安全
- **反序列化 RCE**：`pickle.loads`/`pickle.load`（CWE-502，可执行任意代码）、`marshal.loads`、`yaml.load` 未指定 `SafeLoader`（CWE-502）、`shelve.open`（内部用 pickle）、`jsonpickle.decode`、`dill`、含 `__reduce__` 的对象被反序列化
- **eval/exec**：`eval()`/`exec()` 处理用户输入、`ast.literal_eval` 应替代 `eval` 的场景误用
- **subprocess 注入**：`subprocess.run(shell=True)` + 用户输入（CWE-78）、`os.system`/`os.popen`
- **SQL 注入**：见维度 5
- **认证与授权缺失**：视图/路由/DRF viewset 缺鉴权装饰器或权限类、`@action` 未设 `permission_classes`、依赖全局配置但新接口未继承
- **对象级越权（IDOR）**：`Model.objects.get(id=...)`/`get_object_or_404` 未带 owner 过滤、queryset 未按当前用户/归属字段过滤、DRF 未重写 `get_queryset` 限定范围
- **多租户隔离**：queryset/写入未按租户/组织标识过滤、租户字段可被前端伪造、跨租户读写
- **secrets 硬编码**：API key/token/密码直接写在源码、`.env` 提交到版本库、secret 写入日志
- **路径穿越**：用户输入拼路径未规范化（`os.path.join` + `..`）、`open(user_path)` 未校验根目录
- **SSRF**：用户可控 URL（经任意 HTTP 客户端：`requests`/`httpx`/`aiohttp`/`urllib` 或自封装 client）访问内网/云元数据地址，未做协议与域名白名单；URL 可控性需跨文件追溯，不得仅凭变量名判断
- **XSS（Django 模板）**：`mark_safe`/`|safe` 过滤器渲染用户输入、Jinja2 `autoescape` 关闭
- **依赖漏洞（OWASP 2025 A03）**：lockfile 未提交、未运行 `pip-audit`/`safety`、`postinstall` 等价物（`setup.py` 的恶意钩子）、provenance 缺失
- **CSP**：Django CSP 头未配置、`X-Content-Type-Options`/`X-Frame-Options` 缺失
- **依赖风险结论规则**：见下文专节

### 7. 性能
- **O(n²) 循环**：嵌套循环、列表 `in` 查找（应用 set/dict）、字符串 `+=` 累加（应用 `"".join`）
- **不必要拷贝**：`list(dict.keys())` 多余、切片 `x[:]` 无意义拷贝、大对象传参未用引用
- **缺 generator**：`range(len(x))` 生成列表、大序列 `map` 结果立即 `list()`、应用 `yield` 的场景用 `return list`
- **GIL 阻塞**：CPU 密集任务在 async 事件循环中同步执行、未用 `run_in_executor`/`ProcessPoolExecutor`
- **大对象内存**：一次性读取大文件到内存（`f.read()`）、大 queryset 不分页、pandas DataFrame 不释放
- **ORM N+1**：见维度 5，性能视角
- **缓存缺失**：热点查询/计算结果未缓存、缓存键设计不当（击穿/雪崩）
- **数据结构误选**：队列用 `list.pop(0)`（O(n)，应用 `collections.deque`）、查找用 list（应用 set）

### 8. 异步与并发
- **async 中阻塞调用**：`async def` 内调用 `requests.get`/`time.sleep`/同步 DB 驱动--阻塞整个事件循环（asyncio 最高频事故）
- **task 取消/异常未处理**：`asyncio.gather` 未用 `return_exceptions`、`asyncio.create_task` 未持有引用（task 被 GC）、`CancelledError` 误吞
- **混用并发模型**：同模块混用 `threading`/`asyncio`/`multiprocessing`、async 代码中直接 `Thread`、asyncio 与 Celery 任务边界混乱
- **死锁/竞态**：`threading.Lock` 顺序不一致、asyncio 锁与线程锁混用、共享可变状态无保护
- **async 资源清理**：`async with` 未用、`aiohttp.ClientSession` 未关闭、`asyncio.create_task` 无超时
- **FastAPI async 正确性**：`async def` 路由调用同步阻塞 DB 驱动、`BackgroundTasks` 中跑长任务阻塞响应、`Depends` 缓存作用域误用
- **Celery 并发**：`worker_concurrency`/`worker_prefetch_multiplier` 配置、`acks_late` 与幂等、长任务无超时

### 9. 资源管理
- **context manager 未用**：`open()`/`connect()`/`lock` 未用 `with`、文件句柄泄漏
- **文件/连接未关闭**：`f = open(...)` 后异常路径未关闭、DB 连接未 `close()`、HTTP 连接池未释放
- **引用循环**：对象互相引用未用 `weakref`、`__del__` 误用导致 GC 延迟
- **finally 缺失**：资源获取后异常路径无 `finally` 释放
- **weakref 误用**：`weakref` 持有的对象在需要时已被 GC、`WeakValueDictionary` 误用导致缓存失效
- **临时文件/目录**：`tempfile` 未清理、`os.makedirs` 创建的目录无清理逻辑
- **线程/进程池**：`ThreadPoolExecutor`/`ProcessPoolExecutor` 未 `shutdown`、`with` 块外使用

### 10. 错误处理与可观测性
- **bare except**：`except:` 捕获所有异常（含 `KeyboardInterrupt`/`SystemExit`）、`except Exception` 过宽
- **异常吞咽**：`except ...: pass` 无日志、异常被捕获后只 log 不 reraise 导致问题隐藏
- **自定义异常**：业务异常未定义专用类、异常继承层级混乱（应继承 `Exception` 而非 `BaseException`）
- **全局错误处理**：Django middleware `process_exception`/FastAPI `exception_handler` 缺失、未统一错误响应格式
- **日志规范**：`print` 代替 `logging`、日志级别误用（`info` 打详细 trace）、日志格式无结构化字段
- **敏感信息**：日志/异常信息泄露 token/PII/密码、`DEBUG=True` 生产配置、Django `ADMINS` 邮件泄露堆栈；**间接泄露**：模型 `__str__`/`__repr__` 返回含 PII 被日志间接打印、DRF/Pydantic serializer 未对敏感字段设 `write_only=True`/`extra=kwargs`、`logger.error(repr(obj))` 把整对象（含敏感字段）序列化进日志
- **监控接入**：关键路径无 metrics、异常未上报 Sentry/Datadog、trace 缺失

### 11. 测试质量
- **standard** 仅检查：核心逻辑是否有对应测试、关键路径（鉴权/支付/状态机）测试缺失
- **deep** 存量审查：测试覆盖、核心逻辑、关键路径、mock 使用、边界测试、fixture 设计、参数化、async 测试（`pytest-asyncio`/`anyio`）、覆盖率门槛

### 12. 接口与类型契约
- **standard** 仅检查：RESTful 规范、错误处理、分页规范、FastAPI 路由入参契约
- **deep** 存量审查：RESTful、版本管理、错误处理、幂等、分页、接口文档（OpenAPI schema 与实现漂移）、类型契约一致性（Pydantic 模型与 DB 模型漂移、响应类型与实际不符）

---

## P0 分级门槛

**P0 五项硬门槛**（与 Java、前端一致，必须全部满足）：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。五项必须同时满足；任一不满足都不得标为 P0。

- 证据成立但影响未达到事故级或已有有效缓解机制：P1。
- 事故级风险尚缺生产可达性、调用链、运行配置或防护状态证据：待确认。
- 其他问题继续按影响进入 P2/P3。
- standard、deep、security 模式不得静默丢弃未通过 P0 门槛的候选；fast 按纯 P0 模式边界只输出 P0。

### 性能问题分级边界

- 已证实会造成系统性不可用、生产关键路径可达、缺少超时/限流/隔离/降级并必须阻断发布的性能事故级问题：P0。
- 关键路径性能风险且已证实会显著影响稳定性：P1。示例：async 路由中阻塞调用拖垮事件循环、ORM N+1 在高并发接口打爆 DB 连接池、长事务持锁导致死锁。
- 普通性能问题或局部性能风险：P2。示例：循环 `save()` 而非批量、缺 generator 导致内存峰值、列表 `in` 查找 O(n)、缺缓存。
- 泛优化建议且缺少明确风险链路：P3。示例：建议加缓存、建议补监控、建议优化算法但没有明确生产影响证据。
- 怀疑很严重但缺少生产路径、调用频率、运行配置、表结构、索引或执行计划证据：待确认。不得仅凭"可能慢""可能 N+1""可能打爆资源"的印象升级到 P1/P0。

## 依赖风险结论规则

依赖风险只有在 lockfile（`uv.lock`/`poetry.lock`/`requirements.txt` 带 hash）版本明确且证据可靠时才能形成确定性漏洞结论；否则必须归为待确认或依赖扫描建议，不得仅凭"版本较旧"的印象下漏洞结论。

---

*本手册版本：Python 1.1（Django + FastAPI + 通用 Python，12 维度独立集）*
*最后更新：2026-08-14*
