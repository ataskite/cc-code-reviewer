# Python 源码范围定义

本文件定义 Python 项目的正式源码、只读上下文和排除范围，用于审查覆盖率和批次规划口径。

## 正式源码（SOURCE_SCOPE:formal）

进入正式审查范围和文件覆盖率分母的源码：

- `src/**/*.py`（src layout）
- `<package>/**/*.py`（flat layout，顶层包目录下，含 `__init__.py`）

## 只读上下文（SOURCE_SCOPE:context）

可作为审查辅助参考，但**不产生正式问题**，也**不计入覆盖率分母**：

- `**/tests/**/*.py`、`test_*.py`、`*_test.py`、`conftest.py`（测试代码）
- `**/migrations/**/*.py`（Django/Alembic 生成代码，迁移质量在 deep 模式维度 5 评估，但不产生正式发现位置）

## 排除范围（SOURCE_SCOPE:excluded）

不进入任何审查环节：

- `**/venv/**`、`**/.venv/**`（虚拟环境）
- `**/__pycache__/**`（字节码缓存）
- `**/site-packages/**`（第三方库）
- `**/build/**`、`**/dist/**`、`**/.eggs/**`（构建产物）
- `**/node_modules/**`（前端依赖，混合仓库）
- `**/.tox/**`、`**/.pytest_cache/**`、`**/.mypy_cache/**`、`**/.ruff_cache/**`（工具缓存）

## 覆盖率口径

文件覆盖率 = 已审查的正式源码文件数 / `SOURCE_FILE_COUNT`（PROFILE_SCHEMA 中的生产源码总数）。只读上下文和排除范围不计入分母。
