# Java Code Reviewer Plugin

> **⚠️ 平台说明**：本插件为 **Claude Code 专用插件**，基于 Claude Code 的 Agent 机制和 Plugin 规范开发。

企业级 Java 代码审查插件，支持 15 个维度全面审查，4 种审查模式，增量/存量两种审查类型，支持交互式和快速启动两种使用方式。

## 特性

- **15 维度全面审查**：正确性、代码质量、安全、性能、架构等
- **4 种审查模式**：fast（快速扫雷）、standard（日常推荐）、deep（大版本上线）、security（安全专项）
- **2 种审查类型**：增量审查（最近 N 次提交）、存量审查（全量/指定模块）
- **2 种使用模式**：交互式（逐步引导）、快速启动（自动化/CI/CD）
- **飞书集成**：审查报告上传云文档、问题清单录入多维表格（可选，依赖 lark-cli）
- **跨平台脚本**：macOS/Linux 使用 Bash，Windows 使用 PowerShell，无 Python 依赖

## 安装

### 通过插件市场安装（推荐）

```bash
# 1. 添加插件市场
claude plugin marketplace add ataskite/cc-code-reviewer

# 2. 安装插件
claude plugin install cc-code-reviewer

# 3. 启动 Claude Code 会话后重载插件
/reload-plugins
```

安装成功后，可用 Claude Code 的快速引用格式 `/cc-code-reviewer:cc-code-reviewer` 明确触发本 skill；也可以直接告诉 Claude Code 要审查 Java 项目，由自然语言匹配触发。

### 更新插件

```bash
# 更新到最新版本（在终端执行，非 Claude Code 会话内）
claude plugin update cc-code-reviewer

# 2. 重载插件
/reload-plugins
```

### 前置条件

- Claude Code 已安装
- macOS/Linux：Bash 3.0+ 环境
- Windows：Windows PowerShell 5.1+ 或 PowerShell 7+
- 系统已安装 `git` 命令

### 可选：lark-cli 安装

如需使用飞书上传功能（云文档/多维表格），需安装 `lark-cli` 并启用 `lark-doc`、`lark-base` 技能：

```bash
npm install -g @larksuite/cli
npx skills add larksuite/cli -y -g
lark-cli config init
lark-cli auth login --recommend
```

未安装 lark-cli 不影响审查功能，仅无法上传飞书。详细安装指南见 [lark-cli README](https://github.com/larksuite/cli/blob/main/README.zh.md)。

---

## 使用方式

插件支持两种使用模式：**交互式模式**（默认）和**快速启动模式**（适合自动化）。

### 方式一：快速引用触发（推荐）

使用 Claude Code 的 `/插件名:技能名` 快速引用格式，可以明确触发本技能：

```
# 本地项目
/cc-code-reviewer:cc-code-reviewer /path/to/project

# Git 仓库
/cc-code-reviewer:cc-code-reviewer https://github.com/org/repo.git
/cc-code-reviewer:cc-code-reviewer git@github.com:org/repo.git
```

也可以直接用自然语言触发，例如：`帮我审查 /path/to/project`。

交互流程：
1. **预扫描**（自动）：项目识别 → 分支探测 → 项目扫描 → lark-cli 检测
2. **逐步确认**（使用 AskUserQuestion 工具）：
   - 选择分支（条件步骤，仅多分支时询问）
   - 选择审查类型（增量/存量）
   - 选择审查范围（条件步骤，取决于审查类型和项目类型）
   - 选择审查模式（fast/standard/deep/security）
   - 选择飞书上传选项（条件步骤，仅飞书上传能力可用时询问）
   - 确认执行计划
3. 确认后启动子 Agent 执行审查

> **交互规则**：使用 Claude Code 的 AskUserQuestion 工具进行结构化交互，每个步骤单独询问，提供清晰的选项供用户选择。

### 方式二：快速启动

通过 `--` 参数直接传入全部配置，跳过交互，适合定时任务和 CI/CD：

```
帮我审查 /path/to/project --mode <模式> --type <类型> --scope <范围>
```

#### 参数说明

| 参数 | 必填 | 取值 | 说明 |
|------|------|------|------|
| `--mode` | 必填 | `fast` / `standard` / `deep` / `security` | 审查模式 |
| `--type` | 必填 | `incremental` / `stock` | 增量审查 / 存量审查 |
| `--scope` | 条件必填 | 正整数 或 `full` 或模块名 | 增量时为提交次数；存量多模块时为模块名；存量单模块可省略 |
| `--branch` | 可选 | 分支名 | 审查分支，默认当前分支 |
| `--upload` | 可选 | `no` / `doc` / `bitable` / `both` | 飞书上传，默认 `no` |

#### 快速启动示例

```bash
# 最简用法：增量快速扫雷，仅显示报告
帮我审查 /path/to/project --mode fast --type incremental --scope 5

# 存量全量审查，标准模式，上传飞书云文档
帮我审查 /path/to/project --mode standard --type stock --scope full --upload doc

# 指定模块存量审查，深度模式，同时上传云文档+多维表格
帮我审查 /path/to/project --mode deep --type stock --scope user-service,order-service --upload both

# Git 仓库 + 指定分支
帮我审查 https://github.com/org/repo.git --mode standard --type incremental --scope 3 --branch develop --upload bitable

# 定时任务场景（最简形式）
帮我审查 /path/to/project --mode fast --type incremental --scope 1
```

> **注意**：快速启动模式下，必填参数缺失会直接报错终止，不会降级为交互式模式。

---

## 审查模式

| 模式 | 覆盖维度 | 适用场景 | 预估耗时 |
|------|---------|---------|---------|
| `fast` | 正确性、事务与配置安全、资源管理、P0级安全 | PR 合并前快速卡口 | 2-8 分钟 |
| `standard` | 1-11、14(部分)、15(部分) | 日常迭代上线前推荐 | 5-25 分钟 |
| `deep` | 全量 1-15 维度 | 大版本上线前、重要模块 | 10-60 分钟 |
| `security` | 安全核心 + 强相关交叉维度 | 安全合规检查、安全加固 | 5-35 分钟 |

## 15 个审查维度

| # | 维度 | 说明 |
|---|------|------|
| 1 | 正确性 | Bug、NPE、边界条件、异常处理、并发正确性 |
| 2 | 代码质量 | 单一职责、DRY、复杂度、命名、代码异味 |
| 3 | Spring Boot 规范 | 分层职责、依赖注入、事务、配置安全 |
| 4 | 数据库/数据访问 | 通用数据库、MyBatis、JPA/Hibernate、批量操作、数据一致性 |
| 5 | 安全 | 注入风险、对象级越权、租户隔离、敏感信息、文件/反序列化、JWT/会话、依赖供应链 |
| 6 | 性能 | 并发安全、线程池、算法复杂度、限流降级 |
| 7 | 资源管理 | 连接关闭、线程泄露、OOM风险 |
| 8 | 日志/可观测性 | 日志级别、敏感信息、健康检查 |
| 9 | 测试质量 | 覆盖率、核心逻辑测试、Mock使用 |
| 10 | 技术债 | 临时代码、过时API、设计模式 |
| 11 | 架构 | 模块化、耦合度、全局错误处理 |
| 12 | 分布式系统 | 分布式事务、分布式锁、服务间通信、熔断限流 |
| 13 | 消息队列 | 消息可靠性、幂等性、顺序性、死信队列 |
| 14 | 缓存 | 穿透/击穿/雪崩、一致性、Redis专项 |
| 15 | API 设计 | RESTful规范、版本管理、错误处理、分页 |

## 飞书多维表格

审查问题可录入飞书多维表格，包含 18 个字段：

- **基础字段（15个）**：问题编号、严重级别、所属维度、技术栈、问题描述、位置、置信度、证据、影响、修复建议、修复状态、审查模式、审查日期、负责人、备注
- **预留修复字段（3个）**：修复时间、修复分支、修复人（初始留空，供后续修复流程更新）

## 脚本说明

所有脚本位于 `scripts/` 目录，可独立运行测试。macOS/Linux 使用 `.sh`，Windows 使用 `.ps1`。

```bash
# 项目识别
bash scripts/phase1-detect-project.sh "/path/to/project"

# 分支探测
bash scripts/phase2-detect-branches.sh "/path/to/project"

# 项目预扫描
bash scripts/phase3-project-scan.sh "/path/to/project"

# lark-cli 检测
bash scripts/phase4-detect-lark-plugin.sh
```

```powershell
# 项目识别
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\phase1-detect-project.ps1 "C:\path\to\project"

# 分支探测
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\phase2-detect-branches.ps1 "C:\path\to\project"

# 项目预扫描
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\phase3-project-scan.ps1 "C:\path\to\project"

# lark-cli 检测
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\phase4-detect-lark-plugin.ps1
```

其中 `phase1-detect-project.sh` / `phase1-detect-project.ps1` 会额外输出 `PROJECT_SOURCE=local|git-cache`，供后续分支切换阶段判断是否允许自动切换。本地项目目录若存在未提交改动，会保留当前分支继续审查；Git 缓存目录仍允许自动切换分支。

## 测试

提交前优先运行完整 Bash 测试套件：

```bash
bash tests/run_all.sh
```

当前测试覆盖：
- `phase1-detect-project.sh`：本地路径识别、缺失路径失败输出
- `phase2-detect-branches.sh` / `phase2-switch-branch.sh`：Git 分支探测、本地干净工作区切换、本地脏工作区保护
- `phase3-project-scan.sh`：Maven 多模块扫描、包含空格的模块路径、unknown 项目行数统计
- `phase4-detect-lark-plugin.sh`：lark-cli 可用/不可用输出契约
- `phase5-prepare-incremental.sh`：最近 N 次提交覆盖到首提交时的 diff 边界
- 文档契约：主 skill 参数完整性、报告文件持久化、飞书 Base 字段去重、测试入口说明

`tests/run_all.sh` 会按文件名顺序执行 `tests/test_*.sh`，最后运行 `git diff --check` 检查空白问题。PowerShell 脚本与 Bash 脚本保持同源逻辑；在 Windows 上修改 `.ps1` 后，应额外用 `powershell -NoProfile -ExecutionPolicy Bypass -File ...` 手动验证对应脚本。

## 工作流程

```
用户触发
  ↓
模式判定（检测 --mode 参数）
  ├─ 交互式模式（默认）            ├─ 快速启动模式
  ↓                                ↓
预扫描（4脚本顺序执行）            预扫描（4脚本顺序执行）
  ↓                                ↓
交互式确认（6步，严格单步）         参数校验
  ↓                                ↓
执行计划确认                        直接执行
  └──────────┬─────────────────────┘
             ↓
      代码审查阶段：子 Agent 执行审查
             ↓
      飞书上传（可选）
             ↓
      展示审查结果
```

## 开发与维护

### 修改脚本逻辑
1. 同步编辑 `scripts/` 下对应的 `.sh` 与 `.ps1` 文件
2. 分别在 macOS/Linux 与 Windows 环境独立测试验证
3. 无需修改 `skills/cc-code-reviewer/SKILL.md`（脚本通过路径引用），除非新增或调整脚本调用契约

### 修改审查流程
1. 编辑 `skills/cc-code-reviewer/SKILL.md` 中对应阶段的描述
2. 如需新脚本，在 `scripts/` 目录创建

### 修改审查维度或提示词
1. 审查框架：编辑 `references/review-framework.md`
2. Agent 提示词：编辑 `agents/cc-code-reviewer.md`
3. 确保模式×维度矩阵在两个文件中保持一致

## License

MIT
