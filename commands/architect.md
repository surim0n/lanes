---
description: Turn architect mode on or off. On blocks Edit/Write for the session and arms the review gate.
argument-hint: "on | off | status"
allowed-tools: Bash(lanes:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/lanes:*)
---
!`"${CLAUDE_PLUGIN_ROOT}/bin/lanes" mode $ARGUMENTS`

Report the line above to the user verbatim. If no output appears above, run `lanes mode $ARGUMENTS` yourself and report that. When mode was just turned on, load the `lanes:routing` skill before doing anything else.
