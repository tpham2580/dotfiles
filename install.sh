#!/usr/bin/env bash
#
# install.sh — set up this workspace on a fresh Linux machine.
#
#   git clone https://github.com/tpham2580/dotfiles.git ~/dotfiles
#   cd ~/dotfiles && ./install.sh
#
# The script is idempotent: run it again after pulling and it will refresh
# every config, backing up whatever it replaces.
#
# Distro support: Arch (pacman/yay), Fedora (dnf), Debian/Ubuntu (apt).
# Anything not in the distro repos (herdr, hunk, oh-my-zsh, starship, stylua)
# is installed from its own upstream installer so all three behave the same.
#
set -uo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DOTFILES/linux"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

DO_PACKAGES=1
DO_CONFIGS=1
DO_DESKTOP=0
DRY_RUN=0
ASSUME_YES=0

# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=; C_DIM=
fi

step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '  %sx%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
skip() { printf '  %s-%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

run() {
  if (( DRY_RUN )); then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

confirm() {
  (( ASSUME_YES )) && return 0
  local reply
  read -r -p "  $1 [y/N] " reply </dev/tty || return 1
  [[ $reply == [yY]* ]]
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --no-packages    Deploy config files only; install nothing.
  --packages-only  Install software only; touch no config files.
  --desktop        Also install the Hyprland/i3 desktop stack (bars, launchers,
                   screenshot and audio tools). Skipped by default so this can
                   run on a headless box or a work machine.
  --yes, -y        Do not prompt; assume yes.
  --dry-run        Print every action without doing any of it.
  --help, -h       Show this message.

Existing files are moved to ~/.dotfiles-backup/<timestamp>/ before being
replaced, so nothing is ever destroyed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-packages)   DO_PACKAGES=0 ;;
    --packages-only) DO_CONFIGS=0 ;;
    --desktop)       DO_DESKTOP=1 ;;
    --yes|-y)        ASSUME_YES=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    --help|-h)       usage; exit 0 ;;
    *)               usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

[[ -d $SRC ]] || die "linux/ not found next to install.sh (looked in $DOTFILES)"

# ---------------------------------------------------------------------------
# distro detection
# ---------------------------------------------------------------------------
DISTRO=unknown
PKG_MGR=
DNF_SKIP_FLAG=

detect_distro() {
  local id="" like=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    id=$(. /etc/os-release && printf '%s' "${ID:-}")
    like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
  fi

  case " $id $like " in
    *" arch "*|*" archarm "*|*" manjaro "*|*" endeavouros "*|*" cachyos "*)
      DISTRO=arch; PKG_MGR=pacman ;;
    *" fedora "*|*" rhel "*|*" centos "*|*" nobara "*)
      DISTRO=fedora; PKG_MGR=dnf ;;
    *" debian "*|*" ubuntu "*|*" pop "*|*" linuxmint "*)
      DISTRO=debian; PKG_MGR=apt ;;
    *)
      # Fall back to whichever package manager is actually present.
      for m in pacman dnf apt; do
        if command -v "$m" >/dev/null 2>&1; then
          PKG_MGR=$m
          case $m in pacman) DISTRO=arch ;; dnf) DISTRO=fedora ;; apt) DISTRO=debian ;; esac
          break
        fi
      done ;;
  esac

  # dnf5 (Fedora 41+) renamed --skip-broken to --skip-unavailable for the
  # "package does not exist" case; dnf4 only understands the old flag.
  if [[ $PKG_MGR == dnf ]]; then
    if dnf install --help 2>&1 | grep -q -- '--skip-unavailable'; then
      DNF_SKIP_FLAG=--skip-unavailable
    else
      DNF_SKIP_FLAG=--skip-broken
    fi
  fi
}

# ---------------------------------------------------------------------------
# package sets
#
# Each entry is  generic-name:arch-name:fedora-name:debian-name
# An empty field means "not in that distro's repos" -> handled by the
# from-source installers below, or skipped with a warning.
# ---------------------------------------------------------------------------
CORE_PKGS=(
  # shell + prompt
  'zsh:zsh:zsh:zsh'
  'git:git:git:git'
  'curl:curl:curl:curl'
  'wget:wget:wget:wget'
  'unzip:unzip:unzip:unzip'
  'jq:jq:jq:jq'                      # herdr-copilot / herdr-watch-empty parse agent JSON
  'fzf:fzf:fzf:fzf'                  # herdr-sessionizer, herdr-sessionize, tmux-sessionizer
  'ripgrep:ripgrep:ripgrep:ripgrep'  # telescope live_grep
  'fd:fd:fd-find:fd-find'            # telescope file finder
  'tree:tree:tree:tree'
  'gh:github-cli:gh:gh'              # git credential helper in .gitconfig
  # editor + build deps for treesitter/mason
  'neovim:neovim:neovim:neovim'
  'gcc:gcc:gcc:gcc'
  'make:make:make:make'
  'nodejs:nodejs:nodejs:nodejs'      # copilot.vim, hunk, mason LSPs
  'npm:npm:npm:npm'
  'python:python:python3:python3'
  'python-pip:python-pip:python3-pip:python3-pip'
  # terminal
  'tmux:tmux:tmux:tmux'
  'kitty:kitty:kitty:kitty'
  'xclip:xclip:xclip:xclip'
  'wl-clipboard:wl-clipboard:wl-clipboard:wl-clipboard'
  # zsh plugins (Arch ships these; elsewhere they come from git, see below)
  'zsh-autosuggestions:zsh-autosuggestions:zsh-autosuggestions:zsh-autosuggestions'
  'zsh-syntax-highlighting:zsh-syntax-highlighting:zsh-syntax-highlighting:zsh-syntax-highlighting'
  # fonts — the nvim/waybar/starship configs all assume a Nerd Font
  'nerd-font:ttf-jetbrains-mono-nerd:jetbrains-mono-fonts-all:fonts-jetbrains-mono'
  'nerd-font-symbols:ttf-nerd-fonts-symbols::'
  'noto-emoji:noto-fonts-emoji:google-noto-emoji-fonts:fonts-noto-color-emoji'
)

DESKTOP_PKGS=(
  'hyprland:hyprland:hyprland:'
  'waybar:waybar:waybar:waybar'
  'wofi:wofi:wofi:wofi'
  'rofi:rofi:rofi:rofi'
  'mako:mako:mako:mako-notifier'
  'swaybg:swaybg:swaybg:swaybg'
  'swayidle:swayidle:swayidle:swayidle'
  'swaylock:swaylock-effects:swaylock:swaylock'
  'wlogout:wlogout::'
  'grim:grim:grim:grim'
  'slurp:slurp:slurp:slurp'
  'brightnessctl:brightnessctl:brightnessctl:brightnessctl'
  'pamixer:pamixer:pamixer:pamixer'
  'thunar:thunar:Thunar:thunar'
  'polkit-agent:polkit-gnome:polkit-gnome:policykit-1-gnome'
  'i3:i3-wm:i3:i3'
  'i3lock:i3lock:i3lock:i3lock'
  'picom:picom:picom:picom'
  'polybar:polybar:polybar:polybar'
  'dunst:dunst:dunst:dunst'
  'feh:feh:feh:feh'
  'maim:maim:maim:maim'
)

field_for_distro() {
  # $1 = "generic:arch:fedora:debian"
  local IFS=':' _generic a f d
  read -r _generic a f d <<<"$1"
  case "$DISTRO" in
    arch)   printf '%s' "$a" ;;
    fedora) printf '%s' "$f" ;;
    debian) printf '%s' "$d" ;;
  esac
}

pkg_installed() {
  case "$PKG_MGR" in
    pacman) pacman -Qq "$1" >/dev/null 2>&1 ;;
    dnf)    rpm -q "$1"    >/dev/null 2>&1 ;;
    apt)    dpkg -s "$1"   >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

# Is the package in the distro's own repositories? Used to route Arch packages
# that only exist in the AUR to yay, and to keep apt from aborting the whole
# transaction over one name that does not exist on that release.
pkg_in_repos() {
  case "$PKG_MGR" in
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
    apt)    apt-cache show "$1" >/dev/null 2>&1 ;;
    dnf)    return 0 ;;  # handled by $DNF_SKIP_FLAG instead
    *)      return 1 ;;
  esac
}

aur_helper() {
  local h
  for h in yay paru; do
    have "$h" && { printf '%s' "$h"; return 0; }
  done
  return 1
}

# Build yay from source. Arch only, and only when an AUR package is needed.
install_yay() {
  aur_helper >/dev/null && return 0
  confirm "some packages are AUR-only. install yay to get them?" || return 1
  run sudo pacman -S --needed --noconfirm git base-devel || return 1
  local tmp
  tmp=$(mktemp -d)
  run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" || return 1
  run sh -c "cd '$tmp/yay-bin' && makepkg -si --noconfirm" || return 1
  rm -rf "$tmp"
  ok "yay installed"
}

install_pkgs() {
  local -a wanted=("$@") todo=() aur=() unavailable=() missing_names=()
  local entry name generic

  for entry in "${wanted[@]}"; do
    generic="${entry%%:*}"
    name=$(field_for_distro "$entry")
    if [[ -z $name ]]; then
      missing_names+=("$generic")
      continue
    fi
    pkg_installed "$name" && continue

    if pkg_in_repos "$name"; then
      todo+=("$name")
    elif [[ $PKG_MGR == pacman ]]; then
      aur+=("$name")
    else
      unavailable+=("$name")
    fi
  done

  if (( ${#missing_names[@]} )); then
    warn "not packaged on $DISTRO, install manually if you want them: ${missing_names[*]}"
  fi
  if (( ${#unavailable[@]} )); then
    warn "not found in this release's repos: ${unavailable[*]}"
  fi

  if (( ${#todo[@]} )); then
    printf '  installing: %s\n' "${todo[*]}"
    case "$PKG_MGR" in
      pacman) run sudo pacman -S --needed --noconfirm "${todo[@]}" ;;
      dnf)    run sudo dnf install -y "$DNF_SKIP_FLAG" "${todo[@]}" ;;
      apt)    run sudo apt-get update -qq; run sudo apt-get install -y "${todo[@]}" ;;
    esac
  fi

  if (( ${#aur[@]} )); then
    if install_yay; then
      local helper; helper=$(aur_helper)
      printf '  installing from AUR: %s\n' "${aur[*]}"
      run "$helper" -S --needed --noconfirm "${aur[@]}"
    else
      warn "AUR packages skipped: ${aur[*]}"
    fi
  fi

  if (( ${#todo[@]} == 0 && ${#aur[@]} == 0 )); then
    ok "all packages already present"
  fi
}

install_oh_my_zsh() {
  if [[ -d $HOME/.oh-my-zsh ]]; then
    skip "oh-my-zsh already installed"
    return 0
  fi
  # RUNZSH/CHSH keep the installer from starting a shell or editing .zshrc,
  # which would clobber the .zshrc this script is about to deploy.
  run env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && ok "oh-my-zsh installed"
}

install_starship() {
  if have starship; then skip "starship already installed"; return 0; fi
  if [[ $DISTRO == arch ]]; then
    run sudo pacman -S --needed --noconfirm starship && ok "starship installed"
  else
    run sh -c "curl -fsSL https://starship.rs/install.sh | sh -s -- --yes" \
      && ok "starship installed"
  fi
}

install_herdr() {
  if have herdr || [[ -x $HOME/.local/bin/herdr ]]; then
    skip "herdr already installed ($("${HOME}/.local/bin/herdr" --version 2>/dev/null || herdr --version 2>/dev/null))"
    return 0
  fi
  run sh -c "curl -fsSL https://herdr.dev/install.sh | sh" && ok "herdr installed"
}

install_hunk() {
  if have hunk; then skip "hunk already installed ($(hunk --version 2>/dev/null))"; return 0; fi
  have npm || { warn "npm missing, cannot install hunk"; return 1; }
  # npm's global prefix is set to ~/.local below so this needs no sudo.
  run npm install -g hunkdiff && ok "hunk installed"
}

install_copilot_cli() {
  if have copilot; then skip "GitHub Copilot CLI already installed"; return 0; fi
  have npm || { warn "npm missing, cannot install Copilot CLI"; return 1; }
  run npm install -g @github/copilot && ok "Copilot CLI installed"
}

install_copilot_vim() {
  local dest="$HOME/.config/nvim/pack/github/start/copilot.vim"
  if [[ -d $dest/.git ]]; then
    # Update rather than skip. A --depth 1 clone never advances on its own, so
    # skipping here let machines drift apart by many releases.
    if (( DRY_RUN )); then
      skip "copilot.vim present, would update"
      return 0
    fi
    if git -C "$dest" fetch --quiet --depth 1 origin HEAD 2>/dev/null \
      && git -C "$dest" reset --quiet --hard FETCH_HEAD 2>/dev/null; then
      ok "copilot.vim updated ($(git -C "$dest" log --oneline -1))"
    else
      warn "copilot.vim present but could not be updated"
    fi
    return 0
  fi
  run mkdir -p "$(dirname "$dest")"
  run git clone --depth 1 https://github.com/github/copilot.vim.git "$dest" \
    && ok "copilot.vim installed (run :Copilot setup in nvim)"
}

configure_npm_prefix() {
  # Global npm installs (hunk, copilot) must not need sudo, and ~/.local/bin is
  # already first on PATH in .zshrc.
  local prefix
  prefix=$(npm config get prefix 2>/dev/null)
  if [[ $prefix == "$HOME"* ]]; then
    skip "npm global prefix already user-local ($prefix)"
    return 0
  fi
  run npm config set prefix "$HOME/.local" && ok "npm global prefix -> ~/.local"
}

set_default_shell() {
  local zsh_path
  zsh_path=$(command -v zsh) || { warn "zsh not found, skipping chsh"; return 0; }
  if [[ ${SHELL:-} == "$zsh_path" ]]; then
    skip "zsh is already the login shell"
    return 0
  fi
  if confirm "make zsh ($zsh_path) your login shell?"; then
    grep -qxF "$zsh_path" /etc/shells 2>/dev/null \
      || run sh -c "printf '%s\n' '$zsh_path' | sudo tee -a /etc/shells >/dev/null"
    run chsh -s "$zsh_path" && ok "login shell set to zsh (takes effect next login)"
  else
    skip "login shell unchanged"
  fi
}

# ---------------------------------------------------------------------------
# config deployment
#
# linux/ mirrors $HOME exactly, so every file is copied to the same relative
# path. Whatever is already there is moved into the backup directory first.
# ---------------------------------------------------------------------------
backup() {
  local target="$1" rel="${1#"$HOME"/}"
  [[ -e $target || -L $target ]] || return 0
  if (( DRY_RUN )); then
    printf '  %s[dry-run]%s backup %s\n' "$C_DIM" "$C_RESET" "$rel"
    return 0
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  mv "$target" "$BACKUP_DIR/$rel"
}

# A *.example file in the tree is a per-machine template (e.g. the Hyprland
# monitor layout). Its real counterpart is written once and never touched again,
# so local edits survive every later install.sh run and every git pull.
seed_examples() {
  local rel target seeded=0

  while IFS= read -r -d '' file; do
    rel="${file#"$SRC"/}"
    target="$HOME/${rel%.example}"

    if [[ -e $target ]]; then
      skip "~/${rel%.example} exists, left untouched"
      continue
    fi
    run mkdir -p "$(dirname "$target")"
    run cp "$file" "$target"
    ok "seeded ~/${rel%.example} — edit it for this machine"
    (( seeded++ ))
  done < <(find "$SRC" -type f -name '*.example' -print0)

  (( seeded == 0 )) && return 0
  return 0
}

deploy_tree() {
  local copied=0 backed=0 rel target

  while IFS= read -r -d '' file; do
    rel="${file#"$SRC"/}"
    target="$HOME/$rel"

    # ~/.gitconfig carries an identity, so it goes through deploy_gitconfig.
    [[ $rel == .gitconfig ]] && continue

    # Unchanged file? Leave it and its mtime alone.
    if [[ -f $target && ! -L $target ]] && cmp -s "$file" "$target"; then
      continue
    fi

    if [[ -e $target || -L $target ]]; then
      backup "$target"
      (( backed++ ))
    fi

    run mkdir -p "$(dirname "$target")"
    run cp "$file" "$target"
    # Preserve the executable bit for the scripts in .script/ and .local/scripts/.
    [[ -x $file ]] && run chmod +x "$target"
    (( copied++ ))
  done < <(find "$SRC" -type f -print0)

  ok "$copied file(s) deployed, $backed replaced"
  if (( backed > 0 && ! DRY_RUN )); then
    printf '    %sbackup: %s%s\n' "$C_DIM" "$BACKUP_DIR" "$C_RESET"
  fi
}

deploy_gitconfig() {
  # ~/.gitconfig is the one file worth reviewing rather than overwriting: it
  # carries an identity, and a work machine usually needs a different one.
  local src="$SRC/.gitconfig" target="$HOME/.gitconfig"
  [[ -f $src ]] || return 0

  if [[ -f $target ]] && cmp -s "$src" "$target"; then
    skip "~/.gitconfig already up to date"
    return 0
  fi

  if [[ -f $target ]]; then
    local cur_name cur_email
    cur_name=$(git config --global user.name 2>/dev/null)
    cur_email=$(git config --global user.email 2>/dev/null)
    if [[ -n $cur_name || -n $cur_email ]]; then
      warn "existing git identity: ${cur_name:-?} <${cur_email:-?}>"
      if ! confirm "overwrite ~/.gitconfig with the one from dotfiles?"; then
        skip "~/.gitconfig left as-is (hunk difftool NOT wired up)"
        return 0
      fi
    fi
  fi
  backup "$target"
  run cp "$src" "$target"
  ok "~/.gitconfig deployed"
}

post_deploy_notes() {
  local -a notes=()
  have nvim || notes+=("neovim is not installed; the nvim config will not load")
  have herdr || [[ -x $HOME/.local/bin/herdr ]] || notes+=("herdr missing: curl -fsSL https://herdr.dev/install.sh | sh")
  have hunk || notes+=("hunk missing: npm install -g hunkdiff")
  have fzf || notes+=("fzf missing: herdr-sessionizer and ctrl+f will not work")
  have jq || notes+=("jq missing: herdr-copilot (prefix+A) and the empty-workspace watcher need it")
  have copilot || notes+=("Copilot CLI missing: npm install -g @github/copilot (prefix+shift+A needs it)")

  (( ${#notes[@]} == 0 )) && return 0
  step "Still to do"
  local n; for n in "${notes[@]}"; do warn "$n"; done
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  detect_distro
  step "Environment"
  ok "distro: $DISTRO${PKG_MGR:+ (}${PKG_MGR}${PKG_MGR:+)}"
  ok "dotfiles: $DOTFILES"
  (( DRY_RUN )) && warn "dry run — nothing will be changed"

  if (( DO_PACKAGES )); then
    if [[ -z $PKG_MGR ]]; then
      warn "no supported package manager found; skipping package installation"
    else
      step "Core packages"
      install_pkgs "${CORE_PKGS[@]}"

      if (( DO_DESKTOP )); then
        step "Desktop packages (Hyprland / i3)"
        install_pkgs "${DESKTOP_PKGS[@]}"
      else
        skip "desktop stack skipped (pass --desktop to include it)"
      fi
    fi

    step "Tools outside the distro repos"
    have npm && configure_npm_prefix
    install_oh_my_zsh
    install_starship
    install_herdr
    install_hunk
    install_copilot_cli
  else
    skip "package installation skipped (--no-packages)"
  fi

  if (( DO_CONFIGS )); then
    step "Deploying configs to \$HOME"
    seed_examples
    deploy_tree
    deploy_gitconfig
    step "Neovim"
    install_copilot_vim
    ok "plugins install on first launch (lazy.nvim bootstraps itself)"
    if (( DO_PACKAGES )); then
      step "Shell"
      set_default_shell
    fi
  else
    skip "config deployment skipped (--packages-only)"
  fi

  post_deploy_notes

  step "Done"
  cat <<EOF
  Next:
    1. exec zsh                       reload the shell
    2. nvim                           let lazy.nvim install plugins, then :Copilot setup
    3. herdr                          start the multiplexer (prefix is ctrl+b)
       ctrl+b alt+s  workspace/session picker    ctrl+b ctrl+f  open a folder
       ctrl+b shift+a  start Copilot CLI in this pane
    4. git difftool                   opens hunk
EOF
}

main "$@"
