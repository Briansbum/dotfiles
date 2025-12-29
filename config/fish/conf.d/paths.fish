#!/usr/bin/env fish
# User-installed Go binaries
fish_add_path -p "$HOME/go/bin"

# Krew kubectl plugin manager
set -gx PATH $PATH $HOME/.krew/bin
