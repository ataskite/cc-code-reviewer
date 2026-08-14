# Changelog

## 1.6.2 — 跨文件风险信号机制（三语言）+ 分批门槛统一 1M + 大仓分支检测修复

### 变更

- **跨文件风险信号机制三语言统一 + Python 越权检查点补缺**：把上版"default-deny 专用信号"泛化为通用「跨文件风险信号」（A 关卡/判定函数、B 归属/权限语义、C 外部输入达 sink、D 序列化/字符串化边界），Java/前端/Python 三个 agent 统一落地——阶段 C 命中信号即激活安全维度（不依赖文件类型/类名），阶段 D 命中 A/B 强制跨文件追踪、C/D 追溯后定级且不得直接丢弃。修复 OWASP A01 服务端越权/IDOR/多租户在 Python 框架的**完全缺失**（补 dim6 检查点 + Phase D 越权 grep）；Java/前端/Python 多处检查点去名词化（SSRF 去客户端 API 名绑定、敏感字段去固定字段名清单、认证爆破去 URL 关键词、业务竞态去场景列举、XSS 补间接 sink、env 泄露去前缀绑定、反序列化补 shelve/jsonpickle/dill）；三语言补间接信息泄露（`toString`/`__str__`/序列化边界）。框架版本：Java 5.7、前端 2.4、Python 1.1。
- **Java default-deny 检测改为语义信号驱动（维度 5.8）**：将 default-deny / fail-open 的识别从「按类名（`*Filter`/`*Security`）识别鉴权中间件」重构为「按代码语义信号识别」。新增 S1–S4 四个与命名无关的代码信号（准入判定函数 / null→放行 / 语义重载 / 编排无兜底），命中即激活检查。修复名为 Service/Strategy/Handler 的鉴权链节点 fail-open 漏检（如 `RouteDealServiceImpl` 这类实现鉴权编排接口、却以 Service 命名的类）。`agents/cc-code-reviewer.md` 阶段 C 新增「语义信号维度升级」规则、阶段 D 新增 S3/S4 命中时强制跨文件追踪，打破「单文件内看不出问题→不追踪→永远拿不到跨文件证据」的死循环。审查框架版本 5.5 → 5.7。
- **自动分批门槛提升到 100 万估算 token**：所有存量审查仅在 `estimated_tokens > 1000000` 时开启 batch；等于 100 万仍走单 agent。Maven 多模块不再使用 `REVIEW_LINE_COUNT >= 120000` 作为独立触发条件。文件级 planner 的单批输入预算仍保持 `500000`，与自动触发阈值分离。
- **大仓分支检测 SIGPIPE 修复**：`scripts/core/detect-branches.sh` 不再用 `git for-each-ref | head -5`——大仓分支输出超过管道缓冲（64KB）时，`head` 提前关闭管道会让 git 收到 SIGPIPE(141)，在 `set -e` 下导致检测脚本异常退出（Linux 大仓复现）。改用 `--count=5` 在 git 层面限量，并对 `branch --show-current` 加 `|| true` 兜底分离头指针/老版本 git 的非 0 退出。`tests/test_phase2_git_branches.sh` 补充 >5 分支的回归测试。

### 修复

- **架构图水印修正**：v1.6.1/v1.6.2 的架构总览图此前直接复制 v1.6.0 图，图内标题水印仍为「v1.6.0」。已将 `architecture-overview-v1.6.2.png` 标题水印修正为 v1.6.2，并清理仓库中无引用的历史架构图副本（v1.4.0/v1.5.0/v1.6.1）。
- **报告版本同步**：`references/report-format.md` 报告版本同步 Java 框架版本 5.5 → 5.7，并新增契约测试锚定「报告版本必须与 Java 框架版本同步」，防止再次脱钩。

### 升级方式

三端插件已指向 1.6.2。Claude Code / Codex / ZCode 用户重新加载插件即可（`/reload-plugins` 或对应入口）。

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
