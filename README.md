# Tilefin

A custom [bootc](https://github.com/bootc-dev/bootc) image built on [Universal Blue](https://github.com/ublue-os)'s [base-nvidia](https://github.com/ublue-os/main), providing the [Niri](https://github.com/niri-wm/niri) tiling compositor for a keyboard-driven [Wayland](https://wayland.freedesktop.org/) desktop with Nvidia GPU support.

## Opinionated Defaults

| Choice | Rationale |
| -------- | ----------- |
| **base-nvidia base** | Minimal base with Nvidia drivers. No GNOME, Homebrew, Docker, or other packages to strip. Every installed package is an explicit choice. |
| **Niri compositor** | Scrollable tiling and clean fractional scaling. The image builds niri from a fork that adds a saturation window rule. |
| **Wayland-native** | The session is Wayland. X11 apps run through xwayland-satellite, which niri starts when an X11 client connects. |
| **Tools outside the image** | The image carries only the tools its own shell configuration calls. Standalone tools install per user, and dev toolchains live in a distrobox userbox, so neither waits on an image update. |
| **Minimal notifications** | Mako runs invisibly by default. A waybar indicator shows when notifications exist. No toasts stealing focus. |
| **Focus-follows-mouse** | Enabled in Niri. Keyboard navigation still works independently. |

## Project Goals

1. **Reproducibility**: Immutable system image with explicit, auditable package choices
2. **Reliability**: Stable tiling window manager that works consistently
3. **Visual Quality**: Proper high-DPI support and modern aesthetics
4. **Nvidia Compatibility**: Full GPU support for Nvidia hardware
5. **Keyboard-Driven**: Efficient tiling window management
6. **Clean separation**: OS image for the session and the tools its configuration calls; per-user installs and a userbox for everything else

## Key Features

### Excellent High-DPI Support

Niri provides clean fractional scaling without the pixel-repetition artifacts seen in some other compositors such as Hyprland. Proper `wp-fractional-scale-v1` protocol support ensures crisp text and UI elements on modern displays.

### Scrollable Tiling

Niri's unique scrollable/infinite canvas workflow - windows tile horizontally and you scroll through them, rather than cramming everything onto a fixed screen. Great for ultrawide monitors and focus-oriented workflows.

## What This Image Provides

The base image (`base-nvidia:latest`, which tracks the current Fedora release) provides Fedora, Nvidia open kernel modules, Podman, distrobox, just/ujust, Flatpak with Flathub, and media codecs. It ships no desktop environment. This image adds:

### Wayland Desktop Environment

- **Status Bar**: Waybar
- **Application Launcher**: Fuzzel
- **Terminal**: Ptyxis (GTK4, GPU-accelerated, native container integration)
- **Lock Screen**: Hyprlock
- **Idle Management**: hypridle
- **Notifications**: Mako
- **Screenshots**: Grim and Slurp
- **Screen Recording**: wf-recorder
- **Wallpaper**: swaybg
- **File Manager**: Thunar
- **Display Management**: wdisplays
- **Utilities**: wl-clipboard, cliphist, pamixer, brightnessctl

### Display Manager

- Uses **greetd** with **tuigreet** instead of GDM
- Remembers your last session choice
- Properly configured for OSTree-based systems using sysusers.d and tmpfiles.d
- Full Nvidia environment variables configured

### Theming

- Default GTK theme set to **adw-gtk3-dark** for both GTK 3 and GTK 4
- Dark theme preference enabled by default
- Configuration applied via `/etc/skel` for all new users

### System Configuration

- **Polkit agent**: lxpolkit configured to autostart with the compositor
- **Portals**: xdg-desktop-portal-gtk for proper Wayland integration
- **Input settings**:
  - Caps Lock remapped to Control
  - Natural scrolling enabled for touchpads
  - Custom keyboard and mouse configuration
- **Podman socket**: Enabled by default
- **Nvidia optimizations**: Full environment variable configuration for optimal GPU performance

## Identified Requirements

Based on the current setup, any replacement compositor must support:

### Core Requirements

- **Nvidia GPU compatibility**: Must work with proprietary Nvidia drivers
- **Wayland-native**: A Wayland session, with X11 apps served through xwayland-satellite
- **HiDPI scaling**: Proper fractional scaling and readable text/UI elements
- **OSTree compatibility**: Works with immutable/atomic OS structure

### Integration Requirements

- **Display Manager**: Works with greetd/tuigreet ✓
- **Desktop Portals**: Compatible with xdg-desktop-portal-gtk ✓
- **Session Management**: Launched via Wayland session files ✓
- **Polkit Integration**: Supports polkit agents for privilege escalation ✓

### User Experience

- **Tiling Management**: Automatic window tiling with keyboard controls
- **Multi-monitor**: Robust multi-display support
- **Configuration**: Declarative config files (no GUI-only settings)
- **Input Remapping**: Custom keyboard layouts (e.g., Caps→Ctrl)

### Development Workflow

- VS Code (host application, attaches to containers)
- Container tooling (Podman, distrobox — from base image)
- Fish shell
- Full KVM/QEMU/libvirt virtualization stack with Looking Glass

## Installation

From any bootc-based system:

```bash
sudo bootc switch ghcr.io/repentsinner/tilefin-nvidia-open
sudo reboot
```

## Post-Installation Setup

### WireGuard VPN

WireGuard tools are pre-installed. Configure VPN connections via NetworkManager:

- Use `nmcli` for CLI configuration
- Or install `nm-connection-editor` for GUI setup

WireGuard status can be monitored via NetworkManager.

### Post-Install Setup

First boot provisions your user environment in one step:

```bash
ujust setup-user
```

An interactive menu lets you select from:

- **Standalone tools**, installed into `~/.local/bin`: Claude Code, uv,
  mise, `gh`, `chezmoi` and the lint gates (`shellcheck`) are selected by
  default. The Kubernetes clients (`kubectl`, `helm`, `kind`, `talosctl`,
  `kubeseal`, `mc`) are optional and install through mise.
- **Flatpak apps**: Firefox, Bitwarden, Slack, Discord, Signal, Proton VPN
- **Userbox container**: a distrobox that carries dev toolchains needing a
  full Fedora userland. It exports `fvm`, the Flutter version manager, to
  `~/.local/bin`.

The shell tools behind the image's aliases and prompt (`bat`, `eza`,
`zoxide`, `direnv`, `starship`, `rbw`) ship in the image and need no
setup.

To use a different userbox image:

```bash
ujust setup-user ghcr.io/youruser/yourbox:latest
```

Then bootstrap chezmoi for dotfiles and userbox auto-assembly on future
logins:

```bash
chezmoi init --apply <your-dotfiles-repo>
```

The chezmoi-managed systemd unit reassembles the userbox on each login.
After `chezmoi apply`, the process is self-sustaining.

## Usage

### Updates

The image stages each new build automatically, and the next reboot applies
it. To hold a machine on its current image, turn on production mode:

```bash
ujust production-mode --start
```

While production mode is on, `ujust update` still applies the latest image
on demand. To resume automatic updates:

```bash
ujust production-mode --stop
```

### Niri

Customize by editing `~/.config/niri/config.kdl`. See the [Niri wiki](https://github.com/YaLTeR/niri/wiki) for configuration options.

### Key Bindings

- **Super + /**: View current key bindings

## Package Management

On an immutable system, where a tool lands depends on what depends on it.
Anything the image's own configuration calls ships in the image, because
the configuration and the binary have to update together. Everything else
installs outside the image, so it updates without a rebuild or a reboot:

| Layer | For | Example |
| -------- | ----- | --------- |
| **System image** | Session infrastructure, system services, and the binaries the image's own configuration and services call | Niri, greetd, libvirt, `starship`, `direnv`, `docker-compose` |
| **Per-user tools** (`~/.local/bin`) | Standalone command-line tools that nothing in the image refers to | Claude Code, uv, `gh`, `chezmoi`, and the Kubernetes clients through mise |
| **Distrobox** | Dev toolchains that need a full distro userland: packages, compilers, headers | The userbox (Flutter through `fvm`), or `distrobox create --image fedora:latest` |
| **Flatpak** | Sandboxed GUI apps | `flatpak install --user flathub org.gnome.Evince` |

`ujust setup-user` installs the per-user tools and assembles the userbox.

ujust recipes are baked into the system image (`/usr/share/ublue-os/just/`). They update when the OS image updates via bootc. Run `ujust --list` to see available recipes.

## Compositor Migration History

This project has evolved through several compositors seeking the best HiDPI and tiling experience:

### Sway → Hyprland

Sway lacks `wp-fractional-scale-v1` support, limiting it to integer-only scaling (1x, 2x). This is unusable on modern HiDPI displays where users need 1.25x or 1.5x scaling.

### Hyprland → Niri (Current Default)

While Hyprland solved the fractional scaling protocol support, it has two significant issues:

1. **Scaling artifacts** - visible as repeated columns/rows of pixels at certain fractional scale factors
2. **Recursive splitting layout** - Hyprland's default tiling algorithm continuously subdivides columns for new windows, making layouts with more than 2-3 windows impractical (each window becomes a sliver)

Niri resolves both issues with cleaner fractional scaling and a scrollable horizontal layout that doesn't degrade with window count.

Hyprland has been removed from this image. Niri is the sole compositor.

## Community Resources

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion Forums](https://github.com/bootc-dev/bootc/discussions)

## License

Tilefin is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
