# Changelog

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
