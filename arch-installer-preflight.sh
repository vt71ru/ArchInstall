#!/usr/bin/env bash
# arch-installer-preflight.sh
# Safe preflight for developing a Bash-based Arch Linux installer.
# Does not install packages, modify networking, create repositories, or touch disks.

set -uo pipefail

readonly SCRIPT_NAME="${0##*/}"

section() {
    printf '\n=== %s ===\n' "$1"
}

ok()   { printf '[OK]   %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; }

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

section "1. Operating system and shell"

printf 'Script: %s\n' "$SCRIPT_NAME"
printf 'User:   %s\n' "$(id -un 2>/dev/null || printf unknown)"
printf 'Shell:  %s\n' "${BASH_VERSION:-not running under Bash}"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf 'OS:     %s\n' "${PRETTY_NAME:-unknown}"
else
    warn "/etc/os-release is unavailable"
fi

if [[ "${BASH_VERSION:-}" ]]; then
    ok "Running under Bash"
else
    fail "Run this script with Bash: bash ./$SCRIPT_NAME"
fi

if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
    ok "Arch Linux or an Arch-derived system detected"
else
    warn "This is not identified as Arch Linux; pacman may be unavailable"
fi

section "2. Development tools"

missing=()
for cmd in bash pacman git curl; do
    if have_cmd "$cmd"; then
        ok "$cmd: $(command -v "$cmd")"
        case "$cmd" in
            bash)   bash --version 2>/dev/null | head -n 1 || true ;;
            pacman) pacman --version 2>/dev/null | head -n 1 || true ;;
            git)    git --version 2>/dev/null || true ;;
            curl)   curl --version 2>/dev/null | head -n 1 || true ;;
        esac
    else
        warn "$cmd is not installed or not in PATH"
        missing+=("$cmd")
    fi
done

if have_cmd git; then
    printf 'Git identity (if configured):\n'
    printf '  user.name:  %s\n' "$(git config --global user.name 2>/dev/null || printf '(not set)')"
    printf '  user.email: %s\n' "$(git config --global user.email 2>/dev/null || printf '(not set)')"
fi

section "3. Safe test-environment checks"

if [[ -r /proc/1/cgroup ]] && grep -Eqi 'lxc|container|docker|podman' /proc/1/cgroup; then
    warn "A container may be detected. Do not run an OS installer inside this environment."
else
    ok "No obvious container marker found (this does not prove the system is a VM)"
fi

if have_cmd systemd-detect-virt; then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    case "$virt" in
        ""|none) warn "Virtualization was not detected automatically" ;;
        *)       ok "Virtualization detected: $virt" ;;
    esac
else
    warn "systemd-detect-virt unavailable; virtualization was not checked"
fi

if have_cmd lsblk; then
    printf '\nBlock devices (read-only listing; no disk changes):\n'
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS 2>/dev/null || lsblk
else
    warn "lsblk unavailable; disk layout was not inspected"
fi

printf '\nSafety notes:\n'
printf '  - This script does not format, partition, mount, or write to disks.\n'
printf '  - It does not install packages or change network settings.\n'
printf '  - It does not create or modify a Forgejo repository.\n'
printf '  - Test any future installer only in a disposable VM with a dedicated test disk.\n'

section "Summary"
if ((${#missing[@]} == 0)); then
    ok "All four requested commands are available"
else
    warn "Missing commands: ${missing[*]}"
    printf 'No packages were installed. On Arch, after reviewing the list, you may install tools manually.\n'
fi

printf '\nPreflight finished. No system changes were made.\n'
