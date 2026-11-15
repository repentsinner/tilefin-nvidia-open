# Tilefin

Tilefin is an image-based desktop operating system for NVIDIA workstations.
It provides a keyboard-driven tiling desktop, updates as one image that
applies on the next reboot, and keeps development tools outside the
image so they update on their own schedule.

## Design choices

| Choice | Reason |
| --- | --- |
| **[Universal Blue](https://github.com/ublue-os)'s [base-nvidia](https://github.com/ublue-os/main) as the base** | It provides Fedora with NVIDIA's open kernel modules and no desktop environment, so every desktop package in the image is an explicit choice. |
| **[Niri](https://github.com/niri-wm/niri) as the compositor** | Niri scales fractionally through `wp-fractional-scale-v1`, which keeps text sharp at 1.25x or 1.5x. Windows tile in a horizontal strip that scrolls, so each column keeps its width however many windows are open. The image installs a release build of a niri fork that adds a window desaturation rule. |
| **A Wayland session** | X11 applications run through xwayland-satellite, which niri starts when an X11 client connects. |
| **Silent notifications** | Mako keeps notifications in its history without showing popups, and a waybar indicator shows when some are waiting. |
| **Focus follows the mouse** | Moving the pointer focuses a window. Keyboard navigation works alongside it. |
| **Tools outside the image** | The image carries only the tools its own configuration calls. Standalone tools install per user, and development toolchains live in a distrobox container, so neither waits on an image update. |

## Goals

1. **Reproducibility.** An immutable system image whose packages are listed
   and auditable.
2. **Reliability.** A tiling desktop that behaves the same on every boot.
3. **Visual quality.** Sharp text and UI at fractional scales on high-DPI
   displays.
4. **NVIDIA support.** Full use of NVIDIA GPUs, for the desktop, for CUDA,
   and for passing a GPU to a virtual machine.
5. **Keyboard-driven work.** Window management that needs no mouse.
6. **Clean separation.** The image holds the session and the tools its
   configuration calls; everything else installs per user or in a
   container.

## What the image includes

The base image (`base-nvidia:latest`, which tracks the current Fedora
release) provides Fedora, NVIDIA's open kernel modules, Podman, distrobox,
just and ujust, Flatpak with Flathub, WireGuard tools, and media codecs.
This image adds the following.

### Desktop

- **Status bar:** Waybar
- **Application launcher:** Fuzzel
- **Terminal:** Ptyxis (GTK 4, GPU-accelerated, with container integration)
- **Lock screen:** Hyprlock
- **Idle management:** hypridle
- **Notifications:** Mako
- **Screenshots:** Grim and Slurp
- **Screen recording:** wf-recorder
- **Wallpaper:** swaybg
- **File manager:** Thunar
- **Display layout:** wdisplays
- **Utilities:** wl-clipboard, cliphist, pamixer, brightnessctl

### Login

The greeter is tuigreet, run by greetd on the console. It starts the niri
session directly. The greeter's account and directories come from
sysusers.d and tmpfiles.d, which suit an image-based system.

### Theme

GTK 3 and GTK 4 applications use **adw-gtk3-dark** with the dark color
scheme preferred. The settings live in `/etc/skel`, so every new user
starts with them.

### System configuration

- **Polkit agent:** lxpolkit, started with the session.
- **Portals:** xdg-desktop-portal-gtk handles file choosers and other
  portal requests.
- **Input:** Caps Lock acts as Control, and touchpads scroll naturally.
- **Containers:** the Podman socket is enabled.
- **Virtualization:** KVM, QEMU and libvirt, with virt-manager and the
  Looking Glass client for viewing a VM that has a passed-through GPU.
- **Mesh VPN:** Tailscale, with its daemon enabled.
- **GPU selection:** the session points rendering at the NVIDIA GPU only
  when an NVIDIA GPU drives a monitor and the machine isn't set up to pass
  that GPU to a VM. Otherwise applications render on the integrated GPU.

## Install

### Install on a new machine

The installer is an ISO built from the image. It runs Anaconda, which asks
for the target disk and creates the user account.

1. On GitHub, open **Actions**, select **Build disk images**, and run it.
   When the run finishes, download the ISO from the run's artifacts. To
   build it locally instead, run `just build-iso` in a checkout of this
   repository.
2. Write the ISO to a USB drive and boot from it.
3. Choose the disk and create your account when Anaconda asks.

The installed system updates from the published image, not from the USB
drive.

### Switch an existing system

From any bootc-based system:

```bash
sudo bootc switch ghcr.io/repentsinner/tilefin-nvidia-open
sudo reboot
```

## Set up

### Set up your user environment

On first login, provision the per-user tools, applications and development
container:

```bash
ujust setup-user
```

The recipe offers a menu of:

- **Standalone tools**, installed into `~/.local/bin`: Claude Code, uv,
  mise, `gh`, `chezmoi` and the lint gates (`shellcheck`) are selected by
  default. The Kubernetes clients (`kubectl`, `helm`, `kind`, `talosctl`,
  `kubeseal`, `mc`) are optional and install through mise.
- **Flatpak applications:** Firefox, Bitwarden, Slack, Discord, Signal,
  Proton VPN, and Trayscale.
- **The userbox:** a distrobox container that carries development
  toolchains needing a full Fedora userland. It exports `fvm`, the Flutter
  version manager, to `~/.local/bin`.

The shell tools behind the image's aliases and prompt (`bat`, `eza`,
`zoxide`, `direnv`, `starship`, `rbw`) ship in the image and need no
setup.

To assemble the userbox from a different image:

```bash
ujust setup-user ghcr.io/youruser/yourbox:latest
```

Then bootstrap chezmoi for dotfiles. The chezmoi-managed systemd unit
reassembles the userbox on each login from then on:

```bash
chezmoi init --apply <your-dotfiles-repo>
```

### Join a tailnet

Enrolling the machine is an account action, so the image leaves it to you:

```bash
sudo tailscale up
sudo tailscale set --operator=$USER
```

The second command lets your user talk to the Tailscale daemon, which
Trayscale needs.

### Configure WireGuard

Configure WireGuard connections through NetworkManager with `nmcli`.
NetworkManager also reports their status.

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

#### Choose a channel

The image is published on two channels:

- **`latest`** (the default) rebuilds from `main` every day and on every
  merge. Each build also gets a dated snapshot tag that names the release
  it builds on, such as `latest.v0.12.0.20261114`.
- **`stable`** moves only when a new release is tagged. Each release is
  also published under its version, such as `0.12.0`.

To move a machine to the stable channel, or to pin it to one release:

```bash
sudo bootc switch ghcr.io/repentsinner/tilefin-nvidia-open:stable
sudo bootc switch ghcr.io/repentsinner/tilefin-nvidia-open:0.12.0
```

To see what has been published, open the package's
[tagged versions](https://github.com/repentsinner/tilefin-nvidia-open/pkgs/container/tilefin-nvidia-open/versions?filters%5Bversion_type%5D=tagged).
The newest `latest.v…` tag is what a machine on `latest` gets next.
Snapshots are kept for 90 days and releases indefinitely.

### Idle and suspend

A machine runs in one of three modes. Each dims the display after four
minutes of idle time:

| Mode | Display off and lock | Automatic suspend | Automatic updates |
| --- | --- | --- | --- |
| Development (the default) | Yes | After 30 minutes idle, outside 08:00–18:00 on weekdays | Yes |
| Hot development | Yes | No | Yes |
| Production | No | No | No |

Hot development suits a development machine left running on purpose, such
as one running a long build overnight:

```bash
ujust hot-development --start
ujust hot-development --stop
```

Production mode is described under [Updates](#updates). When both are on,
production mode wins.

To suspend by hand in any mode, press **Super+Shift+L**. A USB keyboard,
mouse or wireless receiver wakes the machine, if the firmware allows
waking from USB.

### Virtual machines

To start, stop, or check a VM without opening virt-manager:

```bash
ujust vm start
ujust vm stop
ujust vm status
```

`stop` asks the guest to shut down and waits for it, so the guest can save
its work. If a guest hangs instead of shutting down, power it off with
`ujust vm stop --force`. When more than one VM is defined, add its name,
for example `ujust vm start win11`.

### Pass the NVIDIA GPU to a VM

A machine with an integrated GPU can hand its NVIDIA GPU to a VM, for
software that needs Windows and a real GPU. The desktop stays on the
integrated GPU, and Looking Glass shows the guest's screen in a window,
pixel for pixel. The NVIDIA GPU returns to Linux whenever the VM is off,
so CUDA work keeps it the rest of the time.

1. **Move the desktop to the integrated GPU.** Plug your monitor into the
   motherboard's video output, and set the integrated GPU as the primary
   display in the firmware setup. On MSI boards, set **Initiate Graphic
   Adapter** to **IGD**.
2. **Prepare the machine:**

   ```bash
   ujust setup-gpu-passthrough
   ```

   It checks the GPUs and the IOMMU, then asks before each change. When it
   finishes, log out and back in.
3. **Create the VM** in virt-manager on the **QEMU/KVM system** connection:
   UEFI firmware with Secure Boot, a virtio disk and network card, and the
   [virtio-win](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
   ISO attached for drivers. For Windows 11, choose it as the operating
   system so virt-manager adds the TPM. Install the guest, then the
   virtio guest tools from that ISO.
4. **Add the GPU and Looking Glass's shared memory.** With the VM off, add
   both of the NVIDIA GPU's functions (the GPU and its audio device) as
   PCI host devices, then add this to the VM's XML with
   `virsh --connect qemu:///system edit <vm>`:

   ```xml
   <shmem name='looking-glass'>
     <model type='ivshmem-plain'/>
     <size unit='M'>128</size>
   </shmem>
   ```

   If `setup-gpu-passthrough` reported guest address-width settings,
   rerun it and let it apply them to this VM.
5. **Install the guest software.** Start the VM and, inside it, install
   NVIDIA's driver for your GPU and the **Looking Glass B7 host** from
   [looking-glass.io](https://looking-glass.io/downloads). The host must be
   B7 to match the client in this image.
6. **Give the NVIDIA GPU a display.** Looking Glass captures what the GPU
   draws, and a GPU with no monitor draws nothing. Run a cable from the
   NVIDIA GPU to a second input on your monitor, or use a dummy plug.
7. **Remove the emulated display**, so the guest has only the real GPU:

   ```bash
   virt-xml --connect qemu:///system <vm> --edit --video model.type=none
   ```

From then on, start the VM with `ujust vm start` and open **Looking
Glass** from the launcher. It opens fullscreen on its own workspace:

- **Right Ctrl** releases the keyboard and mouse. Hold it with **Q** to quit
  the client, or with **F** to leave fullscreen.
- **Super+`** returns to the Looking Glass workspace.
- **Super+Shift+Escape** takes niri's shortcuts back from any app that has
  grabbed the keyboard.

Shut the guest down from inside it, or with `ujust vm stop`. If you shut
the host down with the guest still running, the host shuts the guest down
first and waits for it. The host won't sleep while the guest has the GPU,
because sleep cuts the GPU's power under the guest. To suspend, shut the
guest down first, then suspend the host. To keep the guest's open windows
across that, hibernate the guest instead of shutting it down: hibernation
saves its session to its own disk and powers it off, which hands the GPU
back.

#### Regain control when Looking Glass fails

The monitor cable shows the guest's screen but sends it no keyboard or
mouse input. To regain control, give the VM an emulated display again,
restart it, and use virt-manager's console:

```bash
virt-xml --connect qemu:///system <vm> --add-device --video virtio
ujust vm stop --force
ujust vm start
```

Remove the emulated display again (step 7) once Looking Glass works.

### Blackmagic capture cards

The DeckLink drivers come from Blackmagic as a Desktop Video for Linux
download. To build and install the kernel modules, firmware and tools from
that download:

```bash
ujust bmd-install <path-to-the-Desktop-Video-tarball>
```

The modules build against the running kernel. To remove them:

```bash
ujust bmd-uninstall
```

### Customize niri

The image's niri configuration lives in `/etc/niri/config.kdl`. A file at
`~/.config/niri/config.kdl` replaces it entirely, so start yours by
including the image's configuration, then add your changes below it:

```kdl
include "/etc/niri/config.kdl"

// Your bindings, window rules and output settings follow.
```

That way, changes to the image's configuration still reach you after
updates. See the [niri wiki](https://github.com/niri-wm/niri/wiki) for the
configuration options.

### Key bindings

- **Super+/** shows the key bindings.
- **Super+Shift+Escape** takes niri's shortcuts back from an app that has
  grabbed the keyboard.

## Package management

On an immutable system, where a tool lands depends on what depends on it.
Anything the image's own configuration calls ships in the image, because
the configuration and the binary have to update together. Everything else
installs outside the image, so it updates without a rebuild or a reboot:

| Layer | For | Example |
| --- | --- | --- |
| **System image** | Session infrastructure, system services, and the binaries the image's own configuration and services call | Niri, greetd, libvirt, `starship`, `direnv`, `docker-compose` |
| **Per-user tools** (`~/.local/bin`) | Standalone command-line tools that nothing in the image refers to | Claude Code, uv, `gh`, `chezmoi`, and the Kubernetes clients through mise |
| **Distrobox** | Development toolchains that need a full distribution userland: packages, compilers, headers | The userbox (Flutter through `fvm`), or `distrobox create --image fedora:latest` |
| **Flatpak** | Sandboxed GUI applications | `flatpak install --user flathub org.gnome.Evince` |

`ujust setup-user` installs the per-user tools and assembles the userbox.

The ujust recipes ship in the image, in `/usr/share/ublue-os/just/`, and
update with it. Run `ujust --list` to see them.

## Contributing

The design decisions behind the image, with their reasons, are in
[SPEC.md](SPEC.md). Planned work is in [ROADMAP.md](ROADMAP.md), and
[CHANGELOG.md](CHANGELOG.md) lists what each release changed.

## Community resources

- [Universal Blue forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussion forums](https://github.com/bootc-dev/bootc/discussions)

## License

Tilefin is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
