#!/bin/bash
# Compositor-agnostic exit/logout script
# Works with both Hyprland and Niri

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    hyprctl dispatch exit
elif [ -n "$NIRI_SOCKET" ]; then
    niri msg action quit
else
    loginctl terminate-session self
fi
