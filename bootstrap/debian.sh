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
  atop
  bc
  bubblewrap
  build-essential
  calc
  clang
  cmake
  curl
  docker-compose
  docker.io
  dracut
  etckeeper
  gdb
  gh
  git
  heaptrack
  hugo
  iotop
  jq
  linux-perf
  lld
  mc
  mosh
  nodejs
  npm
  numactl
  passt
  pkg-config
  poppler-utils
  postgresql
  powertop
  psmisc
  python3-venv
  qemu-system
  rr
  shellcheck
  strace
  sudo
  tailscale
  time
  tmux
  tpm2-tools
  valgrind
  vim
  xxd
)
# Tailscale ships its own apt repo. Pinned to trixie: Tailscale does not
# publish for testing/forky, and trixie packages work here.
ts_distro=trixie
ts_keyring=/usr/share/keyrings/tailscale-archive-keyring.gpg
ts_list=/etc/apt/sources.list.d/tailscale.list
if [ ! -f "$ts_keyring" ]; then
  curl -fsSL "https://pkgs.tailscale.com/stable/debian/${ts_distro}.noarmor.gpg" \
    | sudo tee "$ts_keyring" >/dev/null
fi
if [ ! -f "$ts_list" ]; then
  curl -fsSL "https://pkgs.tailscale.com/stable/debian/${ts_distro}.tailscale-keyring.list" \
    | sudo tee "$ts_list" >/dev/null
fi

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

# Allow system-wide profiling (samply/perf): unrestricted perf events and
# kernel-symbol resolution for unprivileged users.
sysctl_dropin=/etc/sysctl.d/99-profiling.conf
sysctl_want=$'kernel.perf_event_paranoid = -1\nkernel.kptr_restrict = 0'
if [ "$(cat "$sysctl_dropin" 2>/dev/null)" != "$sysctl_want" ]; then
  printf '%s\n' "$sysctl_want" | sudo install -Dm644 /dev/stdin "$sysctl_dropin"
  sudo sysctl --system
fi

# Make /dev/kvm usable from inside claude-jail. The jail's user namespace maps a
# single gid, so the kvm group is unmapped there and the group bits can never
# match, no matter which groups the outer user is in. Widening the mode is the
# only way in. Cost: every local user, and every sandbox on this kernel, can
# create VMs (arbitrary guest code, unbounded host memory/CPU). Acceptable on a
# single-user workstation only.
kvm_rule=/etc/udev/rules.d/99-kvm.rules
kvm_want='KERNEL=="kvm", GROUP="kvm", MODE="0666"'
if [ "$(cat "$kvm_rule" 2>/dev/null)" != "$kvm_want" ]; then
  printf '%s\n' "$kvm_want" | sudo install -Dm644 /dev/stdin "$kvm_rule"
  sudo udevadm control --reload
  sudo udevadm trigger --name-match=kvm
fi
