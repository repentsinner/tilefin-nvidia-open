# Add ~/.local/bin to PATH for native-installer CLIs (e.g., Claude Code)
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
