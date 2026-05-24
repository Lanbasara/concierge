#!/usr/bin/env bash
# Concierge Stop hook — 自动秘书简报（B 旁路）
# 当 Claude 准备结束本轮回复时触发，调 LLM 生成简报，通过 systemMessage 渲染给用户
#
# 关键设计：
#   - Claude 的原始回复 100% 不动（Claude 已经发完，hook 只是在它之后追加一条独立 Line）
#   - 简报由独立 LLM 调用生成，不动 Claude token 流
#   - 用 full-schema systemMessage workaround for issue #50542
#   - stop_hook_active 防递归
#   - 配置缺失/disabled → 静默退出，不打扰用户

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

input=$(cat)

# 1. 防递归：如果是上一轮 Stop hook 触发的二次 Stop，直接放行
if echo "$input" | grep -q '"stop_hook_active":[[:space:]]*true'; then
  exit 0
fi

# 2. .concierge-mute 兜底（全局或项目级）
if [ -f "${HOME}/.concierge-mute" ]; then
  exit 0
fi
project_dir=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
if [ -n "$project_dir" ] && [ -f "${project_dir}/.concierge-mute" ]; then
  exit 0
fi

# 3. 读 transcript_path，取最后一条 assistant 消息
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# transcript 是 JSONL；每行一个事件。提取最后一条 assistant 类型的 message.content
# content 可能是字符串或数组(blocks)；都要处理
last_assistant=$(tac "$transcript_path" 2>/dev/null | while IFS= read -r line; do
  msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null || echo "")
  if [ "$msg_type" = "assistant" ]; then
    # 拿 message.content；若是数组，把 type=="text" 的 text 拼起来
    content=$(echo "$line" | jq -r '
      if (.message.content | type) == "string" then
        .message.content
      elif (.message.content | type) == "array" then
        [.message.content[] | select(.type == "text") | .text] | join("\n")
      else
        empty
      end
    ' 2>/dev/null || echo "")
    if [ -n "$content" ]; then
      echo "$content"
      break
    fi
  fi
done | head -c 50000)

if [ -z "$last_assistant" ]; then
  exit 0
fi

# 4. 调 digest.sh 生成简报
brief=$(echo "$last_assistant" | bash "${PLUGIN_ROOT}/scripts/digest.sh" 2>/dev/null) || {
  # 配置缺失/API 失败：静默退出，不打扰用户
  exit 0
}

if [ -z "$brief" ]; then
  exit 0
fi

# 5. full-schema systemMessage 输出（workaround for #50542 — 单独 systemMessage 会被 UI 丢弃）
jq -nc --arg msg "$brief" '{
  continue: true,
  suppressOutput: false,
  systemMessage: $msg
}'

exit 0
