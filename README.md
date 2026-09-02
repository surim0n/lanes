# lanes

![lanes: Claude writes the spec, Codex implements it, a fresh reviewer must approve](assets/banner.svg)

**Architect mode for Claude Code.** Claude turns your request into a concrete specification, Codex implements it at the reasoning level you name, the specified proof command is re-run independently, and a fresh read-only reviewer must approve the result before Claude can call the task done.

```
you ──► Claude (architect) ──► lanes run ──► Codex writes the code
              │                                   │
              │                    report: diff · PROVE re-run · exit code
              ▼
        lanes:reviewer (fresh context, read-only) ──► VERDICT: approve | revise | reject
              │
        Stop hook: no "done" until the tree matches an approval
```

## Install

```
/plugin marketplace add surim0n/lanes
/plugin install lanes@lanes
```

Needs `git` and the [Codex CLI](https://github.com/openai/codex) logged in (`npm i -g @openai/codex && codex login`). Then `/lanes:doctor`.

## Use

1. Put the session on the model you want as architect: `/model fable` or `/model opus`.
2. `/lanes:architect on`. Edit and Write are now blocked and the review gate is armed.
3. Ask for work:

```
Add rate limiting to the public API.
```

Claude writes a spec, runs a lane, reads the report, and calls the reviewer before it can report done. `/lanes:status` shows mode, gate and models. `/lanes:architect off` when you want to edit by hand again.

## What is enforced, what has a known hole, what is only asked

| Rule | How |
|---|---|
| Claude never edits files | PreToolUse hook denies Edit, Write, MultiEdit, NotebookEdit |
| Every spec has a task, files and a proof command | `lanes run` refuses it otherwise (exit 5) |
| An effort is named per task and never rounded | `--effort` is required; a rung the model lacks is refused |
| "It worked" is not evidence | `lanes run` re-runs PROVE itself and shows the output (exit 1 on failure) |
| An empty diff is not a success | tree hash before vs after (exit 2) |
| Parallel lanes can't clobber each other | `--worktree` runs the lane on a copy and returns a patch |
| The reviewer can't change anything | PreToolUse hook limits its shell to git reads, `lanes reports`, `lanes status` |
| The reviewer sees the evidence | `lanes reports` holds every report since the last approval |
| Only the reviewer clears the gate | its `VERDICT:` line is read from its own transcript by a SubagentStop hook; `lanes approve` is denied to Claude and reserved for your terminal |
| Nothing is done until approved | Stop hook blocks the turn while the tree differs from the approved hash |

Known holes, stated plainly:

- The Stop gate yields on the immediate retry, so a session that needs to ask you something can. It fires again next turn.
- Claude could prompt its own reviewer to rubber-stamp. The reviewer is told not to; that is a prompt, not a mechanism.
- Hooks don't police shell redirects. `cat > file` in Bash is only forbidden by the skill.

Everything above is a workflow guardrail against a lazy or hurried session, not a security boundary against an adversarial one.

## The lanes

| Lane | Default model | Efforts | Use |
|---|---|---|---|
| routine | gpt-5.6-luna | low … max | Everything, unless below |
| escalate | gpt-5.6-sol | low … ultra | The rare task the spec can't pin down, or a routine miss twice on a corrected spec |

Both run `codex exec` in a `workspace-write` sandbox with no network (`--network` for package installs). Model names live only in `lanes.conf`; override per project in `.claude/lanes.conf` or per run with `--model`. `lanes doctor` checks the slugs and effort rungs against Codex's own model list.

## The spec

```
TASK:
What to build and what finished looks like.

FILES:
src/limiter.ts        (create)
src/index.ts          (modify)

CONTRACT:
export function limit(key: string, rps: number): Promise<boolean>

RULES:
No new dependencies. Don't touch the auth middleware.

PROVE:
npm test -- limiter
```

`lanes spec-template` prints a blank one. Headers can also be markdown (`## Task`).

## The script

```
lanes run <routine|escalate> --effort <rung> [--model m] [--timeout s] [--worktree] [--network] [--dry-run] [SPEC|-]
lanes doctor          codex install and login, models vs Codex's list, timeout backend, repo state
lanes status          architect mode, gate, reports pending, resolved lanes
lanes mode on|off     architect mode
lanes reports         every lane report since the last approval
lanes approve         human override from your terminal (Claude is denied it)
lanes spec-template   blank spec
```

Exit codes for `run`: 0 done, 1 PROVE failed, 2 nothing changed, 3 timeout, 4 codex unavailable, 5 usage or spec error, 6 codex error. Every run leaves `spec.md`, `prompt.md`, `codex.log`, `final.md`, `prove.log`, `changes.patch` and `report.txt` under `$TMPDIR/lanes/<timestamp>-<lane>/`.

The plugin's `bin/` is on the session's PATH. State lives in `.git/lanes/` of the checkout: nothing to commit, nothing to gitignore.

## Degraded setups

- No Fable on the account: change `model: fable` to `opus` in `agents/reviewer.md`.
- No Codex: lanes exit 4. Turn architect mode off and keep the reviewer.
- No `timeout` binary: `lanes` falls back to `gtimeout`, then `perl`, then warns and runs uncapped.
- No `jq`: hooks parse with `sed`; `lanes doctor` skips the model cross-check.

## Development

```
tests/run.sh               tests against a fake codex; runs on bash 3.2 (macOS default) and 5
tests/lint-frontmatter.sh  agents, commands and skill have frontmatter with a short description
claude plugin validate .
assets/render.sh           re-render assets/banner.png from banner.svg (headless Chrome)
```

CI runs all of it on macOS and Linux, plus shellcheck and a link check.

## License

MIT
