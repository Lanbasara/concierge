#!/usr/bin/env bash
# llm-call.sh — Concierge 共享的 OpenAI-compatible LLM 调用后端
#
# 用法：
#   bash scripts/llm-call.sh "<system_prompt>" "<user_content>"
#
# 输出：
#   stdout — 模型响应内容（content 字段）
#   stderr — 错误诊断
#
# 退出码：
#   0 — 成功（content 在 stdout）
#   1 — 配置缺失或被禁用
#   2 — API 调用失败

LOG_DIR="${HOME}/.concierge"
LOG="${LOG_DIR}/llm-call.log"

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

SYSTEM_PROMPT="${1:-}"
USER_CONTENT="${2:-}"

if [ -z "$SYSTEM_PROMPT" ] || [ -z "$USER_CONTENT" ]; then
  log "missing args (system='${SYSTEM_PROMPT:0:30}', user='${USER_CONTENT:0:30}')"
  echo "llm-call.sh: missing args" >&2
  exit 1
fi

CONFIG_FILE="${HOME}/.concierge/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  log "no config file"
  echo "no config" >&2
  exit 1
fi

disabled=$(jq -r '.disabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$disabled" = "true" ]; then
  log "config disabled"
  echo "disabled" >&2
  exit 1
fi

api_base_url=$(jq -r '.apiBaseUrl // ""' "$CONFIG_FILE" 2>/dev/null)
api_key=$(jq -r '.apiKey // ""' "$CONFIG_FILE" 2>/dev/null)
model=$(jq -r '.model // ""' "$CONFIG_FILE" 2>/dev/null)

if [ -z "$api_base_url" ] || [ -z "$api_key" ] || [ -z "$model" ]; then
  log "incomplete config"
  echo "incomplete config" >&2
  exit 1
fi

payload=$(jq -n \
  --arg model "$model" \
  --arg sys "$SYSTEM_PROMPT" \
  --arg msg "$USER_CONTENT" \
  '{
    model: $model,
    messages: [
      {role: "system", content: $sys},
      {role: "user", content: $msg}
    ],
    temperature: 0.3
  }')

response=$(curl -sS --max-time 30 \
  -X POST "${api_base_url%/}/chat/completions" \
  -H "Authorization: Bearer ${api_key}" \
  -H "Content-Type: application/json" \
  -d "$payload" 2>&1)
curl_exit=$?

if [ $curl_exit -ne 0 ]; then
  log "curl failed (exit $curl_exit): ${response:0:200}"
  echo "curl failed: $response" >&2
  exit 2
fi

content=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
if [ -z "$content" ]; then
  err=$(echo "$response" | jq -r '.error.message // .error // "unknown"' 2>/dev/null)
  log "no content in response: $err"
  echo "no content: $err" >&2
  exit 2
fi

log "ok (model=$model, output=$(echo -n "$content" | wc -c | tr -d ' ') chars)"
printf '%s' "$content"
exit 0
