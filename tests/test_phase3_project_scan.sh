#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java reviewer scan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/demo project"
MODULE_DIR="$PROJECT_DIR/user service"
mkdir -p "$MODULE_DIR/src/main/java/com/example"

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

OUTPUT="$(bash "$ROOT_DIR/scripts/phase3-project-scan.sh" "$PROJECT_DIR")"

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

UNKNOWN_OUTPUT="$(bash "$ROOT_DIR/scripts/phase3-project-scan.sh" "$UNKNOWN_DIR")"

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

STACK_OUTPUT="$(bash "$ROOT_DIR/scripts/phase3-project-scan.sh" "$STACK_DIR")"

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
