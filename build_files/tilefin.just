# Tilefin custom recipes

# Provision user environment: native CLI tools, Flatpaks, userbox container (optional: override image)
setup-user image="":
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Select components to install (space to toggle, enter to confirm):"
    echo ""

    # Native CLI tools selection
    NATIVE_TOOLS=$(gum choose --no-limit --selected="Claude Code,uv,mise" \
        "Claude Code" \
        "uv" \
        "mise")

    # Flatpak apps selection
    FLATPAK_APPS=$(gum choose --no-limit --selected="Firefox,Bitwarden" \
        "Firefox" \
        "Bitwarden" \
        "Slack" \
        "Discord" \
        "Signal" \
        "Proton VPN")

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
        if [ ${#FLATPAK_IDS[@]} -gt 0 ]; then
            flatpak install --user --noninteractive flathub "${FLATPAK_IDS[@]}"
        fi
    fi

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
