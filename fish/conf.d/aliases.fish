#!/usr/local/bin/env fish

function tf --description 'alias tf="terraform"'
    terraform $argv
end

function vim --description 'alias vim="nvim"'
    truncate -s0 /Users/alex/.local/state/nvim/lsp.log 2>/dev/null
    nvim $argv
end

function notes --description 'alias notes="nvim ~/notes"'
    nvim ~/notes $argv
end

function l --description 'alias l="ls -lsah"'
    ls -lsah $argv
end

function mist --description 'alias mist="ollama run mistral"'
    ollama run mistral $argv
end

function stern --description 'alias stern="kubectl stern"'
    kubectl stern $argv
end

function b --description 'alias b with git worktree and fzf'
    set gitroot (git rev-parse --show-toplevel)
    set t (ls "$gitroot/.." | fzf --select-1 --walker=dir,hidden,follow --print-query | tail -n 1)
    if not test -e "$gitroot/../$t"
        git worktree add -b "$t" "$gitroot/../$t"
    end
    cd "$gitroot/../$t"
end

function was --description 'alias was="eval $(docctor aws export)"'
    eval (docctor aws export)
end

function f --description 'alias f="z $(fd --type d | fzf)"'
    set dir (fd --type d | fzf)
    cd $dir
end

function ff --description 'finds dirs in ~/devel to a max-depth of 2, can take a query string to start the search'
    if test (count $argv) -ne 0
        set dir (fd --type d --max-depth 2 . "$HOME/devel" | fzf --query $argv)
    end
    set dir (fd --type d --max-depth 2 . "$HOME/devel" | fzf)
    cd $dir
    ensure_prepare_commit_msg
    if test (git status >/dev/null 2>&1)
        git fetch
    end
end

function ensure_prepare_commit_msg
    if test -d .git -a ! -f .git/prepare_commit_msg
        echo "$PWD" >>/tmp/ff
        ln -s $HOME/devel/dotfiles/scripts/prepare_commit_msg .git/hooks/prepare-commit-msg >>/tmp/ff 2>&1
    end
end

function j --description ''
    set dir (autojump $argv)
    cd $dir
end

function tg --description 'alias tg="terragrunt"'
    terragrunt $argv
end

function rmterra --description 'recursively find and delete .terragrunt-cache dirs'
    set dirs (fd -t d -H '.terragrunt-cache')
    for d in dirs
        rm -rf "$d"
    end
end

function fv --description 'runs ff and opens it in nvim'
    set dir (ff $argv)
    nvim .
end

function kucc --description 'alias kucc="kubectl config unset current-context"'
    kubectl config unset current-context
end

function gssh --description 'copies ghostty terminfo onto ssh targets'
    infocmp -x xterm-ghostty | ssh $argv[1] tic -x -
    ssh $argv
end
