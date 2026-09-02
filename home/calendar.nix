# Google Calendar on the desktop. vdirsyncer mirrors one Google account into a
# local vdir on a timer, khal reads that, and dotfiles/waybar/calendar.sh puts
# the next event in the bar. Imported by hosts/nixos/home.nix. A host that does
# not import this still installs the waybar script, which exits quietly when
# khal is absent, so the bar module simply does not appear there.
#
# Three files live outside the repo, all under ~/.config/vdirsyncer/ next to
# the config this module generates. docs/google-calendar.md walks through them:
#
#   google-client-id, google-client-secret
#       The OAuth client from Google Cloud Console, made by hand once. Read at
#       sync time through client_id.fetch / client_secret.fetch, so neither
#       lands in the nix store.
#   google-calendar.token
#       Written by the first `vdirsyncer discover calendar_google`, which is
#       the interactive browser login. Per host — the token is not portable,
#       so a second host that imports this repeats that one step.
#
# Naming, because vdirsyncer's messages use it: home-manager calls the pair
# calendar_google (account name with a calendar_ prefix), with the remote as
# side "a" and the local vdir as side "b". That is what "from a" and
# "remote wins" below refer to.

{ config, pkgs, lib, ... }:

let
  vdirsyncerDir = "${config.xdg.configHome}/vdirsyncer";
in
{
  # calendar.sh builds its JSON with it. home/common.nix ships yq, not jq.
  home.packages = [ pkgs.jq ];

  accounts.calendar = {
    # Relative to $HOME; each account gets a subdirectory.
    basePath = ".local/share/calendars";

    accounts.google = {
      remote.type = "google_calendar";

      vdirsyncer = {
        enable = true;
        tokenFile = "${vdirsyncerDir}/google-calendar.token";
        clientIdCommand = [ "cat" "${vdirsyncerDir}/google-client-id" ];
        clientSecretCommand = [ "cat" "${vdirsyncerDir}/google-client-secret" ];

        # Every calendar the account exposes over CalDAV. Which ones that is
        # gets decided on Google's side, at
        # https://calendar.google.com/calendar/syncselect — untick the
        # birthdays and holidays feeds there if they clutter the bar.
        collections = [ "from a" ];

        # Google is the source of truth. Edits made in ikhal still sync up;
        # this only decides a same-item conflict.
        conflictResolution = "remote wins";

        # No timeRange, deliberately. With start/end dates vdirsyncer switches
        # to a filtered CalDAV query, and Google answers that with entries for
        # recurrence splits (hrefs ending in _R<date>) that do not exist as
        # items, so the sync dies on a 404 partway through the main calendar
        # (pimutils/vdirsyncer#1007). The plain listing has no such problem;
        # the price is mirroring the whole history, which is small.
      };

      khal = {
        enable = true;
        # One khal calendar per synced Google calendar, named after its
        # directory under basePath.
        type = "discover";
      };
    };
  };

  programs.vdirsyncer.enable = true;

  # `vdirsyncer metasync && vdirsyncer sync` on a user timer. Both fail, and
  # the unit logs it, until the first `discover` has run — see the doc.
  services.vdirsyncer = {
    enable = true;
    frequency = "*:0/15";
  };

  programs.khal = {
    enable = true;
    # Not cosmetic: calendar.sh parses khal's output with these formats and
    # feeds the result to `date -d`, so they must stay machine-readable.
    locale = {
      dateformat = "%Y-%m-%d";
      longdateformat = "%Y-%m-%d";
      timeformat = "%H:%M";
      datetimeformat = "%Y-%m-%d %H:%M";
      longdatetimeformat = "%Y-%m-%d %H:%M";
      firstweekday = 0; # Monday
    };
  };
}
