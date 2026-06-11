# claude-jail macOS port — design

## Goal

Run Claude Code on macOS inside a sandbox that confines filesystem access, so `--dangerously-skip-permissions` can be used without risking host compromise or exfiltration of user data.
The Linux variant uses `bwrap` (user + mount namespaces) to hide `$HOME` behind tmpfs and bind back an allowlist.
macOS has no unprivileged user/mount namespaces, so the port uses `sandbox-exec` (Seatbelt) with an SBPL profile.
The security boundary is filesystem reads of user data and all writes, plus opt-in-only Docker.

## Context

* Host: macOS 26.5.1, arm64.
* `sandbox-exec` present at `/usr/bin/sandbox-exec` (Apple-deprecated but functional; used by Chrome, Nix).
* Claude Code installed via Homebrew cask: `/opt/homebrew/bin/claude` → `/opt/homebrew/Caskroom/claude-code@latest/<ver>/claude`.
  Updates run through `brew`, not the in-tree self-updater, so the install dir stays read-only inside the jail.
* Docker is OrbStack: real socket `~/.orbstack/run/docker.sock`, with `/var/run/docker.sock` symlinked to it.
* ssh uses the launchd agent: `SSH_AUTH_SOCK=/var/run/com.apple.launchd.*/Listeners`.
* `~/.cargo` and `~/.rustup` exist; repos under `~/dev/repos` build Rust.
* Existing Linux script: `private_dot_local/bin/executable_claude-jail`.

## SBPL semantics

Verified against `/System/Library/Sandbox/Profiles/application.sb`: rules use **last-match-wins** precedence.
Line 80 allows `file-read*` on `/Library`, line 81 re-denies a subpath; line 538 allows Keychains, line 543 re-denies a UUID subpath.
So the profile starts with `(deny default)`, adds broad allows, then targeted re-denies override them.

## Decisions

* **Profile strategy: filesystem-focused (A).**
  Deny-default, then permissively allow the syscalls and system reads node + tools need to run, but scope `file-write*` and sensitive reads tightly.
  Not a syscall-minimization jail; it confines user data and writes, which matches the threat.
* **Docker: opt-in flag.**
  No socket access by default. A leading `--docker` argument lifts the deny on the OrbStack socket.
* **ssh: agent socket only.**
  Allow the launchd agent socket plus read-only `~/.ssh/known_hosts` and `~/.ssh/config`. Private key files are not allowed.
* **Rust: enabled.**
  rw `~/.cargo`, ro `~/.rustup`.
* **Workspace: cwd + `~/dev/repos` (rw).**

## File structure

chezmoi cannot map two source files to one target, and the command must stay `~/.local/bin/claude-jail` on both OSes (the `claude-jail-personal` alias calls it).
So a single templated source file branches on OS.

* Rename `private_dot_local/bin/executable_claude-jail` → `executable_claude-jail.tmpl`.
* Branch on `.chezmoi.os`:
  * `linux` → existing bwrap script verbatim, comments preserved.
  * `darwin` → new sandbox-exec script.
  * else → `exit 1` stub printing "claude-jail: unsupported OS".
* Remove the `.local/bin/claude-jail` block from `.chezmoiignore`; keep the karabiner block.

## macOS wrapper script

```
config_dir = CLAUDE_CONFIG_DIR or ~/.claude
cwd        = pwd
docker     = 0
if $1 == "--docker": docker=1; shift     # must be the first argument
reject cwd containing a double-quote (would break the SBPL string)
build the SBPL profile string, interpolating: HOME, cwd, config_dir,
  the OrbStack socket real path; include the docker deny line only when docker=0
exec sandbox-exec -p "$profile" claude --dangerously-skip-permissions "$@"
```

The profile is passed inline via `-p`; no temp file.
`CLAUDE_CONFIG_DIR` is honored so the `claude-jail-personal` alias keeps working.

## SBPL profile

```scheme
(version 1)
(deny default)

;; syscalls/services needed to run node + tools (not the security boundary)
(allow process-fork process-exec*)
(allow signal)                 ; not (target self): would break subprocess mgmt
(allow sysctl-read)
(allow mach-lookup)            ; system services, DNS via mDNSResponder
(allow file-read-metadata)     ; stat / path traversal everywhere
(allow network*)               ; outbound API + git, localhost MCP

;; reads: broad, then deny $HOME. Enumerating every system path dyld + frameworks
;; touch is fragile and was incomplete (the process aborted on an unenumerated
;; dyld shared-cache read). The security boundary is $HOME — denied here, then
;; re-allowed below for the workspace + explicit allowlist (last-match-wins).
(allow file-read*)
(deny file-read* (subpath "<HOME>"))

;; writable system locations (temp, devices)
(allow file-read* file-write* (subpath "/dev"))          ; tty, null, urandom, ptys
(allow file-read* file-write* (subpath "/private/tmp")
                              (subpath "/private/var/folders"))   ; $TMPDIR

;; workspace + state (rw)
(allow file-read* file-write* (subpath "<CWD>"))
(allow file-read* file-write* (subpath "<HOME>/dev/repos"))
(allow file-read* file-write* (subpath "<CONFIG_DIR>"))
(allow file-read* file-write* (literal "<HOME>/.claude.json")
                              (literal "<HOME>/.claude.json.backup"))
(allow file-read* file-write* (subpath "<HOME>/.cargo"))

;; read-only: toolchain, shell init, git/gh config
(allow file-read* (subpath "<HOME>/.rustup")
                  (literal "<HOME>/.zshrc") (literal "<HOME>/.zshenv")
                  (subpath "<HOME>/.oh-my-zsh")
                  (literal "<HOME>/.gitconfig") (subpath "<HOME>/.config/git")
                  (subpath "<HOME>/.config/gh"))

;; ssh: agent only; known_hosts + config ro; private keys not allowed
(allow file-read* (literal "<HOME>/.ssh/known_hosts") (literal "<HOME>/.ssh/config"))
;; SSH_AUTH_SOCK (launchd) reachable via network* + global metadata

;; docker: the OrbStack socket connect is denied unless --docker is passed.
;; This deny line is emitted only when docker=0.
(deny network-outbound (literal "<ORBSTACK_DOCKER_SOCK>"))
```

Interpolation note: `<ORBSTACK_DOCKER_SOCK>` resolves to the real path `~/.orbstack/run/docker.sock` (Seatbelt resolves symlinks, so denying `/var/run/docker.sock` would not suffice).

## Security analysis

Confined:

* Reads of `$HOME` outside the allowlist are denied: `~/.ssh/id_*`, `~/Documents`, `~/Library` (Keychains, Mail, browser data), sibling repos outside `~/dev/repos`.
* Writes are confined to cwd, `~/dev/repos`, the Claude config dir, `~/.cargo`, and temp.
* Docker host-compromise requires explicit `--docker`.

Accepted holes (documented in the script header):

* World/everyone-readable system files stay readable; strategy A is not a syscall jail.
* `network*` is unrestricted outbound; no egress filtering.
* `--docker` reintroduces full host compromise (OrbStack VM root + `docker run -v /:/host`), same trade-off as Linux.
* A cwd containing a double-quote is rejected rather than escaped.

## Testing / iteration

1. Apply with chezmoi; confirm `claude-jail` resolves and starts Claude.
2. First runs will hit sandbox denials for system paths node/git/cargo need.
   Surface them with `log stream --predicate 'sender == "Sandbox"'` (or run with `(debug deny)`), then add minimal allows.
3. Verify confinement: inside the jail, reading `~/.ssh/id_ed25519` and writing `~/Documents/x` both fail; reading/writing the cwd and `~/dev/repos` succeed.
4. Verify `git push` over ssh works via the agent.
5. Verify `docker ps` fails without `--docker` and succeeds with it.
6. Verify `cargo build` works in a `~/dev/repos` Rust project.
