# 🛠️ Dotfiles for Workspace Config 🖥️

Welcome to my **workspace configuration dotfiles** repository! 🎉 These files contain my personal setup to create a clean, productive, and visually pleasing development environment. 🚀

## 📁 What's Included?

### 1️⃣ **Neovim (nvim)** ✍️
- Configuration file: `~/.config/nvim/init.vim`
- Plugins, key mappings, and theme setup for an enhanced coding experience. 🎨
- Includes **LSP** settings, **treesitter**, and **telescope** for modern Neovim workflows.

### 2️⃣ **i3 Window Manager** 🪟
- Configuration file: `~/.config/i3/config`
- Default i3 installations: ```i3 i3status dmenu i3lock xbacklight feh conky xss-lock picom network-manager-applet light maim xclip dunst polkit-gnome polybar rofi```
    - xss-lock - Handles lock and idle stuff
    - picom - Compositor for window transparencies and stuff
    - network-manager-applet - Tray tool for network stuff
    - light - Display brightness controls
    - maim - screenshot utility
    - xclip - clipboard stuff
    - dunst - Notifications
    - polkit-gnome - Hook up for authentication/elevation stuff
    - polybar - A configurable status bar
    - rofi - A sweet sweet launcher (alternative to dmenu)

- REMEMBER: If the flathub apps do not show up in dmenu, a shell script needs to be created in /usr/local/bin folder
```
#!/bin/bash
flatpak run {flatpak for application here}
```

### 3️⃣ **Picom** 🌫️
- Configuration file: `~/.config/picom/picom.conf`
- Provides subtle window transparency and smooth animations. ✨
- Tuned for performance and compatibility with i3.

### 4️⃣ **Polybar** 📊
- Configuration file: `~/.config/polybar/config`
- A sleek status bar showing workspaces, system stats, audio controls, and more. 🎛️
- Customized modules for audio, brightness, battery, network, and date/time.

### 5️⃣ **Rofi** 🎩
- Configuration file: `~/.config/rofi/config.rasi`
- A stylish application launcher and window switcher. 🚀
- Includes themes and bindings to match the overall workspace aesthetic.

---

## 🌟 Features
- Consistent theme across all tools (Neovim, i3, Polybar, Rofi, and Picom). 🎨
- Optimized for speed and minimal resource usage. ⚡
- Fully customizable and modular for different setups. 🛠️

---

## 📦 How to Use
1. Clone this repository
2. Copy files in the appropriate system config locations
