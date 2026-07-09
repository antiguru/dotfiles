#!/usr/bin/env bash
#
# Unify the two Claude Code profiles' projects/ trees into one neutral store so
# memory learned in either profile is visible in the other for the same checkout.
# Design: docs/superpowers/specs/2026-07-02-unify-claude-projects-store-design.md
#
# Run from a plain shell with ALL Claude Code sessions quit. chezmoi runs this
# (run_once_before_) ahead of applying the projects symlinks. The guard aborts
# non-zero if a session is live, which fails the whole apply and leaves the
# projects/ dirs untouched. Re-runs on body-hash change; Step B makes a re-run
# on an already-migrated system a no-op.

set -euo pipefail

store="$HOME/.local/share/claude/projects"
profiles=("$HOME/.claude/projects" "$HOME/.claude-personal/projects")
report="$store/migration-report.txt"
log() { printf '%s\n' "$*" >&2; }

profile_tag() {
  case "$1" in
    "$HOME/.claude/projects") echo work ;;
    "$HOME/.claude-personal/projects") echo personal ;;
    *) basename "$(dirname "$1")" ;;
  esac
}

# --- Step A: guard -----------------------------------------------------------
# A live session is either a bare `claude` (arg0) or the versioned binary path.
# Neither matches this script (arg0 `bash`, path lacks /versions/) or chezmoi.
claude_running() {
  [[ "${MIGRATE_FORCE_GUARD_HIT:-0}" == 1 ]] && return 0
  [[ "${MIGRATE_SKIP_GUARD:-0}" == 1 ]] && return 1
  local pidfile cmdline arg0 base
  case "$(uname -s)" in
    Linux)
      for pidfile in /proc/[0-9]*/cmdline; do
        cmdline=$(tr '\0' '\n' <"$pidfile" 2>/dev/null) || continue
        arg0=${cmdline%%$'\n'*}
        base=${arg0##*/}
        if [[ "$base" == claude ]] || printf '%s' "$cmdline" | grep -qF '.local/share/claude/versions/'; then
          return 0
        fi
      done
      return 1
      ;;
    Darwin)
      # [c]laude keeps the pattern's own text from containing the literal
      # substring, so this grep never matches its own argv in `ps` output.
      ps -eo command 2>/dev/null | grep -Eq '(^|/)[c]laude( |$)|\.local/share/[c]laude/versions/' && return 0
      return 1
      ;;
    *) return 1 ;;
  esac
}

if claude_running; then
  log "ERROR: a Claude Code process is still running."
  log "Quit ALL sessions in BOTH profiles first, including detached remote-control"
  log "sessions (they survive closing a terminal), then re-run 'chezmoi apply'."
  exit 1
fi

# --- Step B: idempotency short-circuit --------------------------------------
already_linked() {
  local p
  for p in "${profiles[@]}"; do
    [[ -L "$p" && "$(readlink -f "$p")" == "$(readlink -f "$store")" ]] || return 1
  done
  return 0
}
if already_linked; then
  log "Already migrated: both profiles resolve to the store. Nothing to do."
  exit 0
fi

mkdir -p "$store"

# --- Step C.0: dangling-link pre-check (abort before any change) -------------
for src in "${profiles[@]}"; do
  [[ -d "$src" && ! -L "$src" ]] || continue
  d=$(find -L "$src" -mindepth 1 -type l -print -quit 2>/dev/null || true)
  if [[ -n "$d" ]]; then
    log "ERROR: dangling symlink under $src ($d); aborting before any destructive step."
    exit 1
  fi
done

# --- Step F prep: pre-migration counts --------------------------------------
count_files() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }
# Parallel to profiles by index; associative arrays need bash 4, macOS ships 3.2.
pre=()
for i in "${!profiles[@]}"; do
  [[ -e "${profiles[$i]}" ]] && pre[$i]=$(count_files "${profiles[$i]}") || pre[$i]=0
done

# --- Step C + D: conflict-aware, symlink-resolving merge --------------------
# find -L follows symlinks, so a `memory -> realdir` yields real files at the
# logical path. Regular files: absent -> copy; identical -> skip; diverging ->
# copy aside as <name>.conflict-<tag>. Directories are recursed structurally.
# memory.bak is dropped (Step D).
declare -a conflicts=()
merge_profile() {
  local src="$1" tag f rel dst
  tag=$(profile_tag "$1")
  [[ -e "$src" ]] || { log "skip: $src absent"; return 0; }
  [[ -L "$src" ]] && { log "skip: $src already a symlink"; return 0; }
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}
    case "$rel" in memory.bak|*/memory.bak|memory.bak/*|*/memory.bak/*) continue ;; esac
    dst="$store/$rel"
    if [[ -d "$f" ]]; then
      mkdir -p "$dst"
    elif [[ ! -e "$dst" ]]; then
      mkdir -p "$(dirname "$dst")"; cp -p "$f" "$dst"
    elif cmp -s "$f" "$dst"; then
      :
    else
      cp -p "$f" "$dst.conflict-$tag"; conflicts+=("$rel (from $tag)")
    fi
  done < <(find -L "$src" -mindepth 1 \( -type d -o -type f \) -print0)
}
# WORK first so its content is canonical on divergence; PERSONAL kept aside.
merge_profile "${profiles[0]}"
merge_profile "${profiles[1]}"

# --- Step E: backup originals, then create symlinks -------------------------
for src in "${profiles[@]}"; do
  [[ -L "$src" ]] && continue
  [[ -e "$src" ]] && mv "$src" "$src.pre-migration"
  ln -s "$store" "$src"
done

# --- Step F: report ---------------------------------------------------------
post=$(count_files "$store")
{
  printf 'migration-report %s\n' "$(date -u +%FT%TZ)"
  for i in "${!profiles[@]}"; do printf 'pre  %s: %s files\n' "${profiles[$i]}" "${pre[$i]:-0}"; done
  printf 'post store: %s files\n' "$post"
  if ((${#conflicts[@]})); then
    printf 'conflicts (%s):\n' "${#conflicts[@]}"; printf '  %s\n' "${conflicts[@]}"
  else
    printf 'conflicts: none\n'
  fi
} >"$report"
log "Migration complete. Report: $report"
