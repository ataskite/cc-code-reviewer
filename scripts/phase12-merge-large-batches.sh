#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/merge-batch-results.sh
# 合并逻辑（去重/门禁/覆盖率）已全部在 core/ 版本，且 core 版本已加 java_* 字段读时 fallback，
# 因此 Java 的 plan.json（total_java_loc 等）无需改字段名即可被正确读取。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/merge-batch-results.sh" "$@"
