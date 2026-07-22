# Python 源码范围定义

本文件定义 Python 项目的正式源码、只读上下文和排除范围，用于审查覆盖率和批次规划口径。

## 正式源码（SOURCE_SCOPE:formal）

进入正式审查范围和文件覆盖率分母的源码：

- `src/**/*.py`（src layout）
- `<package>/**/*.py`（flat layout，顶层包目录下；含 `__init__.py` 的常规包，或不含 `__init__.py` 的 namespace package/PEP 420）
- 根级单文件应用入口：项目根下的 `app.py`、`main.py`、`wsgi.py`、`asgi.py`、`server.py`、`manage.py`（与 `src/` 或 flat 顶层包合并收集，覆盖 `main.py + app/`、`manage.py + project/` 等常见布局）
- 通用根级脚本：仅当项目既无 `src/`、flat 顶层包，也无上述白名单入口时，收集根目录其他生产 `.py`（如 `cli.py`、`worker.py`），继续排除测试和打包配置

## 正式配置（SOURCE_SCOPE:formal-config）

可产生正式配置问题，但**不进入 Python 源码文件覆盖率分母**：

- `pyproject.toml`、`setup.py`、`setup.cfg`
- `requirements*.txt`、`Pipfile`、`uv.lock`、`poetry.lock`、`Pipfile.lock`
- `tox.ini`、`pytest.ini`、Ruff/mypy/flake8 配置

这些路径由预扫描以 `FORMAL_CONFIG_FILE:<绝对路径>` 显式注入。分批审查时只由 `batch-001` 审查，避免重复发现。

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
