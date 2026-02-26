# SPEC: Tilefin System Image

## Purpose

Tilefin is an immutable bootc/OSTree system image that provides a
keyboard-driven Wayland desktop on Nvidia hardware. It layers the Niri
tiling compositor, a Wayland session stack, and desktop applications on
top of Universal Blue's base-nvidia image.

The image provides desktop infrastructure only: compositor, session
management, display manager, theming, and system services. User tools
and development toolchains belong in distrobox containers or user-space
installers — not in the image.

## Base image

`ghcr.io/ublue-os/base-nvidia:gts`

The base image provides Fedora (bootc/OSTree), Nvidia open kernel
modules, nvidia-container-toolkit, Podman, distrobox, just/ujust,
Flatpak with Flathub, media codecs (ffmpeg/libva via negativo17),
XWayland, xdg-desktop-portal, and xdg-desktop-portal-gtk. It ships no
desktop environment or display manager.

Rationale: the previous base (`bluefin-dx-nvidia-open`) included GNOME,
Homebrew, Docker, Cockpit, ROCm, Samba/AD, and other packages the image
immediately removed or never used. Rebasing on base-nvidia eliminates
the install-then-strip cycle, reduces image size, and makes every
installed package an explicit choice.

## Image boundary

The image shall contain only software that meets at least one of:

- Required before or during login (greetd, compositor, session wrapper).
- Required by the desktop session (waybar, clipboard, lock screen).
- A system service or kernel-level integration (libvirt, IOMMU, podman).
- Desktop applications tightly coupled to the session (file manager,
  terminal, polkit agent).

Software that runs on demand with no session dependency belongs
elsewhere:

| Delivery | For |
|---|---|
| **Userbox** (distrobox, pre-built OCI) | CLI tools, shell utilities, dev toolchains |
| **Flatpak** | Sandboxed GUI apps |
| **Native installer** (`~/.local/bin`) | Self-updating vendor CLIs (e.g., Claude Code) |

## Sections

### S1: GNOME removal

*Status: obsolete — base-nvidia ships no desktop environment*

Previously required when the base image was Bluefin-DX (Silverblue).
The base-nvidia image has no GNOME components to remove.

### S2: Homebrew removal

*Status: obsolete — base-nvidia ships no Homebrew integration*

Previously required when the base image was Bluefin-DX. The base-nvidia
image has no Homebrew artifacts.

### S3: Niri compositor

*Status: complete — PR #1, 2024-10-15*

The image installs a custom niri fork (niri-desaturate) from a GitHub
release RPM until the desaturate window rule merges upstream.

The session launches via a wrapper script (`niri-tilefin-session`) that
sets `SSH_AUTH_SOCK` before starting niri. A custom `.desktop` file
registers the session with greetd.

System-wide config lives at `/etc/niri/config.kdl`. Users override via
`~/.config/niri/config.kdl`.

### S4: Wayland environment

*Status: complete — PR #1, 2024-10-15*

The image provides a complete Wayland desktop environment:

- **Status bar**: Waybar with system-wide config at `/etc/xdg/waybar/`.
  Custom modules for update checking and notification indicators live at
  `/usr/share/tilefin/scripts/`.
- **Lock screen**: Hyprlock with system config at `/etc/xdg/hypr/`.
- **Idle management**: Hypridle with system config at `/etc/xdg/hypr/`.
- **Notifications**: Mako. No XDG fallback path — uses `/etc/skel/`.
- **Wallpaper**: swww.
- **Clipboard**: wl-clipboard, wl-clip-persist, cliphist.
- **Screenshots**: grim, slurp, wf-recorder.
- **App launcher**: Fuzzel.
- **Logout**: wlogout, nwg-bar, compositor-exit script.
- **Desktop portal**: xdg-desktop-portal-gtk (inherited from base image;
  portals.conf selects GTK backend over GNOME).

### S5: Display manager

*Status: complete — PR #1, 2024-10-15*

greetd with tuigreet provides graphical session login. The base image
enables `getty@tty1` (console login); greetd overrides this. Config at
`/etc/greetd/config.toml`.
A tmpfiles.d entry creates `/var/lib/greetd` at boot (the package's
tmpfiles.d only sets ownership, doesn't create the directory).

### S6: Desktop applications

*Status: complete — PR #1, 2024-10-15*

- **Terminal**: Ptyxis (GTK4, native distrobox integration).
- **File manager**: Thunar with gvfs and tumbler.
- **Media**: mpv.
- **Polkit**: lxpolkit.
- **Utilities**: rofimoji, network-manager-applet, wdisplays.
- **Shell**: fish.
- **Flatpaks** (installed by `ujust setup-user`, not baked into image):
  Bitwarden, Firefox, Slack.

### S7: Theming

*Status: complete — PR #1, 2024-10-15*

adw-gtk3-dark for GTK 3/4. System-wide via `/etc/gtk-{3,4}.0/`. GTK 2
via `/etc/skel/.gtkrc-2.0`. Fonts: Fira Code, FontAwesome, Noto Emoji.

### S8: System services

*Status: complete — PR #1, 2024-10-15*

Enabled at build time:

- `podman.socket` — container management.
- `libvirtd.socket` — VM management (socket-activated).
- `greetd.service` — display manager.
- `rpm-ostreed-automatic.timer` — auto-stage image upgrades.

### S9: Virtualization

*Status: complete — PR #1, 2024-10-15*

Full KVM/QEMU/libvirt stack for Windows VM hosting with Looking Glass
GPU passthrough support:

- libvirt, qemu-kvm, virt-manager, virt-install.
- edk2-ovmf (UEFI firmware), swtpm (TPM emulation for Windows 11).
- looking-glass-client (low-latency framebuffer, from COPR).
- virtiofsd (fast file sharing).
- Polkit rule: wheel group can manage VMs without extra groups.
- IOMMU kernel args enabled via `bootc kargs.d`.

### S10: Wayland environment config

*Status: complete — PR #1, 2024-10-15*

- Electron apps forced to native Wayland via
  `/etc/environment.d/electron-wayland.conf`.
- System-wide Flatpak overrides enable Wayland socket and Electron
  Wayland flags.

### S11: Shell configuration

*Status: complete — PR #1, 2024-10-15*

#### R11.1: Tool aliases

`/etc/profile.d/tool-aliases.sh` (bash) and
`/etc/fish/conf.d/tool-aliases.fish` (fish) provide aliases and shell
hooks for CLI tools regardless of origin (userbox exports or native
installers): bat, eza, zoxide, starship, direnv, and mise. All entries
are guarded (`command -v` in bash, `command -sq` in fish) and silently
skipped when the tool is absent.

#### R11.2: User-local bin directory in PATH

`/etc/profile.d/local-path.sh` (bash) and
`/etc/fish/conf.d/local-path.fish` (fish) prepend `~/.local/bin` to
`PATH`. The path expands per-user at shell startup. Both scripts are
idempotent — bash guards against duplicate entries, fish uses
`fish_add_path`.

Rationale: userbox exports (R12.4) and native installers (R12.5) place
binaries in `~/.local/bin`. Without this PATH entry, those binaries are
unreachable from interactive shells.

### S12: Userbox — move user tools to distrobox

*Status: in progress*

#### Problem

The image bakes in 7 CLI tools and 1 GUI app with no session-startup
dependencies: `gh`, `chezmoi`, `direnv`, `zoxide`, `starship`, `eza`,
`bws`, `antigravity`. Including them causes image rebuilds for tool
updates and blurs the boundary between OS and personal environment.

#### Design

User tools move to a pre-built OCI container image consumed by
distrobox. The container is ephemeral — recreated from the image on
each login via a systemd user unit. No drift from the declaration.

See [repentsinner/userbox](https://github.com/repentsinner/userbox) for
the Containerfile and CI. This repo covers only the image-side changes.

Three repos, three concerns:

| Repo | Contains | Lifecycle |
|---|---|---|
| **tilefin-nvidia-open** | OS image, ujust recipes, shell aliases, skel default | Rare |
| **repentsinner/userbox** | Containerfile for user tools image | Frequent |
| **chezmoi dotfiles** | `.ini`, systemd unit, shell config | Personal |

##### Bootstrap and graceful degradation

A fresh system has no chezmoi (it lives inside the userbox) and no
userbox `.ini` (it's managed by chezmoi). This cycle breaks via three
layers of the same file, each more specific than the last:

1. **Skel default** — the image ships
   `/etc/skel/.config/distrobox/userbox.ini` with a default image path.
   Every new user account gets a working `.ini` at account creation.
2. **ujust override** — `ujust setup-user [image]` accepts an optional
   image argument, rewrites the `.ini`, and runs assembly. Also installs
   native CLI tools (Claude Code, uv). Useful for first boot or
   switching images.
3. **Chezmoi steady-state** — once the userbox is running, chezmoi owns
   the `.ini` going forward. Changes flow from dotfiles.

All shell aliases and hooks are guarded with `command -v`. A system
with no userbox functions normally — it just lacks CLI tools.

#### R12.1: Image does not contain user tools

The image does not install `gh`, `chezmoi`, `direnv`, `zoxide`,
`starship`, `eza`, `bat`, `bws`, or `antigravity`. No COPR repos, curl
blocks, or package arrays exist for these tools in the build script.
Native installer tools (Claude Code, uv) are also not in the image —
they are installed per-user by `ujust setup-user`.

#### R12.2: Shell aliases degrade gracefully

Every alias and shell hook in `tool-aliases.sh` is guarded with
`command -v`. When a tool is absent (no userbox, or userbox not yet
assembled), the alias is silently skipped. No `command not found`
errors on a fresh system.

#### R12.3: Shell hooks for both bash and fish

`tool-aliases.sh` and `tool-aliases.fish` include guarded hooks
for direnv, zoxide, and starship in both shells. Both files are
system-wide (`/etc/profile.d/` and `/etc/fish/conf.d/`), so no
chezmoi-managed fish config is required for these tools.

#### R12.4: Skel default userbox.ini

The image ships `/etc/skel/.config/distrobox/userbox.ini`. Every new
user account receives a working distrobox declaration at account
creation.

```ini
[userbox]
image=ghcr.io/repentsinner/userbox:latest
nvidia=true
pull=true
replace=true
start_now=true
exported_bins="/usr/bin/gh /usr/bin/chezmoi /usr/bin/direnv /usr/bin/zoxide /usr/bin/starship /usr/bin/eza /usr/bin/bws"
exported_bins_path="~/.local/bin"
```

`nvidia=true` matches the base image (`base-nvidia`), which ships Nvidia
open kernel modules and the container toolkit. The userbox inherits GPU
access for tools that need it.

Rationale: breaks the chezmoi↔userbox bootstrap cycle. Chezmoi lives
inside the userbox, so it cannot seed its own `.ini`. The skel file
provides a working default; chezmoi overwrites it once available.

#### R12.5: ujust setup-user recipe

`tilefin.just` is installed as `/usr/share/ublue-os/just/60-custom.just`,
the extension point that the base image's ujust justfile imports. It
provides a `setup-user` recipe that provisions a new user's development
environment in one step:

The recipe presents three interactive gum menus (all items selected by
default, user deselects with space):

1. **Native CLI tools** — Claude Code, uv, mise. Installed to
   `~/.local/bin` via vendor curl installers. All idempotent.
2. **Flatpak apps** — Firefox, Bitwarden (selected by default); Slack,
   Discord, Signal, Proton VPN (available, unselected). Installed as
   user Flatpaks (`--user`), which persist in `~/.local/share/flatpak`
   and self-update independently of the image.
3. **Userbox container** — yes/no. Assembles from
   `~/.config/distrobox/userbox.ini`.

When an optional image argument is provided, the recipe rewrites the
`image=` line in the `.ini` before assembly. This supports switching
images or overriding the skel default without chezmoi.

The recipe is idempotent. Running it again updates native tools,
skips already-installed Flatpaks, and reassembles the userbox with
`--replace`.

#### R12.6: Systemd user unit for auto-assembly (chezmoi)

A systemd user service (`~/.config/systemd/user/userbox.service`) runs
`distrobox assemble create --replace` on login. Managed by chezmoi.

```ini
[Unit]
Description=Assemble userbox distrobox container

[Service]
Type=oneshot
ExecStart=/usr/bin/distrobox assemble create --replace --file %h/.config/distrobox/userbox.ini
RemainAfterExit=true

[Install]
WantedBy=default.target
```

The service starts after login and does not block the GUI session. With
a cached image, container assembly takes ~10 seconds in the background.

### S13: Sunshine streaming server

*Status: not started*

The image shall include Sunshine for game/desktop streaming.

Sunshine requires direct GPU access (NVENC encoding), KMS/DRM capture,
udev rules for virtual input devices, and a systemd service. These are
system-level integrations that cannot run from a distrobox.

*Requirements to be specified after research into Sunshine's Fedora
packaging and Niri/Wayland compatibility.*

### S14: VS Code

*Status: in progress*

The image installs VS Code from Microsoft's yum repository. The build
adds the repo and installs the `code` package directly.

Rationale: the previous base (Bluefin-DX) provided VS Code; base-nvidia
does not. VS Code is a host application that attaches to containers — it
does not belong in the userbox.

### S16: Dynamic GPU detection for hybrid Intel+Nvidia systems

*Status: in progress*

#### Problem

The niri config hardcodes Nvidia-specific environment variables
(`GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`).
These force the compositor to render through Nvidia. On systems where
an Intel iGPU drives the display and the Nvidia GPU is reserved for
CUDA or PCI passthrough, these variables prevent niri from starting or
cause broken rendering.

Additionally, `WLR_NO_HARDWARE_CURSORS` is a wlroots variable. Niri
uses Smithay and ignores it. The equivalent niri setting is
`debug { disable-cursor-plane }`.

#### Design

Nvidia environment variables move from the static niri config
(`config.kdl`) to the session wrapper (`niri-session.sh`). The wrapper
detects whether an Nvidia GPU drives a display output and sets the
variables conditionally.

Detection: if any DRM connector under an Nvidia-driven card reports a
connected display, the system is Nvidia-as-display. Otherwise (Intel
iGPU drives display, Nvidia has no outputs or is unbound), the
variables stay unset and mesa auto-detects Intel.

The niri config retains only hardware-independent environment variables
(`XDG_SESSION_TYPE`, `XCURSOR_SIZE`, `ELECTRON_OZONE_PLATFORM_HINT`).

#### R16.1: No Nvidia environment variables in niri config

`config.kdl` shall not set `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`,
`LIBVA_DRIVER_NAME`, or `WLR_NO_HARDWARE_CURSORS`.

#### R16.2: Session wrapper sets Nvidia variables conditionally

`niri-session.sh` shall detect whether Nvidia drives a display output.
When true, it exports `GBM_BACKEND=nvidia-drm`,
`__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `LIBVA_DRIVER_NAME=nvidia`.
When false, it leaves them unset.

#### R16.3: WLR_NO_HARDWARE_CURSORS removed

The wlroots variable `WLR_NO_HARDWARE_CURSORS` is removed entirely. It
has no effect on niri (Smithay-based).

### S15: Rebase from Bluefin-DX to base-nvidia

*Status: in progress*

#### Problem

The image based on Bluefin-DX (`bluefin-dx-nvidia-open:gts`) pulled in
four layers of upstream packages (ublue-os/main → Bluefin base →
Bluefin-DX) then immediately stripped most of them: GNOME Shell, GDM,
Homebrew, and all GNOME extensions. Packages never referenced by the
build — Docker, Cockpit, ROCm, Incus/LXC, Samba/AD/Kerberos, backup
tools — added image size and attack surface for no benefit.

#### Design

The image rebases onto `ghcr.io/ublue-os/base-nvidia:gts`, the lowest
Universal Blue layer that includes Nvidia drivers. This image ships no
desktop environment, no display manager, and no application-layer
packages.

Changes from the previous base:

- GNOME removal (S1) and Homebrew removal (S2) become no-ops.
- VS Code (S14) is installed directly from Microsoft's yum repo.
- `nvidia-container-toolkit` is no longer installed by the build — the
  base image provides it.
- `xdg-desktop-portal-gtk` is no longer installed by the build — the
  base image provides it.
- `tailscaled.service` is no longer enabled. Trayscale Flatpak and its
  `/run/tailscale` override are removed.
- `fish` is added to the package install (previously inherited from
  Bluefin base).

### S17: Automated releases

*Status: in progress*

release-please generates semver tags and a CHANGELOG from conventional
commits. Configuration uses the `simple` release type (`version.txt` +
`CHANGELOG.md`).

Three workflows support the release lifecycle:

- **release-please.yml** — runs on push to main. Opens or updates a
  release PR. When the PR merges, creates a GitHub Release with a
  semver tag.
- **auto-merge-release.yml** — auto-merges release PRs opened by
  release-please after CI passes.
- **build.yml** — adds semver tags to the container image when a git
  tag exists on the commit (e.g., `ghcr.io/.../tilefin-nvidia-open:0.4.0`).

Daily and push builds continue producing `latest` and date-stamped
tags. Semver tags are additive — they appear only when a release is cut.

Version history: 0.1.0 (Sway on Bluefin-DX), 0.2.0 (Hyprland on Bluefin-DX), 0.3.0 (Niri on
Bluefin-DX), 0.4.0 (Niri on base-nvidia).

### S18: Install media

*Status: in progress*

#### Problem

The image is consumed via `bootc switch` from a running Fedora system.
This requires an existing installation to migrate from — there is no
path to bare-metal install on a new machine.

#### Design

bootc-image-builder (BIB) produces installable disk images from the
container image. Two ISO types serve different use cases:

| Type | Config | Network | Use case |
|---|---|---|---|
| `iso` (bootc-installer) | `disk_config/iso.toml` | Not required | Offline install from USB/Ventoy. Image embedded in ISO. |
| `anaconda-iso` | `disk_config/anaconda-iso.toml` | Required | Interactive Anaconda installer. Pulls image from GHCR at install time. |

Offline-first: the `iso` type is the primary install path. A user
copies the ISO to a Ventoy USB drive and boots it. No network, no
intermediate OS, no migration step.

The Anaconda ISO provides a graphical installer with disk, user,
timezone, and network configuration. It suits environments where
network access is available and interactive setup is preferred.

Both types use a 20 GiB minimum root filesystem on btrfs.

#### R18.1: Offline bootc-installer ISO

BIB produces an `iso` type image that embeds the full container image.
The ISO is bootable without network access.

#### R18.2: Anaconda ISO

BIB produces an `anaconda-iso` type image with a graphical Anaconda
installer. The RHEL Subscription module is disabled. All other
Anaconda modules use their defaults.

#### R18.3: CI builds both types

The `build-disk.yml` workflow matrix includes `iso` and `anaconda-iso`
alongside `qcow2`. Each type maps to its own config file. Builds run
on `workflow_dispatch` and on PRs that touch disk config or the
workflow itself.

#### R18.4: Local build recipes

The Justfile provides `build-iso` (offline) and `build-anaconda-iso`
(network) recipes. Both delegate to BIB via `_build-bib` with the
appropriate type and config file.

## Out of scope

- **User dotfiles**: Managed by chezmoi in a separate repo. This image
  provides system-wide defaults via `/etc/skel/`, `/etc/xdg/`, and
  `/etc/profile.d/`. Users override in `~/.config/`.
- **Userbox Containerfile**: Lives in repentsinner/userbox. This spec
  covers the image-side changes only (R12.1–R12.5).
- **Flutter/FVM**: Future addition to the userbox Containerfile.
- **Flatpak apps beyond Bitwarden**: User-installed via
  `flatpak install --user`.
