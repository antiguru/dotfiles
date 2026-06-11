# claude-jail macOS port — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a macOS (`sandbox-exec`/Seatbelt) variant of `claude-jail` so Claude Code runs with `--dangerously-skip-permissions` inside a filesystem-confined sandbox.

**Architecture:** Convert the single Linux bwrap script into one chezmoi-templated source file that branches on `.chezmoi.os`. The Linux branch keeps the existing bwrap script verbatim; the new Darwin branch builds a deny-default SBPL profile and execs `sandbox-exec`. Docker is opt-in, ssh is agent-only, Rust builds are allowed.

**Tech Stack:** bash, chezmoi templates (Go text/template), macOS `sandbox-exec` + SBPL.

**Spec:** `docs/superpowers/specs/2026-06-04-claude-jail-macos-design.md`

---

## Environment note (read first)

* This is the chezmoi source repo at `~/.local/share/chezmoi`. Testing requires applying to the live home dir.
* If working in a git worktree, run chezmoi against it with `--source "$PWD"` (e.g. `chezmoi --source "$PWD" cat ~/.local/bin/claude-jail`). All chezmoi commands below assume the active source is the checkout you are editing.
* Host for verification: macOS 26.5.1, arm64. The Linux branch cannot be runtime-tested here; verify it by template rendering and inspection only.
* There is no unit-test framework. "Tests" are template-render checks and behavioral checks run inside the jail. Each task pairs a change with a concrete verification command and expected output.

## File structure

* Modify (rename + rewrite): `private_dot_local/bin/executable_claude-jail` → `private_dot_local/bin/executable_claude-jail.tmpl`
  Single responsibility: emit the correct `claude-jail` script per OS.
* Modify: `.chezmoiignore` — remove the `.local/bin/claude-jail` Linux-gate block; keep the karabiner block.

---

## Task 1: Rename the script to a template and add the OS skeleton

**Files:**
- Rename: `private_dot_local/bin/executable_claude-jail` → `private_dot_local/bin/executable_claude-jail.tmpl`

- [ ] **Step 1: Rename via git so history follows**

Run:
```bash
git mv private_dot_local/bin/executable_claude-jail private_dot_local/bin/executable_claude-jail.tmpl
```

- [ ] **Step 2: Wrap existing content in the linux branch and add else stub**

Edit `private_dot_local/bin/executable_claude-jail.tmpl`.
Prepend this line as the new line 1 (before the existing `#!/usr/bin/env bash`):
```
{{- if eq .chezmoi.os "linux" -}}
```
Append at the very end of the file (after the existing final `exec bwrap ...` line):
```
{{- else if eq .chezmoi.os "darwin" -}}
#!/usr/bin/env bash
echo "claude-jail: darwin branch not implemented yet" >&2
exit 1
{{- else -}}
#!/usr/bin/env bash
echo "claude-jail: unsupported OS" >&2
exit 1
{{- end -}}
```

The existing Linux script body stays byte-for-byte unchanged between the `if` and `else if` directives. Do not edit its comments or logic.

- [ ] **Step 3: Verify the template renders on this (darwin) host**

Run:
```bash
chezmoi --source "$PWD" execute-template < private_dot_local/bin/executable_claude-jail.tmpl
```
Expected output (exactly three lines):
```
#!/usr/bin/env bash
echo "claude-jail: darwin branch not implemented yet" >&2
exit 1
```
This confirms: template parses, darwin branch is selected, shebang is line 1 (trim markers correct).

- [ ] **Step 4: Verify the linux branch still contains the bwrap script**

Run:
```bash
grep -c "exec bwrap" private_dot_local/bin/executable_claude-jail.tmpl
```
Expected: `1`

- [ ] **Step 5: Commit**

```bash
git add private_dot_local/bin/executable_claude-jail.tmpl
git commit -m "claude-jail: template by OS, stub darwin branch"
```

---

## Task 2: Implement the Darwin sandbox-exec branch

**Files:**
- Modify: `private_dot_local/bin/executable_claude-jail.tmpl` (replace the darwin stub from Task 1)

- [ ] **Step 1: Replace the darwin stub with the real script**

In `private_dot_local/bin/executable_claude-jail.tmpl`, replace these three stub lines inside the darwin branch:
```
#!/usr/bin/env bash
echo "claude-jail: darwin branch not implemented yet" >&2
exit 1
```
with the full Darwin script below (verbatim). Leave the `{{- else if eq .chezmoi.os "darwin" -}}` line above it and the `{{- else -}}` line below it untouched.

```bash
#!/usr/bin/env bash
# claude-jail (macOS): run Claude Code inside a sandbox-exec (Seatbelt) jail.
#
# Read+write: cwd, ~/dev/repos, Claude config dir, ~/.cargo, temp.
# Read-only:  system dirs, ~/.rustup, shell init, git/gh config,
#             ~/.ssh/known_hosts + ~/.ssh/config.
# Denied:     everything else in $HOME (~/.ssh keys, ~/Documents, ~/Library, ...).
# Network:    unrestricted outbound. Docker: opt-in via leading --docker.
#
# Honors CLAUDE_CONFIG_DIR (e.g. claude-personal alias).
# Design: docs/superpowers/specs/2026-06-04-claude-jail-macos-design.md
#
# Accepted holes: world-readable system files stay readable (not a syscall jail);
# no egress filtering; --docker = full host compromise (orbstack root + -v /:/host).
set -euo pipefail

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cwd="$(pwd)"

# Opt-in docker: must be the first argument.
docker=0
if [[ "${1:-}" == "--docker" ]]; then
  docker=1
  shift
fi

# A double-quote in cwd would break the SBPL string literal below.
case "$cwd" in
  *'"'*) echo "claude-jail: refusing cwd containing a double-quote: $cwd" >&2; exit 1 ;;
esac

# OrbStack docker socket, real path (Seatbelt resolves symlinks).
docker_sock="$HOME/.orbstack/run/docker.sock"

# Docker socket connect denied unless opted in.
docker_rule=""
if [[ "$docker" -eq 0 ]]; then
  docker_rule="(deny network-outbound (literal \"$docker_sock\"))"
fi

profile="(version 1)
(deny default)

;; syscalls/services needed to run node + tools (not the security boundary)
(allow process-fork process-exec*)
(allow signal (target self))
(allow sysctl-read)
(allow mach-lookup)
(allow file-read-metadata)
(allow network*)

;; system reads: needed to load binaries and frameworks
(allow file-read* (subpath \"/usr\") (subpath \"/System\") (subpath \"/Library\")
                  (subpath \"/bin\") (subpath \"/sbin\") (subpath \"/opt/homebrew\")
                  (subpath \"/private/etc\") (subpath \"/private/var/db\"))
(allow file-read* file-write* (subpath \"/dev\"))
(allow file-read* file-write* (subpath \"/private/tmp\")
                              (subpath \"/private/var/folders\"))

;; workspace + state (rw)
(allow file-read* file-write* (subpath \"$cwd\"))
(allow file-read* file-write* (subpath \"$HOME/dev/repos\"))
(allow file-read* file-write* (subpath \"$config_dir\"))
(allow file-read* file-write* (literal \"$HOME/.claude.json\")
                              (literal \"$HOME/.claude.json.backup\"))
(allow file-read* file-write* (subpath \"$HOME/.cargo\"))

;; read-only: toolchain, shell init, git/gh config
(allow file-read* (subpath \"$HOME/.rustup\")
                  (literal \"$HOME/.zshrc\") (literal \"$HOME/.zshenv\")
                  (subpath \"$HOME/.oh-my-zsh\")
                  (literal \"$HOME/.gitconfig\") (subpath \"$HOME/.config/git\")
                  (subpath \"$HOME/.config/gh\"))

;; ssh: agent only; known_hosts + config ro; private keys not allowed
(allow file-read* (literal \"$HOME/.ssh/known_hosts\") (literal \"$HOME/.ssh/config\"))

;; docker: orbstack socket connect denied unless --docker
$docker_rule
"

exec sandbox-exec -p "$profile" claude --dangerously-skip-permissions "$@"
```

> **Escaping note:** The code block above is the exact file content. Bash variables stay plain (`$cwd`, `$HOME`, `$profile`, `$@`). The SBPL double-quotes stay backslash-escaped (`\"`) because they sit inside the bash double-quoted `profile="..."` string. chezmoi's Go template engine treats `$` as literal text outside `{{ }}` actions, so no chezmoi-level escaping is needed. Step 2's `bash -n` check confirms the result parses.

- [ ] **Step 2: Verify the rendered darwin script is valid bash**

Run:
```bash
chezmoi --source "$PWD" execute-template < private_dot_local/bin/executable_claude-jail.tmpl | bash -n -
```
Expected: no output, exit 0 (bash syntax check passes).

- [ ] **Step 3: Verify rendered content has the key markers**

Run:
```bash
chezmoi --source "$PWD" execute-template < private_dot_local/bin/executable_claude-jail.tmpl \
  | grep -E "sandbox-exec -p|deny default|orbstack/run/docker.sock"
```
Expected: three matching lines present (the `sandbox-exec` exec line, the `(deny default)` line, and the docker socket path).

- [ ] **Step 4: Commit**

```bash
git add private_dot_local/bin/executable_claude-jail.tmpl
git commit -m "claude-jail: implement macOS sandbox-exec branch"
```

---

## Task 3: Drop the Linux-only ignore gate

**Files:**
- Modify: `.chezmoiignore`

- [ ] **Step 1: Remove the claude-jail block**

Edit `.chezmoiignore`. Delete these lines:
```
{{- if ne .chezmoi.os "linux" }}
{{/* bwrap-based, Linux-only; macOS variant would be a separate script */}}
.local/bin/claude-jail
{{- end }}
```
Keep the karabiner block intact.

- [ ] **Step 2: Verify claude-jail is no longer ignored on darwin**

Run:
```bash
chezmoi --source "$PWD" ignored | grep claude-jail || echo "not ignored"
```
Expected: `not ignored`

- [ ] **Step 3: Verify chezmoi resolves the target to the template**

Run:
```bash
chezmoi --source "$PWD" source-path ~/.local/bin/claude-jail
```
Expected: path ending in `private_dot_local/bin/executable_claude-jail.tmpl`

- [ ] **Step 4: Commit**

```bash
git add .chezmoiignore
git commit -m "claude-jail: drop linux-only ignore, template handles both OSes"
```

---

## Task 4: Apply and resolve sandbox denials (iteration pass)

**Files:** none (runtime tuning; any fixes go back into the darwin branch of `executable_claude-jail.tmpl`)

- [ ] **Step 1: Apply to home**

Run:
```bash
chezmoi --source "$PWD" apply ~/.local/bin/claude-jail
ls -l ~/.local/bin/claude-jail
```
Expected: file exists, executable bit set.

- [ ] **Step 2: Start a sandbox denial log stream in a second terminal**

In a separate terminal, run:
```bash
log stream --style compact --predicate 'sender == "Sandbox"'
```
Leave it running during Step 3. Denied operations print here as `deny(1) <operation> <path>`.

- [ ] **Step 3: Launch the jail in a throwaway dir and confirm Claude starts**

Run:
```bash
cd "$(mktemp -d)" && claude-jail --version
```
Expected: Claude prints its version and exits 0.
If it hangs, crashes, or the log stream shows `deny(1) file-read*`/`file-read-data`/`mach-lookup`/`sysctl-read` for a clearly-needed system path (under `/usr`, `/System`, `/Library`, `/opt/homebrew`, `/private/var/folders`, `/dev`), note the operation + path.

- [ ] **Step 4: Add minimal allows for any legitimate denials**

For each system denial observed in Step 3, add the narrowest allow to the SBPL profile in the darwin branch. Examples of likely additions and where they go:
* A denied `file-read*` on a system subpath → add it to the existing `;; system reads` allow list.
* A denied `mach-lookup` (already broadly allowed) — should not occur; if a more specific operation like `iokit-open` or `ipc-posix-shm` is denied and Claude fails, add `(allow iokit-open)` or `(allow ipc-posix-shm)` on its own line under the syscalls section.
Do NOT widen `file-write*` or add `$HOME` reads beyond the spec's allowlist — those are the security boundary.
After editing, re-render and re-apply:
```bash
chezmoi --source "$PWD" execute-template < private_dot_local/bin/executable_claude-jail.tmpl | bash -n -
chezmoi --source "$PWD" apply ~/.local/bin/claude-jail
```
Repeat Step 3 until `claude-jail --version` succeeds with no needed-system-path denials.

- [ ] **Step 5: Commit any profile fixes**

```bash
git add private_dot_local/bin/executable_claude-jail.tmpl
git commit -m "claude-jail: allow system paths node needs at startup"
```
If no fixes were needed, skip this commit.

---

## Task 5: Verify confinement (the security checks)

**Files:** none (behavioral verification)

These run probe commands under the exact same SBPL profile, by turning the rendered script into a generic "run any program in the jail" runner. The runner replaces the final `exec ... claude ...` line so it execs `"$@"` instead — then it accepts an arbitrary command. The profile is byte-identical to production.

- [ ] **Step 1: Build a reusable jail runner from the rendered template**

Run:
```bash
src="$HOME/.local/share/chezmoi"
chezmoi --source "$src" execute-template < "$src/private_dot_local/bin/executable_claude-jail.tmpl" \
  | sed 's@exec sandbox-exec -p "$profile" claude --dangerously-skip-permissions "$@"@exec sandbox-exec -p "$profile" "$@"@' \
  > /tmp/jailrun.sh
chmod +x /tmp/jailrun.sh
# Sanity-check the substitution landed:
grep -q 'exec sandbox-exec -p "$profile" "$@"' /tmp/jailrun.sh && echo "runner ready"
```
Expected: `runner ready`.
Usage from here on: `/tmp/jailrun.sh <cmd> <args...>` runs `<cmd>` inside the jail with the current dir as the rw workspace. The runner keeps the wrapper's `--docker` flag logic, so `/tmp/jailrun.sh --docker <cmd>` runs with the docker socket allowed (used in Step 6). All probe steps below first `cd` into a throwaway workspace dir so the cwd allow-rule points somewhere harmless:
```bash
cd "$(mktemp -d)"
```

- [ ] **Step 2: Deny — reading an ssh private key fails**

Run:
```bash
/tmp/jailrun.sh /bin/bash -c 'cat ~/.ssh/id_ed25519 2>&1 || cat ~/.ssh/id_rsa 2>&1'
```
Expected: `Operation not permitted`. (Only acceptable otherwise if no private key exists on the host at all; if a key file exists, it MUST report not-permitted, not its contents.)

- [ ] **Step 3: Deny — writing outside the workspace fails**

Run:
```bash
/tmp/jailrun.sh /bin/bash -c 'touch ~/Documents/claude-jail-test 2>&1'
ls ~/Documents/claude-jail-test 2>&1
```
Expected: first command prints `Operation not permitted`; second prints `No such file or directory` (no file created).

- [ ] **Step 4: Allow — workspace read/write works**

Run:
```bash
/tmp/jailrun.sh /bin/bash -c 'touch ./jail-write-ok && echo ok && rm ./jail-write-ok'
```
Expected: `ok`, exit 0.

- [ ] **Step 5: Allow — ~/dev/repos write works**

Run:
```bash
/tmp/jailrun.sh /bin/bash -c 'touch ~/dev/repos/.jail-write-ok && echo ok && rm ~/dev/repos/.jail-write-ok'
```
Expected: `ok`, exit 0.

- [ ] **Step 6: Docker gating — denied without --docker, allowed with it**

Run:
```bash
echo "--- without --docker (expect failure) ---"
/tmp/jailrun.sh docker --context orbstack ps 2>&1 | head -2
echo "--- with --docker (expect container table / daemon reachable) ---"
/tmp/jailrun.sh --docker docker --context orbstack ps 2>&1 | head -2
```
Expected: first block shows a daemon-connection error (socket unreachable); second block reaches the daemon (header row `CONTAINER ID ...` or a normal docker response).

- [ ] **Step 7: Record results**

No commit. Note any check that did not behave as expected; if a deny check FAILED (data was readable/writable), stop and revisit the profile before proceeding — that is a security regression.

---

## Task 6: Functional smoke test and finish

**Files:** none

- [ ] **Step 1: ssh agent works**

Run (uses the runner from Task 5; `SSH_AUTH_SOCK` must be set in the calling env):
```bash
cd "$(mktemp -d)" && /tmp/jailrun.sh ssh -T git@github.com 2>&1 | head -2
```
Expected: GitHub's "successfully authenticated" greeting (auth via the launchd agent), not a permission or host-key failure.

- [ ] **Step 2: cargo build works in a repo**

Run, against a small Rust repo under `~/dev/repos`:
```bash
cd ~/dev/repos/rust-lgalloc && /tmp/jailrun.sh cargo check 2>&1 | tail -3
```
Expected: cargo runs (compiles or reports normal compile errors), not a sandbox/permission failure on `~/.cargo` or `~/.rustup`.

- [ ] **Step 3: docker works WITH --docker**

Run:
```bash
cd ~/dev/repos && claude-jail --docker --version
```
Expected: Claude version prints (flag is consumed by the wrapper, not passed to Claude). Then, if practical, verify a docker probe under the `--docker` profile reaches the daemon. This confirms the flag lifts the deny.

- [ ] **Step 4: Final apply and status**

Run:
```bash
chezmoi --source "$PWD" apply ~/.local/bin/claude-jail
git status -sb
```
Expected: clean tree (all changes committed), `claude-jail` applied.

- [ ] **Step 5: Decide branch integration**

Use the `superpowers:finishing-a-development-branch` skill to merge to `main` and push (this repo commits directly to `main`; confirm with the user).
