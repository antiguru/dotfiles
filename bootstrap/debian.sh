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
  git-svn
  gpg
  heaptrack
  helm
  hugo
  iotop
  jq
  linux-cpupower
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
  subversion
  sudo
  tailscale
  teleport-ent
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

# Helm ships its own apt repo on Buildkite's package registry.
helm_key_id=DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6
helm_keyring=/usr/share/keyrings/helm.gpg
helm_list=/etc/apt/sources.list.d/helm-stable-debian.list
if [ ! -f "$helm_keyring" ]; then
  helm_key=$(mktemp)
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey >"$helm_key"
  # Pin the fingerprint: a compromised repo must not be able to install its own
  # signing key.
  helm_key_got=$(gpg --show-keys --with-colons "$helm_key" \
    | awk -F: '$1 == "fpr" {print $10}' | head -n 1)
  if [ "$helm_key_got" != "$helm_key_id" ]; then
    echo "ERROR: unexpected Helm APT key ID: $helm_key_got" >&2
    exit 1
  fi
  gpg --dearmor <"$helm_key" | sudo tee "$helm_keyring" >/dev/null
  rm -f "$helm_key"
fi
if [ ! -f "$helm_list" ]; then
  echo "deb [signed-by=$helm_keyring] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
    | sudo tee "$helm_list" >/dev/null
fi

# Teleport ships its own apt repo, keyed by the Debian codename.
teleport_key_id=0C5E8BA5658E320D1B031179C87ED53A6282C411
teleport_keyring=/etc/apt/keyrings/teleport-archive-keyring.asc
teleport_list=/etc/apt/sources.list.d/teleport.list
if [ ! -f "$teleport_keyring" ]; then
  teleport_key=$(mktemp)
  curl -fsSL https://apt.releases.teleport.dev/gpg >"$teleport_key"
  # Pin the fingerprint, as for Helm.
  teleport_key_got=$(gpg --show-keys --with-colons "$teleport_key" \
    | awk -F: '$1 == "fpr" {print $10}' | head -n 1)
  if [ "$teleport_key_got" != "$teleport_key_id" ]; then
    echo "ERROR: unexpected Teleport APT key ID: $teleport_key_got" >&2
    exit 1
  fi
  sudo install -Dm644 "$teleport_key" "$teleport_keyring"
  rm -f "$teleport_key"
fi
if [ ! -f "$teleport_list" ]; then
  # shellcheck source=/dev/null
  teleport_distro=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [signed-by=$teleport_keyring] https://apt.releases.teleport.dev/debian $teleport_distro stable/v18" \
    | sudo tee "$teleport_list" >/dev/null
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

# Put a compressed RAM cache (zswap) in front of the disk swap, and prefer
# dropping page cache over swapping. Swap sits behind dm-crypt, so every swap-in
# is a 4K random read plus decryption. Under large tmpfs build trees that
# saturated the NVMe while CPUs sat idle. zswap is built into the kernel
# (CONFIG_ZSWAP=y), so modprobe.d options are ignored and its parameters go
# through sysfs at boot via tmpfiles. The shrinker writes cold pages back to
# disk swap, keeping the pool LRU-ordered instead of filling up with stale pages.
# The compressor line comes first so the pool never starts with the lzo default.
swap_sysctl=/etc/sysctl.d/99-swappiness.conf
swap_sysctl_want='vm.swappiness = 10'
if [ "$(cat "$swap_sysctl" 2>/dev/null)" != "$swap_sysctl_want" ]; then
  printf '%s\n' "$swap_sysctl_want" | sudo install -Dm644 /dev/stdin "$swap_sysctl"
  sudo sysctl --system
fi
zswap_conf=/etc/tmpfiles.d/zswap.conf
zswap_want=$'w- /sys/module/zswap/parameters/compressor       - - - - zstd\nw- /sys/module/zswap/parameters/shrinker_enabled - - - - Y\nw- /sys/module/zswap/parameters/enabled          - - - - Y'
if [ "$(cat "$zswap_conf" 2>/dev/null)" != "$zswap_want" ]; then
  printf '%s\n' "$zswap_want" | sudo install -Dm644 /dev/stdin "$zswap_conf"
  sudo systemd-tmpfiles --create "$zswap_conf"
fi

# Pass TRIM through dm-crypt to the SSD, and trim weekly. Without the crypttab
# discard option, dm-crypt drops discards, so fstrim frees nothing on the SSD.
# Cost: the SSD's free-space pattern becomes visible on the raw device, which
# leaks filesystem layout (not contents). The root volume is unlocked in the
# initrd (x-initrd.attach), so the initrd must be rebuilt to pick up the change,
# and it takes effect at the next boot.
crypttab_want=$(awk '
  !/^[[:space:]]*(#|$)/ && $4 ~ /(^|,)luks(,|$)/ && $4 !~ /(^|,)discard(,|$)/ {
    $4 = $4 ",discard"
  }
  { print }
' /etc/crypttab)
if [ "$(cat /etc/crypttab)" != "$crypttab_want" ]; then
  printf '%s\n' "$crypttab_want" | sudo install -m644 /dev/stdin /etc/crypttab
  sudo dracut --force --regenerate-all
fi
if ! systemctl is-enabled --quiet fstrim.timer; then
  sudo systemctl enable --now fstrim.timer
fi

# Discard freed swap slots. fstrim only covers mounted filesystems, so without
# this the SSD keeps treating every page ever swapped out as live data. Takes
# effect at the next swapon (boot), since re-enabling swap live first pulls all
# swapped pages back into RAM.
fstab_want=$(awk '
  !/^[[:space:]]*(#|$)/ && $3 == "swap" && $4 !~ /(^|,)discard(=|,|$)/ {
    $4 = $4 ",discard"
  }
  { print }
' /etc/fstab)
if [ "$(cat /etc/fstab)" != "$fstab_want" ]; then
  printf '%s\n' "$fstab_want" | sudo install -m644 /dev/stdin /etc/fstab
  sudo systemctl daemon-reload
fi
