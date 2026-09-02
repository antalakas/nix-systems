#!/usr/bin/env bash

# Calendar module for waybar: the next event today in the bar, with today's
# and tomorrow's agenda in the tooltip. Reads khal's local cache, which
# vdirsyncer fills from Google on a timer (home/calendar.nix). Nothing here
# touches the network, so polling every minute costs nothing.
#
# Output is one line of waybar JSON. The class drives style.css:
#   soon  the next event starts within SOON_MIN minutes
#   now   an event is running and nothing is about to start
#
# On a host without khal — one that does not import home/calendar.nix — this
# prints nothing, and waybar hides the module.

set -u

SOON_MIN=10
ICON="󰃭"
# khal's own output, one event per line. The title goes last so a '|' inside
# it survives the split below: `read` leaves the remainder in the last field.
# {start-time} is empty for all-day events.
FMT='{start-date}|{start-time}|{end-date}|{end-time}|{title}'

command -v khal >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/khal/config" ] || exit 0

now=$(date +%s)
today=$(date +%F)

# Events overlapping a khal date range, without the day headers. The date
# formats are the ones home/calendar.nix pins in khal's locale section, which
# is what lets `date -d` read them back.
events() {
    khal list --day-format '' --format "$FMT" "$@" 2>/dev/null
}

# ── Bar text ──────────────────────────────────────────────────────────────
# `now eod` is what is running plus what is still to come today, in start
# order. Keep the first of each.
ongoing_title="" ongoing_end="" next_title="" next_time="" next_start=0
while IFS='|' read -r sd st ed et title; do
    [ -n "$st" ] || continue # all-day: tooltip only
    start=$(date -d "$sd $st" +%s)
    if [ "$start" -le "$now" ]; then
        if [ -z "$ongoing_title" ]; then
            ongoing_title=$title
            ongoing_end=$et
            [ "$ed" = "$today" ] || ongoing_end="$ed $et"
        fi
    elif [ -z "$next_title" ]; then
        next_title=$title
        next_time=$st
        next_start=$start
    fi
done < <(events now eod)

text=$ICON
class=""
if [ -n "$next_title" ] && [ $((next_start - now)) -le $((SOON_MIN * 60)) ]; then
    # Rounded up, so it never reads "in 0m" while there is still time.
    text="$ICON in $(((next_start - now + 59) / 60))m $next_title"
    class=soon
elif [ -n "$ongoing_title" ]; then
    text="$ICON $ongoing_title until $ongoing_end"
    class=now
elif [ -n "$next_title" ]; then
    text="$ICON $next_time $next_title"
fi

# ── Tooltip ───────────────────────────────────────────────────────────────
agenda() {
    local sd st ed et title
    events "$@" | while IFS='|' read -r sd st ed et title; do
        if [ -z "$st" ]; then
            printf 'all day        %s\n' "$title"
        else
            printf '%s – %s  %s\n' "$st" "$et" "$title"
        fi
    done
}

today_agenda=$(agenda today eod)
tomorrow_agenda=$(agenda tomorrow tomorrow)

# waybar renders both text and tooltip as Pango markup, so event titles are
# escaped (@html) and only the headings carry tags.
jq -cn \
    --arg text "$text" \
    --arg class "$class" \
    --arg today "${today_agenda:-nothing scheduled}" \
    --arg tomorrow "${tomorrow_agenda:-nothing scheduled}" \
    '{
        text: ($text | @html),
        class: $class,
        tooltip: ("<b>Today</b>\n" + ($today | @html)
                  + "\n\n<b>Tomorrow</b>\n" + ($tomorrow | @html))
     }'
