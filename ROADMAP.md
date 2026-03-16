# ROADMAP

Planned work derived from SPEC.md. Sections in build-dependency order.
Completed work is removed — see CHANGELOG.md for history.

## AJA Corvid44 kernel module (S19)

- **aja-kmod-build-stage**: Add a Containerfile build stage that
  compiles `ajantv2.ko` from aja-video/libajantv2 source against
  the base image's kernel headers. COPY the `.ko` into the final
  image under `/usr/lib/modules/<kversion>/extra/ajantv2/` and run
  `depmod`. Pin to a release tag (not `main`) for reproducibility.
  Files: `Containerfile`.

- **aja-kmod-autoload**: Add `/etc/modules-load.d/ajantv2.conf` so
  the module loads at boot. Add the config file to `build_files/`
  and copy it in `build.sh`.
  Depends on **aja-kmod-build-stage**.
  Files: `build_files/ajantv2-modules-load.conf`, `build_files/build.sh`.

## Dynamic GPU detection (S16)

- **niri-gpu-detect**: Move Nvidia env vars from `niri-config.kdl` to
  `niri-session.sh` behind a DRM connector detection check. Remove
  `WLR_NO_HARDWARE_CURSORS`.
  Files: `build_files/niri-config.kdl`, `build_files/niri-session.sh`.

## Sunshine streaming server (S13)

- **sunshine-research**: Research Sunshine packaging on Fedora, Niri/
  Wayland compatibility, and required system integrations (udev, KMS,
  NVENC). Write spec requirements in S13 before implementation.
  Blocked — requirements not yet specified. Unblocked when S13 spec
  is written.
