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

- **bmd-justfile-import**: `build.sh` copies `bmd.just` to
  `61-bmd.just` but nothing imports it — `ujust bmd-install` is
  invisible. Introduce `60-custom.just` as an import shim: rename
  `tilefin.just` install to `61-tilefin.just`, `bmd.just` to
  `62-bmd.just`, and create `build_files/60-custom.just` with
  `import?` lines for both. Update `build.sh` cp lines.
  Files: `build_files/60-custom.just` (new), `build_files/build.sh`.

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

## Sunshine streaming server (S13)

- **sunshine-research**: Research Sunshine packaging on Fedora, Niri/
  Wayland compatibility, and required system integrations (udev, KMS,
  NVENC). Write spec requirements in S13 before implementation.
  Blocked — requirements not yet specified. Unblocked when S13 spec
  is written.
