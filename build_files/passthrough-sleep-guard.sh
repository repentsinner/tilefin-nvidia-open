#!/usr/bin/env bash
# Runs under systemd-inhibit (tilefin-passthrough-sleep-guard.service) and
# exits once no guest holds the passed-through GPU, which releases the sleep
# inhibitor (§spec:passthrough-host-power). The handover hook keeps one marker
# per guest that took the GPU (§spec:gpu-handover).
set -euo pipefail

# Overridable so test/passthrough-sleep-guard.test.sh runs against fakes.
MARKERS="${TILEFIN_HANDOVER_STATE_DIR:-/run/libvirt/nvidia-handover}"
# How long sleep stays blocked after the last guest stops, at most.
INTERVAL="${TILEFIN_SLEEP_GUARD_INTERVAL:-5}"

while compgen -G "$MARKERS/*" >/dev/null; do
    sleep "$INTERVAL"
done
