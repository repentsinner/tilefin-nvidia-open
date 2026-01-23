#!/bin/bash

set -ouex pipefail

###############################################################################
# Hyprfin-DX Build Script
# Based on patterns from github.com/ashebanow/hyprblue
###############################################################################

# Customize OS name for GRUB boot menu
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Hyprfin-DX Nvidia Open"/' /usr/lib/os-release
if [ -f /etc/os-release ] && [ ! -L /etc/os-release ]; then
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Hyprfin-DX Nvidia Open"/' /etc/os-release
fi

###############################################################################
# Package Arrays
# Organized by function for easier maintenance
###############################################################################

# GNOME components to remove (not needed for Hyprland)
GNOME_REMOVE=(
    gnome-shell
    mutter
    gdm
    gnome-initial-setup
    gnome-shell-extension-gsconnect
    gnome-shell-extension-common
    gnome-shell-extension-window-list
    nautilus-gsconnect
    gnome-session-wayland-session
    gnome-classic-session
    gnome-browser-connector
    gnome-shell-extension-supergfxctl-gex
    gnome-shell-extension-apps-menu
    gnome-shell-extension-places-menu
    gnome-shell-extension-launch-new-instance
)

# Hyprland compositor and core tools
HYPR_CORE=(
    hyprland
    hyprlock
    hypridle
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
)

# Wayland utilities and tools
WAYLAND_UTILS=(
    waybar
    fuzzel
    wlogout
    grim
    slurp
    wl-clipboard
    cliphist
    swww
    wdisplays
    wf-recorder
    mako
)

# Desktop environment components
DESKTOP_APPS=(
    ptyxis
    thunar
    lxpolkit
    rofimoji
    nwg-bar
)

# System utilities
SYSTEM_UTILS=(
    pamixer
    brightnessctl
    greetd
    greetd-tuigreet
    nvidia-container-toolkit
    adw-gtk3-theme
)

# Niri compositor (scrollable tiling alternative to Hyprland)
NIRI_PKGS=(
    niri
    swaylock              # niri uses swaylock for screen locking
    swayidle              # idle daemon for niri (like hypridle for hyprland)
)

# Additional applications
ADDITIONAL_APPS=(
    antigravity
)

# COPR repositories to enable
COPR_REPOS=(
    solopasha/hyprland
)

# Additional RPM repositories (name::url format)
RPM_REPOS=(
    "antigravity-rpm::https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm"
)

# Flatpaks to install (avoid extra-data apps like Slack - they fail in container builds)
FLATPAKS=(
    com.bitwarden.desktop
    dev.deedles.Trayscale
)

###############################################################################
# Enable System Services
###############################################################################

systemctl enable podman.socket
systemctl enable tailscaled.service

###############################################################################
# Remove GNOME Components
###############################################################################

echo "Removing GNOME components..."
rpm-ostree override remove "${GNOME_REMOVE[@]}"

###############################################################################
# Configure Repositories
###############################################################################

# Enable COPR repositories (error-tolerant for cross-version compatibility)
echo "Enabling COPR repositories..."
for repo in "${COPR_REPOS[@]}"; do
    echo "  Enabling COPR: $repo"
    dnf5 -y copr enable "$repo" || echo "  Warning: Failed to enable $repo (may not support this Fedora version)"
done

# Add additional RPM repositories
echo "Adding RPM repositories..."
for repo_entry in "${RPM_REPOS[@]}"; do
    repo_name="${repo_entry%%::*}"
    repo_url="${repo_entry##*::}"
    echo "  Adding repo: $repo_name"
    tee "/etc/yum.repos.d/${repo_name}.repo" << EOL
[${repo_name}]
name=${repo_name}
baseurl=${repo_url}
enabled=1
gpgcheck=0
EOL
done

###############################################################################
# Install Packages
# Single dnf5 install to minimize image layers
###############################################################################

# Combine all package arrays
ALL_PACKAGES=(
    "${HYPR_CORE[@]}"
    "${NIRI_PKGS[@]}"
    "${WAYLAND_UTILS[@]}"
    "${DESKTOP_APPS[@]}"
    "${SYSTEM_UTILS[@]}"
    "${ADDITIONAL_APPS[@]}"
)

echo "Installing ${#ALL_PACKAGES[@]} packages..."
dnf5 install -y --setopt=install_weak_deps=False "${ALL_PACKAGES[@]}"

###############################################################################
# Cleanup Repositories
# Remove repos so they don't stay enabled in the final image
###############################################################################

echo "Cleaning up repositories..."
for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr disable "$repo" || true
done

for repo_entry in "${RPM_REPOS[@]}"; do
    repo_name="${repo_entry%%::*}"
    rm -f "/etc/yum.repos.d/${repo_name}.repo"
done

###############################################################################
# Install Flatpaks
###############################################################################

echo "Installing Flatpaks..."
flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo

if [ ${#FLATPAKS[@]} -gt 0 ]; then
    flatpak install --system --noninteractive flathub "${FLATPAKS[@]}"
fi

# Note: Flatpaks with "extra-data" (like Slack) can't be installed during container builds
# due to sandbox/namespace restrictions. Install those manually after boot:
#   flatpak install flathub com.slack.Slack

###############################################################################
# Install Additional Tools
###############################################################################

# Bitwarden Secrets CLI
echo "Installing Bitwarden Secrets CLI..."
curl -Lo /tmp/bws.zip "https://github.com/bitwarden/sdk/releases/download/bws-v1.0.0/bws-x86_64-unknown-linux-gnu-1.0.0.zip"
unzip /tmp/bws.zip -d /tmp
install -Dm755 /tmp/bws /usr/bin/bws
rm -rf /tmp/bws.zip /tmp/bws

###############################################################################
# Configure Display Manager (greetd)
###############################################################################

mkdir -p /etc/greetd
cp /ctx/greetd-config.toml /etc/greetd/config.toml

# Create greeter system user using sysusers.d (works with OSTree)
mkdir -p /usr/lib/sysusers.d
cp /ctx/greeter.conf /usr/lib/sysusers.d/greeter.conf

# Create cache directory for tuigreet using tmpfiles.d (works with OSTree)
mkdir -p /usr/lib/tmpfiles.d
cp /ctx/greeter-cache.conf /usr/lib/tmpfiles.d/greeter-cache.conf

# Create Wayland session directory if needed
mkdir -p /usr/share/wayland-sessions

# Ensure hyprland.desktop exists for session selection
if [ ! -f /usr/share/wayland-sessions/hyprland.desktop ]; then
    cat > /usr/share/wayland-sessions/hyprland.desktop <<EOF
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
fi

systemctl enable greetd.service

###############################################################################
# Configure Wayland Environment
###############################################################################

# Configure Electron apps to use native Wayland rendering for proper fractional scaling
mkdir -p /etc/environment.d
cp /ctx/electron-wayland.conf /etc/environment.d/electron-wayland.conf

# Configure all Flatpak apps to use Wayland for proper fractional scaling
mkdir -p /etc/skel/.local/share/flatpak/overrides
cat > /etc/skel/.local/share/flatpak/overrides/global <<EOF
[Context]
sockets=wayland;

[Environment]
ELECTRON_ENABLE_WAYLAND=1
ELECTRON_OZONE_PLATFORM_HINT=wayland
EOF

# Configure trayscale to access tailscale socket
cat > /etc/skel/.local/share/flatpak/overrides/dev.deedles.Trayscale <<EOF
[Context]
filesystems=/run/tailscale:rw;
EOF

###############################################################################
# Configure Hyprland
###############################################################################

# System-wide settings
mkdir -p /etc/hypr
cp /ctx/hyprland.conf /etc/hypr/hyprland.conf

# Pre-populate Hyprland config for new users
mkdir -p /etc/skel/.config/hypr
cp /ctx/hyprland.conf /etc/skel/.config/hypr/hyprland.conf
cp /ctx/hyprlock.conf /etc/skel/.config/hypr/hyprlock.conf
cp /ctx/hypridle.conf /etc/skel/.config/hypr/hypridle.conf

# Configure waybar
mkdir -p /etc/skel/.config/waybar
mkdir -p /etc/skel/.config/waybar/scripts
cp /ctx/waybar-config.json /etc/skel/.config/waybar/config
cp /ctx/waybar-style.css /etc/skel/.config/waybar/style.css
cp /ctx/update-check.sh /etc/skel/.config/waybar/scripts/update-check.sh
chmod +x /etc/skel/.config/waybar/scripts/update-check.sh

# Configure mako (minimal notifications)
mkdir -p /etc/skel/.config/mako
cp /ctx/mako.conf /etc/skel/.config/mako/config

###############################################################################
# Configure Niri
###############################################################################

# System-wide settings
mkdir -p /etc/niri
cp /ctx/niri-config.kdl /etc/niri/config.kdl

# Pre-populate Niri config for new users
mkdir -p /etc/skel/.config/niri
cp /ctx/niri-config.kdl /etc/skel/.config/niri/config.kdl

###############################################################################
# Configure GTK Theming
###############################################################################

mkdir -p /etc/skel/.config/gtk-3.0
mkdir -p /etc/skel/.config/gtk-4.0

# GTK 3 settings
cat > /etc/skel/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
EOF

# GTK 4 settings
cat > /etc/skel/.config/gtk-4.0/settings.ini <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
EOF

# GTK 2 settings (legacy apps)
cat > /etc/skel/.gtkrc-2.0 <<EOF
gtk-theme-name="adw-gtk3-dark"
gtk-icon-theme-name="Adwaita"
gtk-cursor-theme-name="Adwaita"
gtk-font-name="Cantarell 11"
EOF

echo "Build complete!"
