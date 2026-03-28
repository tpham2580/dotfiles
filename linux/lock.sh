#!/bin/sh
set -e

if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    swaylock -f -c 000000
else
    i3lock -i ~/Pictures/turtle.png --tiling -u -c 000000
    xset dpms
fi
