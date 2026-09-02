#!/usr/bin/env bash

# Pull requests module for waybar: every open PR of one repository as a count
# in the bar and a list in the tooltip, with a badge for what changed since
# you last looked. Data comes from `gh`, so the one prerequisite is `gh auth
# login` on this host. Without that, or without network on the first run,
# the script prints nothing and waybar hides the module.
#
#   prs.sh          waybar JSON (the polled default; network at most per TTL)
#   prs.sh --pick   fuzzel picker over the cached list; opens the chosen PR
#   prs.sh --seen   mark everything seen, then poke waybar to redraw
#
# Bar text is "<icon> <open> +<unseen>", the badge only when non-zero. Classes,
# for style.css:
#   review   a review is requested from you on at least one PR
#   unseen   something opened or changed since you last looked
#   stale    the last fetch failed; the tooltip says when the data is from
#   error    logged in but never fetched; the tooltip carries gh's message
#
# Tooltip markers, one column each:
#   ●  opened since you last looked      ↻  updated since you last looked
#   R  review requested from you         D  draft
#   ✓ ✗ …  checks passed / failed / still running; blank when there are none
# Lines that changed since you last looked are bold as well.

set -u

# Use the account from `gh auth login`, not whatever token the shell that
# started waybar happened to export: on the laptop GH_TOKEN carries the
# sandbox's narrow fine-grained token, which cannot see the organisation,
# and gh lets an environment token override the stored login.
unset GH_TOKEN GITHUB_TOKEN

REPO="${WAYBAR_PRS_REPO:-TileDB-Inc/tile-ai}"
ICON=""
SIGNAL=8 # matches "signal" in config.json; --seen sends SIGRTMIN+8
TTL=60   # seconds a fetch stays fresh, so --seen redraws without a round trip

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
CACHE="$CACHE_DIR/prs.json"
SEEN="$CACHE_DIR/prs.seen"

picker() {
    if [ -n "${WAYBAR_PICKER:-}" ]; then $WAYBAR_PICKER; else
        fuzzel --dmenu --prompt 'PR ❯ ' --width 110 --lines 15
    fi
}

fresh() {
    [ -f "$CACHE" ] && [ $(($(date +%s) - $(stat -c %Y "$CACHE"))) -lt "$TTL" ]
}

# Two calls: the list, and the numbers GitHub says want a review from you.
# The second is a search, so it also covers reviews requested from a team.
fetch() {
    local prs mine
    mkdir -p "$CACHE_DIR"
    prs=$(gh pr list -R "$REPO" --state open --limit 100 \
        --json number,title,url,author,createdAt,updatedAt,isDraft,statusCheckRollup \
        2>"$CACHE_DIR/prs.error") || return 1
    mine=$(gh pr list -R "$REPO" --state open --limit 100 \
        --search 'review-requested:@me' --json number 2>/dev/null) || mine='[]'
    # The list goes in on stdin: as an argument it can exceed the exec limit
    # once a hundred PRs carry their check rollups.
    printf '%s' "$prs" | jq --argjson mine "$mine" --arg at "$(date +%s)" '
        ($mine | map(.number)) as $wanted
        | {
            fetched: ($at | tonumber),
            prs: [ .[] | . + {
                review: (.number as $n | $wanted | index($n) != null),
                # One symbol for the whole rollup. CheckRun rows carry
                # conclusion (null while running) and status; StatusContext
                # rows carry state. Cancelled, skipped and neutral count as
                # nothing, so a superseded run does not read as a failure.
                checks: (
                    [ .statusCheckRollup[]?
                      | if (.conclusion // "") != "" then .conclusion
                        elif (.state // "") != "" then .state
                        else (.status // "") end ] as $c
                    | if any($c[]; IN("FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE")) then "✗"
                      elif any($c[]; IN("PENDING", "EXPECTED", "IN_PROGRESS", "QUEUED", "WAITING", "REQUESTED")) then "…"
                      elif any($c[]; . == "SUCCESS") then "✓"
                      else " " end)
            } ]
          }' > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE" && rm -f "$CACHE_DIR/prs.error"
}

render() {
    local seen stale=$1
    seen=$(cat "$SEEN" 2>/dev/null || echo 0)
    jq -c --arg icon "$ICON" --arg repo "$REPO" --arg stale "$stale" \
          --argjson seen "$seen" --argjson now "$(date +%s)" '
        def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
        def age: ($now - .) as $d
            | if $d < 3600 then "\($d / 60 | floor)m"
              elif $d < 86400 then "\($d / 3600 | floor)h"
              else "\($d / 86400 | floor)d" end;
        def line:
            ((.createdAt | ts) > $seen) as $new
            | ((.updatedAt | ts) > $seen) as $changed
            | ( (if $new then "●" elif $changed then "↻" else " " end)
              + (if .review then "R" else " " end)
              + (if .isDraft then "D" else " " end)
              + " " + .checks
              + "  #" + (.number | tostring)
              + "  " + (.title | .[0:72] | @html)
              + "  <i>" + (.author.login | @html) + " · " + (.updatedAt | ts | age) + "</i>" )
            | if $changed then "<b>" + . + "</b>" else . end;

        .prs as $p
        | ($p | map(select((.updatedAt | ts) > $seen)) | length) as $unseen
        | ($p | map(select(.review)) | length) as $review
        | {
            text: ($icon + " " + ($p | length | tostring)
                   + (if $unseen > 0 then " +" + ($unseen | tostring) else "" end)),
            class: [ (if $review > 0 then "review" else empty end),
                     (if $unseen > 0 then "unseen" else empty end),
                     (if $stale != "" then "stale" else empty end) ],
            tooltip: ( "<b>" + ($repo | @html) + "</b>  " + ($p | length | tostring) + " open"
                       + (if $review > 0 then " · " + ($review | tostring) + " waiting for your review" else "" end)
                       + (if $stale != "" then "  <i>(offline, data from " + (.fetched | strflocaltime("%H:%M")) + ")</i>" else "" end)
                       + (if ($p | length) > 0 then "\n" else "" end)
                       + ($p | sort_by([(.review | not), -(.updatedAt | ts)]) | map(line) | join("\n")) )
          }' "$CACHE"
}

pick() {
    [ -f "$CACHE" ] || exit 0
    local choice number url
    choice=$( {
        printf 'All open pull requests\n'
        jq -r '.prs | sort_by([(.review | not), .updatedAt]) | reverse[]
               | "#\(.number)  \(.title)  (\(.author.login))"' "$CACHE"
    } | picker) || exit 0
    case $choice in
        "#"*)
            number=${choice#\#}; number=${number%% *}
            url=$(jq -r --argjson n "$number" '.prs[] | select(.number == $n) | .url' "$CACHE")
            [ -n "$url" ] && xdg-open "$url" ;;
        "All open"*)
            xdg-open "https://github.com/$REPO/pulls" ;;
    esac
}

mark_seen() {
    mkdir -p "$CACHE_DIR"
    date +%s > "$SEEN"
    pkill -SIGRTMIN+$SIGNAL waybar 2>/dev/null || true
}

case ${1:-} in
    --pick) pick; exit 0 ;;
    --seen) mark_seen; exit 0 ;;
esac

command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 0
gh auth token >/dev/null 2>&1 || exit 0 # not logged in on this host: no module

stale=""
fresh || fetch || stale=1
if [ ! -f "$CACHE" ]; then
    # Logged in but never fetched: say why, so a wrong repo name, missing
    # org access or no network is visible rather than an absent module.
    jq -cn --arg icon "$ICON" --arg repo "$REPO" \
        --arg err "$(head -c 300 "$CACHE_DIR/prs.error" 2>/dev/null | tr -s '[:space:]' ' ')" \
        '{text: ($icon + " !"), class: ["error"],
          tooltip: ("gh pr list -R " + ($repo | @html) + ": " + (if $err == "" then "no output" else ($err | @html) end))}'
    exit 0
fi
render "$stale"
