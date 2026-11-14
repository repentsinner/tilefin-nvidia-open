#!/usr/bin/bash
# Behaviour test for the `ujust vm` recipe (§spec:vm-power-recipe).
# Runs the recipe against a stub virsh that keeps domain state in files and
# records every call, so no real VM is started or stopped.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JUSTFILE="$ROOT/build_files/tilefin.just"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/virsh" <<'STUB'
#!/usr/bin/bash
# Stub virsh. State: $STUB_DIR/<domain>.state holds "running" or "shut off".
echo "$*" >> "$STUB_DIR/calls"
[ "${1:-}" = "--connect" ] && shift 2
cmd="${1:-}"; shift || true
state_file() { echo "$STUB_DIR/$1.state"; }
exists() { [ -f "$(state_file "$1")" ]; }
case "$cmd" in
    list)
        for f in "$STUB_DIR"/*.state; do
            [ -f "$f" ] && basename "$f" .state
        done
        echo ""   # virsh ends --name listings with a blank line
        ;;
    dominfo)
        exists "$1" || { echo "error: failed to get domain '$1'" >&2; exit 1; }
        ;;
    domstate)
        exists "$1" || { echo "error: failed to get domain '$1'" >&2; exit 1; }
        cat "$(state_file "$1")"
        ;;
    dumpxml)
        exists "$1" || exit 1
        echo "<domain><name>$1</name><devices>${STUB_XML_DEVICES:-}</devices></domain>"
        ;;
    start)
        if [ -n "${STUB_START_ERROR:-}" ]; then
            echo "error: Failed to start domain '$1'" >&2
            echo "error: $STUB_START_ERROR" >&2
            exit 1
        fi
        echo "running" > "$(state_file "$1")"
        echo "Domain '$1' started"
        ;;
    shutdown)
        [ "${STUB_SHUTDOWN_HONOURED:-1}" = 1 ] && echo "shut off" > "$(state_file "$1")"
        echo "Domain '$1' is being shutdown"
        ;;
    destroy)
        echo "shut off" > "$(state_file "$1")"
        echo "Domain '$1' destroyed"
        ;;
    *)
        echo "stub virsh: unhandled command: $cmd" >&2
        exit 2
        ;;
esac
STUB
chmod +x "$STUB_BIN/virsh"

fail=0
OUT=""; RC=0

# reset <domain=state>... : fresh stub state for one case
reset() {
    STUB_DIR="$TMP/case.$RANDOM$RANDOM"
    mkdir -p "$STUB_DIR"
    : > "$STUB_DIR/calls"
    local pair
    for pair in "$@"; do
        echo "${pair#*=}" > "$STUB_DIR/${pair%%=*}.state"
    done
    export STUB_DIR
}

# run <env assignments...> -- <recipe args...> : stdin is not a terminal
run() {
    local envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    OUT="$(env PATH="$STUB_BIN:$PATH" TILEFIN_VM_POLL_INTERVAL=0.1 \
        TILEFIN_VM_SHUTDOWN_TIMEOUT=1 "${envs[@]}" \
        just --justfile "$JUSTFILE" --working-directory "$ROOT" vm "$@" 2>&1 </dev/null)"
    # shellcheck disable=SC2034 # read inside the condition strings check() evals
    RC=$?
}

ok()   { printf 'ok   - %s\n' "$1"; }
bad()  { printf 'FAIL - %s\n' "$1"; printf '       output: %s\n' "$OUT" | head -5; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
called()     { grep -qE "(^| )$1( |$)" "$STUB_DIR/calls"; }
state_of()   { cat "$STUB_DIR/$1.state"; }

# status
reset win=running;          run -- status
check "status names the only VM and its state" '[ $RC = 0 ] && grep -q win <<<"$OUT" && grep -q running <<<"$OUT"'
reset win="shut off";       run --
check "no action means status"                 '[ $RC = 0 ] && grep -q "shut off" <<<"$OUT" && ! called start'

# start
reset win="shut off";       run -- start
check "start boots a stopped VM"               '[ $RC = 0 ] && called start && [ "$(state_of win)" = running ]'
reset win=running;          run -- start
check "start leaves a running VM alone"        '[ $RC = 0 ] && ! called start && grep -qi "already running" <<<"$OUT"'
reset win="shut off";       run STUB_START_ERROR="The NVIDIA GPU is in use on the host: 1234 firefox" -- start
check "start surfaces libvirt's refusal"       '[ $RC != 0 ] && grep -q "1234 firefox" <<<"$OUT"'

# stop
reset win=running;          run -- stop
check "stop shuts a VM down gracefully"        '[ $RC = 0 ] && called shutdown && ! called destroy && [ "$(state_of win)" = "shut off" ]'
reset win=running;          run STUB_SHUTDOWN_HONOURED=0 -- stop
check "stop never forces on its own"           '[ $RC != 0 ] && called shutdown && ! called destroy && grep -q -- "--force" <<<"$OUT"'
reset win=running;          run -- stop --force
check "stop --force powers off at once"        '[ $RC = 0 ] && called destroy && ! called shutdown && [ "$(state_of win)" = "shut off" ]'
reset win="shut off";       run -- stop
check "stop leaves a stopped VM alone"         '[ $RC = 0 ] && ! called shutdown && ! called destroy'

# choosing the VM
reset;                      run -- start
check "no VMs: start fails with guidance"      '[ $RC != 0 ] && grep -qi "no vm" <<<"$OUT"'
reset win="shut off" lin="shut off"; run -- start
check "several VMs, no name, no tty: asks for a name" '[ $RC != 0 ] && ! called start && grep -q win <<<"$OUT" && grep -q lin <<<"$OUT"'
reset win="shut off" lin="shut off"; run -- start lin
check "a named VM is the one acted on"         '[ $RC = 0 ] && [ "$(state_of lin)" = running ] && [ "$(state_of win)" = "shut off" ]'
reset win="shut off";       run -- start nope
check "an unknown name fails and lists VMs"    '[ $RC != 0 ] && grep -q nope <<<"$OUT" && grep -q win <<<"$OUT"'
reset win=running;          run -- stop win --force
check "--force works after the name too"       '[ $RC = 0 ] && called destroy'

# usage
reset win=running;          run -- reboot
check "an unknown action fails with usage"     '[ $RC != 0 ] && grep -qi "usage" <<<"$OUT"'

# Looking Glass hint only for guests that have its shared memory
reset win="shut off";       run STUB_XML_DEVICES="<shmem name='looking-glass'/>" -- start
check "start points at Looking Glass when the guest has it" '[ $RC = 0 ] && grep -q "Looking Glass" <<<"$OUT"'
reset win="shut off";       run -- start
check "no Looking Glass hint without its shared memory"    '[ $RC = 0 ] && ! grep -q "Looking Glass" <<<"$OUT"'

exit "$fail"
