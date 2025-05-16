#!/usr/local/bin/env fish
fish_add_path /usr/local/go/bin
fish_add_path -p "$HOME/go/bin"

set -gx PATH $PATH $HOME/.krew/bin
