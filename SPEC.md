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

### S19: AJA Corvid44 kernel module

*Status: complete*

#### Problem

The AJA Corvid44 is a professional SDI video I/O PCIe card used for
broadcast capture and playout. Its Linux kernel driver (`ajantv2.ko`)
is not packaged for any distribution — it must be built from source.
On an immutable bootc/OSTree system, kernel modules cannot be compiled
at runtime because `/usr/lib/modules` is read-only. The module must be
baked into the image at build time.

#### Design

The Containerfile adds a multi-stage build that compiles `ajantv2.ko`
from the [aja-video/libajantv2](https://github.com/aja-video/libajantv2)
source tree against the kernel headers shipped by the base image. The
compiled module is copied into the final image layer and registered
with `depmod`.

This follows the same pattern Universal Blue uses for NVIDIA modules:
build at image time, ship pre-compiled, rebuild automatically when the
base image updates (new kernel).

Only the kernel driver is built — the userspace library (`libajantv2`)
and SDK tools are out of scope for the image. Applications that need
the userspace SDK can install it in a distrobox.

#### R19.1: Kernel module built at image time

A Containerfile build stage installs `kernel-devel`, `gcc`, and `make`,
clones the libajantv2 source, and builds `ajantv2.ko` using the
driver's Makefile with `KVERSION` set to match the base image kernel.
The `.ko` file is installed to
`/usr/lib/modules/<kversion>/extra/ajantv2/` in the final image.
`depmod` runs after installation.

Build dependencies (`kernel-devel`, `gcc`, `make`, `git`) exist only
in the build stage and do not appear in the final image.

Rationale: the driver Makefile supports cross-compilation via
`KVERSION` — the module builds for a target kernel without requiring
that kernel to be running. This is exactly the container build use
case.

#### R19.2: Module auto-loads at boot

A `modules-load.d` configuration file (`/etc/modules-load.d/ajantv2.conf`)
causes `ajantv2` to load automatically at boot. The driver creates
`/dev/ajantv2*` device nodes on load.

#### R19.3: GPU Direct RDMA support

The `ajantv2.ko` module is compiled with GPU Direct RDMA enabled
(`AJA_RDMA=1`). This allows zero-copy DMA between the Corvid44 and
NVIDIA GPU memory, bypassing system RAM.

Use case: SDI capture → GPU tensor processing → SDI output. Without
RDMA, each direction requires a CPU-mediated copy through system
memory (two PCIe hops per frame). With RDMA, frames transfer
directly between the AJA card and GPU (one hop, zero CPU involvement).

RDMA is not a separate kernel module. The AJA Makefile compiles RDMA
support into `ajantv2.ko` when `AJA_RDMA=1` is set. The build
requires `nv-p2p.h` from NVIDIA's
[open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules)
source tree (`kernel-open/nvidia-peermem/nv-p2p.h`).

The build stage detects the installed NVIDIA driver version from
the base image's kernel modules and fetches `nv-p2p.h` from the
corresponding open-gpu-kernel-modules tag.

At runtime the AJA RDMA code calls `nvidia_p2p_get_pages()`,
`nvidia_p2p_dma_map_pages()`, and related functions exported by
`nvidia.ko`. These are NVIDIA's PCIe peer-to-peer DMA APIs — they do
not require `nvidia-peermem`. The `nvidia-peermem` module is an
InfiniBand/Mellanox peer memory bridge for network RDMA (e.g.,
Rivermax GPUDirect over Ethernet); the AJA driver's PCIe P2P path
is independent of it.

### S20: Rivermax ST2110 streaming

*Status: future work*

#### Problem

The machine has a Mellanox ConnectX-6 NIC capable of hardware-
accelerated SMPTE ST 2110 media transport via NVIDIA Rivermax. Rivermax
GPUDirect RDMA allows zero-copy packet I/O between the ConnectX NIC and
GPU memory over Ethernet — the network-side complement to the AJA
card's PCIe P2P path (S19).

#### Rivermax SDK requirements (v1.81.21)

Rivermax hard-requires DOCA-Host (v2.10.0-0.5.3) on the host. Three
DOCA profiles are compatible:

| Profile | Scope |
|---|---|
| `doca-roce` | Minimal Ethernet/RoCE kernel drivers (replaces `MLNX_EN`) |
| `doca-ofed` | DOCA-OFED drivers and tools (replaces `MLNX_OFED`) |
| `doca-all` | Full DOCA-Host libraries |

The Rivermax SDK ships pre-built for RHEL 9.2 and Ubuntu 24.04.
Fedora is not a supported target. The SDK is a vendored tarball
containing shared libraries, demo applications (`media_sender`,
`media_receiver`, `generic_sender`, `generic_receiver`), a dev kit,
and CMake components. It requires a license file at
`/opt/mellanox/rivermax/rivermax.lic` (or via
`RIVERMAX_LICENSE_PATH`).

#### GPUDirect in Rivermax

Rivermax GPUDirect uses CUDA to allocate GPU memory (must reside in
PCIe BAR1), then passes pointers to the Rivermax API. The NIC
reads/writes GPU memory directly. The v1.81.21 docs reference "CUDA
Toolkit Documentation -> GPUDirect RDMA" for setup — which is the
`nvidia-peermem` + IB verbs path (`ibv_reg_mr()`).

**Rivermax v1.81.21 does not support kernel DMA-BUF
(`ibv_reg_dmabuf_mr`).** Neither the installation guide nor the user
manual mentions DMA-BUF. The NVIDIA GPU Operator docs recommend
DMA-BUF for GPUDirect RDMA generally, but Rivermax has not adopted
it as of this version.

#### GPU memory registration: background

Linux offers two mechanisms for an RDMA NIC to access GPU memory:

| | nvidia-peermem (legacy) | DMA-BUF (standard) |
|---|---|---|
| Verbs call | `ibv_reg_mr()` on GPU pointer | `ibv_reg_dmabuf_mr()` on dma-buf fd |
| Kernel mechanism | Proprietary NVIDIA peer memory API registered into IB verbs | Standard Linux `dma-buf` fd sharing (kernel 5.12+) |
| NIC driver requirement | MLNX_OFED or DOCA-OFED | Inbox `rdma-core` sufficient |
| GPU requirement | Any data center GPU | Turing+ with open kernel modules |
| NVIDIA recommendation | Legacy | **Recommended** |

DMA-BUF would avoid the DOCA-OFED dependency entirely — the image
already meets its kernel/driver prerequisites (kernel 6.19, open
NVIDIA driver 595.45.04, Turing+ GPU, inbox `rdma-core`). But since
Rivermax does not use it, this path is blocked on NVIDIA updating
the SDK.

The ublue `kmod-nvidia` build compiles `nvidia-peermem` as a non-
functional stub (`NV_MLNX_IB_PEER_MEM_SYMBOLS_PRESENT` undefined)
because the build environment lacks DOCA-OFED headers. This stub
returns `-EINVAL` on load. AJA RDMA (S19) is unaffected — it uses
NVIDIA's PCIe P2P API (`nvidia_p2p_*` from `nvidia.ko`) directly,
bypassing IB verbs.

#### Design

Rivermax userspace runs in a container. The host provides kernel
drivers and `nvidia-peermem`.

```
Host (tilefin-nvidia-open):
  ├─ doca-roce or doca-ofed kernel drivers (replaces inbox mlx5)
  ├─ nvidia-peermem.ko (rebuilt with DOCA-OFED headers)
  └─ nvidia.ko, nvidia-uvm.ko (from ublue kmod-nvidia, unchanged)

Container (Rivermax workload):
  ├─ Rivermax SDK + libs (from vendored tarball)
  ├─ CUDA toolkit
  ├─ demo apps (media_sender, media_receiver, etc.)
  └─ rivermax.lic bind-mounted from host
```

Host-side changes required:

1. **Replace inbox Mellanox kernel driver with DOCA-OFED.** The inbox
   `mlx5_core` from Fedora's kernel must be replaced (or overlaid)
   with DOCA's version. At minimum `doca-roce` profile. DOCA packages
   are published for RHEL — Fedora compatibility is unverified.
2. **Rebuild `nvidia-peermem.ko`** with DOCA-OFED headers present so
   `NV_MLNX_IB_PEER_MEM_SYMBOLS_PRESENT` is defined. This can follow
   the same Containerfile build-stage pattern as AJA (S19): compile
   from NVIDIA open-gpu-kernel-modules source, overlay the `.ko` on
   top of the stub from `kmod-nvidia`.
3. **`modules-load.d` entry for `nvidia-peermem`** once the module is
   functional.

A related project
([Fuse-Technical-Group/bluefin-gdx-doca](https://github.com/Fuse-Technical-Group/bluefin-gdx-doca))
has explored the full DOCA stack on CentOS Stream 10 (bluefin-gdx:lts
base). That project installs `doca-all`, `doca-roce`, `rivermax`, and
`rivermax-utils` directly into the image via the Mellanox yum repo.

#### Open questions

- Can DOCA-OFED kernel packages (built for RHEL) install on Fedora
  42's kernel, or does Fedora's kernel ABI diverge too far?
- Is `doca-roce` sufficient, or does Rivermax GPUDirect require
  `doca-ofed`?
- Can the DOCA kernel drivers coexist with ublue's `kmod-nvidia`, or
  do they conflict on `nvidia-peermem`?
- Resizable BAR (per-machine BIOS setting) controls how much GPU
  memory the NIC can access for GPUDirect. Without it, BAR1 is
  256 MB regardless of GPU VRAM. This limits the total GPU memory
  registerable with the NIC at once — constraining the number of
  concurrent streams, not per-stream throughput. For low-latency
  broadcast use cases with shallow ring buffers, 256 MB is likely
  sufficient for a small number of streams.

Requirements to be specified after resolving DOCA-OFED packaging on
Fedora bootc.

### S21: NVIDIA DRM modesetting

*Status: in progress*

#### Problem

The rebase from Bluefin-DX to base-nvidia (S15) dropped
`nvidia-drm.modeset=1` from kernel args. Bluefin-DX passed it on the
command line; base-nvidia does not. Without DRM modesetting, NVIDIA
cannot properly manage display power states. Display DPMS power cycling
(especially DSC link retraining on 5K displays) corrupts GPU contexts,
causing:

- Electron apps (VS Code, Bitwarden) crash with SIGILL after display
  wakes from sleep.
- Hyprlock renders a flat magenta/red field instead of a blurred
  screenshot after extended display sleep.

#### Design

A `bootc kargs.d` file (`30-nvidia-drm.toml`) adds
`nvidia-drm.modeset=1` to kernel arguments, following the same pattern
as `10-iommu.toml` and `20-verbose-boot.toml`.

The base image already ships `NVreg_PreserveVideoMemoryAllocations=1`
in `/usr/lib/modprobe.d/nvidia.conf` — no additional modprobe
configuration is needed.

#### R21.1: DRM modesetting kernel arg

`/usr/lib/bootc/kargs.d/30-nvidia-drm.toml` sets
`nvidia-drm.modeset=1`. The arg appears in `/proc/cmdline` after reboot.

### S22: Manual system suspend

*Status: in progress*

#### Problem

The nwg-bar power menu provides Lock, Logout, Reboot, and Shutdown but
no suspend option. Users must run `systemctl suspend` manually.

Auto-suspend via hypridle remains intentionally disabled — an
unattended suspend during long-running builds or VM workloads is
destructive. Manual suspend via the power menu gives the user explicit
control.

#### Design

nwg-bar gains a Sleep button between Lock and Logout. The button runs
`systemctl suspend`. The icon (`system-suspend.svg`) ships with the
nwg-bar package.

#### R22.1: Sleep button in nwg-bar

The nwg-bar config (`bar.json`) includes a Sleep entry that runs
`systemctl suspend`, positioned between Lock and Logout.

## Out of scope

- **User dotfiles**: Managed by chezmoi in a separate repo. This image
  provides system-wide defaults via `/etc/skel/`, `/etc/xdg/`, and
  `/etc/profile.d/`. Users override in `~/.config/`.
- **Userbox Containerfile**: Lives in repentsinner/userbox. This spec
  covers the image-side changes only (R12.1–R12.5).
- **Flutter/FVM**: Future addition to the userbox Containerfile.
- **Flatpak apps beyond Bitwarden**: User-installed via
  `flatpak install --user`.
