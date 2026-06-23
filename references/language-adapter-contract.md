# Language Adapter Contract

本文件定义语言适配器与共享内核之间的标准协议。预扫描采用版本化的 key=value 输出。

## Java 字段 → 公共字段映射（兼容桥）

| Java 现有输出 | 公共中性字段 | 说明 |
|---|---|---|
| `Java文件总数`（phase3 文本行） | `source_file_count` | 仅 src/main/java 生产源码 |
| `代码总行数` | `source_line_count` | 仅 src/main/java |
| `MODULE:` 行 | `COMPONENT:` 行 | 公共层只保存展示 |
| `TECH_STACK:` 行 | `TECH_STACK:` 行 | 透传，公共层不解释 |
| phase10 输出 | `CODE_INTELLIGENCE_PROVIDER` | jdtls-lsp / none |

> Java 适配器在迁移前（Phase 4 之前）继续输出原有字段；公共层在 Phase 1 引入兼容映射。完整 PROFILE_SCHEMA v1 定义见「Phase 1」段。

（Phase 1 将补充 PROFILE_SCHEMA 完整定义、适配器职责与 schema version 处理规则。）
