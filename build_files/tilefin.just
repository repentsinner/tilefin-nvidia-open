# Tilefin custom recipes

# Provision user environment: native CLI tools, Flatpaks, userbox container (optional: override image)
setup-user image="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Static hostname. The installer never asks: Anaconda keeps the hostname
    # field inside the Network spoke, which the ISO kickstart already
    # satisfies, so the spoke is never flagged and the field is never seen.
    # Without a static hostname the greeter falls back to the kernel default
    # and announces the machine as "fedora", and the only name it answers to
    # comes from a DHCP lease rather than from the machine itself.
    CURRENT_STATIC=$(hostnamectl --static 2>/dev/null || true)
    CURRENT_TRANSIENT=$(hostnamectl --transient 2>/dev/null | cut -d. -f1 || true)
    HOSTNAME_NEW=$(gum input --header="Static hostname" \
        --value="${CURRENT_STATIC:-${CURRENT_TRANSIENT:-tilefin}}")
    if [ -n "$HOSTNAME_NEW" ] && [ "$HOSTNAME_NEW" != "$CURRENT_STATIC" ]; then
        echo "==> Setting static hostname to ${HOSTNAME_NEW} (needs sudo)..."
        sudo hostnamectl set-hostname "$HOSTNAME_NEW"
    fi

    # Login shell. Anaconda creates the account with /bin/bash, but the image
    # ships fish and carries fish-specific integration (tool-aliases.fish,
    # local-path.fish), so the choice belongs here rather than being
    # rediscovered on every machine. /bin and /usr/bin are the same directory
    # on Fedora; normalise so the current shell matches an offered option.
    CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
    CURRENT_SHELL_NORM=${CURRENT_SHELL/#\/bin\//\/usr\/bin\/}
    SHELL_NEW=$(grep -E '^/usr/bin/(bash|fish|zsh)$' /etc/shells | sort -u \
        | gum choose --header="Login shell" --selected="$CURRENT_SHELL_NORM")
    if [ -n "$SHELL_NEW" ] && [ "$SHELL_NEW" != "$CURRENT_SHELL_NORM" ]; then
        echo "==> Setting login shell to ${SHELL_NEW} (needs sudo)..."
        sudo usermod -s "$SHELL_NEW" "$USER"
        echo "    Takes effect at next login."
    fi

    echo ""
    echo "Select components to install (space to toggle, enter to confirm):"
    echo ""

    # Native CLI tools selection
    NATIVE_TOOLS=$(gum choose --no-limit --selected="Claude Code,uv,mise,gh,chezmoi,lint gates" \
        "Claude Code" \
        "uv" \
        "mise" \
        "gh" \
        "chezmoi" \
        "lint gates" \
        "kubernetes")

    # Flatpak apps selection
    FLATPAK_APPS=$(gum choose --no-limit --selected="Firefox,Bitwarden" \
        "Firefox" \
        "Bitwarden" \
        "Slack" \
        "Discord" \
        "Signal" \
        "Proton VPN" \
        "Trayscale")

    # Userbox
    INSTALL_USERBOX=$(gum choose --selected="Yes" "Yes" "No" \
        --header="Assemble userbox container?")

    # Install selected native CLI tools
    if [ -n "$NATIVE_TOOLS" ]; then
        echo ""
        echo "==> Installing native CLI tools to ~/.local/bin..."
        if echo "$NATIVE_TOOLS" | grep -q "Claude Code"; then
            echo "  Claude Code..."
            curl -fsSL https://claude.ai/install.sh | bash
        fi
        if echo "$NATIVE_TOOLS" | grep -q "uv"; then
            echo "  uv..."
            curl -LsSf https://astral.sh/uv/install.sh | sh
        fi
        if echo "$NATIVE_TOOLS" | grep -q "mise"; then
            echo "  mise..."
            curl -fsSL https://mise.run | sh
        fi
        # gh and chezmoi live here rather than in the image: they carry no
        # image-side shell configuration and update faster than the OS
        # (§spec:image-excludes-user-tools). The match is anchored: an
        # unanchored "gh" hits any selection containing those two letters.
        if echo "$NATIVE_TOOLS" | grep -qx "gh"; then
            echo "  gh..."
            GH_VER=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
                | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)
            curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" \
                | tar xz -C /tmp
            install -Dm755 "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" "$HOME/.local/bin/gh"
            rm -rf "/tmp/gh_${GH_VER}_linux_amd64"
        fi
        if echo "$NATIVE_TOOLS" | grep -qx "chezmoi"; then
            echo "  chezmoi..."
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        fi
        # shellcheck only. Project ci.sh scripts call it by name and guard it
        # with `command -v`, so an absent copy is skipped in silence and a
        # local run reports a success the remote gate would not
        # (§spec:lint-gates-on-path). Nothing resolves it on demand for them.
        #
        # vale and the markdown linter are deliberately absent: the governance
        # contract pins both and resolves them itself, through mise and uvx. A
        # copy installed here is a second version to drift from that pin, not
        # a convenience.
        if echo "$NATIVE_TOOLS" | grep -qx "lint gates"; then
            echo "  lint gates (shellcheck)..."
            # Upstream release binary; the PyPI repackage is third-party.
            SC_URL=$(curl -fsSL https://api.github.com/repos/koalaman/shellcheck/releases/latest \
                | grep -oE 'https://[^"]*linux\.x86_64\.tar\.xz' | head -1)
            curl -fsSL "$SC_URL" | tar xJ -C /tmp
            install -Dm755 /tmp/shellcheck-*/shellcheck "$HOME/.local/bin/shellcheck"
            rm -rf /tmp/shellcheck-*
        fi
        # Kubernetes clients, through mise so the set is declared in one place
        # and updates without an image rebuild. Versions are deliberately
        # loose: kubectl is supported within one minor of the API server and
        # patch versions do not affect compatibility, so one set of clients
        # serves every cluster we reach (§spec:k8s-clients). helm is held at
        # 3.21 because a bare "3" resolves to a release candidate.
        if echo "$NATIVE_TOOLS" | grep -qx "kubernetes"; then
            echo "  kubernetes clients..."
            "$HOME/.local/bin/mise" use -g --yes \
                kubectl@latest \
                talosctl@latest \
                helm@3.21 \
                kubeseal@latest \
                mc@latest \
                kind@latest
        fi
    fi

    # Install selected Flatpak apps
    if [ -n "$FLATPAK_APPS" ]; then
        echo ""
        echo "==> Installing Flatpak apps..."
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        FLATPAK_IDS=()
        echo "$FLATPAK_APPS" | grep -q "Firefox"   && FLATPAK_IDS+=("org.mozilla.firefox")
        echo "$FLATPAK_APPS" | grep -q "Bitwarden" && FLATPAK_IDS+=("com.bitwarden.desktop")
        echo "$FLATPAK_APPS" | grep -q "Slack"     && FLATPAK_IDS+=("com.slack.Slack")
        echo "$FLATPAK_APPS" | grep -q "Discord"    && FLATPAK_IDS+=("com.discordapp.Discord")
        echo "$FLATPAK_APPS" | grep -q "Signal"     && FLATPAK_IDS+=("org.signal.Signal")
        echo "$FLATPAK_APPS" | grep -q "Proton VPN" && FLATPAK_IDS+=("com.protonvpn.www")
        echo "$FLATPAK_APPS" | grep -q "Trayscale"  && FLATPAK_IDS+=("dev.deedles.Trayscale")
        if [ ${#FLATPAK_IDS[@]} -gt 0 ]; then
            flatpak install --user --noninteractive flathub "${FLATPAK_IDS[@]}"
        fi
    fi

    # Wayland overrides for the user Flatpak installation (§spec:flatpak-override-scope).
    # build.sh writes the same overrides to /var/lib/flatpak/overrides/global,
    # but Flatpak reads overrides from the installation an app belongs to, and
    # everything here installs --user. Unconditional: the overrides apply to
    # apps installed later too. flatpak override merges into an existing
    # global file, so re-running setup-user preserves per-user grants.
    echo ""
    echo "==> Applying Wayland Flatpak overrides (user installation)..."
    flatpak override --user --socket=wayland
    flatpak override --user --env=ELECTRON_ENABLE_WAYLAND=1
    flatpak override --user --env=ELECTRON_OZONE_PLATFORM_HINT=wayland

    # Assemble userbox container
    if [ "$INSTALL_USERBOX" = "Yes" ]; then
        echo ""
        echo "==> Assembling userbox container..."
        INI="$HOME/.config/distrobox/userbox.ini"
        if [ ! -f "$INI" ]; then
            echo "Error: $INI not found."
            echo "Expected at account creation via /etc/skel."
            exit 1
        fi
        if [ -n "{{image}}" ]; then
            echo "  Overriding image to: {{image}}"
            sed -i 's|^image=.*|image={{image}}|' "$INI"
        fi
        distrobox assemble create --replace --file "$INI"
    fi

    echo ""
    echo "==> Done. Restart your shell or run: source ~/.bashrc"

# Toggle production-mode update lock (--start | --stop | --start-from-current)
production-mode mode="--start":
    #!/usr/bin/env bash
    set -euo pipefail

    FLAG_DIR="/etc/tilefin"
    FLAG_FILE="${FLAG_DIR}/production-mode"

    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }

    case "{{ mode }}" in
        --start|--start-from-current)
            STAGED_VERSION=$(rpm-ostree status --json 2>/dev/null \
                | jq -r '[.deployments[] | select(.staged)][0].version // empty')

            UNSTAGE="no"
            if [ -n "${STAGED_VERSION}" ]; then
                if [ "{{ mode }}" = "--start-from-current" ]; then
                    UNSTAGE="yes"
                else
                    echo "A deployment is already staged: ${STAGED_VERSION}"
                    echo ""
                    CHOICE=$(gum choose --selected="Keep staged deployment" \
                        --header="Production mode blocks future staging. What about the existing one?" \
                        "Keep staged deployment" \
                        "Unstage (next reboot keeps current image)")
                    if [ "${CHOICE}" = "Unstage (next reboot keeps current image)" ]; then
                        UNSTAGE="yes"
                    fi
                fi
            fi

            if [ "${UNSTAGE}" = "yes" ]; then
                echo "==> Unstaging deployment ${STAGED_VERSION}..."
                sudoif rpm-ostree cleanup -p
            fi

            echo "==> Enabling production mode..."
            sudoif install -d -m 755 "${FLAG_DIR}"
            sudoif touch "${FLAG_FILE}"
            echo "Flag created: ${FLAG_FILE}"
            echo "rpm-ostreed-automatic.service is now blocked at the timer."
            echo "Manual updates (bootc upgrade, rpm-ostree update, ujust update) still work."
            pkill -RTMIN+8 waybar 2>/dev/null || true
            ;;
        --stop)
            if [ -e "${FLAG_FILE}" ]; then
                echo "==> Disabling production mode..."
                sudoif rm -f "${FLAG_FILE}"
                echo "Flag removed: ${FLAG_FILE}"
                echo "Auto-staging resumes on the next rpm-ostreed-automatic.timer firing."
                pkill -RTMIN+8 waybar 2>/dev/null || true
            else
                echo "Production mode is already off (${FLAG_FILE} does not exist)."
            fi
            ;;
        *)
            echo "Usage: ujust production-mode [--start | --stop | --start-from-current]"
            echo ""
            echo "  --start                Enable update lock. Interactive if a deployment is staged."
            echo "  --start-from-current   Enable update lock and unstage any staged deployment."
            echo "  --stop                 Disable update lock; auto-staging resumes."
            exit 1
            ;;
    esac

# Toggle hot-development mode: idle display sleep and lock, no auto-suspend (--start | --stop)
hot-development mode="--start":
    #!/usr/bin/env bash
    set -euo pipefail

    FLAG_DIR="/etc/tilefin"
    FLAG_FILE="${FLAG_DIR}/hot-development"

    case "{{ mode }}" in
        --start)
            echo "==> Enabling hot-development mode..."
            sudo install -d -m 755 "${FLAG_DIR}"
            sudo touch "${FLAG_FILE}"
            echo "Flag created: ${FLAG_FILE}"
            echo "Idle display-off and lock still fire; the machine no longer auto-suspends."
            if [ -e "${FLAG_DIR}/production-mode" ]; then
                echo "Note: production mode is on and takes precedence — idle display-off and lock stay off."
            fi
            pkill -RTMIN+8 waybar 2>/dev/null || true
            ;;
        --stop)
            if [ -e "${FLAG_FILE}" ]; then
                echo "==> Disabling hot-development mode..."
                sudo rm -f "${FLAG_FILE}"
                echo "Flag removed: ${FLAG_FILE}"
                echo "Time-gated auto-suspend resumes outside business hours."
                pkill -RTMIN+8 waybar 2>/dev/null || true
            else
                echo "Hot-development mode is already off (${FLAG_FILE} does not exist)."
            fi
            ;;
        *)
            echo "Usage: ujust hot-development [--start | --stop]"
            echo ""
            echo "  --start   Hold auto-suspend so background work survives idle periods."
            echo "  --stop    Resume time-gated auto-suspend (§spec:auto-suspend)."
            exit 1
            ;;
    esac

# Start, stop, or show a libvirt VM (start | stop [--force] | status) [name]
[group('Virtualization')]
[positional-arguments]
vm action="status" *args:
    #!/usr/bin/env bash
    set -euo pipefail

    # §spec:vm-power-recipe. The system connection is where VMs that pass a
    # host device through live; the session connection cannot hold them.
    VIRSH=(virsh --connect qemu:///system)
    # Windows can take a minute or more to finish shutting down, longer while
    # it installs updates. Past this, the recipe stops waiting, never forcing.
    SHUTDOWN_TIMEOUT="${TILEFIN_VM_SHUTDOWN_TIMEOUT:-120}"
    POLL_INTERVAL="${TILEFIN_VM_POLL_INTERVAL:-2}"

    usage() {
        echo "Usage: ujust vm [status | start | stop [--force]] [name]"
        echo ""
        echo "  status         Show the VM's state (the default)."
        echo "  start          Start the VM."
        echo "  stop           Ask the guest to shut down, and wait for it."
        echo "  stop --force   Power the VM off at once, without asking the guest."
        echo ""
        echo "  name           Needed only when more than one VM is defined."
    }

    ACTION="${1:-status}"
    shift || true
    NAME=""
    FORCE=false
    for arg in "$@"; do
        case "$arg" in
            --force) FORCE=true ;;
            -*) usage; exit 1 ;;
            *) NAME="$arg" ;;
        esac
    done
    case "$ACTION" in
        status|start|stop) ;;
        *) usage; exit 1 ;;
    esac

    mapfile -t VMS < <("${VIRSH[@]}" list --all --name | sed '/^$/d')
    if [ -n "$NAME" ]; then
        if ! "${VIRSH[@]}" dominfo "$NAME" >/dev/null 2>&1; then
            echo "No VM named ${NAME}. Defined VMs: ${VMS[*]:-none}" >&2
            exit 1
        fi
    elif [ "${#VMS[@]}" -eq 0 ]; then
        echo "No VMs are defined. Create one with virt-manager." >&2
        exit 1
    elif [ "${#VMS[@]}" -eq 1 ]; then
        NAME="${VMS[0]}"
    elif [ -t 0 ]; then
        NAME=$(gum choose --header="Which VM?" "${VMS[@]}")
    else
        echo "More than one VM is defined; name one: ${VMS[*]}" >&2
        echo "Example: ujust vm ${ACTION} ${VMS[0]}" >&2
        exit 1
    fi

    state() { "${VIRSH[@]}" domstate "$NAME" 2>/dev/null | sed '/^$/d'; }

    case "$ACTION" in
        status)
            echo "${NAME}: $(state)"
            ;;
        start)
            if [ "$(state)" = "running" ]; then
                echo "${NAME} is already running."
                exit 0
            fi
            # A refusal, such as the GPU handover naming processes that hold
            # the GPU (§spec:gpu-handover), arrives as virsh's own error.
            "${VIRSH[@]}" start "$NAME" >/dev/null
            echo "Started ${NAME}."
            if "${VIRSH[@]}" dumpxml "$NAME" | grep -q "<shmem name=['\"]looking-glass['\"]"; then
                echo "Open Looking Glass once the guest has booted."
            fi
            ;;
        stop)
            if [ "$(state)" != "running" ]; then
                echo "${NAME} is not running."
                exit 0
            fi
            if [ "$FORCE" = true ]; then
                "${VIRSH[@]}" destroy "$NAME" >/dev/null
                echo "${NAME} is powered off."
                exit 0
            fi
            "${VIRSH[@]}" shutdown "$NAME" >/dev/null
            echo "Asked ${NAME} to shut down; waiting up to ${SHUTDOWN_TIMEOUT} s..."
            deadline=$(( SECONDS + SHUTDOWN_TIMEOUT ))
            while [ "$SECONDS" -lt "$deadline" ]; do
                if [ "$(state)" != "running" ]; then
                    echo "${NAME} has shut down."
                    exit 0
                fi
                sleep "$POLL_INTERVAL"
            done
            echo "${NAME} did not shut down within ${SHUTDOWN_TIMEOUT} s." >&2
            echo "If the guest is stuck, power it off with: ujust vm stop --force ${NAME}" >&2
            exit 1
            ;;
    esac

# Prepare this machine to pass its NVIDIA GPU to a VM, and report what remains
[group('Virtualization')]
setup-gpu-passthrough:
    #!/usr/bin/env bash
    set -euo pipefail

    # §spec:passthrough-setup. Overridable so test/setup-gpu-passthrough.test.sh
    # runs against fakes.
    SYSFS="${TILEFIN_SYSFS:-/sys}"
    CPUINFO="${TILEFIN_CPUINFO:-/proc/cpuinfo}"
    ETC="${TILEFIN_ETC:-/etc}"
    ASSUME_YES="${TILEFIN_ASSUME_YES:-}"
    VIRSH=(virsh --connect qemu:///system)
    NVIDIA_VENDOR="0x10de"
    WORKSPACE="vm"
    MIB=$((1024 * 1024))

    INTERACTIVE=false
    [ -t 0 ] && INTERACTIVE=true
    # Every change waits for the operator. Without a terminal nothing is asked,
    # so nothing changes and the recipe only reports.
    confirm() {
        [ -n "$ASSUME_YES" ] && return 0
        [ "$INTERACTIVE" = true ] && gum confirm "$1"
    }

    # --- GPUs: the NVIDIA one goes to the guest, another drives the desktop.
    PASS=(); DESK=()
    for dev in "$SYSFS"/bus/pci/devices/*; do
        [[ "$(cat "$dev/class")" == 0x03* ]] || continue
        if [ "$(cat "$dev/vendor")" = "$NVIDIA_VENDOR" ]; then
            PASS+=("$(basename "$dev")")
        else
            DESK+=("$(basename "$dev")")
        fi
    done
    if [ "${#PASS[@]}" -ne 1 ]; then
        echo "Passthrough handles exactly one NVIDIA GPU; found ${#PASS[@]}." >&2
        exit 1
    fi
    if [ "${#DESK[@]}" -eq 0 ]; then
        echo "No other GPU can drive the desktop while the NVIDIA GPU is in a VM." >&2
        echo "Enable the integrated GPU in the firmware, then run this again." >&2
        exit 1
    fi
    PT="${PASS[0]}"
    DT="${DESK[0]}"
    echo "GPU to pass through: ${PT}"
    echo "Desktop GPU:         ${DT}"

    # --- Boot GPU: it owns the console and the greeter.
    if [ "$(cat "$SYSFS/bus/pci/devices/$DT/boot_vga" 2>/dev/null)" != "1" ]; then
        echo ""
        echo "The boot GPU is not the desktop GPU, so the console and greeter appear on"
        echo "the GPU the VM takes. Set the integrated GPU as primary in the firmware"
        echo "(on MSI boards: Initiate Graphic Adapter = IGD)."
    fi

    # --- IOMMU group: the guest takes the whole group.
    if [ ! -e "$SYSFS/bus/pci/devices/$PT/iommu_group" ]; then
        echo "The IOMMU is off, so no device can be passed through." >&2
        exit 1
    fi
    GROUP="$(basename "$(readlink "$SYSFS/bus/pci/devices/$PT/iommu_group")")"
    MEMBERS=(); FOREIGN=()
    for m in "$SYSFS/kernel/iommu_groups/$GROUP/devices"/*; do
        m="$(basename "$m")"
        MEMBERS+=("$m")
        [ "${m%.*}" = "${PT%.*}" ] || FOREIGN+=("$m")
    done
    if [ "${#FOREIGN[@]}" -gt 0 ]; then
        echo "IOMMU group ${GROUP} also holds ${FOREIGN[*]}, which would go to the VM" >&2
        echo "with the GPU. Refusing; a different slot may give the GPU a group of its own." >&2
        exit 1
    fi
    echo "IOMMU group ${GROUP}: ${MEMBERS[*]}"

    # --- Guest address width (§spec:guest-address-width).
    MGAW=""
    for cap in "$SYSFS"/class/iommu/dmar*/intel-iommu/cap; do
        [ -e "$cap" ] || continue
        w=$(( ((0x$(cat "$cap") >> 16) & 0x3f) + 1 ))
        if [ -z "$MGAW" ] || [ "$w" -lt "$MGAW" ]; then MGAW=$w; fi
    done
    PHYS="$(grep -m1 'address sizes' "$CPUINFO" | grep -oE '[0-9]+ bits physical' | grep -oE '^[0-9]+' || true)"
    LARGEST_BAR=0
    while read -r start end _; do
        size=$(( end - start + 1 ))
        [ "$(( start ))" -ne 0 ] && [ "$size" -gt "$LARGEST_BAR" ] && LARGEST_BAR=$size
    done < "$SYSFS/bus/pci/devices/$PT/resource"
    # OVMF's 64-bit window must hold the largest BAR at its own alignment, so
    # give it twice that, rounded up to a power of two.
    WINDOW_MIB=1
    while [ "$WINDOW_MIB" -lt $(( 2 * LARGEST_BAR / MIB )) ]; do WINDOW_MIB=$(( WINDOW_MIB * 2 )); done
    NEED_GUEST=false
    if [ -n "$MGAW" ] && [ -n "$PHYS" ] && [ "$MGAW" -lt "$PHYS" ]; then
        NEED_GUEST=true
        echo ""
        echo "The IOMMU addresses ${MGAW} bits and the CPU ${PHYS}. A guest that passes this"
        echo "GPU through needs, in its libvirt definition:"
        echo "  <cpu ...><maxphysaddr mode='passthrough' limit='${MGAW}'/></cpu>"
        echo "  <qemu:commandline> -fw_cfg name=opt/ovmf/X-PciMmio64Mb,string=${WINDOW_MIB}"
    fi

    if [ -z "$ASSUME_YES" ] && [ "$INTERACTIVE" = false ]; then
        echo ""
        echo "Run this from a terminal to apply changes; nothing was changed."
        exit 0
    fi
    echo ""

    # --- Designation (§spec:passthrough-desktop-gpu).
    if confirm "Keep the desktop on ${DT} and reserve ${PT} for VMs?"; then
        sudo install -d -m 755 "$ETC/tilefin" "$ETC/niri"
        printf 'PASSTHROUGH_GPU=%s\nDESKTOP_GPU=%s\n' "$PT" "$DT" \
            | sudo tee "$ETC/tilefin/gpu-passthrough.conf" >/dev/null
        printf '%s\n' \
            "// Written by ujust setup-gpu-passthrough (§spec:passthrough-desktop-gpu)." \
            "debug {" \
            "    render-drm-device \"/dev/dri/by-path/pci-${DT}-render\"" \
            "    ignore-drm-device \"/dev/dri/by-path/pci-${PT}-render\"" \
            "}" \
            "" \
            "// Looking Glass opens fullscreen on its own workspace (§spec:looking-glass-workspace)." \
            "workspace \"${WORKSPACE}\"" \
            "window-rule {" \
            "    match app-id=r#\"^looking-glass-client\$\"#" \
            "    open-on-workspace \"${WORKSPACE}\"" \
            "    open-fullscreen true" \
            "    open-focused true" \
            "}" \
            "binds {" \
            "    Mod+Grave { focus-workspace \"${WORKSPACE}\"; }" \
            "}" \
            | sudo tee "$ETC/niri/gpu-passthrough.kdl" >/dev/null
        echo "Wrote $ETC/tilefin/gpu-passthrough.conf and $ETC/niri/gpu-passthrough.kdl."
    fi

    # nvidia-persistenced holds the GPU open, which blocks the handover; the
    # hook manages no services (§spec:gpu-handover).
    if confirm "Disable nvidia-persistenced, which holds the GPU open?"; then
        sudo systemctl disable --now nvidia-persistenced.service
    fi

    if confirm "Add ${USER} to the looking-glass group?"; then
        sudo usermod -aG looking-glass "$USER"
    fi

    if [ "$NEED_GUEST" = true ]; then
        VM="${TILEFIN_VM:-}"
        if [ -z "$VM" ] && [ "$INTERACTIVE" = true ]; then
            mapfile -t VMS < <("${VIRSH[@]}" list --all --name | sed '/^$/d')
            [ "${#VMS[@]}" -gt 0 ] && VM=$(gum choose --header="Apply the guest settings to which VM?" "${VMS[@]}" "None")
        fi
        if [ -n "$VM" ] && [ "$VM" != "None" ] && confirm "Apply the address-width settings to ${VM}?"; then
            XML="$(mktemp)"
            "${VIRSH[@]}" dumpxml --inactive "$VM" | python3 -I -c '
    import sys, xml.etree.ElementTree as ET
    NS = "http://libvirt.org/schemas/domain/qemu/1.0"
    CL, ARG = "{" + NS + "}commandline", "{" + NS + "}arg"
    ET.register_namespace("qemu", NS)
    limit, window = sys.argv[1], sys.argv[2]
    root = ET.parse(sys.stdin).getroot()
    cpu = root.find("cpu")
    if cpu is None:
        cpu = ET.SubElement(root, "cpu", {"mode": "host-passthrough"})
    for old in cpu.findall("maxphysaddr"):
        cpu.remove(old)
    ET.SubElement(cpu, "maxphysaddr", {"mode": "passthrough", "limit": limit})
    cl = root.find(CL)
    if cl is None:
        cl = ET.SubElement(root, CL)
    args = list(cl)
    for i, a in enumerate(args):
        if "X-PciMmio64Mb" in a.get("value", ""):
            cl.remove(a)
            if i and args[i - 1].get("value") == "-fw_cfg":
                cl.remove(args[i - 1])
    for v in ("-fw_cfg", "name=opt/ovmf/X-PciMmio64Mb,string=" + window):
        ET.SubElement(cl, ARG, {"value": v})
    ET.ElementTree(root).write(sys.stdout, encoding="unicode")
    ' "$MGAW" "$WINDOW_MIB" > "$XML"
            "${VIRSH[@]}" define "$XML" >/dev/null
            rm -f "$XML"
            echo "Updated ${VM}; the settings apply from its next start."
        fi
    fi

    echo ""
    echo "Log out and back in for the desktop and group changes to take effect."
