#!/usr/bin/env bash
# Concierge UserPromptSubmit hook (command type)
# 把 Boss 的口语输入翻译成结构化笔记给 Claude
#
# 失败时静默 exit 0，不阻塞用户。所有诊断写 ~/.concierge/improve-prompt.log

LOG_DIR="${HOME}/.concierge"
LOG="${LOG_DIR}/improve-prompt.log"

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

trap 'log "trap: caught error at line $LINENO"; exit 0' ERR

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"

input=$(cat 2>/dev/null)
if [ -z "$input" ]; then
  log "skip: empty hook input"
  exit 0
fi

user_prompt=$(printf '%s' "$input" | jq -r '.user_prompt // ""' 2>/dev/null)
if [ -z "$user_prompt" ]; then
  log "skip: no user_prompt in hook input"
  exit 0
fi

# 全局/项目级静音
if [ -f "${HOME}/.concierge-mute" ]; then
  log "skip: ~/.concierge-mute"
  exit 0
fi
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
if [ -n "$cwd" ] && [ -f "${cwd}/.concierge-mute" ]; then
  log "skip: project mute"
  exit 0
fi

# 配置检查
CONFIG_FILE="${HOME}/.concierge/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  log "skip: no config (~/.concierge/config.json), improver needs API"
  exit 0
fi

disabled=$(jq -r '.disabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$disabled" = "true" ]; then
  log "skip: config disabled"
  exit 0
fi

improver_enabled=$(jq -r '.improverEnabled // true' "$CONFIG_FILE" 2>/dev/null)
if [ "$improver_enabled" = "false" ]; then
  log "skip: improverEnabled=false"
  exit 0
fi

# 廉价启发式：太短的输入跳过（trivial）
min_chars=$(jq -r '.improverMinChars // 30' "$CONFIG_FILE" 2>/dev/null)
prompt_len=$(printf '%s' "$user_prompt" | wc -c | tr -d ' ')
if [ "$prompt_len" -lt "$min_chars" ]; then
  log "skip: prompt $prompt_len chars < $min_chars threshold"
  exit 0
fi

# 读 priorities（全局 + 项目级）
priorities_global=""
priorities_project=""
if [ -f "${HOME}/.concierge/priorities.md" ]; then
  priorities_global=$(cat "${HOME}/.concierge/priorities.md" 2>/dev/null)
fi
if [ -n "$cwd" ] && [ -f "${cwd}/.concierge-priorities.md" ]; then
  priorities_project=$(cat "${cwd}/.concierge-priorities.md" 2>/dev/null)
fi

priorities_combined=""
if [ -n "$priorities_global" ]; then
  priorities_combined="$priorities_global"
fi
if [ -n "$priorities_project" ]; then
  if [ -n "$priorities_combined" ]; then
    priorities_combined="${priorities_combined}

---

# Project-specific overrides

${priorities_project}"
  else
    priorities_combined="$priorities_project"
  fi
fi

if [ -z "$priorities_combined" ]; then
  priorities_combined="（无优先级文件，按通用判断）"
fi

# 读 improver system prompt
SYSTEM_PROMPT_FILE="${PLUGIN_ROOT}/prompts/improve-system.md"
if [ ! -f "$SYSTEM_PROMPT_FILE" ]; then
  log "skip: improve-system.md missing"
  exit 0
fi
system_prompt=$(cat "$SYSTEM_PROMPT_FILE" 2>/dev/null)

# 构造 user content（含 priorities + Boss 输入）
user_content="<boss_priorities>
${priorities_combined}
</boss_priorities>

<boss_input>
${user_prompt}
</boss_input>"

# 调 LLM
result=$(bash "${PLUGIN_ROOT}/scripts/llm-call.sh" "$system_prompt" "$user_content" 2>>"$LOG")
llm_exit=$?

if [ $llm_exit -ne 0 ]; then
  log "skip: llm-call.sh exited $llm_exit"
  exit 0
fi

if [ -z "$result" ]; then
  log "skip: llm returned empty"
  exit 0
fi

# 大写 NONE 表示 TRIVIAL/STANDARD，无需注入
trimmed=$(printf '%s' "$result" | tr -d '[:space:]')
if [ "$trimmed" = "NONE" ]; then
  log "skip: classified as TRIVIAL/STANDARD"
  exit 0
fi
# 容错：开头是 NONE 也算
if printf '%s' "$result" | head -c 10 | grep -qE '^NONE\b'; then
  log "skip: classified as TRIVIAL/STANDARD (prefix match)"
  exit 0
fi

# 输出 additionalContext 注入给 Claude
output=$(jq -nc --arg msg "$result" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $msg
  }
}' 2>/dev/null)

if [ -z "$output" ]; then
  log "skip: failed to build output JSON"
  exit 0
fi

printf '%s\n' "$output"
log "ok: injected translation ($(printf '%s' "$result" | wc -c | tr -d ' ') chars)"
exit 0
