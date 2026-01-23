#!/bin/bash
# Waybar launcher that picks the right config for the current compositor

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"

case "$XDG_CURRENT_DESKTOP" in
    niri)
        exec waybar -c "$CONFIG_DIR/config-niri"
        ;;
    Hyprland)
        exec waybar -c "$CONFIG_DIR/config-hyprland"
        ;;
    *)
        # Fallback: try to detect from running process
        if pgrep -x niri > /dev/null; then
            exec waybar -c "$CONFIG_DIR/config-niri"
        elif pgrep -x Hyprland > /dev/null; then
            exec waybar -c "$CONFIG_DIR/config-hyprland"
        else
            # Default to niri config
            exec waybar -c "$CONFIG_DIR/config-niri"
        fi
        ;;
esac
