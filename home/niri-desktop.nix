# The user half of a niri session: launcher, bar, notifications, wallpaper and
# the fonts the rest of the config assumes. modules/desktop.nix is the system
# half — that one installs the compositor and the session; this one dresses it.
#
# Written when `scribe` was added, and imported only by that host so far. The
# laptop still carries its own inline copies of everything here in
# hosts/nixos/home.nix, so the two can drift, and the same caveat applies as in
# modules/desktop.nix: migrating it is a separate job. What is *not* here is
# the laptop's application set — Slack, Cursor, Logseq, Brave profiles, Zoom,
# Teams — because that is a working environment rather than a desktop.
#
# Deliberately not host-agnostic in one place, and it is called out below:
# mako's `output` pin.

{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    swaybg # wallpaper; the niri profiles spawn it at startup
    libnotify # notify-send, for anything that wants to raise a notification
    papirus-icon-theme
  ];

  # ─────────────────────────────────────────────────────────────
  # Launcher (Mod+D)
  # ─────────────────────────────────────────────────────────────
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # Iosevka Nerd Font comes from modules/desktop.nix's fonts.packages. A
        # host that imports this without that one gets a fallback face and no
        # icons.
        font = "Iosevka Nerd Font:size=12";
        prompt = "❯ ";
        icon-theme = "Adwaita";
        icons-enabled = true;
        terminal = "alacritty -e";
        layer = "overlay";
        width = 50;
        horizontal-pad = 20;
        vertical-pad = 15;
        inner-pad = 10;
        lines = 12;
      };
      colors = {
        background = "2b303bdd";
        text = "ffffffee";
        match = "7fc8ffff";
        selection = "64727dff";
        selection-text = "ffffffff";
        selection-match = "7fc8ffff";
        border = "64727dff";
      };
      border = {
        width = 2;
        radius = 12;
      };
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Bar
  # ─────────────────────────────────────────────────────────────
  # Config and style are files rather than nix, below: the bar has a custom
  # niri-workspaces module backed by a shell script, which does not survive
  # being expressed as an attrset.
  #
  # The niri profiles start it with an explicit --config/--style and a two
  # second delay, so that the environment import ahead of it has landed. Its
  # `battery` module needs services.upower on the system side, which
  # hosts/scribe/default.nix enables and a desktop would not.
  programs.waybar.enable = true;

  # ─────────────────────────────────────────────────────────────
  # Notifications
  # ─────────────────────────────────────────────────────────────
  services.mako = {
    enable = true;
    settings = {
      background-color = "#1e1e2e";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      border-size = 2;
      border-radius = 10;
      padding = "15";
      margin = "10";

      width = 500;
      height = 200;

      # No `output` pin, unlike hosts/nixos/home.nix, which sends notifications
      # to eDP-1 only so they never land on a monitor someone else can see.
      # That is a multi-head privacy setting; on a single-panel machine it
      # would name the only output there is. Add it back on any host that grows
      # an external display.

      font = "sans-serif 16";
      markup = true;
      format = "<b>%s</b>\\n%b";

      default-timeout = 5000;

      icons = true;
      max-icon-size = 64;
      icon-path = "${pkgs.papirus-icon-theme}/share/icons/Papirus";
    };

    extraConfig = ''
      [urgency=low]
      border-color=#89dceb

      [urgency=high]
      border-color=#f38ba8
    '';
  };

  # ─────────────────────────────────────────────────────────────
  # Theme and directories
  # ─────────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
  };

  # ~/Pictures in particular, which the niri screenshot binds write into —
  # `screenshot-path` in the profiles points at ~/Pictures/Screenshots and niri
  # will not create a missing parent.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # home-manager's newer default drops the XDG_*_DIR session variables,
    # because they go stale whenever the file changes. Pinned explicitly rather
    # than inherited from home.stateVersion, so this does not change meaning
    # when a host is installed from a different release.
    setSessionVariables = false;
  };

  # ─────────────────────────────────────────────────────────────
  # System monitor
  # ─────────────────────────────────────────────────────────────
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "Default";
      theme_background = true;
      truecolor = true;
      rounded_corners = true;
      graph_symbol = "braille";
      shown_boxes = "cpu mem net proc";
      update_ms = 2000;
      proc_sorting = "cpu lazy";
      proc_colors = true;
      proc_gradient = true;
      proc_mem_bytes = true;
      proc_cpu_graphs = true;
      cpu_invert_lower = true;
      show_uptime = true;
      show_cpu_watts = true;
      check_temp = true;
      show_coretemp = true;
      temp_scale = "celsius";
      show_cpu_freq = true;
      clock_format = "%X";
      mem_graphs = true;
      show_swap = true;
      swap_disk = true;
      show_disks = true;
      only_physical = true;
      use_fstab = true;
      show_io_stat = true;
      net_auto = true;
      net_sync = true;
      show_battery = true;
      show_battery_watts = true;
      log_level = "WARNING";
      gpu_mirror_graph = true;
    };
  };

  # ─────────────────────────────────────────────────────────────
  # Files with no home-manager module
  # ─────────────────────────────────────────────────────────────
  # The niri config itself is deliberately absent: which profile a host runs is
  # per-host, so hosts/<host>/home.nix installs it. Everything here is shared.
  home.file = {
    ".config/waybar/config.json".source = ../dotfiles/waybar/config.json;
    ".config/waybar/style.css".source = ../dotfiles/waybar/style.css;
    ".config/waybar/niri-workspaces.sh" = {
      source = ../dotfiles/waybar/niri-workspaces.sh;
      executable = true;
    };
    # The bar's calendar module. It needs khal from home/calendar.nix to show
    # anything and hides itself otherwise, so a host that wants it imports
    # that module too (and does the OAuth login described in
    # docs/google-calendar.md); a host that does not is unaffected.
    ".config/waybar/calendar.sh" = {
      source = ../dotfiles/waybar/calendar.sh;
      executable = true;
    };
    # Same arrangement for the pull-request and Linear modules: they hide
    # themselves until `gh auth login` has been run, respectively until
    # ~/.config/linear/api-key exists (docs/work-bar.md).
    ".config/waybar/prs.sh" = {
      source = ../dotfiles/waybar/prs.sh;
      executable = true;
    };
    ".config/waybar/linear.sh" = {
      source = ../dotfiles/waybar/linear.sh;
      executable = true;
    };

    ".config/wallpapers/microgpt.png".source = ../dotfiles/wallpapers/microgpt.png;

    ".local/share/fonts/Pragmasevka".source = ../fonts/Pragmasevka;
  };

  # Pragmasevka lands in ~/.local/share/fonts as a store symlink, which
  # fontconfig does not notice on its own.
  home.activation.refreshFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/.local/share/fonts/Pragmasevka" ]; then
      $DRY_RUN_CMD ${pkgs.fontconfig}/bin/fc-cache -f
    fi
  '';
}
