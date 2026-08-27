<!-- 适用: **/.github/workflows/*.{yml,yaml} **/Jenkinsfile **/.gitlab-ci.yml -->
# CI 流水线专项清单（.github/workflows、Jenkinsfile、.gitlab-ci.yml）

- 检查 `pull_request_target` 触发：on: pull_request_target 与 checkout 到 PR head 的组合等于让外部 PR 代码以仓库 secrets 运行；确认 privileged 步骤只跑在 base 分支上下文
- 排查 secrets 泄漏面：secrets.X 被拼进 run 命令行/echo/日志、写入文件后未清理、经 artifact 上传带出；确认敏感值仅走 env 注入并避免子命令回显
- 核对第三方 action 未锁 SHA：uses 引用仅到 tag 或分支（尤其非官方 owner）时可被移动投毒；要求 pin 到 commit SHA 并说明升级流程
- 确认 workflow 顶层/任务级 permissions 是否最小化：默认写权限（contents: write 等）下运行不可信代码的放大效应逐项指出
- 审视缓存投毒面：actions/cache / sccache 缓存键可被同仓库低权限分支污染并在发布流水线命中时，指出键隔离与 restore-keys 风险
- 检查 Jenkinsfile：脚本式 pipeline 中 sh/git 参数插值是否引入 Groovy 注入；凭据绑定是否用 withCredentials 且未 echo
- 核对 GitLab CI 变量传递：job 级 variables 继承 masked/protected 配置缺失导致 runner 日志明文；镜像 tag 用 $CI_COMMIT_REF_NAME 可被分支名注入
- 确认构建产物与部署链路：自托管 runner 复用于不可信项目、deploy job 对 PR fork 开放的环境门控是否成立
- 验证动态执行点：curl | bash、远端脚本未校验 checksum 签名即执行的供应链缺口逐一列出
