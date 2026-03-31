# ROADMAP

Planned work derived from SPEC.md. Sections in build-dependency order.
Completed work is removed — see CHANGELOG.md for history.

## Remove AJA Corvid44 / add DeckLink support (S19)

- **remove-aja-containerfile**: Remove `aja-kmod-builder` build stage
  and AJA module install step from Containerfile. Remove
  `build_files/ajantv2-modules-load.conf`. Remove AJA modules-load
  copy and update memlock comment in `build.sh`.
  Files: `Containerfile`, `build_files/build.sh`,
  `build_files/ajantv2-modules-load.conf`.

- **decklink-justfile**: Add `ujust setup-decklink` recipe to
  `build_files/tilefin.just`. Accepts path to Blackmagic
  `desktopvideo` RPM. Installs RPM if not present, copies kernel
  module source to writable location, builds against running kernel
  headers (`KERNELDIR=/usr/src/kernels/$(uname -r)`), installs `.ko`
  files to `/var/lib/blackmagic-io/`, creates and enables a
  systemd user service to `insmod` at boot. Idempotent — safe to
  re-run after kernel updates. Depends on **remove-aja-containerfile**.
  Files: `build_files/tilefin.just`.

## Dynamic GPU detection (S16)

- **niri-gpu-detect**: Move Nvidia env vars from `niri-config.kdl` to
  `niri-session.sh` behind a DRM connector detection check. Remove
  `WLR_NO_HARDWARE_CURSORS`.
  Files: `build_files/niri-config.kdl`, `build_files/niri-session.sh`.

## Rivermax ST2110 streaming (S20)

- **doca-roce-fedora-probe**: Throwaway Containerfile build stage that
  attempts to install `doca-roce` from the Mellanox yum repo against
  Fedora 42's kernel-devel. Determines whether DOCA kernel modules
  compile on kernel 6.19+ with Fedora's glibc. Check `rpm -ql` output
  for `nvidia-peermem.ko` and `mlx5_core.ko` to assess coexistence
  with ublue `kmod-nvidia`. This gates all subsequent S20 work.

## Manual system suspend (S22)

- **manual-suspend**: Add Sleep button to nwg-bar power menu. Runs
  `systemctl suspend`. Icon: `system-suspend.svg` (ships with nwg-bar).
  Files: `build_files/nwg-bar.json`.

## Dual-channel image publishing (S23)

- **build-channel-tags**: Add a workflow step that reads `version.txt`
  into a step output. Update `docker/metadata-action` tags: replace
  `latest.YYYYMMDD` and bare `YYYYMMDD` with
  `latest.v<version>.<YYYYMMDD>`. Add `stable` and `<version>` tags
  for `v*` tag builds. Remove `<major>.<minor>` tag. Set
  `org.opencontainers.image.version` label to semver.
  Files: `.github/workflows/build.yml`.

- **build-push-gate**: Widen the push-to-GHCR and cosign-signing `if`
  conditions to allow `refs/tags/v*` in addition to the default
  branch. Depends on **build-channel-tags**.
  Files: `.github/workflows/build.yml`.

## Sunshine streaming server (S13)

- **sunshine-research**: Research Sunshine packaging on Fedora, Niri/
  Wayland compatibility, and required system integrations (udev, KMS,
  NVENC). Write spec requirements in S13 before implementation.
  Blocked — requirements not yet specified. Unblocked when S13 spec
  is written.
