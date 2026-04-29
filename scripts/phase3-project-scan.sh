#!/bin/bash
# 阶段三：项目预扫描
# 用途：快速了解项目规模、模块分布和项目类型，完成单模块/多模块判断

set -e

PROJECT_DIR="${1:?请输入项目路径}"

java_stats() {
  local root_dir="$1"
  local build_exclude="$2"
  local count=0
  local lines=0
  local file
  local file_lines

  while IFS= read -r -d '' file; do
    count=$((count + 1))
    file_lines=$(wc -l < "$file" | tr -d ' ')
    lines=$((lines + file_lines))
  done < <(find "$root_dir" -name '*.java' -not -path "$build_exclude" -not -path '*/.git/*' -print0 2>/dev/null)

  echo "$count|$lines"
}

relative_dir() {
  local dir="$1"
  if [ "$dir" = "$PROJECT_DIR" ]; then
    echo ""
  else
    echo "/${dir#$PROJECT_DIR/}"
  fi
}

collect_maven_poms() {
  find "$PROJECT_DIR" -maxdepth 3 -name 'pom.xml' -not -path '*/target/*' -print0 2>/dev/null
}

collect_gradle_builds() {
  find "$PROJECT_DIR" -maxdepth 3 -name 'build.gradle*' -not -path '*/build/*' -print0 2>/dev/null
}

detect_maven_dependency() {
  local pattern="$1"
  local match
  match=$(collect_maven_poms | xargs -0 grep -Eoh "$pattern" 2>/dev/null | head -1 || true)
  if [ -n "$match" ]; then
    echo "$match"
  fi
}

detect_gradle_dependency() {
  local pattern="$1"
  local match
  match=$(collect_gradle_builds | xargs -0 grep -Eoh "$pattern" 2>/dev/null | head -1 || true)
  if [ -n "$match" ]; then
    echo "$match"
  fi
}

emit_tech_stack() {
  local name="$1"
  local detector="$2"
  local pattern="$3"
  local dimensions="$4"
  local rules="$5"
  local evidence
  evidence=$("$detector" "$pattern")
  if [ -n "$evidence" ]; then
    echo "TECH_STACK:${name}|dependency:${evidence}|dimensions:${dimensions}|rules:${rules}"
    return 0
  fi
  return 1
}

scan_dependency_tech_stack() {
  local detector="$1"
  local fallback_reason="$2"
  local emitted=0

  echo ""
  echo "=== 技术栈识别 ==="
  emit_tech_stack "Spring Boot" "$detector" 'spring-boot-starter[-A-Za-z0-9]*' "3,5,8" "启用 Spring Boot 规范、配置安全、运行时暴露检查" && emitted=1
  emit_tech_stack "Spring MVC" "$detector" 'spring-boot-starter-web|spring-webmvc' "1,3,5,8,15" "启用 Controller/API、输入校验、错误响应和 REST 规范审查" && emitted=1
  emit_tech_stack "WebFlux/Reactor" "$detector" 'spring-boot-starter-webflux|reactor-core' "1,3,5,6,7,8,15" "启用响应式链路、阻塞调用、超时和资源释放审查" && emitted=1
  emit_tech_stack "MyBatis" "$detector" 'mybatis-spring-boot-starter|mybatis-plus-boot-starter|mybatis-[A-Za-z0-9_.-]+' "4,5,6" "启用 MyBatis Mapper/XML、参数绑定、动态 SQL、分页和结果映射审查" && emitted=1
  emit_tech_stack "MyBatis Plus" "$detector" 'mybatis-plus-[A-Za-z0-9_.-]+' "4,5,6" "启用 MyBatis Plus Wrapper、分页插件、批量操作和逻辑删除审查" && emitted=1
  emit_tech_stack "JPA/Hibernate" "$detector" 'spring-boot-starter-data-jpa|hibernate-core|hibernate-entitymanager|jakarta.persistence-api|javax.persistence-api' "4,5,6" "启用 JPA Repository、实体映射、懒加载、N+1、事务边界和批量写入审查" && emitted=1
  emit_tech_stack "Redis/Cache" "$detector" 'spring-boot-starter-data-redis|spring-cache|redisson|jedis|lettuce-core' "6,7,12,14" "启用缓存穿透/击穿/雪崩、一致性、Redis key/连接池和分布式锁审查" && emitted=1
  emit_tech_stack "Kafka" "$detector" 'spring-kafka|kafka-clients' "12,13" "启用消息可靠性、消费者幂等、顺序性、重试和死信审查" && emitted=1
  emit_tech_stack "RabbitMQ" "$detector" 'spring-boot-starter-amqp|amqp-client|spring-rabbit' "12,13" "启用消息确认、持久化、重试、死信和消费幂等审查" && emitted=1
  emit_tech_stack "RocketMQ" "$detector" 'rocketmq-spring-boot-starter|rocketmq-client' "12,13" "启用消息可靠性、消费幂等、顺序消息和重试策略审查" && emitted=1
  emit_tech_stack "OpenFeign" "$detector" 'spring-cloud-starter-openfeign|feign-core' "6,8,12" "启用服务间调用、超时、重试、降级、鉴权透传和日志脱敏审查" && emitted=1
  emit_tech_stack "Dubbo" "$detector" 'dubbo-spring-boot-starter|dubbo' "6,8,12" "启用 RPC 超时、重试、服务降级、接口幂等和认证审查" && emitted=1
  emit_tech_stack "Spring Security" "$detector" 'spring-boot-starter-security|spring-security-[A-Za-z0-9_.-]+' "3,5,8,15" "启用认证授权、对象级越权、CSRF、会话和安全配置审查" && emitted=1
  emit_tech_stack "Shiro" "$detector" 'shiro-[A-Za-z0-9_.-]+' "5,8,15" "启用认证授权、权限注解、会话和越权审查" && emitted=1
  emit_tech_stack "JWT" "$detector" 'jjwt|java-jwt|nimbus-jose-jwt' "5,8,15" "启用 JWT 签名、过期、刷新、撤销和敏感信息审查" && emitted=1
  emit_tech_stack "Validation" "$detector" 'spring-boot-starter-validation|hibernate-validator|jakarta.validation-api|javax.validation' "1,3,5,15" "启用 Bean Validation、输入边界和 API 参数校验审查" && emitted=1
  emit_tech_stack "Actuator" "$detector" 'spring-boot-starter-actuator' "3,5,8" "启用管理端暴露、健康检查、指标和敏感端点审查" && emitted=1
  emit_tech_stack "Seata" "$detector" 'seata-[A-Za-z0-9_.-]+' "4,12" "启用分布式事务、回滚边界、幂等和补偿机制审查" && emitted=1
  emit_tech_stack "Resilience4j/Sentinel" "$detector" 'resilience4j-[A-Za-z0-9_.-]+|sentinel-[A-Za-z0-9_.-]+' "6,8,12" "启用熔断、限流、降级和异常兜底审查" && emitted=1

  if [ "$emitted" -eq 0 ]; then
    echo "TECH_STACK:未识别|dependency:none|dimensions:1,2,5,7,10|rules:${fallback_reason}"
  fi
}

# 检测项目类型并执行相应扫描
if [ -f "$PROJECT_DIR/pom.xml" ]; then
  # Maven项目扫描
  echo "=== 项目概况 ==="
  echo "项目类型: Maven"
  STATS=$(java_stats "$PROJECT_DIR" '*/target/*')
  JAVA_COUNT="${STATS%%|*}"
  JAVA_LINES="${STATS##*|}"
  echo "Java文件总数: $JAVA_COUNT"
  echo "代码总行数: $JAVA_LINES"
  echo ""

  # 检测是否为多模块项目（关键判断，后续阶段直接使用PROJECT_TYPE变量）
  # 排除 XML 注释中的 <modules> 标签，避免误判
  IS_MULTI_MODULE=$(sed '/<!--.*-->/d' "$PROJECT_DIR/pom.xml" 2>/dev/null | grep -c '<modules>' || true)
  if [ "$IS_MULTI_MODULE" -eq 0 ]; then
    echo "模块类型: 单模块项目"
    echo "PROJECT_TYPE=maven-single"
  else
    echo "模块类型: 多模块项目"
    echo "PROJECT_TYPE=maven-multi"
  fi

  echo ""
  echo "=== 模块结构 ==="
  while IFS= read -r -d '' pom_file; do
    dir="${pom_file%/pom.xml}"
    rel=$(relative_dir "$dir")
    # 单模块项目：跳过根目录自身（rel 为空），避免输出空 MODULE 行
    if [ -z "$rel" ]; then
      root_stats=$(java_stats "$dir" '*/target/*')
      root_count="${root_stats%%|*}"
      root_lines="${root_stats##*|}"
      echo "├── (root)  [${root_count} 类, ${root_lines} 行]"
      continue
    fi
    module_stats=$(java_stats "$dir" '*/target/*')
    java_count="${module_stats%%|*}"
    lines="${module_stats##*|}"
    if [ "$java_count" -gt 0 ]; then
      depth=$(echo "$rel" | tr -cd '/' | wc -c | tr -d ' ')
      indent=$(printf '%*s' $((depth * 2)) '')
      echo "${indent}├── ${rel##*/}  [${java_count} 类, ${lines} 行]"
      echo "MODULE:${rel##*/}|${rel}|${java_count}|${lines}"
    fi
  done < <(find "$PROJECT_DIR" -maxdepth 3 -name 'pom.xml' -not -path '*/target/*' -print0)

  scan_dependency_tech_stack "detect_maven_dependency" "未从 pom.xml 依赖识别出专项技术栈，仅启用通用 Java 审查规则"

elif [ -f "$PROJECT_DIR/build.gradle" ] || [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
  # Gradle项目扫描
  echo "=== 项目概况 ==="
  echo "项目类型: Gradle"
  STATS=$(java_stats "$PROJECT_DIR" '*/build/*')
  JAVA_COUNT="${STATS%%|*}"
  JAVA_LINES="${STATS##*|}"
  echo "Java文件总数: $JAVA_COUNT"
  echo "代码总行数: $JAVA_LINES"
  echo ""

  # 检测是否为多模块项目（通过settings.gradle判断）
  # 排除注释行，避免误判
  if [ -f "$PROJECT_DIR/settings.gradle" ] || [ -f "$PROJECT_DIR/settings.gradle.kts" ]; then
    SETTINGS_FILE=$(ls "$PROJECT_DIR"/settings.gradle* 2>/dev/null | head -1)
    INCLUDE_COUNT=$(sed '/^\s*\/\//d' "$SETTINGS_FILE" 2>/dev/null | grep -c 'include' || true)
    if [ "$INCLUDE_COUNT" -gt 0 ]; then
      echo "模块类型: 多模块项目"
      echo "PROJECT_TYPE=gradle-multi"
    else
      echo "模块类型: 单模块项目"
      echo "PROJECT_TYPE=gradle-single"
    fi
  else
    echo "模块类型: 单模块项目"
    echo "PROJECT_TYPE=gradle-single"
  fi

  echo ""
  echo "=== 模块结构 ==="
  while IFS= read -r -d '' build_file; do
    dir="${build_file%/build.gradle*}"
    rel=$(relative_dir "$dir")
    if [ -z "$rel" ]; then
      root_stats=$(java_stats "$dir" '*/build/*')
      root_count="${root_stats%%|*}"
      root_lines="${root_stats##*|}"
      echo "├── (root)  [${root_count} 类, ${root_lines} 行]"
      continue
    fi
    module_stats=$(java_stats "$dir" '*/build/*')
    java_count="${module_stats%%|*}"
    lines="${module_stats##*|}"
    if [ "$java_count" -gt 0 ]; then
      depth=$(echo "$rel" | tr -cd '/' | wc -c | tr -d ' ')
      indent=$(printf '%*s' $((depth * 2)) '')
      echo "${indent}├── ${rel##*/}  [${java_count} 类, ${lines} 行]"
      echo "MODULE:${rel##*/}|${rel}|${java_count}|${lines}"
    fi
  done < <(find "$PROJECT_DIR" -maxdepth 3 -name 'build.gradle*' -not -path '*/build/*' -print0)

  scan_dependency_tech_stack "detect_gradle_dependency" "未从 build.gradle/build.gradle.kts 依赖识别出专项技术栈，仅启用通用 Java 审查规则"
else
  echo "=== 项目概况 ==="
  echo "❌ 未检测到 Maven (pom.xml) 或 Gradle (build.gradle) 构建文件"
  echo "PROJECT_TYPE=unknown"
  echo ""
  STATS=$(java_stats "$PROJECT_DIR" '*/target/*')
  JAVA_COUNT="${STATS%%|*}"
  echo "Java文件总数: $JAVA_COUNT"
  echo ""
  echo "=== 技术栈识别 ==="
  echo "TECH_STACK:未识别|dependency:none|dimensions:1,2,5,7,10|rules:未检测到 Maven/Gradle 构建文件，仅启用通用 Java 审查规则"
fi
