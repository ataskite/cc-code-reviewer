---
description: 扫描后沉淀项目级 ignore 规则，从飞书 Base 或本地 Markdown 问题清单中选择代表性问题并写入本地 ignore 文件
---

# Project Ignore Skill

你负责把扫描后的误报或项目特有设计沉淀为项目级 ignore 规则。ignore 文件是 **AI 指令型 ignore 文件**，供后续 scan agent 读取并跳过同类问题。

## 入口参数

用户只需要提供项目路径：

```text
/cc-code-reviewer:cc-code-ignore /path/to/project
```

必须先识别并校验项目路径。项目路径无效时终止，不得写入任何文件。

## 必须读取的参考

执行前读取：

```text
references/ignore-workflow.md
```

并严格遵守其中的 YAML 格式和写入规则。

## 执行顺序

### 1. 检测项目路径

确认项目目录存在。默认 ignore 文件路径为：

```text
{PROJECT_DIR}/.cc-code-reviewer/ignore/issues.yml
```

### 2. 询问问题清单来源

使用 AskUserQuestion，一次只问来源：

- 飞书 Base
- 本地 Markdown

如果用户在 Other/free-form 中直接粘贴飞书 Base 链接或 Markdown 路径，也可以根据输入动态识别。

### 3. 读取问题清单

#### 飞书 Base

必须通过 `lark-base` / `lark-cli` 读取飞书 Base 记录。不得用本地脚本解析飞书 Base 链接。

读取字段至少包括：

- 问题编号
- 严重级别
- 所属维度
- 问题描述
- 位置
- 证据
- 修复建议

#### 本地 Markdown

直接读取本地 Markdown 文件，按问题编号定位问题段落。支持：

- `P0-N`
- `P1-N`
- `P2-N`
- `P3-N`
- `待确认-N`

### 4. 用户指定问题编号

展示可选问题摘要后，让用户指定问题编号。编号只用于定位这一次问题清单中的代表性问题。

禁止把报告编号写入 ignore 文件。

### 5. 生成 ignore 规则

根据代表性问题生成极简 YAML：

```yaml
- name: "Controller 未显式鉴权"
  applies_to:
    - "所有 Controller 接口"
    - "Spring MVC 请求入口"
  skip_when: |
    如果发现的问题是 Controller 方法缺少 @PreAuthorize、@RequiresPermissions、
    权限注解、显式鉴权调用，或类似“接口未做权限校验”的结论，
    后续扫描不要再把这类问题列为扫描问题。
```

生成规则要求：

- `name` 写成问题类型，不写本次编号。
- `applies_to` 写适用范围，可以来自问题位置、模块、包名、技术栈或接口类型。
- `skip_when` 写给 AI 的判断指令，说明后续遇到什么同类问题要跳过。
- 不写 `reason`、`created_by`、`created_at`、fingerprint 或审计字段。

### 6. 写入前确认

展示拟追加的 YAML 片段，使用 AskUserQuestion 让用户确认：

- 确认写入
- 取消

用户确认后才能写文件。

### 7. 写入文件

写入 `{PROJECT_DIR}/.cc-code-reviewer/ignore/issues.yml`：

- 文件不存在时创建：
  ```yaml
  version: 1

  ignore:
  ```
- 文件存在时只追加，不重排、不改写已有规则。
- 如果 `name` 与已有规则重复，先提示用户确认是否仍然追加。

## 输出

完成后输出：

```text
✅ 已写入项目 ignore 规则

📄 文件：{PROJECT_DIR}/.cc-code-reviewer/ignore/issues.yml
🧩 规则：{name}

后续扫描会读取该文件，语义命中 skip_when 的同类问题将不再列入扫描问题清单。
```
