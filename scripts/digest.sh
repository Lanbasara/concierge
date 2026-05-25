#!/usr/bin/env bash
# Concierge 出口简报后端
# 从 stdin 读取 Claude 的原始回复，调 llm-call.sh 生成秘书简报
# v0.4.0：读 priorities，让简报对照 Boss 关心的事高亮
#
# 退出码：
#   0 — 成功，简报在 stdout
#   1 — 配置缺失/禁用
#   2 — API 失败

LOG_DIR="${HOME}/.concierge"
LOG="${LOG_DIR}/digest.log"

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="${SCRIPT_DIR}/../prompts/digest-system.md"

CONFIG_FILE="${HOME}/.concierge/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  log "skip: no config"
  echo "Concierge: 配置文件不存在 (~/.concierge/config.json)，运行 /sec-setup 配置" >&2
  exit 1
fi

disabled=$(jq -r '.disabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$disabled" = "true" ]; then
  log "skip: disabled"
  echo "Concierge: 简报功能已被用户禁用" >&2
  exit 1
fi

brief_enabled=$(jq -r '.briefEnabled // true' "$CONFIG_FILE" 2>/dev/null)
if [ "$brief_enabled" = "false" ]; then
  log "skip: briefEnabled=false"
  echo "Concierge: briefEnabled=false" >&2
  exit 1
fi

message=$(cat)
if [ -z "$message" ]; then
  log "skip: empty input"
  echo "Concierge: digest 输入为空" >&2
  exit 1
fi

# 最小长度门控
min_chars=$(jq -r '.briefMinChars // 0' "$CONFIG_FILE" 2>/dev/null)
msg_len=$(printf '%s' "$message" | wc -c | tr -d ' ')
if [ "$msg_len" -lt "$min_chars" ]; then
  log "skip: $msg_len chars < $min_chars threshold"
  exit 1
fi

# 读 system prompt
if [ ! -f "$PROMPT_FILE" ]; then
  log "skip: digest-system.md missing"
  echo "Concierge: digest-system.md 缺失" >&2
  exit 2
fi
system_prompt=$(cat "$PROMPT_FILE")

# 读 priorities（全局 + 项目级，参考 Boss 的优先级让简报更个性化）
priorities_global=""
priorities_project=""
if [ -f "${HOME}/.concierge/priorities.md" ]; then
  priorities_global=$(cat "${HOME}/.concierge/priorities.md" 2>/dev/null)
fi
# 项目级 priorities — 试着探测 PWD（hook 不一定在 cwd 里跑，用 PWD 作启发）
if [ -n "${PWD:-}" ] && [ -f "${PWD}/.concierge-priorities.md" ]; then
  priorities_project=$(cat "${PWD}/.concierge-priorities.md" 2>/dev/null)
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

# 构造给 LLM 的 user content
if [ -n "$priorities_combined" ]; then
  user_content="<boss_priorities>
${priorities_combined}
</boss_priorities>

<claude_reply>
${message}
</claude_reply>"
else
  user_content="$message"
fi

# 调共享 LLM 后端，温度调到 0.5 给秘书一点判断空间（v0.4.2+）
content=$(bash "${SCRIPT_DIR}/llm-call.sh" "$system_prompt" "$user_content" 0.5 2>>"$LOG")
llm_exit=$?

if [ $llm_exit -ne 0 ]; then
  log "llm-call.sh exited $llm_exit"
  exit $llm_exit
fi

if [ -z "$content" ]; then
  log "empty content from llm-call.sh"
  echo "Concierge: digest 返回空" >&2
  exit 2
fi

log "ok ($(printf '%s' "$content" | wc -c | tr -d ' ') chars)"
printf '%s' "$content"
exit 0
