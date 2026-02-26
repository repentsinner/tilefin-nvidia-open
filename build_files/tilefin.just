# Tilefin custom recipes

# Provision user environment: native CLI tools + userbox container (optional: override image)
setup-user image="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Native CLI tools (idempotent — safe to re-run)
    echo "==> Installing native CLI tools to ~/.local/bin..."

    echo "  Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash

    echo "  uv (Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    echo "  mise (runtime version manager)..."
    curl -fsSL https://mise.run | sh

    # Userbox container
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

    echo ""
    echo "==> Done. Restart your shell or run: source ~/.bashrc"
    echo "    Native tools: claude, uv, mise"
    echo "    Userbox tools: ~/.local/bin (exported from container)"
