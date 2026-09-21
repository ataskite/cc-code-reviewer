# OWASP 离线上游基线（不可变快照）

本目录是 cc-code-reviewer Security Control Catalog 的离线标准映射依据。**不可变**：正文不得修改、翻译或删段；任何更新只能走显式维护流程。

## 内容

| 目录 | 来源 | 版本/Revision | 许可证 |
|---|---|---|---|
| `asvs/5.0.0/` | OWASP ASVS 官方 release 资产（en JSON） | tag `v5.0.0_release` | CC-BY-SA-4.0 |
| `top10/2025/` | OWASP Top 10:2025 官方仓库 `2025/docs/en` | commit `66ebc4798d2c` | CC-BY-SA-4.0 |
| `api-top10/2023/` | OWASP API Security Top 10:2023 官方仓库 `editions/2023/en` | commit `e85ddfa5a936` | CC-BY-SA-4.0 |
| `nodejs-cheat-sheet/ef539da38a09/` | OWASP Cheat Sheet Series | commit `ef539da38a09`（12 位前缀目录名，完整 SHA 见 manifest） | CC-BY-SA-4.0 |

每个目录含 `NOTICE.md`（来源/版本/revision/抓取日期/许可证核验/原样保存声明）与 `SHA256SUMS`（对原始字节计算）；`manifest.json` 是唯一上游清单，`catalog/node-security-controls.json` 的 `upstream_manifest_sha256` 与其字节哈希强绑定。Top10 与 API Top10 的快照文件按本插件命名约定重命名（`introduction.md` / `A01.md`… / `API1.md`…），正文字节原样——映射关系见各 NOTICE。

## 边界

- **审查运行时零网络依赖**：本目录中的 URL 只用于来源审计与显式维护升级；任何 Skill、Agent、脚本不得在审查时访问外部 URL（`tests/security/test_offline_security_runtime.sh` 强制验证）。
- 上游原文不代表本插件立场；控制选择与映射由 `references/security/catalog/` 决定并逐条经本快照核验。
- 不宣称 OWASP 认证或 ASVS 全量合规；只能声明固定版本的控制映射与本轮覆盖状态。

## 升级流程（仅维护者显式执行）

```bash
# 1. 下载到显式 staging（只从 OWASP 官方域；失败不回退第三方镜像）
bash scripts/maintenance/update-owasp-baseline.sh --fetch owasp-top10 \
  --version 2025 --revision <commit-sha> --staging <dir>
# 2. 人工核验上游 LICENSE 后改写 staging/.source-meta/*.json 的 license（默认 UNVERIFIED，emit 会拒绝）
# 3. 为每个目录补 NOTICE.md，然后生成 SHA256SUMS + manifest.json
bash scripts/maintenance/update-owasp-baseline.sh --emit-manifest --staging <dir>
# 4. 离线核验 staging（复用完整完整性契约）
bash scripts/maintenance/update-owasp-baseline.sh --verify-only <dir>
# 5. 人工审阅差异后复制覆盖本目录，重算 catalog 的 upstream_manifest_sha256，
#    更新映射并跑 bash tests/security/test_security_upstream.sh 与全量测试
```

维护脚本绝不写入仓库、不自动改 catalog 映射、不自动提交、不 bump VERSION；Skill、Agent 与测试主流程绝不自动调用它。
