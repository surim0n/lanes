# Changelog

## 0.2.0

- Spec sections are now TASK, FILES, CONTRACT, RULES, PROVE. TASK, FILES and PROVE are required.
- The reviewer's verdict is captured by a SubagentStop hook from its own output (`VERDICT: approve | revise | reject`). No shell call records a verdict any more.
- `lanes approve` is a human override for your own terminal; a hook denies it to Claude in architect mode.
- `lanes reports` gives the reviewer every lane report since the last approval, so it judges the PROVE evidence, not just the diff.
- Report statuses renamed: done, prove-failed, no-change, timeout, unavailable, error.

## 0.1.0

Initial release: `lanes` script, routine and escalate lanes through the Codex CLI, worktree mode, hook-enforced architect mode, read-only reviewer, Stop-hook review gate, `lanes.conf`.
