#!/usr/bin/env bash
# 把 prompts/*.md 的 prompt 主体同步到 hooks/hooks.json
# 用法: bash scripts/sync-prompts.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 提取 markdown 文件中第一个独立 "---" 行之后的内容（跳过元数据块）
extract_prompt() {
  local file="$1"
  awk 'found {print} /^---$/ && !found {found=1}' "$file" | sed '/./,$!d'
}

intent=$(extract_prompt "$ROOT/prompts/intent-clarifier.md")
guardian=$(extract_prompt "$ROOT/prompts/cognitive-guardian.md")

if [ -z "$intent" ] || [ -z "$guardian" ]; then
  echo "ERROR: 提取的 prompt 内容为空，检查 prompts/ 下的源文件格式" >&2
  exit 1
fi

jq -n \
  --arg intent "$intent" \
  --arg guardian "$guardian" \
  '{
    description: "Concierge 秘书层 — SessionStart 契约 + UserPromptSubmit 意图澄清 + Stop 认知守门",
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
              type: "prompt",
              prompt: $guardian,
              timeout: 30
            }
          ]
        }
      ]
    }
  }' > "$ROOT/hooks/hooks.json"

echo "✓ 已同步 prompts/ → hooks/hooks.json"
echo "  intent-clarifier:  $(echo -n "$intent" | wc -c) 字符"
echo "  cognitive-guardian: $(echo -n "$guardian" | wc -c) 字符"
