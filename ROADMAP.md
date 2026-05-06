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

- **build-needs-fix**: Fix `build_push` skip cascade on non-PR events.
  The `changes` job is PR-only; `build_push` declares `needs: [changes]`
  which causes it to skip on tag pushes, schedule, and workflow_dispatch.
  Add `if: always()` to `build_push` and adjust the existing `if`
  condition to handle the skipped `changes` output. Verify with a
  `workflow_dispatch` or tag push that `build_push` runs.
  Files: `.github/workflows/build.yml`.

- **build-channel-tags**: Add a workflow step that reads `version.txt`
  into a step output. Update `docker/metadata-action` tags: replace
  `latest.YYYYMMDD` and bare `YYYYMMDD` with
  `latest.v<version>.<YYYYMMDD>`. Add `stable` and `<version>` tags
  for `v*` tag builds. Remove `<major>.<minor>` tag. Set
  `org.opencontainers.image.version` label to semver.
  Depends on **build-needs-fix**.
  Files: `.github/workflows/build.yml`.

- **build-push-gate**: Widen the push-to-GHCR and cosign-signing `if`
  conditions to allow `refs/tags/v*` in addition to the default
  branch. Depends on **build-channel-tags**.
  Files: `.github/workflows/build.yml`.

## EGL-Wayland platform plugin (S24)

- **egl-wayland-package**: Add `egl-wayland` to the `WAYLAND_CORE`
  package group in `build_files/build.sh` so NVIDIA's EGL can handle
  `EGL_PLATFORM_WAYLAND` display requests. Verifiable when the built
  image contains `/usr/lib64/libnvidia-egl-wayland.so.1` and
  `/usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json`.
  No dependencies, but won't reach users until S23 republishes images.
  Files: `build_files/build.sh`.

## Production-mode update lock (S25)

- **production-mode**: Ship a `ConditionPathExists=!/etc/tilefin/production-mode`
  drop-in for `rpm-ostreed-automatic.service`, a `ujust production-mode
  --start | --stop | --start-from-current` recipe (interactive when a
  deployment is already staged at `--start` time, prompting keep vs.
  unstage via gum), and a waybar update-check extension that prefixes
  the module text with `production` or `development` and adds a
  `Mode:` line to the tooltip. The drop-in installs to
  `/usr/lib/systemd/system/rpm-ostreed-automatic.service.d/` so it
  ships read-only with the image; the flag file lives in `/etc` so
  it persists per-machine across image upgrades. No dependencies.
  Files: new `build_files/rpm-ostreed-automatic-production.conf`,
  `build_files/build.sh`, `build_files/tilefin.just`,
  `build_files/update-check.sh`.

  **Verify:** Build the image, rebase, and reboot. Confirm the
  waybar update module reads `development · <age>` with `Mode:
  development` in the tooltip. Run `ujust production-mode --start`;
  confirm `/etc/tilefin/production-mode` exists, the waybar text
  switches to `production · <age>`, and the tooltip shows `Mode:
  production`. Run `sudo systemctl start rpm-ostreed-automatic.service`;
  confirm `systemctl status rpm-ostreed-automatic.service` reports
  the `ConditionPathExists` is unmet and no new deployment is staged
  (`rpm-ostree status` shows no staged entry). Run `sudo bootc upgrade
  --check` (or `rpm-ostree update --preview`); confirm manual update
  paths still work. Run `ujust production-mode --stop`; confirm the
  flag file is removed and the next service start stages updates as
  before. Re-stage a deployment manually, then run `ujust
  production-mode --start` again; confirm the recipe surfaces the
  staged version interactively. Run `ujust production-mode
  --start-from-current` while a deployment is staged; confirm the
  staged deployment is unstaged and the booted image remains the
  default for next reboot.

## Sunshine streaming server (S13)

- **sunshine-research**: Research Sunshine packaging on Fedora, Niri/
  Wayland compatibility, and required system integrations (udev, KMS,
  NVENC). Write spec requirements in S13 before implementation.
  Blocked — requirements not yet specified. Unblocked when S13 spec
  is written.
