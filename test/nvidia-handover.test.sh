#!/usr/bin/bash
# Behaviour test for the libvirt GPU handover hook (§spec:gpu-handover).
# Runs the hook against a fake sysfs and /proc, with stub modprobe and logger,
# so no module is unloaded and no real process is inspected.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/build_files/nvidia-handover"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
# modprobe stub: records calls; "modprobe -r" fails while $STUB_DIR/busy exists.
cat > "$STUB_BIN/modprobe" <<'STUB'
#!/usr/bin/bash
echo "modprobe $*" >> "$STUB_DIR/calls"
if [ "$1" = "-r" ] && [ -e "$STUB_DIR/busy" ]; then
    echo "modprobe: FATAL: Module nvidia is in use." >&2
    exit 1
fi
exit 0
STUB
cat > "$STUB_BIN/logger" <<'STUB'
#!/usr/bin/bash
echo "logger $*" >> "$STUB_DIR/log"
STUB
chmod +x "$STUB_BIN/modprobe" "$STUB_BIN/logger"

GPU_XML="<domain><name>vm</name><devices>
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source><address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/></source>
  </hostdev>
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source><address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/></source>
  </hostdev>
</devices></domain>"
PLAIN_XML="<domain><name>vm</name><devices><disk/></devices></domain>"

fail=0
OUT=""; RC=0

# reset <driver of 0000:01:00.0> : fresh fake sysfs, /proc, state and stub logs
reset() {
    STUB_DIR="$TMP/case.$RANDOM$RANDOM"
    mkdir -p "$STUB_DIR/sys/bus/pci/drivers/$1" "$STUB_DIR/sys/bus/pci/devices/0000:01:00.0" \
        "$STUB_DIR/proc" "$STUB_DIR/run"
    ln -s "../../../bus/pci/drivers/$1" "$STUB_DIR/sys/bus/pci/devices/0000:01:00.0/driver"
    : > "$STUB_DIR/calls"; : > "$STUB_DIR/log"
    export STUB_DIR
}
# holder <pid> <comm> : a fake process holding /dev/nvidia0
holder() {
    mkdir -p "$STUB_DIR/proc/$1/fd"
    echo "$2" > "$STUB_DIR/proc/$1/comm"
    ln -s /dev/nvidia0 "$STUB_DIR/proc/$1/fd/3"
}
# run <xml> <operation> <sub-operation>
run() {
    OUT="$(printf '%s' "$1" | env PATH="$STUB_BIN:$PATH" \
        TILEFIN_SYSFS="$STUB_DIR/sys" TILEFIN_PROC="$STUB_DIR/proc" \
        TILEFIN_HANDOVER_STATE_DIR="$STUB_DIR/run" \
        "$HOOK" vm "$2" "$3" - 2>&1)"
    # shellcheck disable=SC2034 # read inside the condition strings check() evals
    RC=$?
}

ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; printf '       output: %s\n' "$OUT" | head -5; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
unloaded() { grep -q '^modprobe -r ' "$STUB_DIR/calls"; }
loaded()   { grep -q '^modprobe nvidia_drm$' "$STUB_DIR/calls"; }
logged()   { grep -q "event=$1" "$STUB_DIR/log"; }

# Release
reset nvidia;   run "$GPU_XML" prepare begin
check "a guest taking the NVIDIA GPU unloads the modules" '[ $RC = 0 ] && unloaded && logged released'
check "the release log line carries the domain in a field" 'grep -q "domain=vm" "$STUB_DIR/log"'
reset nvidia;   run "$PLAIN_XML" prepare begin
check "a guest without host devices is left alone"         '[ $RC = 0 ] && ! unloaded && [ ! -s "$STUB_DIR/log" ]'
reset vfio-pci; run "$GPU_XML" prepare begin
check "a device not on the nvidia driver is left alone"    '[ $RC = 0 ] && ! unloaded'

# Refusal
reset nvidia; : > "$STUB_DIR/busy"; holder 4242 firefox; holder 4243 protonvpn-app
run "$GPU_XML" prepare begin
check "a held GPU refuses the start"                      '[ $RC != 0 ] && logged refused'
check "the refusal names the holding processes"           'grep -q "4242 firefox" <<<"$OUT" && grep -q "4243 protonvpn-app" <<<"$OUT"'
check "a refused start restores the host's modules"       'loaded'
reset nvidia; : > "$STUB_DIR/busy"
run "$GPU_XML" prepare begin
check "a refusal with no visible holders still refuses"   '[ $RC != 0 ] && grep -qi "in use" <<<"$OUT"'

# Restore
reset nvidia;   run "$GPU_XML" prepare begin; run "$GPU_XML" release end
check "a guest that took the GPU gives it back"           '[ $RC = 0 ] && loaded && logged restored'
reset nvidia;   run "$GPU_XML" release end
check "a guest that never took the GPU restores nothing"  '[ $RC = 0 ] && ! loaded'

# Other operations
reset nvidia;   run "$GPU_XML" started begin
check "other operations do nothing"                       '[ $RC = 0 ] && ! unloaded && ! loaded'

# The hook never manages services itself (§spec:gpu-handover)
check "the hook does not call systemctl"                  '! grep -vE "^[[:space:]]*#" "$HOOK" | grep -q systemctl'

exit "$fail"
