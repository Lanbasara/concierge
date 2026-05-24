# 安装与启用

## 方式一：作为本地插件加载（推荐）

Claude Code 支持从本地目录加载插件。在你的 Claude Code 配置中把 `~/concierge` 添加为本地插件源。

具体步骤：

1. 确认插件目录完整：

   ```bash
   ls ~/concierge/.claude-plugin/plugin.json
   ls ~/concierge/hooks/hooks.json
   ls ~/concierge/hooks-handlers/session-start.sh
   ```

2. 在 Claude Code 里执行 `/plugins` 命令，添加本地路径 `~/concierge`。

3. 启用插件后，**重启 Claude Code 会话**（hooks 只在会话启动时加载）。

4. 验证：随便发一条消息，观察 Claude 是否：
   - 不再写"好的"、"让我们来看看"等开场白
   - 答案首句直接给结论
   - 列表保持 ≤ 4 项

## 方式二：直接复制到全局 hooks（快速测试用）

不打包成插件，直接把 hook 注册到全局 settings.json：

```bash
# 备份
cp ~/.claude/settings.json ~/.claude/settings.json.bak

# 编辑 ~/.claude/settings.json，在 "hooks" 字段下添加：
#
# "SessionStart": [
#   {
#     "hooks": [
#       {
#         "type": "command",
#         "command": "bash /home/ubuntu/concierge/hooks-handlers/session-start.sh"
#       }
#     ]
#   }
# ]
```

注意：手动改 settings.json 时 `CLAUDE_PLUGIN_ROOT` 变量不会自动注入，需要在 script 里改用绝对路径。建议优先用方式一。

## 验证 hook 已生效

启动新会话后运行 `/hooks` 命令，应能看到 `SessionStart` 下出现 concierge 的条目。

也可以手动执行 hook 看 JSON 输出是否正常：

```bash
CLAUDE_PLUGIN_ROOT=/home/ubuntu/concierge bash /home/ubuntu/concierge/hooks-handlers/session-start.sh | jq .
```

期望看到 `hookSpecificOutput.additionalContext` 字段里是契约 markdown 全文。

## 临时关闭

不想卸载插件、只想暂停秘书：

```bash
# 全局关闭
touch ~/.concierge-mute

# 仅当前项目关闭
cd /your/project
touch .concierge-mute
```

删掉文件即恢复。**下次新会话生效**（hook 只在 SessionStart 读取）。

## 卸载

```bash
# 方式一：在 Claude Code 的 /plugins 里禁用或移除
# 方式二：删除目录
rm -rf ~/concierge
```
