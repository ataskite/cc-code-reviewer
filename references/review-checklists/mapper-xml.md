<!-- 适用: **/*mapper*.xml **/*dao*.xml -->
# MyBatis Mapper/DAO XML 专项清单（*mapper*.xml / *dao*.xml）

- 检查 `${}` 占位符：凡出现在 SQL 字符串中的 `${}` 都是字符串拼接点；确认每个 `${}` 的取值是否来自白名单常量/枚举映射，来自请求参数的按 SQL 注入列候选
- 排查动态表名/动态列名/动态排序字段拼接：`order by ${column}`、表名经参数传入时验证是否有枚举校验，缺失即注入选候选
- 核对 `<foreach>` 批量操作：批量 insert/update 是否在大集合场景缺少分片上限，单条 SQL 万级 bind 参数会触发数据库报错或内存膨胀
- 检查批量 delete/update 的 where 条件是否可被空集合绕过：foreach 生成恒真片段或外层未判空导致全表更新
- 审视 `resultMap` 与查询列的对应关系：结果集是否带出密码哈希、盐、手机号、身份证等敏感列而 DTO 未做脱敏裁剪
- 检查 `<sql>` 片段复用引入的隐性拼接：公共片段中的 `${}` 被多处引用放大注入面，逐引用点确认取值来源
- 核对 XML 内嵌 SQL 的 LIKE 模糊匹配是否手工拼 `%${kw}%` 而非参数化 concat；确认转义责任落在哪一层
- 验证 statement 类型：.Statement 与 .PREPARED 混用、自定义拦截器改写 SQL 时是否有新增拼接路径
- 检查执行超时与 fetchSize 缺失的大结果集全量加载：无 limit 无游标的导出类查询按性能与 OOM 候选处理
