function fv {
    fd $1 -X nvim
}

function gw {
    if ! git status >/dev/null 2>&1; then
        echo 'not a git repo'
        exit 1
    fi

    local mainbranch="$(git branch -a --contains $(git rev-list --max-parents=0 HEAD) | head -n1 | cut -d' ' -f2)"
    if ! ls | grep "$mainbranch" >/dev/null 2>&1; then
        echo "your repo is not set up for this command, setting up"
        set -x
        local dir="$(basename $PWD)"
        pushd ..
        mkdir tmp
        mv "$dir" tmp/
        mkdir -p "$dir/$mainbranch"
        mv tmp/"$dir"/* "$dir/$mainbranch/"
        rm -rf tmp
        popd
        pushd "$dir/$mainbranch"
        set +x
    fi

    if test -z "$1"; then
        echo 'no branch specified, here is the list'
        git worktree list
        return 1
    fi    

    if ! git worktree list | grep "$1" >/dev/null 2>&1; then
        local parentdir="$(git worktree list | head -n1 | cut -d' ' -f1 | xargs dirname)"
        git worktree add -b "$1" "$parentdir/$1"
    fi
    pushd $(git worktree list | grep "$1" | cut -d' ' -f1)
}
