# Concierge — Claude Code 秘书层

一个 Claude Code 插件，给你的 AI 配一个"秘书"：双向翻译输入与输出，让对话更高效。

## 为什么需要这个

- **输入侧**：你的表达习惯不一定最能激活 AI。Claude 4.x 起字面执行指令，含糊的提示直接劣化结果。
- **输出侧**：AI 倾向冗长、铺垫、列表蔓延 — 而人类工作记忆只有 ~4 chunk，扫读优先于精读。两边一错配，就是"AI 阅读疲劳"。

Concierge 不修改模型本身，只在会话两端加一层"翻译"。

## 当前版本：v0.1.0（契约骨架）

只做了一件事：**每次会话开始时，向 Claude 注入一份「秘书契约」**，让它从一开始就按认知友好的规则工作。

契约内容见 [`prompts/secretary-contract.md`](prompts/secretary-contract.md)，你可以自由编辑。

## 安装

把这个目录作为一个本地 Claude Code 插件加载（具体方式见 [docs/install.md](docs/install.md)）。

## 临时关闭

- 全局关闭：`touch ~/.concierge-mute`
- 仅本项目关闭：在项目根目录 `touch .concierge-mute`

删掉文件即可恢复。

## 工程结构

```
concierge/
├── .claude-plugin/plugin.json          # 插件清单
├── hooks/hooks.json                    # 注册 SessionStart hook
├── hooks-handlers/session-start.sh     # hook 实际执行的脚本
├── prompts/secretary-contract.md       # 秘书契约（用户可编辑）
├── docs/                               # 设计文档、安装指南
└── skills/                             # /sec * 命令（后续阶段）
```

## 路线图

- [x] 阶段 1：契约骨架 — SessionStart 注入
- [ ] 阶段 2：双向拦截 — UserPromptSubmit + Stop hook
- [ ] 阶段 3：主动能力 — `/sec optimize`、`/sec brief`、`/sec mute`
- [ ] 阶段 4：学习闭环 — Memory 个性化

详见 [docs/design.md](docs/design.md)。

## 依赖

- `bash`
- `jq`（多数 Linux/macOS 默认装好）
