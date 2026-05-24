#!/usr/bin/env bash
# Concierge Stop hook — 旁路秘书简报
#
# 设计原则：失败时静默退出 0，不在用户聊天流里冒出红色错误。
# 所有诊断写到 ~/.concierge/stop-hook.log，用户主动看才看到。
#
# v0.3.1: 移除 tac (macOS 不可用) 换 jq 跨平台读 transcript；
#         移除 set -euo pipefail，任何错误都吞掉 exit 0；
#         加 debug log。

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
LOG_DIR="${HOME}/.concierge"
LOG="${LOG_DIR}/stop-hook.log"

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# 包装：任何未预料的失败都退出 0，不打扰用户
trap 'log "trap: caught error at line $LINENO"; exit 0' ERR

input=$(cat 2>/dev/null)
if [ -z "$input" ]; then
  log "skip: empty hook input"
  exit 0
fi

# 防递归
if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null; then
  log "skip: stop_hook_active=true"
  exit 0
fi

# 全局/项目级静音
if [ -f "${HOME}/.concierge-mute" ]; then
  log "skip: ~/.concierge-mute"
  exit 0
fi
project_dir=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
if [ -n "$project_dir" ] && [ -f "${project_dir}/.concierge-mute" ]; then
  log "skip: project mute"
  exit 0
fi

# 读 transcript 路径
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
if [ -z "$transcript_path" ]; then
  log "skip: no transcript_path in hook input"
  exit 0
fi
if [ ! -f "$transcript_path" ]; then
  log "skip: transcript file does not exist: $transcript_path"
  exit 0
fi

# 用 jq slurp 把 JSONL 转成数组，取最后一个 assistant 消息的 text 内容
# 完全跨平台，不依赖 tac/tail -r 这类 GNU/BSD 特定命令
last_assistant=$(jq -rs '
  map(select(.type == "assistant"))
  | if length == 0 then ""
    else
      (last | .message.content) as $c
      | if ($c | type) == "string" then $c
        elif ($c | type) == "array" then
          [$c[] | select(.type == "text") | .text] | join("\n")
        else "" end
    end
' "$transcript_path" 2>/dev/null)

# 长度截断（防极长输出把 LLM 调用撑爆）
last_assistant=$(printf '%s' "$last_assistant" | head -c 50000 2>/dev/null)

if [ -z "$last_assistant" ]; then
  log "skip: no assistant content extracted (fresh session or non-text-only response)"
  exit 0
fi

# 调 digest 后端，错误也吞掉
brief=$(printf '%s' "$last_assistant" | bash "${PLUGIN_ROOT}/scripts/digest.sh" 2>>"$LOG")
brief_exit=$?

if [ $brief_exit -ne 0 ] || [ -z "$brief" ]; then
  log "skip: digest.sh exited $brief_exit, brief empty=$([ -z "$brief" ] && echo yes || echo no)"
  exit 0
fi

# 用 full-schema systemMessage 渲染（workaround for issue #50542）
output=$(jq -nc --arg msg "$brief" '{
  continue: true,
  suppressOutput: false,
  systemMessage: $msg
}' 2>/dev/null)

if [ -z "$output" ]; then
  log "skip: failed to build output JSON"
  exit 0
fi

printf '%s\n' "$output"
log "ok: rendered brief ($(printf '%s' "$brief" | wc -c | tr -d ' ') chars)"
exit 0
