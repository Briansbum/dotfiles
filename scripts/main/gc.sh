#!/usr/bin/env bash

set -x

git fetch --all
branch=$(git branch -a --format='%(refname:lstrip=2)' | fzf --print-query)
found=$?
if [[ $found -eq 0 ]]; then
    branch=$(echo "$branch" | tail -n 1)
else
    branch=$(echo "$branch" | head -n 1)
fi

remotes=$(git remote)

for remote in $remotes; do
    if [[ $branch == $remote/* ]]; then
        branch=${branch/$remote\//}
    fi
done

gitroot=$(git rev-parse --show-toplevel)
currbranch=$(git branch --show-current)
gcfile=".gcenabled"

if ! stat "$gitroot/../$gcfile" &>/dev/null; then
    tar -czf /tmp/temp.tar.gz ./.
    find . -name . -o -prune -exec rm -rf -- {} +
    touch $gcfile
    mkdir "$currbranch"
    tar -xzf /tmp/temp.tar.gz -C "$currbranch"
fi

if [[ $(basename "$gitroot") != "$currbranch" ]]; then
    pushd "$gitroot/$currbranch" &>/dev/null
    gitroot=$(git rev-parse --show-toplevel)
fi

set +e
existingworktree=$(git worktree list | grep branch | awk '{print $1}')
set -e
if [[ -n $existingworktree ]]; then
    pushd "$existingworktree" &>/dev/null
    exit 0
fi

if [[ $found -ne 0 ]]; then
    git worktree add -b "../$branch" "$branch" >/dev/null 2>&1
else
    git worktree add "../$branch" "$branch" >/dev/null 2>&1
fi

echo "$(dirname "$gitroot")/$branch"
