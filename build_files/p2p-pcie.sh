#!/usr/bin/bash
# Peer-to-peer PCIe mode (§spec:p2p-pcie): the PCIe settings a NIC needs to
# DMA media payload to and from GPU memory, held as machine state on the
# machine that chose them. The image carries this mechanism and no addresses.
#
#   p2p-pcie.sh derive <gpu-pci-address> <interface|nic-pci-address>
#       Derives the root ports above the GPU and the NIC and prints them with
#       the kernel argument that turns their ACS redirect off
#       (§spec:p2p-pcie-derivation). Reads only.
#   p2p-pcie.sh apply <pci-address>
#       Sets the configured NIC's Max Read Request Size to 4096 bytes and
#       records the read-back under /run (§spec:p2p-pcie-read-request). Any
#       other device is left alone. Run as root by tilefin-p2p-pcie@.service,
#       which the udev rule starts on the NIC's add and bind events.
#   p2p-pcie.sh check
#       Reports the configuration, the kernel argument, the IOMMU groups and
#       the recorded registers, and the live registers when run as root
#       (§spec:p2p-pcie-check). Changes nothing.
#
# TILEFIN_SYSFS, TILEFIN_PROC, TILEFIN_RUN and TILEFIN_ETC stand in for /sys,
# /proc, /run and /etc, TILEFIN_SETPCI for setpci, and TILEFIN_EUID for the
# caller's effective user ID, so a test runs every path against fake trees
# (test/p2p-pcie.test.sh).
set -euo pipefail

SYSFS="${TILEFIN_SYSFS:-/sys}"
PROC="${TILEFIN_PROC:-/proc}"
RUN="${TILEFIN_RUN:-/run}"
ETC="${TILEFIN_ETC:-/etc}"
SETPCI="${TILEFIN_SETPCI:-setpci}"
CALLER_EUID="${TILEFIN_EUID:-$EUID}"
CONF="$ETC/tilefin/p2p-pcie.conf"
PASSTHROUGH_CONF="$ETC/tilefin/gpu-passthrough.conf"
STATUS_DIR="$RUN/tilefin/p2p-pcie"
PCI_DIR="$SYSFS/bus/pci/devices"

KARG_OPTION="disable_acs_redir"
# PCI class codes: display controllers are 0x03xxxx, network controllers
# 0x02xxxx.
CLASS_DISPLAY="0x03"
CLASS_NETWORK="0x02"
# Device Control (PCI Express capability + 8), bits 14:12: the Max Read
# Request Size, encoded as log2(bytes) - 7. 101b is 4096 bytes.
DEVCTL_REG="CAP_EXP+8.w"
MRRS_BITS="5000"
MRRS_MASK="7000"
MRRS_SHIFT=12
MRRS_FIELD=7
MRRS_BASE=128
MRRS_WANTED=4096
# ACS Control (ACS extended capability + 6): bit 2 P2P Request Redirect,
# bit 3 P2P Completion Redirect.
ACS_CTRL_REG="ECAP_ACS+6.w"
ACS_RR=$((1 << 2))
ACS_CR=$((1 << 3))

die() { echo "p2p-pcie: $*" >&2; exit 1; }

# --- devices -----------------------------------------------------------------

# The PCI address a NIC argument names: an interface's device, or an address.
nic_address() {
    if [ -e "$SYSFS/class/net/$1/device" ]; then
        basename "$(readlink -f "$SYSFS/class/net/$1/device")"
    elif [ -e "$PCI_DIR/$1" ]; then
        echo "$1"
    else
        die "$1 is neither a network interface nor a PCI address"
    fi
}

# Fails unless the device exists and its class starts with the given prefix.
require_class() {
    local bdf="$1" prefix="$2" what="$3" class
    [ -e "$PCI_DIR/$bdf" ] || die "$bdf is not a PCI address on this machine"
    class="$(cat "$PCI_DIR/$bdf/class")"
    [[ "$class" == "$prefix"* ]] || die "$bdf is not a $what (PCI class $class)"
}

# The root port above an endpoint: the first device on its sysfs path below
# the host bridge (pciDDDD:BB). Behind a switch that is not the parent bridge,
# and the root port is where the root complex applies ACS redirect.
root_port() {
    local path rest
    path="$(readlink -f "$PCI_DIR/$1")"
    rest="${path#*/devices/pci}"
    rest="${rest#*/}"
    [ "${rest%%/*}" != "$rest" ] || die "$1 sits on the root bus, with no root port above it"
    echo "${rest%%/*}"
}

parent_of() { basename "$(dirname "$(readlink -f "$PCI_DIR/$1")")"; }

iommu_group() {
    local link="$PCI_DIR/$1/iommu_group"
    if [ -e "$link" ]; then basename "$(readlink -f "$link")"; fi
}

# --- configuration -----------------------------------------------------------

conf_value() { sed -n "s/^$1=//p" "$CONF" | awk 'END { print }'; }

# --- derive ------------------------------------------------------------------

derive() {
    local gpu="${1:-}" nic_arg="${2:-}" nic ports karg
    [ -n "$gpu" ] && [ -n "$nic_arg" ] ||
        die "usage: p2p-pcie.sh derive <gpu-pci-address> <interface|nic-pci-address>"
    if [ -e "$PASSTHROUGH_CONF" ]; then
        die "GPU passthrough is set up ($PASSTHROUGH_CONF). This mode merges IOMMU groups, so a VM can no longer take the GPU alone. Delete $PASSTHROUGH_CONF and $ETC/niri/gpu-passthrough.kdl first."
    fi
    require_class "$gpu" "$CLASS_DISPLAY" "display controller"
    nic="$(nic_address "$nic_arg")"
    require_class "$nic" "$CLASS_NETWORK" "network controller"

    ports="$( { root_port "$gpu"; root_port "$nic"; } | sort -u | tr '\n' ' ')"
    ports="${ports% }"
    # GRUB's BLS loader runs the options line as GRUB script, where a bare
    # semicolon ends the command and drops the rest of the command line.
    karg="pci=$KARG_OPTION=${ports// /\\;}"

    echo "gpu: $gpu"
    echo "nic: $nic"
    echo "root ports: $ports"
    echo "kargs: $karg"
}

# --- apply -------------------------------------------------------------------

mrrs_of() { echo $(( MRRS_BASE << ((16#$1 >> MRRS_SHIFT) & MRRS_FIELD) )); }

# Writes a status file atomically, so a reader never sees half of it.
write_status() {
    local file="$STATUS_DIR/$1" tmp
    shift
    mkdir -p "$STATUS_DIR"
    tmp="$(mktemp "$file.XXXXXX")"
    printf '%s\n' "$@" > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$file"
}

apply() {
    local bdf="${1:-}" nic devctl mrrs port ctrl
    [ -n "$bdf" ] || die "usage: p2p-pcie.sh apply <pci-address>"
    [ -e "$CONF" ] || return 0
    nic="$(conf_value NIC)"
    [ "$bdf" = "$nic" ] || return 0

    "$SETPCI" -s "$nic" "$DEVCTL_REG=$MRRS_BITS:$MRRS_MASK"
    devctl="$("$SETPCI" -s "$nic" "$DEVCTL_REG")"
    mrrs="$(mrrs_of "$devctl")"
    write_status "$nic" "role=nic" "devctl=0x$devctl" "mrrs=$mrrs"
    echo "NIC $nic: Device Control 0x$devctl, max read request $mrrs bytes"

    # The root ports' ACS Control, read here because only root can read it,
    # so the unprivileged check can report it.
    for port in $(conf_value ROOT_PORTS); do
        if ctrl="$("$SETPCI" -s "$port" "$ACS_CTRL_REG" 2>/dev/null)"; then
            write_status "$port" "role=root-port" "acs_ctrl=0x$ctrl"
        else
            write_status "$port" "role=root-port" "acs_ctrl=absent"
        fi
    done

    [ "$mrrs" -eq "$MRRS_WANTED" ] ||
        die "NIC $nic reads back a $mrrs-byte max read request after writing $MRRS_WANTED"
}

# --- check -------------------------------------------------------------------

# The device list of the last disable_acs_redir option on the command line,
# one device a line. The kernel keeps only the last one it parses.
cmdline_ports() {
    local word opt list=""
    for word in $(cat "$PROC/cmdline"); do
        [[ "$word" == pci=* ]] || continue
        local IFS=,
        for opt in ${word#pci=}; do
            [[ "$opt" == "$KARG_OPTION="* ]] && list="${opt#*=}"
        done
        unset IFS
    done
    [ -n "$list" ] && tr ';' '\n' <<<"$list"
    return 0
}

status_value() { sed -n "s/^$2=//p" "$STATUS_DIR/$1" 2>/dev/null; }

redirect_bits() {
    local ctrl=$((16#$1)) out=""
    (( ctrl & ACS_RR )) && out+="RR "
    (( ctrl & ACS_CR )) && out+="CR "
    echo "${out% }"
}

check() {
    local status=0 gpu nic ports port derived listed dev group port_group ctrl bits mrrs devctl
    listed="$(cmdline_ports)"
    if [ ! -e "$CONF" ]; then
        echo "P2P PCIe mode is not set ($CONF is absent)"
        if [ -n "$listed" ]; then
            echo "the command line still turns ACS redirect off on: $(tr '\n' ' ' <<<"$listed")"
            echo "  remove it with: ujust p2p-pcie --remove"
            status=1
        fi
        return "$status"
    fi

    gpu="$(conf_value GPU)"
    nic="$(conf_value NIC)"
    ports="$(conf_value ROOT_PORTS)"
    echo "GPU: $gpu (IOMMU group $(iommu_group "$gpu"))"
    echo "NIC: $nic (IOMMU group $(iommu_group "$nic"))"
    echo "root ports: $ports"

    derived="$( { root_port "$gpu"; root_port "$nic"; } 2>/dev/null | sort -u | tr '\n' ' ')"
    if [ "${derived% }" != "$ports" ]; then
        echo "  the topology now gives root ports '${derived% }'; run ujust p2p-pcie again"
        status=1
    fi

    echo "kernel argument pci=$KARG_OPTION:"
    for port in $ports; do
        if grep -qx "$port" <<<"$listed"; then
            echo "  $port: on the command line"
        else
            echo "  $port: missing from the command line"
            status=1
        fi
    done

    # With redirect off on its root port, the kernel no longer counts the path
    # as isolated and puts an endpoint directly below it in the root port's
    # group. Behind a switch, the switch's own ACS can keep the group apart.
    echo "IOMMU groups:"
    for dev in "$gpu" "$nic"; do
        port="$(root_port "$dev" 2>/dev/null || true)"
        group="$(iommu_group "$dev")"
        port_group="$(iommu_group "$port")"
        if [ -z "$group" ]; then
            echo "  $dev: no IOMMU group; the IOMMU is off"
        elif [ "$(parent_of "$dev")" != "$port" ]; then
            echo "  $dev: group $group, behind a switch below root port $port (not checked)"
        elif [ "$group" = "$port_group" ]; then
            echo "  $dev: shares group $group with root port $port"
        else
            echo "  $dev: group $group, apart from root port $port (group ${port_group:-none}); redirect is still on"
            status=1
        fi
    done
    if [ -n "$(iommu_group "$gpu")" ] && [ "$(iommu_group "$gpu")" = "$(iommu_group "$nic")" ]; then
        echo "  the GPU and the NIC share group $(iommu_group "$gpu")"
    fi

    echo "recorded by tilefin-p2p-pcie@$nic.service ($STATUS_DIR):"
    mrrs="$(status_value "$nic" mrrs)"
    if [ -z "$mrrs" ]; then
        echo "  $nic: no record; the service has not run since boot"
        status=1
    elif [ "$mrrs" -eq "$MRRS_WANTED" ]; then
        echo "  $nic: max read request $mrrs bytes"
    else
        echo "  $nic: max read request $mrrs bytes, not $MRRS_WANTED"
        status=1
    fi
    for port in $ports; do
        ctrl="$(status_value "$port" acs_ctrl)"
        case "$ctrl" in
            "") echo "  $port: no record" ;;
            absent) echo "  $port: no ACS capability" ;;
            *)
                bits="$(redirect_bits "${ctrl#0x}")"
                if [ -n "$bits" ]; then
                    echo "  $port: ACS Control $ctrl, $bits still set"
                    status=1
                else
                    echo "  $port: ACS Control $ctrl, redirect off"
                fi
                ;;
        esac
    done

    if [ "$CALLER_EUID" -ne 0 ]; then
        echo "Run with sudo to read the live ACS Control and Device Control registers."
        return "$status"
    fi
    echo "live registers:"
    for port in $ports; do
        if ! ctrl="$("$SETPCI" -s "$port" "$ACS_CTRL_REG" 2>/dev/null)"; then
            echo "  $port: no ACS capability"
            continue
        fi
        bits="$(redirect_bits "$ctrl")"
        if [ -n "$bits" ]; then
            echo "  $port: ACS Control 0x$ctrl, $bits set"
            status=1
        else
            echo "  $port: ACS Control 0x$ctrl, redirect off"
        fi
    done
    devctl="$("$SETPCI" -s "$nic" "$DEVCTL_REG")"
    mrrs="$(mrrs_of "$devctl")"
    if [ "$mrrs" -eq "$MRRS_WANTED" ]; then
        echo "  $nic: Device Control 0x$devctl, max read request $mrrs bytes"
    else
        echo "  $nic: Device Control 0x$devctl, max read request $mrrs bytes, not $MRRS_WANTED"
        status=1
    fi
    return "$status"
}

case "${1:-}" in
    derive) shift; derive "$@" ;;
    apply) shift; apply "$@" ;;
    check) check ;;
    *) die "usage: p2p-pcie.sh derive <gpu-pci-address> <interface|nic-pci-address> | apply <pci-address> | check" ;;
esac
