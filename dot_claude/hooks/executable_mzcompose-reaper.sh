#!/usr/bin/env bash
# Tears down mzcompose compositions that Claude Code sessions leave running.
#
# Usage: mzcompose-reaper.sh pre|post|end|start, hook input JSON on stdin.
#   pre    PreToolUse(Bash): snapshot running compose projects.
#   post   PostToolUse(Bash): record projects this session started.
#   end    SessionEnd: tear down projects this session started.
#   start  SessionStart: tear down orphans, whose working directory is gone.
#
# Ownership is recorded two ways, because neither covers every run.
# The pre/post diff of running projects catches foreground runs with any
# project name. A background run returns before its containers exist, so
# post also parses the project name from the command (--project-name, else
# the composition name, which is mzcompose's default project name).
#
# NOTE: two sessions using the same project name share one compose project.
# `end` skips a project that another session claimed within LIVE_MINUTES.
set -u

STATE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-mzcompose"
LOG="$STATE/reaper.log"
LIVE_MINUTES=720
mkdir -p "$STATE"
exec 2>>"$LOG"

mode="${1:-}"
input=$(cat)
field() { printf '%s' "$input" | jq -r "$1 // empty"; }
log() { echo "$(date +%Y-%m-%dT%H:%M:%S%z) $mode ${session:-?}: $*" >>"$LOG"; }

session=$(field .session_id)
[[ -n "$session" ]] || exit 0
owned="$STATE/$session.owned"

running_projects() {
  docker ps --filter label=com.docker.compose.project \
    --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | sort -u
}

# Detached so the teardown survives Claude Code exiting before it finishes.
# Flags match `bin/mzcompose down`, which always removes volumes.
down() {
  log "down $1"
  (cd / && setsid nohup docker compose -p "$1" down \
    --timeout 0 --volumes --remove-orphans >>"$LOG" 2>&1 &)
}

# Prints the project names a command line's mzcompose invocations use.
parse_projects() {
  local cmd=$1 cwd=$2 seg dir name
  # Split on shell separators. Quoting is not handled, which is fine for the
  # plain `bin/mzcompose --find NAME run ...` shapes sessions use.
  while IFS= read -r seg; do
    if [[ $seg =~ (^|[[:space:]])cd[[:space:]]+([^[:space:]]+) ]]; then
      dir=${BASH_REMATCH[2]}
      [[ $dir == /* ]] || dir="$cwd/$dir"
      cwd=$dir
    fi
    [[ $seg == *mzcompose* ]] || continue
    name=
    if [[ $seg =~ --project-name[=[:space:]]+([^[:space:]]+) ]]; then
      name=${BASH_REMATCH[1]}
    elif [[ $seg =~ --find[=[:space:]]+([^[:space:]]+) ]]; then
      name=${BASH_REMATCH[1]}
    elif [[ $seg =~ mzcompose[[:space:]] ]]; then
      name=$(basename "$cwd")
    fi
    [[ -n $name ]] && printf '%s\n' "$name"
  done < <(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
}

case "$mode" in
pre)
  [[ $(field .tool_input.command) == *mzcompose* ]] || exit 0
  running_projects >"$STATE/$session.$(field .tool_use_id).pre"
  ;;
post)
  cmd=$(field .tool_input.command)
  [[ $cmd == *mzcompose* ]] || exit 0
  pre="$STATE/$session.$(field .tool_use_id).pre"
  {
    [[ -f $pre ]] && comm -13 "$pre" <(running_projects)
    parse_projects "$cmd" "$(field .cwd)"
  } | sort -u | while IFS= read -r p; do
    grep -qxF "$p" "$owned" 2>/dev/null || { echo "$p" >>"$owned"; log "own $p"; }
  done
  rm -f "$pre"
  # Refresh the claim even when nothing new was recorded.
  [[ -f $owned ]] && touch "$owned"
  ;;
end)
  rm -f "$STATE/$session".*.pre
  [[ -f $owned ]] || exit 0
  running=$(running_projects)
  while IFS= read -r p; do
    grep -qxF "$p" <<<"$running" || continue
    other=$(find "$STATE" -name '*.owned' ! -name "$session.owned" \
      -mmin -"$LIVE_MINUTES" -exec grep -lxF "$p" {} + 2>/dev/null | head -1)
    if [[ -n $other ]]; then
      log "skip $p, also claimed by $(basename "$other" .owned)"
      continue
    fi
    down "$p"
  done <"$owned"
  rm -f "$owned"
  ;;
start)
  # A missing working directory means the worktree was removed, so no
  # session can still use the composition.
  docker ps --filter label=com.docker.compose.project --format \
    '{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.project.working_dir"}}' \
    2>/dev/null | sort -u | while IFS=$'\t' read -r p wd; do
    [[ -n $wd && ! -d $wd ]] && down "$p"
  done
  find "$STATE" \( -name '*.owned' -o -name '*.pre' \) -mtime +7 -delete
  ;;
*)
  echo "usage: $0 pre|post|end|start" >&2
  exit 2
  ;;
esac
exit 0
