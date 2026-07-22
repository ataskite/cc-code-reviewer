#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java reviewer scan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/demo project"
MODULE_DIR="$PROJECT_DIR/user service"
mkdir -p "$MODULE_DIR/src/main/java/com/example" "$MODULE_DIR/src/test/java/com/example"

cat > "$PROJECT_DIR/pom.xml" <<'POM'
<project>
  <modules>
    <module>user service</module>
  </modules>
</project>
POM

cat > "$MODULE_DIR/pom.xml" <<'POM'
<project></project>
POM

cat > "$MODULE_DIR/src/main/java/com/example/UserService.java" <<'JAVA'
package com.example;

public class UserService {
    public String name() {
        return "demo";
    }
}
JAVA

cat > "$MODULE_DIR/src/test/java/com/example/UserServiceTest.java" <<'JAVA'
package com.example;

public class UserServiceTest {
    public void testName() {
        new UserService().name();
    }
}
JAVA

OUTPUT="$(bash "$ROOT_DIR/scripts/languages/java/project-scan.sh" "$PROJECT_DIR")"

echo "$OUTPUT" | grep -q "PROJECT_TYPE=maven-multi"
echo "$OUTPUT" | grep -q "Java文件总数: 1"
echo "$OUTPUT" | grep -q "代码总行数: 7"
echo "$OUTPUT" | grep -q "MODULE:user service|/user service|1|7"

UNKNOWN_DIR="$TMP_DIR/plain java"
mkdir -p "$UNKNOWN_DIR/src/main/java/com/example"
cat > "$UNKNOWN_DIR/src/main/java/com/example/Plain.java" <<'JAVA'
package com.example;

public class Plain {
    public int value() {
        return 1;
    }
}
JAVA

UNKNOWN_OUTPUT="$(bash "$ROOT_DIR/scripts/languages/java/project-scan.sh" "$UNKNOWN_DIR")"

echo "$UNKNOWN_OUTPUT" | grep -q "PROJECT_TYPE=unknown"
echo "$UNKNOWN_OUTPUT" | grep -q "Java文件总数: 1"
echo "$UNKNOWN_OUTPUT" | grep -q "代码总行数: 7"

STACK_DIR="$TMP_DIR/stack project"
mkdir -p "$STACK_DIR/src/main/java/com/example" "$STACK_DIR/k8s"
cat > "$STACK_DIR/pom.xml" <<'POM'
<project>
  <dependencies>
    <dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-gateway</artifactId></dependency>
    <dependency><groupId>com.alibaba.cloud</groupId><artifactId>spring-cloud-starter-alibaba-nacos-config</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-oauth2-resource-server</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-elasticsearch</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-mongodb</artifactId></dependency>
    <dependency><groupId>org.quartz-scheduler</groupId><artifactId>quartz</artifactId></dependency>
    <dependency><groupId>org.flywaydb</groupId><artifactId>flyway-core</artifactId></dependency>
    <dependency><groupId>org.mapstruct</groupId><artifactId>mapstruct</artifactId></dependency>
    <dependency><groupId>com.alibaba.fastjson2</groupId><artifactId>fastjson2</artifactId></dependency>
    <dependency><groupId>io.micrometer</groupId><artifactId>micrometer-tracing-bridge-otel</artifactId></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-openai-spring-boot-starter</artifactId></dependency>
  </dependencies>
</project>
POM
cat > "$STACK_DIR/Dockerfile" <<'DOCKER'
FROM eclipse-temurin:17
COPY app.jar app.jar
DOCKER
cat > "$STACK_DIR/k8s/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
YAML

STACK_OUTPUT="$(bash "$ROOT_DIR/scripts/languages/java/project-scan.sh" "$STACK_DIR")"

echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Spring Cloud Gateway|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Nacos/Apollo Config|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:OAuth2/OIDC|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Elasticsearch|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:MongoDB|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Scheduler|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Flyway/Liquibase|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:MapStruct|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:JSON Serialization|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Docker|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Kubernetes|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Micrometer/OTel|"
echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Spring AI/LangChain4j|"

# P2-6: 非 Java 21 / 非 Boot 3.2 的 Spring Boot 项目不应输出 Virtual Threads
if echo "$STACK_OUTPUT" | grep -q "TECH_STACK:Virtual Threads"; then
  echo "FAIL: 非 Java 21/Boot 3.2 项目不应输出 Virtual Threads TECH_STACK" >&2
  exit 1
fi

# P2-6: Java 21 + Boot 3.2 应输出 Virtual Threads
VT_DIR="$TMP_DIR/vt project"
mkdir -p "$VT_DIR/src/main/java/com/example"
cat > "$VT_DIR/pom.xml" <<'POM'
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.1</version>
  </parent>
  <properties>
    <java.version>21</java.version>
  </properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
  </dependencies>
</project>
POM

VT_OUTPUT="$(bash "$ROOT_DIR/scripts/languages/java/project-scan.sh" "$VT_DIR")"
echo "$VT_OUTPUT" | grep -q "TECH_STACK:Virtual Threads|" || { echo "FAIL: Java 21+Boot 3.2 应输出 Virtual Threads" >&2; exit 1; }

# Gradle 显式使用虚拟线程时也必须启用专项规则。
VT_GRADLE_DIR="$TMP_DIR/vt-gradle"
mkdir -p "$VT_GRADLE_DIR/src/main/java/com/example"
cat > "$VT_GRADLE_DIR/build.gradle.kts" <<'GRADLE'
plugins {
    id("org.springframework.boot") version "3.2.2"
    java
}
java { toolchain { languageVersion.set(JavaLanguageVersion.of(21)) } }
GRADLE
cat > "$VT_GRADLE_DIR/src/main/java/com/example/App.java" <<'JAVA'
package com.example;
class App { Thread start(Runnable task) { return Thread.ofVirtual().start(task); } }
JAVA
VT_GRADLE_OUTPUT="$(bash "$ROOT_DIR/scripts/languages/java/project-scan.sh" "$VT_GRADLE_DIR")"
echo "$VT_GRADLE_OUTPUT" | grep -q "TECH_STACK:Virtual Threads|" || { echo "FAIL: Gradle 虚拟线程使用应输出 Virtual Threads" >&2; exit 1; }

# 即使尚无显式源码调用，Gradle Java 21 + Boot 3.2 也应识别能力边界。
VT_GRADLE_CAP_DIR="$TMP_DIR/vt-gradle-capability"
mkdir -p "$VT_GRADLE_CAP_DIR/src/main/java/com/example"
cat > "$VT_GRADLE_CAP_DIR/build.gradle" <<'GRADLE'
plugins {
    id 'org.springframework.boot' version '3.2.3'
    id 'java'
}
sourceCompatibility = JavaVersion.VERSION_21
GRADLE
echo 'package com.example; class App {}' > "$VT_GRADLE_CAP_DIR/src/main/java/com/example/App.java"
VT_GRADLE_CAP_OUTPUT="$(bash "$ROOT_DIR/scripts/languages/java/project-scan.sh" "$VT_GRADLE_CAP_DIR")"
echo "$VT_GRADLE_CAP_OUTPUT" | grep -q "TECH_STACK:Virtual Threads|" || { echo "FAIL: Gradle Java 21+Boot 3.2 应输出 Virtual Threads" >&2; exit 1; }
