<!-- 适用: **/Dockerfile* -->
# Dockerfile 专项清单（Dockerfile / Dockerfile.*）

- 检查基础镜像是否使用 latest/未固定 digest：latest 让构建不可复现并可在镜像仓被替换投毒；建议固定具体 tag 并附 digest
- 核对运行用户：最终阶段缺 `USER` 非 root 声明即列候选；确认应用目录与端口权限匹配非 root 运行
- 排查密钥进层：ARG/COPY/env 内嵌数据库口令、token、私钥、.npmrc/.docker/config.json 凭据会被层缓存永久保留；确认密钥走 BuildKit secret/挂载且不在中间层残留
- 审视 ADD 与 COPY 误用：ADD 拉远端 URL 或自动解压引入不可审计产物；敏感构建上下文（.git、.env）经 .dockerignore 缺失进入镜像
- 确认多阶段构建：编译期工具链/源码未被裁剪进运行层时指出体积与攻击面收益
- 检查包管理器收尾：apt/apk 更新后未清缓存可接受；但锁版本缺失导致依赖漂移逐项标注
- 审视 HEALTHCHECK：长驻服务未声明 HEALTHCHECK 仅作低危提示，不占 P0/P1 高危位；有编排层探针时可判豁免并在报告注明
- 核对信号处理：ENTRYPOINT 以 shell 形式包裹导致 PID 1 不收 SIGTERM 的优雅停机缺陷
- 验证端口与网络：EXPOSE 与实际监听不一致、0.0.0.0 绑定管理端口的暴露面说明
