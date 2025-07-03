#!/usr/bin/env fish
fish_add_path -p /opt/homebrew/bin
fish_add_path -p /opt/homebrew/opt/coreutils/libexec/gnubin

[ -f /opt/homebrew/share/autojump/autojump.fish ]; and source /opt/homebrew/share/autojump/autojump.fish

export TG_PROVIDER_CACHE=1

# Function to recursively remove terragrunt cache directories
function rmterra
    find . -type d -name '.terragrunt-cache' -exec rm -rf {} +
end

function kco --description 'loads old kubeconfig as my kubeconfig'
    echo "Setting old kubeconfig"
    set KUBECONFIG '/Users/alex/.kube/config'
end

function kcn --description 'loads new kubeconfig as my kubeconfig'
    echo "Setting new kubeconfig"
    set KUBECONFIG '/Users/alex/.docctor/config/kubeconfig'
end

# Set new kubeconfig as the default
kcn
