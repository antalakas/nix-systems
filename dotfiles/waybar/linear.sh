#!/usr/bin/env bash

# Linear module for waybar: what changed in a team's projects since you last
# looked, as a count in the bar and a per-project overview in the tooltip.
# Talks to Linear's GraphQL API with a personal API key read from
# ~/.config/linear/api-key; without that file the script prints nothing and
# waybar hides the module.
#
#   linear.sh          waybar JSON (the polled default; network at most per TTL)
#   linear.sh --pick   fuzzel picker over the cached list; opens the choice
#   linear.sh --seen   mark everything seen, then poke waybar to redraw
#   linear.sh --debug  one live request, printed: window, errors, counts
#
# "The team's projects" is read broadly: an issue counts when it belongs to
# the team *or* sits in a project the team has access to, because projects
# are shared across teams and the issues inside one often carry another
# team's prefix. TEAM may list several keys, comma-separated.
#
# The window is "since you last looked", but never less than today and never
# more than a week, so the morning after still shows yesterday evening and a
# fortnight away does not produce a wall of text. Items newer than the last
# look are bold and counted in the badge.
#
# Bar text is "<icon> <changed> +<unseen>". Classes, for style.css:
#   update   a project update (the written status a lead posts) landed
#   unseen   something changed since you last looked
#   stale    the last fetch failed; the tooltip says when the data is from
#   error    no data at all; the tooltip carries the API's message
#
# Per-issue markers: ✓ done  ▶ started  ● new  ✗ cancelled  ↻ other change

set -u

TEAM="${WAYBAR_LINEAR_TEAM:-ENG}"
ICON=""
SIGNAL=9 # matches "signal" in config.json; --seen sends SIGRTMIN+9
TTL=60
MAX_DAYS=7

KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/linear/api-key"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
CACHE="$CACHE_DIR/linear.json"
SEEN="$CACHE_DIR/linear.seen"

picker() {
    if [ -n "${WAYBAR_PICKER:-}" ]; then $WAYBAR_PICKER; else
        fuzzel --dmenu --prompt 'Linear ❯ ' --width 110 --lines 15
    fi
}

now=$(date +%s)
seen=$(cat "$SEEN" 2>/dev/null || echo 0)
today0=$(date -d 'today 00:00' +%s)
since=$today0
[ "$seen" -gt 0 ] && [ "$seen" -lt "$since" ] && since=$seen
[ "$since" -lt $((now - MAX_DAYS * 86400)) ] && since=$((now - MAX_DAYS * 86400))

# Fresh means recent *and* fetched for a window that starts no later than the
# one wanted now; the window only grows as the last look recedes.
fresh() {
    [ -f "$CACHE" ] || return 1
    [ $((now - $(stat -c %Y "$CACHE"))) -lt "$TTL" ] || return 1
    [ "$(jq -r '.since' "$CACHE")" -le "$since" ]
}

# Two flat top-level queries rather than team → projects → updates: Linear
# prices nested pagination multiplicatively, and a hundred projects each
# carrying their updates went over its complexity limit ("query too complex").
QUERY='query($teams: [String!]!, $since: DateTimeOrDuration!) {
  organization { urlKey }
  projectUpdates(first: 25, orderBy: createdAt, filter: {
      createdAt: { gt: $since },
      project: { accessibleTeams: { some: { key: { in: $teams } } } } }) { nodes {
    createdAt health body url user { displayName } project { id name url } } }
  issues(first: 100, orderBy: updatedAt, filter: {
      updatedAt: { gt: $since },
      or: [ { team: { key: { in: $teams } } },
            { project: { accessibleTeams: { some: { key: { in: $teams } } } } } ] }) { nodes {
    identifier title url createdAt updatedAt completedAt startedAt canceledAt
    state { name type } team { key } project { id name url } assignee { displayName } } }
}'

since_iso=$(date -u -d "@$since" +%Y-%m-%dT%H:%M:%SZ)

# One request; prints the raw reply. Non-zero only on a transport failure.
request() {
    local key body
    key=$(tr -d '[:space:]' < "$KEY_FILE")
    body=$(jq -n --arg q "$QUERY" --arg teams "$TEAM" --arg since "$since_iso" '{
        query: $q,
        variables: {
            teams: ($teams | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))),
            since: $since } }')
    curl -sS -m 20 https://api.linear.app/graphql \
        -H 'Content-Type: application/json' -H "Authorization: $key" --data "$body" 2>&1
}

fetch() {
    local reply
    reply=$(request) || { printf '%s' "$reply" > "$CACHE_DIR/linear.error"; return 1; }
    if ! printf '%s' "$reply" | jq -e '.data.issues.nodes | type == "array"' >/dev/null 2>&1; then
        printf '%s' "$reply" | jq -r '(.errors // [{message: "unexpected reply"}]) | map(.message) | join("; ")' \
            2>/dev/null > "$CACHE_DIR/linear.error" || printf '%s' "$reply" > "$CACHE_DIR/linear.error"
        [ -s "$CACHE_DIR/linear.error" ] || echo "empty reply" > "$CACHE_DIR/linear.error"
        return 1
    fi
    printf '%s' "$reply" | jq --argjson at "$now" --argjson since "$since" --arg team "$TEAM" \
        '{fetched: $at, since: $since, key: $team, org: .data.organization.urlKey,
          issues: .data.issues.nodes, updates: .data.projectUpdates.nodes}' \
        > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
    rm -f "$CACHE_DIR/linear.error"
}

render() {
    local stale=$1
    jq -c --arg icon "$ICON" --arg stale "$stale" --argjson today0 "$today0" \
          --argjson seen "$seen" --argjson since "$since" --argjson now "$now" '
        def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
        def after($t): . != null and (ts > $t);
        def health: { onTrack: "<span foreground=\"#26A65B\">on track</span>",
                      atRisk:  "<span foreground=\"#f39c12\">at risk</span>",
                      offTrack: "<span foreground=\"#f53c3c\">off track</span>" }[.] // .;
        def kind:
            if (.canceledAt | after($since)) then "✗"
            elif (.completedAt | after($since)) then "✓"
            elif (.startedAt | after($since)) then "▶"
            elif (.createdAt | after($since)) then "●"
            else "↻" end;
        def rank: {"✓": 0, "▶": 1, "●": 2, "✗": 3, "↻": 4}[.];
        def bold_if($c): if $c then "<b>" + . + "</b>" else . end;
        def issue_line:
            ((.updatedAt | ts) > $seen) as $unseen
            | ( .kind + " " + .identifier + "  " + (.title | .[0:64] | @html)
                + (if .assignee then "  <i>" + (.assignee.displayName | @html) + "</i>" else "" end) )
            | bold_if($unseen);
        def update_line:
            ((.createdAt | ts) > $seen) as $unseen
            | ( "   ↳ " + (.health | health) + " — "
                + (.body | split("\n")[0] | .[0:80] | @html)
                + "  <i>" + (.user.displayName | @html) + " " + (.createdAt | ts | strflocaltime("%H:%M")) + "</i>" )
            | bold_if($unseen);
        def counts: group_by(.kind) | map({key: .[0].kind, value: length}) | from_entries
            | [ (.["✓"] // 0 | if . > 0 then "\(.) done" else empty end),
                (.["▶"] // 0 | if . > 0 then "\(.) started" else empty end),
                (.["●"] // 0 | if . > 0 then "\(.) new" else empty end),
                (.["✗"] // 0 | if . > 0 then "\(.) cancelled" else empty end),
                (.["↻"] // 0 | if . > 0 then "\(.) updated" else empty end) ] | join(" · ");

        [ .issues[] | . + {kind: kind} ] as $issues
        | [ .updates[] | select(.createdAt | after($since)) ] as $updates
        | ($issues | map(select((.updatedAt | ts) > $seen)) | length) as $unseen_i
        | ($updates | map(select((.createdAt | ts) > $seen)) | length) as $unseen_u
        | ($unseen_i + $unseen_u) as $unseen
        | ( [ $issues[] | select(.project != null) | .project ] + [ $updates[] | .project ]
            | unique_by(.id) | sort_by(.name) ) as $projects
        | ( $projects
            | map(. as $p
                  | {name: $p.name,
                     issues: [ $issues[] | select(.project != null and .project.id == $p.id) ],
                     updates: [ $updates[] | select(.project.id == $p.id) ] })
            + [ { name: "No project",
                  issues: [ $issues[] | select(.project == null) ], updates: [] }
                | select((.issues | length) > 0) ] ) as $groups
        | ( "since " + ($since | strflocaltime(if $since >= $today0 then "%H:%M" else "%a %H:%M" end)) ) as $window
        | {
            text: ($icon + " " + (($issues | length) + ($updates | length) | tostring)
                   + (if $unseen > 0 then " +" + ($unseen | tostring) else "" end)),
            class: [ (if ($updates | length) > 0 then "update" else empty end),
                     (if $unseen > 0 then "unseen" else empty end),
                     (if $stale != "" then "stale" else empty end) ],
            tooltip: ( "<b>" + (.key | @html) + " · " + $window + "</b>  "
                       + ($issues | length | tostring) + " issues"
                       + (if ($updates | length) > 0 then " · " + ($updates | length | tostring) + " project update" + (if ($updates | length) > 1 then "s" else "" end) else "" end)
                       + (if $stale != "" then "  <i>(offline, data from " + (.fetched | strflocaltime("%H:%M")) + ")</i>" else "" end)
                       + ( $groups | map(
                             "\n\n<span foreground=\"#7fc8ff\"><b>" + (.name | @html) + "</b></span>"
                             + (if (.issues | length) > 0 then "  " + (.issues | counts) else "" end)
                             + ( .updates | map("\n" + update_line) | join("") )
                             + ( .issues | sort_by([(.kind | rank), -(.updatedAt | ts)]) | map("\n " + issue_line) | join("") )
                         ) | join("") )
                       + (if ($groups | length) == 0 then "\n\nnothing changed" else "" end) )
          }' "$CACHE"
}

pick() {
    [ -f "$CACHE" ] || exit 0
    local choice url org
    org=$(jq -r '.org // ""' "$CACHE")
    choice=$( {
        printf 'Team %s in Linear\n' "$TEAM"
        jq -r --argjson since "$since" '.updates[]
               | select((.createdAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) > $since)
               | "Update  \(.project.name)  — \(.body | split("\n")[0] | .[0:60])"' "$CACHE"
        jq -r '.issues[] | "\(.identifier)  \(.title)  [\(.state.name)]"' "$CACHE"
    } | picker) || exit 0
    case $choice in
        "Team "*)
            [ -n "$org" ] && xdg-open "https://linear.app/$org/team/$TEAM/active" ;;
        "Update  "*)
            url=$(jq -r --arg c "$choice" '.updates[]
                   | select(("Update  \(.project.name)  — \(.body | split("\n")[0] | .[0:60])") == $c) | .url' "$CACHE" | head -1)
            [ -n "$url" ] && xdg-open "$url" ;;
        *)
            url=$(jq -r --arg id "${choice%% *}" '.issues[] | select(.identifier == $id) | .url' "$CACHE" | head -1)
            [ -n "$url" ] && xdg-open "$url" ;;
    esac
}

mark_seen() {
    mkdir -p "$CACHE_DIR"
    date +%s > "$SEEN"
    pkill -SIGRTMIN+$SIGNAL waybar 2>/dev/null || true
}

# What the key can see at all, independent of TEAM and the window: who it
# belongs to, the team keys in the workspace, and the three most recently
# updated issues. If the main query returns nothing, this says why.
PROBE='{ viewer { name email }
  teams(first: 50) { nodes { key name } }
  issues(first: 3, orderBy: updatedAt) { nodes {
    identifier updatedAt team { key } project { name } } } }'

debug() {
    local reply key
    [ -r "$KEY_FILE" ] || { echo "no key at $KEY_FILE"; exit 1; }
    echo "teams:     $TEAM"
    echo "since:     $since_iso"
    echo "last look: $([ "$seen" -gt 0 ] && date -d "@$seen" '+%F %T' || echo never)"
    echo "--- probe: what the key sees ---"
    key=$(tr -d '[:space:]' < "$KEY_FILE")
    curl -sS -m 20 https://api.linear.app/graphql \
        -H 'Content-Type: application/json' -H "Authorization: $key" \
        --data "$(jq -n --arg q "$PROBE" '{query: $q}')" 2>&1 \
        | jq '{ viewer: .data.viewer, errors: (.errors // "none"),
                team_keys: (.data.teams.nodes // [] | map(.key + " = " + .name)),
                latest_issues: (.data.issues.nodes // [] | map({identifier, team: .team.key, project: .project.name, updatedAt})) }'
    echo "--- main query ---"
    reply=$(request) || { echo "transport: $reply"; exit 1; }
    printf '%s' "$reply" | jq '{
        errors: (.errors // "none"),
        issues: (.data.issues.nodes // [] | length),
        project_updates: (.data.projectUpdates.nodes // [] | length),
        first_issues: (.data.issues.nodes // [] | .[0:5] | map({identifier, team: .team.key, project: .project.name, updatedAt})),
        first_updates: (.data.projectUpdates.nodes // [] | .[0:3] | map({project: .project.name, createdAt, health})) }' \
        || printf '%s\n' "$reply"
}

case ${1:-} in
    --pick) pick; exit 0 ;;
    --seen) mark_seen; exit 0 ;;
    --debug) debug; exit 0 ;;
esac

[ -r "$KEY_FILE" ] || exit 0 # no key on this host: no module
command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$CACHE_DIR"

stale=""
fresh || fetch || stale=1
if [ ! -f "$CACHE" ]; then
    # Nothing ever fetched: say why, so a wrong key or query is visible.
    jq -cn --arg icon "$ICON" --arg err "$(cat "$CACHE_DIR/linear.error" 2>/dev/null)" \
        '{text: ($icon + " !"), class: ["error"], tooltip: ("linear: " + ($err | @html))}'
    exit 0
fi
render "$stale"
