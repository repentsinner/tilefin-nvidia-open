# Tilefin-DX

A custom [bootc](https://github.com/bootc-dev/bootc) image based on [Universal Blue](https://github.com/ublue-os)'s [Bluefin-DX](https://github.com/ublue-os/bluefin/), replacing GNOME with the [Niri](https://github.com/niri-wm/niri) tiling compositor for a keyboard-driven [Wayland](https://wayland.freedesktop.org/) workflow with Nvidia GPU support.

## Opinionated Defaults

This image makes deliberate choices that diverge from upstream Bluefin:

| Choice | Rationale |
|--------|-----------|
| **Niri compositor** | Scrollable tiling, clean fractional scaling, official Fedora package. |
| **Wayland-only** | No XWayland/X11. Future-forward graphics stack. Apps that don't support Wayland won't work. |
| **No Homebrew** | Bluefin targets single-user macOS-style laptops. We want a proper immutable system without `/home/linuxbrew` pollution. Use Flatpak, distrobox, or bake it into the image. |
| **Minimal notifications** | Mako runs invisibly by default. A waybar indicator shows when notifications exist. No toasts stealing focus. |
| **Focus-follows-mouse** | Enabled in Niri. Keyboard navigation still works independently. |

## Project Goals

This image aims to provide:

1. **Reproducibility**: An reproducible, immutable system image. No system-wide homebrew
2. **Reliability**: A stable, well-supported tiling window manager that works consistently
3. **Visual Quality**: Proper high-DPI support and modern aesthetics (not terminal-era visuals)
4. **Nvidia Compatibility**: Full GPU support for Nvidia hardware
5. **Developer Workflow**: Preserve Bluefin-DX's development tools while adding tiling capabilities
6. **Keyboard-Driven**: Efficient tiling window management

## Key Features

### Excellent High-DPI Support
Niri provides clean fractional scaling without the pixel-repetition artifacts seen in some other compositors such as Hyprland. Proper `wp-fractional-scale-v1` protocol support ensures crisp text and UI elements on modern displays.

### Scrollable Tiling
Niri's unique scrollable/infinite canvas workflow - windows tile horizontally and you scroll through them, rather than cramming everything onto a fixed screen. Great for ultrawide monitors and focus-oriented workflows.

## What This Image Does

This image transforms Bluefin-DX into a tiling window manager system by:

### GNOME Removal
Removes GNOME Shell, GDM, Mutter, and all GNOME Shell extensions to create a minimal base for the Niri compositor.

Environment includes:
- **Status Bar**: Waybar
- **Application Launcher**: Fuzzel
- **Terminal**: Ptyxis (GTK4, GPU-accelerated, native container integration)
- **Lock Screen**: Hyprlock
- **Idle Management**: hypridle
- **Notifications**: Mako
- **Screenshots**: Grim and Slurp
- **Screen Recording**: wf-recorder
- **Wallpaper**: swww
- **File Manager**: Thunar
- **Display Management**: wdisplays
- **Utilities**: wl-clipboard, cliphist, pamixer, brightnessctl
- **IDE**: Google Antigravity

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
- **Layout**: Master-stack layout configured as default
- **Nvidia optimizations**: Full environment variable configuration for optimal GPU performance

## Identified Requirements

Based on the current setup, any replacement compositor must support:

### Core Requirements
- **Nvidia GPU compatibility**: Must work with proprietary Nvidia drivers
- **Wayland-only**: Pure Wayland, no XWayland/X11 compatibility (X11-only apps will not work)
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

### Development Workflow (Inherited from Bluefin-DX)
- Container tooling compatibility (Podman, distrobox)
- Terminal emulator support
- Screen capture/recording tools
- Visual theming capabilities (GTK apps)

## Installation

From a bootc-based system (Bazzite, Bluefin, Aurora, etc.):

```bash
sudo bootc switch ghcr.io/<username>/tiled-bluefin-dx-nvidia-open
sudo reboot
```

## Post-Installation Setup

### WireGuard VPN

WireGuard tools are pre-installed. Configure VPN connections via NetworkManager:
- Use `nmcli` for CLI configuration
- Or install `nm-connection-editor` for GUI setup

WireGuard status can be monitored via NetworkManager.

## Configuration

### Niri
Customize by editing `~/.config/niri/config.kdl`. See the [Niri wiki](https://github.com/YaLTeR/niri/wiki) for configuration options.

### Key Bindings

- **Super + /**: View current key bindings

## Package Management Guidelines

On immutable, multi-user systems, package management requires more thought than traditional Linux. Homebrew's single-user macOS assumptions (shared `/home/linuxbrew` owned by one user, system-wide pollution) scale poorly. Prefer these methods in order:

### Preference Hierarchy

1. **System Image** (baked in or rpm-ostree layer)
   - For: Compositors, system services, boot-critical tools
   - Why: Atomic updates, rollback capability, consistent across users

2. **Flatpak with `--user`**
   - For: GUI applications
   - Why: Sandboxed, per-user isolation, auto-updates, proper portal integration
   - Example: `flatpak install --user flathub org.mozilla.firefox`

3. **Native Installers** (vendor-provided, to `~/.local/bin`)
   - For: CLI tools where vendor provides self-updating installer
   - Why: Fastest updates, per-user, vendor-maintained
   - Example: `claude install` (Anthropic's Claude Code)

4. **Distrobox/Toolbox Containers**
   - For: Development toolchains, language runtimes, mutable environments
   - Why: Full isolation, disposable, doesn't touch host
   - Example: `distrobox create --name dev --image fedora:latest`

5. **AppImage**
   - For: One-off tools, testing software
   - Why: No install required, self-contained
   - Downsides: No auto-update, no sandboxing, manual management

6. **Homebrew** (last resort)
   - For: When nothing else works
   - Why not: Single-owner shared state, multi-user hostile, permission chaos
   - If forced: Document who "owns" it, accept the tradeoffs

### Bluefin's Homebrew Integration

Bluefin provides convenience wrappers for homebrew via ujust:

- **`ujust bluefin-cli`**: Installs curated CLI tools (atuin, starship, eza, fd, ripgrep, etc.)
- **`ujust bbrew`**: Interactive installer for curated Brewfiles (IDE tools, k8s tools, fonts, etc.)

This works well for **single-user systems** where Bluefin's target audience lives. The curated Brewfiles are sensible defaults and save setup time.

**For multi-user systems**, the standard homebrew caveats apply—`/home/linuxbrew` is shared and owned by whoever set it up first. Consider containerizing homebrew in a distrobox if user isolation matters.

### Multi-User Considerations

- Flatpak `--user` installs are truly per-user (`~/.local/share/flatpak`)
- Native installers to `~/.local/bin` are per-user
- Homebrew's `/home/linuxbrew` is shared—one user owns it, others suffer
- Distrobox containers are per-user by default
- When in doubt, containerize it

### ujust Recipe Updates

ujust recipes are baked into the system image (`/usr/share/ublue-os/just/`). They update when the OS image updates via bootc, not separately. Run `ujust --list` to see available recipes.

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
