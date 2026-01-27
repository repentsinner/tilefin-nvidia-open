#!/bin/bash
# Hyprland session wrapper
# Sets up environment before starting Hyprland

# Bitwarden SSH agent socket
export SSH_AUTH_SOCK="$HOME/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock"

# Propagate to systemd and dbus for services
systemctl --user set-environment SSH_AUTH_SOCK="$SSH_AUTH_SOCK"
dbus-update-activation-environment SSH_AUTH_SOCK

# Hyprland only looks in ~/.config/hypr/, not /etc/xdg/hypr/
# Use system config as fallback if user config doesn't exist
if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
    exec Hyprland
elif [[ -f /etc/xdg/hypr/hyprland.conf ]]; then
    exec Hyprland -c /etc/xdg/hypr/hyprland.conf
else
    exec Hyprland
fi
