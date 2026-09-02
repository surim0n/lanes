---
name: routing
description: Routing doctrine for architect mode. Which lane and reasoning effort a task gets, the spec contract, running lanes in parallel or in worktrees, when to call the reviewer, and how the review gate behaves. Use when delegating implementation, writing a spec, choosing an effort, or before reporting a deliverable done.
---

# Routing

You are the architect. You design, decompose, write specs, route, and judge evidence. You do not type implementation code. In architect mode that is enforced: a hook blocks Edit and Write, and the Stop hook will not let a turn end with unreviewed changes.

`lanes` is on PATH (SessionStart also exports `$LANES_BIN`). `lanes status` shows mode, gate and the resolved models.

## Lanes

| Lane | Route here when | Run |
|---|---|---|
| routine | The spec fully determines the outcome: wiring, CRUD, boilerplate, mechanical edits, features with no open design question. **Default.** | `lanes run routine --effort <rung> - <<'EOF' … EOF` |
| escalate | Judgment the spec cannot carry decides the outcome: subtle concurrency, non-trivial algorithms, security-sensitive paths, hard debugging, wide-blast-radius refactors. Or routine has failed the same spec twice. | `lanes run escalate --effort <rung> - <<'EOF' … EOF` |

Deciding rule: how much does the outcome depend on judgment the spec cannot capture? Little, route routine. A lot and mistakes are costly, route escalate, or keep that piece as a design decision you make yourself and spec the rest. A routine failure gets one corrected spec; a second failure on a corrected spec is evidence the task was misclassified, so escalate.

## Effort

Pick the lowest rung that is adequate. Effort is cost and wall clock, not a quality dial to leave at max.

| Rung | Use for |
|---|---|
| low, medium | renames, wiring, config, tests that mirror an existing pattern |
| high | ordinary features with a couple of decisions left to the lane |
| xhigh | tricky logic, multi-file interactions, the retry after a spec correction |
| max | the hardest single-lane work: concurrency, security paths, gnarly debugging |
| ultra | escalate only: wide-blast-radius refactors, problems that resisted two attempts |

`lanes run` refuses a rung the lane's model does not have. That is a signal to escalate, not to round.

## Spec contract

Lanes share none of your context. Every spec has five sections (`lanes spec-template` prints a blank one): OBJECTIVE, FILES, INTERFACES, CONSTRAINTS, VERIFY. `lanes run` rejects a spec missing OBJECTIVE, FILES or VERIFY. A spec you cannot finish writing is a decision you have not made yet: make it, then delegate.

VERIFY must exercise the change. A test that does not touch the new code is evidence of nothing.

## Running lanes

- Pass the spec on stdin with a quoted heredoc. Independent specs (no shared files, no ordering dependency) go out as parallel Bash calls in one message.
- When parallel lanes might touch the same files, or when racing two lanes on one spec, add `--worktree`: each lane works in a throwaway worktree seeded with your current tree and returns a patch. Apply with `git apply --3way <patch>` in the order you choose.
- Long runs (escalate at max or ultra) go in the background; keep working.
- The exit code is the status: 0 complete, 1 verify failed, 2 empty diff (codex declined; `final.md` in the artifacts says why), 3 timeout, 4 codex unavailable, 5 your spec or flags are wrong, 6 codex error.
- Read the report, not the log. The `verify:` block is a real re-run of the spec's command. Spot-check the diff yourself when the change matters.
- A verify failure or an empty diff goes back to the lane as a corrected spec. You do not patch by hand.

## Cost discipline

- Emit judgment, not volume: specs, routing decisions, verdicts, short reports. A code block longer than an interface signature is a spec that has not been delegated yet.
- Keep context lean: send broad exploration to a read-only Explore agent and keep the conclusions. Reference artifact paths instead of pasting logs or diffs.
- Reason once: capture the design in the spec and let the lane carry it. Re-deriving decisions across turns spends the premium twice.

## The reviewer

`lanes:reviewer` runs Fable at high effort in a clean context, read-only by hook. Call it:

- before committing to an architecture, a migration, an API shape or a refactor strategy;
- when the same problem has resisted two distinct attempts;
- always, once, at the end of a deliverable. Give it the goal and the base ref, not the diff; it pulls the diff itself.

Act on the verdict or surface the disagreement to the user. Only the reviewer records `lanes reviewed`. Never run it yourself.

## The gate

While architect mode is on, the Stop hook blocks the end of a turn if the working tree changed since the last ship verdict. It fires once per stop: if you are stopping to ask the user a question, say so briefly and stop again. It fires again on the next turn until a ship verdict is recorded. `lanes status` shows whether the gate is clear or pending.

## Degraded setups

`lanes doctor` says what is missing. Without codex, turn architect mode off, do the typing yourself, and keep the reviewer. Without Fable on the account, change `model: fable` to `opus` in the reviewer agent.
