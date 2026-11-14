#!/usr/bin/bash
# Behaviour test for `ujust setup-gpu-passthrough` (§spec:passthrough-setup,
# §spec:guest-address-width). Runs the recipe against a fake sysfs modelled on
# an Intel iGPU + NVIDIA workstation, writing under a temporary /etc, with
# stubs for sudo, systemctl, usermod and virsh.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JUSTFILE="$ROOT/build_files/tilefin.just"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
printf '#!/usr/bin/bash\n"$@"\n' > "$STUB_BIN/sudo"
for cmd in systemctl usermod; do
    printf '#!/usr/bin/bash\necho "%s $*" >> "$STUB_DIR/calls"\n' "$cmd" > "$STUB_BIN/$cmd"
done
cat > "$STUB_BIN/virsh" <<'STUB'
#!/usr/bin/bash
echo "virsh $*" >> "$STUB_DIR/calls"
[ "$1" = "--connect" ] && shift 2
case "$1" in
    list) echo "win11"; echo "" ;;
    dumpxml) cat "$STUB_DIR/domain.xml" ;;
    define) cp "$2" "$STUB_DIR/defined.xml" ;;
esac
STUB
chmod +x "$STUB_BIN"/*

fail=0
OUT=""; RC=0
GIB=$((1024 * 1024 * 1024))

# pcidev <addr> <vendor> <class> <boot_vga> <group> [bar1_bytes]
pcidev() {
    local d="$STUB_DIR/sys/bus/pci/devices/$1"
    mkdir -p "$d" "$STUB_DIR/sys/kernel/iommu_groups/$5/devices"
    echo "$2" > "$d/vendor"; echo "$3" > "$d/class"; echo "$4" > "$d/boot_vga"
    ln -s "../../../../kernel/iommu_groups/$5" "$d/iommu_group"
    ln -s "../../../../bus/pci/devices/$1" "$STUB_DIR/sys/kernel/iommu_groups/$5/devices/$1"
    local bar1="${6:-0}"
    printf '0x0000000080000000 0x0000000080ffffff 0x0\n' > "$d/resource"
    if [ "$bar1" -gt 0 ]; then
        printf '0x0000004000000000 0x%016x 0x0\n' $((0x4000000000 + bar1 - 1)) >> "$d/resource"
    fi
}
# reset [mgaw_bits] : this workstation's layout, IOMMU MGAW defaulting to 39
reset() {
    STUB_DIR="$TMP/case.$RANDOM$RANDOM"
    mkdir -p "$STUB_DIR/etc" "$STUB_DIR/sys/class/iommu/dmar0/intel-iommu"
    : > "$STUB_DIR/calls"
    pcidev 0000:00:02.0 0x8086 0x030000 1 0
    pcidev 0000:01:00.0 0x10de 0x030000 0 16 $((64 * GIB))
    pcidev 0000:01:00.1 0x10de 0x040300 0 16
    # MGAW is bits 21:16 of the capability register, stored as width minus one.
    printf '%x\n' $(( (${1:-39} - 1) << 16 )) > "$STUB_DIR/sys/class/iommu/dmar0/intel-iommu/cap"
    printf 'address sizes\t: 46 bits physical, 48 bits virtual\n' > "$STUB_DIR/cpuinfo"
    echo "<domain><name>win11</name><cpu mode='host-passthrough'/><devices/></domain>" > "$STUB_DIR/domain.xml"
    export STUB_DIR
}
# run <env assignments...> -- : stdin is not a terminal unless ASSUME_YES
run() {
    local envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    OUT="$(env PATH="$STUB_BIN:$PATH" USER=tester TILEFIN_SYSFS="$STUB_DIR/sys" \
        TILEFIN_CPUINFO="$STUB_DIR/cpuinfo" TILEFIN_ETC="$STUB_DIR/etc" "${envs[@]}" \
        just --justfile "$JUSTFILE" --working-directory "$ROOT" setup-gpu-passthrough 2>&1 </dev/null)"
    # shellcheck disable=SC2034 # read inside the condition strings check() evals
    RC=$?
}

ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; printf '       output: %s\n' "$OUT" | head -8; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
called() { grep -qF "$1" "$STUB_DIR/calls"; }
conf()   { echo "$STUB_DIR/etc/tilefin/gpu-passthrough.conf"; }
kdl()    { echo "$STUB_DIR/etc/niri/gpu-passthrough.kdl"; }

# Report-only without a terminal
reset; run --
check "names the GPU to pass through and the desktop GPU"   'grep -q 0000:01:00.0 <<<"$OUT" && grep -q 0000:00:02.0 <<<"$OUT"'
check "a clean IOMMU group passes"                         'grep -qi "group 16" <<<"$OUT" && ! grep -qi refus <<<"$OUT"'
check "a narrow IOMMU is reported with the guest settings" 'grep -q "39" <<<"$OUT" && grep -q "131072" <<<"$OUT"'
check "without a terminal nothing is written"              '[ ! -e "$(conf)" ] && [ ! -s "$STUB_DIR/calls" ]'

reset; echo 0 > "$STUB_DIR/sys/bus/pci/devices/0000:00:02.0/boot_vga"
echo 1 > "$STUB_DIR/sys/bus/pci/devices/0000:01:00.0/boot_vga"; run --
check "a non-integrated boot GPU names the firmware setting" 'grep -qi "boot GPU" <<<"$OUT" && grep -q "Initiate Graphic Adapter" <<<"$OUT"'

reset; pcidev 0000:02:00.0 0x8086 0x020000 0 16; run --
check "a shared IOMMU group is refused"                    '[ $RC != 0 ] && grep -q 0000:02:00.0 <<<"$OUT" && [ ! -e "$(conf)" ]'

reset 48; run --
check "an IOMMU as wide as needed reports no guest change" '! grep -q "131072" <<<"$OUT"'

# Applying everything
reset; run TILEFIN_ASSUME_YES=1 TILEFIN_VM=win11 --
check "the designation names both GPUs"                    'grep -qx "PASSTHROUGH_GPU=0000:01:00.0" "$(conf)" && grep -qx "DESKTOP_GPU=0000:00:02.0" "$(conf)"'
check "niri renders on the desktop GPU by stable path"     'grep -qF "render-drm-device \"/dev/dri/by-path/pci-0000:00:02.0-render\"" "$(kdl)"'
check "niri ignores the passthrough GPU by stable path"    'grep -qF "ignore-drm-device \"/dev/dri/by-path/pci-0000:01:00.0-render\"" "$(kdl)"'
check "Looking Glass gets a fullscreen workspace and bind" 'grep -q "open-fullscreen true" "$(kdl)" && grep -q "focus-workspace" "$(kdl)"'
check "the niri include validates"                         'niri validate -c "$(kdl)" >/dev/null 2>&1 || ! command -v niri >/dev/null'
check "nvidia-persistenced is disabled"                    'called "systemctl disable --now nvidia-persistenced.service"'
check "the user joins the looking-glass group"             'called "usermod -aG looking-glass tester"'
check "the named guest gets the 39-bit limit"              'grep -q "maxphysaddr" "$STUB_DIR/defined.xml" && grep -q "limit=.39" "$STUB_DIR/defined.xml"'
check "the named guest gets the larger firmware window"    'grep -q "X-PciMmio64Mb,string=131072" "$STUB_DIR/defined.xml"'
check "the recipe never reboots"                           '! grep -qE "reboot|systemctl (reboot|poweroff)" "$STUB_DIR/calls"'

exit "$fail"
