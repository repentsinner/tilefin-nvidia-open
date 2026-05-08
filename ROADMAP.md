# ROADMAP

Planned work derived from SPEC.md. Sections in build-dependency order.
Completed work is removed — see CHANGELOG.md for history.

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

## Sunshine streaming server (S13)

- **sunshine-research**: Research Sunshine packaging on Fedora, Niri/
  Wayland compatibility, and required system integrations (udev, KMS,
  NVENC). Write spec requirements in S13 before implementation.
  Blocked — requirements not yet specified. Unblocked when S13 spec
  is written.

## Release workflow hygiene (S17)

- **auto-merge-release-trigger-fix**: Stop `auto-merge-release.yml`
  from generating 0-second failure runs on every push event. The
  workflow declares only `on: pull_request`, yet GitHub creates
  push-event runs that surface the file path (not the friendly
  workflow name) as the run identifier, with zero jobs and a
  `failure` conclusion. The pattern repeats across main, release-
  please branches, and feature branches — every push leaves a red
  mark in the Actions tab and erodes the signal value of CI status.
  The job `if:` references `github.event.pull_request.labels.*.name`,
  which is undefined on push events; restructure the trigger or guard
  the `if:` so push-event runs are either not created or cleanly
  skipped. The fix must not regress the actual auto-merge behavior
  on release-please PRs (S17). Verify by pushing a no-op commit to a
  branch and to main and confirming the workflow either produces no
  run or a clean `skipped` run for each push.
  Files: `.github/workflows/auto-merge-release.yml`.
