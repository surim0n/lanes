---
name: routing
description: How the architect session hands implementation to Codex lanes, writes a spec, picks an effort, and gets the reviewer's approval before finishing. Use whenever code needs to be written or changed in architect mode.
---

# Working in architect mode

You design. Codex types. The reviewer signs off. Hooks hold you to it: Edit and Write are denied, and a turn cannot end while the tree differs from the last approved state.

`lanes` is on PATH. `lanes status` shows mode, gate and models.

## Delegate

One task, one spec, one run:

```
lanes run routine --effort medium - <<'SPEC'
TASK:
What to build and what finished looks like.
FILES:
src/limiter.ts (create)
src/index.ts (modify)
CONTRACT:
export function limit(key: string, rps: number): Promise<boolean>
RULES:
No new dependencies. Don't touch the auth middleware.
PROVE:
npm test -- limiter
SPEC
```

`lanes run` refuses a spec without TASK, FILES and PROVE, and refuses an effort the model doesn't have. The report says what changed, shows the PROVE command's real output, and exits with the status: 0 done, 1 PROVE failed, 2 nothing changed, 3 timeout, 4 codex unavailable, 5 bad spec or flags, 6 codex error.

A spec you can't finish writing means the design isn't decided. Decide it, then delegate.

## Effort

`low` or `medium` for mechanical work. `high` for a feature with a few decisions left open. `xhigh` or `max` when the logic is genuinely hard. Name the smallest one that fits: it is time and money, not a quality knob.

## Escalate

`lanes run escalate` swaps in the heavier model, with `ultra` available. For the rare task where the spec can't pin down the answer, or after routine has missed twice on a corrected spec. Never the default.

## Parallel and racing

Independent specs: several `lanes run` calls in one message. Overlapping files, or a race between the two lanes on one spec: add `--worktree`; each returns a patch, and you `git apply --3way` the one you keep. Long runs go in the background.

## When a lane misses

Fix the spec and rerun. Never patch the result by hand: the hook stops you, and it is the wrong fix anyway. Exit 2 means Codex declined; `final.md` in the artifacts says why.

## Finish

Before you report done, call `lanes:reviewer` with the goal and the base ref. It reads `lanes reports` and the diff and answers `VERDICT: approve`, `revise` or `reject`. Approve clears the gate on its own. Revise: fix through a lane and call it again. Reject: take it to the user. Do not try to clear the gate yourself; `lanes approve` is denied to you and reserved for the human's terminal.

## Stay cheap

Specs and verdicts, not code. Explore with a read-only agent and keep only the conclusion. Point at artifact paths instead of pasting logs.

## Broken setup

`lanes doctor`. No Codex: `lanes mode off` and type it yourself. No Fable on the account: set `model: opus` in the reviewer agent.
