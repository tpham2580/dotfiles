#!/usr/bin/env bash
#
# setup-printer.sh - Install and configure the CUPS print stack on Arch Linux
#                    for a USB Brother HL-L2300D (brlaser driver).
#
# Safe to re-run: every step checks current state before changing anything.
#
# Usage:
#   ~/.script/setup-printer.sh              # full setup
#   ~/.script/setup-printer.sh --check      # diagnose only, change nothing
#   ~/.script/setup-printer.sh --skip-upgrade
#
set -euo pipefail

PRINTER_NAME="Brother-HL-L2300D"
USB_ID="04f9:0061"

CHECK_ONLY=0
SKIP_UPGRADE=0
for arg in "$@"; do
  case "$arg" in
    --check)        CHECK_ONLY=1 ;;
    --skip-upgrade) SKIP_UPGRADE=1 ;;
    -h|--help)      awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_bld=$'\e[1m'; c_rst=$'\e[0m'
step() { printf '\n%s==>%s %s%s\n' "$c_bld" "$c_rst" "$c_bld" "$1$c_rst"; }
ok()   { printf '  %s✓%s %s\n' "$c_grn" "$c_rst" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_ylw" "$c_rst" "$1"; }
die()  { printf '  %s✗%s %s\n' "$c_red" "$c_rst" "$1" >&2; exit 1; }

# Root would break yay (it refuses to build as root) and would leave
# root-owned files in the user's home.
[[ $EUID -eq 0 ]] && die "do not run this as root; it calls sudo only where needed"

step "Preflight"
[[ -f /etc/arch-release ]] || die "this script targets Arch Linux"
command -v yay >/dev/null || die "yay not found; needed for the AUR brlaser package"
ok "Arch Linux, yay present"

if lsusb 2>/dev/null | grep -q "$USB_ID"; then
  ok "printer detected on USB ($USB_ID)"
else
  warn "printer NOT detected on USB. Check power and cable."
  warn "Continuing: the software stack can still be installed now."
fi

if (( CHECK_ONLY )); then
  step "Current state (--check, nothing will be modified)"
  for p in cups cups-filters cups-pdf brlaser; do
    if pacman -Q "$p" &>/dev/null; then ok "$p installed"; else warn "$p MISSING"; fi
  done
  systemctl is-active --quiet cups.socket && ok "cups.socket active" || warn "cups.socket inactive"
  lpstat -p 2>/dev/null || warn "no printers configured"
  exit 0
fi

# A stale sync DB plus a targeted -S is the classic Arch partial-upgrade
# footgun, so refresh the whole system rather than just the new packages.
if (( SKIP_UPGRADE )); then
  step "Skipping system upgrade (--skip-upgrade)"
  warn "if install fails on a library version, re-run without this flag"
else
  step "Full system upgrade (avoids a partial-upgrade break)"
  sudo pacman -Syu --noconfirm
  ok "system up to date"
fi

step "Installing print stack"
missing=()
for p in cups cups-filters cups-pdf; do
  pacman -Q "$p" &>/dev/null || missing+=("$p")
done
if (( ${#missing[@]} )); then
  sudo pacman -S --needed --noconfirm "${missing[@]}"
  ok "installed: ${missing[*]}"
else
  ok "cups, cups-filters, cups-pdf already installed"
fi

step "Installing brlaser driver (AUR)"
if pacman -Q brlaser &>/dev/null; then
  ok "brlaser already installed"
else
  yay -S --needed --noconfirm brlaser
  ok "brlaser installed"
fi

step "Enabling CUPS"
# Socket activation starts cupsd on first use instead of at every boot.
if systemctl is-enabled --quiet cups.socket 2>/dev/null; then
  ok "cups.socket already enabled"
else
  sudo systemctl enable --now cups.socket
  ok "cups.socket enabled and started"
fi
systemctl is-active --quiet cups.socket || sudo systemctl start cups.socket

# cupsd is socket-activated, so poke it once to make lpinfo/lpstat answer.
lpstat -r &>/dev/null || true
for _ in {1..10}; do
  lpstat -r &>/dev/null && break
  sleep 0.5
done
lpstat -r &>/dev/null || die "cupsd did not come up; check: journalctl -u cups"
ok "cupsd responding"

step "Configuring printer"
if lpstat -p "$PRINTER_NAME" &>/dev/null; then
  ok "printer '$PRINTER_NAME' already configured"
else
  uri="$(lpinfo -v 2>/dev/null | awk '/usb:\/\// && /(Brother|HL-L2300)/ {print $2; exit}')"
  [[ -n "$uri" ]] || uri="$(lpinfo -v 2>/dev/null | awk '/usb:\/\// {print $2; exit}')"
  [[ -n "$uri" ]] || die "no USB printer URI found. Is the printer on? Try: lpinfo -v"
  ok "device URI: $uri"

  ppd="$(lpinfo -m 2>/dev/null | awk '/brlaser/ && /2300/ {print $1; exit}')"
  [[ -n "$ppd" ]] || ppd="$(lpinfo -m 2>/dev/null | awk '/brlaser/ {print $1; exit}')"
  [[ -n "$ppd" ]] || die "no brlaser PPD found. Inspect manually: lpinfo -m | grep -i brlaser"
  ok "PPD: $ppd"

  sudo lpadmin -p "$PRINTER_NAME" -E -v "$uri" -m "$ppd"
  sudo lpadmin -d "$PRINTER_NAME"
  ok "printer '$PRINTER_NAME' added and set as default"
fi

step "Result"
lpstat -p -d

cat <<EOF

${c_grn}Done.${c_rst} Send a test page with:

  echo "print test" | lp

Web UI:  http://localhost:631
Re-check anytime:  $0 --check
EOF
