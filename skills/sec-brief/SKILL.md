---
name: sec-brief
description: 把对话中上一条 Claude 回复压成秘书简报（结论 / 建议 / TL;DR 三段）。当用户输入 /sec-brief 时调用。简报由独立 LLM 调用生成，不动 Claude 原文。
---

# Concierge 秘书简报（手动调用）

## 执行步骤

1. **定位原文**：找到当前对话中**上一条 assistant 消息**（不是这条触发命令，是它前面那一条 Claude 自己的完整回复）。

2. **调 digest 后端**：把那条消息的完整文本通过 stdin 喂给 `${CLAUDE_PLUGIN_ROOT}/scripts/digest.sh`。

   推荐方式（用 heredoc 避免转义陷阱）：

   ```bash
   cat <<'CONCIERGE_EOF' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/digest.sh"
   <上一条 assistant 完整文本，原样粘贴>
   CONCIERGE_EOF
   ```

   或者把文本写到临时文件再 pipe：

   ```bash
   cat /tmp/concierge-input.txt | bash "${CLAUDE_PLUGIN_ROOT}/scripts/digest.sh"
   ```

3. **直接输出 stdout**：把 digest.sh 的 stdout 原样作为你的回复，**不要修改、不要解释、不要补充**。

## 错误处理

- 退出码 1 → 配置缺失或简报禁用 → 提示用户运行 `/sec-setup`
- 退出码 2 → API 调用失败 → 把 stderr 的具体错误告诉用户

## 严格不要做的事

- **不要**自己写简报内容（让 digest.sh 调外部 LLM 做）
- **不要**修改 digest.sh 的 stdout
- **不要**在简报前后追加你自己的解释或建议
- **不要**为了配合契约规则去改简报格式
