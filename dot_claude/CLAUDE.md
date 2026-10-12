# General

* Do not compliment me.
* Tell me when I'm wrong. Push back.
* Prefer correctness over performance.
* Prefer reuse over writing.
* Finish tasks, don't leave half-finished work behind.
  If you can't finish a task, take a step back and consult user.
* Never drop comments, especially when refactoring code.
* If a file system operation fails due to insufficient permissions, ask me the fix it.
* Never attempt to use `sudo` on the local machine.
  On disposable remote scratch instances, sudo is fine.
* Keep chat responses terse. Fragments fine, drop filler and hedging.
  If caveman mode is active, follow it in chat.
  Code, commits, pull requests, and docs stay in normal prose.
* `~/.claude` is published in a public dotfiles repository.
  In skills, hooks, and CLAUDE.md, resolve workspace identifiers (URLs, ids, names) at run time, never hardcode them.

# Running programs

* To cap a program's memory, use `memcap LIMIT CMD`, e.g. `memcap 1G ./target/debug/environmentd`.
  It sets cgroup `memory.max`, so the program is OOM-killed at the cap and exits 137.
* Never use `systemd-run` for this.
  It needs a D-Bus socket that claude-jail does not have.
* Never use `pkill -f` or `pgrep -f PATTERN` inside a tool call.
  The pattern matches the calling shell's own command line, so it kills the shell or makes wait loops never finish.
  Kill or wait by PID, or put cleanup in a script file whose name does not match.

# Agents

* Execute ready plans with subagent-driven development without asking which approach.
* Subagents that build or start services must commit before verifying, block in the foreground (no background watchers), and return BLOCKED rather than ending the turn.
* After a subagent reports DONE, check `git status` and `git log` before trusting it.
* Write hand-off prompts as markdown with sections.

# Pull requests

* Keep pull requst comments short and precise. Do not outline test plans or specific code changes.
* Do no prefix pull request descriptions with `## Summary`.
* Do not include a test plan in the pull request description.

# Markdown

These rules cover markdown other people see: docs, commit messages, pull requests, and files in the repo.
They do not cover chat responses to me.

* In text, structure paragraphs into 4-5 sentences, where the first describes a concept, the middle 2-3 support the concept, and the last one connects it to the next paragraph or broader context.
* Only make claims that are based on evidence.
  If there's no evidence, ask the user what to do.
  Do not hallucinate.
* Use a concise, technical writing style.
* Avoid filler words, use active voice.
* Capitalization of headers: First word upper case, and after colon.
  Uppercase proper nouns, but no other words.
* Use mermaid for diagrams.
* Use the asterisk `*` for lists in markdown, not dash `-`.

# Git

* Never use `git push --force`, always use `--force-with-lease`.
* Never use `git reset --hard`. Never.
* Never use `git add -A`.
* Always work off branches in worktrees.
  Use EnterWorktree before editing files.
  Double-check that the worktree's revision matches the expected revision.
* Add local ignored files to .git/info/exclude, and global (for all users) ignores to .gitignore
* Never revert a probe with `git checkout <file>`, it discards every uncommitted edit in that file.
  Commit before probing, or revert with an edit.
* When rebasing stacks:
  * Take pre-rebase backups as tags, not branches, because `rebase --update-refs` moves every branch in the range.
  * Disable rerere (`git -c rerere.enabled=false rebase`).
  * Before pushing, check `git merge-base --is-ancestor` for every adjacent pair of branches.

# Github

* Prefer github MCP over `gh` tool.
* Mark posts to GitHub (issues, comments, reviews, pull requests) as posted by Claude Code.
* When collecting pull request feedback, call `get_reviews` in addition to the comment tools.
  A review with a body and no line comments only appears there.

# Rust

* No unsafe, unless strictly needed.
  Each unsafe block/function needs a SAFETY explanation.
* Use `CARGO_INCREMENTAL=0`, disk space and I/O is scarce.
* Large test modules go in `<module>/tests.rs`, declared with a plain `#[cfg(test)] mod tests;`, never `#[path]`.
  Small inline test modules stay inline.
* When work touches an unwieldy file, split it by responsibility as an early pure-move step that keeps the public surface.

## Comments

* No em-dashes (`—`) or structuring semicolons in comments.
* Doc comment states the contract.
  Reasoning lives inline at the decision point, not in the doc comment.
* Don't name the vendor in user-facing surfaces (e.g. column comments, docs).
* Don't narrate abstractions that belong to a future change.

# Materialize

This applies to `~/dev/repos/materialize`.

* The base branch is always upstream/main.
  Never consider `main_empty` or origin/main.

* Worktrees are in ~/dev/repos/materialize/.claude/worktrees/ Use EnterWorktree before editing files.
* Check if compiles using `cargo check`.
* Format code using `bin/fmt` after editing files, not `cargo fmt`.
  Never run `cargo fmt --check`.
* Run docker compositions in `mzcompose` using `bin/mzcompose --find NAME run WORKFLOW`, with `default` being a valid workflow that selects all workflows.
* Use `bin/mzcompose list` (or `list-workflows`, `list-compositions`) to see what can be run.
* Use `bin/mzcompose logs` to access logs of a container.
* Use `bin/mzcompose down` to stop a composition.
* Never allow as_conversions, use mz_ore::CastFrom/CastLossy.
* Pull requests use `upstream/main` as their base.
* Push branches to `origin`.
* Do not manually update `*.snap` files. Use `cargo test` followed by `cargo insta accept` instead.
