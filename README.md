# 🛠️ Dotfiles for Workspace Config 🖥️

Welcome to my **workspace configuration dotfiles** repository! 🎉 These files contain my personal setup to create a clean, productive, and visually pleasing development environment. 🚀

---

## 🚀 Quick start on a new machine

```bash
git clone https://github.com/tpham2580/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

That is the whole thing. `install.sh` detects the distro, installs what is
missing, and copies every config into `$HOME`.

| Flag | Effect |
| --- | --- |
| *(none)* | Packages + configs, terminal stack only |
| `--desktop` | Also install the Hyprland / i3 desktop stack |
| `--no-packages` | Deploy config files only, install nothing |
| `--packages-only` | Install software only, touch no config files |
| `--dry-run` | Print every action without doing any of it |
| `--yes` / `-y` | Never prompt |

**Supported distros:** Arch (`pacman`, falls back to `yay` for AUR packages),
Fedora (`dnf`), Debian/Ubuntu (`apt`).

**Nothing is ever destroyed.** Any file the script replaces is moved to
`~/.dotfiles-backup/<timestamp>/` first. Files that already match the repo are
left alone, so re-running after a `git pull` is cheap and safe.

**Not from the distro repos** — installed from their own upstream installers so
all three distros behave identically: [oh-my-zsh](https://ohmyz.sh),
[starship](https://starship.rs), [herdr](https://herdr.dev),
[hunk](https://github.com/modem-dev/hunk),
[Copilot CLI](https://github.com/github/copilot-cli),
[copilot.vim](https://github.com/github/copilot.vim).

After it finishes:

```
exec zsh          # reload the shell
nvim              # lazy.nvim installs plugins, then run :Copilot setup
herdr             # start the multiplexer (prefix is ctrl+b)
```

### 🖥️ Per-machine settings

Anything that differs between machines lives in a `*.example` file. `install.sh`
copies it to its real name **only if that file does not already exist**, so your
local edits survive every later run and every `git pull`.

| Template | Becomes | Holds |
| --- | --- | --- |
| `linux/.config/hypr/host.conf.example` | `~/.config/hypr/host.conf` | Monitor layout, wallpaper, polkit agent path |

`hyprland.conf` sources `host.conf` on its first line, so the shared config stays
identical on every machine and only the monitor block changes. Edit
`~/.config/hypr/host.conf` on each box — the file ships with commented-out blocks
for the laptop and desktop layouts.

---

## 📁 Structure

```
dotfiles/
├── install.sh                  # ← run this
├── linux/                      # mirrors $HOME exactly
│   ├── .config/
│   │   ├── herdr/              # herdr multiplexer (tmux-compatible keymap)
│   │   ├── hunk/               # hunk diff viewer
│   │   ├── hypr/               # Hyprland (+ host.conf.example)
│   │   ├── i3/                 # i3 window manager
│   │   ├── mako/ wofi/ waybar/ # Wayland notifications, launcher, bar
│   │   ├── nvim/               # Neovim
│   │   ├── picom/ polybar/ rofi/  # X11 compositor, bar, launcher
│   │   └── tmux/               # Terminal multiplexer (legacy, replaced by herdr)
│   ├── .local/scripts/         # tmux-sessionizer (legacy)
│   ├── .script/                # herdr helper scripts
│   ├── .zsh/completions/       # _herdr
│   ├── .gitconfig              # identity + hunk difftool
│   ├── .zshenv                 # EDITOR, cargo env
│   ├── .zshrc                  # Zsh config
│   └── lock.sh                 # i3 lock screen script
├── windows/                    # Windows-only configs
│   ├── .config/nvim/           # Neovim (Windows)
│   └── .glzr/glazewm/          # GlazeWM tiling WM
└── README.md
```

Every path under `linux/` maps to the same path under `$HOME`, so
`linux/.config/nvim/init.lua` → `~/.config/nvim/init.lua`. To add a new config,
drop it in the matching place and it deploys automatically.

---

## 🐧 Linux

### **herdr** — terminal multiplexer

- Configuration file: `linux/.config/herdr/config.toml`
- Deploy path: `~/.config/herdr/config.toml`
- [herdr](https://herdr.dev) replaces tmux. It is agent-aware, so a Copilot CLI
  session running in a pane is tracked as a real agent with working / blocked /
  idle state.
- The keymap is deliberately **tmux-compatible**. Concept mapping:

  | tmux | herdr |
  | --- | --- |
  | session | **workspace** (one per project — the daily switcher) |
  | window | **tab** |
  | pane | **pane** |

  A herdr *named session* is a whole separate server, not a tmux session. Those
  are switched from the shell with `hs` / `ha`, not from inside the app.

- Prefix is `ctrl+b`, same as tmux. Bindings that are not tmux ports:

  | Key | Action |
  | --- | --- |
  | `prefix+alt+s` | Workspace / session picker (`herdr-sessionizer`) |
  | `prefix+ctrl+f` | Open any folder as a workspace (`herdr-sessionize`) |
  | `prefix+shift+a` | Start Copilot CLI in this pane (`herdr-copilot`) |
  | `prefix+shift+s` | Settings (tmux's `prefix+s` is remapped to the picker) |
  | `prefix+alt+1..9` | Focus agent *n* |
  | `ctrl+alt+j` / `ctrl+alt+k` | Next / previous agent |

- Search roots for the folder picker: `linux/.config/herdr/sessionize-paths`
- **Requires:** `fzf` and `jq`

#### Helper scripts (`linux/.script/` → `~/.script/`, on `PATH`)

| Script | Purpose |
| --- | --- |
| `herdr-attach` | Attach, and return to the shell when you close your last workspace instead of landing in an auto-created empty one |
| `herdr-watch-empty` | The watcher that makes the above work |
| `herdr-sessionizer` | fzf picker over workspaces + projects + named sessions (the `tmux-sessionizer` port) |
| `herdr-sessionize` | Open any folder as a workspace (`ctrl+f`) |
| `herdr-copilot` | Register Copilot CLI as a tracked agent in the current pane |
| `herdr.zsh` | Sourced from `.zshrc`; defines `hs` `hl` `ha` `hw` `hk` and the `alt+s` / `ctrl+f` widgets |
| `setup-printer.sh` | Brother/CUPS printer setup |

### **hunk** — diff viewer

- Configuration file: `linux/.config/hunk/config.toml`
- Deploy path: `~/.config/hunk/config.toml`
- [hunk](https://github.com/modem-dev/hunk) replaces `diffview.nvim` and
  `vimdiff`. Wired into git as the difftool via `.gitconfig`, so `git difftool`
  opens it directly.
- Theme `catppuccin-mocha`, stacked mode, 4-space tabs.
- The sidebar is width-driven, not a config key: it appears automatically at
  ≥ 220 columns, and toggles with `s` down to ~71 columns.
- Install: `npm install -g hunkdiff`

### **Neovim (nvim)**

- Configuration file: `linux/.config/nvim/init.lua`
- Deploy path: `~/.config/nvim/init.lua`
- Base configuration came from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- Current theme: [Catppuccin](https://github.com/catppuccin/catppuccin) (catppuccin-mocha)
- Requires **Neovim 0.11+**: `nvim-treesitter` now tracks the `main` branch,
  because `master` is archived and breaks on 0.12. `main` has no module system,
  so highlighting and indentation are enabled manually in `init.lua`.

Custom Lua modules in `lua/custom/`:

| Module | What it does |
| --- | --- |
| `hunk.lua` | Opens the hunk TUI in a terminal tab for git review |
| `herdr.lua` | Sends code from Neovim to a Copilot CLI agent running in herdr |

Key maps added on top of kickstart:

| Key | Action |
| --- | --- |
| `<leader>gd` / `<leader>gD` | Diff uncommitted / staged (hunk) |
| `<leader>gm` | Diff against the default branch's merge base |
| `<leader>gb` / `<leader>gc` | Pick a branch / commit to review |
| `<leader>gs` | Show the last commit |
| `<leader>gr` / `<leader>gf` | Diff an arbitrary revision / the current file |
| `<leader>pp` | Prompt Copilot |
| `<leader>ps` / `<leader>pa` *(visual)* | Send / ask about the selection |
| `<leader>pf` | Send the current file |
| `<leader>ma` / `<leader>mm` | Harpoon add / menu (was `<leader>a` / `ctrl+e`) |

`:HerdrDoctor` checks every herdr CLI assumption `herdr.lua` depends on — run it
after upgrading herdr to see exactly what, if anything, broke.

### **.zshrc / .zshenv**

- Deploy paths: `~/.zshrc`, `~/.zshenv`
- `EDITOR` is set in `.zshenv`, not `.zshrc`, so **every** zsh gets it —
  including non-interactive shells and anything launched from them. hunk's `e`
  command reads `$EDITOR` from the environment it inherits.
- `~/.script` is on `PATH`; `~/.zsh/completions` is on `fpath` before oh-my-zsh
  runs `compinit` (herdr completions).
- `ctrl+f` opens the herdr folder picker (was `tmux-sessionizer`).
- `ctrl+g` starts an [aichat](https://github.com/sigoden/aichat) session using a
  Deepseek key read from `pass deepseek/api-key`.
- ssh-agent starts on first use so the ssh passphrase is entered once.

### **Hyprland**

- Configuration file: `linux/.config/hypr/hyprland.conf`
- Deploy path: `~/.config/hypr/hyprland.conf`
- Monitors, wallpaper and the polkit agent are **per-machine** — see
  [Per-machine settings](#-per-machine-settings) above.
- Bar: waybar · Launcher: wofi · Notifications: mako · Lock: swaylock + swayidle

### **i3 Window Manager** (X11, kept for older machines)

- Configuration file: `linux/.config/i3/config`
- Deploy path: `~/.config/i3/config`
- Current theme: [Catppuccin](https://github.com/catppuccin/catppuccin)
- Stack: `i3-wm i3status dmenu i3lock xbacklight feh conky xss-lock picom
  network-manager-applet light maim xclip dunst polkit-gnome polybar rofi`
  - `xss-lock` — lock and idle handling
  - `picom` — compositor (`linux/.config/picom/picom.conf`)
  - `light` — display brightness
  - `maim` / `xclip` — screenshots and clipboard
  - `dunst` — notifications
  - `polkit-gnome` — authentication/elevation
  - `polybar` — status bar (`linux/.config/polybar/config.ini`)
  - `rofi` — launcher (`linux/.config/rofi/config.rasi`)

- REMEMBER: if flathub apps do not show up in dmenu, create a shell script in `/usr/local/bin`:
  ```bash
  #!/bin/bash
  flatpak run {flatpak for application here}
  ```
- Or symlink it:
  ```bash
  sudo ln -s /opt/extract-folder/bin/start.sh /usr/local/bin/appname
  ```

### **Legacy scripts**
- `tmux-sessionizer` (`linux/.local/scripts/tmux-sessionizer`)
    - REQUIRES: `fzf` and `tmux`
    - Fuzzy-finds directories and creates a tmux session named after them
    - Superseded by `herdr-sessionizer`, kept for machines still on tmux

---

## 🪟 Windows

`install.sh` is Linux-only. On Windows, copy the files manually.

### **GlazeWM**

- Configuration file: `windows/.glzr/glazewm/config.yaml`
- Deploy path: `~/.glzr/glazewm/config.yaml`
- Windows tiling window manager (i3-like for Windows)
- Uses `lwin` (Windows key) as the primary modifier
- Requires a `DisabledHotkeys` registry entry for `Win+Number` workspace switching:
  ```powershell
  Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisabledHotkeys" -Value "0123456789" -Type String
  ```
- Status bar: [Zebar](https://github.com/glzr-io/zebar)

### **Neovim (nvim)**

- Configuration file: `windows/.config/nvim/init.lua`
- Deploy path: `~/AppData/Local/nvim/init.lua`
- Base configuration came from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- Current theme: [Kanagawa](https://github.com/rebelot/kanagawa.nvim) (kanagawa-dragon)
- ⚠️ This config has **not** been updated alongside the Linux one — it still uses
  `avante.nvim` and `diffview.nvim` and has no `herdr`/`hunk` integration
  (neither tool runs on Windows).

---

## 🔄 Updating the repo from a machine

The deploy is a copy, not a symlink, so changes made in `~/.config` have to be
copied back:

```bash
cd ~/dotfiles
cp ~/.config/nvim/init.lua      linux/.config/nvim/init.lua
cp ~/.config/herdr/config.toml  linux/.config/herdr/config.toml
git diff                        # review, then commit
```

Do **not** copy back `~/.config/hypr/host.conf` — it is intentionally
machine-specific and untracked.
