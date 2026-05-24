#!/usr/bin/env bash
# Concierge SessionStart hook
# 注入秘书契约 + 首次配置提示
#
# v0.3.1: 移除 set -euo pipefail，任何错误都退出 0（不阻塞会话）

LOG_DIR="${HOME}/.concierge"
LOG="${LOG_DIR}/session-start.log"

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

trap 'log "trap: caught error at line $LINENO"; exit 0' ERR

CONTRACT_FILE="${CLAUDE_PLUGIN_ROOT}/prompts/secretary-contract.md"
CONFIG_FILE="${HOME}/.concierge/config.json"

if [ ! -f "$CONTRACT_FILE" ]; then
  log "skip: contract file missing at $CONTRACT_FILE"
  exit 0
fi

if [ -f "${HOME}/.concierge-mute" ]; then
  log "skip: ~/.concierge-mute"
  exit 0
fi
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/.concierge-mute" ]; then
  log "skip: project mute"
  exit 0
fi

content=$(cat "$CONTRACT_FILE" 2>/dev/null)
if [ -z "$content" ]; then
  log "skip: contract file empty"
  exit 0
fi

# 根据配置状态追加运行时提示
config_note=""
if [ ! -f "$CONFIG_FILE" ]; then
  config_note=$'\n\n---\n\n## 七、首次运行提示\n\n用户尚未配置 `~/.concierge/config.json`。秘书简报功能（Stop 旁路）需要这个配置才能启用。\n\n**在用户的下一次提问中，回答完用户的真实请求之后**（不要打断他们的真正问题），用一句话告诉用户：\n\n> "顺便提醒：Concierge 秘书首次运行 — 自动简报功能需要配置一个 OpenAI-compatible API。运行 `/sec-setup` 开始配置，或者继续不配也行（仅缺自动简报）。"\n\n只在第一次会话提示一次，用户跳过后会写入禁用标记，之后不再提示。'
  log "first-run notice appended"
elif [ -f "$CONFIG_FILE" ]; then
  disabled=$(jq -r '.disabled // false' "$CONFIG_FILE" 2>/dev/null)
  if [ "$disabled" != "true" ]; then
    api_key=$(jq -r '.apiKey // ""' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$api_key" ]; then
      config_note=$'\n\n---\n\n## 运行时状态\n\n用户已配置秘书简报。Stop hook 会在你每次最终回复后自动追加一段简报（结论/建议/TL;DR 三段），由独立 LLM 调用生成，不影响你的原始 token 流。'
      log "config detected and active"
    fi
  else
    log "config disabled by user"
  fi
fi

full_content="${content}${config_note}"

output=$(jq -nc --arg content "$full_content" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $content
  }
}' 2>/dev/null)

if [ -z "$output" ]; then
  log "skip: failed to build output JSON"
  exit 0
fi

printf '%s\n' "$output"
exit 0
