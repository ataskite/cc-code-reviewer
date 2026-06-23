# Shared Review Framework（公共维度定义）

公共层定义 15 个稳定维度 ID，语言适配器负责映射为语言专属展示名称。公共 ID 用于内核、Ignore、合并与未来扩展，不要求所有语言使用完全相同的具体规则。

| 公共 ID | 名称（中性） | Java 展示名 | 前端展示名 |
|---|---|---|---|
| D01_CORRECTNESS | 正确性 | 正确性 | 正确性 |
| D02_MAINTAINABILITY | 代码质量 | 代码质量 | 代码质量 |
| D03_PLATFORM_PRACTICES | 平台规范 | Spring Boot 规范 | React Hooks/渲染/组件规范 |
| D04_DATA_STATE | 数据与状态 | 数据库与数据访问 | 状态管理与数据请求 |
| D05_SECURITY | 安全 | 安全 | 安全 |
| D06_PERFORMANCE | 性能 | 性能 | 性能 |
| D07_RESOURCE_LIFECYCLE | 资源生命周期 | 资源管理 | 副作用与资源清理 |
| D08_OBSERVABILITY | 可观测性 | 日志/可观测性 | 错误监控与可观测性 |
| D09_TESTING | 测试质量 | 测试质量 | 测试质量 |
| D10_TECH_DEBT | 技术债 | 技术债 | 技术债 |
| D11_ARCHITECTURE | 架构 | 架构 | 组件边界与架构 |
| D12_DISTRIBUTED_INTEGRATION | 分布式集成 | 分布式系统 | 跨端集成（首期弱化） |
| D13_ASYNC_EVENTS | 异步事件 | 消息队列 | 异步与事件 |
| D14_CACHE_CONSISTENCY | 缓存一致性 | 缓存 | 客户端缓存一致性 |
| D15_INTERFACE_CONTRACT | 接口契约 | API 设计 | 接口/类型契约 |

**规则**：
- Java 报告继续使用原有用户可见名称，公共 ID 用于内核、Ignore、合并与未来扩展。
- 语言适配器的具体规则与模式矩阵定义在各自 `references/languages/<id>/review-framework.md`。
- 横切关注点（如错误处理、安全）会在多个维度出现：按维度语义分别判断，同一代码片段触发多个风险时可合并为一条并在"所属维度"中标注多个维度。
