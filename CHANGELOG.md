# Changelog

## 1.6.5 — 对标 OpenCodeReview：定向规则清单与批次可信治理

### 新增

- **文件类型定向规则清单**：新增 `scripts/core/filetype-rule-map.json`（16 条有序 pattern，first-match-wins、大小写不敏感）与 `references/review-checklists/*.md` 共 11 份清单文档（pom、gradle 构建、mapper XML、Spring 配置、日志配置、CI workflow、Dockerfile、OpenAPI/Swagger、npm package.json、Django 核心、Python 依赖）。`core/resolve-review-rules.sh` 解析项目规则时向 review-rules.json 叠加输出 `filetype_checklists` 组——pattern / checklist / doc / files 与清单全文 `content` 内嵌，无命中时整键缺省；映射缺失或零命中一律 fail-open 整体省略。三个 collector 增加伴随文件白名单层：Java 为模块构建描述符 + `src/main/resources` 定向模式 + CI/容器文件（硬上限 200，stderr `COMPANION_FILES_ADDED=N` 披露），前端并入各 package 根 package.json，Python 并入根 requirements*/pyproject.toml，保证 pattern 始终可触达。三个审查 agent 阶段 C 叠加执行命中的清单检查：ignore 冲突以 ignore 为准，无命中不引用。
- **跨批次内容指纹去重**：`core/merge-batch-results.sh` 的 `dedupe_issue_blocks()` 升级为内容指纹口径——身份键 = sha256(文件路径 ␀ 维度标签 ␀ 归一化证据行)。证据行归一与 relocate-findings.sh 同口径（trim → 剥 +/- → trim、空行全弃），路径按原字节保留（不做相对化/小写化），行号与措辞不入键；legacy 整块折叠键仅兜底「无 `- 文件：` 行且无闭合围栏」的块，`fp\0` 与 `legacy\0` 两类键空间隔离绝不互相命中。同一缺陷跨批次的措辞漂移不再重复计数。
- **批次失败归因枚举**：状态 JSON 的 `failed` / `partial` 必填 `"failure_class"` 字段（判不准写 `unknown`，`completed` 禁带），取值为封闭五值枚举 context_exhausted / tool_budget_exhausted / output_truncated / cancelled / unknown，禁止发明其他值。merge 侧解析次序为显式值恒优先（枚举外视为未填写）→ 缺失走确定性中文关键词回退（上下文|context→context_exhausted；工具|轮次|tool→tool_budget_exhausted；中断|截断|truncat→output_truncated；取消|cancel|interrupt|ctrl→cancelled）→ 其余落 `unknown`，错误文本为空同样归 `unknown`。
- **失败归因统计与重试提示**：`summary.json` 在 finding_count 后新增 `dedup` 去重统计对象（`input_findings` / `merged_duplicates` / `output_findings`，N=0 时整对象省略）并在覆盖说明区追加「跨批次去重」披露行；failed_batches 组后新增 `"failed_by_class"` 五键含零归因对象（零失败时整体省略，计数和恒等于 failed_batches）；run-manifest 的 failed/partial 条目写入解析后的枚举值；批次状态总览错误列展示为 `[短标签] 原error`；`core/show-batch-status.sh` footer 输出「失败归因」归因行与三类重试提示（工具预算耗尽/输出中断可原样重试，上下文耗尽建议拆批缩小范围，已取消先人工确认）——归因展示只采信显式声明、不做文本猜测。
- **续跑准入门禁**：两个分批 planner 写 plan.json 时记录 `rules_snapshot_sha256`（review-rules.json 字节哈希，shasum -a 256 → sha256sum → perl Digest::SHA 回退链）；新增 `scripts/core/validate-resume-input.sh <RUN_DIR> <PROJECT_DIR> [--rules]` 恢复门禁——exit 0 输出单行 `GATE_OK=<run_id>` 放行；exit 2 INPUT_CHANGED（快照哈希不符/冻结输入缺失/review_input_path 越出 RUN_DIR/plan 缺 review_input_sha256 一律 fail-closed）、exit 3 RULES_CHANGED（仅 --rules 校验；legacy 计划缺快照字段 = 固定串 'legacy run lacks rules snapshot' 且同样 fail-closed）、exit 4 FROZEN_INPUT_MISSING、exit 1 用法错误；非零时 stderr 含机器可 grep 的 `ERROR_<REASON>` 行与中文建议行。主 Skill 恢复流程强制带 --rules 接线：非零不得列出任何可调度批次，必须由用户确认重新规划并新建 RUN_DIR。

### 变更

- 三个审查 agent（Java / Frontend / Python）阶段 C 统一接线：新增「文件类型专项清单叠加（强制）」段——清单是聚焦透镜而非替代框架，不得借清单跳过常规维度、不得套用到未命中的文件；状态写入约定加入「中断归因枚举」表。SKILL.md 批次注入表披露 `filetype_checklists` 映射与 content 内嵌，合并步骤跨批去重说明同步为指纹口径，恢复流程接线准入门禁；契约测试钉住枚举封闭性、`failed_by_class` 稳态、`rules_snapshot_sha256` 落盘、门禁脚本存在性与 `filetype_checklists` 输出。

### 升级方式

三端插件 manifest 已指向 1.6.5。Claude Code / Codex / ZCode 用户重新加载插件即可（`/reload-plugins` 或对应入口）。

## 1.6.4 — 吸收 OpenCodeReview v1.10.0 第一梯队特性

### 新增

- **跨文件重归档**：新增 `scripts/core/relocate-findings.sh`。发现声明的文件与证据代码实际所在文件不一致时，先在声明文件内校正行号漂移；声明文件内找不到证据时，在 manifest 圈定的审查范围内逐行精确匹配，唯一命中才把位置（文件+行号）整体迁移到真实文件；0 处或多处命中保持原状（fail-open，绝不猜测）。`core/merge-batch-results.sh` 在去重前对纳入批次自动挂接该脚本（fail-open），`summary.json` 新增 `relocation` 对象，合并报告覆盖说明输出跨文件重归档统计行。
- **partial 部分完成批次**：批次状态枚举扩展为 5 值（pending/running/completed/failed/partial）。批次 agent 中途无法继续但已产出至少一条正式发现时，写入结果文件并把状态记为 `partial`（含 `finding_count` 与中断原因）；零产出才记 `failed`。`partial` 批次保持可调度、可整批重跑；合并时其已产出发现纳入正式结论（标注「部分完成已纳入」），覆盖统计保守不计，报告保持 `[阶段性]`，`summary.json` 新增 `partial_batches` / `partial_batch_ids`。
- **语义分组亲和分批**：`core/plan-file-batches.sh` 支持环境变量 `CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE`（TSV `<group_key>\t<file_path>`，仓库相对或绝对路径），分组单元按组亲和装箱（组优先于普通 FFD 顺序，预算硬限制优先）；清单缺失、不可读或零命中时整体退化为未启用（fail-open）。`plan.json` 披露 `semantic_grouping_enabled` / `semantic_groups_path`，batch json 在启用时输出 `semantic_group_ids`；Java 适配层透传同一环境变量。
- **增量审查语义分组清单**：主 Skill 在增量审查输入冻结后，仅依据 review-input 元数据（路径、增删行数、模块/目录、扩展名）自动生成语义分组清单（同模块同功能、接口+实现+调用点、测试+被测、i18n/配置变体、rename 对应物），写入 `$RUN_DIR/semantic-groups.tsv`：单 agent 增量路径作为「语义分组清单（可选，仅增量审查时提供）」注入子 agent，文件级分批路径导出给分批器做组亲和。不确定就不分组，单文件或 ≤3 个变更文件跳过，分组不改变审查范围。
- **组内次要文件覆盖义务**：三个审查 agent 新增逐文件覆盖义务（强制），批次结果模板以 `## 覆盖情况` 章节披露已审文件 N/M 与逐文件跳过原因；中途按 partial 结束时也必须如实标注未完整覆盖，次要文件不再可能被静默跳过。

### 变更

- **Agent 自校验升级为三层**：发现清单自校验在行号回抽（RE_LOCATION）与证伪过滤（REVIEW_FILTER）之外新增跨文件重归档层级（SELF_REFILED_COUNT）；披露行统一为 `自校验：行号修正 N 处、跨文件重归档 K 处、证伪移除 M 条（误报清道夫）`。
- **批次恢复与调度语义**：恢复未完成 `RUN_DIR` 时 `partial` 批次与 `pending` / `failed` 一样可调度（整批重跑）；`CURRENT_RUN_BATCH_LIMIT` 的候选批次集合同步包含 `partial`；`core/show-batch-status.sh` 将 `partial` 展示为可执行状态。
- **架构总览图去版本号**：架构总览主图固定为 `docs/assets/architecture-overview.png`（内容已含跨文件重归档 / partial 状态 / 语义分组亲和），HTML 源文件随仓库维护、改源码即可重渲染，不再随版本复制带水印的副本；README 引用同步切换，契约测试锁定无版本号引用并禁止回引 `architecture-overview-v*` 历史副本（v1.6.0/v1.6.2/v1.6.3/v1.6.4 等旧图全部清理）。

### 升级方式

三端插件已指向 1.6.4。Claude Code / Codex / ZCode 用户重新加载插件即可（`/reload-plugins` 或对应入口）。

## 1.6.3 — 安全设计不变量审查

### 变更

- **安全模式识别从词表升级为语义不变量推理**：Java、前端和 Python Agent 不再通过预置类名、方法名或字段名清单定义跨文件安全风险。安全维度启用时，大模型基于代码真实行为识别受保护动作、授权证据、完整状态空间、逐状态控制流和边界传播，并主动寻找“未获得明确授权证据仍到达受保护动作”的反例路径。Java Default Deny / Fail-Closed 的 S1–S4 同步改为明确授权、状态完备、逐状态结果和编排默认行为四项设计不变量。
- **单 Agent 复用结构化 review units**：新增 `core/prepare-review-context.sh`，从不可变 `REVIEW_INPUT_PATH` 的 `selected=true` 文件生成 import/直接依赖关联单元并注入三类 Agent。脚本只组织上下文，不识别安全语义、不生成候选问题；分批路径复用相同关联数据，正式范围仍由冻结输入或批次边界决定。
- **回归门禁**：新增中性命名的结构关联测试和提示词契约，防止 Default Deny 识别重新退化为方法名词表。

## 1.6.2 — 跨文件风险信号机制（三语言）+ 分批门槛统一 1M + 大仓分支检测修复

### 变更

- **跨文件风险信号机制三语言统一 + Python 越权检查点补缺**：把上版"default-deny 专用信号"泛化为通用「跨文件风险信号」（A 关卡/判定函数、B 归属/权限语义、C 外部输入达 sink、D 序列化/字符串化边界），Java/前端/Python 三个 agent 统一落地——阶段 C 命中信号即激活安全维度（不依赖文件类型/类名），阶段 D 命中 A/B 强制跨文件追踪、C/D 追溯后定级且不得直接丢弃。修复 OWASP A01 服务端越权/IDOR/多租户在 Python 框架的**完全缺失**（补 dim6 检查点 + Phase D 越权 grep）；Java/前端/Python 多处检查点去名词化（SSRF 去客户端 API 名绑定、敏感字段去固定字段名清单、认证爆破去 URL 关键词、业务竞态去场景列举、XSS 补间接 sink、env 泄露去前缀绑定、反序列化补 shelve/jsonpickle/dill）；三语言补间接信息泄露（`toString`/`__str__`/序列化边界）。框架版本：Java 5.7、前端 2.5、Python 1.1。
- **Java default-deny 检测改为语义信号驱动（维度 5.8）**：将 default-deny / fail-open 的识别从「按类名（`*Filter`/`*Security`）识别鉴权中间件」重构为「按代码语义信号识别」。新增 S1–S4 四个与命名无关的代码信号（准入判定函数 / null→放行 / 语义重载 / 编排无兜底），命中即激活检查。修复名为 Service/Strategy/Handler 的鉴权链节点 fail-open 漏检（如 `RouteDealServiceImpl` 这类实现鉴权编排接口、却以 Service 命名的类）。`agents/cc-code-reviewer.md` 阶段 C 新增「语义信号维度升级」规则、阶段 D 新增 S3/S4 命中时强制跨文件追踪，打破「单文件内看不出问题→不追踪→永远拿不到跨文件证据」的死循环。审查框架版本 5.5 → 5.7。
- **自动分批门槛提升到 100 万估算 token**：所有存量审查仅在 `estimated_tokens > 1000000` 时开启 batch；等于 100 万仍走单 agent。Maven 多模块不再使用 `REVIEW_LINE_COUNT >= 120000` 作为独立触发条件。文件级 planner 的单批输入预算仍保持 `500000`，与自动触发阈值分离。
- **大仓分支检测 SIGPIPE 修复**：`scripts/core/detect-branches.sh` 不再用 `git for-each-ref | head -5`——大仓分支输出超过管道缓冲（64KB）时，`head` 提前关闭管道会让 git 收到 SIGPIPE(141)，在 `set -e` 下导致检测脚本异常退出（Linux 大仓复现）。改用 `--count=5` 在 git 层面限量，并对 `branch --show-current` 加 `|| true` 兜底分离头指针/老版本 git 的非 0 退出。`tests/test_phase2_git_branches.sh` 补充 >5 分支的回归测试。

### 修复

- **架构图水印修正**：v1.6.1/v1.6.2 的架构总览图此前直接复制 v1.6.0 图，图内标题水印仍为「v1.6.0」。已将 `architecture-overview-v1.6.2.png` 标题水印修正为 v1.6.2，并清理仓库中无引用的历史架构图副本（v1.4.0/v1.5.0/v1.6.1）。
- **报告版本同步**：`references/report-format.md` 报告版本同步 Java 框架版本 5.5 → 5.7，并新增契约测试锚定「报告版本必须与 Java 框架版本同步」，防止再次脱钩。
- **前端间接泄露检查点补缺**：前端框架维度 9 补显式「间接泄露」检查点（`console.log`/`console.error` 生产未剥离、Sentry `extra`/`contexts` 整对象上报、埋点 payload 携带含 token 的 URL query 或整页 state），对齐 Java 5.3 与 Python 维度 10 的既有模式，为 agent 信号 D 提供显式落点。前端框架版本 2.4 → 2.5。
- **补齐 MIT LICENSE 文件**：三端 manifest 与 README License 段均已声明 MIT，但仓库根目录缺少 LICENSE 文件，补齐标准 MIT 文本并新增契约测试锁定「LICENSE 存在且 manifest 声明 MIT」。

### 升级方式

三端插件已指向 1.6.3。Claude Code / Codex / ZCode 用户重新加载插件即可（`/reload-plugins` 或对应入口）。

## 1.6.1 — Java 外网漏洞审查补强 + 小仓跳过分批

### 新增

- **Java 安全审查维度补强（维度 5）**：针对外网应用高频漏洞新增专项检查与分级边界，确保外网可达的高危漏洞能被扫出并定级为 P0。
  - **5.8 外网暴露面与常见 Web 漏洞**：新增子维度，覆盖 8 项外网高频漏洞——XSS（服务端拼接）、CSRF、开放重定向、CORS 配置错误、HTTP 安全响应头、认证爆破与用户枚举、**Default Deny / Fail-Closed（默认拒绝）**、业务逻辑竞态（安全视角）。
  - **5.3 数据保护脱敏分层**：强化「数据保护与敏感信息」子维度，新增 FII（First-Party Identifiable Information）分层脱敏要求，覆盖存储脱敏、传输脱敏、日志脱敏、第三方外传脱敏四层，要求 DTO 序列化用统一序列化器而非逐处手写。
  - **安全问题分级边界**：新增五段式分级（P0/P1/P2/P3/待确认），明确外网可达且证据完整的 RCE（反序列化、命令注入、SSRF 打云元数据）、认证绕过、水平越权、SQL 注入、存储型 XSS = P0；内网可达或需前置条件 = P1。同步到 `agents/cc-code-reviewer.md`，对齐性能分级边界的双份模式。
  - **契约测试加固**：`tests/test_contract_docs.sh` 新增 5 条断言，保护「安全问题分级边界」及其分级条目，对称于性能分级边界的契约保护。
- **Maven 多模块小仓库跳过分批**：新增 `scripts/core/decide-batch-mode.sh`，在步骤 4 确认 `REVIEW_SCOPE` 后按当前范围重算规模。只有 `estimated_tokens > 500000` 或 `REVIEW_LINE_COUNT >= 120000` 时才进入步骤 4B 选择分批策略；几千行的小型多模块仓库直接使用单 agent，不再强制分批。
  - 交互状态机新增 `current_scope_sizing` 状态（`runtime/contract.md`），位于 `review_scope` 之后、`optional_batch_strategy` 之前。
  - `STOCK_REVIEW_STRATEGY` 默认为 `single-agent`，只有当前范围达到大仓门槛后步骤 4B 才可能设为 `module-sequential` 或 `ai-planned`。
  - 全量审查必须显示「全部模块」，不得显示「所选模块」。

### 修复

- 修正 FastAPI CORS 规则表述：`allow_origins=["*"]` + `allow_credentials=True` 会被浏览器拒绝 credentialed CORS，通常属于配置/功能错误；真正的安全风险是反射任意 Origin 或过宽 Origin 白名单同时允许 credentials。
- 架构图引用更新为 `architecture-overview-v1.6.0.png`。

### 变更

- **交互状态机顺序调整**：`model_profile` 后移至 `current_scope_sizing` 与 `optional_batch_strategy` 之后、`optional_batch_count` 之前——模型选择必须在分批判定之后，但小仓跳过 4B 时模型仍先于批次规划。
- **Java 审查框架版本**：`references/languages/java/review-framework.md` 5.4 → 5.5；`references/report-format.md` 报告版本同步 5.4 → 5.5。

### 升级方式

三端插件已指向 1.6.1。Claude Code / Codex / ZCode 用户重新加载插件即可（`/reload-plugins` 或对应入口）。

## 1.6.0 — 吸收 OpenCodeReview 精华

### 新增

- **发现清单自校验（反思两阶段）**：三个审查 agent（Java / Frontend / Python）在生成报告前，新增"第四步：发现清单自校验"，吸收阿里 OpenCodeReview 的 RE_LOCATION + REVIEW_FILTER 思想：
  - **行号回抽校验**：对带具体 `file:line` 的发现，用 Read 工具回抽 ±3 行验证证据代码真实存在；行号漂移则修正，证据缺失则降级为待确认项（不直接删除）。
  - **证伪式过滤**：对每条发现执行"只证伪、不证实"复核——只有当可见代码证据直接构成反证时才移除，凡需 diff 外信息才能判定的评论一律放行。遵循"宁可放过，不可错杀"原则。
  - **fail-open 哲学**：自校验失败的问题保留原状，自校验只会让结果变好或不变，绝不会让结果变没。
- **Maven 大仓依赖图亲和分批**：`plan-large-batches.sh` 启用此前已采集但未参与装箱的 `module_dependency_edges`。有依赖边的模块在装箱时 cost 容差放宽 15%（等价约 ×0.87 折扣），LOC 硬上限不变且 cost 始终钳制在 `HARD_MAX_BATCH_COST=325000` 内。batch.json 的 `affinity_edges` 不再写死空数组，改为输出批次内实际命中的依赖边；plan.json 新增 `affinity_enabled: true` 标记。
- **不可变审查协议**：新增 `prepare-review-input.sh` 与 `review-input.json`，冻结 Git 基准、selected/excluded 文件、变更类型、选中文件/行数统计和内容指纹；单 Agent 展示规模与正式范围使用同一冻结输入，文件级与 Maven 大仓批次也将其写入 `RUN_DIR`。合并新增 `run-manifest.json`，从计划文件和终态结果生成逐文件 completed / failed / leftover 覆盖账本，不从 Markdown 反推。
- **项目级审查规则**：新增 `.cc-code-reviewer/review-rules.yml` 与确定性解析器。规则只为路径增加检查重点，绝不等同 ignore、绝不隐藏发现或改变严重级别门槛。
- **保守关联文件单元**：文件级分批新增 `review-units.json`，只把直接相对 import、Python 同包 import、无歧义 Java class import 保持在同一批；无法可靠识别时保持单文件单元。
- **Java 单 Agent 正式源码清单**：新增 `languages/java/collect-source-files.sh`，使小仓/指定模块存量审查也能在启动前冻结 `src/main/java` 文件边界；Java / Frontend / Python 的单 Agent 路径统一注入 `REVIEW_INPUT_PATH` 和基于 selected 文件解析的 `REVIEW_RULES_RESOLVED_PATH`。
- **默认源码排除口径对齐**：Java / Frontend / Python 的正式源码清单默认排除 `__snapshots__`、`testdata`、`fixtures` 与常见生成文件；Java 规划统计与 manifest 使用同一过滤口径，避免分母和实际审查范围漂移。
- **覆盖契约增强**：`run-manifest.json` 保留兼容的逐文件 `coverage`，覆盖路径统一为仓库相对路径；`item_id` 基于规范化仓库身份、语言和相对路径生成，在不同 clone/workspace 以及等价 HTTPS/SSH remote 下保持一致，并新增 `coverage_sets`（selected/completed/reused/failed/waived/leftover）、typed failure class、`terminal_state`、输入模式和覆盖比例。

### 修复

- 修复前端 `../shared/...` 及 Python 多级相对 import 未进入同一保守审查单元的问题；解析时对真实候选文件执行规范化，不再依赖保留 `..` 的文本路径。
- 修复旧示例仍使用 100k token 阈值、模型选择晚于批次/并发选择，以及 README 前端维度仍写 11 项的文档漂移。

### 变更

- **Agent 流程重编号为连续七步制**：原"第一步→第二步→第二步之后→第三步→第三步之后→第四步"重编为"第一步→第七步"连续编号，消除"第X步之后"半正式表述。新映射：ignore（原第二步之后）→第三步，生成报告（原第三步）→第五步，持久化（原第三步之后）→第六步，最终汇总（原第四步）→第七步，反思自校验插入为第四步。
- **跨文件引用同步**：`references/report-format.md` 中"第三步（生成审查报告）"更新为"第五步"。

### 不在本轮范围

- 不新增独立反思脚本或独立 LLM 调用（反思嵌入同一 agent 同一上下文）。
- 不接入 CI/PR/MR webhook 或多 SCM 自动触发；当前仍由显式 Skill 调用启动审查。

## 1.5.0 — 三端 Agent 插件兼容

### 新增

- **三平台分发**：同一 Git 仓库现可被 Claude Code、Codex CLI/Desktop 和 ZCode 安装。新增 `.codex-plugin/plugin.json`、`.zcode-plugin/plugin.json`、`.agents/plugins/marketplace.json` 原生清单；版本由 `VERSION` 单一真相源驱动。
- **运行时适配层（`runtime/`）**：新增平台无关契约 `runtime/contract.md` 与三端适配器 `runtime/claude-code.md` / `runtime/codex.md` / `runtime/zcode.md`，定义 `PLUGIN_ROOT`、人工确认状态机、模型档位和子 Agent 调度的跨平台映射。
- **清单校验脚本**：新增 `scripts/core/validate-plugin-manifests.sh`，校验三端清单名称、版本、repository 和 code-fix 关键字一致性。
- **三端兼容契约测试套件（`tests/runtime/`）**：9 个新测试覆盖发布基线、清单契约、Skill 元数据、PLUGIN_ROOT 契约、跨平台交互、模型档位、Agent 调度、能力发现和分发门禁。

### 变更

- **插件根目录中立化**：活跃 Skill 中 `${CLAUDE_PLUGIN_ROOT}` 替换为平台无关 `${PLUGIN_ROOT}`；三端统一从根 Skill 资源位置推导并校验插件根目录。
- **Skill 元数据补齐**：三个 Skill 增加稳定 `name` 字段（`cc-code-reviewer` / `cc-code-ignore` / `cc-code-fixer`）。
- **Agent 模型去绑定**：三个共享 Agent Prompt 移除 `model: sonnet` 硬编码，改为平台无关 `MODEL_PROFILE` 档位（`inherit` / `economy` / `balanced` / `maximum`）。
- **跨平台人工确认**：三个 Skill 声明平台无关交互契约；`INTERACT` 由各 runtime adapter 映射，Codex / ZCode 执行等价逐步确认状态机。
- **Codex 官方 schema 对齐**：`.codex-plugin/plugin.json` 显式声明 `skills: "./skills/"`、完整 interface 和 default prompts；Git Marketplace 条目补齐 source、policy 与 category。
- **ZCode 原生 schema 对齐**：`.zcode-plugin/plugin.json` 使用官方优先 manifest 与 `skills: "skills"`；1.5.0 不依赖仅记录但不执行的 `agents` manifest 字段。
- **能力发现中立化**：`detect-lark-plugin.sh` 与 `detect-superpowers.sh` 的 Skill 搜索根覆盖 `.claude` / `.agents` / `.codex` / `.zcode` 四端。
- **文档更新**：README 首屏改为"三平台代码审查与修复插件"，分别提供三端安装、更新和卸载说明；AGENTS.md / CLAUDE.md 同步三端架构与执行契约。

### 已知限制

- **Codex IDE Extension**：插件安装不在 1.5.0 承诺范围，当前以 CLI/Desktop 为正式支持面。
- **ZCode 插件 Beta**：插件体系仍为 Beta，Git 自定义 Marketplace 是 1.5.0 的正式分发路径。
- 不新增 Windows 支持。

### 升级方式

- Claude Code：`claude plugin update cc-code-reviewer@cc-code-reviewer`
- Codex：重新 `codex plugin add cc-code-reviewer@cc-code-reviewer`
- ZCode：Settings → Plugins 刷新 Marketplace 并更新

---

## 1.4.3 及更早

参见 Git 历史。
