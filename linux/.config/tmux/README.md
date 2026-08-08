# tmux Configuration Setup

This guide provides steps to set up tmux with the Catppuccin theme and properly configure it for future use.

---

## **Setup Steps**

1. **Create the Plugin Directory**
   - To set up the Catppuccin theme for tmux, first create a plugin directory:
     ```bash
     mkdir -p ~/.config/tmux/plugins/catppuccin
     ```

2. **Clone the Catppuccin Plugin**
   - Clone the Catppuccin tmux repository into the plugin directory:
     ```bash
     git clone -b v2.1.2 https://github.com/catppuccin/tmux.git ~/.config/tmux/plugins/catppuccin/tmux
     ```

3. **Copy the `tmux.conf` File**
   - Ensure your `tmux.conf` file is located at `~/.config/tmux/tmux.conf`. If it isn’t already there, copy it using:
     ```bash
     cp tmux.conf ~/.config/tmux/tmux.conf
     ```

4. **Reload tmux Configuration**
   - Apply the changes to tmux by reloading the configuration:
     ```bash
     tmux source-file ~/.config/tmux/tmux.conf
     ```

---

## **What This Does**
- Sets up the **Catppuccin theme** for tmux, providing a visually appealing status bar and consistent styling.
- Ensures your tmux configuration is loaded correctly from `~/.config/tmux/tmux.conf`.

