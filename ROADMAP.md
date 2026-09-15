# ROADMAP

Planned work derived from SPEC.md. Sections in build-dependency order.
Completed work is removed — see CHANGELOG.md for history.

## Dual-channel image publishing §road:image-channels

### Semver provenance in image tags §road:build-channel-tags

Add a workflow step that reads `version.txt` into a step output. Update
`docker/metadata-action` tags: replace `latest.YYYYMMDD` and bare
`YYYYMMDD` with `latest.v<version>.<YYYYMMDD>`. Add `stable` and
`<version>` tags for `v*` tag builds. Remove `<major>.<minor>` tag. Set
`org.opencontainers.image.version` label to semver.
Files: `.github/workflows/build.yml`.
§spec:daily-tag-provenance §spec:oci-version-label

### Widen the push and signing gate §road:build-push-gate

Widen the push-to-GHCR and cosign-signing `if` conditions to allow
`refs/tags/v*` in addition to the default branch. Depends on
§road:build-channel-tags.
Files: `.github/workflows/build.yml`.
§spec:tag-builds-stable-channel

**Verify:** A `v*` tag push publishes `stable` and `<version>` to GHCR,
signed.

## EGL-Wayland platform plugin §road:egl-wayland

### Ship egl-wayland in the image §road:egl-wayland-package

Add `egl-wayland` to the `WAYLAND_CORE` package group in
`build_files/build.sh` so NVIDIA's EGL can handle
`EGL_PLATFORM_WAYLAND` display requests. No dependencies.
Files: `build_files/build.sh`.
§spec:egl-wayland-installed

**Verify:** The built image contains
`/usr/lib64/libnvidia-egl-wayland.so.1` and
`/usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json`.

## Sunshine streaming server §road:sunshine

### Research Sunshine on Fedora and Niri §road:sunshine-research

Research Sunshine packaging on Fedora, Niri/Wayland compatibility, and
required system integrations (udev, KMS, NVENC). Write spec
requirements in §spec:sunshine before implementation. Blocked —
requirements not yet specified. Unblocked when the §spec:sunshine
requirements are written.

## Cross-release bootc switch §road:cross-release-switch

### Identify what re-applies the store label §road:selinux-relabel-writer

Establish what writes `semanage_store_t` onto `/etc/selinux/targeted`
after `restorecon` has corrected it. A relabel pass touching `mtab`,
`os-release`, `resolv.conf`, `credstore`, `pam.d`, `polkit-1/rules.d`
and `selinux/targeted` runs within a single coarse-clock tick early in
boot; no systemd unit in the image invokes `semodule`, `semanage`,
`setsebool`, `restorecon` or `fixfiles`, so the writer is elsewhere.
Candidates not yet excluded: PID 1's own early relabel, libsemanage
recovery of the interrupted transaction whose `tmp` and `final`
directories are present, and the ostree deployment path.
§spec:cross-release-switch

Retest the switch first. §spec:base-image now tracks `:latest`, so a
switch from Bluefin `:stable` is Fedora 44 onto Fedora 44 rather than
backwards across a release. That costs one reboot on mr-plywood and
may retire this workstream outright.

**Verify:** If the same-release switch still mislabels the store, an
audit watch (`-w /etc/selinux/targeted -p a`) or equivalent names the
writing process across a boot. The finding either identifies a repair
that survives, or establishes that switching onto this image is
unsupportable and install media is the only path.

## GPUDirect Storage over network filesystems §road:gpudirect-storage

### Build and ship nvidia-fs.ko §road:nvfs-network-fs

Build and ship `nvidia-fs.ko` so the `nvfs` path is available for
distributed filesystems — Lustre, WekaFS, EXAScaler, GPFS, NFS over
RDMA. The `p2pdma` path §spec:gpudirect-storage once shipped cannot reach
them: it covers NVMe block devices only, and NVIDIA scopes the no-module
exemption to "mounts of NVMe (local or with NVIDIA DOCA SNAP)". No amount
of tuning that setup substitutes, which is part of why it was backed out
on 2026-08-31 rather than maintained against a workload it cannot serve.

Blocked — no such workload yet. The build recipe (one driver header,
symbol CRCs from the shipped `nvidia.ko`, `kernel-devel` from
`updates-archive`) and the three standing costs are recorded under
§spec:gpudirect-storage. The `nvfs` path may also want DOCA's NVMe
patches, and DOCA does not target Fedora; verify that before planning
around it.

## Rootless container enabling config §road:rootless-k8s-enabling

### Probe cgroup delegation on base-nvidia §road:cgroup-delegation-probe

Determine whether base-nvidia already delegates cgroup v2 controllers
(`cpu`, `cpuset`, `io`, `memory`) to the user session. On a running
image, check
`cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/.../cgroup.controllers`
and `systemctl cat user@.service`. If delegation is absent, add a
`user@.service.d` drop-in. This gates the rest of the section.
Files: `build_files/build.sh` (and a drop-in conf if needed).
§spec:rootless-k8s-enabling

**Verify:** The delegated controllers appear in the user slice's
`cgroup.controllers` on a booted image.

### Select podman as the kind provider §road:kind-podman-enabling

Export `KIND_EXPERIMENTAL_PROVIDER=podman` system-wide via
`/etc/environment.d/`, matching the electron-wayland pattern
(§spec:wayland-config), and add any further sysctls `kind` needs beyond
the inotify cap (§spec:inotify-instance-cap) under
`/usr/lib/sysctl.d/`. Depends on §road:cgroup-delegation-probe.
Files: `build_files/build.sh`, new `kind-provider.conf`,
new sysctl `.conf`.
§spec:rootless-k8s-enabling

**Verify:** With the Kubernetes clients installed by `setup-user`
(§spec:k8s-clients), `kind create cluster` succeeds rootless on podman
and `kubectl get nodes` reports Ready. `printenv
KIND_EXPERIMENTAL_PROVIDER` reads `podman` in a fresh shell. The compose
provider is no longer part of this workstream — it ships in the image
(§spec:compose-provider).
