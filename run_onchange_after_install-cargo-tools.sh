#!/usr/bin/env bash
# Cargo-installed dev tools (user-local, no sudo, all platforms). Fires whenever
# this file changes; each tool is (re)built only when its pinned version is not
# already installed. Needs a Rust toolchain (cargo on PATH).
set -euo pipefail

command -v cargo >/dev/null || { echo "cargo not on PATH; skipping cargo tools" >&2; exit 0; }

installed=$(cargo install --list)

# ensure CRATE VERSION: install the pinned version unless it is already present.
ensure() { grep -qxF "$1 v$2:" <<<"$installed" || cargo install --locked "$1@$2"; }

ensure zizmor 1.18.0
ensure cargo-deny 0.19.9
ensure cargo-deplint 0.1.0
ensure cargo-nextest 0.9.143
ensure samply 0.13.1
ensure pollard 0.0.9
