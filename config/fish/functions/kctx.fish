function kctx --description "Switch Kubernetes context (kubectx replacement)"
    set -l context $argv[1]

    if test -n "$context"
        # Direct context switch if argument provided
        kubectl config use-context "$context"
        return $status
    end

    # Get current context for highlighting
    set -l current_context (kubectl config current-context 2>/dev/null)

    # Use fzf with fancy features
    set -l selected (kubectl config get-contexts -o name 2>/dev/null | fzf \
        --ansi \
        --no-sort \
        --tiebreak=index \
        --history="$HOME/.local/share/fzf/kctx-history" \
        --header="Current: $current_context" \
        --prompt="Context> " \
        --preview='kubectl config get-contexts {1}' \
        --preview-window=down:3:wrap \
        --color='fg:#ffffff,bg:#16181a,hl:#5ef1ff,fg+:#ffffff,bg+:#3c4048,hl+:#5ef1ff,info:#7b8496,prompt:#5eff6c,pointer:#ffbd5e,marker:#bd5eff,spinner:#5ea1ff,header:#f1ff5e' \
        --bind='ctrl-/:toggle-preview' \
        --bind='ctrl-y:execute-silent(echo -n {1} | pbcopy)+abort' \
        --height=50% \
        --layout=reverse \
        --border=rounded \
        --margin=1 \
        --padding=1)

    if test -n "$selected"
        kubectl config use-context "$selected"
    end
end
