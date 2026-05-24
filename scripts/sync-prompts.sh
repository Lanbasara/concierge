#!/usr/bin/env bash
# 重建 hooks/hooks.json
# v0.4.0: 三个 hook 都是 command type，不再 embed prompt body 到 hooks.json
#         （prompts/ 下的 markdown 由各自的 script 直接读取运行时）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

jq -n '{
  description: "Concierge v0.4.0 — SessionStart 契约 + UserPromptSubmit 输入翻译 + Stop 出口简报 (全旁路)",
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
            type: "command",
            command: "bash \"${CLAUDE_PLUGIN_ROOT}/hooks-handlers/improve-prompt.sh\"",
            timeout: 45
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

echo "✓ hooks/hooks.json 已重建 (v0.4.0)"
echo "  SessionStart       → command (session-start.sh)   — 契约 + 首次配置提示"
echo "  UserPromptSubmit   → command (improve-prompt.sh)  — 输入翻译为 XML 结构 (新)"
echo "  Stop               → command (stop-digest.sh)     — 出口简报 (现读 priorities)"
