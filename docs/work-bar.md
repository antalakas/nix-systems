# Pull requests and Linear in the bar

Two waybar modules next to the calendar, built the same way: a script polled
every five minutes, a count in the bar, the details only in the tooltip, and a
badge for what changed since you last looked. `dotfiles/waybar/prs.sh` and
`dotfiles/waybar/linear.sh`; both are installed by `hosts/nixos/home.nix`.

Neither module appears until its credential is in place, so a host without
one simply has no such module. Both credentials are per host and by hand.

## Prerequisites

**Pull requests: `gh` logged in.**

```bash
gh auth status || gh auth login
```

Choose GitHub.com, HTTPS, and log in with the browser. The account needs
read access to `TileDB-Inc/tile-ai`, which is the repository the module
watches (`REPO` at the top of `prs.sh`). The script ignores `GH_TOKEN` and
`GITHUB_TOKEN` from the environment on purpose: the shell exports the
sandbox's narrow token under that name, and gh would otherwise prefer it
to the stored login. So what counts is the keyring entry `gh auth status`
lists, not the environment one. To check that one on its own:

```bash
env -u GH_TOKEN gh repo view TileDB-Inc/tile-ai
```

If that fails with "Could not resolve to a Repository" while the account is
a member of the organisation, the organisation enforces SAML single
sign-on and the CLI's token has not been authorised for it: on github.com,
Settings, Applications, Authorized OAuth Apps, GitHub CLI, Configure SSO,
authorise for TileDB-Inc.

**Linear: a personal API key.** In Linear, Settings, then Security & access,
then Personal API keys, create one, and:

```bash
mkdir -p ~/.config/linear
printf '%s' 'lin_api_...' > ~/.config/linear/api-key
chmod 600 ~/.config/linear/api-key
```

The team is `ENG` (`TEAM` at the top of `linear.sh`; several keys may be
listed, comma-separated). An issue counts when it belongs to one of those
teams or sits in a project one of them has access to, since projects are
shared across teams and the issues inside them often carry another team's
prefix. The key sees whatever your Linear account sees.

Then restart waybar, as after any config change:

```bash
pkill waybar
waybar --config ~/.config/waybar/config.json --style ~/.config/waybar/style.css &
```

## What they show

**Pull requests**, `  9 +2`: open PRs in the repository, and how many
opened or changed since you last looked. Blue when a review is requested from
you, bold while something is unseen, dimmed italic when the last fetch failed
and the numbers are from the cache. The tooltip lists every open PR, the ones
waiting for your review first, then newest change first:

| column | meaning |
|---|---|
| `●` / `↻` | opened / updated since you last looked (the line is bold too) |
| `R` | review requested from you |
| `D` | draft |
| `✓` `✗` `…` | checks passed / failed / still running; blank when there are none |

**Linear**, `  14 +3`: issues in the team that changed in the window, plus
project updates posted in it, and how many of those are unseen. Purple when a
project update landed, bold while something is unseen. The tooltip is grouped
by project, with a one-line summary per project (done, started, new,
cancelled, updated), the update's health and first line under it, then the
issues:

| marker | meaning |
|---|---|
| `✓` | completed in the window |
| `▶` | started in the window |
| `●` | created in the window |
| `✗` | cancelled in the window |
| `↻` | changed in some other way, a comment or an edit |

The window is "since you last looked", but at least today and at most a week.

## Clicks

- **Left click** opens a fuzzel picker over the items. Pick one and it opens
  in the browser. The first entry opens the full list: the repository's pull
  requests, or the team in Linear.
- **Right click** marks everything seen. The badge drops to zero and the bar
  redraws at once; the lists are unchanged. The last-look time is per module,
  in `~/.cache/waybar/prs.seen` and `linear.seen`. The very first run has no
  last look, so everything counts as unseen; one right click settles it.

## Behaviour and troubleshooting

- Network is touched at most once a minute per module, on the five-minute
  poll and on a right click when the cache is older than that. Fuzzel reads
  from the cache, so it opens instantly.
- If a fetch fails, the module keeps showing the cached data, dimmed, with
  the fetch time in the tooltip.
- Linear with no cache at all shows `!` and the API's error message in the
  tooltip. A wrong key gives an authentication error; a query rejected by the
  API names the field. `~/.config/waybar/linear.sh --debug` makes one live
  request and prints the window, any errors, the counts and the first few
  issues it got, which is the thing to look at when the count seems wrong.
- Pull requests with no cache shows `!` and gh's message in the tooltip, as
  long as `gh auth token` works; a wrong repository name, an organisation
  that has not authorised the token, or no network all land there. Run
  `~/.config/waybar/prs.sh` in a terminal for the same JSON.
- To watch another repository or team, change `REPO` or `TEAM` at the top of
  the script. Both also read `WAYBAR_PRS_REPO` and `WAYBAR_LINEAR_TEAM` from
  the environment, which is what the tests in this repo's history used.
