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
else
  echo "=== 项目概况 ==="
  echo "❌ 未检测到 Maven (pom.xml) 或 Gradle (build.gradle) 构建文件"
  echo "PROJECT_TYPE=unknown"
  echo ""
  STATS=$(java_stats "$PROJECT_DIR" '*/target/*')
  JAVA_COUNT="${STATS%%|*}"
  echo "Java文件总数: $JAVA_COUNT"
fi
