---
name: sec-priorities
description: 打开 / 编辑 / 创建 Boss 的优先级文件 ~/.concierge/priorities.md。Concierge 秘书读这个文件来"懂你"——入口翻译和出口简报都会用。
---

# Concierge 优先级管理

`~/.concierge/priorities.md` 是 Boss 写给秘书的"我在意 / 不在意什么"清单。Concierge 在两处读它：
- **UserPromptSubmit**（输入翻译）按 priorities 加权理解 Boss 的请求
- **Stop**（出口简报）按 priorities 决定简报里强调什么、省略什么

## 执行步骤

### 第 1 步：检查文件是否存在

```bash
ls -la ~/.concierge/priorities.md 2>/dev/null
```

### 第 2 步：根据状态分流

**情况 A — 文件不存在 → 创建（用模板）**

```bash
mkdir -p ~/.concierge
cp "${CLAUDE_PLUGIN_ROOT}/prompts/priorities-template.md" ~/.concierge/priorities.md
```

然后告诉用户：

> "已创建 `~/.concierge/priorities.md`（用模板填充）。这是 Boss 写给秘书的"懂你清单"——建议你现在用编辑器打开填上几条真正在意的事。模板里有示例和建议。
>
> 写法：每条尽量具体，3-5 条就够。写完后，下次会话开始秘书就会读了。"

**情况 B — 文件已存在 → 读出来给用户看 + 询问是否要改**

```bash
cat ~/.concierge/priorities.md
```

读出后，用 AskUserQuestion：

```
问题: "要做什么？"
选项:
- "只是看一下，不改"
- "我想直接告诉你要改什么，你帮我改" 
- "我自己用编辑器改 (告诉我路径)"
```

根据选择处理：
- 看一下 → 结束
- 替 Boss 改 → 用 AskUserQuestion 进一步问要加 / 删 / 改什么，然后用 Edit 工具改 `~/.concierge/priorities.md`
- 自己改 → 告诉用户文件路径 `~/.concierge/priorities.md`，结束

### 项目级 priorities（可选介绍）

如果 Boss 想要某个项目专属的偏好，可以在项目根目录创建 `.concierge-priorities.md`。这个文件会**追加到全局之后**（项目级覆盖 / 补充全局）。

适用场景：
- 某个项目有特别的合规要求
- 某个项目希望更激进 / 更保守
- 不同领域的项目（前端 vs 后端 vs 数据），关注维度不同

## 规则

- **永远不要在你的输出里复述用户的 API key 或其他敏感信息**（priorities 文件不应该有，但万一）
- **不要替 Boss 凭空写偏好** — 只在用户明确告诉你要写什么时才写
- 鼓励 Boss 写"我希望" + "我不希望"两面，比单一更准
