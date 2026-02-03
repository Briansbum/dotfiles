function kns --description "Switch Kubernetes namespace (kubens replacement)"
    set -l namespace $argv[1]

    if test -n "$namespace"
        # Direct namespace switch if argument provided
        kubectl config set-context --current --namespace="$namespace"
        return $status
    end

    # Get current context and namespace for display
    set -l current_context (kubectl config current-context 2>/dev/null)
    set -l current_namespace (kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
    if test -z "$current_namespace"
        set current_namespace "default"
    end

    # Use fzf with fancy features
    set -l selected (kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | fzf \
        --ansi \
        --no-sort \
        --tiebreak=index \
        --history="$HOME/.local/share/fzf/kns-history" \
        --header="Context: $current_context | Current NS: $current_namespace" \
        --prompt="Namespace> " \
        --preview='kubectl get pods -n {1} --no-headers 2>/dev/null | head -20 || echo "No pods or access denied"' \
        --preview-window=down:10:wrap \
        --color='fg:#ffffff,bg:#16181a,hl:#5ef1ff,fg+:#ffffff,bg+:#3c4048,hl+:#5ef1ff,info:#7b8496,prompt:#5eff6c,pointer:#ffbd5e,marker:#bd5eff,spinner:#5ea1ff,header:#f1ff5e' \
        --bind='ctrl-/:toggle-preview' \
        --bind='ctrl-y:execute-silent(echo -n {1} | pbcopy)+abort' \
        --height=50% \
        --layout=reverse \
        --border=rounded \
        --margin=1 \
        --padding=1)

    if test -n "$selected"
        kubectl config set-context --current --namespace="$selected"
    end
end
