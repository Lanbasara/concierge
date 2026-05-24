#!/usr/bin/env bash
# Concierge 共享 digest 后端
# 从 stdin 读取一段文本（Claude 的原始回复），调用用户配置的 OpenAI-compatible LLM
# 生成秘书简报，输出到 stdout
#
# 用法：
#   echo "Claude 的回复全文" | bash scripts/digest.sh
#
# 配置文件：~/.concierge/config.json
# 字段：apiBaseUrl, apiKey, model, briefEnabled (true/false), briefMinChars (default 0)
#
# 退出码：
#   0 — 正常输出简报到 stdout
#   1 — 配置缺失或 brief 禁用 (stdout 为空，stderr 解释)
#   2 — API 调用失败 (stdout 为空，stderr 错误信息)

set -euo pipefail

CONFIG_FILE="${HOME}/.concierge/config.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="${SCRIPT_DIR}/../prompts/digest-system.md"

# 1. 配置检查
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Concierge: 配置文件不存在 (~/.concierge/config.json)，运行 /sec setup 配置" >&2
  exit 1
fi

disabled=$(jq -r '.disabled // false' "$CONFIG_FILE")
if [ "$disabled" = "true" ]; then
  echo "Concierge: 简报功能已被用户禁用" >&2
  exit 1
fi

brief_enabled=$(jq -r '.briefEnabled // true' "$CONFIG_FILE")
if [ "$brief_enabled" = "false" ]; then
  echo "Concierge: briefEnabled=false" >&2
  exit 1
fi

api_base_url=$(jq -r '.apiBaseUrl // ""' "$CONFIG_FILE")
api_key=$(jq -r '.apiKey // ""' "$CONFIG_FILE")
model=$(jq -r '.model // ""' "$CONFIG_FILE")

if [ -z "$api_base_url" ] || [ -z "$api_key" ] || [ -z "$model" ]; then
  echo "Concierge: 配置不完整 — 需要 apiBaseUrl + apiKey + model" >&2
  exit 1
fi

# 2. 读取原文
message=$(cat)
if [ -z "$message" ]; then
  echo "Concierge: digest 输入为空" >&2
  exit 1
fi

# 3. 最小长度门控（默认 0 = 永远触发）
min_chars=$(jq -r '.briefMinChars // 0' "$CONFIG_FILE")
msg_len=$(echo -n "$message" | wc -c)
if [ "$msg_len" -lt "$min_chars" ]; then
  echo "Concierge: 原文 ${msg_len} 字符 < 阈值 ${min_chars}，跳过" >&2
  exit 1
fi

# 4. 读取秘书简报的 system prompt
if [ ! -f "$PROMPT_FILE" ]; then
  echo "Concierge: digest-system.md 缺失" >&2
  exit 2
fi
system_prompt=$(cat "$PROMPT_FILE")

# 5. 构造 OpenAI-compatible chat completions 请求
payload=$(jq -n \
  --arg model "$model" \
  --arg sys "$system_prompt" \
  --arg msg "$message" \
  '{
    model: $model,
    messages: [
      {role: "system", content: $sys},
      {role: "user", content: $msg}
    ],
    temperature: 0.3
  }')

# 6. 调用 API（10 秒超时）
response=$(curl -sS --max-time 30 \
  -X POST "${api_base_url%/}/chat/completions" \
  -H "Authorization: Bearer ${api_key}" \
  -H "Content-Type: application/json" \
  -d "$payload" 2>&1) || {
    echo "Concierge: curl 失败 — $response" >&2
    exit 2
  }

# 7. 提取内容（OpenAI-compatible 格式）
content=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo "")
if [ -z "$content" ]; then
  err=$(echo "$response" | jq -r '.error.message // .error // "未知错误"' 2>/dev/null || echo "$response")
  echo "Concierge: API 响应缺 content — $err" >&2
  exit 2
fi

# 8. 输出简报
echo "$content"
exit 0
