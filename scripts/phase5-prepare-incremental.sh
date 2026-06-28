#!/bin/bash
# 兼容转发 wrapper —— 已迁移至 scripts/core/prepare-incremental.sh
# 本文件仅为向后兼容旧调用路径，新代码请直接引用新路径。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/core/prepare-incremental.sh" "$@"
