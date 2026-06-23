#!/usr/bin/env bash
# One-shot Debian machine setup. Run manually (NOT managed by chezmoi):
#   ./bootstrap/debian.sh
# Covers system-level changes that need sudo: apt packages plus a couple of
# systemd settings. User-local tools (e.g. buf) are handled by chezmoi instead.
# Idempotent: safe to re-run.
set -euo pipefail

# Packages I install by hand (captured from apt history); base/system packages
# pulled in by the Debian installer are deliberately excluded.
apt_packages=(
  aptitude
  bubblewrap
  build-essential
  clang
  cmake
  curl
  docker-compose
  docker.io
  etckeeper
  gh
  git
  jq
  lld
  mc
  nodejs
  pkg-config
  powertop
  python3-venv
  shellcheck
  sudo
  tmux
  vim
)
sudo apt-get update
sudo apt-get install -y "${apt_packages[@]}"

# Run my user services without an active login session.
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
  sudo loginctl enable-linger "$USER"
fi

# Suspend instead of powering off when the power button is pressed.
dropin=/etc/systemd/logind.conf.d/power-button.conf
want=$'[Login]\nHandlePowerKey=suspend'
if [ "$(cat "$dropin" 2>/dev/null)" != "$want" ]; then
  printf '%s\n' "$want" | sudo install -Dm644 /dev/stdin "$dropin"
  sudo systemctl restart systemd-logind
fi
