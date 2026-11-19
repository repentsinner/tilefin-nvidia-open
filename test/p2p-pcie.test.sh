#!/usr/bin/bash
# Behaviour test for peer-to-peer PCIe mode (§spec:p2p-pcie): the derivation
# (§spec:p2p-pcie-derivation), the read request size the udev rule applies
# (§spec:p2p-pcie-read-request), the read-only check (§spec:p2p-pcie-check),
# the recipe and its exclusion with GPU passthrough (§spec:p2p-pcie-exclusion).
# Each runs against fake sysfs, procfs and /etc trees, with stubs for setpci,
# sudo, gum and rpm-ostree, so nothing on the host is read or written.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/build_files/p2p-pcie.sh"
JUSTFILE="$ROOT/build_files/tilefin.just"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; fail=1; }
# expect_eq <description> <expected> <actual>
expect_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
# expect_has <description> <needle> <haystack>
expect_has() {
    case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (no '$2' in: $3)" ;; esac
}
# expect_fails <description> <command...>
expect_fails() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "$what"; else ok "$what"; fi
}

# --- fake topology -----------------------------------------------------------

# A GPU under one root port, a two-port NIC under another, a second NIC behind
# a switch under a third, and an integrated device on the root bus itself.
SYS="$TMP/sys"
mkdir -p "$SYS/bus/pci/devices" "$SYS/class/net" "$SYS/kernel/iommu_groups"

# pcidev <path below devices/> <class> <iommu group>
pcidev() {
    local path="$1" bdf dir
    bdf="$(basename "$path")"
    dir="$SYS/devices/$path"
    mkdir -p "$dir" "$SYS/kernel/iommu_groups/$3/devices"
    echo "$2" > "$dir/class"
    ln -sfn "$dir" "$SYS/bus/pci/devices/$bdf"
    ln -sfn "$SYS/kernel/iommu_groups/$3" "$dir/iommu_group"
    ln -sfn "$dir" "$SYS/kernel/iommu_groups/$3/devices/$bdf"
}
# regroup <bdf> <iommu group> : moves a device to another group, as the
# kernel does once ACS redirect is off above it
regroup() {
    local dir old
    dir="$(readlink -f "$SYS/bus/pci/devices/$1")"
    old="$(basename "$(readlink -f "$dir/iommu_group")")"
    rm -f "$SYS/kernel/iommu_groups/$old/devices/$1"
    mkdir -p "$SYS/kernel/iommu_groups/$2/devices"
    ln -sfn "$SYS/kernel/iommu_groups/$2" "$dir/iommu_group"
    ln -sfn "$dir" "$SYS/kernel/iommu_groups/$2/devices/$1"
}

pcidev "pci0000:00/0000:00:1c.0" 0x060400 1
pcidev "pci0000:00/0000:00:1c.0/0000:0a:00.0" 0x030000 11
pcidev "pci0000:00/0000:00:1c.0/0000:0a:00.1" 0x040300 11
pcidev "pci0000:00/0000:00:1d.0" 0x060400 2
pcidev "pci0000:00/0000:00:1d.0/0000:0b:00.0" 0x020000 12
pcidev "pci0000:00/0000:00:1d.0/0000:0b:00.1" 0x020000 13
pcidev "pci0000:00/0000:00:1e.0" 0x060400 3
pcidev "pci0000:00/0000:00:1e.0/0000:0c:00.0" 0x060400 14
pcidev "pci0000:00/0000:00:1e.0/0000:0c:00.0/0000:0d:00.0" 0x060400 14
pcidev "pci0000:00/0000:00:1e.0/0000:0c:00.0/0000:0d:00.0/0000:0e:00.0" 0x020000 15
pcidev "pci0000:00/0000:00:1c.0/0000:0a:00.2" 0x020000 16
pcidev "pci0000:00/0000:00:19.0" 0x020000 4
mkdir -p "$SYS/class/net/ens2f0np0"
ln -s "$SYS/devices/pci0000:00/0000:00:1d.0/0000:0b:00.0" "$SYS/class/net/ens2f0np0/device"

ETC="$TMP/etc"
mkdir -p "$ETC/tilefin"
derive() { TILEFIN_SYSFS="$SYS" TILEFIN_ETC="$ETC" "$SCRIPT" derive "$@"; }
field() { sed -n "s/^$1: //p"; }

# --- derivation --------------------------------------------------------------

out="$(derive 0000:0a:00.0 0000:0b:00.0)"
expect_eq "each endpoint's root port is named" \
    "0000:00:1c.0 0000:00:1d.0" "$(field "root ports" <<<"$out")"
expect_eq "one argument lists both ports, with the semicolon escaped for GRUB" \
    'pci=disable_acs_redir=0000:00:1c.0\;0000:00:1d.0' "$(field kargs <<<"$out")"

out="$(derive 0000:0a:00.0 ens2f0np0)"
expect_eq "an interface resolves to its PCI device" \
    "0000:0b:00.0" "$(field nic <<<"$out")"
expect_eq "an interface derives the same ports as its address" \
    "0000:00:1c.0 0000:00:1d.0" "$(field "root ports" <<<"$out")"

out="$(derive 0000:0a:00.0 0000:0a:00.2)"
expect_eq "devices under one root port name it once" \
    "pci=disable_acs_redir=0000:00:1c.0" "$(field kargs <<<"$out")"

out="$(derive 0000:0a:00.0 0000:0e:00.0)"
expect_eq "behind a switch, the root port is the top of the path, not the parent bridge" \
    "0000:00:1c.0 0000:00:1e.0" "$(field "root ports" <<<"$out")"

expect_fails "a GPU address that is not a display device is refused" derive 0000:0b:00.0 0000:0a:00.0
expect_fails "a NIC that is not a network device is refused" derive 0000:0a:00.0 0000:0a:00.1
expect_fails "a device on the root bus, with no root port, is refused" derive 0000:0a:00.0 0000:00:19.0
expect_fails "a name that is no device is refused" derive 0000:0a:00.0 eth9
expect_fails "a missing argument is refused" derive 0000:0a:00.0

echo "PASSTHROUGH_GPU=0000:0a:00.0" > "$ETC/tilefin/gpu-passthrough.conf"
if out="$(derive 0000:0a:00.0 0000:0b:00.0 2>&1)"; then
    bad "the derivation refuses while GPU passthrough is set up"
else
    ok "the derivation refuses while GPU passthrough is set up"
fi
expect_has "the refusal names the passthrough designation" "gpu-passthrough.conf" "$out"
rm "$ETC/tilefin/gpu-passthrough.conf"

# --- apply (the udev rule's service) -----------------------------------------

# setpci stub: logs each call, and keeps the registers in files so a write
# reads back. Ports start with Request and Completion Redirect set.
REGS="$TMP/regs"
mkdir -p "$REGS"
cat > "$TMP/setpci" <<'EOF'
#!/usr/bin/bash
echo "setpci $*" >> "$REGS/calls"
[ "$1" = -s ] || exit 2
dev="$2" spec="$3"
reg="${spec%%=*}"
file="$REGS/$dev.${reg%%.*}"
[ -e "$file" ] || { echo "setpci: $dev has no $reg" >&2; exit 1; }
if [[ "$spec" == *=* ]]; then
    value="${spec#*=}" mask=ffff
    [[ "$value" == *:* ]] && mask="${value#*:}" value="${value%:*}"
    old=$((16#$(cat "$file")))
    printf '%04x\n' $(( (old & ~16#$mask) | (16#$value & 16#$mask) )) > "$file"
else
    cat "$file"
fi
EOF
chmod +x "$TMP/setpci"
export REGS
# NIC Device Control: max payload 256, read request 512 (bits 14:12 = 010).
regs_reset() {
    rm -f "$REGS"/*
    echo 2930 > "$REGS/0000:0b:00.0.CAP_EXP+8"
    echo 001d > "$REGS/0000:00:1c.0.ECAP_ACS+6"
    echo 001d > "$REGS/0000:00:1d.0.ECAP_ACS+6"
}

RUN="$TMP/run"
apply() {
    TILEFIN_SYSFS="$SYS" TILEFIN_ETC="$ETC" TILEFIN_RUN="$RUN" \
        TILEFIN_SETPCI="$TMP/setpci" "$SCRIPT" apply "$1"
}
write_conf() {
    printf 'GPU=0000:0a:00.0\nNIC=0000:0b:00.0\nROOT_PORTS=0000:00:1c.0 0000:00:1d.0\n' \
        > "$ETC/tilefin/p2p-pcie.conf"
}

regs_reset
if apply 0000:0b:00.0 >/dev/null 2>&1; then
    ok "without a configuration, apply succeeds"
else
    bad "without a configuration, apply succeeds"
fi
expect_eq "without a configuration, apply touches no device" "" "$(cat "$REGS/calls" 2>/dev/null)"

write_conf
regs_reset
apply 0000:0b:00.1 >/dev/null 2>&1
expect_eq "a device other than the configured NIC is left alone" "" "$(cat "$REGS/calls" 2>/dev/null)"

if apply 0000:0b:00.0 > "$TMP/apply.log" 2>&1; then
    ok "apply succeeds on the configured NIC"
else
    bad "apply succeeds on the configured NIC ($(cat "$TMP/apply.log"))"
fi
expect_has "the read request size is written under its mask" \
    "setpci -s 0000:0b:00.0 CAP_EXP+8.w=5000:7000" "$(cat "$REGS/calls")"
expect_eq "only the read request bits change" "5930" "$(cat "$REGS/0000:0b:00.0.CAP_EXP+8")"
expect_has "the status records the read-back size" \
    "mrrs=4096" "$(cat "$RUN/tilefin/p2p-pcie/0000:0b:00.0" 2>/dev/null)"
expect_has "the status records each root port's ACS Control" \
    "acs_ctrl=0x001d" "$(cat "$RUN/tilefin/p2p-pcie/0000:00:1c.0" 2>/dev/null)"
expect_eq "apply writes no ACS register; the kernel argument owns it" \
    "001d" "$(cat "$REGS/0000:00:1c.0.ECAP_ACS+6")"

# A device that ignores the write fails the unit, so systemctl --failed shows it.
cat > "$TMP/setpci-stuck" <<'EOF'
#!/usr/bin/bash
[[ "$3" == *=* ]] && exit 0
exec "$(dirname "$0")/setpci" "$@"
EOF
chmod +x "$TMP/setpci-stuck"
regs_reset
if TILEFIN_SYSFS="$SYS" TILEFIN_ETC="$ETC" TILEFIN_RUN="$RUN" TILEFIN_SETPCI="$TMP/setpci-stuck" \
    "$SCRIPT" apply 0000:0b:00.0 >/dev/null 2>&1; then
    bad "apply fails when the read request size does not read back"
else
    ok "apply fails when the read request size does not read back"
fi

# --- check -------------------------------------------------------------------

PROC="$TMP/proc"
mkdir -p "$PROC"
cmdline() { echo "BOOT_IMAGE=vmlinuz root=UUID=x pci=realloc $1" > "$PROC/cmdline"; }
check() {
    TILEFIN_SYSFS="$SYS" TILEFIN_ETC="$ETC" TILEFIN_RUN="$RUN" TILEFIN_PROC="$PROC" \
        TILEFIN_SETPCI="$TMP/setpci" TILEFIN_EUID="${EUID_AS:-1000}" "$SCRIPT" check
}
# The state after a reboot with the argument: each endpoint joins its root
# port's group, the ports read RR and CR clear, and apply has run.
booted() {
    cmdline 'pci=disable_acs_redir=0000:00:1c.0;0000:00:1d.0'
    regroup 0000:0a:00.0 1; regroup 0000:0a:00.1 1
    regroup 0000:0b:00.0 2; regroup 0000:0b:00.1 2
    regs_reset
    echo 0011 > "$REGS/0000:00:1c.0.ECAP_ACS+6"
    echo 0011 > "$REGS/0000:00:1d.0.ECAP_ACS+6"
    apply 0000:0b:00.0 >/dev/null 2>&1
}

rm -f "$ETC/tilefin/p2p-pcie.conf"
cmdline ""
if out="$(check)"; then ok "with nothing set, the check passes"; else bad "with nothing set, the check passes ($out)"; fi
expect_has "the check says when the mode is not set" "not set" "$out"

write_conf
booted
if out="$(check)"; then ok "the check passes once the mode is in force"; else bad "the check passes once the mode is in force ($out)"; fi
expect_has "the check names the root ports" "0000:00:1d.0" "$out"
expect_has "the check reports the read request size from the status" "4096" "$out"
expect_has "the check asks for sudo to read the live registers" "sudo" "$out"
if out="$(EUID_AS=0 check)"; then ok "as root, the live registers pass"; else bad "as root, the live registers pass ($out)"; fi
expect_has "as root, the check reads ACS Control" "ACS Control" "$out"

cmdline 'pci=disable_acs_redir=0000:00:1c.0'
if out="$(check)"; then bad "the check fails when a root port is missing from the argument"; else ok "the check fails when a root port is missing from the argument"; fi
expect_has "the check names the port the argument misses" "0000:00:1d.0" "$out"

booted
cmdline 'pci=disable_acs_redir=0000:00:1c.0;0000:00:1d.0 pci=disable_acs_redir=0000:00:1c.0'
if out="$(check)"; then bad "the last disable_acs_redir wins, as in the kernel"; else ok "the last disable_acs_redir wins, as in the kernel"; fi

booted
regroup 0000:0b:00.0 12
if out="$(check)"; then bad "the check fails when an endpoint keeps a group apart from its root port"; else ok "the check fails when an endpoint keeps a group apart from its root port"; fi

booted
rm -f "$RUN/tilefin/p2p-pcie/0000:0b:00.0"
if out="$(check)"; then bad "the check fails when apply has not run"; else ok "the check fails when apply has not run"; fi

booted
echo 001d > "$REGS/0000:00:1d.0.ECAP_ACS+6"
if out="$(EUID_AS=0 check)"; then bad "as root, the check fails on a port with redirect still set"; else ok "as root, the check fails on a port with redirect still set"; fi
echo 0011 > "$REGS/0000:00:1d.0.ECAP_ACS+6"
echo 2930 > "$REGS/0000:0b:00.0.CAP_EXP+8"
if out="$(EUID_AS=0 check)"; then bad "as root, the check fails when the live read request size has reverted"; else ok "as root, the check fails when the live read request size has reverted"; fi
expect_has "the reverted size is named" "512" "$out"

# Behind a switch, the switch's downstream port can keep its own ACS and the
# endpoint its own group, so the group is reported and not judged.
printf 'GPU=0000:0a:00.0\nNIC=0000:0e:00.0\nROOT_PORTS=0000:00:1c.0 0000:00:1e.0\n' \
    > "$ETC/tilefin/p2p-pcie.conf"
cmdline 'pci=disable_acs_redir=0000:00:1c.0;0000:00:1e.0'
regs_reset
echo 2930 > "$REGS/0000:0e:00.0.CAP_EXP+8"
echo 0011 > "$REGS/0000:00:1e.0.ECAP_ACS+6"
echo 0011 > "$REGS/0000:00:1c.0.ECAP_ACS+6"
apply 0000:0e:00.0 >/dev/null 2>&1
if out="$(check)"; then ok "a NIC behind a switch passes with a group of its own"; else bad "a NIC behind a switch passes with a group of its own ($out)"; fi
expect_has "the switch case is reported" "behind a switch" "$out"
write_conf

# --- recipes -----------------------------------------------------------------

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
printf '#!/usr/bin/bash\n"$@"\n' > "$STUB_BIN/sudo"
printf '#!/usr/bin/bash\nexit 0\n' > "$STUB_BIN/gum"
cat > "$STUB_BIN/rpm-ostree" <<'EOF'
#!/usr/bin/bash
echo "rpm-ostree $*" >> "$STUB_DIR/calls"
if [ "$1" = kargs ] && [ "$#" -eq 1 ]; then cat "$STUB_DIR/kargs"; fi
EOF
cat > "$STUB_BIN/systemctl" <<'EOF'
#!/usr/bin/bash
echo "systemctl $*" >> "$STUB_DIR/calls"
EOF
chmod +x "$STUB_BIN"/*
STUB_DIR="$TMP/stub"
mkdir -p "$STUB_DIR"
export STUB_DIR

recipe() {
    : > "$STUB_DIR/calls"
    env PATH="$STUB_BIN:$PATH" TILEFIN_SYSFS="$SYS" TILEFIN_ETC="$ETC" TILEFIN_PROC="$PROC" \
        TILEFIN_P2P_PCIE="$SCRIPT" \
        just --justfile "$JUSTFILE" --working-directory "$ROOT" "$@" 2>&1 </dev/null
}

rm -f "$ETC/tilefin/p2p-pcie.conf"
echo "root=UUID=x rw pci=disable_acs_redir=0000:00:1b.0 iommu=pt" > "$STUB_DIR/kargs"
out="$(recipe p2p-pcie 0000:0a:00.0 ens2f0np0)"
expect_has "the recipe replaces an earlier argument and appends the new one" \
    'rpm-ostree kargs --delete=pci=disable_acs_redir=0000:00:1b.0 --append=pci=disable_acs_redir=0000:00:1c.0\;0000:00:1d.0' \
    "$(cat "$STUB_DIR/calls")"
expect_has "the recipe records the NIC for the udev rule" \
    "NIC=0000:0b:00.0" "$(cat "$ETC/tilefin/p2p-pcie.conf" 2>/dev/null)"
expect_has "the recipe records the root ports" \
    "ROOT_PORTS=0000:00:1c.0 0000:00:1d.0" "$(cat "$ETC/tilefin/p2p-pcie.conf" 2>/dev/null)"
if grep -qE "reboot|poweroff" "$STUB_DIR/calls"; then bad "the recipe never reboots"; else ok "the recipe never reboots"; fi

echo "root=UUID=x rw pci=realloc,disable_acs_redir=0000:00:1b.0" > "$STUB_DIR/kargs"
rm -f "$ETC/tilefin/p2p-pcie.conf"
out="$(recipe p2p-pcie 0000:0a:00.0 ens2f0np0)"
if grep -q -- "--append" "$STUB_DIR/calls"; then
    bad "the recipe refuses a disable_acs_redir joined to other pci= options"
else
    ok "the recipe refuses a disable_acs_redir joined to other pci= options"
fi

echo "PASSTHROUGH_GPU=0000:0a:00.0" > "$ETC/tilefin/gpu-passthrough.conf"
echo "root=UUID=x rw" > "$STUB_DIR/kargs"
out="$(recipe p2p-pcie 0000:0a:00.0 ens2f0np0)"
if grep -q -- "--append" "$STUB_DIR/calls" || [ -e "$ETC/tilefin/p2p-pcie.conf" ]; then
    bad "the recipe changes nothing while GPU passthrough is set up"
else
    ok "the recipe changes nothing while GPU passthrough is set up"
fi
rm "$ETC/tilefin/gpu-passthrough.conf"

write_conf
echo "root=UUID=x rw pci=disable_acs_redir=0000:00:1c.0\\;0000:00:1d.0 iommu=pt" > "$STUB_DIR/kargs"
out="$(recipe p2p-pcie --remove)"
expect_has "--remove deletes the argument" \
    'rpm-ostree kargs --delete=pci=disable_acs_redir=0000:00:1c.0\;0000:00:1d.0' "$(cat "$STUB_DIR/calls")"
if [ -e "$ETC/tilefin/p2p-pcie.conf" ]; then bad "--remove deletes the configuration"; else ok "--remove deletes the configuration"; fi

exit "$fail"
