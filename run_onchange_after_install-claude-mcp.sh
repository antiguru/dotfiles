#!/usr/bin/env bash
# Register user-scope MCP servers in both Claude profiles.
# Re-runs whenever this file changes; idempotent via remove-before-add.
set -euo pipefail

command -v claude >/dev/null || { echo "claude CLI not on PATH; skipping"; exit 0; }
claude mcp remove --scope user github 2>/dev/null || true
claude mcp add --scope user --transport stdio github -- \
  sh -c 'GITHUB_PERSONAL_ACCESS_TOKEN=$(gh auth token) exec github-mcp-server stdio'

# HTTP MCP servers (main profile only). rustrover is local and only connects
# when RustRover is running; polarsignals uses short-lived tokens.
claude mcp remove --scope user polarsignals 2>/dev/null || true
claude mcp add --scope user --transport http polarsignals https://api.polarsignals.com/api/mcp
claude mcp remove --scope user rustrover 2>/dev/null || true
claude mcp add --scope user --transport http rustrover http://localhost:64342/stream
claude mcp remove --scope user launchdarkly 2>/dev/null || true
claude mcp add --scope user --transport http launchdarkly https://mcp.launchdarkly.com/mcp/launchdarkly
claude mcp remove --scope user buildkite 2>/dev/null || true
claude mcp add --scope user --transport http buildkite https://mcp.buildkite.com/mcp

for dir in "$HOME/.claude-personal"; do
  CLAUDE_CONFIG_DIR="$dir" claude mcp remove --scope user github 2>/dev/null || true
  CLAUDE_CONFIG_DIR="$dir" claude mcp add --scope user --transport stdio github -- \
    sh -c 'GITHUB_PERSONAL_ACCESS_TOKEN=$(gh auth token) exec github-mcp-server stdio'
done
