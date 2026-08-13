# 🛠️ Dotfiles for Workspace Config 🖥️

Welcome to my **workspace configuration dotfiles** repository! 🎉 These files contain my personal setup to create a clean, productive, and visually pleasing development environment. 🚀

---

## 🚀 Quick start on a new machine

### 🐧 Linux

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

### 🪟 Windows

```powershell
git clone https://github.com/tpham2580/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles
.\install.ps1
```

`install.ps1` is the PowerShell counterpart of `install.sh`: it installs the
missing packages with `winget`, then copies every config under `windows\` into
place. It requires **PowerShell 7** (`#Requires -Version 7.0`) — Windows
PowerShell 5.1 runs `Restricted` by default and will not dot-source the herdr
helpers.

| Flag | Effect |
| --- | --- |
| *(none)* | Packages + configs |
| `-NoPackages` | Deploy config files only, install nothing |
| `-PackagesOnly` | Install software only, touch no config files |
| `-DryRun` | Print every action without doing any of it |
| `-Yes` | Never prompt |

Same safety rules as Linux: replaced files are moved to
`~\.dotfiles-backup\<timestamp>\` first, and files that already match the repo
are skipped, so re-running after a `git pull` is cheap.

**Two packages do not come from winget:**

- **herdr** — `winget search herdr` only returns a *third-party fork* several
  versions behind, so the script always uses the upstream installer
  (`irm https://herdr.dev/install.ps1 | iex`).
- **hunk** — `npm install -g hunkdiff`.

**Themes are read back, not hardcoded.** The script prints the herdr and hunk
themes by parsing the configs it just deployed, so changing a theme in
`windows\AppData\Roaming\herdr\config.toml` is all it takes — the installer
needs no edit.

**Paths are retargeted per machine.** herdr does not expand `$HOME` (or any
variable) inside `[[keys.command]]`, so the tracked `config.toml` has to carry an
absolute path to the helper scripts. `install.ps1` rewrites that path to the
current machine's home directory as it deploys, so the bindings work under any
username or profile location — nothing to fix by hand. The repo copy keeps
whatever the last machine committed; only the deployed copy is rewritten.

After it finishes:

```powershell
pwsh              # reload the shell (or: . $PROFILE)
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
| `windows/AppData/Roaming/herdr/sessionize-paths` | `%APPDATA%\herdr\sessionize-paths` | Folders the sessionizer searches (`C:\Projects`) |

On Windows the mechanism is the same but the file has no `.example` suffix:
`install.ps1` treats `sessionize-paths` as **seed-once**, writing it only when it
is absent, so per-machine search roots survive later runs and `git pull`.

`hyprland.conf` sources `host.conf` on its first line, so the shared config stays
identical on every machine and only the monitor block changes. Edit
`~/.config/hypr/host.conf` on each box — the file ships with commented-out blocks
for the laptop and desktop layouts.

---

## 📁 Structure

```
dotfiles/
├── install.sh                  # ← run this on Linux
├── install.ps1                 # ← run this on Windows
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
│   ├── AppData/
│   │   ├── Local/Packages/…/   # Windows Terminal settings.json
│   │   └── Roaming/herdr/      # herdr config + sessionize search roots
│   ├── .copilot/scripts/       # herdr helper scripts (PowerShell)
│   ├── .config/hunk/           # hunk diff viewer
│   ├── .config/nvim/           # Neovim (deploys to %LOCALAPPDATA%\nvim)
│   └── .glzr/
│       ├── glazewm/            # GlazeWM tiling WM
│       └── zebar/              # Zebar status bar
└── README.md
```

Every path under `linux/` maps to the same path under `$HOME`, so
`linux/.config/nvim/init.lua` → `~/.config/nvim/init.lua`. To add a new config,
drop it in the matching place and it deploys automatically.

**`windows/` does not mirror `$HOME` one-for-one**, because Windows apps
disagree about where config belongs. `install.ps1` applies these rules in order:

| Path under `windows/` | Deploys to | Used by |
| --- | --- | --- |
| `.config/nvim/*` | `%LOCALAPPDATA%\nvim\` | Neovim |
| `AppData/Roaming/*` | `%APPDATA%\` | herdr |
| `AppData/Local/*` | `%LOCALAPPDATA%\` | Windows Terminal |
| *everything else* | `$HOME\` | hunk, GlazeWM, Zebar, Copilot scripts |

The `.config/nvim` entry is a leftover from the Linux tree — Neovim on Windows
reads `%LOCALAPPDATA%\nvim`, not `~\.config\nvim`, so it needs the special case.

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
- Terminal chat is Copilot CLI, started in a herdr pane with `prefix+shift+A`
  (`herdr-copilot`). There is no `ctrl+g` binding.
- ssh-agent starts on first use so the ssh passphrase is entered once.

### **Hyprland**

- Configuration file: `linux/.config/hypr/hyprland.conf`
- Deploy path: `~/.config/hypr/hyprland.conf`
- Monitors, wallpaper and the polkit agent are **per-machine** — see
  [Per-machine settings](#-per-machine-settings) above.
- Bar: waybar · Launcher: wofi · Notifications: mako · Lock: swaylock + swayidle
- Also autostarted: `xdg-desktop-portal-hyprland` (screen share, file pickers),
  `nm-applet` and `blueman-applet` (network and bluetooth trays — waybar's
  bluetooth module opens `blueman-manager` on click). The waybar weather module
  runs `waybar-wttr.py`, which needs Python `requests`. `install.sh --desktop`
  installs all of them.

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

`install.sh` is Linux-only. On Windows, copy the files manually. Every path
under `windows/` maps to the same path under `$HOME`, so
`windows/AppData/Roaming/herdr/config.toml` → `~/AppData/Roaming/herdr/config.toml`.

### **herdr** — terminal multiplexer

- Configuration file: `windows/AppData/Roaming/herdr/config.toml`
- Deploy path: `%APPDATA%\herdr\config.toml` (reload with `herdr server reload-config`)
- The `[keys]` block is kept **identical to `linux/.config/herdr/config.toml`** —
  same tmux-compatible prefix (`ctrl+b`), same 36 bindings. Only the sections
  below it differ, and each difference is a Windows constraint:

  | Windows-only | Why |
  | --- | --- |
  | `onboarding = false` | Skips the first-run wizard |
  | `[theme] name = "kanagawa"` | Uses the Kanagawa Wave palette (Linux is catppuccin) |
  | `[theme.custom]` | Pins Wave accents and lets Windows Terminal's `opacity` show through |
  | `[terminal] default_shell = "pwsh"` | PowerShell 5.1 is `Restricted` and refuses to dot-source the helper scripts |
  | `[[keys.command]]` paths | PowerShell in `~\.copilot\scripts` instead of bash in `~/.script` |

- The helper scripts are PowerShell instead of bash, and there is no `jq`
  dependency — `ConvertFrom-Json` does the same job.
- **Requires:** `fzf` (`winget install --id junegunn.fzf`) and PowerShell 7 (`pwsh`).
- ⚠️ The `[[keys.command]]` entries use **absolute** `C:\Users\<you>\...` paths.
  herdr does not expand `$HOME` / `%USERPROFILE%` there, so fix the user name
  after copying the file to a new machine.

| Key | Action |
| --- | --- |
| `prefix+alt+s` | Workspace / folder picker (`Invoke-HerdrSessionizer.ps1`) |
| `prefix+ctrl+f` | Open any folder as a workspace (`Invoke-HerdrSessionize.ps1`) |
| `prefix+a` | Start a Copilot agent in the focused pane |
| `prefix+shift+a` | Same, pre-authorized to drive hunk |
| `prefix+alt+k` | Stop and delete the current session |

#### Helper scripts (`windows/.copilot/scripts/` → `~/.copilot/scripts/`)

| Script | Purpose |
| --- | --- |
| `Invoke-HerdrSession.ps1` | Core session helpers: `Get-HerdrExe`, `Get-HerdrSession`, `Connect-HerdrSession`, the detach→attach handoff |
| `Invoke-HerdrSessionize.ps1` | Open any folder as a workspace and name new workspaces — the `herdr-sessionize` port |
| `Invoke-HerdrSessionizer.ps1` | fzf picker over the `default` session's workspaces (pane count + agent status) **and** the folders from `sessionize-paths` |
| `Select-HerdrSession.ps1` | Session-only picker (superseded by the sessionizer, kept because `hsw` still uses it) |
| `Start-HerdrAgentHere.ps1` | Start a Copilot agent in the focused pane instead of splitting a new one |
| `Stop-CurrentHerdrSession.ps1` | Stop + delete the session this pane belongs to, behind a typed confirmation |
| `Remove-StoppedHerdrSession.ps1` | The reaper that outlives the killed server to finish the delete |

#### Shell bindings and aliases

Add to `$PROFILE`. Only the sessionizer binds `Alt+S`, so load order no longer
decides which picker you get; `Invoke-HerdrSession.ps1` still loads first
because the sessionizer builds on its helpers:

```powershell
$__herdrSession = "$HOME\.copilot\scripts\Invoke-HerdrSession.ps1"
if (Test-Path $__herdrSession) { . $__herdrSession }

$__herdrSessionizer = "$HOME\.copilot\scripts\Invoke-HerdrSessionizer.ps1"
if (Test-Path $__herdrSessionizer) { . $__herdrSessionizer }
```

| Key / alias | Action |
| --- | --- |
| `Alt+S` / `hz` | Workspace **and** folder picker for the `default` session; type a new name to create a workspace in the current directory |
| `Ctrl+F` / `hf` | Open any folder as a workspace (fzf), prompting for its workspace name |
| `hf <dir>` / `hw <dir>` | Open a specific folder and prompt for its workspace name |
| `hw <dir> -Name <name>` | Open a specific folder with a supplied workspace name |
| `hf -Edit` | Edit the search-roots file |
| `hz -Rows` | Print the raw picker rows (what fzf's reload binding calls) |
| `hdr [name]` | Attach in a loop that honors the switch handoff |
| `hsw [name]` | Session-only picker / switch |

Inside the pickers: `enter` switches workspaces, `ctrl-t` opens one in a new
Windows Terminal tab, `del` closes a workspace, and `ctrl-c` cancels. Each
workspace can contain its own group of panes and agents.

`Alt+S` never lists sessions. Outside herdr it pins itself to `default`, so the
terminal and the in-herdr popup show the same thing: that session's workspaces,
then every folder from `sessionize-paths` that no workspace is sitting in yet.
Picking a folder opens it as a workspace in `default` (deriving a unique name,
no prompt) and attaches — the whole `tmux-sessionizer` workflow in one key. The
model is one session holding several workspaces, so a typed name that matches no
row also becomes a workspace here, rooted at the focused pane's directory, and
never spawns a separate server. When the server is down the workspace rows are
simply absent and opening a folder starts it. Named sessions, on the rare
occasion you want one, are still reachable through `hsw` / `hdr`.

`del` always asks for confirmation first — it sits one key away from the arrows,
and closing a workspace kills every process in it. It additionally refuses to
touch the `default` session or the session you are currently attached to. If you
close the workspace you are *looking at*, focus moves to the next remaining one
(or the previous, if it was last); closing the very last workspace ends the
session and drops you back to the plain terminal.

#### Two Windows fzf traps worth knowing

Linux's `herdr-sessionizer` deletes **in place** with
`del:execute-silent(...)+reload(...)`. That is not portable, and neither failure
mode is obvious — both just look like a dead key:

1. **A child process cannot prompt you.** On Linux the child reopens `/dev/tty`.
   Windows has no equivalent, and fzf's own stdin is the pipe feeding it rows —
   so a child spawned by `execute` inherits a stdin already at EOF, on a console
   fzf is still painting. The prompt is invisible and reads nothing, so it always
   declines. **Fix:** `del` is reported via `--expect` instead; fzf exits, the
   parent PowerShell process (which owns the console) confirms and deletes, then
   reopens the picker. Closing several rows in a row still works — the list just
   blinks instead of reloading in place.

2. **`--bind` / `--preview` commands must contain no double quotes.** PowerShell
   escapes an embedded `"` as `\"` when building a native command line and
   `cmd.exe` does not undo it, so `-File "C:\...ps1"` arrives as
   `-File \"C:\...ps1\"`. Under `reload` that yields no output and the picker
   goes **blank**. `--with-shell` cannot help: fzf funnels placeholder commands
   through a temp batch file on Windows. **Fix:** keep quotes out of fzf's argv —
   the folder preview puts them in the *value* of `%HERDR_PWSH%`, which `cmd`
   expands at run time. Note also that fzf substitutes `{}` / `{1}` as
   **single-quoted** values that `cmd` does not strip, which is why the preview
   is routed through `pwsh`, where `'C:\some path'` is already valid syntax.

#### How this differs from Linux

A herdr *named session* is a separate server process with its own socket, and a
client cannot re-point itself at another one. Linux therefore hides sessions
from the picker while you are inside herdr. Windows instead uses a **handoff
file** (`~\.herdr\.switch-target`): the profile wraps the ordinary no-argument
`herdr` command in the same attach loop as `hdr`, so picking something in
another session writes the target and `ctrl+b d` re-attaches to it. A Herdr
process started before that wrapper was loaded falls back to opening the
destination in a new Windows Terminal tab.

Because focusing a workspace is a plain socket call to *that* session's server,
the sessionizer can list and focus workspaces across every running session — so
one `enter` + one detach lands you on exactly the workspace you picked.

- Search roots for the folder picker: `windows/AppData/Roaming/herdr/sessionize-paths`
  (one `path[:depth]` per line; `~` expands; override the file with
  `$env:HERDR_SESSIONIZE_PATHS`). It is seeded automatically on first use.

### **hunk** — diff viewer

- Configuration file: `windows/.config/hunk/config.toml`
- Deploy path: `~\.config\hunk\config.toml`
- Mirrors `linux/.config/hunk/config.toml` apart from two deliberate changes:
  `theme = "kanagawa-dragon"` (matching nvim and herdr on Windows) and
  `transparent_background = true`, the counterpart of herdr's
  `panel_bg = "reset"` so Windows Terminal's `opacity` shows through hunk too.
- ⚠️ `tab_width` is **not** a recognised key in hunk 0.17.7 — the accepted set is
  `mode`, `vcs`, `theme`, `watch`, `exclude_untracked`, `line_numbers`,
  `wrap_lines`, `hunk_headers`, `menu_bar`, `agent_notes`, `copy_decorations`,
  `transparent_background`, `color_moved`. The `tab_width` line in the Linux
  config is a no-op and is not mirrored here.
- Unlike Linux, hunk is **not** wired into git as the difftool here — Windows
  `~\.gitconfig` has no `[diff] tool = hunk`. Add it if you want `git difftool`
  to open hunk:
  ```gitconfig
  [diff]
      tool = hunk
  [difftool "hunk"]
      cmd = hunk difftool \"$LOCAL\" \"$REMOTE\" \"$BASE\"
  [difftool]
      prompt = false
  ```
- Install: `npm install -g hunkdiff`

### **GlazeWM**

- Configuration file: `windows/.glzr/glazewm/config.yaml`
- Deploy path: `~/.glzr/glazewm/config.yaml`
- Install: `winget install glzr-io.glazewm`
- Windows tiling window manager (i3-like for Windows)
- Uses `lwin` (Windows key) as the primary modifier
- Requires a `DisabledHotkeys` registry entry for `Win+Number` workspace switching:
  ```powershell
  Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisabledHotkeys" -Value "0123456789" -Type String
  ```
- `install.ps1` runs `glazewm command wm-reload-config` after deploying, so an
  already-running instance picks up the new config without a restart.

> **`glazewm` on its own does not start the window manager.** The binary on
> `PATH` (`...\GlazeWM\cli\glazewm.exe`) is the CLI *client*, not the WM
> (`...\GlazeWM\glazewm.exe`). Running bare `glazewm` prints usage and exits 0
> having started nothing, which looks exactly like "installed but no UI". The
> window manager is started with the `start` subcommand:
>
> ```powershell
> glazewm start
> ```
>
> winget also registers no autostart entry, so nothing launches the WM at login.
> `install.ps1` handles both: it starts the WM if it is not already running, and
> writes an `HKCU:\...\CurrentVersion\Run\GlazeWM` entry pointing at
> `glazewm start`.

### **Zebar** — GlazeWM status bar

- Configuration file: `windows/.glzr/zebar/settings.json`
- Deploy path: `~/.glzr/zebar/settings.json`
- Install: `winget install glzr-io.zebar`
- [Zebar](https://github.com/glzr-io/zebar) is a **hard dependency of the GlazeWM
  config**, not an optional extra — `config.yaml` starts it and kills it:
  ```yaml
  startup_commands: ['shell-exec zebar']
  shutdown_commands: ['shell-exec taskkill /IM zebar.exe /F']
  ```
  It is also in the `window_rules` ignore list so the bar is never tiled. Without
  Zebar installed, GlazeWM starts with no bar at all, so `install.ps1` warns
  about it in the "Still to do" section.
- `settings.json` only selects the startup widget (the `glzr-io.starter` pack,
  `with-glazewm` widget, `default` preset). The widget pack itself ships with
  Zebar. `.marketplace/` holds install receipts (timestamps) and is gitignored.

### **Windows Terminal**

- Configuration file:
  `windows/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- Deploy path: the same path under `%LOCALAPPDATA%`
- Install: `winget install Microsoft.WindowsTerminal`
- Tracked because herdr's `panel_bg = "reset"` depends on the terminal's own
  opacity/theme to render correctly.
- ⚠️ Windows Terminal **rewrites this file itself** — it appends profiles when it
  discovers newly installed shells. Expect it to drift, and copy it back before
  committing. Its sibling files (`state.json`, `elevated-state.json`, `*.backup`)
  are per-machine runtime state and are gitignored.
- Profile GUIDs are generated from the profile source, so stock profiles resolve
  on any machine; a profile pointing at a shell that is not installed simply
  fails to launch.

### **Neovim (nvim)**

- Configuration file: `windows/.config/nvim/init.lua`
- Deploy path: `~/AppData/Local/nvim/init.lua`
- Base configuration came from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- Current theme: [Kanagawa](https://github.com/rebelot/kanagawa.nvim) (kanagawa-dragon)
- The Windows tree has since diverged from the Linux one and carries three
  modules that tie Neovim into the herdr/hunk workflow:

  | Module | Does |
  | --- | --- |
  | `lua/custom/review.lua` | Review mode — repoints gitsigns at the **merge-base** with the target branch, so every hunk a branch introduced stays highlighted in real, editable buffers even after it is committed and pushed (plain gitsigns diffs against `HEAD`, so the gutter goes blank once you commit). |
  | `lua/custom/plugins/review.lua` | Lazy-loads the above off `gitsigns.nvim`; `init` only registers commands and keymaps, so startup cost is unmeasurable. |
  | `lua/custom/aisend.lua` | Sends a visual selection plus a prompt to the Copilot agent in the current herdr session — the terminal equivalent of VS Code's "add selection to Copilot chat". Pairs with hunk: press `e` on a hunk, select lines, `<leader>ai`. When more than one agent is running, the picker leads with the **workspace name and tab name**: agent names are usually unset, terminal titles are truncated task names, and folder basenames repeat across checkouts. The workspace label narrows it to a project, and the tab name separates several agents *within* that workspace, where cwd and workspace label are identical. |

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

On Windows — or just re-run `.\install.ps1` after editing the repo copy, which
deploys in the other direction:

```powershell
cd $HOME\dotfiles
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"

Copy-Item $env:APPDATA\herdr\config.toml       windows\AppData\Roaming\herdr\config.toml
Copy-Item $env:APPDATA\herdr\sessionize-paths  windows\AppData\Roaming\herdr\sessionize-paths
Copy-Item ~\.config\hunk\config.toml           windows\.config\hunk\config.toml
Copy-Item ~\.copilot\scripts\*Herdr*.ps1       windows\.copilot\scripts\
Copy-Item ~\.glzr\glazewm\config.yaml          windows\.glzr\glazewm\config.yaml
Copy-Item ~\.glzr\zebar\settings.json          windows\.glzr\zebar\settings.json
Copy-Item $wt\settings.json                    windows\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
Copy-Item $env:LOCALAPPDATA\nvim\* windows\.config\nvim\ -Recurse -Force -Exclude pack,plugin

git diff
```

`git status` is the safety net here: the runtime files that sit next to these
configs (`errors.log`, `state.json`, `*.backup`, `.marketplace/`, nvim's `pack/`
and `plugin/`) are all gitignored, so an over-broad copy cannot leak them into a
commit.
