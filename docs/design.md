# Concierge 顶层设计

## 一、问题域

### 1.1 输入侧错配
Claude 4.x 起字面执行用户指令，含糊提示直接劣化输出。Anthropic 2026 官方实践把"首轮就说清意图、约束、成功标准"列为头号守则。常见用户缺陷：

- 目标含糊（"帮我改一下"）
- 上下文缺失（用户脑里有的背景，模型看不见）
- 没有成功标准
- 隐含假设
- 抽象层错位（要设计还是要实现）

### 1.2 输出侧错配（"AI 阅读疲劳"）
2026 年数据：人类有效上下文跨度从 2004 年 ~16,000 tokens 跌至 ~1,800 tokens。同期 LLM 输出越来越长。

| AI 倾向 | 人脑约束 | 后果 |
|--------|---------|-----|
| 信息平铺 | 工作记忆 ~4 chunk | 抓不住重点 |
| 前置铺垫 | 注意力前置 | 错过结论 |
| 列表过载 | 需要层级 | 视而不见 |
| 过度对冲 | 决策疲劳 | 无法行动 |
| 全量披露 | 渐进式吸收 | 放弃阅读 |
| 流畅伪装正确 | fluency bias | 过度信任 |

研究还指出 LLM 本身不擅长评估可读性，所以让模型"自己注意"不可靠，必须外挂执行者。

### 1.3 参考文献
- [Cognitive Divergence: AI Context Windows & Human Attention Decline](https://arxiv.org/pdf/2603.26707)
- [Behavioral Indicators of Overreliance During LLM Interaction](https://arxiv.org/html/2602.11567v1)
- [Readability Formulas, Systems and LLMs are Poor Predictors](https://arxiv.org/abs/2502.11150)
- [Verbose LLM Outputs](https://arxiv.org/pdf/2410.00863)
- [Anthropic Prompt Engineering Best Practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)

## 二、秘书角色模型

不是另一个 AI，是双向翻译官。借鉴顶级高管助理的特征：

1. **低存在感** — 不替老板说话，不抢功
2. **预判** — 知道老板偏好，主动补全没说出口的约束
3. **守门** — 把不合格的草稿打回去，不让老板看废稿
4. **可学习** — 跟得越久越懂你
5. **可关闭** — 用户随时能跳过秘书直接和 AI 说话

## 三、技术架构

### 3.1 Claude Code 原语映射

| 原语 | 用途 |
|-----|-----|
| `SessionStart` hook | 契约层 — 每会话注入秘书人格与输出规范 |
| `UserPromptSubmit` hook (prompt 型) | 入口层 — 意图澄清 + 注入上下文 |
| `Stop` hook (prompt 型) | 出口层 — 认知科学审查，不达标返工 |
| Skill (`/sec ...`) | 主动层 — 显式调用的能力 |
| Memory | 学习层 — 累积用户风格 |
| Subagent | 重活层 — 超长输出重排 |
| Plugin 打包 | 统一分发 |

### 3.2 三层架构

```
Layer C: 学习层 (Memory)          ← 长期记忆
       ↑
Layer B: 主动层 (Skills)          ← 显式触发
       ↑
Layer A: 契约层 (Hooks)           ← 始终在线
```

**核心洞察**：Layer A 是最重要的。与其事后修，不如事前规定。SessionStart 注入的契约让 Claude 自带秘书行为，零开销。Stop hook 是兜底。

### 3.3 单回合数据流

```
用户输入
  → UserPromptSubmit hook
    （识别意图缺口，注入 systemMessage）
  → Claude 思考与工具调用（受 Layer A 契约约束）
  → Claude 准备 Stop
  → Stop hook
    （认知检查表打分；不及格 block + 返工）
  → 输出送达用户
  → Memory 异步更新
```

## 四、模块清单

### 4.1 输入侧 — Prompt Optimizer (UserPromptSubmit, prompt 型)
评估用户输入：
1. 意图是否明确？识别最可能的两种解读
2. 是否缺关键上下文？
3. 抽象层是否对齐？
4. 是否触发"字面执行陷阱"？

注入 systemMessage：
- 真实意图（最可能解读）
- 隐含约束
- 成功标准
- 歧义不可消除则触发 AskUserQuestion

### 4.2 输出侧 — Cognitive Guardian (Stop, prompt 型)

检查表（可配权重）：

| 维度 | 判据 | 违规处理 |
|-----|------|---------|
| 答案前置 | 首段是否给出结论 | block：拎到最前 |
| 信息密度 | 每句是否承载新信息 | block：删冗余 |
| 层级清晰 | 视觉锚引导扫读 | block：补层级 |
| 块大小 | 列表 ≤ 4 项 | block：分组 |
| 不确定性显式 | 关键判断标注信心 | block：补标注 |
| 行动指向 | 决策段给下一步 | block：补行动 |
| 长度匹配 | 不为完整而冗长 | block：压缩 |

**硬上限**：返工最多 2 次，第二次没过仍放行（带标记）。

### 4.3 主动层 — Skills

| 命令 | 用途 |
|-----|-----|
| `/sec optimize` | 预审准备发的提示，给改写建议 |
| `/sec brief <n>` | 把上 N 轮压成认知友好摘要 |
| `/sec rewrite` | 把刚才那段 AI 输出按认知规则重排 |
| `/sec audit` | 解释为什么某段触发了 guardian |
| `/sec style <profile>` | 切换风格档 |
| `/sec mute` | 当前会话临时关闭秘书 |

### 4.4 学习层 — Memory

类型：
- `feedback`：用户对 guardian 决定的修正
- `user`：领域、语言、视觉风格
- `style-profile`：偏好档（短/长、列表/段落）

阈值由 Memory 决定。同一秘书面对不同用户会自我调整。

## 五、关键权衡

| 权衡 | 取向 | 理由 |
|-----|-----|-----|
| 入侵程度 | 低存在感 | 秘书的最高荣誉是感觉不到她 |
| 自动 vs 显式 | 契约层默认开 + 主动层按需 | 不每回合都跑重型重写 |
| 强制 vs 建议 | Stop 强制返工 + escape hatch | `/sec mute` 跳过 |
| 通用 vs 个性化 | 先通用 → 3 周后切个性化 | 冷启动可用 |
| 性能 | hook 轻量 + 重活下放 skill | Stop hook 30s 够用 |
| 失败兜底 | fail open | 秘书坏了不卡住老板 |

## 六、不做的事

- 不做模型再训练
- 不做内容审查
- 不做强行风格化（保留用户文风）
- 不做无差别压缩（代码、引文、长文档原样保留）
- 不替用户做决策

## 七、阶段路线

### 阶段 1（已完成 v0.1.0）— 契约骨架
- `.claude-plugin/plugin.json`
- `hooks/hooks.json` 注册 SessionStart
- `hooks-handlers/session-start.sh` 注入契约
- `prompts/secretary-contract.md` 契约内容（用户可编辑）

### 阶段 2（已完成 v0.2.x）— 双向拦截（旧设计 / 已废弃部分）
- `UserPromptSubmit` prompt-hook：意图澄清器（**v0.3.0 保留**）
- `Stop` prompt-hook：认知守门员（**v0.3.0 已移除** — 强制 rewrite 净负）
- 📋 标记（**v0.3.0 保留**）

### 阶段 4（已完成 v0.4.0）— 双向翻译 + 优先级个性化

**触发洞察（用户提出）：** 真秘书有 5 个核心职能 (Gatekeeping / Briefing / Translation / Memory / Anticipation)，v0.3.x 只做了 Briefing 一项。Translation 缺一半（输入侧 Boss → Expert 没做），这导致 Claude 4.x 字面执行习惯下 Boss 的口语化输入无法激活 Claude 的深度推理。

**v0.4.0 关键变化：**

1. **入口翻译（UserPromptSubmit）从 prompt-type 改为 command-type**
   - 旧版只做意图澄清，新版调独立 LLM 把 Boss 的口语化输入翻译成结构化 XML 笔记
   - 翻译内容：`<task> <context> <constraints> <success_criteria> <priority_lens> <thinking_mode>`
   - 仅对 COMPLEX 类型的输入生成翻译，TRIVIAL/STANDARD 返回 NONE 静默跳过
   - 30 字符以下输入走廉价启发式直接跳过，不调 LLM

2. **`~/.concierge/priorities.md` 优先级文件**
   - 自由编辑的 markdown，Boss 写"我在意/不在意/决策风格/项目上下文"
   - 入口翻译 + 出口简报两端都读，统一驱动个性化
   - 项目级覆盖：`<项目根>/.concierge-priorities.md` 追加到全局之后

3. **共享 LLM 调用后端 `scripts/llm-call.sh`**
   - 单点维护的 curl OpenAI-compatible 调用
   - 同时被 digest.sh（出口简报）和 improve-prompt.sh（入口翻译）使用

4. **数字签名：3 个 hook 全部 command-type**
   - 不再用 prompt-type hook（v0.2.x 时用过，schema 验证麻烦）
   - 所有 prompt 内容在 `prompts/` 下，由 script 运行时读取

5. **新增 skill `/sec-priorities`** — 创建 / 查看 / 编辑优先级文件

6. **配置文件 schema 扩展**：新增 `improverEnabled`（默认 true）、`improverMinChars`（默认 30）

### 阶段 3（已完成 v0.3.0）— 旁路秘书简报
- **架构转向**：从"调整 Claude 原输出"转为"在 Claude 输出之后独立追加"
  - 触发：[Issue #50542](https://github.com/anthropics/claude-code/issues/50542) 评论里发现 full-schema `{continue, suppressOutput, systemMessage}` 可以持久渲染独立 Line
  - 用户实测确认 workaround 在 v2.1.150 上工作
- **Stop hook 类型从 prompt 改为 command**：
  - 读 `transcript_path`，提取最后一条 assistant 消息
  - 调 `scripts/digest.sh`（curl OpenAI-compatible endpoint）生成简报
  - 用 full-schema systemMessage 渲染到用户聊天流
  - Claude 原始 token 输出**完全不动**
- **简报格式**：`📋 结论 / 建议 / TL;DR` 三段，由独立 LLM 用 `prompts/digest-system.md` 这个 system prompt 生成
- **契约瘦身**：移除"答案前置"、"凡多选必推荐"两条会切断 chain-of-thought 的硬规则
- **新增 skills**：
  - `/sec-setup` — AskUserQuestion 引导填配置，写入 `~/.concierge/config.json`
  - `/sec-brief` — 手动调用简报，复用同一个 digest 后端
- **配置文件**：`~/.concierge/config.json`（不在 plugin cache 内，免被 update 清掉）

### 阶段 4（未做 v0.4.x）— Memory 个性化
- 累积用户偏好、修正、领域词汇
- 让简报根据 Boss 风格自适应

### 阶段 5（未做 v0.5.x）— 优先级文件
- `.concierge-priorities` 列 Boss 在意 / 不在意的事
- 注入到 digest system prompt，让简报对照"Boss 关心的事"做高亮

### 阶段 3 — 主动能力
- `/sec optimize`、`/sec brief`、`/sec mute` 三个 skill
- 文档与示例

### 阶段 4 — 学习闭环
- Memory schema（feedback / style-profile）
- 用户的纠正自动写回 Memory，影响后续阈值
- 周期性"秘书例会"skill：累积偏好让用户确认

## 八、开放问题

1. **Stop hook 重写循环** — 硬上限 ≤2 次必须实现
2. **UserPromptSubmit 改写边界** — 能否真正改写用户原文需技术验证；不能则只能"在旁边提醒"
3. **个性化漂移** — Memory 学得太久会过度迁就，强化盲区；需定期审计机制
4. **响应延迟** — Stop hook 增加 5-30s；对短问答笨拙，需按输出长度门控
