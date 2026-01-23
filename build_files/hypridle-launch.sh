#!/bin/bash
# Hypridle launcher that picks the right config for the current compositor

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

case "$XDG_CURRENT_DESKTOP" in
    niri)
        exec hypridle -c "$CONFIG_DIR/hypridle-niri.conf"
        ;;
    Hyprland)
        exec hypridle -c "$CONFIG_DIR/hypridle.conf"
        ;;
    *)
        # Fallback: try to detect from running process
        if pgrep -x niri > /dev/null; then
            exec hypridle -c "$CONFIG_DIR/hypridle-niri.conf"
        else
            exec hypridle -c "$CONFIG_DIR/hypridle.conf"
        fi
        ;;
esac
