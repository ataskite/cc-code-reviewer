<!-- 适用: **/{requirements*.txt,pyproject.toml} -->
# Python 依赖治理专项清单（requirements*.txt / pyproject.toml）

- 检查可复现性基线：只有无上界的 `>=` 范围规范而没有 poetry.lock/Pipfile.lock/uv.lock 时逐文件指出漂移面；存在 lockfile 时核对其生成来源与 pyproject 是否同步
- 排查已知漏洞版本快照：requests < 2.32.0（Cookie 头跨域泄漏）、urllib3 < 1.26.17 / < 2.0.7（重定向泄漏）、cryptography 旧 LTS 前系列、PyYAML 需配合调用面 SafeLoader 等；命中时给出安全修复版本建议
- 核对分层文件一致性：requirements-base/prod/dev 分层中同一坐标多版本并存或 prod 复制 dev 全集的膨胀面；逐层确认最终部署读取的是哪一份
- 确认私有源凭据落点：--extra-index-url/--index-url 内嵌 user:token@ 即密钥入库候选；http:// 明文源同样列候选
- 审视 VCS 直装形态：git+https 可变 ref（main/HEAD/@develop）缺 commit 固定即供应链候选；固定 tag 亦要求补充复核路径说明
- 检查 pyproject 元数据契约：[build-system] requires 未固定导致元数据构建不可复现；python 版本约束过宽（^3 跨大版本 ABI 断裂面）逐项标注
- 验证可选组边界：extras/all 组把调试工具、代理探针类组件拖进默认安装集的组合指出收窄方向
- 核对传递面污染：requirements 以 `pkg==x.y` 强制压回低于安全线的旧版、pyproject constraints 反向锁死上游补丁版本的冲突组合
- 检查打包内容边界：setuptools/hatch build 配置的 packages/include 白名单是否会把 `.env`、本地配置、密钥样例带进发布产物
