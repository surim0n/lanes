---
description: Check the lanes setup — Codex install and login, configured models against Codex's model list, timeout backend, repo state.
allowed-tools: Bash(lanes:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/lanes:*)
---
!`"${CLAUDE_PLUGIN_ROOT}/bin/lanes" doctor`

Show the user the report above. For each ✗ line, say the one command that fixes it (the line already names it). If no output appears above, run `lanes doctor` yourself.
