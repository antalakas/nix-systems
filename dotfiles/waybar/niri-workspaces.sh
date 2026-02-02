#!/usr/bin/env bash

# Workspace indicator for Niri - shows workspaces for this monitor
# Uses WAYBAR_OUTPUT_NAME env var set by waybar
# Shows: [n] = active, ● = has windows, ○ = empty

output="${WAYBAR_OUTPUT_NAME:-}"

# Get all data
workspaces=$(niri msg -j workspaces 2>/dev/null)
windows=$(niri msg -j windows 2>/dev/null)

if [ -z "$output" ]; then
    # Fallback: show focused workspace across all monitors
    active=$(echo "$workspaces" | jq -r '.[] | select(.is_focused == true) | .idx' 2>/dev/null)
    echo "󰧨 ${active:-?}"
    exit 0
fi

# Get workspace IDs that have windows
ws_with_windows=$(echo "$windows" | jq -r '[.[].workspace_id] | unique | .[]' 2>/dev/null)

# Filter workspaces for this output
output_workspaces=$(echo "$workspaces" | jq -c --arg out "$output" '[.[] | select(.output == $out)] | sort_by(.idx)')

# Build the display string
result=""
count=0
total=$(echo "$output_workspaces" | jq 'length')

while read -r ws; do
    count=$((count + 1))
    idx=$(echo "$ws" | jq -r '.idx')
    ws_id=$(echo "$ws" | jq -r '.id')
    is_active=$(echo "$ws" | jq -r '.is_active')
    
    # Check if this workspace has windows
    has_windows=false
    for wid in $ws_with_windows; do
        if [ "$wid" = "$ws_id" ]; then
            has_windows=true
            break
        fi
    done
    
    # Skip the last workspace if it's empty (niri's auto-created empty workspace)
    if [ "$count" -eq "$total" ] && [ "$has_windows" = "false" ] && [ "$is_active" != "true" ]; then
        continue
    fi
    
    if [ "$is_active" = "true" ]; then
        # Active workspace - show in brackets with indicator
        if [ "$has_windows" = "true" ]; then
            result+="[$idx●] "
        else
            result+="[$idx○] "
        fi
    else
        # Inactive workspace
        if [ "$has_windows" = "true" ]; then
            result+="$idx● "
        else
            result+="$idx○ "
        fi
    fi
done < <(echo "$output_workspaces" | jq -c '.[]')

# Trim trailing space
result="${result% }"

if [ -n "$result" ]; then
    echo "$result"
else
    echo "[1○]"
fi

