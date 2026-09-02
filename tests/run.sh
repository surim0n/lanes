#!/usr/bin/env bash
# lanes test suite. Plain bash, no framework. Uses a fake codex on PATH (tests/bin/codex).
# shellcheck disable=SC2015  # "test && ok || ko" is the intended pass/fail idiom here
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
export PATH="$HERE/bin:$ROOT/bin:$PATH"
LANES_RUN_DIR="$(mktemp -d -t lanes-test-runs.XXXXXX)"; export LANES_RUN_DIR
export FAKE_CODEX_ARGS="$LANES_RUN_DIR/args"
unset CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE LANES_CONF LANES_ROUTINE_MODEL LANES_ESCALATE_MODEL FAKE_CODEX_MODE
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0; fail=0
t()  { printf '%-62s' "$1"; }
ok() { echo ok; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
eq()    { if [ "$1" = "$2" ]; then ok; else ko "expected '$2', got '$1'"; fi; }
match() { if printf '%s' "$1" | grep -qE -- "$2"; then ok; else ko "expected /$2/ in: $(printf '%s' "$1" | tr '\n' ' ' | cut -c1-240)"; fi; }
nomatch() { if printf '%s' "$1" | grep -qE -- "$2"; then ko "did not expect /$2/ in: $(printf '%s' "$1" | tr '\n' ' ' | cut -c1-240)"; else ok; fi; }

repo() { local d; d="$(mktemp -d -t lanes-test-repo.XXXXXX)"; d="$(cd "$d" && pwd -P)"; git -C "$d" init -q; git -C "$d" commit -q --allow-empty -m init; printf '%s' "$d"; }
SPEC='OBJECTIVE: write hello
FILES: lane-output.txt
INTERFACES: none
CONSTRAINTS: none
VERIFY: echo VERIFY-MARKER && test -f lane-output.txt'
run() { # dir args… ; spec on stdin ; prints output, sets RC
  local d="$1"; shift
  OUT="$(cd "$d" && lanes run "$@" 2>&1)"; RC=$?
}

echo "== run: argument and spec validation"
d="$(repo)"
t "no lane → exit 5";                 run "$d" --effort high <<<"$SPEC"; eq "$RC" 5
t "missing --effort → exit 5";        run "$d" routine <<<"$SPEC"; eq "$RC" 5
t "  …names the rungs";               match "$OUT" "rungs: low medium high xhigh max"
t "ultra on routine → exit 5";        run "$d" routine --effort ultra <<<"$SPEC"; eq "$RC" 5
t "  …says escalate, not round";      match "$OUT" "Escalate instead of rounding"
t "ultra on escalate → accepted";     run "$d" escalate --effort ultra --dry-run <<<"$SPEC"; eq "$RC" 0
t "spec missing VERIFY → exit 5";     run "$d" routine --effort low <<<"$(printf 'OBJECTIVE: x\nFILES: y')"; eq "$RC" 5
t "  …names the section";             match "$OUT" "missing required section\(s\): VERIFY"
t "markdown headers accepted";        run "$d" routine --effort low --dry-run <<<"$(printf '## Objective\nx\n## Files\ny\n## Verify\ntrue')"; eq "$RC" 0
t "unknown flag → exit 5";            run "$d" routine --effort low --bogus <<<"$SPEC"; eq "$RC" 5
t "outside git → exit 5";             OUT="$(cd /tmp && lanes run routine --effort low --dry-run <<<"$SPEC" 2>&1)"; eq "$?" 5

echo "== run: config resolution"
t "dry-run shows default model";      run "$d" routine --effort high --dry-run <<<"$SPEC"; match "$OUT" "gpt-5.6-luna · effort high · timeout 600s"
t "escalate default model+timeout";   run "$d" escalate --effort max --dry-run <<<"$SPEC"; match "$OUT" "gpt-5.6-sol · effort max · timeout 1800s"
t "--model overrides";                run "$d" routine --effort high --model foo --dry-run <<<"$SPEC"; match "$OUT" "· foo ·"
t "env overrides conf";               OUT="$(cd "$d" && LANES_ROUTINE_MODEL=bar lanes run routine --effort high --dry-run <<<"$SPEC" 2>&1)"; match "$OUT" "· bar ·"
mkdir -p "$d/.claude"; printf 'routine.model = baz\nroutine.timeout = 42\n' > "$d/.claude/lanes.conf"
t "project .claude/lanes.conf overrides"; run "$d" routine --effort high --dry-run <<<"$SPEC"; match "$OUT" "· baz · effort high · timeout 42s"
rm -rf "$d/.claude"

echo "== run: preflight"
t "codex missing → exit 4";           OUT="$(cd "$d" && PATH=/usr/bin:/bin "$ROOT/bin/lanes" run routine --effort low <<<"$SPEC" 2>&1)"; eq "$?" 4
t "codex logged out → exit 4";        OUT="$(cd "$d" && FAKE_CODEX_LOGGED_OUT=1 lanes run routine --effort low <<<"$SPEC" 2>&1)"; eq "$?" 4
t "  …says how to fix";               match "$OUT" "codex login"

echo "== run: outcomes"
d="$(repo)"
t "complete → exit 0";                run "$d" routine --effort high <<<"$SPEC"; eq "$RC" 0
t "  …file landed in the tree";       [ -f "$d/lane-output.txt" ] && ok || ko "no file"
t "  …report says complete";          match "$OUT" "LANE REPORT · routine · gpt-5.6-luna · effort high · [0-9]+m[0-9]+s · complete"
t "  …lists the change";              match "$OUT" "A[[:space:]]+lane-output.txt"
t "  …verify re-run shown";           match "$OUT" "verify: exit 0 · echo VERIFY-MARKER"
t "  …verify output shown";           match "$OUT" "^    VERIFY-MARKER$"
t "  …codex final message shown";     match "$OUT" "^    Wrote lane-output.txt"
t "  …codex got --model";             match "$(cat "$FAKE_CODEX_ARGS")" "^gpt-5.6-luna$"
t "  …codex got quoted effort";       match "$(cat "$FAKE_CODEX_ARGS")" '^model_reasoning_effort="high"$'
t "  …sandbox workspace-write";       match "$(tr '\n' ' ' < "$FAKE_CODEX_ARGS")" "--sandbox workspace-write"
t "  …ephemeral by default";          match "$(cat "$FAKE_CODEX_ARGS")" "^--ephemeral$"
t "  …prompt carries spec + trailer"; ART="$(printf "%s" "$OUT" | sed -n "s/^artifacts: //p")"; OUT2="$(cat "$ART/prompt.md")"; match "$OUT2" "^OBJECTIVE: write hello"
t "  …prompt carries the trailer";     match "$OUT2" "^Lane instructions:"
t "  …patch artifact written";        [ -s "$ART/changes.patch" ] && ok || ko "no patch"
t "--keep-session drops --ephemeral"; run "$d" routine --effort low --keep-session <<<"$SPEC"; nomatch "$(cat "$FAKE_CODEX_ARGS")" "^--ephemeral$"
t "--network sets sandbox key";       run "$d" routine --effort low --network <<<"$SPEC"; match "$(cat "$FAKE_CODEX_ARGS")" "sandbox_workspace_write.network_access=true"

d="$(repo)"
t "verify fails → exit 1";            run "$d" routine --effort high <<<"$(printf '%s\n' "$SPEC" | sed 's/VERIFY: .*/VERIFY: test -f nope/')"; eq "$RC" 1
t "  …status verify-failed";          match "$OUT" "· verify-failed"
t "  …next says corrected spec";      match "$OUT" "corrected spec"

d="$(repo)"
t "empty diff → exit 2";              OUT="$(cd "$d" && FAKE_CODEX_MODE=noop lanes run routine --effort high <<<"$SPEC" 2>&1)"; eq "$?" 2
t "  …quotes codex's reason";         match "$OUT" "spec conflicts with a project rule"
t "  …no verify run";                 nomatch "$OUT" "verify: exit"

d="$(repo)"
t "timeout → exit 3";                 OUT="$(cd "$d" && FAKE_CODEX_MODE=slow FAKE_CODEX_SLEEP=4 lanes run routine --effort high --timeout 1 <<<"$SPEC" 2>&1)"; eq "$?" 3
t "  …status timeout";                match "$OUT" "· timeout"

d="$(repo)"
t "codex error → exit 6";             OUT="$(cd "$d" && FAKE_CODEX_MODE=fail lanes run routine --effort high <<<"$SPEC" 2>&1)"; eq "$?" 6
t "  …shows codex stderr";            match "$OUT" "fake codex: boom"

echo "== run: worktree"
d="$(repo)"
printf 'uncommitted\n' > "$d/pre.txt"
LS="$LANES_RUN_DIR/ls"
OUT="$(cd "$d" && FAKE_CODEX_LS="$LS" lanes run routine --effort high --worktree <<<"$SPEC" 2>&1)"; RC=$?
t "worktree run → exit 0";            eq "$RC" 0
t "  …lane saw uncommitted file";     match "$(cat "$LS")" "^pre.txt$"
t "  …main tree untouched";           [ ! -f "$d/lane-output.txt" ] && ok || ko "file leaked into main tree"
t "  …worktree removed";              eq "$(git -C "$d" worktree list | wc -l | tr -d ' ')" 1
PATCH="$(printf '%s' "$OUT" | sed -n 's/^patch: \([^ ]*\).*/\1/p')"
t "  …patch path in report";          [ -s "$PATCH" ] && ok || ko "no patch at '$PATCH'"
t "  …patch applies to main";         (cd "$d" && git apply --3way "$PATCH" 2>&1) && [ -f "$d/lane-output.txt" ] && ok || ko "apply failed"
t "  …pre-existing file kept";        [ -f "$d/pre.txt" ] && ok || ko "pre.txt lost"

echo "== mode / reviewed / status / tree-hash"
d="$(repo)"
t "mode default off";                 eq "$(cd "$d" && lanes mode status)" off
t "mode on";                          match "$(cd "$d" && lanes mode on)" "architect mode: on"
t "  …status on";                     eq "$(cd "$d" && lanes mode status)" on
t "  …state in .git/lanes";           [ -f "$d/.git/lanes/architect" ] && [ -s "$d/.git/lanes/reviewed" ] && ok || ko "state missing"
H1="$(cd "$d" && lanes tree-hash)"
printf 'x\n' > "$d/new.txt"
H2="$(cd "$d" && lanes tree-hash)"
t "tree-hash changes on untracked";   [ "$H1" != "$H2" ] && ok || ko "same hash"
printf 'new.txt\n' > "$d/.gitignore"; H3="$(cd "$d" && lanes tree-hash)"; rm "$d/.gitignore"
t "tree-hash respects .gitignore";    [ "$H3" != "$H2" ] && ok || ko "ignored file still hashed"
t "  …real index untouched";          eq "$(git -C "$d" diff --cached --name-only | wc -l | tr -d ' ')" 0
t "status: gate pending 1";           match "$(cd "$d" && lanes status)" "gate: pending — 1 file\(s\) changed"
t "reviewed fix keeps gate";          match "$(cd "$d" && lanes reviewed --verdict fix)" "gate stays armed"
t "  …status still pending";          match "$(cd "$d" && lanes status)" "gate: pending"
t "reviewed ship clears gate";        match "$(cd "$d" && lanes reviewed --verdict ship)" "gate clear"
t "  …status clear";                  match "$(cd "$d" && lanes status)" "gate: clear \(last verdict: .* ship\)"
t "  …log has both verdicts";         eq "$(cut -f3 "$d/.git/lanes/reviews.log" | tr '\n' ' ')" "fix ship "
t "reviewed bad verdict → exit 5";    (cd "$d" && lanes reviewed --verdict maybe >/dev/null 2>&1); eq "$?" 5
t "mode off";                         match "$(cd "$d" && lanes mode off)" "architect mode: off"
t "status outside git";               match "$(cd /tmp && lanes status)" "not a git repository"

echo "== hooks"
d="$(repo)"
hook() { printf '%s' "$2" | (cd "$d" && lanes hook "$1" 2>&1); }
J_EDIT="$(printf '{"cwd":"%s","tool_name":"Edit"}' "$d")"
J_MAIN_RM="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' "$d")"
J_REV_DIFF="$(printf '{"cwd":"%s","agent_type":"lanes:reviewer","tool_input":{"command":"git diff HEAD --stat"}}' "$d")"
J_REV_MARK="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"lanes reviewed --verdict ship"}}' "$d")"
J_REV_RM="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"rm -rf x"}}' "$d")"
J_REV_PIPE="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"git diff | tee out"}}' "$d")"
J_REV_PUSH="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"git push"}}' "$d")"
J_NAME_NPM="$(printf '{"cwd":"%s","agent_name":"reviewer","tool_input":{"command":"npm test"}}' "$d")"
J_STOP="$(printf '{"cwd":"%s","stop_hook_active":false}' "$d")"
J_STOP_ACTIVE="$(printf '{"cwd":"%s","stop_hook_active":true}' "$d")"
t "pre-edit: mode off → silent";      eq "$(hook pre-edit "$J_EDIT")" ""
(cd "$d" && lanes mode on >/dev/null)
t "pre-edit: mode on → deny";         match "$(hook pre-edit "$J_EDIT")" '"permissionDecision":"deny"'
t "  …valid JSON";                    hook pre-edit "$J_EDIT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok || ko "bad json"
t "pre-edit: CLAUDE_PROJECT_DIR wins"; OUT="$(printf '{"cwd":"/tmp"}' | (cd /tmp && CLAUDE_PROJECT_DIR="$d" lanes hook pre-edit))"; match "$OUT" deny
t "bash: main session → silent";      eq "$(hook bash "$J_MAIN_RM")" ""
t "bash: reviewer git diff → allow";  eq "$(hook bash "$J_REV_DIFF")" ""
t "bash: reviewer lanes reviewed → allow"; eq "$(hook bash "$J_REV_MARK")" ""
t "bash: reviewer rm → deny";         match "$(hook bash "$J_REV_RM")" '"permissionDecision":"deny"'
t "bash: reviewer pipe → deny";       match "$(hook bash "$J_REV_PIPE")" '"permissionDecision":"deny"'
t "bash: reviewer git push → deny";   match "$(hook bash "$J_REV_PUSH")" '"permissionDecision":"deny"'
t "bash: agent_name also matched";    match "$(hook bash "$J_NAME_NPM")" '"permissionDecision":"deny"'
t "stop: clean → silent";             eq "$(hook stop "$J_STOP")" ""
printf 'y\n' > "$d/changed.txt"
t "stop: changed → block";            match "$(hook stop "$J_STOP")" '"decision":"block"'
t "  …valid JSON with reason";        hook stop "$J_STOP" | jq -e '.decision == "block" and (.reason | test("1 file"))' >/dev/null && ok || ko "bad json"
t "stop: stop_hook_active → silent";  eq "$(hook stop "$J_STOP_ACTIVE")" ""
t "stop: after fix verdict → block";  (cd "$d" && lanes reviewed --verdict fix >/dev/null); match "$(hook stop "$J_STOP")" block
t "stop: after ship verdict → silent"; (cd "$d" && lanes reviewed --verdict ship >/dev/null); eq "$(hook stop "$J_STOP")" ""
printf 'z\n' >> "$d/changed.txt"
t "stop: changed again → block";      match "$(hook stop "$J_STOP")" block
git -C "$d" add -A && git -C "$d" commit -q -m wip
t "stop: commit alone doesn't clear"; match "$(hook stop "$J_STOP")" block
(cd "$d" && lanes reviewed --verdict ship >/dev/null)
git -C "$d" commit -q --allow-empty -m empty
t "stop: commit after ship stays clear"; eq "$(hook stop "$J_STOP")" ""
(cd "$d" && lanes mode off >/dev/null)
printf 'w\n' > "$d/changed.txt"
t "stop: mode off → silent";          eq "$(hook stop "$J_STOP")" ""
t "stop: outside git → silent";       eq "$(printf '{"cwd":"/tmp"}' | (cd /tmp && lanes hook stop))" ""
ENVF="$LANES_RUN_DIR/env"; : > "$ENVF"
OUT="$(printf '{"cwd":"%s"}' "$d" | (cd "$d" && CLAUDE_ENV_FILE="$ENVF" lanes hook session-start))"
t "session-start: context JSON";      printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | test("architect mode: off")' >/dev/null && ok || ko "bad json: $OUT"
t "  …exports LANES_BIN";             match "$(cat "$ENVF")" "^export LANES_BIN=.*bin/lanes"
t "  …prepends PATH";                 match "$(cat "$ENVF")" "^export PATH=.*/bin:"
t "hooks never exit non-zero";        (printf 'not json' | (cd "$d" && lanes hook stop >/dev/null 2>&1)); eq "$?" 0

echo "== doctor"
t "doctor runs with fake codex";      OUT="$(cd "$d" && CODEX_HOME=/nonexistent lanes doctor 2>&1)"; eq "$?" 0
t "  …reports lanes";                 match "$OUT" "routine lane: gpt-5.6-luna \[low medium high xhigh max\] 600s"
t "doctor: codex missing → exit 1";   OUT="$(cd "$d" && PATH=/usr/bin:/bin "$ROOT/bin/lanes" doctor 2>&1)"; eq "$?" 1
t "  …names the fix";                 match "$OUT" "npm i -g @openai/codex"

echo
echo "$pass passed, $fail failed"
rm -rf "$LANES_RUN_DIR"
[ "$fail" = 0 ]
