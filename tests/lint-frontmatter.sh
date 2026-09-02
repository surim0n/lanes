#!/usr/bin/env bash
# Every agent, command and skill file must open with YAML frontmatter carrying a description
# (and a name for agents and skills). Catches the class of README/prompt breakage a link check misses.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
rc=0
check() { # file needs-name
  local f="$1" need_name="$2" fm
  if [ "$(head -n 1 "$f")" != "---" ]; then echo "✗ $f: no frontmatter"; rc=1; return; fi
  fm="$(awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$f")"
  printf '%s\n' "$fm" | grep -qE '^description: .{10,}' || { echo "✗ $f: missing/short description"; rc=1; }
  if [ "$need_name" = 1 ]; then
    printf '%s\n' "$fm" | grep -qE '^name: [a-z0-9-]+$' || { echo "✗ $f: missing name"; rc=1; }
  fi
  # descriptions are loaded into every session's context; keep them short
  local words; words="$(printf '%s\n' "$fm" | sed -n 's/^description: //p' | wc -w | tr -d ' ')"
  [ "$words" -le 60 ] || { echo "✗ $f: description is $words words (max 60)"; rc=1; }
}
for f in agents/*.md skills/*/SKILL.md; do check "$f" 1; done
for f in commands/*.md; do check "$f" 0; done
[ "$rc" = 0 ] && echo "frontmatter ok"
exit "$rc"
