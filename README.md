# Tiling Bluefin-DX (Experimental)

A custom [bootc](https://github.com/bootc-dev/bootc) image based on Universal Blue's Bluefin-DX, replacing GNOME with tiling window managers for a keyboard-driven Wayland workflow with Nvidia GPU support.

**Default Compositor**: Niri (Hyprland also available, selectable at login)

**Wayland-Only**: This is a pure Wayland build with no XWayland/X11 compatibility layer. All applications must support native Wayland.

## Compositor Migration History

This project has evolved through several compositors seeking the best HiDPI and tiling experience:

### Sway → Hyprland
Sway lacks `wp-fractional-scale-v1` support, limiting it to integer-only scaling (1x, 2x). This is unusable on modern HiDPI displays where users need 1.25x or 1.5x scaling.

### Hyprland → Niri (Current Default)
While Hyprland solved the fractional scaling protocol support, it exhibited **scaling algorithm artifacts** - visible as repeated columns/rows of pixels at certain scale factors. Niri resolves these rendering issues and provides cleaner fractional scaling output.

Both compositors remain installed and selectable at the login screen.

## Project Goals

This image aims to provide:

1. **Reliability**: A stable, well-supported tiling window manager that works consistently
2. **Visual Quality**: Proper high-DPI support and modern aesthetics (not terminal-era visuals)
3. **Nvidia Compatibility**: Full GPU support for Nvidia hardware
4. **Developer Workflow**: Preserve Bluefin-DX's development tools while adding tiling capabilities
5. **Keyboard-Driven**: Efficient tiling window management

## Key Features

### Excellent High-DPI Support
Niri provides clean fractional scaling without the pixel-repetition artifacts seen in some other compositors. Proper `wp-fractional-scale-v1` protocol support ensures crisp text and UI elements on modern displays.

### Scrollable Tiling
Niri's unique scrollable/infinite canvas workflow - windows tile horizontally and you scroll through them, rather than cramming everything onto a fixed screen. Great for ultrawide monitors and focus-oriented workflows.

## What This Image Does

This image transforms Bluefin-DX into a tiling window manager system by:

### GNOME Removal
Removes GNOME Shell, GDM, Mutter, and all GNOME Shell extensions to create a minimal base for tiling compositors.

### Compositor Installation
Installs both **Niri** (default) and **Hyprland** compositors, selectable at the login screen:

- **Niri** (recommended): Scrollable tiling compositor with clean fractional scaling and infinite canvas workflow
- **Hyprland**: Dynamic tiling compositor with animations and effects (fallback option)

Shared environment includes:
- **Status Bar**: Waybar
- **Application Launcher**: Fuzzel
- **Terminal**: Ptyxis (GTK4, GPU-accelerated, native container integration)
- **Lock Screen**: Hyprlock (both compositors)
- **Idle Management**: hypridle (both compositors)
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
- Session selector allows choosing between Niri and Hyprland at login
- Remembers your last session choice
- Properly configured for OSTree-based systems using sysusers.d and tmpfiles.d
- Full Nvidia environment variables configured

### Theming
- Default GTK theme set to **adw-gtk3-dark** for both GTK 3 and GTK 4
- Dark theme preference enabled by default
- Configuration applied via `/etc/skel` for all new users

### System Configuration
- **Polkit agent**: lxpolkit configured to autostart with the compositor
- **Portals**: xdg-desktop-portal-gtk (shared) and xdg-desktop-portal-hyprland for proper Wayland integration
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

### Tailscale VPN (Optional)

Tailscale is pre-installed and enabled. To set up the GUI:

1. **Set your user as operator** (allows GUI control without sudo):
   ```bash
   sudo tailscale set --operator=$USER
   ```

2. **Install trayscale GUI** (already configured to auto-start):
   ```bash
   flatpak install flathub dev.deedles.Trayscale
   ```

The trayscale icon will appear in your system tray for easy VPN management.

### WireGuard VPN

WireGuard tools are pre-installed. Configure VPN connections via NetworkManager:
- Use `nmcli` for CLI configuration
- Or install `nm-connection-editor` for GUI setup

WireGuard status is shown in the waybar status bar.

## Configuration

### Niri (Default)
Customize by editing `~/.config/niri/config.kdl`. See the [Niri wiki](https://github.com/YaLTeR/niri/wiki) for configuration options.

### Hyprland
Customize by editing `~/.config/hypr/hyprland.conf`. This file will be sourced by the system configuration and can override any settings.

### Key Bindings (Niri Default)

- **Super + Enter**: Launch terminal (ptyxis)
- **Super + D**: Application launcher (fuzzel)
- **Super + Q**: Close window
- **Super + Shift + E**: Exit Niri
- **Super + E**: File manager (Thunar)
- **Super + V**: Toggle floating
- **Super + Arrow Keys**: Move focus
- **Super + 1-9**: Switch workspace
- **Super + Shift + 1-9**: Move column to workspace
- **Super + R**: Cycle preset column widths (1/3, 1/2, 2/3)
- **Super + F**: Maximize column
- **Super + O**: Toggle overview
- **Print**: Screenshot selection

All keybindings can be customized in your user configuration file.

## Community Resources

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion Forums](https://github.com/bootc-dev/bootc/discussions)
