# Google Calendar in the bar

The waybar calendar module (`dotfiles/waybar/calendar.sh`) shows the next
event of the day and, in its tooltip, today's and tomorrow's agenda. It turns
amber when an event starts within ten minutes and green while one is running.
Left click opens `ikhal`, right click opens Google Calendar in the browser.

It reads a local mirror of one Google account, kept in sync by vdirsyncer
every 15 minutes and read by khal. `home/calendar.nix` configures all of
that; `hosts/nixos/home.nix` imports it. What the module cannot do is log in
to Google for you. That is a one-off by hand, described here.

Paths below assume the laptop (user `andreas`). The token is per host, so a
second host that imports `home/calendar.nix` repeats §3 there.

## 1. An OAuth client in Google Cloud

vdirsyncer talks to Google's CalDAV endpoint with OAuth, and Google only
issues OAuth credentials to a registered "app". You register one, for
yourself. Do this while signed in as the Google account whose calendar you
want; it is free and needs no billing account.

1. Open <https://console.cloud.google.com/> and create a project. The name
   is only for you — `khal` is fine.
2. **APIs & Services → Library**, search for **CalDAV API** and enable it.
   Not the "Google Calendar API": vdirsyncer speaks CalDAV, and Google's
   CalDAV endpoint checks for this one specifically.
3. **APIs & Services → OAuth consent screen** (Google has been renaming this
   to "Google Auth Platform"; it is the same page). Fill in the app name and
   the support and developer e-mail addresses — your own. Audience:
   - a gmail.com account has to pick **External**;
   - a Google Workspace account can pick **Internal**, which skips every
     warning and caveat below.
4. Still on that page, under **Publishing status**, click **Publish app** and
   confirm. Leave it at "Testing" and Google expires the refresh token after
   seven days, which means a browser login every week. A published app that
   has never gone through Google's verification still works for its own
   developer; the only consequence is the "unverified app" interstitial at
   login in §3. You do not need to submit it for verification.
5. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
   Application type **Desktop app**, any name. Copy the **Client ID** and the
   **Client secret**. The secret is shown once; if you lose it, make a new
   client.

Then tell Google which calendars to expose over CalDAV, at
<https://calendar.google.com/calendar/syncselect>. By default that is every
calendar in the account, including birthdays and holidays. Untick anything
you do not want in the bar; this is the only place to choose.

## 2. The credentials on the laptop

Two files, read by vdirsyncer at every sync. They are outside the repo on
purpose, so they never land in git or in the nix store.

```bash
mkdir -p ~/.config/vdirsyncer
printf '%s' 'PASTE-CLIENT-ID' > ~/.config/vdirsyncer/google-client-id
printf '%s' 'PASTE-CLIENT-SECRET' > ~/.config/vdirsyncer/google-client-secret
chmod 600 ~/.config/vdirsyncer/google-client-*
```

`printf '%s'` rather than `echo`, so there is no trailing newline in the value
vdirsyncer sends. Then rebuild:

```bash
nrs
```

That installs khal and vdirsyncer, writes `~/.config/vdirsyncer/config` and
`~/.config/khal/config`, adds the waybar module and starts the sync timer.
The timer fails on every tick until the next section is done; that is
expected, and `journalctl --user -u vdirsyncer` will say so.

## 3. First login and sync

```bash
vdirsyncer discover calendar_google
```

`calendar_google` is the pair name home-manager derives from the account
(`accounts.calendar.accounts.google`). vdirsyncer prints an
`accounts.google.com` URL and tries to open it in the browser; if nothing
opens, paste it yourself. In the browser:

1. Choose the right Google account.
2. On "Google hasn't verified this app", click **Advanced**, then
   **Go to ‹app name› (unsafe)**. That is the unverified-app interstitial from §1
   and it is about you trusting your own client.
3. Allow calendar access.

Google redirects to a `127.0.0.1` address that vdirsyncer is listening on
for exactly this; the page will say something like "Done, you may close
this". Back in the terminal vdirsyncer lists the calendars it found and asks,
one by one, whether to create the local copy — answer `y`. The token is now
in `~/.config/vdirsyncer/google-calendar.token`.

Then the first real sync, and a check:

```bash
vdirsyncer sync
khal list today 7d
systemctl --user status vdirsyncer.timer   # start it if it is not active
```

Waybar polls the script once a minute but only reads its config at start,
so restart it once:

```bash
pkill waybar
waybar --config ~/.config/waybar/config.json --style ~/.config/waybar/style.css &
```

## Day to day

- Sync runs every 15 minutes; `systemctl --user start vdirsyncer` forces one.
- `ikhal` is the interactive view. `khal new` needs `-a <calendar>` because
  no default calendar is set: with `type = "discover"` the khal calendars
  are named after the directories under `~/.local/share/calendars/google/`,
  and those names are Google's calendar ids. `khal printcalendars` lists them.
- Edits made in ikhal sync back to Google. On a conflict Google wins.
- The whole calendar is mirrored, not a window of it. `home/calendar.nix`
  explains why there is no `timeRange`: with one set, Google lists
  recurrence-split entries that then 404, and the sync aborts on the first.
- If the token is revoked or expires (see §1 step 4), sync starts failing
  with an OAuth error. Delete `~/.config/vdirsyncer/google-calendar.token`
  and repeat §3.
- A second Google account is a second block under
  `accounts.calendar.accounts` in `home/calendar.nix`, its own client-id and
  client-secret files, and its own `discover` run. The bar script does not
  care how many calendars khal has.
