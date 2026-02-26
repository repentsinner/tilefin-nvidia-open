#!/bin/bash

set -ouex pipefail

###############################################################################
# Tilefin-DX Build Script
# Niri compositor on Universal Blue base-nvidia
###############################################################################

# Customize OS name for GRUB boot menu
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Tilefin-DX Nvidia Open"/' /usr/lib/os-release
if [ -f /etc/os-release ] && [ ! -L /etc/os-release ]; then
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Tilefin-DX Nvidia Open"/' /etc/os-release
fi

###############################################################################
# Package Arrays
###############################################################################

#------------------------------------------------------------------------------
# Compositor
#------------------------------------------------------------------------------

COMPOSITOR=(
    niri
)

#------------------------------------------------------------------------------
# Shared Wayland Environment
#------------------------------------------------------------------------------

WAYLAND_CORE=(
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
    fish                      # Shell
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
# Virtualization (Windows VM + Looking Glass support)
#------------------------------------------------------------------------------

VIRTUALIZATION=(
    libvirt
    libvirt-daemon-kvm
    qemu-kvm
    virt-manager
    virt-install
    edk2-ovmf                 # UEFI firmware for VMs
    swtpm                     # TPM emulation (Windows 11 requirement)
    swtpm-tools
    looking-glass-client      # Low-latency framebuffer for GPU passthrough (from COPR)
    virtiofsd                 # Fast file sharing with VMs
)

#------------------------------------------------------------------------------
# Repositories
#------------------------------------------------------------------------------

COPR_REPOS=(
    solopasha/hyprland              # hyprlock, hypridle, swww, cliphist (used with Niri too)
    leloubil/wl-clip-persist
    pgaskin/looking-glass-client
)

FLATPAKS=(
    com.bitwarden.desktop
)

###############################################################################
# Enable System Services (base image)
###############################################################################

systemctl enable podman.socket
systemctl enable rpm-ostreed-automatic.timer  # Auto-stage image upgrades

###############################################################################
# Configure Repositories
###############################################################################

echo "Enabling COPR repositories..."
for repo in "${COPR_REPOS[@]}"; do
    echo "  Enabling COPR: $repo"
    dnf5 -y copr enable "$repo" || echo "  Warning: Failed to enable $repo (may not support this Fedora version)"
done

###############################################################################
# Install Packages
###############################################################################

ALL_PACKAGES=(
    # Compositor
    "${COMPOSITOR[@]}"
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
    # Virtualization
    "${VIRTUALIZATION[@]}"
)

echo "Installing ${#ALL_PACKAGES[@]} packages..."
dnf5 install -y --setopt=install_weak_deps=False "${ALL_PACKAGES[@]}"

###############################################################################
# Enable System Services (installed packages)
###############################################################################

systemctl enable libvirtd.socket          # VM management (socket-activated)

###############################################################################
# Cleanup Repositories
###############################################################################

echo "Cleaning up repositories..."
for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr disable "$repo" || true
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

# VS Code: install from Microsoft repo (not in base image)
echo "Installing VS Code..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf5 config-manager addrepo --from-repofile=https://packages.microsoft.com/yumrepos/vscode/config.repo
dnf5 install -y code

# niri-desaturate (fork with desaturate window rule support)
# Replaces the COPR niri package until upstream merges the PR
# https://github.com/repentsinner/niri-desaturate
echo "Installing niri-desaturate..."
curl -Lo /tmp/niri-desaturate.rpm "https://github.com/repentsinner/niri-desaturate/releases/download/v25.11.0.1/niri-25.11.0.1-1.x86_64.rpm"
dnf5 install -y --allowerasing /tmp/niri-desaturate.rpm
rm -f /tmp/niri-desaturate.rpm

###############################################################################
# Configure Display Manager (greetd)
# Note: greetd package provides /usr/lib/sysusers.d/greetd.conf (creates greetd user)
# but its tmpfiles.d only sets ownership, doesn't create /var/lib/greetd
###############################################################################

mkdir -p /etc/greetd
cp /ctx/greetd-config.toml /etc/greetd/config.toml

# Create greetd home directory (package tmpfiles.d doesn't do this)
mkdir -p /usr/lib/tmpfiles.d
cp /ctx/greeter-cache.conf /usr/lib/tmpfiles.d/greetd-home.conf

# Create Wayland session directory if needed
mkdir -p /usr/share/wayland-sessions

systemctl enable greetd.service

###############################################################################
# Configure Wayland Environment
###############################################################################

# Electron apps: use native Wayland for proper fractional scaling
mkdir -p /etc/environment.d
cp /ctx/electron-wayland.conf /etc/environment.d/electron-wayland.conf

# Flatpak overrides: system-wide (apply to all users automatically)
mkdir -p /var/lib/flatpak/overrides
cat > /var/lib/flatpak/overrides/global <<EOF
[Context]
sockets=wayland;

[Environment]
ELECTRON_ENABLE_WAYLAND=1
ELECTRON_OZONE_PLATFORM_HINT=wayland
EOF

###############################################################################
# Configure CLI Tools
###############################################################################

# CLI aliases and shell hooks (tools resolved at runtime from $PATH)
cp /ctx/cli-aliases.sh /etc/profile.d/cli-aliases.sh

# Default userbox distrobox declaration (bootstrap for new accounts)
mkdir -p /etc/skel/.config/distrobox
cp /ctx/userbox.ini /etc/skel/.config/distrobox/userbox.ini

###############################################################################
# Configure Wayland Components
###############################################################################

# hyprlock + hypridle (lock screen and idle management)
# System-wide via XDG fallback (/etc/xdg/hypr/) — hyprutils findConfig() checks this path
# Users can override in ~/.config/hypr/
mkdir -p /etc/xdg/hypr
cp /ctx/hyprlock.conf /etc/xdg/hypr/hyprlock.conf
cp /ctx/hypridle-niri.conf /etc/xdg/hypr/hypridle.conf

# waybar (status bar)
# System-wide config via XDG fallback (/etc/xdg/waybar/)
# Users can override by creating ~/.config/waybar/config
mkdir -p /etc/xdg/waybar
cp /ctx/waybar-config-niri.json /etc/xdg/waybar/config
cp /ctx/waybar-style.css /etc/xdg/waybar/style.css
install -Dm755 /ctx/update-check.sh /usr/share/tilefin/scripts/update-check.sh
install -Dm755 /ctx/notification-indicator.sh /usr/share/tilefin/scripts/notification-indicator.sh

# mako (notifications) — no system path support, must use skel
mkdir -p /etc/skel/.config/mako
cp /ctx/mako.conf /etc/skel/.config/mako/config

# nwg-bar (power menu) — no system path support, must use skel
mkdir -p /etc/skel/.config/nwg-bar
cp /ctx/nwg-bar.json /etc/skel/.config/nwg-bar/bar.json

# compositor-exit (logout script)
install -Dm755 /ctx/compositor-exit.sh /usr/bin/compositor-exit

# XDG desktop portal (use GTK backend instead of GNOME)
# System-wide via XDG_CONFIG_DIRS fallback
mkdir -p /etc/xdg/xdg-desktop-portal
cp /ctx/portals.conf /etc/xdg/xdg-desktop-portal/portals.conf

###############################################################################
# Configure Niri
###############################################################################

# Niri config: system-wide via /etc/niri/ fallback
# Users can override by creating ~/.config/niri/config.kdl
mkdir -p /etc/niri
cp /ctx/niri-config.kdl /etc/niri/config.kdl

# Session wrapper (sets SSH_AUTH_SOCK before starting niri)
install -Dm755 /ctx/niri-session.sh /usr/bin/niri-tilefin-session
cp /ctx/niri-tilefin.desktop /usr/share/wayland-sessions/niri-tilefin.desktop

# Remove stock niri session file (we use our Tilefin version)
rm -f /usr/share/wayland-sessions/niri.desktop

###############################################################################
# Configure GTK Theming
###############################################################################

# GTK 3/4: system-wide defaults (users can override in ~/.config/gtk-*/settings.ini)
mkdir -p /etc/gtk-3.0
mkdir -p /etc/gtk-4.0

cat > /etc/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
EOF

cat > /etc/gtk-4.0/settings.ini <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-application-prefer-dark-theme=true
EOF

# GTK 2: no system path, must use skel
cat > /etc/skel/.gtkrc-2.0 <<EOF
gtk-theme-name="adw-gtk3-dark"
gtk-icon-theme-name="Adwaita"
gtk-cursor-theme-name="Adwaita"
gtk-font-name="Cantarell 11"
EOF

###############################################################################
# Configure Virtualization
###############################################################################

# Allow wheel group to manage VMs without additional group membership
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-libvirt.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF

# Enable IOMMU for GPU passthrough (harmless on single-GPU systems)
# This sets kernel args that will be applied on next boot after image switch
mkdir -p /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/10-iommu.toml <<'EOF'
# Enable IOMMU for VFIO GPU passthrough
# These are safe on systems without passthrough - just enables the capability
kargs = ["intel_iommu=on", "amd_iommu=on", "iommu=pt"]
EOF

# Enable verbose boot (show kernel and systemd messages instead of splash)
# Note: bootc kargs.d only supports adding args, not deleting.
# To remove 'quiet' and 'rhgb' from base image, run after first boot:
#   rpm-ostree kargs --delete=quiet --delete=rhgb
cat > /usr/lib/bootc/kargs.d/20-verbose-boot.toml <<'EOF'
# Show systemd service status during boot
kargs = ["systemd.show_status=1"]
EOF

###############################################################################
# Install Custom Justfile (ujust recipes)
###############################################################################

echo "Installing custom ujust recipes..."
cp /ctx/tilefin.just /usr/share/ublue-os/just/60-tilefin.just

echo "Build complete!"
