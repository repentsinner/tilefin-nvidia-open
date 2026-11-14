#!/usr/bin/bash
# Behaviour test for the passthrough sleep guard (§spec:passthrough-host-power).
# The guard runs under systemd-inhibit and must keep running exactly while a
# handover marker exists, so the inhibitor lasts as long as a guest holds the
# GPU. Runs against a temporary marker directory.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/build_files/passthrough-sleep-guard.sh"
TMP="$(mktemp -d)"
trap 'kill "$PID" 2>/dev/null; rm -rf "$TMP"' EXIT
PID=""

fail=0
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; fail=1; }

start_guard() {
    TILEFIN_HANDOVER_STATE_DIR="$TMP/markers" TILEFIN_SLEEP_GUARD_INTERVAL=0.1 \
        bash "$GUARD" &
    PID=$!
}
running() { kill -0 "$PID" 2>/dev/null; }
# wait_exit <seconds> : true if the guard exits within the time given
wait_exit() {
    local end=$((SECONDS + $1))
    while [ "$SECONDS" -le "$end" ]; do
        running || return 0
        sleep 0.1
    done
    return 1
}

# No marker: nothing holds the GPU, so the guard ends at once.
mkdir -p "$TMP/markers"
start_guard
if wait_exit 2; then ok "no marker: the guard exits"; else bad "no marker: the guard exits"; fi

# Missing marker directory (no guest has started since boot): exits too.
rm -rf "$TMP/markers"
start_guard
if wait_exit 2; then ok "no marker directory: the guard exits"; else bad "no marker directory: the guard exits"; fi

# A guest holds the GPU: the guard keeps running.
mkdir -p "$TMP/markers"; : > "$TMP/markers/vm"
start_guard
sleep 0.5
if running; then ok "a marker keeps the guard running"; else bad "a marker keeps the guard running"; fi

# Two guests; one stops: the guard keeps running for the other.
: > "$TMP/markers/vm2"; rm -f "$TMP/markers/vm"
sleep 0.5
if running; then ok "one remaining marker keeps it running"; else bad "one remaining marker keeps it running"; fi

# The last guest stops: the guard ends, releasing the inhibitor.
rm -f "$TMP/markers/vm2"
if wait_exit 2; then ok "the last marker gone: the guard exits"; else bad "the last marker gone: the guard exits"; fi

exit "$fail"
