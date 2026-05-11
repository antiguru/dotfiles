#!/usr/bin/env bash
# Register user-scope MCP servers in both Claude profiles.
# Re-runs whenever this file changes; idempotent via remove-before-add.
set -euo pipefail

command -v claude >/dev/null || { echo "claude CLI not on PATH; skipping"; exit 0; }
claude mcp remove --scope user github 2>/dev/null || true
claude mcp add --scope user --transport stdio github -- \
  sh -c 'GITHUB_PERSONAL_ACCESS_TOKEN=$(gh auth token) exec github-mcp-server stdio'

for dir in "$HOME/.claude-personal"; do
  CLAUDE_CONFIG_DIR="$dir" claude mcp remove --scope user github 2>/dev/null || true
  CLAUDE_CONFIG_DIR="$dir" claude mcp add --scope user --transport stdio github -- \
    sh -c 'GITHUB_PERSONAL_ACCESS_TOKEN=$(gh auth token) exec github-mcp-server stdio'
done
