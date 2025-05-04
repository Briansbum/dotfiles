#!/usr/bin/env fish
fish_add_path -p /opt/homebrew/bin
fish_add_path -p /opt/homebrew/opt/coreutils/libexec/gnubin

[ -f /opt/homebrew/share/autojump/autojump.fish ]; and source /opt/homebrew/share/autojump/autojump.fish

export TG_PROVIDER_CACHE=1
