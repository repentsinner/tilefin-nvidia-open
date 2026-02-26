# Aliases and shell hooks for CLI tools (userbox exports and native installers)
# All entries guarded with command -sq — silently skipped when tool is absent

# bat: syntax-highlighting pager (replaces cat for interactive use)
if command -sq bat
    alias cat 'bat --style=plain --pager=never'
end

# eza: modern ls replacement
if command -sq eza
    alias ls 'eza'
    alias ll 'eza -l'
    alias la 'eza -la'
    alias lt 'eza --tree'
end

# zoxide: smarter cd (replaces cd with fuzzy matching)
if status is-interactive; and command -sq zoxide
    zoxide init fish --cmd cd | source
end

# starship: modern prompt
if status is-interactive; and command -sq starship
    starship init fish | source
end

# direnv: per-directory environment variables
# direnv hook outputs hardcoded paths (/usr/bin/direnv) that don't exist on
# the host when direnv is a distrobox export. Replace with the actual path.
if status is-interactive; and command -sq direnv
    set -l _direnv_bin (command -s direnv)
    direnv hook fish | string replace -a '"/usr/bin/direnv"' "\"$_direnv_bin\"" | source
end

# mise: per-project runtime version manager (activates when .mise.toml exists)
if status is-interactive; and command -sq mise
    mise activate fish | source
end
