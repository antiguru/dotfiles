#!/usr/bin/env bash
# Cargo-installed dev tools (user-local, no sudo, all platforms). Fires whenever
# this file changes; each tool is (re)built only when its pinned version is not
# already installed. Needs a Rust toolchain (cargo on PATH).
set -euo pipefail

# A fresh rustup install is not on PATH yet in chezmoi's environment.
# shellcheck source=/dev/null
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
command -v cargo >/dev/null || { echo "cargo not on PATH; skipping cargo tools" >&2; exit 0; }

installed=$(cargo install --list)

# ensure CRATE VERSION: install the pinned version unless it is already present.
ensure() { grep -qxF "$1 v$2:" <<<"$installed" || cargo install --locked "$1@$2"; }

ensure zizmor 1.30.1
ensure cargo-deny 0.20.2
ensure cargo-deplint 0.1.0
ensure cargo-binutils 0.4.0
ensure cargo-llvm-lines 0.4.48
ensure cargo-nextest 0.9.148
ensure samply 0.13.1
ensure pollard 0.0.10
