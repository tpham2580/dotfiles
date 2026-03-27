# 🛠️ Dotfiles for Workspace Config 🖥️

Welcome to my **workspace configuration dotfiles** repository! 🎉 These files contain my personal setup to create a clean, productive, and visually pleasing development environment. 🚀

## 📁 Structure

```
dotfiles/
├── linux/                      # Linux-only configs
│   ├── .config/
│   │   ├── i3/                 # i3 window manager
│   │   ├── nvim/               # Neovim (Linux)
│   │   ├── picom/              # Compositor
│   │   ├── polybar/            # Status bar
│   │   ├── rofi/               # App launcher
│   │   └── tmux/               # Terminal multiplexer
│   ├── .local/scripts/         # Custom scripts
│   ├── .zshrc                  # Zsh config
│   └── lock.sh                 # Lock screen script
├── windows/                    # Windows-only configs
│   ├── .config/nvim/           # Neovim (Windows)
│   └── .glzr/glazewm/         # GlazeWM tiling WM
└── README.md
```

---

## 🪟 Windows

### **GlazeWM**

- Configuration file: `windows/.glzr/glazewm/config.yaml`
- Deploy path: `~/.glzr/glazewm/config.yaml`
- Windows tiling window manager (i3-like for Windows)
- Uses `lwin` (Windows key) as the primary modifier
- Requires `DisabledHotkeys` registry entry for `Win+Number` workspace switching:
  ```powershell
  Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisabledHotkeys" -Value "0123456789" -Type String
  ```
- Status bar: [Zebar](https://github.com/glzr-io/zebar)

### **Neovim (nvim)**

- Configuration file: `windows/.config/nvim/init.lua`
- Deploy path: `~/AppData/Local/nvim/init.lua`
- Base configuration file came from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- Current Theme: [Kanagawa](https://github.com/rebelot/kanagawa.nvim) (kanagawa-dragon)

---

## 🐧 Linux

### **i3 Window Manager**

- Configuration file: `linux/.config/i3/config`
- Deploy path: `~/.config/i3/config`
- Current Theme: [Catppuccin](https://github.com/catppuccin/catppuccin)
- Default i3 installations: ```i3 i3status dmenu i3lock xbacklight feh conky xss-lock picom network-manager-applet light maim xclip dunst polkit-gnome polybar rofi```
    - xss-lock - Handles lock and idle stuff
    - picom - Compositor for window transparencies and stuff
        - Configuration file: `linux/.config/picom/picom.conf`
    - network-manager-applet - Tray tool for network stuff
    - light - Display brightness controls
    - maim - screenshot utility
    - xclip - clipboard stuff
    - dunst - Notifications
    - polkit-gnome - Hook up for authentication/elevation stuff
    - polybar - A configurable status bar
        - Configuration file: `linux/.config/polybar/config`
    - rofi - A sweet sweet launcher (alternative to dmenu)
        - Configuration file: `linux/.config/rofi/config.rasi`

- REMEMBER: If the flathub apps do not show up in dmenu, a shell script needs to be created in /usr/local/bin folder
```
#!/bin/bash
flatpak run {flatpak for application here}
```
- You can also run this command to create a file with symlink
```
sudo ln -s /opt/extract-folder/bin/start.sh /usr/local/bin/appname
```

### **.zshrc**

- Configuration file: `linux/.zshrc`
- Contains keybinding for tmux-sessionizer
- Check ssh agent on after first time use to prevent password reenter for ssh each time
- Contains keybinding for [aichat](https://github.com/sigoden/aichat) using Deepseek API

### **Scripts**
- tmux-sessionizer (`linux/.local/scripts/tmux-sessionizer`)
    - REQUIRES: fzf (fuzzy finder) and tmux
    - Fuzzy find specified directories and creates a new tmux session with it's name

### **Neovim (nvim)**

- Configuration file: `linux/.config/nvim/init.lua`
- Deploy path: `~/.config/nvim/init.lua`
- Base configuration file came from [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- Current Theme: [Catppuccin](https://github.com/catppuccin/catppuccin) (catppuccin-mocha)

---

## 📦 How to Use
1. Clone this repository
2. Copy or symlink files from the appropriate OS folder to their deploy paths
