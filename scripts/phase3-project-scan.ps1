# 阶段三：项目预扫描
# 用途：快速了解项目规模、模块分布和项目类型，完成单模块/多模块判断

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"

function Test-PathSegment {
    param([string]$Path, [string]$Segment)
    $escaped = [regex]::Escape($Segment)
    return $Path -match "[/\\]$escaped([/\\]|$)"
}

function Get-JavaStats {
    param([string]$RootDir, [string]$ExcludePattern)
    $count = 0
    $lines = 0
    $javaFiles = Get-ChildItem -Path $RootDir -Filter "*.java" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PathSegment $_.FullName $ExcludePattern) -and $_.FullName -notmatch '\.git[/\\]' }
    foreach ($file in $javaFiles) {
        $count++
        $lines += (Get-Content $file.FullName | Measure-Object -Line).Lines
    }
    return "$count|$lines"
}

function Get-RelativeDir {
    param([string]$Dir)
    if ($Dir -eq $ProjectDir) {
        return ""
    } else {
        $rel = $Dir.Substring($ProjectDir.Length)
        return $rel
    }
}

function Get-MavenPomFiles {
    Get-ChildItem -Path $ProjectDir -Filter "pom.xml" -Recurse -File -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PathSegment $_.FullName "target") }
}

function Get-GradleBuildFiles {
    Get-ChildItem -Path $ProjectDir -Filter "build.gradle*" -Recurse -File -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PathSegment $_.FullName "build") }
}

function Find-MavenDependency {
    param([string]$Pattern)
    foreach ($pom in Get-MavenPomFiles) {
        $content = Get-Content $pom.FullName -Raw -ErrorAction SilentlyContinue
        $match = [regex]::Match($content, $Pattern)
        if ($match.Success) {
            return $match.Value
        }
    }
    return $null
}

function Find-GradleDependency {
    param([string]$Pattern)
    foreach ($buildFile in Get-GradleBuildFiles) {
        $content = Get-Content $buildFile.FullName -Raw -ErrorAction SilentlyContinue
        $match = [regex]::Match($content, $Pattern)
        if ($match.Success) {
            return $match.Value
        }
    }
    return $null
}

function Write-TechStack {
    param(
        [string]$Name,
        [string]$Detector,
        [string]$Pattern,
        [string]$Dimensions,
        [string]$Rules
    )
    if ($Detector -eq "maven") {
        $evidence = Find-MavenDependency $Pattern
    } else {
        $evidence = Find-GradleDependency $Pattern
    }
    if ($evidence) {
        Write-Output "TECH_STACK:$Name|dependency:$evidence|dimensions:$Dimensions|rules:$Rules"
        return
    }
}

function Find-DockerFile {
    $files = Get-ChildItem -Path $ProjectDir -Recurse -File -Depth 4 -ErrorAction SilentlyContinue |
        Where-Object {
            -not (Test-PathSegment $_.FullName "target") -and
            -not (Test-PathSegment $_.FullName "build") -and
            $_.FullName -notmatch '\.git[/\\]' -and
            ($_.Name -eq "Dockerfile" -or $_.Name -like "Dockerfile.*" -or $_.Name -eq "docker-compose.yml" -or $_.Name -eq "docker-compose.yaml")
        }
    $first = $files | Select-Object -First 1
    if ($first) {
        return (Get-RelativeDir $first.FullName).TrimStart('\', '/')
    }
    return $null
}

function Find-KubernetesFile {
    $files = Get-ChildItem -Path $ProjectDir -Recurse -File -Depth 5 -ErrorAction SilentlyContinue |
        Where-Object {
            -not (Test-PathSegment $_.FullName "target") -and
            -not (Test-PathSegment $_.FullName "build") -and
            $_.FullName -notmatch '\.git[/\\]' -and
            (
                (Test-PathSegment $_.FullName "k8s") -or
                (Test-PathSegment $_.FullName "kubernetes") -or
                $_.Extension -eq ".yaml" -or
                $_.Extension -eq ".yml"
            )
        }
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match '(?m)^(apiVersion|kind):') {
            return (Get-RelativeDir $file.FullName).TrimStart('\', '/')
        }
    }
    return $null
}

function Write-FileTechStack {
    param(
        [string]$Name,
        [string]$Detector,
        [string]$Dimensions,
        [string]$Rules
    )
    if ($Detector -eq "docker") {
        $evidence = Find-DockerFile
    } else {
        $evidence = Find-KubernetesFile
    }
    if ($evidence) {
        Write-Output "TECH_STACK:$Name|dependency:file:$evidence|dimensions:$Dimensions|rules:$Rules"
        return
    }
}

function Write-DependencyTechStackScan {
    param([string]$Detector, [string]$FallbackReason)
    $emitted = $false

    Write-Output ""
    Write-Output "=== 技术栈识别 ==="
    $checks = @(
        @("Spring Boot", 'spring-boot-starter[-A-Za-z0-9]*', "3,5,8", "启用 Spring Boot 规范、配置安全、运行时暴露检查"),
        @("Spring MVC", 'spring-boot-starter-web|spring-webmvc', "1,3,5,8,15", "启用 Controller/API、输入校验、错误响应和 REST 规范审查"),
        @("WebFlux/Reactor", 'spring-boot-starter-webflux|reactor-core', "1,3,5,6,7,8,15", "启用响应式链路、阻塞调用、超时和资源释放审查"),
        @("MyBatis", 'mybatis-spring-boot-starter|mybatis-plus-boot-starter|mybatis-[A-Za-z0-9_.-]+', "4,5,6", "启用 MyBatis Mapper/XML、参数绑定、动态 SQL、分页和结果映射审查"),
        @("MyBatis Plus", 'mybatis-plus-[A-Za-z0-9_.-]+', "4,5,6", "启用 MyBatis Plus Wrapper、分页插件、批量操作和逻辑删除审查"),
        @("JPA/Hibernate", 'spring-boot-starter-data-jpa|hibernate-core|hibernate-entitymanager|jakarta.persistence-api|javax.persistence-api', "4,5,6", "启用 JPA Repository、实体映射、懒加载、N+1、事务边界和批量写入审查"),
        @("Redis/Cache", 'spring-boot-starter-data-redis|spring-cache|redisson|jedis|lettuce-core', "6,7,12,14", "启用缓存穿透/击穿/雪崩、一致性、Redis key/连接池和分布式锁审查"),
        @("Kafka", 'spring-kafka|kafka-clients', "12,13", "启用消息可靠性、消费者幂等、顺序性、重试和死信审查"),
        @("RabbitMQ", 'spring-boot-starter-amqp|amqp-client|spring-rabbit', "12,13", "启用消息确认、持久化、重试、死信和消费幂等审查"),
        @("RocketMQ", 'rocketmq-spring-boot-starter|rocketmq-client', "12,13", "启用消息可靠性、消费幂等、顺序消息和重试策略审查"),
        @("OpenFeign", 'spring-cloud-starter-openfeign|feign-core', "6,8,12", "启用服务间调用、超时、重试、降级、鉴权透传和日志脱敏审查"),
        @("Dubbo", 'dubbo-spring-boot-starter|dubbo', "6,8,12", "启用 RPC 超时、重试、服务降级、接口幂等和认证审查"),
        @("Spring Security", 'spring-boot-starter-security|spring-security-[A-Za-z0-9_.-]+', "3,5,8,15", "启用认证授权、对象级越权、CSRF、会话和安全配置审查"),
        @("Shiro", 'shiro-[A-Za-z0-9_.-]+', "5,8,15", "启用认证授权、权限注解、会话和越权审查"),
        @("JWT", 'jjwt|java-jwt|nimbus-jose-jwt', "5,8,15", "启用 JWT 签名、过期、刷新、撤销和敏感信息审查"),
        @("Validation", 'spring-boot-starter-validation|hibernate-validator|jakarta.validation-api|javax.validation', "1,3,5,15", "启用 Bean Validation、输入边界和 API 参数校验审查"),
        @("Actuator", 'spring-boot-starter-actuator', "3,5,8", "启用管理端暴露、健康检查、指标和敏感端点审查"),
        @("Seata", 'seata-[A-Za-z0-9_.-]+', "4,12", "启用分布式事务、回滚边界、幂等和补偿机制审查"),
        @("Resilience4j/Sentinel", 'resilience4j-[A-Za-z0-9_.-]+|sentinel-[A-Za-z0-9_.-]+', "6,8,12", "启用熔断、限流、降级和异常兜底审查"),
        @("Spring Cloud Gateway", 'spring-cloud-starter-gateway|spring-cloud-gateway[-A-Za-z0-9_.]*', "3,5,8,12,15", "启用网关路由、过滤器、鉴权透传、CORS、限流和错误响应审查"),
        @("Nacos/Apollo Config", 'spring-cloud-starter-alibaba-nacos-config|nacos-client|nacos-config-spring-boot-starter|apollo-client|apollo-core', "3,5,8,12", "启用配置中心命名空间、动态配置、密钥外置、配置刷新和降级审查"),
        @("OAuth2/OIDC", 'spring-boot-starter-oauth2-resource-server|spring-boot-starter-oauth2-client|spring-security-oauth2-[A-Za-z0-9_.-]+|oauth2-oidc-sdk', "3,5,8,15", "启用 token 校验、issuer/audience、scope 权限、资源服务器和错误信息审查"),
        @("Elasticsearch", 'spring-boot-starter-data-elasticsearch|spring-data-elasticsearch|elasticsearch-rest-high-level-client|elasticsearch-java|elasticsearch-rest-client', "4,5,6,8", "启用搜索查询拼接、分页深翻页、索引映射、超时和敏感字段审查"),
        @("MongoDB", 'spring-boot-starter-data-mongodb|mongodb-driver-sync|mongodb-driver-reactivestreams|spring-data-mongodb', "4,5,6", "启用文档查询、索引、分页、NoSQL 注入和连接池审查"),
        @("Scheduler", 'quartz|xxl-job-core|elastic-job-[A-Za-z0-9_.-]+', "1,6,7,8,12", "启用定时任务并发、错过触发、幂等、锁、重试和告警审查"),
        @("Flyway/Liquibase", 'flyway-core|liquibase-core', "4,10,11", "启用数据库迁移顺序、回滚策略、破坏性 DDL 和环境一致性审查"),
        @("MapStruct", 'mapstruct', "1,2,10", "启用 DTO/Entity 映射遗漏、默认值、枚举映射和敏感字段透传审查"),
        @("JSON Serialization", 'jackson-databind|fastjson2?|gson', "1,5,15", "启用反序列化安全、未知字段、日期格式、精度和响应字段暴露审查")
    )

    foreach ($check in $checks) {
        $output = Write-TechStack $check[0] $Detector $check[1] $check[2] $check[3]
        if ($output) {
            Write-Output $output
            $emitted = $true
        }
    }

    $fileChecks = @(
        @("Docker", "docker", "3,5,7,8,12", "启用镜像基础版本、运行用户、密钥注入、资源限制、健康检查和优雅停机审查"),
        @("Kubernetes", "kubernetes", "3,5,7,8,12", "启用探针、资源 requests/limits、Secret/ConfigMap、滚动发布和服务暴露审查")
    )
    foreach ($check in $fileChecks) {
        $output = Write-FileTechStack $check[0] $check[1] $check[2] $check[3]
        if ($output) {
            Write-Output $output
            $emitted = $true
        }
    }

    if (-not $emitted) {
        Write-Output "TECH_STACK:未识别|dependency:none|dimensions:1,2,5,7,10|rules:$FallbackReason"
    }
}

# 检测项目类型并执行相应扫描
if (Test-Path (Join-Path $ProjectDir "pom.xml")) {
    # Maven项目扫描
    Write-Output "=== 项目概况 ==="
    Write-Output "项目类型: Maven"
    $stats = Get-JavaStats $ProjectDir 'target'
    $javaCount = $stats.Split('|')[0]
    $javaLines = $stats.Split('|')[1]
    Write-Output "Java文件总数: $javaCount"
    Write-Output "代码总行数: $javaLines"
    Write-Output ""

    # 检测是否为多模块项目（排除 XML 注释中的 <modules> 标签）
    $pomContent = Get-Content (Join-Path $ProjectDir "pom.xml") -Raw
    $pomNoComments = $pomContent -replace '<!--.*?-->', ''
    $isMultiModule = [regex]::Matches($pomNoComments, '<modules>').Count
    if ($isMultiModule -eq 0) {
        Write-Output "模块类型: 单模块项目"
        Write-Output "PROJECT_TYPE=maven-single"
    } else {
        Write-Output "模块类型: 多模块项目"
        Write-Output "PROJECT_TYPE=maven-multi"
    }

    Write-Output ""
    Write-Output "=== 模块结构 ==="
    $pomFiles = Get-ChildItem -Path $ProjectDir -Filter "pom.xml" -Recurse -File -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PathSegment $_.FullName "target") }
    foreach ($pomFile in $pomFiles) {
        $dir = $pomFile.DirectoryName
        $rel = Get-RelativeDir $dir
        if ([string]::IsNullOrEmpty($rel)) {
            $rootStats = Get-JavaStats $dir 'target'
            $rootCount = $rootStats.Split('|')[0]
            $rootLines = $rootStats.Split('|')[1]
            Write-Output "├── (root)  [$rootCount 类, $rootLines 行]"
            continue
        }
        $moduleStats = Get-JavaStats $dir 'target'
        $mCount = $moduleStats.Split('|')[0]
        $mLines = $moduleStats.Split('|')[1]
        if ([int]$mCount -gt 0) {
            $depth = ($rel.ToCharArray() | Where-Object { $_ -eq '\' -or $_ -eq '/' }).Count
            $indent = " " * ($depth * 2)
            $name = Split-Path $dir -Leaf
            Write-Output "$indent├── $name  [$mCount 类, $mLines 行]"
            Write-Output "MODULE:$name|$rel|$mCount|$mLines"
        }
    }

    Write-DependencyTechStackScan "maven" "未从 pom.xml 依赖识别出专项技术栈，仅启用通用 Java 审查规则"

} elseif ((Test-Path (Join-Path $ProjectDir "build.gradle")) -or (Test-Path (Join-Path $ProjectDir "build.gradle.kts"))) {
    # Gradle项目扫描
    Write-Output "=== 项目概况 ==="
    Write-Output "项目类型: Gradle"
    $stats = Get-JavaStats $ProjectDir 'build'
    $javaCount = $stats.Split('|')[0]
    $javaLines = $stats.Split('|')[1]
    Write-Output "Java文件总数: $javaCount"
    Write-Output "代码总行数: $javaLines"
    Write-Output ""

    # 检测是否为多模块项目（通过settings.gradle判断）
    $settingsFile = Get-ChildItem -Path $ProjectDir -Filter "settings.gradle*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($settingsFile) {
        $settingsContent = Get-Content $settingsFile.FullName -Raw
        $settingsNoComments = $settingsContent -replace '(?m)^\s*//.*$', ''
        $includeCount = [regex]::Matches($settingsNoComments, 'include').Count
        if ($includeCount -gt 0) {
            Write-Output "模块类型: 多模块项目"
            Write-Output "PROJECT_TYPE=gradle-multi"
        } else {
            Write-Output "模块类型: 单模块项目"
            Write-Output "PROJECT_TYPE=gradle-single"
        }
    } else {
        Write-Output "模块类型: 单模块项目"
        Write-Output "PROJECT_TYPE=gradle-single"
    }

    Write-Output ""
    Write-Output "=== 模块结构 ==="
    $buildFiles = Get-ChildItem -Path $ProjectDir -Filter "build.gradle*" -Recurse -File -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PathSegment $_.FullName "build") }
    foreach ($buildFile in $buildFiles) {
        $dir = $buildFile.DirectoryName
        $rel = Get-RelativeDir $dir
        if ([string]::IsNullOrEmpty($rel)) {
            $rootStats = Get-JavaStats $dir 'build'
            $rootCount = $rootStats.Split('|')[0]
            $rootLines = $rootStats.Split('|')[1]
            Write-Output "├── (root)  [$rootCount 类, $rootLines 行]"
            continue
        }
        $moduleStats = Get-JavaStats $dir 'build'
        $mCount = $moduleStats.Split('|')[0]
        $mLines = $moduleStats.Split('|')[1]
        if ([int]$mCount -gt 0) {
            $depth = ($rel.ToCharArray() | Where-Object { $_ -eq '\' -or $_ -eq '/' }).Count
            $indent = " " * ($depth * 2)
            $name = Split-Path $dir -Leaf
            Write-Output "$indent├── $name  [$mCount 类, $mLines 行]"
            Write-Output "MODULE:$name|$rel|$mCount|$mLines"
        }
    }
    Write-DependencyTechStackScan "gradle" "未从 build.gradle/build.gradle.kts 依赖识别出专项技术栈，仅启用通用 Java 审查规则"
} else {
    Write-Output "=== 项目概况 ==="
    Write-Output "❌ 未检测到 Maven (pom.xml) 或 Gradle (build.gradle) 构建文件"
    Write-Output "PROJECT_TYPE=unknown"
    Write-Output ""
    $stats = Get-JavaStats $ProjectDir 'target'
    $javaCount = $stats.Split('|')[0]
    $javaLines = $stats.Split('|')[1]
    Write-Output "Java文件总数: $javaCount"
    Write-Output "代码总行数: $javaLines"
    Write-Output ""
    Write-Output "=== 技术栈识别 ==="
    Write-Output "TECH_STACK:未识别|dependency:none|dimensions:1,2,5,7,10|rules:未检测到 Maven/Gradle 构建文件，仅启用通用 Java 审查规则"
}
