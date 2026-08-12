#!/usr/bin/env fish

for dir in /run/current-system/sw/bin /etc/profiles/per-user/alex/bin
    contains -- $dir $PATH; or set -x PATH $dir $PATH
end

set -g moved_count 0
set -g problems

function snapshot_live -a path
    aerospace list-windows --all --json --format '%{window-id}%{workspace}%{monitor-name}%{app-bundle-id}%{app-name}%{window-title}' >$path 2>/dev/null
    test -s $path; or echo "[]" >$path
end

function move_window -a id current target
    test "$current" = "$target"; and return 0
    if aerospace move-node-to-workspace --window-id $id -- $target
        set -g moved_count (math $moved_count + 1)
    else
        set -ga problems "Could not move window $id to workspace $target"
    end
end

if not pgrep -x AeroSpace >/dev/null 2>&1
    open -a AeroSpace
end

set -l ready 0
set -l waited 0
while test $waited -lt 30
    if aerospace list-workspaces --focused >/dev/null 2>&1
        set ready 1
        break
    end
    sleep 1
    set waited (math $waited + 1)
end

if test $ready -eq 0
    echo "AeroSpace did not start responding within 30 seconds" >&2
    exit 1
end

set -l state_dir ~/.local/state/aerospace
set -l layout $state_dir/layout.json
if not test -f $layout
    echo "No saved layout found at $layout, nothing to restore"
    exit 0
end

if not jq -e '(.windows | type == "array") and (.visible | type == "array") and (."focused-workspace" | type == "string")' $layout >/dev/null 2>&1
    echo "Saved layout at $layout is malformed, refusing to restore" >&2
    exit 1
end

set -l live_file (mktemp $state_dir/live.XXXXXX)
if test -z "$live_file"
    echo "Could not create a temporary file in $state_dir" >&2
    exit 1
end
snapshot_live $live_file

set -l saved_bundles (jq -r '.windows[] | ."app-bundle-id" | select(. != null and . != "")' $layout | sort -u)
set -l live_bundles (jq -r '.[] | ."app-bundle-id" | select(. != null and . != "")' $live_file | sort -u)

set -l bundleless (jq -r '[.windows[] | select((."app-bundle-id" // "") == "")] | length' $layout)
if test $bundleless -gt 0
    set -ga problems "$bundleless saved windows have no bundle identifier and cannot be matched"
end

set -l launched
set -l unlaunchable
for bundle in $saved_bundles
    contains -- $bundle $live_bundles; and continue
    if open -g -b $bundle >/dev/null 2>&1
        set -a launched $bundle
    else
        set -a unlaunchable $bundle
    end
end

set -l wait_left 30
set -l stable 0
set -l last_total -1
while test (count $launched) -gt 0
    set -l pending
    for bundle in $launched
        set -l want (jq -r --arg b $bundle '[.windows[] | select(."app-bundle-id" == $b)] | length' $layout)
        set -l have (jq -r --arg b $bundle '[.[] | select(."app-bundle-id" == $b)] | length' $live_file)
        test $have -lt $want; and set -a pending $bundle
    end
    if test (count $pending) -eq 0
        break
    end
    set -l total (jq -r 'length' $live_file)
    if test $total -eq $last_total
        set stable (math $stable + 1)
    else
        set stable 0
    end
    set last_total $total
    if test $stable -ge 3
        set -ga problems (string join ", " $pending)" opened fewer windows than were saved"
        break
    end
    if test $wait_left -le 0
        set -ga problems "Gave up waiting for windows from "(string join ", " $pending)
        break
    end
    sleep 2
    set wait_left (math $wait_left - 2)
    snapshot_live $live_file
end

set -l unmatched
for bundle in $saved_bundles
    set -l saved_titles
    set -l saved_ws
    for line in (jq -r --arg b $bundle '.windows[] | select(."app-bundle-id" == $b) | [."window-title", .workspace] | @tsv' $layout)
        set -l parts (string split \t -- $line)
        set -a saved_titles $parts[1]
        set -a saved_ws $parts[2]
    end

    set -l live_ids
    set -l live_ws
    set -l live_titles
    for line in (jq -r --arg b $bundle '.[] | select(."app-bundle-id" == $b) | [(."window-id" | tostring), .workspace, ."window-title"] | @tsv' $live_file)
        set -l parts (string split \t -- $line)
        set -a live_ids $parts[1]
        set -a live_ws $parts[2]
        set -a live_titles $parts[3]
    end

    set -l total (count $live_ids)
    set -l used
    for j in (seq 1 $total)
        set -a used 0
    end

    set -l leftover_saved
    for i in (seq 1 (count $saved_titles))
        set -l hit 0
        for j in (seq 1 $total)
            test $used[$j] -eq 1; and continue
            if test "$live_titles[$j]" = "$saved_titles[$i]"
                set used[$j] 1
                move_window $live_ids[$j] "$live_ws[$j]" "$saved_ws[$i]"
                set hit 1
                break
            end
        end
        test $hit -eq 0; and set -a leftover_saved $i
    end

    set -l leftover_live
    for j in (seq 1 $total)
        test $used[$j] -eq 0; and set -a leftover_live $j
    end

    for k in (seq 1 (count $leftover_saved))
        set -l i $leftover_saved[$k]
        if test $k -gt (count $leftover_live)
            set -a unmatched "$bundle \"$saved_titles[$i]\" for workspace $saved_ws[$i]"
            continue
        end
        set -l j $leftover_live[$k]
        move_window $live_ids[$j] "$live_ws[$j]" "$saved_ws[$i]"
    end
end

set -l monitor_json (aerospace list-monitors --json)
if test $status -ne 0
    echo "Failed to query AeroSpace for connected monitors" >&2
    rm -f $live_file
    exit 1
end
set -l monitors (string join \n -- $monitor_json | jq -r '.[]."monitor-name"')

for line in (jq -r 'reduce (.windows[], .visible[]) as $w ({}; if has($w.workspace) then . else . + {($w.workspace): $w["monitor-name"]} end) | to_entries[] | [.key, .value] | @tsv' $layout)
    set -l parts (string split \t -- $line)
    set -l ws $parts[1]
    set -l monitor $parts[2]
    if not contains -- $monitor $monitors
        set -ga problems "Monitor \"$monitor\" is not connected, left workspace $ws where it is"
        continue
    end
    aerospace move-workspace-to-monitor --workspace $ws -- '^'(string escape --style=regex -- $monitor)'$'
end

for line in (jq -r '.visible[]? | [.workspace, ."monitor-name"] | @tsv' $layout)
    set -l parts (string split \t -- $line)
    set -l ws $parts[1]
    set -l monitor $parts[2]
    if not contains -- $monitor $monitors
        set -ga problems "Monitor \"$monitor\" is not connected, did not make workspace $ws visible"
        continue
    end
    if not aerospace workspace -- $ws >/dev/null 2>&1
        set -ga problems "Could not make workspace $ws visible"
    end
end

set -l focused (jq -r '."focused-workspace" // empty' $layout)
if test -n "$focused"
    if not aerospace workspace -- $focused >/dev/null 2>&1
        set -ga problems "Could not focus workspace $focused"
    end
end

rm -f $live_file

echo "Restored the saved layout from $layout"

if test (count $launched) -gt 0
    echo "Launched "(string join ", " $launched)
else
    echo "Launched nothing, every saved application was already running"
end

if test $moved_count -eq 1
    echo "Moved 1 window onto its saved workspace"
else
    echo "Moved $moved_count windows onto their saved workspaces"
end

if test -n "$focused"
    echo "Focused workspace $focused"
end

if test (count $unlaunchable) -gt 0
    echo "Could not launch "(string join ", " $unlaunchable)
end

if test (count $unmatched) -gt 0
    echo "No live window matched these saved windows:"
    for entry in $unmatched
        echo "  $entry"
    end
end

if test (count $problems) -gt 0
    echo "Problems:"
    for problem in $problems
        echo "  $problem"
    end
end
