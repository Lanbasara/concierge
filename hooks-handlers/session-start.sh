#!/usr/bin/env bash
# Concierge SessionStart hook
# 读取秘书契约 markdown，JSON 编码后作为 additionalContext 注入到会话系统指引

set -euo pipefail

CONTRACT_FILE="${CLAUDE_PLUGIN_ROOT}/prompts/secretary-contract.md"

if [ ! -f "$CONTRACT_FILE" ]; then
  # 契约文件缺失，静默退出（fail open — 不卡住会话）
  exit 0
fi

# 用户级开关：若家目录有 .concierge-mute 文件，本次会话不注入契约
if [ -f "${HOME}/.concierge-mute" ]; then
  exit 0
fi

# 项目级开关：若当前项目目录有 .concierge-mute 文件，本次会话不注入契约
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/.concierge-mute" ]; then
  exit 0
fi

content=$(cat "$CONTRACT_FILE")

# 用 jq 安全地把 markdown 内容 JSON 编码进 additionalContext
jq -nc --arg content "$content" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $content
  }
}'

exit 0
