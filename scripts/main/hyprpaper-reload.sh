#!/usr/bin/env bash

WALLPAPER_DIR="/mnt/photos/Export/Portfolio"
CURRENT_WALL=$(hyprctl hyprpaper listloaded)

# Get a random wallpaper that is not the current one
WALLPAPER=$(find "$WALLPAPER_DIR" -type f ! -name "$(basename "$CURRENT_WALL")" | shuf -n 1)

# Apply the selected wallpaper
hyprctl hyprpaper reload $WALLPAPER

sleep 1

hyprctl hyprpaper unload unused
