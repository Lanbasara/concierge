#!/usr/bin/env bash
# 把 prompts/*.md 的 prompt 主体同步到 hooks/hooks.json
# 用法: bash scripts/sync-prompts.sh
#
# v0.3.0: cognitive-guardian 已移除（Stop 改为 command type 旁路）
#         只需同步 intent-clarifier。其他 hook 用固定的 command 路径。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

extract_prompt() {
  local file="$1"
  awk 'found {print} /^---$/ && !found {found=1}' "$file" | sed '/./,$!d'
}

intent=$(extract_prompt "$ROOT/prompts/intent-clarifier.md")

if [ -z "$intent" ]; then
  echo "ERROR: 提取 intent-clarifier 内容为空" >&2
  exit 1
fi

jq -n \
  --arg intent "$intent" \
  '{
    description: "Concierge v0.3.0 — SessionStart 契约 + UserPromptSubmit 意图澄清 + Stop 自动秘书简报 (旁路)",
    hooks: {
      SessionStart: [
        {
          hooks: [
            {
              type: "command",
              command: "bash \"${CLAUDE_PLUGIN_ROOT}/hooks-handlers/session-start.sh\""
            }
          ]
        }
      ],
      UserPromptSubmit: [
        {
          matcher: "*",
          hooks: [
            {
              type: "prompt",
              prompt: $intent,
              timeout: 30
            }
          ]
        }
      ],
      Stop: [
        {
          matcher: "*",
          hooks: [
            {
              type: "command",
              command: "bash \"${CLAUDE_PLUGIN_ROOT}/hooks-handlers/stop-digest.sh\"",
              timeout: 45
            }
          ]
        }
      ]
    }
  }' > "$ROOT/hooks/hooks.json"

echo "✓ hooks/hooks.json 已重建"
echo "  SessionStart       → command (session-start.sh) — 注入契约 + 首次配置提示"
echo "  UserPromptSubmit   → prompt  (intent-clarifier  $(echo -n "$intent" | wc -c) 字符)"
echo "  Stop               → command (stop-digest.sh)   — 旁路秘书简报"
