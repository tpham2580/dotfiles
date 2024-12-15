#!/bin/bash

# Set wallpaper using feh
feh --bg-scale ~/Pictures/mountains-minimalism-red-Moon-1912113-wallhere.com.png

# Assign workspaces to monitors
i3-msg "workspace 1; move workspace to output DP-0"
i3-msg "workspace 11; move workspace to output DP-4"

# Switch to the desired workspaces
i3-msg "workspace 1"
i3-msg "workspace 11"
