#!/usr/bin/env fish

for dir in /run/current-system/sw/bin /etc/profiles/per-user/alex/bin
    contains -- $dir $PATH; or set -x PATH $dir $PATH
end

set -l focused (aerospace list-workspaces --focused)
if test $status -ne 0
    echo "Failed to query AeroSpace for the focused workspace" >&2
    exit 1
end

set -l visible (aerospace list-workspaces --monitor all --visible --json --format '%{workspace}%{monitor-name}')
if test $status -ne 0
    echo "Failed to query AeroSpace for visible workspaces" >&2
    exit 1
end

set -l windows (aerospace list-windows --all --json --format '%{window-id}%{workspace}%{monitor-name}%{app-bundle-id}%{app-name}%{window-title}')
if test $status -ne 0
    echo "Failed to query AeroSpace for windows" >&2
    exit 1
end

set -l visible_json (string join \n -- $visible | string collect)
set -l windows_json (string join \n -- $windows | string collect)

for doc in $visible_json $windows_json
    if not printf '%s\n' $doc | jq -e 'type == "array"' >/dev/null 2>&1
        echo "AeroSpace returned unexpected output, refusing to overwrite the saved layout" >&2
        exit 1
    end
end

set -l state_dir ~/.local/state/aerospace
set -l layout $state_dir/layout.json
mkdir -p $state_dir

if not jq -n \
        --arg focused "$focused" \
        --argjson visible "$visible_json" \
        --argjson windows "$windows_json" \
        '{"focused-workspace": $focused, visible: $visible, windows: $windows}' >$layout.tmp
    rm -f $layout.tmp
    echo "Failed to build the layout document, left the previous layout in place" >&2
    exit 1
end

mv $layout.tmp $layout

set -l window_count (jq '.windows | length' $layout)
set -l workspace_count (jq '.windows | map(.workspace) | unique | length' $layout)
echo "Saved $window_count windows across $workspace_count workspaces to $layout"
