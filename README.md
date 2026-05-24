# Concierge — Claude Code 秘书层

一个 Claude Code 插件。给你的 AI 配一个**真秘书**：不替它说话，但在它说完之后，独立做一份**结论 / 建议 / TL;DR** 三段式简报。

## 设计哲学

不当"风格警察"。秘书的工作是**保护老板的注意力**，不是规定 AI 怎么说话。所以 v0.3.0 起：

- **不再强制 "答案前置"** — autoregressive 模型的思考发生在 token 流里，强制结论前置等于切断推理链
- **不再强制 "凡多选必推荐"** — 有些问题真没有清晰胜者，让 AI 保留诚实
- **Claude 的原始输出 100% 不被修改**
- **简报由独立 LLM 调用生成**（你配置的 endpoint + model），追加在 Claude 回复之后作为独立 Line

## 架构（v0.3.0）

| Hook | 作用 | 类型 | 对 Claude 推理的影响 |
|------|------|------|-------------------|
| `SessionStart` | 注入轻量秘书契约（信息密度、列表大小等低成本规则）+ 首次配置提示 | command | 极小 |
| `UserPromptSubmit` | 含糊提示时给 Claude 注入"内部解读"备忘 | prompt | 0（纯增益） |
| `Stop` | **旁路简报** — 调你的 LLM endpoint 生成 3 段简报，用 full-schema systemMessage 渲染 | command | 0（不动 Claude 输出） |

## 安装

通过 marketplace：

```
/plugins → 选 lanbasara → 找 concierge → Install → 重启会话
```

首次会话开始时 Claude 会提示运行 `/sec-setup` 配置 API。

## 配置（一次性）

```
/sec-setup
```

依次问：

1. 是否启用秘书简报？（跳过会写 `disabled: true`，下次不再问）
2. API base URL（OpenAI / DeepSeek / OpenRouter / 自填）
3. API key（直接发到对话里，会写入 `~/.concierge/config.json` 权限 600）
4. Model 名称

写入后 **重启会话** 让 Stop hook 拉取新配置。

## 手动调用

```
/sec-brief
```

随时调用 — 把上一条 Claude 回复压成简报。等同于 Stop hook 自动做的事，但你主动触发。

## 临时关闭

| 范围 | 操作 |
|------|------|
| 仅自动简报 | 编辑 `~/.concierge/config.json` 把 `briefEnabled` 设为 `false` |
| 全部功能（全局） | `touch ~/.concierge-mute` |
| 全部功能（项目级） | 项目根目录 `touch .concierge-mute` |

## 工程结构

```
concierge/
├── .claude-plugin/plugin.json
├── hooks/hooks.json                    # 3 个 hook 的注册
├── hooks-handlers/
│   ├── session-start.sh                # 注入契约 + 首次配置提示
│   └── stop-digest.sh                  # Stop 旁路：读 transcript → 调 digest → 输出 systemMessage
├── prompts/
│   ├── secretary-contract.md           # 轻量契约 (SessionStart 注入)
│   ├── intent-clarifier.md             # UserPromptSubmit 评估 prompt
│   └── digest-system.md                # 秘书简报的 system prompt
├── scripts/
│   ├── digest.sh                       # 共享的 LLM 调用后端 (curl OpenAI-compatible)
│   └── sync-prompts.sh                 # prompts/*.md → hooks.json
├── skills/
│   ├── sec-brief/SKILL.md              # /sec-brief 手动简报
│   └── sec-setup/SKILL.md              # /sec-setup 配置向导
└── docs/                               # 设计文档
```

## 路线图

- [x] **v0.1.0** — SessionStart 契约骨架
- [x] **v0.2.x** — UserPromptSubmit + 旧 Stop 守门 + 📋 标记
- [x] **v0.3.0** — 移除 rewrite-Stop，改为旁路简报；契约瘦身
- [ ] **v0.4.x** — Memory 个性化（学习偏好、累积纠正）
- [ ] **v0.5.x** — `.concierge-priorities` 优先级文件（注入 Boss 的"在意/不在意"清单）

详见 [docs/design.md](docs/design.md)。

## 依赖

- `bash`、`jq`、`curl`
- 一个 OpenAI-compatible LLM endpoint + API key（OpenAI / DeepSeek / OpenRouter / 任意兼容代理）

## 已知约束

- **Stop hook 自动简报渲染依赖 Claude Code ≥ 2.1.114** 的 full-schema systemMessage 行为（见 [issue #50542](https://github.com/anthropics/claude-code/issues/50542)）
- 简报触发后增加约 1-3 秒延迟（取决于你选的 model 速度）
- 每条 Claude 回复都会消耗一次 LLM 调用 — 用便宜的模型（Haiku、gpt-4o-mini、deepseek-chat）控制成本
