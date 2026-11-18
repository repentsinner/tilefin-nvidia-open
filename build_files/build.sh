#!/bin/bash

set -ouex pipefail

###############################################################################
# Tilefin Build Script
# Niri compositor on Universal Blue base-nvidia
###############################################################################

# Customize OS name for GRUB boot menu
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Tilefin Nvidia Open"/' /usr/lib/os-release
if [ -f /etc/os-release ] && [ ! -L /etc/os-release ]; then
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Tilefin Nvidia Open"/' /etc/os-release
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
    swaybg                    # Wallpaper (Fedora; swww is unpackaged)
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
    gum                       # TUI menus for ujust recipes
    gnome-keyring             # Secret Service (org.freedesktop.secrets) for gh/secret-tool (§spec:credential-storage)
    gnome-keyring-pam         # Activates the keyring auto-unlock lines already in /etc/pam.d/greetd
    xdg-user-dirs             # Creates ~/Downloads etc. so Flatpak xdg-* grants resolve (§spec:xdg-user-dirs)
    dbus-tools                # dbus-update-activation-environment, needed by the session wrapper (§spec:session-targets)
    linuxptp                  # ptp4l/phc2sys — PTP clock sync for ST2110 (§spec:ptp)
    libatomic                 # GCC runtime for vendored binaries (§spec:host-runtime-libs)
    docker-compose            # `podman compose` provider (§spec:compose-provider)
    pciutils                  # setpci for the P2P NIC read request size (§spec:p2p-pcie-read-request)
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
# Shell tooling
#------------------------------------------------------------------------------
# Binaries behind the aliases and hooks in tool-aliases.{sh,fish}
# (§spec:tool-aliases). The configuration ships in this image, so the binaries
# do too — see §spec:image-ships-shell-tools.

SHELL_TOOLS=(
    bat                       # cat replacement (aliased)
    eza                       # ls replacement (aliased)
    zoxide                    # cd replacement (shell hook)
    direnv                    # per-directory environment (shell hook)
    starship                  # prompt (shell hook, from COPR)
    rbw                       # Bitwarden vault client, called from .envrc
    pinentry                  # rbw password prompt; named because weak deps are off
)

#------------------------------------------------------------------------------
# Virtualization (VM hosting and GPU passthrough, §spec:virtualization)
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
    virtiofsd                 # Fast file sharing with VMs
)

# Libraries the Looking Glass client links directly. The Containerfile builds
# the client itself (§spec:looking-glass-client), so no package pulls these in.
LOOKING_GLASS_RUNTIME=(
    fontconfig
    gmp
    libdecor
    libglvnd-egl
    libglvnd-glx
    libsamplerate
    libwayland-client
    libwayland-cursor
    libwayland-egl
    libX11
    libXcursor
    libXfixes
    libXi
    libXinerama
    libXpresent
    libXScrnSaver
    libxkbcommon
    nettle
    pipewire-libs
    pulseaudio-libs
)

#------------------------------------------------------------------------------
# Repositories
#------------------------------------------------------------------------------

COPR_REPOS=(
    craftidore/wayblueorg-hyprland  # hyprlock, hypridle (used with Niri too)
    leloubil/wl-clip-persist
    atim/starship                   # starship is not packaged in Fedora proper
)

###############################################################################
# Enable System Services (base image)
###############################################################################

systemctl enable podman.socket
systemctl enable rpm-ostreed-automatic.timer  # Auto-stage image upgrades

# Production-mode update lock (§spec:production-mode): drop-in gates auto-staging on the
# presence of /etc/tilefin/production-mode. The drop-in ships read-only
# in /usr/lib/; the flag file is mutable per-machine in /etc/.
install -Dm644 /ctx/rpm-ostreed-automatic-production.conf \
    /usr/lib/systemd/system/rpm-ostreed-automatic.service.d/production.conf

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
    # Shell tooling
    "${SHELL_TOOLS[@]}"
    # Virtualization
    "${VIRTUALIZATION[@]}"
    "${LOOKING_GLASS_RUNTIME[@]}"
)

echo "Installing ${#ALL_PACKAGES[@]} packages..."
dnf5 install -y --setopt=install_weak_deps=False "${ALL_PACKAGES[@]}"

# VMware guest tooling ships in the base image but this is bare metal
# (systemd-detect-virt reports none). open-vm-tools-desktop drops
# /etc/xdg/autostart/vmware-user.desktop, which fails at every login with
# "could not open /proc/fs/vmblock/dev". Nothing else depends on it.
if rpm -q open-vm-tools >/dev/null 2>&1; then
    echo "Removing VMware guest tooling (bare metal host)..."
    dnf5 remove -y open-vm-tools open-vm-tools-desktop
fi

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
# Install Additional Tools
###############################################################################

# VS Code: install from Microsoft repo (not in base image)
echo "Installing VS Code..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf5 config-manager addrepo --from-repofile=https://packages.microsoft.com/yumrepos/vscode/config.repo
dnf5 install -y code

# Tailscale: install from Tailscale's yum repo (§spec:tailscale). Neither
# Fedora nor base-nvidia packages it. The repo baseurl is keyed on $basearch,
# not $releasever, so it survives Fedora release bumps.
echo "Installing Tailscale..."
rpm --import https://pkgs.tailscale.com/stable/fedora/repo.gpg
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 install -y tailscale

# tailscaled owns the tailscale0 interface, routes and DNS, so it belongs to
# the host rather than a container. Enabled here, not in the package-service
# block above, because the package is installed in this section.
systemctl enable tailscaled.service

# niri-desaturate (fork with desaturate window rule support)
# Replaces the COPR niri package until upstream merges the PR
# https://github.com/repentsinner/niri-desaturate
echo "Installing niri-desaturate..."
curl -Lo /tmp/niri-desaturate.rpm "https://github.com/repentsinner/niri-desaturate/releases/download/v26.04.0.1/niri-26.04.0.1-1.x86_64.rpm"
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

# The base image enables authselect's with-fingerprint, but fprintd-pam is
# not installed and this hardware has no reader. The generated stack then
# references a missing pam_fprintd.so and logs a dlopen error on every
# login. Drop the feature so the stack matches what is installed.
if authselect current 2>/dev/null | grep -q with-fingerprint; then
    echo "Disabling authselect with-fingerprint (no reader, no fprintd-pam)..."
    authselect disable-feature with-fingerprint
fi

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

# Tool aliases and shell hooks (resolved at runtime from $PATH)
cp /ctx/tool-aliases.sh /etc/profile.d/tool-aliases.sh
cp /ctx/local-path.sh /etc/profile.d/local-path.sh
mkdir -p /etc/fish/conf.d
cp /ctx/tool-aliases.fish /etc/fish/conf.d/tool-aliases.fish
cp /ctx/local-path.fish /etc/fish/conf.d/local-path.fish

# Silence kbd unicode_start on the tty1 login shell (see the file's comment)
mkdir -p /etc/fish/functions
cp /ctx/unicode-start-noop.fish /etc/fish/functions/unicode_start.fish

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

# hypridle runs as a --user service (§spec:auto-suspend §spec:hypridle-user-service) so the re-arm timer can
# restart it. niri starts it via spawn-at-startup; not enabled here
# because niri --session does not activate graphical-session.target.
install -Dm644 /ctx/hypridle.service /usr/lib/systemd/user/hypridle.service

# Weekday 18:00 timer re-arms hypridle at the business-hours boundary
# (§spec:auto-suspend §spec:weekday-rearm). Enabled for all users; timers.target is reached by the
# user manager independent of the graphical session.
install -Dm644 /ctx/tilefin-hypridle-rearm.service /usr/lib/systemd/user/tilefin-hypridle-rearm.service
install -Dm644 /ctx/tilefin-hypridle-rearm.timer /usr/lib/systemd/user/tilefin-hypridle-rearm.timer
systemctl --global enable hypridle.service        # Pulled in by graphical-session.target (§spec:session-targets)
systemctl --global enable tilefin-hypridle-rearm.timer

# waybar (status bar)
# System-wide config via XDG fallback (/etc/xdg/waybar/)
# Users can override by creating ~/.config/waybar/config
mkdir -p /etc/xdg/waybar
cp /ctx/waybar-config-niri.json /etc/xdg/waybar/config
cp /ctx/waybar-style.css /etc/xdg/waybar/style.css
install -Dm755 /ctx/update-check.sh /usr/share/tilefin/scripts/update-check.sh
install -Dm755 /ctx/notification-indicator.sh /usr/share/tilefin/scripts/notification-indicator.sh
install -Dm755 /ctx/auto-suspend.sh /usr/share/tilefin/scripts/auto-suspend.sh

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

# GPU passthrough to a local VM (§spec:gpu-passthrough). Each piece is inert
# on a machine that never passes a GPU through.
# Hand the NVIDIA GPU to a guest and back (§spec:gpu-handover). A real file,
# not a symlink into /usr, so it carries the policy's virt_hook_t label.
install -Dm755 /ctx/nvidia-handover /etc/libvirt/hooks/qemu.d/50-nvidia-handover
# Shared-memory owner group, the shared memory itself and the guest log
# directory, each labelled by the module below (§spec:passthrough-selinux-labels).
install -Dm644 /ctx/looking-glass.sysusers /usr/lib/sysusers.d/looking-glass.conf
install -Dm644 /ctx/passthrough.tmpfiles /usr/lib/tmpfiles.d/tilefin-passthrough.conf
# -n: build the policy store without loading it; the booted system loads it.
semodule -n -i /ctx/tilefin-passthrough.cil
# The Containerfile copies the client and its icon in; the launcher entry and
# the client defaults come from here (§spec:looking-glass-client).
install -Dm644 /ctx/looking-glass-client.desktop /usr/share/applications/looking-glass-client.desktop
install -Dm644 /ctx/looking-glass-client.ini /etc/looking-glass-client.ini
# Host sleep waits while a guest holds the GPU, and host shutdown shuts guests
# down cleanly (§spec:passthrough-host-power). The guard holds a sleep
# inhibitor while the handover hook's markers exist; libvirt-guests shuts
# every running guest down, passthrough or not, before libvirt stops.
install -Dm755 /ctx/passthrough-sleep-guard.sh /usr/share/tilefin/scripts/passthrough-sleep-guard.sh
install -Dm644 /ctx/tilefin-passthrough-sleep-guard.path /usr/lib/systemd/system/tilefin-passthrough-sleep-guard.path
install -Dm644 /ctx/tilefin-passthrough-sleep-guard.service /usr/lib/systemd/system/tilefin-passthrough-sleep-guard.service
systemctl enable tilefin-passthrough-sleep-guard.path
install -Dm644 /ctx/libvirt-guests.sysconfig /etc/sysconfig/libvirt-guests
systemctl enable libvirt-guests.service

# Media CPU partition (§spec:media-cpu-partition). The image carries the
# mechanism and no core numbers: `ujust media-cores` writes a machine's
# partition as local kernel arguments, and the steering unit runs only on a
# command line that carries one.
install -Dm755 /ctx/media-cores.sh /usr/share/tilefin/scripts/media-cores.sh
install -Dm644 /ctx/tilefin-media-cores-steer.service /usr/lib/systemd/system/tilefin-media-cores-steer.service
systemctl enable tilefin-media-cores-steer.service

# P2P PCIe mode (§spec:p2p-pcie). The image carries the mechanism and no PCI
# addresses: `ujust p2p-pcie` writes a machine's root ports as a local kernel
# argument and its NIC to /etc/tilefin/p2p-pcie.conf, and the udev rule acts
# only while that file exists. The template unit has no [Install] section;
# the rule starts it.
install -Dm755 /ctx/p2p-pcie.sh /usr/share/tilefin/scripts/p2p-pcie.sh
install -Dm644 /ctx/tilefin-p2p-pcie@.service /usr/lib/systemd/system/tilefin-p2p-pcie@.service
install -Dm644 /ctx/80-tilefin-p2p-pcie.rules /usr/lib/udev/rules.d/80-tilefin-p2p-pcie.rules

# Raise memlock limit for GPU/RDMA workloads (nvidia_p2p_get_pages,
# ibv_reg_mr). Applies to all users in wheel group.
# PAM path — covers interactive login sessions (greetd → niri → terminal)
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-memlock.conf <<'EOF'
# Unlimited memlock for wheel group — required for GPU pinned memory
# and RDMA verb registration (DeckLink capture, ST2110 on the ConnectX-6)
@wheel  -  memlock  unlimited
EOF

# systemd path — covers user services (e.g. userbox.service)
mkdir -p /etc/systemd/user.conf.d
cat > /etc/systemd/user.conf.d/memlock.conf <<'EOF'
[Manager]
DefaultLimitMEMLOCK=infinity
EOF

# Raise the inotify instance cap. The kernel default (128) is exhausted by
# a development workload: every conmon (one per podman container, including
# userbox and kind nodes) takes an instance, as do editors, direnv, and file
# watchers. Exhaustion shows up as "conmon: Failed to create inotify fd".
# See §spec:inotify-instance-cap.
mkdir -p /usr/lib/sysctl.d
cat > /usr/lib/sysctl.d/90-inotify.conf <<'EOF'
# 512 matches the kind rootless-podman recommendation
fs.inotify.max_user_instances = 512
EOF

# Turn an unrecoverable hang into a recorded panic. The capture chain below
# this is already complete — pstore registers the firmware-backed ERST
# backend and systemd-pstore.service is enabled in the base image — but
# nothing converted a hang into a panic, so a freeze left no evidence at all.
# See §spec:crash-capture.
cat > /usr/lib/sysctl.d/91-crash-capture.conf <<'EOF'
# All SysRq functions. Alt+SysRq+w (blocked tasks) and Alt+SysRq+l (CPU
# backtraces) put a diagnosis in the log while the machine is still wedged;
# REISUB gets a clean sync out of one that is past saving. The kernel default
# of 16 permits only an emergency sync.
kernel.sysrq = 1

# A hard lockup — a CPU that stopped answering the NMI watchdog — is already
# fatal. Panicking records why, instead of leaving a silent freeze.
kernel.hardlockup_panic = 1

# An oops leaves the kernel in an undefined state. Panic while the trace can
# still be written rather than limping on to a worse failure.
kernel.panic_on_oops = 1

# Reboot 20s after a panic, which gives pstore time to write. The default of 0
# leaves the machine dead at the panic screen until someone walks over to it,
# and the trace is in pstore either way.
kernel.panic = 20

# kernel.softlockup_panic is deliberately left at 0. A soft lockup is 20s in
# the kernel without scheduling, which heavy DMA from the capture card or the
# NICs can reach without the machine being wedged, so enabling it trades a
# silent freeze for spurious reboots. Turn it on for the duration of a bisect,
# not as standing configuration.
EOF

# Keep the console to errors once the system is up, so kernel warnings stop
# landing on the greeter's tty. Early boot still prints everything, because
# this applies when systemd-sysctl runs; the journal keeps every level.
# See §spec:console-loglevel.
cat > /usr/lib/sysctl.d/92-console-loglevel.conf <<'EOF'
# console_loglevel 4 prints emerg, alert, crit and err (levels 0-3) to the
# console and leaves warnings and below to the journal. The other three
# fields keep the kernel's defaults.
kernel.printk = 4 4 1 7
EOF

# Plymouth turns console logging off when it starts in the initrd, which
# saves the level then in force (the kernel default of 7), and turns it back
# on when it quits, which restores that saved 7 over the sysctl above. Apply
# the printk sysctl again once Plymouth has quit (§spec:console-loglevel).
mkdir -p /usr/lib/systemd/system/plymouth-quit.service.d
cat > /usr/lib/systemd/system/plymouth-quit.service.d/10-tilefin-console-loglevel.conf <<'EOF'
[Service]
ExecStartPost=-/usr/lib/systemd/systemd-sysctl --prefix=kernel.printk
EOF

# Skip systemd-remount-fs on a read-only root (§spec:composefs-root-remount).
# The root is a read-only composefs overlay, which refuses every remount. An
# installer that wrote / into /etc/fstab makes the unit try anyway: it fails
# on every boot, and a hung attempt blocks boot indefinitely, since the unit
# has no start timeout and the journal flush waits for it.
mkdir -p /usr/lib/systemd/system/systemd-remount-fs.service.d
cat > /usr/lib/systemd/system/systemd-remount-fs.service.d/10-tilefin-composefs-skip.conf <<'EOF'
# statvfs reports ST_RDONLY for the composefs root, so the condition fails
# and the unit is skipped: never run, never failed, never hung. A writable
# root still runs it. On a read-only root this also skips any other fstab
# entry the unit owns (/usr, API filesystems); the image ships none.
[Unit]
ConditionPathIsReadWrite=/
EOF

# Enable the IOMMU for GPU passthrough, with host-owned devices in passthrough
# mode. These kernel args apply on the next boot after an image switch.
mkdir -p /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/10-iommu.toml <<'EOF'
# intel_iommu=on enables the Intel IOMMU so VFIO can hand a GPU to a guest
# (§spec:virtualization), because Fedora builds without
# CONFIG_INTEL_IOMMU_DEFAULT_ON. The AMD IOMMU enables itself from the firmware
# tables and takes no argument.
#
# iommu=pt gives host-owned devices an identity domain. The NIC needs it to
# DMA into GPU memory registered as a DMA-BUF memory region, because under a
# translating IOMMU every one of those peer-to-peer writes faults
# (§spec:iommu-mode). Passthrough to a guest still works: binding vfio-pci
# moves that device's group into a translated domain that VFIO owns.
kargs = ["intel_iommu=on", "iommu=pt"]
EOF

# Enable verbose boot (show kernel and systemd messages instead of splash)
# Note: bootc kargs.d only supports adding args, not deleting.
# To remove 'quiet' and 'rhgb' from base image, run after first boot:
#   rpm-ostree kargs --delete=quiet --delete=rhgb
cat > /usr/lib/bootc/kargs.d/20-verbose-boot.toml <<'EOF'
# Show systemd service status during boot
kargs = ["systemd.show_status=1"]
EOF

# NVIDIA module parameters — kernel args, deliberately not modprobe.d.
#
# nvidia.ko loads from the initramfs, seconds before switch-root. That
# initramfs is generated in the ublue base image, so it captures the base's
# /usr/lib/modprobe.d and nothing this script writes afterwards: options
# placed in /etc/modprobe.d read back as their defaults on the running
# system (verify with /proc/driver/nvidia/params). Kernel command line
# parameters bind at module load regardless of when the module is loaded.
# Regenerating the initramfs in this layer would also work, but kargs are
# cheaper and are already the established pattern here.
#
# One parameter remains. nvidia-drm.modeset was dropped — the driver has
# defaulted it on since 560 and this image ships 610 (§spec:nvidia-drm-modeset)
# — and NVreg_EnableResizableBar with it, a no-op wherever firmware already
# sizes BAR1 to full VRAM (§spec:static-bar1-p2pdma).
#
# NVreg_RestrictProfilingToAdminUsers=0: non-root access to GPU
#   performance counters for Nsight Compute/Systems and CUPTI, which
#   otherwise fail with ERR_NVGPUCTRPERM. Confirm with
#   RmProfilingAdminOnly in /proc/driver/nvidia/params.
cat > /usr/lib/bootc/kargs.d/40-nvidia-params.toml <<'EOF'
kargs = ["nvidia.NVreg_RestrictProfilingToAdminUsers=0"]
EOF

###############################################################################
# Install Custom Justfile (ujust recipes)
###############################################################################

echo "Installing custom ujust recipes..."
cp /ctx/60-custom.just /usr/share/ublue-os/just/60-custom.just
cp /ctx/tilefin.just /usr/share/ublue-os/just/61-tilefin.just
cp /ctx/bmd.just /usr/share/ublue-os/just/62-bmd.just

echo "Build complete!"
