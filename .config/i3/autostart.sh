#!/bin/bash

# Set wallpaper using feh
feh --bg-scale ~/Pictures/hammer.jpg

# Assign workspaces to monitors
i3-msg "workspace 5; move workspace to output DP-2"
i3-msg "workspace 10; move workspace to output DP-0"
i3-msg "workspace 20; move workspace to output DP-4"

# Switch to the desired workspaces
i3-msg "workspace 5"
i3-msg "workspace 10"
i3-msg "workspace 20"
