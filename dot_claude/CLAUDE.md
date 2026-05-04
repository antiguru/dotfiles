# General

* Do not compliment me.
* Tell me when I'm wrong. Push back.
* Prefer correctness over performance.
* Prefer reuse over writing.
* Finish tasks, don't leave half-finished work behind.
  If you can't finish a task, take a step back and consult user.
* Never drop comments, especially when refactoring code.
* If a file system operation fails due to insufficient permissions, ask me the fix it.
* Never attempt to use `sudo`.

# Pull requests

* Keep pull requst comments short and precise. Do not outline test plans or specific code changes.
* Do no prefix pull request descriptions with `## Summary`.
* Do not include a test plan in the pull request description.

# Markdown

* In markdown, put each sentence on its own line.
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

# Rust

* No unsafe, unless strictly needed.
  Each unsafe block/function needs a SAFETY explanation.

# Materialize

This applies to `~/dev/repos/materialize`.

* The base branch is always upstream/main.
  Never consider `main_empty` or origin/main.

* Worktrees are in ~/dev/repos/materialize/.claude/worktrees/ Use EnterWorktree before editing files.
* Check if compiles using `cargo check`.
* Format code using `cargo fmt` after editing Rust files.
  Never run `cargo fmt --check`.
* Run `bin/lint` and `cargo fmt` before committing, fixing any potential errors.
* Run locally using `bin/environmentd`, not `cargo build` or `cargo run`.
  * If it fails to start with Cockroach not running, start cockroach using `docker run --name=cockroach -d -p 26257:26257 -p 26258:8080 cockroachdb/cockroach:latest start-single-node --insecure --store=type=mem,size=2G` (or `docker start cockroach` if the container exists.)
* Run docker compositions in `mzcompose` using `bin/mzcompose --find NAME run WORKFLOW`, with `default` being a valid workflow that selects all workflows.
* Use `bin/mzcompose list` (or `list-workflows`, `list-compositions`) to see what can be run.
* Use `bin/mzcompose logs` to access logs of a container.
* Use `bin/mzcompose down` to stop a composition.

* To commit, do the following first:
  * Check that a change is clean, run `bin/lint`.
  * Use `bin/pyfmt` to format .py files.
  * Use `cargo fmt` to format .rs files.
  * Run `cargo clippy`
  * A change is clean when no (unexpected) warnings are left.

* Run testdrive files using `bin/mzcompose --find testdrive -- NAME`. `NAME` is a file in `test/testdrive`, relative to this directory.
* Run sqllogictest files using `bin/sqllogictest -- PATH`. `PATH` is relative to the root and usually a file in `test/sqllogictest`.
  * Rewrite sqllogictest files using `bin/sqllogictest -- --rewrite-results`
* Use `REWRITE=1 cargo test ...` to rewrite datadriven tests.
* Pull requests use `upstream/main` as their base.
* Push branches to `origin`.
* Do not manually update `*.snap` files. Use `cargo test` followed by `cargo insta accept` instead.
