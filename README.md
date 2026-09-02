# lanes

**Architect mode for Claude Code.** Your session designs, writes specs and judges evidence. Codex lanes do the typing at the reasoning effort each task deserves. A clean-context reviewer decides when it's done. The rules are enforced by hooks and one script, not by asking the model nicely.

```
you ──► Claude session (architect) ──► lanes run routine|escalate ──► Codex CLI writes the code
                │                                    │
                │                          report: diff · verify re-run · exit code
                ▼
        lanes:reviewer (Fable, clean context, read-only) ──► ship / fix / rethink
                │
        Stop hook: no "done" until the tree has a ship verdict
```

## What is enforced, and how

| Rule | Mechanism |
|---|---|
| The architect never edits files | PreToolUse hook denies Edit, Write, MultiEdit and NotebookEdit while architect mode is on |
| Every spec has an objective, files and a verification command | `lanes run` refuses the spec otherwise (exit 5) |
| A reasoning effort is named per task and never rounded | `--effort` is required; a rung the lane's model lacks is refused (exit 5) |
| An empty diff is not a success | `lanes run` compares content hashes of the tree before and after; exit 2 |
| Verification is re-run, not trusted | `lanes run` runs the spec's VERIFY command itself and shows the output; exit 1 on failure |
| Two lanes can't clobber each other | `--worktree` runs the lane in a throwaway worktree seeded with your uncommitted tree and returns a patch |
| The reviewer is read-only | PreToolUse hook limits its shell to `git diff/status/log/show/blame/ls-files` and `lanes reviewed` |
| Nothing ships without a review | Stop hook blocks the end of a turn while the tree differs from the last ship verdict |
| Model names live in one place | `lanes.conf`; `lanes doctor` cross-checks the slugs and effort rungs against Codex's own model list |
| Codex missing or logged out fails loudly | exit 4 with the fix; there is no silent fallback to a Claude lane |

What is still instruction rather than mechanism: the routing choice itself (routine vs escalate, which rung), and the architect not typing code through `cat > file` in Bash. The skill states both; the hooks don't police shell redirects.

## Install

```
/plugin marketplace add surim0n/lanes
/plugin install lanes@lanes
```

Requirements: Claude Code with plugin support, `git`, and the [Codex CLI](https://github.com/openai/codex) logged in (`npm i -g @openai/codex && codex login`). Then:

```
/lanes:doctor
```

## Use

1. Start the session on the model you want as architect (`/model fable` or `/model opus`).
2. `/lanes:architect on`. From now on Edit and Write are blocked and the review gate is armed.
3. Ask for work. The `routing` skill tells the session how to spec and route it:

```
Add rate limiting to the public API. Design it, delegate the implementation, verify the evidence.
```

The session writes a spec, runs a lane, reads the report, and calls `lanes:reviewer` before it can report done. `/lanes:status` shows mode, gate and models at any time. `/lanes:architect off` when you want to edit by hand again.

Optional, to make the doctrine always-on, add one line to your project's `CLAUDE.md`:

```
Work in architect mode: delegate all implementation through `lanes run`, name an effort per task, and get a lanes:reviewer verdict before reporting done.
```

## The lanes

| Lane | Default model | Efforts | Route here when |
|---|---|---|---|
| routine | gpt-5.6-luna | low … max | The spec fully determines the outcome. Default. |
| escalate | gpt-5.6-sol | low … ultra | Judgment the spec can't carry decides the outcome, or routine failed the same spec twice. |

Both run through `codex exec` in a `workspace-write` sandbox with no network (add `--network` for package installs). Change models in `lanes.conf`, per project in `.claude/lanes.conf`, per run with `--model`.

## The spec

```
OBJECTIVE:
One paragraph. What to build and what done looks like.

FILES:
src/limiter.ts        (create)
src/index.ts          (modify)

INTERFACES:
export function limit(key: string, opts: { rps: number }): Promise<boolean>

CONSTRAINTS:
No new dependencies. Don't touch the auth middleware.

VERIFY:
npm test -- limiter
```

`lanes spec-template` prints a blank one. Headers may also be markdown (`## Objective`).

## The script

```
lanes run <routine|escalate> --effort <rung> [--model m] [--timeout s] [--worktree] [--network] [--dry-run] [SPEC|-]
lanes doctor            codex install and login, models vs Codex's list, timeout backend, repo state
lanes status            architect mode, gate, resolved lanes
lanes mode on|off       architect mode
lanes reviewed          record a verdict (the reviewer calls this; never the architect)
lanes spec-template     blank spec
```

`lanes run` exit codes: 0 complete, 1 verify failed, 2 empty diff, 3 timeout, 4 codex unavailable, 5 usage or spec error, 6 codex error. Every run leaves `spec.md`, `prompt.md`, `codex.log`, `final.md`, `verify.log`, `changes.patch` and `report.txt` under `$TMPDIR/lanes/<timestamp>-<lane>/`.

The plugin's `bin/` is on the session's PATH, so the session types `lanes …` directly. State lives in `.git/lanes/` of the checkout: nothing to commit, nothing to gitignore.

## The gate

While architect mode is on, the Stop hook compares a content hash of the working tree (tracked and untracked, `.gitignore` respected) with the hash recorded by the last `ship` verdict. If they differ, the turn can't end; the reason tells the session to run the reviewer. The hook fires once per stop and yields on the immediate retry, so a session that genuinely needs to ask you something can. It fires again next turn. Commits don't clear it; only a ship verdict on the current content does.

## Degraded setups

- **No Fable on the account**: change `model: fable` to `opus` in `agents/reviewer.md`.
- **No Codex**: the lanes exit 4. Turn architect mode off and keep the reviewer; you lose the cross-vendor typing, not the gate.
- **No `timeout` binary**: `lanes` falls back to `gtimeout`, then `perl`, then warns and runs uncapped. `brew install coreutils` on macOS.
- **No `jq`**: hooks parse with `sed`; `lanes doctor` skips the model cross-check.

## Development

```
tests/run.sh               96 tests against a fake codex; runs on bash 3.2 (macOS default) and 5
tests/lint-frontmatter.sh  agents, commands and skill have frontmatter with a short description
claude plugin validate .
```

CI runs all three on macOS and Linux, plus shellcheck and a link check.

## License

MIT
