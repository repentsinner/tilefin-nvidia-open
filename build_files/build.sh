#!/bin/bash

set -ouex pipefail

###############################################################################
# Tiled Bluefin-DX Build Script
# Based on patterns from github.com/ashebanow/hyprblue
###############################################################################

# Customize OS name for GRUB boot menu
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Tilefin-DX Nvidia Open"/' /usr/lib/os-release
if [ -f /etc/os-release ] && [ ! -L /etc/os-release ]; then
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Tilefin-DX Nvidia Open"/' /etc/os-release
fi

###############################################################################
# Package Arrays
###############################################################################

# GNOME components to remove (replaced by tiling compositors)
GNOME_REMOVE=(
    gnome-shell
    mutter
    gdm
    gnome-initial-setup
    gnome-shell-extension-gsconnect
    gnome-shell-extension-common
    gnome-shell-extension-window-list
    nautilus
    nautilus-gsconnect
    gnome-session-wayland-session
    gnome-classic-session
    gnome-browser-connector
    gnome-shell-extension-supergfxctl-gex
    gnome-shell-extension-apps-menu
    gnome-shell-extension-places-menu
    gnome-shell-extension-launch-new-instance
)

#------------------------------------------------------------------------------
# Compositors
#------------------------------------------------------------------------------

COMPOSITOR_HYPRLAND=(
    hyprland
    xdg-desktop-portal-hyprland
)

COMPOSITOR_NIRI=(
    niri
)

#------------------------------------------------------------------------------
# Shared Wayland Environment
#------------------------------------------------------------------------------

WAYLAND_CORE=(
    xdg-desktop-portal-gtk
    waybar
    fuzzel
    wlogout
    hyprlock                  # Lock screen
    hypridle                  # Idle daemon
    mako                      # Notifications
    swww                      # Wallpaper
)

WAYLAND_CLIPBOARD=(
    wl-clipboard
    wl-clip-persist           # Prevents clipboard clearing when source app closes
    cliphist
)

WAYLAND_SCREENSHOT=(
    grim
    slurp
    wf-recorder
)

#------------------------------------------------------------------------------
# Desktop Applications
#------------------------------------------------------------------------------

DESKTOP_APPS=(
    ptyxis                    # Terminal
    thunar                    # File manager
    gvfs                      # Virtual filesystem (network, MTP, trash)
    tumbler                   # Thumbnail service
    mpv                       # Media player
)

DESKTOP_UTILITIES=(
    lxpolkit                  # Polkit agent
    rofimoji                  # Emoji picker
    nwg-bar                   # Power menu
    network-manager-applet    # Network tray icon
    wdisplays                 # Display configuration
)

#------------------------------------------------------------------------------
# System
#------------------------------------------------------------------------------

SYSTEM_UTILS=(
    pamixer
    brightnessctl
    greetd
    greetd-tuigreet
    nvidia-container-toolkit
)

SYSTEM_THEMING=(
    adw-gtk3-theme
)

FONTS=(
    fira-code-fonts
    fontawesome-fonts-all
    google-noto-emoji-fonts
)

#------------------------------------------------------------------------------
# Additional Applications
#------------------------------------------------------------------------------

ADDITIONAL_APPS=(
    antigravity
)

#------------------------------------------------------------------------------
# Repositories
#------------------------------------------------------------------------------

COPR_REPOS=(
    solopasha/hyprland
    leloubil/wl-clip-persist
)

RPM_REPOS=(
    "antigravity-rpm::https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm"
)

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

echo "Enabling COPR repositories..."
for repo in "${COPR_REPOS[@]}"; do
    echo "  Enabling COPR: $repo"
    dnf5 -y copr enable "$repo" || echo "  Warning: Failed to enable $repo (may not support this Fedora version)"
done

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
###############################################################################

ALL_PACKAGES=(
    # Compositors
    "${COMPOSITOR_HYPRLAND[@]}"
    "${COMPOSITOR_NIRI[@]}"
    # Wayland environment
    "${WAYLAND_CORE[@]}"
    "${WAYLAND_CLIPBOARD[@]}"
    "${WAYLAND_SCREENSHOT[@]}"
    # Desktop
    "${DESKTOP_APPS[@]}"
    "${DESKTOP_UTILITIES[@]}"
    # System
    "${SYSTEM_UTILS[@]}"
    "${SYSTEM_THEMING[@]}"
    "${FONTS[@]}"
    # Additional
    "${ADDITIONAL_APPS[@]}"
)

echo "Installing ${#ALL_PACKAGES[@]} packages..."
dnf5 install -y --setopt=install_weak_deps=False "${ALL_PACKAGES[@]}"

###############################################################################
# Cleanup Repositories
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

# Electron apps: use native Wayland for proper fractional scaling
mkdir -p /etc/environment.d
cp /ctx/electron-wayland.conf /etc/environment.d/electron-wayland.conf

# Flatpak apps: use Wayland for proper fractional scaling
mkdir -p /etc/skel/.local/share/flatpak/overrides
cat > /etc/skel/.local/share/flatpak/overrides/global <<EOF
[Context]
sockets=wayland;

[Environment]
ELECTRON_ENABLE_WAYLAND=1
ELECTRON_OZONE_PLATFORM_HINT=wayland
EOF

# Trayscale: access tailscale socket
cat > /etc/skel/.local/share/flatpak/overrides/dev.deedles.Trayscale <<EOF
[Context]
filesystems=/run/tailscale:rw;
EOF

###############################################################################
# Configure Shared Components
# (Used by both Hyprland and Niri)
###############################################################################

# hyprlock + hypridle (lock screen and idle management)
mkdir -p /etc/skel/.config/hypr
cp /ctx/hyprlock.conf /etc/skel/.config/hypr/hyprlock.conf
cp /ctx/hypridle.conf /etc/skel/.config/hypr/hypridle.conf
cp /ctx/hypridle-niri.conf /etc/skel/.config/hypr/hypridle-niri.conf
cp /ctx/hypridle-launch.sh /etc/skel/.config/hypr/hypridle-launch.sh
chmod +x /etc/skel/.config/hypr/hypridle-launch.sh

# waybar (status bar)
mkdir -p /etc/skel/.config/waybar/scripts
cp /ctx/waybar-config-niri.json /etc/skel/.config/waybar/config-niri
cp /ctx/waybar-config.json /etc/skel/.config/waybar/config-hyprland
cp /ctx/waybar-style.css /etc/skel/.config/waybar/style.css
cp /ctx/waybar-launch.sh /etc/skel/.config/waybar/launch.sh
chmod +x /etc/skel/.config/waybar/launch.sh
cp /ctx/update-check.sh /etc/skel/.config/waybar/scripts/update-check.sh
chmod +x /etc/skel/.config/waybar/scripts/update-check.sh

# mako (notifications)
mkdir -p /etc/skel/.config/mako
cp /ctx/mako.conf /etc/skel/.config/mako/config

# nwg-bar (power menu)
mkdir -p /etc/skel/.config/nwg-bar
cp /ctx/nwg-bar.json /etc/skel/.config/nwg-bar/bar.json

# compositor-exit (logout script for both Hyprland and Niri)
install -Dm755 /ctx/compositor-exit.sh /usr/bin/compositor-exit

# XDG desktop portal (use GTK backend instead of GNOME)
mkdir -p /etc/skel/.config/xdg-desktop-portal
cp /ctx/portals.conf /etc/skel/.config/xdg-desktop-portal/portals.conf

###############################################################################
# Configure Hyprland
###############################################################################

mkdir -p /etc/xdg/hypr
cp /ctx/hyprland.conf /etc/xdg/hypr/hyprland.conf
cp /ctx/hyprland.conf /etc/skel/.config/hypr/hyprland.conf

# Session wrapper (sets SSH_AUTH_SOCK before starting Hyprland)
install -Dm755 /ctx/hyprland-session.sh /usr/bin/hyprland-tilefin-session
cp /ctx/hyprland-tilefin.desktop /usr/share/wayland-sessions/hyprland-tilefin.desktop

###############################################################################
# Configure Niri
###############################################################################

mkdir -p /etc/niri
cp /ctx/niri-config.kdl /etc/niri/config.kdl

mkdir -p /etc/skel/.config/niri
cp /ctx/niri-config.kdl /etc/skel/.config/niri/config.kdl

# Session wrapper (sets SSH_AUTH_SOCK before starting niri)
install -Dm755 /ctx/niri-session.sh /usr/bin/niri-tilefin-session
cp /ctx/niri-tilefin.desktop /usr/share/wayland-sessions/niri-tilefin.desktop

###############################################################################
# Configure GTK Theming
###############################################################################

mkdir -p /etc/skel/.config/gtk-3.0
mkdir -p /etc/skel/.config/gtk-4.0

cat > /etc/skel/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
EOF

cat > /etc/skel/.config/gtk-4.0/settings.ini <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
EOF

cat > /etc/skel/.gtkrc-2.0 <<EOF
gtk-theme-name="adw-gtk3-dark"
gtk-icon-theme-name="Adwaita"
gtk-cursor-theme-name="Adwaita"
gtk-font-name="Cantarell 11"
EOF

echo "Build complete!"
