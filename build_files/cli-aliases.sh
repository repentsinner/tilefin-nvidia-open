#!/bin/bash
# Modern CLI tool aliases and initialization

# eza: modern ls replacement
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
fi

# zoxide: smarter cd (replaces cd with fuzzy matching)
if [[ $- == *i* ]] && command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash --cmd cd)"
fi

# starship: modern prompt
if [[ $- == *i* ]] && command -v starship &>/dev/null; then
    eval "$(starship init bash)"
fi

# direnv: per-directory environment variables
if [[ $- == *i* ]] && command -v direnv &>/dev/null; then
    eval "$(direnv hook bash)"
fi
