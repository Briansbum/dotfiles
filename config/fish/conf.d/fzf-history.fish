# Ensure fzf history directory exists for kctx/kns functions
if not test -d "$HOME/.local/share/fzf"
    mkdir -p "$HOME/.local/share/fzf"
end
