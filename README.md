# 🛠️ Dotfiles for Workspace Config 🖥️

Welcome to my **workspace configuration dotfiles** repository! 🎉 These files contain my personal setup to create a clean, productive, and visually pleasing development environment. 🚀

## 📁 What's Included?

### **Neovim (nvim)** ✍️
- Configuration file: `~/.config/nvim/init.vim`
- Plugins, key mappings, and theme setup for an enhanced coding experience. 🎨
- Includes **LSP** settings, **treesitter**, and **telescope** for modern Neovim workflows.

### **i3 Window Manager** 🪟
- Configuration file: `~/.config/i3/config`
- Default i3 installations: ```i3 i3status dmenu i3lock xbacklight feh conky xss-lock picom network-manager-applet light maim xclip dunst polkit-gnome polybar rofi```
    - xss-lock - Handles lock and idle stuff
    - picom - Compositor for window transparencies and stuff
        - Configuration file: `~/.config/picom/picom.conf`
    - network-manager-applet - Tray tool for network stuff
    - light - Display brightness controls
    - maim - screenshot utility
    - xclip - clipboard stuff
    - dunst - Notifications
    - polkit-gnome - Hook up for authentication/elevation stuff
    - polybar - A configurable status bar
        - Configuration file: `~/.config/polybar/config`
    - rofi - A sweet sweet launcher (alternative to dmenu)
        - Configuration file: `~/.config/rofi/config.rasi`

- REMEMBER: If the flathub apps do not show up in dmenu, a shell script needs to be created in /usr/local/bin folder
```
#!/bin/bash
flatpak run {flatpak for application here}
```

### **.zshrc** 💻
- Contains keybinding for tmux-sessionizer
- Check ssh agent on after first time use to prevent password reenter for ssh each time

### **Scripts** 🤖
- tmux-sessionizer
    - REQUIRES: fzf (fuzzy finder) and tmux
    - Fuzzy find specified directories and creates a new tmux session with it's name

---

## 📦 How to Use
1. Clone this repository
2. Copy files in the appropriate system config locations
