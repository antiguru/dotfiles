#!/usr/bin/env bash
# gh extensions and the agent skills that document them (all platforms). Fires
# whenever this file changes. Skills install at user scope for Claude Code
# (~/.claude/skills) and carry source metadata for `gh skill update`. Needs an
# authenticated gh on PATH.
set -euo pipefail

command -v gh >/dev/null || { echo "gh not on PATH; skipping gh extensions" >&2; exit 0; }

# renovate: datasource=github-releases depName=github/gh-stack
gh_stack_version="v0.0.8"
# renovate: datasource=github-releases depName=cli/cli
gh_cli_skill_version="v2.95.0"

# A pinned extension refuses `gh extension upgrade`, so replace it when the
# installed version differs from the pin.
if ! gh extension list | grep -qxF $'gh stack\tgithub/gh-stack\t'"$gh_stack_version"; then
  gh extension remove stack 2>/dev/null || true
  gh extension install github/gh-stack --pin "$gh_stack_version"
fi

skill() { gh skill install "$1" "$2" --pin "$3" --agent claude-code --scope user --force; }

skill github/gh-stack gh-stack "$gh_stack_version"
skill cli/cli gh "$gh_cli_skill_version"
