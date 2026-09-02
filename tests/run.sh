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
SPEC='TASK: write hello
FILES: lane-output.txt
CONTRACT: none
RULES: none
PROVE: echo PROVE-MARKER && test -f lane-output.txt'
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
t "spec missing PROVE → exit 5";      run "$d" routine --effort low <<<"$(printf 'TASK: x\nFILES: y')"; eq "$RC" 5
t "  …names the section";             match "$OUT" "missing required section\(s\): PROVE"
t "markdown headers accepted";        run "$d" routine --effort low --dry-run <<<"$(printf '## Task\nx\n## Files\ny\n## Prove\ntrue')"; eq "$RC" 0
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
t "done → exit 0";                    run "$d" routine --effort high <<<"$SPEC"; eq "$RC" 0
t "  …file landed in the tree";       [ -f "$d/lane-output.txt" ] && ok || ko "no file"
t "  …report says done";              match "$OUT" "LANE REPORT · routine · gpt-5.6-luna · effort high · [0-9]+m[0-9]+s · done"
t "  …lists the change";              match "$OUT" "A[[:space:]]+lane-output.txt"
t "  …PROVE re-run shown";            match "$OUT" "prove: exit 0 · echo PROVE-MARKER"
t "  …PROVE output shown";            match "$OUT" "^    PROVE-MARKER$"
t "  …codex final message shown";     match "$OUT" "^    Wrote lane-output.txt"
t "  …codex got --model";             match "$(cat "$FAKE_CODEX_ARGS")" "^gpt-5.6-luna$"
t "  …codex got quoted effort";       match "$(cat "$FAKE_CODEX_ARGS")" '^model_reasoning_effort="high"$'
t "  …sandbox workspace-write";       match "$(tr '\n' ' ' < "$FAKE_CODEX_ARGS")" "--sandbox workspace-write"
t "  …ephemeral by default";          match "$(cat "$FAKE_CODEX_ARGS")" "^--ephemeral$"
ART="$(printf '%s' "$OUT" | sed -n 's/^artifacts: //p')"
t "  …prompt carries the spec";       match "$(cat "$ART/prompt.md")" "^TASK: write hello"
t "  …prompt carries the trailer";    match "$(cat "$ART/prompt.md")" "^Lane instructions:"
t "  …patch artifact written";        [ -s "$ART/changes.patch" ] && ok || ko "no patch"
t "  …report appended for reviewer";  match "$(cd "$d" && lanes reports)" "^LANE REPORT · routine"
t "--keep-session drops --ephemeral"; run "$d" routine --effort low --keep-session <<<"$SPEC"; nomatch "$(cat "$FAKE_CODEX_ARGS")" "^--ephemeral$"
t "--network sets sandbox key";       run "$d" routine --effort low --network <<<"$SPEC"; match "$(cat "$FAKE_CODEX_ARGS")" "sandbox_workspace_write.network_access=true"
t "reports accumulate";               eq "$(cd "$d" && lanes reports | grep -c '^LANE REPORT')" 3

d="$(repo)"
t "PROVE fails → exit 1";             run "$d" routine --effort high <<<"$(printf '%s\n' "$SPEC" | sed 's/PROVE: .*/PROVE: test -f nope/')"; eq "$RC" 1
t "  …status prove-failed";           match "$OUT" "· prove-failed"
t "  …next says correct the spec";    match "$OUT" "correct the spec"

d="$(repo)"
t "no change → exit 2";               OUT="$(cd "$d" && FAKE_CODEX_MODE=noop lanes run routine --effort high <<<"$SPEC" 2>&1)"; eq "$?" 2
t "  …quotes codex's reason";         match "$OUT" "spec conflicts with a project rule"
t "  …no PROVE run";                  nomatch "$OUT" "prove: exit"

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

echo "== mode / approve / reports / status / tree-hash"
d="$(repo)"
t "mode default off";                 eq "$(cd "$d" && lanes mode status)" off
t "reports before any run";           match "$(cd "$d" && lanes reports)" "no lane reports since the last approval"
t "mode on";                          match "$(cd "$d" && lanes mode on)" "architect mode: on"
t "  …status on";                     eq "$(cd "$d" && lanes mode status)" on
t "  …state in .git/lanes";           [ -f "$d/.git/lanes/architect" ] && [ -s "$d/.git/lanes/approved" ] && ok || ko "state missing"
H1="$(cd "$d" && lanes tree-hash)"
printf 'x\n' > "$d/new.txt"
H2="$(cd "$d" && lanes tree-hash)"
t "tree-hash changes on untracked";   [ "$H1" != "$H2" ] && ok || ko "same hash"
printf 'new.txt\n' > "$d/.gitignore"; H3="$(cd "$d" && lanes tree-hash)"; rm "$d/.gitignore"
t "tree-hash respects .gitignore";    [ "$H3" != "$H2" ] && ok || ko "ignored file still hashed"
t "  …real index untouched";          eq "$(git -C "$d" diff --cached --name-only | wc -l | tr -d ' ')" 0
t "status: gate pending 1";           match "$(cd "$d" && lanes status)" "gate: pending — 1 file\(s\) changed since the last approval"
run "$d" routine --effort low <<<"$SPEC"
t "status: counts reports";           match "$(cd "$d" && lanes status)" "reports since approval: 1"
t "approve (human) clears gate";      match "$(cd "$d" && lanes approve)" "approved: tree .* \(gate clear\)"
t "  …status clear";                  match "$(cd "$d" && lanes status)" "gate: clear \(last verdict: .* approve human\)"
t "  …reports cleared";               match "$(cd "$d" && lanes reports)" "no lane reports since the last approval"
t "  …verdict logged with source";    eq "$(tail -n 1 "$d/.git/lanes/verdicts.log" | cut -f3,4 | tr '\t' ' ')" "approve human"
t "mode off";                         match "$(cd "$d" && lanes mode off)" "architect mode: off"
t "status outside git";               match "$(cd /tmp && lanes status)" "not a git repository"

echo "== hooks"
d="$(repo)"
hook() { printf '%s' "$2" | (cd "$d" && lanes hook "$1" 2>&1); }
J_EDIT="$(printf '{"cwd":"%s","tool_name":"Edit"}' "$d")"
J_MAIN_RM="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' "$d")"
J_MAIN_APPROVE="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"lanes approve"}}' "$d")"
J_MAIN_APPROVE_PATH="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"cd x && /opt/plugins/lanes/bin/lanes approve"}}' "$d")"
J_MAIN_STATUS="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"lanes status"}}' "$d")"
J_REV_DIFF="$(printf '{"cwd":"%s","agent_type":"lanes:reviewer","tool_input":{"command":"git diff HEAD --stat"}}' "$d")"
J_REV_REPORTS="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"lanes reports"}}' "$d")"
J_REV_APPROVE="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"lanes approve"}}' "$d")"
J_REV_RM="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"rm -rf x"}}' "$d")"
J_REV_PIPE="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"git diff | tee out"}}' "$d")"
J_REV_PUSH="$(printf '{"cwd":"%s","agent_type":"reviewer","tool_input":{"command":"git push"}}' "$d")"
J_NAME_NPM="$(printf '{"cwd":"%s","agent_name":"reviewer","tool_input":{"command":"npm test"}}' "$d")"
J_STOP="$(printf '{"cwd":"%s","stop_hook_active":false}' "$d")"
J_STOP_ACTIVE="$(printf '{"cwd":"%s","stop_hook_active":true}' "$d")"
TR="$LANES_RUN_DIR/transcript.jsonl"
J_SUB_REV="$(printf '{"cwd":"%s","agent_name":"reviewer","agent_type":"lanes:reviewer","transcript_path":"%s"}' "$d" "$TR")"
J_SUB_OTHER="$(printf '{"cwd":"%s","agent_name":"Explore","transcript_path":"%s"}' "$d" "$TR")"
J_SUB_MISSING="$(printf '{"cwd":"%s","agent_name":"reviewer","transcript_path":"/nonexistent/t.jsonl"}' "$d")"
transcript() { # verdict-in-assistant
  printf '{"type":"user","message":{"role":"user","content":"Answer with VERDICT: approve | revise | reject"}}\n' > "$TR"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking at the diff.\\nVERDICT: %s\\nWHY: because."}]}}\n' "$1" >> "$TR"
}
t "pre-edit: mode off → silent";      eq "$(hook pre-edit "$J_EDIT")" ""
t "bash: approve allowed when mode off"; eq "$(hook bash "$J_MAIN_APPROVE")" ""
(cd "$d" && lanes mode on >/dev/null)
t "pre-edit: mode on → deny";         match "$(hook pre-edit "$J_EDIT")" '"permissionDecision":"deny"'
t "  …valid JSON";                    hook pre-edit "$J_EDIT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null && ok || ko "bad json"
t "pre-edit: CLAUDE_PROJECT_DIR wins"; OUT="$(printf '{"cwd":"/tmp"}' | (cd /tmp && CLAUDE_PROJECT_DIR="$d" lanes hook pre-edit))"; match "$OUT" deny
t "bash: main rm → silent";           eq "$(hook bash "$J_MAIN_RM")" ""
t "bash: main lanes status → silent"; eq "$(hook bash "$J_MAIN_STATUS")" ""
t "bash: main lanes approve → deny";  match "$(hook bash "$J_MAIN_APPROVE")" '"permissionDecision":"deny"'
t "bash: main …/bin/lanes approve → deny"; match "$(hook bash "$J_MAIN_APPROVE_PATH")" '"permissionDecision":"deny"'
t "bash: reviewer git diff → allow";  eq "$(hook bash "$J_REV_DIFF")" ""
t "bash: reviewer lanes reports → allow"; eq "$(hook bash "$J_REV_REPORTS")" ""
t "bash: reviewer lanes approve → deny"; match "$(hook bash "$J_REV_APPROVE")" '"permissionDecision":"deny"'
t "bash: reviewer rm → deny";         match "$(hook bash "$J_REV_RM")" '"permissionDecision":"deny"'
t "bash: reviewer pipe → deny";       match "$(hook bash "$J_REV_PIPE")" '"permissionDecision":"deny"'
t "bash: reviewer git push → deny";   match "$(hook bash "$J_REV_PUSH")" '"permissionDecision":"deny"'
t "bash: agent_name also matched";    match "$(hook bash "$J_NAME_NPM")" '"permissionDecision":"deny"'
t "stop: clean → silent";             eq "$(hook stop "$J_STOP")" ""
printf 'y\n' > "$d/changed.txt"
t "stop: changed → block";            match "$(hook stop "$J_STOP")" '"decision":"block"'
t "  …valid JSON with reason";        hook stop "$J_STOP" | jq -e '.decision == "block" and (.reason | test("1 file"))' >/dev/null && ok || ko "bad json"
t "  …reason names the reviewer";     match "$(hook stop "$J_STOP")" "lanes:reviewer"
t "stop: stop_hook_active → silent";  eq "$(hook stop "$J_STOP_ACTIVE")" ""
transcript revise
t "subagent-stop: revise → recorded"; hook subagent-stop "$J_SUB_REV" >/dev/null; eq "$(tail -n 1 "$d/.git/lanes/verdicts.log" | cut -f3,4 | tr '\t' ' ')" "revise reviewer"
t "  …gate still blocks";             match "$(hook stop "$J_STOP")" block
transcript approve
t "subagent-stop: other agent → ignored"; hook subagent-stop "$J_SUB_OTHER" >/dev/null; eq "$(tail -n 1 "$d/.git/lanes/verdicts.log" | cut -f3)" "revise"
t "subagent-stop: missing transcript → ignored"; hook subagent-stop "$J_SUB_MISSING" >/dev/null; eq "$(tail -n 1 "$d/.git/lanes/verdicts.log" | cut -f3)" "revise"
t "subagent-stop: approve → gate clear"; hook subagent-stop "$J_SUB_REV" >/dev/null; eq "$(hook stop "$J_STOP")" ""
t "  …verdict logged as reviewer";    eq "$(tail -n 1 "$d/.git/lanes/verdicts.log" | cut -f3,4 | tr '\t' ' ')" "approve reviewer"
t "  …template text in user turn ignored"; printf '{"type":"user","message":{"role":"user","content":"VERDICT: approve"}}\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"VERDICT: reject"}]}}\n' > "$TR"; hook subagent-stop "$J_SUB_REV" >/dev/null; eq "$(tail -n 1 "$d/.git/lanes/verdicts.log" | cut -f3)" "reject"
printf 'z\n' >> "$d/changed.txt"
t "stop: changed again → block";      match "$(hook stop "$J_STOP")" block
git -C "$d" add -A && git -C "$d" commit -q -m wip
t "stop: commit alone doesn't clear"; match "$(hook stop "$J_STOP")" block
(cd "$d" && lanes approve >/dev/null)
git -C "$d" commit -q --allow-empty -m empty
t "stop: commit after approval stays clear"; eq "$(hook stop "$J_STOP")" ""
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
