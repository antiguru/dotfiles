# Unified Claude projects store implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `~/.claude` (WORK) and `~/.claude-personal` (PERSONAL) profiles share one `projects/` store so memory learned in either is visible in the other for the same checkout.

**Architecture:** A neutral real store at `~/.local/share/claude/projects` holds the data; both profiles' `projects/` become symlinks to it. A `run_once_before` migration script merges existing data into the store, resolves the split-brain, and creates the symlinks itself before chezmoi applies the declared symlink files. The macOS jail gets one `allow` line; Linux needs none.

**Tech Stack:** chezmoi (Go templates, source-name conventions), bash, `claude-jail` (Linux bwrap / macOS SBPL). No unit-test framework exists in this repo; the migration script is verified with a bash harness against a sandboxed `$HOME`.

## Global constraints

* Design spec: `docs/superpowers/specs/2026-07-02-unify-claude-projects-store-design.md`. Every task implements part of it.
* Targets two OSes: `linux` and `darwin`. The jail edit is macOS-only; the migration guard has a Linux and a Darwin branch.
* Symlink target invariant: the string the migration script passes to `ln -s` MUST be byte-identical to the rendered content of `symlink_projects.tmpl`, both `$HOME/.local/share/claude/projects` absolute with no trailing newline. If they differ, chezmoi stops seeing the symlink files as a no-op and reports perpetual drift.
* Never delete original data: the migration renames `projects/` aside to `projects.pre-migration/`, it does not `rm` it.
* The migration runs only from a plain shell with ALL Claude Code sessions quit (including the session that wrote this plan). The guard aborts non-zero otherwise, which fails the whole `chezmoi apply` and leaves `projects/` untouched.
* chezmoi source-name conventions: `symlink_NAME` produces a symlink whose target is the file's rendered content; `.tmpl` renders as a Go template; `run_once_before_*` runs once per body-hash during `chezmoi apply`, before file application.
* Markdown in this repo: one sentence per line, `*` for list bullets.

## File structure

* `private_dot_local/bin/executable_claude-jail.tmpl` — modify: add one macOS `allow` line for the store. Responsibility unchanged (the OS sandbox), one new permitted subpath.
* `run_once_before_migrate-claude-projects.sh` — create at source root (maps to `$HOME`): the entire migration (guard, idempotency short-circuit, conflict-aware merge, cleanup, backup-then-replace, report). Plain `.sh` (not `.tmpl`) so it derives paths from `$HOME` at runtime, which keeps it testable under a sandboxed `$HOME` and keeps its `ln` target byte-identical to the rendered symlink files. This is the one deviation from the spec's `.tmpl` naming; the byte-identical invariant is preserved because `{{ .chezmoi.homeDir }}` equals `$HOME` at apply time.
* `dot_claude/symlink_projects.tmpl` — create: declares `~/.claude/projects` as a symlink to the store.
* `dot_claude-personal/symlink_projects.tmpl` — create: declares `~/.claude-personal/projects` as a symlink to the store.

Task order: jail edit first (independent, low risk), then the migration script (the correctness-critical core, developed test-first), then the two symlink files (they only make sense once the migration exists), then the operator-run apply.

---

### Task 1: macOS jail allow for the store

**Files:**
- Modify: `private_dot_local/bin/executable_claude-jail.tmpl` (macOS SBPL branch, after the `.claude.json` allow at lines 207-208)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing consumed by later tasks. Independent.

- [ ] **Step 1: Add the allow line**

In the macOS SBPL branch, insert after the `.claude.json` / `.claude.json.backup` allow block (currently lines 207-208), before the `.cargo` allow:

```
(allow file-read* file-write* (literal \"$HOME/.claude.json\")
                              (literal \"$HOME/.claude.json.backup\"))
;; projects/ in each config_dir is a symlink to this neutral store shared by
;; both profiles; the resolved target is outside config_dir, so allow it rw.
(allow file-read* file-write* (subpath \"$HOME/.local/share/claude\"))
(allow file-read* file-write* (subpath \"$HOME/.cargo\"))
```

- [ ] **Step 2: Verify it renders**

Run: `chezmoi execute-template < private_dot_local/bin/executable_claude-jail.tmpl | grep -n 'local/share/claude'`
Expected: a line showing `(allow file-read* file-write* (subpath "$HOME/.local/share/claude"))` (quotes unescaped in the rendered output).

- [ ] **Step 3: Commit**

```bash
git add private_dot_local/bin/executable_claude-jail.tmpl
git commit -m "claude-jail: allow the shared projects store on macOS"
```

---

### Task 2: Migration script

**Files:**
- Create: `run_once_before_migrate-claude-projects.sh` (source root)
- Test: `$SCRATCH/mig-test.sh` (a throwaway harness in the scratchpad, not committed)

**Interfaces:**
- Consumes: nothing.
- Produces: at runtime, both profiles' `projects` become symlinks to `$HOME/.local/share/claude/projects`; the `ln -s` target string is exactly `$HOME/.local/share/claude/projects`, which Task 3's symlink files must match.
- Test overrides the script honors: `MIGRATE_SKIP_GUARD=1` bypasses the guard (for sandbox runs), `MIGRATE_FORCE_GUARD_HIT=1` forces the guard to fire (to test the abort path).

- [ ] **Step 1: Write the failing test harness**

Create `$SCRATCH/mig-test.sh` (replace `$SCRATCH` with the real scratchpad path and `$SCRIPT` with the absolute path to `run_once_before_migrate-claude-projects.sh` in the worktree):

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$1"                      # path to run_once_before_migrate-claude-projects.sh
SB="$(mktemp -d)/home"           # sandbox HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [[ "$(cat "$1")" == "$2" ]] || fail "$1 != '$2' (got '$(cat "$1" 2>/dev/null)')"; }

# --- fixtures -------------------------------------------------------------
mkdir -p "$SB/.claude/projects" "$SB/.claude-personal/projects"
W="$SB/.claude/projects"; P="$SB/.claude-personal/projects"

# slugA: work-only
mkdir -p "$W/slugA/memory"; echo work-A >"$W/slugA/memory/MEMORY.md"
echo same >"$W/slugA/memory/fact.md"
# slugB: personal-only
mkdir -p "$P/slugB/memory"; echo personal-B >"$P/slugB/memory/MEMORY.md"
# slugShared: diverging MEMORY.md, identical todos/ subtree
mkdir -p "$W/slugShared/memory" "$W/slugShared/todos"
mkdir -p "$P/slugShared/memory" "$P/slugShared/todos"
echo workshared >"$W/slugShared/memory/MEMORY.md"
echo personalshared >"$P/slugShared/memory/MEMORY.md"
echo same-todo >"$W/slugShared/todos/t.md"
echo same-todo >"$P/slugShared/todos/t.md"
echo w-sess >"$W/slugShared/w.jsonl"
echo p-sess >"$P/slugShared/p.jsonl"
# slugM: materialize-like: personal memory is a symlink to work's, plus memory.bak
mkdir -p "$W/slugM/memory" "$P/slugM"; echo M >"$W/slugM/memory/MEMORY.md"
ln -s "$W/slugM/memory" "$P/slugM/memory"
mkdir -p "$P/slugM/memory.bak"; echo junk >"$P/slugM/memory.bak/old.md"

# --- run migration (guard bypassed) --------------------------------------
HOME="$SB" MIGRATE_SKIP_GUARD=1 bash "$SCRIPT"

S="$SB/.local/share/claude/projects"
# work-only and personal-only preserved
eq "$S/slugA/memory/MEMORY.md" work-A
eq "$S/slugB/memory/MEMORY.md" personal-B
# shared: work wins, personal kept aside, no data lost
eq "$S/slugShared/memory/MEMORY.md" workshared
eq "$S/slugShared/memory/MEMORY.md.conflict-personal" personalshared
# recursion: identical todo not false-flagged
[[ -f "$S/slugShared/todos/t.md" ]] || fail "todos/t.md missing"
[[ ! -e "$S/slugShared/todos/t.md.conflict-personal" ]] || fail "identical todo wrongly conflicted"
# session union
[[ -f "$S/slugShared/w.jsonl" && -f "$S/slugShared/p.jsonl" ]] || fail "session union incomplete"
# materialize-like: real content, no symlink, no memory.bak in store
eq "$S/slugM/memory/MEMORY.md" M
[[ ! -L "$S/slugM/memory" ]] || fail "store memory is a symlink"
[[ ! -e "$S/slugM/memory.bak" ]] || fail "memory.bak leaked into store"
# profiles are now symlinks to the store; originals backed up
[[ -L "$SB/.claude/projects" && "$(readlink "$SB/.claude/projects")" == "$SB/.local/share/claude/projects" ]] || fail "work projects not linked to store"
[[ -L "$SB/.claude-personal/projects" && "$(readlink "$SB/.claude-personal/projects")" == "$SB/.local/share/claude/projects" ]] || fail "personal projects not linked to store"
[[ -d "$SB/.claude/projects.pre-migration" && -d "$SB/.claude-personal/projects.pre-migration" ]] || fail "backups missing"
[[ -f "$S/migration-report.txt" ]] || fail "report missing"

# --- idempotency: second run is a no-op ----------------------------------
before=$(find "$S" -type f | sort | xargs cksum | cksum)
HOME="$SB" MIGRATE_SKIP_GUARD=1 bash "$SCRIPT"
after=$(find "$S" -type f | sort | xargs cksum | cksum)
[[ "$before" == "$after" ]] || fail "second run changed the store"

# --- guard: forced hit aborts non-zero, touches nothing ------------------
SB2="$(mktemp -d)/home"; mkdir -p "$SB2/.claude/projects/x"
if HOME="$SB2" MIGRATE_FORCE_GUARD_HIT=1 bash "$SCRIPT"; then fail "guard did not abort"; fi
[[ ! -e "$SB2/.local/share/claude/projects" ]] || fail "guard hit but store was created"
[[ -d "$SB2/.claude/projects" && ! -L "$SB2/.claude/projects" ]] || fail "guard hit but projects changed"

echo "ALL PASS"
```

- [ ] **Step 2: Run the harness to verify it fails**

Run: `bash "$SCRATCH/mig-test.sh" "$PWD/run_once_before_migrate-claude-projects.sh"`
Expected: FAIL — the script does not exist yet (`bash: .../run_once_before_migrate-claude-projects.sh: No such file or directory`).

- [ ] **Step 3: Write the migration script**

Create `run_once_before_migrate-claude-projects.sh` at the source root:

```bash
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
      ps -eo command 2>/dev/null | grep -Eq '(^|/)claude( |$)|\.local/share/claude/versions/' && return 0
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
declare -A pre
for src in "${profiles[@]}"; do
  [[ -e "$src" ]] && pre["$src"]=$(count_files "$src") || pre["$src"]=0
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
  for src in "${profiles[@]}"; do printf 'pre  %s: %s files\n' "$src" "${pre["$src"]:-0}"; done
  printf 'post store: %s files\n' "$post"
  if ((${#conflicts[@]})); then
    printf 'conflicts (%s):\n' "${#conflicts[@]}"; printf '  %s\n' "${conflicts[@]}"
  else
    printf 'conflicts: none\n'
  fi
} >"$report"
log "Migration complete. Report: $report"
```

- [ ] **Step 4: Run the harness to verify it passes**

Run: `bash "$SCRATCH/mig-test.sh" "$PWD/run_once_before_migrate-claude-projects.sh"`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add run_once_before_migrate-claude-projects.sh
git commit -m "claude: migrate both profiles' projects to a shared store"
```

---

### Task 3: Declared symlink files

**Files:**
- Create: `dot_claude/symlink_projects.tmpl`
- Create: `dot_claude-personal/symlink_projects.tmpl`

**Interfaces:**
- Consumes: the `ln -s` target from Task 2 (`$HOME/.local/share/claude/projects`); these files must render byte-identically to it.
- Produces: the declared end state chezmoi enforces on every apply.

- [ ] **Step 1: Create both symlink files**

Write each file with exactly this single line and no trailing newline:

```
{{ .chezmoi.homeDir }}/.local/share/claude/projects
```

`dot_claude/symlink_projects.tmpl` and `dot_claude-personal/symlink_projects.tmpl` have identical content.

- [ ] **Step 2: Verify render and byte-identical target**

Run:
```bash
chezmoi execute-template < dot_claude/symlink_projects.tmpl; echo
chezmoi execute-template < dot_claude-personal/symlink_projects.tmpl; echo
```
Expected: both print `/home/<you>/.local/share/claude/projects` (i.e. `$HOME/.local/share/claude/projects`), matching the `ln -s "$store"` target in Task 2's script exactly.

- [ ] **Step 3: Commit**

```bash
git add dot_claude/symlink_projects.tmpl dot_claude-personal/symlink_projects.tmpl
git commit -m "claude: declare both profiles' projects as symlinks to the store"
```

---

### Task 4: Operator-run migration and verification (surgical)

This task changes the live system. It is run by the operator, not an implementation subagent, and only when every Claude Code session is quit (including the one that produced this plan). Nothing here is committed; Tasks 1-3 already committed the source.

Surgical path (chosen): the migration script is run directly rather than through a full `chezmoi apply`, so the pre-existing, unrelated `settings.json` drift in both profiles is not touched. The script itself creates the store and the symlinks; a full apply is deliberately avoided until that drift is reconciled separately.

**Files:**
- No source changes. Acts on `~/.claude`, `~/.claude-personal`, `~/.local/share/claude/projects`.

**Interfaces:**
- Consumes: the three committed source files from Tasks 1-3.

- [ ] **Step 1: Merge the branch to the applied source**

The worktree branch must reach the source tree chezmoi reads (`~/.local/share/chezmoi`). Merge `unify-claude-projects` into `main` so the migration script lands at `~/.local/share/chezmoi/run_once_before_migrate-claude-projects.sh` and the two `symlink_projects.tmpl` files are present.

- [ ] **Step 2: Quit all sessions, then run the migration script directly**

Quit every Claude Code session in both profiles, including detached remote-control sessions (they survive closing a terminal). Then, from a plain shell:

Run: `bash ~/.local/share/chezmoi/run_once_before_migrate-claude-projects.sh`
Expected: prints `Migration complete. Report: ...`. If a session is still live, it aborts with the guard error and changes nothing; quit the straggler and retry. Running the script directly (not via chezmoi) means chezmoi never records it as run, which is harmless: the Step B short-circuit makes any later `chezmoi apply` re-run a clean no-op.

- [ ] **Step 3: Verify the result**

Run:
```bash
readlink ~/.claude/projects ~/.claude-personal/projects
cat ~/.local/share/claude/projects/migration-report.txt
```
Expected: both `readlink`s print `/home/<you>/.local/share/claude/projects`; the report shows `post store` file count at least the larger per-profile `pre` count and lists any conflicts.

- [ ] **Step 4: Confirm the scoped apply is now a no-op**

Run: `chezmoi diff ~/.claude/projects ~/.claude-personal/projects`
Expected: empty output. The script already created the exact symlinks chezmoi declares, so there is nothing left to apply for the projects targets, and `settings.json` was never in scope.

On macOS only, also apply the jail edit (it does not affect a running session, which must be restarted to pick it up):
Run: `chezmoi apply ~/.local/bin/claude-jail`

- [ ] **Step 5: Confirm cross-profile visibility**

Start a session in each profile on the same checkout and confirm a memory file written under one is visible under the other (both resolve to the same `<slug>/memory/`).

- [ ] **Step 6: Reconcile conflicts, then drop backups**

Review every `*.conflict-personal` (or `*.conflict-work`) file listed in the report, merge or accept each, and delete it. Only after verification passes, remove the backups:

```bash
rm -rf ~/.claude/projects.pre-migration ~/.claude-personal/projects.pre-migration
```

---

## Self-review

**Spec coverage:**
* Neutral store + both profiles symlinked → Tasks 2 (creates/links) and 3 (declares).
* Slug-keyed, whole-`projects/`, identical-paths-only sharing → inherent in symlinking `projects/`; no per-slug code (Task 2 merge is generic).
* Jail: Linux unchanged, macOS one allow line → Task 1.
* Migration steps A-F → Task 2 script, structured A/B/C.0/C+D/E/F matching the spec.
* Guard: bare-`claude` + versioned-binary detection, mandatory non-zero exit → Task 2 `claude_running` + abort.
* Idempotency on re-run → Task 2 Step B and the `-L` skip in `merge_profile`.
* Conflict-aware merge, directory recursion, dangling-link abort, `memory.bak` drop → Task 2 Step C.0, C+D.
* Backup-not-delete, byte-identical target → Task 2 Step E, Global constraints, Task 3 Step 2.
* Report + verification baseline → Task 2 Step F, Task 4 Step 4.
* Accepted tradeoffs (shared `/resume`, unmerged `.claude.json`, write races) → no code; documented in spec.

**Placeholder scan:** No TBD/TODO; every code step contains complete code; the test harness is fully specified.

**Type/name consistency:** `store`, `profiles`, `profile_tag`, `claude_running`, `already_linked`, `merge_profile`, `MIGRATE_SKIP_GUARD`, `MIGRATE_FORCE_GUARD_HIT`, and the `$HOME/.local/share/claude/projects` target string are used identically across the script, the harness, and Task 3.
