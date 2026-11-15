#!/usr/bin/bash
# The media CPU partition (§spec:media-cpu-partition): a housekeeping set and
# an isolated set of CPUs, held as local kernel arguments on the machine that
# chose them. The image carries this mechanism and no core numbers.
#
#   media-cores.sh derive <interface|pci-address> <cores>
#       Derives a partition from the anchor's topology and prints it with the
#       kernel arguments it implies (§spec:media-cores-partition). Reads only.
#   media-cores.sh steer
#       Moves every movable IRQ onto the housekeeping set, and fails when one
#       stays on the isolated set (§spec:media-cores-irq-steering). Run once
#       at boot by tilefin-media-cores-steer.service.
#   media-cores.sh check
#       Reports the partition, the IRQs on the isolated set and any IRQ
#       balancer, and changes nothing (§spec:media-cores-check).
#
# TILEFIN_SYSFS, TILEFIN_PROC and TILEFIN_RUN stand in for /sys, /proc and
# /run, TILEFIN_PROCESSES for a file of running process names, and
# TILEFIN_AFFINITY_WRITE for the command that writes an IRQ's affinity, so a
# test runs every path against fake trees (test/media-cores.test.sh).
set -euo pipefail

SYSFS="${TILEFIN_SYSFS:-/sys}"
PROC="${TILEFIN_PROC:-/proc}"
RUN="${TILEFIN_RUN:-/run}"
CPU_DIR="$SYSFS/devices/system/cpu"
MANAGED_FILE="$RUN/tilefin/managed-irqs"
PARTITION_KEYS=(irqaffinity isolcpus nohz_full rcu_nocbs)

die() { echo "media-cores: $*" >&2; exit 1; }

# --- CPU lists -------------------------------------------------------------

# Prints a kernel CPU list ("0-3,8,10-11") one CPU a line.
expand() {
    local part lo hi
    local IFS=,
    for part in $1; do
        [ -n "$part" ] || continue
        if [[ "$part" == *-* ]]; then
            lo="${part%-*}"; hi="${part#*-}"
            seq "$lo" "$hi"
        else
            echo "$part"
        fi
    done
}

# Reads CPUs one a line and prints them as a kernel CPU list, in ranges.
compress() {
    local out="" start="" prev="" n
    while read -r n; do
        [ -n "$n" ] || continue
        if [ -z "$start" ]; then
            start="$n"
        elif [ "$n" -ne $((prev + 1)) ]; then
            out+="$(span "$start" "$prev"),"
            start="$n"
        fi
        prev="$n"
    done < <(sort -nu)
    [ -n "$start" ] && out+="$(span "$start" "$prev")"
    echo "$out"
}
span() { if [ "$1" = "$2" ]; then echo "$1"; else echo "$1-$2"; fi; }

# --- derive ----------------------------------------------------------------

# The PCI device directory an anchor names: an interface's device, or a PCI
# address.
anchor_device() {
    local anchor="$1"
    if [ -e "$SYSFS/class/net/$anchor/device" ]; then
        echo "$SYSFS/class/net/$anchor/device"
    elif [ -e "$SYSFS/bus/pci/devices/$anchor" ]; then
        echo "$SYSFS/bus/pci/devices/$anchor"
    else
        die "$anchor is neither a network interface nor a PCI address"
    fi
}

# The first line of its input, read to the end: a reader that stops early
# (head, grep -q) leaves its writer to SIGPIPE, which pipefail and set -e turn
# into a silent exit.
first() { awk 'NR == 1'; }

# A physical core's key: the first CPU of its SMT sibling list.
core_of() { expand "$(cat "$CPU_DIR/cpu$1/topology/thread_siblings_list")" | first; }
siblings_of() { expand "$(cat "$CPU_DIR/cpu$1/topology/thread_siblings_list")"; }
l3_of() { cat "$CPU_DIR/cpu$1/cache/index3/shared_cpu_list"; }

derive() {
    local anchor="${1:-}" count="${2:-}"
    [ -n "$anchor" ] && [ -n "$count" ] ||
        die "usage: media-cores.sh derive <interface|pci-address> <cores>"
    [[ "$count" =~ ^[1-9][0-9]*$ ]] || die "the core count has to be a positive whole number, got $count"

    local device node node_cpus online
    device="$(anchor_device "$anchor")"
    node="$(cat "$device/numa_node" 2>/dev/null || echo -1)"
    online="$(cat "$CPU_DIR/online")"
    if [ "$node" = "-1" ]; then
        node_cpus="$online"
    else
        node_cpus="$(cat "$SYSFS/devices/system/node/node$node/cpulist")"
    fi

    # Performance cores only, on a hybrid part; every core elsewhere.
    local eligible="$node_cpus"
    if [ -e "$SYSFS/devices/cpu_core/cpus" ]; then
        eligible="$(comm -12 <(expand "$node_cpus" | sort) \
            <(expand "$(cat "$SYSFS/devices/cpu_core/cpus")" | sort) | sort -n | compress)"
    fi

    # Group the eligible physical cores by L3, keyed by each group's first CPU.
    local -A group_cores=()
    local cpu core l3 boot_l3
    boot_l3="$(l3_of 0)"
    while read -r cpu; do
        core="$(core_of "$cpu")"
        [ "$core" = "$cpu" ] || continue
        l3="$(l3_of "$cpu")"
        group_cores[$l3]+="$core "
    done < <(expand "$eligible")

    local groups=("${!group_cores[@]}") shared=""
    if [ "${#groups[@]}" -eq 1 ] && [ "${groups[0]}" = "$boot_l3" ]; then
        # One L3 group: only CPU 0's core stays behind, and isolated threads
        # share the cache with housekeeping load.
        group_cores[$boot_l3]="$(tr ' ' '\n' <<<"${group_cores[$boot_l3]}" |
            grep -vx "$(core_of 0)" | tr '\n' ' ')"
        shared="yes"
    else
        unset "group_cores[$boot_l3]"
    fi

    # Whole groups from the far end of the CPU numbering first, then the
    # highest cores of the next, so housekeeping keeps the low, boot-adjacent
    # end and each isolated group is whole where the count allows.
    local -a ordered=() taken=()
    local -A is_taken=()
    mapfile -t ordered < <(for l3 in "${!group_cores[@]}"; do
        echo "$(expand "$l3" | first) $l3"
    done | sort -rn | cut -d' ' -f2)
    local remaining="$count" members
    for l3 in "${ordered[@]}"; do
        mapfile -t members < <(tr ' ' '\n' <<<"${group_cores[$l3]}" | grep . | sort -rn)
        [ "${#members[@]}" -gt 0 ] || continue
        if [ "${#members[@]}" -le "$remaining" ]; then
            taken+=("${members[@]}")
            for core in "${members[@]}"; do is_taken[$core]=1; done
            remaining=$((remaining - ${#members[@]}))
        fi
        [ "$remaining" -eq 0 ] && break
    done
    if [ "$remaining" -gt 0 ]; then
        for l3 in "${ordered[@]}"; do
            mapfile -t members < <(tr ' ' '\n' <<<"${group_cores[$l3]}" | grep . | sort -rn)
            for core in "${members[@]}"; do
                [ "$remaining" -gt 0 ] || break
                [ -z "${is_taken[$core]:-}" ] || continue
                taken+=("$core")
                is_taken[$core]=1
                remaining=$((remaining - 1))
            done
        done
    fi
    [ "$remaining" -eq 0 ] ||
        die "$count cores asked for, and only $((count - remaining)) can be isolated beside CPU 0's $( [ -n "$shared" ] && echo core || echo 'L3 group')"

    local isolated housekeeping
    isolated="$(for core in "${taken[@]}"; do siblings_of "$core"; done | compress)"
    housekeeping="$(comm -23 <(expand "$online" | sort) <(expand "$isolated" | sort) | sort -n | compress)"

    echo "anchor: $anchor (NUMA node $node)"
    echo "isolated: $isolated"
    echo "housekeeping: $housekeeping"
    echo "kargs: irqaffinity=$housekeeping isolcpus=managed_irq,domain,$isolated nohz_full=$isolated rcu_nocbs=$isolated"
    if [ -n "$shared" ]; then
        echo "note: the node has one L3 group, so the isolated cores share the L3 with housekeeping load"
    fi
}

# --- the partition on the command line ---------------------------------------

# Prints the value of one partition argument on the running command line.
cmdline_value() {
    local word
    for word in $(cat "$PROC/cmdline"); do
        if [[ "$word" == "$1="* ]]; then echo "${word#*=}"; return; fi
    done
}
running_isolated() { cmdline_value nohz_full; }
running_housekeeping() { cmdline_value irqaffinity; }

# IRQ numbers with an effective affinity, one a line.
irqs() {
    local dir
    for dir in "$PROC"/irq/[0-9]*; do
        [ -e "$dir/effective_affinity_list" ] && basename "$dir"
    done | sort -n
}
intersects() {
    [ -n "$(comm -12 <(expand "$1" | sort) <(expand "$2" | sort))" ]
}
action_of() {
    sed -n "s/^ *$1: *//p" "$PROC/interrupts" | awk 'NR == 1 {print $NF}'
}

write_affinity() {
    if [ -n "${TILEFIN_AFFINITY_WRITE:-}" ]; then
        "$TILEFIN_AFFINITY_WRITE" "$1" "$2"
    else
        echo "$2" > "$1"
    fi
}

steer() {
    local isolated housekeeping irq effective stuck=0
    isolated="$(running_isolated)"
    if [ -z "$isolated" ]; then
        echo "no isolated set on the command line; nothing to steer"
        return 0
    fi
    housekeeping="$(running_housekeeping)"
    [ -n "$housekeeping" ] || die "nohz_full is set without irqaffinity; the partition is incomplete"

    mkdir -p "$(dirname "$MANAGED_FILE")"
    : > "$MANAGED_FILE"
    for irq in $(irqs); do
        # A managed IRQ refuses the write; isolcpus=managed_irq covers it.
        if ! write_affinity "$PROC/irq/$irq/smp_affinity_list" "$housekeeping" 2>/dev/null; then
            echo "$irq" >> "$MANAGED_FILE"
        fi
    done
    for irq in $(irqs); do
        effective="$(cat "$PROC/irq/$irq/effective_affinity_list")"
        intersects "$effective" "$isolated" || continue
        if grep -qx "$irq" "$MANAGED_FILE"; then
            echo "managed IRQ $irq ($(action_of "$irq")) stays on CPUs $effective"
        else
            echo "movable IRQ $irq ($(action_of "$irq")) is still on CPUs $effective, inside the isolated set $isolated" >&2
            stuck=1
        fi
    done
    [ "$stuck" -eq 0 ] || die "movable IRQs remain on the isolated set"
    echo "every movable IRQ is on the housekeeping set $housekeeping"
}

# --- check -----------------------------------------------------------------

running() {
    if [ -n "${TILEFIN_PROCESSES:-}" ]; then
        grep -qx "$1" "$TILEFIN_PROCESSES"
    else
        pgrep -x "$1" >/dev/null
    fi
}

check() {
    local isolated status=0 key value kernel irq effective kind counts
    isolated="$(running_isolated)"
    if [ -z "$isolated" ]; then
        echo "no partition is set on the command line"
    else
        echo "partition on the command line:"
        for key in "${PARTITION_KEYS[@]}"; do
            value="$(cmdline_value "$key")"
            echo "  $key=${value:-(absent)}"
        done
        for key in isolated nohz_full; do
            kernel="$(cat "$CPU_DIR/$key" 2>/dev/null || true)"
            if [ "$kernel" = "$isolated" ]; then
                echo "  /sys/devices/system/cpu/$key matches: $kernel"
            else
                echo "  /sys/devices/system/cpu/$key is '${kernel}', not $isolated"
                status=1
            fi
        done
        echo "IRQs on the isolated set:"
        for irq in $(irqs); do
            effective="$(cat "$PROC/irq/$irq/effective_affinity_list")"
            intersects "$effective" "$isolated" || continue
            kind="movable"
            grep -qsx "$irq" "$MANAGED_FILE" && kind="managed"
            counts="$(sed -n "s/^ *$irq: *//p" "$PROC/interrupts" | first)"
            echo "  $irq ($(action_of "$irq")) $kind on CPUs $effective: $counts"
            [ "$kind" = "movable" ] && status=1
        done
    fi
    for key in irqbalance tuned; do
        if running "$key"; then
            echo "$key is running and can rewrite IRQ affinity behind the partition"
        fi
    done
    return "$status"
}

case "${1:-}" in
    derive) shift; derive "$@" ;;
    steer) steer ;;
    check) check ;;
    *) die "usage: media-cores.sh derive <interface|pci-address> <cores> | steer | check" ;;
esac
