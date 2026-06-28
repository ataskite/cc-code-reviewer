#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/languages/java/plan-large-batches.sh
# 本文件仅为向后兼容旧调用路径，新代码请直接引用新路径。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/languages/java/plan-large-batches.sh" "$@"
