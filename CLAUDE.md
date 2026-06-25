# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This is a [chezmoi](https://chezmoi.io) source tree: the managed copy of the user's dotfiles, applied into `$HOME`.
Editing a file here does not change the live system until `chezmoi apply` runs.
The repo targets two operating systems (`darwin`, `linux`) from one source via Go templates.

## Workflow

* Edit the source file in this tree, never the deployed file in `$HOME` (apply overwrites it).
* `chezmoi diff` shows pending target changes (current `$HOME` state on `-`, desired source state on `+`).
* `chezmoi diff <target-path>` and `chezmoi apply --verbose <target-path>` scope to one deployed file, e.g. `~/.local/bin/claude-jail`.
* `chezmoi edit --apply <target>` edits source and applies in one step.
* `chezmoi execute-template < file.tmpl` renders a template with the current data for debugging.
* There is no build or test suite; `chezmoi diff` before apply is the verification step.

## Source-name conventions

chezmoi encodes target attributes in the source filename, not in metadata.

* `dot_foo` → `~/.foo`; `private_` → mode 0600; `executable_` → +x; `symlink_` → a symlink; `.tmpl` → rendered as a template.
* `run_once_*` runs once ever (tracked by content hash); `run_onchange_*` re-runs whenever the script body changes; `before`/`after` orders relative to file application.
* Renaming a source file changes the deployed target, so preserve prefixes when refactoring.

## Templating and data

* Template data comes from `.chezmoi.toml.tmpl`: `.chezmoi.os`, `.name`, `.email`, and `.shell` (prompted once at init).
* OS gating is `{{ if eq .chezmoi.os "darwin" }}` / `"linux"`; shell gating is `{{ if eq .shell "zsh" }}`.
* `.chezmoiignore` is itself a template; it excludes `docs/**` and `bootstrap/**` from apply, and platform-irrelevant files (e.g. karabiner off macOS).

## Secrets

* Encryption is age; the identity is `~/.config/chezmoi/key.txt`, the recipient is pinned in `.chezmoi.toml.tmpl`.
* `*.age` files are listed in `.chezmoiignore` so they are never applied standalone.
* They are consumed only inline via `{{ include "path.age" | decrypt | trim }}` into a target file (see `private_dot_config/materialize/mz.toml.tmpl`, `grafana_token.age`).
* Encrypt a new secret with `chezmoi encrypt < plain > secret.age`; never commit plaintext credentials.

## Provisioning scripts

* `run_onchange_before_install-packages-darwin.sh.tmpl` is the macOS `brew bundle` manifest (brews + casks); edit the heredoc to add a package.
* `run_onchange_before_install-local-bin-linux.sh.tmpl` installs pinned release binaries into `~/.local/bin` on Linux (no Homebrew there); `bootstrap/debian.sh` handles system packages.
* `run_onchange_after_install-cargo-tools.sh` installs pinned `cargo install` tools on all platforms.
* `run_onchange_after_install-claude-mcp.sh.tmpl` registers user-scope MCP servers into both Claude profiles via the `claude mcp` CLI; it is remove-before-add idempotent.
* Version bumps in these scripts trigger re-runs because the body hash changes.

## Claude Code config

* Two profiles are managed: `dot_claude/` (default, `~/.claude`) and `dot_claude-personal/` (`~/.claude-personal`, selected via `CLAUDE_CONFIG_DIR`).
* `dot_claude/settings.json.tmpl` holds the permission allowlist and hooks; live `/config` edits drift from source and show up in `chezmoi diff` until reconciled.
* `dot_claude/statusline.py` is the status line script (token usage, context %, PR/rate-limit info).

## claude-jail

`private_dot_local/bin/executable_claude-jail.tmpl` is the most involved file: it runs Claude Code inside an OS sandbox.

* Linux branch uses bwrap (mount namespace); macOS branch builds a Seatbelt/SBPL profile passed to `sandbox-exec`.
* The macOS security model is deny-default, allow-read-everywhere, then `(deny file-read* (subpath "$HOME"))`, then re-allow the workspace plus an explicit allowlist; last-match-wins, so order matters.
* Paths are interpolated into the SBPL string, so the script rejects paths containing quote/backslash/newline before building the profile.
* Docker is opt-in via a leading `--docker` arg (full host-compromise blast radius, documented in the header).
* The Seatbelt profile is fixed at process launch: editing and applying the file does not change an already-running jailed session; it must restart.
* Design rationale lives in `docs/superpowers/specs/2026-06-04-claude-jail-macos-design.md`.

## docs/

* `docs/` is git-tracked but excluded from apply; it holds the "why" behind managed files.
* `superpowers/specs/` are durable design docs; `superpowers/plans/` are historical implementation plans.
* When a managed file's shape needs justification, add or update a spec here rather than over-commenting the file.
