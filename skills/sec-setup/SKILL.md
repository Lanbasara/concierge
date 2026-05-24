---
name: sec-setup
description: 配置 Concierge 秘书的 API 接入信息（apiBaseUrl + apiKey + model）。当用户首次使用秘书简报、或输入 /sec-setup 时调用。
---

# Concierge 配置向导

引导用户填写 `~/.concierge/config.json`，启用秘书简报功能。

## 第 1 步：询问是否启用

用 AskUserQuestion：

```
问题: "是否启用 Concierge 秘书简报？（需要一个 OpenAI-compatible API endpoint，每次 Claude 回复后会调用一次）"
选项:
- "启用 — 我有 API 信息" (推荐)
- "暂时跳过 — 不显示简报"
```

如果用户选**"暂时跳过"**：

```bash
mkdir -p ~/.concierge
echo '{"disabled": true}' > ~/.concierge/config.json
```

告诉用户：「已禁用秘书简报。再次运行 `/sec-setup` 可以启用。其他功能（契约层、意图澄清）不受影响。」结束。

## 第 2 步：API base URL

如果用户选启用，用 AskUserQuestion 问 base URL：

```
问题: "选择 API endpoint："
选项:
- "OpenAI 官方 (https://api.openai.com/v1)"
- "DeepSeek (https://api.deepseek.com/v1)"
- "OpenRouter (https://openrouter.ai/api/v1)"
```

用户也可以选 Other 自填。把选择的 URL 存到变量 `BASE_URL`。

## 第 3 步：API key

**不要用 AskUserQuestion** —— API key 是自由文本。直接告诉用户：

> "请直接在对话里回复你的 API key。它会被写入本地 `~/.concierge/config.json`（权限 600），不会上传任何地方。"

等用户在下一条消息中提供 key。**不要在你的输出中复述这个 key**。把它存到变量 `API_KEY`。

## 第 4 步：Model 名称

根据 BASE_URL 给合理默认选项，用 AskUserQuestion：

- 如果 BASE_URL 包含 `openai.com`:
  ```
  选项: "gpt-4o-mini (推荐, 便宜快)" / "gpt-4o" / "gpt-4.1-mini"
  ```
- 如果包含 `deepseek.com`:
  ```
  选项: "deepseek-chat (推荐)" / "deepseek-reasoner"
  ```
- 如果包含 `openrouter.ai`:
  ```
  问题: "OpenRouter 上模型很多，请填具体模型名（如 anthropic/claude-haiku-4-5）"
  选项: "anthropic/claude-haiku-4-5 (推荐)" / "openai/gpt-4o-mini" / "deepseek/deepseek-chat"
  ```
- 其他: 让用户自填（提供 Other）

把选的存到 `MODEL`。

## 第 5 步：写入配置

```bash
mkdir -p ~/.concierge
jq -n \
  --arg base "$BASE_URL" \
  --arg key "$API_KEY" \
  --arg model "$MODEL" \
  '{apiBaseUrl: $base, apiKey: $key, model: $model, briefEnabled: true, briefMinChars: 0}' \
  > ~/.concierge/config.json
chmod 600 ~/.concierge/config.json
```

**重要**：写入时用 Bash 工具直接执行，**不要把 API key 复述在你的输出文字里**。

## 第 6 步：写完 API 配置后，建议设置 priorities

告诉用户：

> "✓ API 配置写入完成（~/.concierge/config.json，权限 600）。
>
> 下一步建议：现在运行 `/sec-priorities` 创建一份"Boss 优先级"清单——这是 Concierge 秘书"懂你"的关键。秘书会在入口翻译和出口简报里都对照这份清单做个性化。
>
> 完成后**重启 Claude Code 会话**，hooks 才能加载新配置。"

可以直接用 AskUserQuestion 问：

```
问题: "API 已配置好。要不要现在设置 Boss 优先级文件？"
选项:
- "好，跑 /sec-priorities" (推荐)
- "以后再说"
```

如果用户选"跑 /sec-priorities"，引导他们手动输入命令（你不能直接调用其他 skill，但可以告诉他们怎么调）。

## 异常情况

- 如果第 3 步用户提供的 key 看起来明显格式错误（太短、含空格等），礼貌确认一下再写入
- 如果用户中途反悔不想配，可以中断并写 `{"disabled": true}`
