#!/usr/bin/bash
# Behaviour test for the session wrapper's GPU environment
# (§spec:gpu-detection, §spec:passthrough-desktop-gpu). Runs the wrapper
# against a fake DRM tree and designation file, with stubs for the commands it
# calls; the stub niri-session prints the environment it would start with.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$ROOT/build_files/niri-session.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
for cmd in systemctl dbus-update-activation-environment; do
    printf '#!/usr/bin/bash\nexit 0\n' > "$STUB_BIN/$cmd"
done
printf '#!/usr/bin/bash\nenv\n' > "$STUB_BIN/niri-session"
chmod +x "$STUB_BIN"/*

fail=0
OUT=""

# reset : fresh fake DRM tree with no cards and no designation
reset() {
    CASE="$TMP/case.$RANDOM$RANDOM"
    mkdir -p "$CASE/drm" "$CASE/pci/drivers/nvidia" "$CASE/pci/drivers/i915"
}
# card <n> <driver> <connected|disconnected> : a card with one connector
card() {
    mkdir -p "$CASE/pci/dev$1" "$CASE/drm/card$1/card$1-DP-1"
    ln -s "../drivers/$2" "$CASE/pci/dev$1/driver"
    ln -s "../../pci/dev$1" "$CASE/drm/card$1/device"
    echo "$3" > "$CASE/drm/card$1/card$1-DP-1/status"
}
designate() { printf 'PASSTHROUGH_GPU=0000:01:00.0\nDESKTOP_GPU=0000:00:02.0\n' > "$CASE/gpu-passthrough.conf"; }
run() {
    OUT="$(env -i PATH="$STUB_BIN:/usr/bin:/bin" HOME="$CASE" \
        TILEFIN_DRM_ROOT="$CASE/drm" TILEFIN_PASSTHROUGH_CONF="$CASE/gpu-passthrough.conf" \
        bash "$WRAPPER" 2>&1)"
}

ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
has()  { grep -q "^$1=" <<<"$OUT"; }
val()  { grep "^$1=" <<<"$OUT" | cut -d= -f2-; }

# Without a designation: the connector rule (§spec:gpu-detection)
reset; card 0 nvidia connected; run
check "NVIDIA drives a monitor: NVIDIA rendering variables"  'has GBM_BACKEND && [ "$(val __GLX_VENDOR_LIBRARY_NAME)" = nvidia ]'
check "no designation: desktop apps still see NVIDIA"         '! has __EGL_VENDOR_LIBRARY_FILENAMES && ! has VK_LOADER_DRIVERS_DISABLE'
reset; card 0 nvidia disconnected; card 1 i915 connected; run
check "Intel drives the monitor: no NVIDIA variables"         '! has GBM_BACKEND && ! has __GLX_VENDOR_LIBRARY_NAME'

# With a designation (§spec:passthrough-desktop-gpu)
reset; card 0 nvidia connected; card 1 i915 connected; designate; run
check "a cabled passthrough GPU never gets NVIDIA variables"   '! has GBM_BACKEND && ! has LIBVA_DRIVER_NAME'
check "EGL loads only Mesa"                                   '[ "$(val __EGL_VENDOR_LIBRARY_FILENAMES)" = /usr/share/glvnd/egl_vendor.d/50_mesa.json ]'
check "GLX loads only Mesa"                                   '[ "$(val __GLX_VENDOR_LIBRARY_NAME)" = mesa ]'
check "Vulkan skips the NVIDIA driver"                        '[ "$(val VK_LOADER_DRIVERS_DISABLE)" = "*nvidia*" ]'

# The wrapper still hands off to niri-session
reset; run
check "the wrapper execs niri-session"                        'grep -q "^SSH_AUTH_SOCK=" <<<"$OUT"'

exit "$fail"
