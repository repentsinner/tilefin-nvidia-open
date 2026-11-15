#!/usr/bin/bash
# Behaviour test for the media CPU partition (§spec:media-cpu-partition):
# the derivation (§spec:media-cores-partition), the boot-time IRQ steering
# (§spec:media-cores-irq-steering) and the read-only check
# (§spec:media-cores-check). Each runs against fake sysfs and procfs trees,
# so nothing on the host is read or written.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/build_files/media-cores.sh"
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

# --- fake topologies -------------------------------------------------------

# cpu <sys> <cpu> <l3 shared list> <siblings>
cpu() {
    local dir="$1/devices/system/cpu/cpu$2"
    mkdir -p "$dir/cache/index3" "$dir/topology"
    echo "$3" > "$dir/cache/index3/shared_cpu_list"
    echo "$4" > "$dir/topology/thread_siblings_list"
}

# A 32-core part with SMT, one NUMA node, eight L3 groups of four cores:
# core c is CPUs c and c+32, and its L3 group is the four cores c-c%4..+3.
SYS_TR="$TMP/tr/sys"
mkdir -p "$SYS_TR/devices/system/cpu" "$SYS_TR/class/net" "$SYS_TR/bus/pci/devices/0000:41:00.0"
echo "0-63" > "$SYS_TR/devices/system/cpu/online"
for c in $(seq 0 31); do
    g=$((c / 4 * 4))
    l3="$g-$((g + 3)),$((g + 32))-$((g + 35))"
    cpu "$SYS_TR" "$c" "$l3" "$c,$((c + 32))"
    cpu "$SYS_TR" "$((c + 32))" "$l3" "$c,$((c + 32))"
done
echo "-1" > "$SYS_TR/bus/pci/devices/0000:41:00.0/numa_node"
mkdir -p "$SYS_TR/class/net/enp65s0f0np0"
ln -s "../../../bus/pci/devices/0000:41:00.0" "$SYS_TR/class/net/enp65s0f0np0/device"

# A hybrid part sharing one L3: P-cores 0-7 with SMT (core p is CPUs 2p and
# 2p+1), E-cores 16-23 without; the anchor reports NUMA node 0.
SYS_HY="$TMP/hy/sys"
mkdir -p "$SYS_HY/devices/system/cpu" "$SYS_HY/devices/system/node/node0" \
    "$SYS_HY/devices/cpu_core" "$SYS_HY/devices/cpu_atom" "$SYS_HY/bus/pci/devices/0000:01:00.0"
echo "0-23" > "$SYS_HY/devices/system/cpu/online"
echo "0-23" > "$SYS_HY/devices/system/node/node0/cpulist"
echo "0-15" > "$SYS_HY/devices/cpu_core/cpus"
echo "16-23" > "$SYS_HY/devices/cpu_atom/cpus"
for p in $(seq 0 7); do
    cpu "$SYS_HY" "$((2 * p))" "0-23" "$((2 * p))-$((2 * p + 1))"
    cpu "$SYS_HY" "$((2 * p + 1))" "0-23" "$((2 * p))-$((2 * p + 1))"
done
for e in $(seq 16 23); do cpu "$SYS_HY" "$e" "0-23" "$e"; done
echo "0" > "$SYS_HY/bus/pci/devices/0000:01:00.0/numa_node"

derive() { TILEFIN_SYSFS="$1" "$SCRIPT" derive "$2" "$3"; }
field() { sed -n "s/^$1: //p"; }

# --- derivation ------------------------------------------------------------

out="$(derive "$SYS_TR" enp65s0f0np0 4)"
expect_eq "one whole L3 group, taken from the far end" \
    "28-31,60-63" "$(field isolated <<<"$out")"
expect_eq "housekeeping is every other online CPU" \
    "0-27,32-59" "$(field housekeeping <<<"$out")"
expect_eq "the four arguments name the partition" \
    "irqaffinity=0-27,32-59 isolcpus=managed_irq,domain,28-31,60-63 nohz_full=28-31,60-63 rcu_nocbs=28-31,60-63" \
    "$(field kargs <<<"$out")"

out="$(derive "$SYS_TR" 0000:41:00.0 6)"
expect_eq "a PCI address anchors as its interface does; whole groups first, then part of the next" \
    "26-31,58-63" "$(field isolated <<<"$out")"

out="$(derive "$SYS_TR" enp65s0f0np0 28)"
expect_eq "every group but CPU 0's can be isolated" \
    "4-31,36-63" "$(field isolated <<<"$out")"
if derive "$SYS_TR" enp65s0f0np0 29 >/dev/null 2>&1; then
    bad "CPU 0's L3 group is refused to the isolated set"
else
    ok "CPU 0's L3 group is refused to the isolated set"
fi
if derive "$SYS_TR" enp65s0f0np0 0 >/dev/null 2>&1; then
    bad "a count of zero is refused"
else
    ok "a count of zero is refused"
fi
if derive "$SYS_TR" eth9 4 >/dev/null 2>&1; then
    bad "an anchor that names no device is refused"
else
    ok "an anchor that names no device is refused"
fi

out="$(derive "$SYS_HY" 0000:01:00.0 3)"
expect_eq "a hybrid part isolates performance cores only, keeping CPU 0's core" \
    "10-15" "$(field isolated <<<"$out")"
expect_has "a single L3 group is reported as shared" \
    "share the L3" "$out"
if derive "$SYS_HY" 0000:01:00.0 8 >/dev/null 2>&1; then
    bad "efficiency cores never make up the count"
else
    ok "efficiency cores never make up the count"
fi

# --- steering --------------------------------------------------------------

# irq <proc> <n> <effective list> <managed: yes|no> <action>
irq() {
    local dir="$1/irq/$2"
    mkdir -p "$dir"
    echo "$3" > "$dir/effective_affinity_list"
    echo "$3" > "$dir/smp_affinity_list"
    [ "$4" = yes ] && touch "$dir/.managed"
    printf '%4s: %s\n' "$2" "$5" >> "$1/interrupts"
}

# A fake /proc whose smp_affinity_list writes land in the file, as the
# kernel's do, except on a managed IRQ, which refuses them.
make_proc() {
    local proc="$1"
    mkdir -p "$proc/irq"
    : > "$proc/interrupts"
    echo "BOOT_IMAGE=vmlinuz $2" > "$proc/cmdline"
}

PARTITION="irqaffinity=0-27,32-59 isolcpus=managed_irq,domain,28-31,60-63 nohz_full=28-31,60-63 rcu_nocbs=28-31,60-63"

steer() {
    TILEFIN_SYSFS="$SYS_TR" TILEFIN_PROC="$1" TILEFIN_RUN="$1/run" \
        TILEFIN_AFFINITY_WRITE="$TMP/write-affinity" "$SCRIPT" steer
}
# The writer the script uses in place of a shell redirect, so the test can
# refuse a managed IRQ's write the way the kernel does, and move a movable
# IRQ's effective affinity the way the kernel does.
cat > "$TMP/write-affinity" <<'EOF'
#!/usr/bin/bash
dir="$(dirname "$1")"
[ -e "$dir/.managed" ] && exit 1
[ -e "$dir/.stuck" ] && exit 0
echo "$2" > "$1"
echo "$2" > "$dir/effective_affinity_list"
EOF
chmod +x "$TMP/write-affinity"

P1="$TMP/p1"
make_proc "$P1" "$PARTITION"
irq "$P1" 30 "29" no "mlx5_comp3"
irq "$P1" 31 "61" yes "nvme0q12"
irq "$P1" 32 "2" no "xhci_hcd"
if steer "$P1" > "$TMP/steer1.log" 2>&1; then ok "steering succeeds when every movable IRQ moves"; else bad "steering succeeds when every movable IRQ moves"; fi
expect_eq "a movable IRQ is moved to the housekeeping set" \
    "0-27,32-59" "$(cat "$P1/irq/30/smp_affinity_list")"
expect_has "a managed IRQ left on the isolated set is logged" \
    "nvme0q12" "$(cat "$TMP/steer1.log")"
expect_eq "the managed IRQs are recorded for the check" \
    "31" "$(cat "$P1/run/tilefin/managed-irqs")"

P2="$TMP/p2"
make_proc "$P2" "$PARTITION"
irq "$P2" 40 "30" no "rogue_driver"
touch "$P2/irq/40/.stuck"
if steer "$P2" > "$TMP/steer2.log" 2>&1; then bad "steering fails when a movable IRQ stays on the isolated set"; else ok "steering fails when a movable IRQ stays on the isolated set"; fi
expect_has "the stuck IRQ is named with its action" \
    "rogue_driver" "$(cat "$TMP/steer2.log")"

P3="$TMP/p3"
make_proc "$P3" ""
irq "$P3" 50 "29" no "mlx5_comp3"
if steer "$P3" > "$TMP/steer3.log" 2>&1; then ok "without a partition, steering succeeds"; else bad "without a partition, steering succeeds"; fi
expect_eq "without a partition, steering changes nothing" \
    "29" "$(cat "$P3/irq/50/smp_affinity_list")"

# --- check -----------------------------------------------------------------

check() {
    TILEFIN_SYSFS="$2" TILEFIN_PROC="$1" TILEFIN_RUN="$1/run" \
        TILEFIN_PROCESSES="$TMP/no-processes" "$SCRIPT" check
}
: > "$TMP/no-processes"
echo "28-31,60-63" > "$SYS_TR/devices/system/cpu/isolated"
echo "28-31,60-63" > "$SYS_TR/devices/system/cpu/nohz_full"

if out="$(check "$P1" "$SYS_TR")"; then ok "the check passes once steering has run"; else bad "the check passes once steering has run ($out)"; fi
expect_has "the check reports the managed IRQ as managed" \
    "managed" "$out"

if out="$(check "$P2" "$SYS_TR")"; then bad "the check fails on a movable IRQ on the isolated set"; else ok "the check fails on a movable IRQ on the isolated set"; fi
expect_has "the check names the movable IRQ" "rogue_driver" "$out"

out="$(check "$P3" "$SYS_TR")"
expect_has "the check says when no partition is set" "no partition" "$out"

echo "28-31" > "$SYS_TR/devices/system/cpu/isolated"
if out="$(check "$P1" "$SYS_TR")"; then bad "the check fails when the kernel's isolated set differs"; else ok "the check fails when the kernel's isolated set differs"; fi
echo "28-31,60-63" > "$SYS_TR/devices/system/cpu/isolated"

echo "irqbalance" > "$TMP/no-processes"
out="$(check "$P1" "$SYS_TR")"
expect_has "the check reports a running irqbalance" "irqbalance" "$out"

exit "$fail"
