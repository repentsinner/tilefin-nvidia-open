#!/bin/bash
# Modern CLI tool aliases and initialization

# eza: modern ls replacement
alias ls='eza'
alias ll='eza -l'
alias la='eza -la'
alias lt='eza --tree'

# zoxide: smarter cd (replaces cd with fuzzy matching)
if [[ $- == *i* ]] && command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash --cmd cd)"
fi

# starship: modern prompt
if [[ $- == *i* ]] && command -v starship &>/dev/null; then
    eval "$(starship init bash)"
fi
