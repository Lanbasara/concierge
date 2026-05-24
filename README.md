# Concierge — Claude Code 秘书层

一个 Claude Code 插件。给你的 AI 配一个**真秘书**：

- **入口翻译**：把你的口语化提示**结构化**成 XML 笔记给 Claude，激活更深的推理
- **出口简报**：Claude 说完后，独立调一个 LLM 生成 **结论 / 建议 / TL;DR** 三段简报
- **个性化**：两端都对照你的 `~/.concierge/priorities.md` ——你在意/不在意什么，秘书都知道
- **零侵入**：Claude 的原始 token 输出**完全不修改**

## 设计哲学

不当"风格警察"，做"真秘书"。一个真秘书的 5 个核心职能：

| 职能 | Concierge 当前进度 |
|------|------------------|
| 1. 把关 (Gatekeeping) | ❌ 故意不做 — 不动 Claude 推理流 |
| 2. 简报 (Briefing) | ✅ 出口 3 段简报，按优先级加权 |
| 3. 翻译 (Translation) | ✅ v0.4.0 起，入口翻译 + 出口简报双向 |
| 4. 记忆 (Memory) | ⚠️ priorities 文件是简版；Memory 学习层待做 |
| 5. 预判 (Anticipation) | ⚠️ 待做 |

v0.4.0 砍下了 5 项里的 3 项核心。

## 架构

| Hook | 时机 | 类型 | 作用 |
|------|------|------|------|
| SessionStart | 会话启动 | command | 注入轻量契约 + 首次配置提示 |
| **UserPromptSubmit** | Boss 提交输入后、Claude 看到前 | **command (v0.4.0 新)** | **调 LLM 把 Boss 口语翻译成结构化 XML 笔记**（仅复杂任务） |
| **Stop** | Claude 准备结束本轮 | command | 调 LLM 生成 3 段秘书简报，full-schema systemMessage 渲染 |

| Skill | 用途 |
|-------|------|
| `/sec-setup` | 配置 API 接入信息（OpenAI-compatible endpoint + key + model） |
| `/sec-brief` | 手动调用简报，临时用 |
| `/sec-priorities` | 创建 / 查看 / 编辑 `~/.concierge/priorities.md` |

## 安装

```
/plugins → 选 lanbasara → 找 concierge → Install → 重启会话
```

## 首次使用

1. `/sec-setup` — 配置 API（base URL、key、model）
2. `/sec-priorities` — 创建你的优先级清单（重要！）
3. 重启会话让 hooks 加载新配置
4. 正常用 Claude Code，秘书会自动工作

## 优先级清单是什么

`~/.concierge/priorities.md` 是你写给秘书的"懂你清单"。例如：

```markdown
## 我在意
- 代码可读性 > 性能优化
- 跨平台兼容 (macOS + Linux)
- 根因 > 表面修复

## 我不在意
- 不必反复确认我已知道的常识
- 不要列 5 个方案让我选，给我推荐

## 决策风格
- 偏好先说结论再展开
- 不确定就明说，不要假装确定
```

秘书在**两个地方**读这份清单：
- **入口**：解读 Boss 请求时，对照在意的维度加权
- **出口**：简报里强调 Boss 关心的事、省略不关心的

项目级覆盖：在项目根目录加 `.concierge-priorities.md`，会追加到全局之后。

## 临时关闭

| 范围 | 操作 |
|------|------|
| 仅出口简报 | `~/.concierge/config.json` 把 `briefEnabled` 设为 `false` |
| 仅入口翻译 | `~/.concierge/config.json` 把 `improverEnabled` 设为 `false` |
| 全部（全局） | `touch ~/.concierge-mute` |
| 全部（项目级） | 项目根目录 `touch .concierge-mute` |

## 工程结构

```
concierge/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── hooks-handlers/
│   ├── session-start.sh                # 注入契约 + 首次配置提示
│   ├── improve-prompt.sh               # v0.4.0 新：入口翻译 (command type)
│   └── stop-digest.sh                  # 出口简报：full-schema systemMessage
├── prompts/
│   ├── secretary-contract.md           # SessionStart 注入的契约
│   ├── improve-system.md               # v0.4.0 新：入口翻译器 system prompt
│   ├── digest-system.md                # 简报生成 system prompt
│   └── priorities-template.md          # /sec-priorities 用的模板
├── scripts/
│   ├── llm-call.sh                     # v0.4.0 新：共享 LLM 调用后端 (curl OpenAI-compat)
│   ├── digest.sh                       # 简报后端 (调 llm-call.sh)
│   └── sync-prompts.sh                 # 重建 hooks.json
├── skills/
│   ├── sec-setup/SKILL.md              # 配置向导
│   ├── sec-brief/SKILL.md              # 手动简报
│   └── sec-priorities/SKILL.md         # v0.4.0 新：管理优先级文件
└── docs/                               # 设计文档
```

## 路线图

- [x] **v0.1.0** — SessionStart 契约骨架
- [x] **v0.2.x** — UserPromptSubmit + 旧 Stop 守门 + 📋 标记
- [x] **v0.3.x** — 移除 rewrite-Stop，改为旁路简报；契约瘦身
- [x] **v0.4.0** — **双向翻译 + 优先级个性化**
- [ ] **v0.5.x** — 学习层（Memory）— 从用户对简报/翻译的反应推断偏好，自动更新 priorities
- [ ] **v0.6.x** — 预判 (Anticipation) — 主动提醒 / 上下文转换警告

详见 [docs/design.md](docs/design.md)。

## 依赖

- `bash`、`jq`、`curl`
- 一个 OpenAI-compatible LLM endpoint + API key

## 已知约束

- Stop hook 自动简报渲染依赖 Claude Code ≥ 2.1.114 的 full-schema systemMessage workaround（参见 [issue #50542](https://github.com/anthropics/claude-code/issues/50542)）
- 入口翻译每次提示会额外调一次 LLM（默认走 30 字符门控 + NONE 早返跳过 trivial 输入）
- 出口简报每次回复会额外调一次 LLM
- 用便宜模型（Haiku、gpt-4o-mini、deepseek-chat）控制成本；配置里的 `model` 字段
