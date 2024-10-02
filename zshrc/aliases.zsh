alias tf='terraform'
alias vim='nvim'
alias notes='nvim ~/notes'
alias l='ls -lsah'
alias mist='ollama run mistral'
eval $(thefuck --alias)
alias cd='z'
alias stern='kubectl stern'
alias b='gitroot=$(git rev-parse --show-toplevel); t=$(ls "$gitroot/.." | fzf --select-1 --walker=dir,hidden,follow --print-query | tail -1); if ! $(stat "$gitroot/../$t" >/dev/null 2>/dev/null); then git worktree add -b "$t" "$gitroot/../$t"; fi; cd "$gitroot/../$t"'
