# Tilefin custom recipes

# Install Claude Code CLI to user's home directory
setup-claude:
    #!/usr/bin/env bash
    if command -v claude &>/dev/null; then
        echo "Claude Code is already installed: $(claude --version)"
        echo "Run 'claude update' to check for updates"
    else
        echo "Installing Claude Code CLI..."
        curl -fsSL https://claude.ai/install.sh | bash
        echo "Claude Code installed. Restart your shell or run: source ~/.bashrc"
    fi

# Assemble userbox distrobox container (optional: override image)
setup-userbox image="":
    #!/usr/bin/env bash
    INI="$HOME/.config/distrobox/userbox.ini"
    if [ ! -f "$INI" ]; then
        echo "Error: $INI not found."
        echo "Expected at account creation via /etc/skel."
        exit 1
    fi
    if [ -n "{{image}}" ]; then
        echo "Overriding image to: {{image}}"
        sed -i 's|^image=.*|image={{image}}|' "$INI"
    fi
    echo "Assembling userbox container..."
    distrobox assemble create --replace --file "$INI"
    echo "Userbox assembled. Exported binaries are in ~/.local/bin"
