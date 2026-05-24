# Concierge — Claude Code 秘书层

一个 Claude Code 插件，给你的 AI 配一个"秘书"：双向翻译输入与输出，让对话更高效。

## 为什么需要这个

- **输入侧**：你的表达习惯不一定最能激活 AI。Claude 4.x 起字面执行指令，含糊的提示直接劣化结果。
- **输出侧**：AI 倾向冗长、铺垫、列表蔓延 — 而人类工作记忆只有 ~4 chunk，扫读优先于精读。两边一错配，就是"AI 阅读疲劳"。

Concierge 不修改模型本身，只在会话两端加一层"翻译"。

## 当前版本：v0.2.0（双向拦截）

三层 hook 协同工作：

| Hook | 时机 | 作用 |
|-----|-----|-----|
| `SessionStart` | 会话启动 | 注入「秘书契约」，让 Claude 自带认知友好行为 |
| `UserPromptSubmit` | 用户提交后、Claude 看到前 | 评估意图清晰度，给 Claude 注入"内部解读"小抄 |
| `Stop` | Claude 准备结束本轮 | 按认知科学检查表评估输出，不达标 block 返工 |

三份 prompt 都是可读 markdown，放在 `prompts/` 下，你可以自由编辑：

- [`prompts/secretary-contract.md`](prompts/secretary-contract.md) — 秘书契约
- [`prompts/intent-clarifier.md`](prompts/intent-clarifier.md) — 入口意图澄清器
- [`prompts/cognitive-guardian.md`](prompts/cognitive-guardian.md) — 出口认知守门员

修改后运行 `bash scripts/sync-prompts.sh` 把后两份同步到 `hooks/hooks.json`（契约文件被 SessionStart hook 在运行时直接读取，无需同步）。

## 安装

把这个目录作为一个本地 Claude Code 插件加载（具体方式见 [docs/install.md](docs/install.md)），或通过 marketplace 安装。

## 临时关闭

- 全局关闭：`touch ~/.concierge-mute`
- 仅本项目关闭：在项目根目录 `touch .concierge-mute`

删掉文件即可恢复。注意：**只有 SessionStart 契约会响应 mute 文件**；prompt-based hooks（UserPromptSubmit / Stop）若需关闭，请在 Claude Code 的 `/plugins` 里禁用整个插件。

## 工程结构

```
concierge/
├── .claude-plugin/plugin.json          # 插件清单
├── hooks/hooks.json                    # 注册 SessionStart + UserPromptSubmit + Stop
├── hooks-handlers/session-start.sh     # SessionStart hook 执行的脚本
├── prompts/                            # prompt 源文件（人类可读，可编辑）
│   ├── secretary-contract.md           #   SessionStart 注入的契约
│   ├── intent-clarifier.md             #   UserPromptSubmit 的评估 prompt
│   └── cognitive-guardian.md           #   Stop 的评估 prompt
├── scripts/sync-prompts.sh             # 把 prompts/*.md 同步到 hooks.json
├── docs/                               # 设计文档、安装指南
└── skills/                             # /sec * 命令（阶段 3 占位）
```

## 路线图

- [x] 阶段 1：契约骨架 — SessionStart 注入
- [x] 阶段 2：双向拦截 — UserPromptSubmit + Stop hook
- [ ] 阶段 3：主动能力 — `/sec optimize`、`/sec brief`、`/sec mute`
- [ ] 阶段 4：学习闭环 — Memory 个性化

详见 [docs/design.md](docs/design.md)。

## 依赖

- `bash`
- `jq`（多数 Linux/macOS 默认装好；`sync-prompts.sh` 需要）

## 已知限制（v0.2.0）

1. **Stop hook 返工循环风险** — 当前用 prompt 内置的"看上轮是否同因被打回则放行"规则做软兜底；尚无硬性次数上限。若发现循环，临时禁用插件。
2. **UserPromptSubmit 改写边界** — 当前实现是注入 `systemMessage` 作为"秘书小抄"，**不修改用户原文**。是否能真正改写原文待后续验证。
3. **响应延迟** — 每轮回复结束会多 5-30 秒（Stop hook 评估）。对一次性短问答会感觉笨拙，未来需按输出长度门控。
