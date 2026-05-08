#!/usr/bin/env bash
# WorktreeCreate hook.
# Input JSON on stdin: {session_id, cwd, hook_event_name, name}
# Output: absolute worktree path on stdout (single line).
set -u

LOG=/tmp/wtcreate.log
exec 2>>"$LOG"
echo "=== $(date +%Y-%m-%dT%H:%M:%S%z) ===" >>"$LOG"

input=$(cat)
echo "input: $input" >>"$LOG"

main=$(printf '%s' "$input" | jq -r '.cwd // empty')
name=$(printf '%s' "$input" | jq -r '.name // empty')

if [[ -z "$main" || -z "$name" ]]; then
  echo "missing cwd or name" >>"$LOG"
  exit 1
fi

# Resolve main repo top-level (cwd may be a subdir).
top=$(git -C "$main" rev-parse --show-toplevel 2>>"$LOG") || { echo "not a git repo: $main" >>"$LOG"; exit 1; }
wt="$top/.claude/worktrees/$name"
echo "top=$top wt=$wt" >>"$LOG"

if [[ -e "$wt" ]]; then
  echo "worktree path already exists" >>"$LOG"
  exit 1
fi

# Prefer upstream/main (Materialize convention); fall back to origin/<default-branch>.
if git -C "$top" rev-parse --verify --quiet upstream/main >/dev/null; then
  base_ref="upstream/main"
else
  default_branch=$(git -C "$top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  default_branch=${default_branch:-main}
  base_ref="origin/$default_branch"
fi
echo "base_ref=$base_ref branch=$name" >>"$LOG"

git -C "$top" worktree add -b "$name" "$wt" "$base_ref" >>"$LOG" 2>&1 || {
  echo "git worktree add failed" >>"$LOG"
  exit 1
}

mkdir -p "$wt/.claude" >>"$LOG" 2>&1
jq -n --arg dir "$top" '{permissions:{additionalDirectories:[$dir]}}' \
  > "$wt/.claude/settings.local.json" || { echo "write settings failed" >>"$LOG"; exit 1; }

printf '%s\n' "$wt"
echo "ok" >>"$LOG"
